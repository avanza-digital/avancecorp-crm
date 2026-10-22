#!/usr/bin/env bash
# DERIVAS del bloque 2.13 — la migración (y su reversa) se niegan si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una DERIVA rompe el catálogo ANTES:
# lo que se prueba aquí es el PREFLIGHT. La migración parchea por ancla única el disparador de disponibilidad que deja el 2.8 y crea
# una pieza que repite el veredicto del verificador: sin preflight, un cambio hecho a mano en el disparador, en la pieza del 2.8, en
# los disparadores de tabla, en una pieza de la que depende la regla (la forma canónica, la clave del candado, el rol, el verificador),
# en la ficha cuya edición protege, en el CHECK del alternativo o en los trinquetes que barre se pisaría o se daría por bueno sin que
# nadie lo viera. Con cada deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier
# error— y dejar todo (disparador, pieza del 2.8, núcleo, forma canónica, ficha, disparadores de tabla: definición, dueño, ACL,
# comentario) EXACTAMENTE como estaba.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Después, un MUTANTE DEL PREFLIGHT: sin comparar la
# pieza del 2.8, un cambio hecho a mano en ella se daría por bueno (la migración entra).
#
# Al final, las DERIVAS DE LA REVERSA: aplicar → un cambio posterior → la reversa tiene que abortar sin rastro (y el control: sin cambio,
# entra y devuelve el disparador del 2.8 sin la pieza). Otro LLAMADOR de la pieza (una función PL/pgSQL, en minúsculas o en
# MAYÚSCULAS; una vista; un trabajo programado `cron.job`; un comentario que la nombra —falso positivo conservador—) también la hace
# abortar; y el LÍMITE declarado: una llamada construida en tiempo de ejecución no se ve (se mide: la reversa entra). Y dos MUTANTES DE LA
# REVERSA: RM1 sin su comprobación de llamadores (el llamador PL/pgSQL se cuela) y RM2 sin la comprobación de la ficha del disparador
# en su preflight (el GRANT posterior aborta igual en su postflight: defensa en dos capas).
#
# El cambio de dueño solo lo puede hacer un superusuario: esas derivas corren enteras con EJECUTAR_SQL_ADMIN (el mismo ejecutor como
# supabase_admin; la migración fija el dueño de la pieza en postgres, así que su postflight vale igual).
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/alternativo-cliente-no-toma-lead/derivas.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (derivas de cambio de dueño)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/alternativo-cliente-no-toma-lead
MIG="$(ls supabase/migrations/*_crm_alternativo_cliente_no_toma_lead.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_alternativo_cliente_no_toma_lead.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

D='private.trg_leads_disponibilidad_atomica()'
P='private.juicio_lead_vivo_por_numero(text,uuid)'
P28='private.juicio_cliente_convertido(text,text,text,uuid)'

ejecuta() { # ejecuta <ejecutor> <archivo.sql> → <archivo>.salida.txt (stdin cerrado: el ejecutor usa `docker exec -i`)
  local codigo
  # shellcheck disable=SC2086  # el ejecutor es un comando con sus argumentos
  $1 "$2" > "${2%.sql}.salida.txt" 2>&1 < /dev/null
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($2). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}
veredicto() { grep -Eo '(DERIVA|REVERSA CON DERIVA) (VERDE|ROJO)' "$1" | head -n 1 | grep -Eo '(VERDE|ROJO)$'; }
aborto() { grep -m 1 -E '^la (migración|reversa) (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0

echo "0. Control: sin deriva, la migración entra por el mismo envoltorio"
: > "$TMP/d0.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d0.deriva.sql" > "$TMP/d0.sql" || exit 1
ejecuta "$EJECUTAR_SQL" "$TMP/d0.sql"
if [[ "$(veredicto "$TMP/d0.salida.txt")" == "VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d0.salida.txt"; then
  echo "  ✓ control → $(aborto "$TMP/d0.salida.txt")"
else
  echo "  ✗ control → la migración no entró sin deriva: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d0.salida.txt" | cut -c1-230)"
  fallos=$((fallos + 1))
fi

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto del preflight que debe abortar> [admin]
  local salida ejecutor="$EJECUTAR_SQL"
  n=$((n + 1))
  salida="$TMP/d$n.salida.txt"
  [[ "${4:-}" == "admin" ]] && ejecutor="$EJECUTAR_SQL_ADMIN"
  echo "$n. Deriva: $1"
  printf '%s\n' "$2" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "$3" > "$TMP/d$n.sql" || exit 1
  ejecuta "$ejecutor" "$TMP/d$n.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "VERDE" ]]; then
    echo "  ✓ el preflight se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
cambia_cuerpo() { # cambia_cuerpo <firma> <texto que aparece en el cuerpo> → SQL que recrea la función con ese texto + «.»
  printf "do \$d\$ begin execute replace(pg_get_functiondef('%s'::regprocedure), \$t\$%s\$t\$, \$t\$%s.\$t\$); end \$d\$;" "$1" "$2" "$2"
}

APLICADA='esta migración ya está aplicada'
DISP_CUERPO='no es el que deja el bloque 2.8 en su ronda 4'
DISP_FICHA='la ficha del disparador no es la auditada'
DISP_COMENTARIO='el comentario del disparador no es el que deja el 2.8'
PIEZA28='la pieza private.juicio_cliente_convertido no es la que deja el 2.8'
DISPARADORES='los disparadores de tabla trg_leads_00_disponibilidad_insert/_update no son los auditados'
PIEZAS='cambió una pieza de la que depende la regla o la ficha cuya edición protege'
RESTRICCION='cambió o falta la restricción leads_telefono_alternativo_formato'
TRINQUETES='los private.assert_*() que barre la migración no son los auditados'

# Ya aplicada: la propia migración antes (la línea se sustituye por ella) o una función con el nombre de la pieza (otra firma).
deriva "la migración ya estaba aplicada" "-- @@MIGRACION@@" "$APLICADA"
deriva "ya existe una función con el nombre de la pieza (otra firma)" "create function private.juicio_lead_vivo_por_numero(text) returns jsonb language sql stable as \$f\$ select null::jsonb \$f\$;" "$APLICADA"
# El disparador que deja el 2.8: otro cuerpo; otro SET; INVOKER (las tres cambian su definición); su ACL; su comentario.
deriva "el disparador tenía otro cuerpo" "$(cambia_cuerpo "$D" 'Acceso CRM revocado')" "$DISP_CUERPO"
deriva "el disparador traía otro SET" "alter function $D set statement_timeout = '30s';" "$DISP_CUERPO"
deriva "el disparador había pasado a security invoker" "alter function $D security invoker;" "$DISP_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el disparador" "grant execute on function $D to authenticated;" "$DISP_FICHA"
deriva "el disparador traía otro comentario" "comment on function $D is 'comentario ajeno';" "$DISP_COMENTARIO"
# La pieza del 2.8 (su veredicto manda sobre el de esta regla): otro cuerpo, su ACL, su comentario.
deriva "la pieza del 2.8 tenía otro cuerpo" "$(cambia_cuerpo "$P28" 'Si ningún teléfono casa, el DNI (D-27)')" "$PIEZA28"
deriva "authenticated ya tenía EXECUTE sobre la pieza del 2.8" "grant execute on function $P28 to authenticated;" "$PIEZA28"
deriva "la pieza del 2.8 traía otro comentario" "comment on function $P28 is 'comentario ajeno';" "$PIEZA28"
# Los disparadores de tabla: el de la edición con otra lista (sin el alternativo) o deshabilitado.
deriva "el disparador de la edición tenía otra lista de columnas (sin el alternativo)" "create or replace trigger trg_leads_00_disponibilidad_update before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte on crm.leads for each row execute function $D;" "$DISPARADORES"
deriva "el disparador de la edición estaba deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_update;" "$DISPARADORES"
# Las piezas de las que depende la regla y la ficha cuya edición protege: definición (cuerpo y atributos), dueño y ACL.
deriva "la forma canónica (canonizar_contacto) tenía otro cuerpo" "$(cambia_cuerpo 'private.canonizar_contacto(text)' 'UN FIJO EXIGE MARCA')" "$PIEZAS"
deriva "authenticated ya tenía EXECUTE sobre canonizar_contacto" "grant execute on function private.canonizar_contacto(text) to authenticated;" "$PIEZAS"
deriva "canonizar_contacto había cambiado de dueño (lo hace un superusuario)" "alter function private.canonizar_contacto(text) owner to supabase_admin;" "$PIEZAS" admin
deriva "la clave del candado (bloquear_contactos_lead) traía otro SET" "alter function private.bloquear_contactos_lead(text[],text[]) set statement_timeout = '30s';" "$PIEZAS"
deriva "normalizar_telefono traía otra regla" "do \$d\$ begin execute replace(pg_get_functiondef('private.normalizar_telefono(text)'::regprocedure), \$t\$then '+51' || regexp_replace\$t\$, \$t\$then '+510' || regexp_replace\$t\$); end \$d\$;" "$PIEZAS"
deriva "private.rol_crm había pasado a STRICT" "alter function private.rol_crm(uuid) strict;" "$PIEZAS"
deriva "el verificador tenía otro cuerpo" "$(cambia_cuerpo 'private.verificar_disponibilidad_lead_impl(text,text,uuid)' 'Un solo lead TOTAL por persona')" "$PIEZAS"
deriva "la ficha (crm.editar_lead_fn) tenía otro cuerpo" "$(cambia_cuerpo 'crm.editar_lead_fn(uuid,jsonb)' 'nunca un «ok» sin escribir')" "$PIEZAS"
deriva "anon ya tenía EXECUTE sobre crm.editar_lead_documento_fn" "grant execute on function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text) to anon;" "$PIEZAS"
# El CHECK del alternativo (la premisa de la forma canónica): quitado, cambiado o sin validar.
deriva "el CHECK del formato del alternativo no estaba" "alter table crm.leads drop constraint leads_telefono_alternativo_formato;" "$RESTRICCION"
deriva "el CHECK del formato del alternativo era otro" "alter table crm.leads drop constraint leads_telefono_alternativo_formato; alter table crm.leads add constraint leads_telefono_alternativo_formato check (telefono_alternativo is null or telefono_alternativo ~ '^\+[0-9]{8,15}\$') not valid; alter table crm.leads validate constraint leads_telefono_alternativo_formato;" "$RESTRICCION"
deriva "el CHECK del formato del alternativo estaba sin validar" "alter table crm.leads drop constraint leads_telefono_alternativo_formato; alter table crm.leads add constraint leads_telefono_alternativo_formato check (((telefono_alternativo IS NULL) OR (telefono_alternativo ~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})\$'::text))) not valid;" "$RESTRICCION"
# El inventario y las definiciones de los trinquetes que se barren (antes del primer barrido): uno distinto, uno más, uno menos.
deriva "un trinquete tenía otra definición" "alter function private.assert_cola_v3() set statement_timeout = '31s';" "$TRINQUETES"
deriva "había un trinquete más" "create function private.assert_ensayo_deriva_2_13() returns void language sql as \$f\$ select \$f\$;" "$TRINQUETES"
deriva "faltaba un trinquete (renombrado)" "alter function private.assert_cola_v3() rename to zz_ensayo_deriva_2_13_cola_v3;" "$TRINQUETES"
# Reselle C1 (13/10): el censo fija los 29 que ningún bloque toca y de private.assert_gestion_diaria_resultado() (que re-sella el 2.16) solo
# exige que exista. Faltando él ⇒ se niega; re-sellado (otra definición, como lo deja el 2.16) ⇒ entra (control abajo).
deriva "faltaba el trinquete que re-sella el 2.16 (assert_gestion_diaria_resultado, borrado)" "drop function private.assert_gestion_diaria_resultado();" "$TRINQUETES"
deriva "faltaba el trinquete que re-sella el 2.16 (renombrado)" "alter function private.assert_gestion_diaria_resultado() rename to zz_ensayo_deriva_2_13_gdr;" "$TRINQUETES"
deriva "otro de los 29 trinquetes fijados tenía otra definición (assert_sla_nucleo)" "alter function private.assert_sla_nucleo() set statement_timeout = '31s';" "$TRINQUETES"

# ── Control del reselle C1: el trinquete que re-sella el 2.16 puede tener OTRA definición y la migración entra igual ──────────────────
echo "RS. Control del reselle C1: private.assert_gestion_diaria_resultado() re-sellado (otra definición, como lo deja el 2.16) → la migración ENTRA"
printf '%s\n' "alter function private.assert_gestion_diaria_resultado() set statement_timeout = '31s';" > "$TMP/rs.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/rs.deriva.sql" > "$TMP/rs.sql" || exit 1
ejecuta "$EJECUTAR_SQL" "$TMP/rs.sql"
if grep -q 'DERIVA_INSTALADA' "$TMP/rs.salida.txt" && [[ "$(veredicto "$TMP/rs.salida.txt")" == "VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/rs.salida.txt"; then
  echo "  ✓ entra con el trinquete re-sellado → $(aborto "$TMP/rs.salida.txt")"
else
  echo "  ✗ la migración NO entró con el trinquete re-sellado: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/rs.salida.txt" | cut -c1-230)"; fallos=$((fallos + 1))
fi

# ── El MUTANTE DEL PREFLIGHT: sin comparar la pieza del 2.8, un cambio hecho a mano en ella se da por bueno ──────────────────────
echo "MP. Mutante del preflight SIN la comparación de la pieza del 2.8: la pieza cambiada a mano tiene que COLARSE"
if python3 -I - "$MIG" "$TMP/mig-sin-pieza28.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- La pieza del 2.8 (su veredicto manda sobre el de esta regla), exacta: cuerpo, definición, ficha y comentario.\n"
fin = "  -- Los dos disparadores de tabla de disponibilidad, exactos y habilitados (el de la edición mira ya el alternativo: 2.8).\n"
if sql.count(ini) != 1 or sql.count(fin) != 1:
    sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE')
i = sql.index(ini); j = sql.index(fin)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "$(cambia_cuerpo "$P28" 'Si ningún teléfono casa, el DNI (D-27)')" > "$TMP/mp.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-pieza28.sql" --deriva "$TMP/mp.deriva.sql" --espera "$PIEZA28" > "$TMP/mp.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/mp.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp.salida.txt" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp.salida.txt")" == "ROJO" ]] && grep -q '^la migración NO abortó' "$TMP/mp.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comparación, la pieza del 2.8 cambiada a mano se dio por buena y la migración entró. Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/mp.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del preflight"; fallos=$((fallos + 1))
fi

# ══ DERIVAS DE LA REVERSA ════════════════════════════════════════════════════════════════════════════════════════════════════
nr=0
reversa_deriva() { # reversa_deriva <nombre> <sentencia(s) SQL> <texto que debe abortar | vacío = control> [admin|-] [limite]
  local archivo salida ejecutor="$EJECUTAR_SQL"
  nr=$((nr + 1))
  archivo="$TMP/r$nr.sql"; salida="$TMP/r$nr.salida.txt"
  [[ "${4:-}" == "admin" ]] && ejecutor="$EJECUTAR_SQL_ADMIN"
  echo "R$nr. Reversa con deriva: $1"
  printf '%s\n' "$2" > "$TMP/r$nr.deriva.sql"
  if [[ -n "$3" ]]; then
    node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/r$nr.deriva.sql" --espera "$3" > "$archivo" || exit 1
  else
    node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/r$nr.deriva.sql" > "$archivo" || exit 1
  fi
  ejecuta "$ejecutor" "$archivo"
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1)); return
  fi
  if [[ "$(veredicto "$salida")" == "VERDE" ]]; then
    if [[ -n "$3" ]]; then echo "  ✓ la reversa se negó y no dejó rastro → $(aborto "$salida")"
    elif [[ "${5:-}" == "limite" ]]; then echo "  ✓ límite medido: no se detecta; la reversa entra y devuelve el disparador del 2.8 (el llamador dinámico queda roto)"
    else echo "  ✓ control: sin deriva, la reversa entra y devuelve el disparador del 2.8 sin la pieza"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_PIEZA='la pieza private.juicio_lead_vivo_por_numero no es la que dejó la migración'
REV_DISP_DEF='el disparador no tiene exactamente la definición que dejó la migración'
REV_DISP_FICHA='la ficha o el comentario del disparador no son los que dejó la migración'
REV_DISPARADORES='los disparadores de tabla de disponibilidad no son los que dejó la migración'
REV_LLAMADORES='posible llamador de la pieza private.juicio_lead_vivo_por_numero'
LLAMADOR_PLPGSQL="create function private.ensayo_llamador_2_13() returns jsonb language plpgsql stable set search_path = '' as \$f\$ begin return private.juicio_lead_vivo_por_numero(null, null); end \$f\$;"
reversa_deriva "control (sin deriva): la reversa entra y devuelve el disparador del 2.8 sin la pieza" "" ""
reversa_deriva "un SET statement_timeout añadido al disparador" "alter function $D set statement_timeout = '30s';" "$REV_DISP_DEF"
reversa_deriva "un GRANT EXECUTE a authenticated sobre el disparador" "grant execute on function $D to authenticated;" "$REV_DISP_FICHA"
reversa_deriva "el disparador cambió de dueño (lo hace un superusuario)" "alter function $D owner to supabase_admin;" "$REV_DISP_FICHA" admin
reversa_deriva "el comentario del disparador cambió" "comment on function $D is 'comentario ajeno';" "$REV_DISP_FICHA"
reversa_deriva "un GRANT EXECUTE a authenticated sobre la pieza" "grant execute on function $P to authenticated;" "$REV_PIEZA"
reversa_deriva "la pieza con otro cuerpo" "$(cambia_cuerpo "$P" 'Sin forma canónica no casa con nada')" "$REV_PIEZA"
reversa_deriva "el comentario de la pieza cambió" "comment on function $P is 'comentario ajeno';" "$REV_PIEZA"
reversa_deriva "el disparador de la edición deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_update;" "$REV_DISPARADORES"
reversa_deriva "otro llamador de la pieza: una función PL/pgSQL" "$LLAMADOR_PLPGSQL" "$REV_LLAMADORES"
reversa_deriva "un llamador PL/pgSQL ESTÁTICO en MAYÚSCULAS (PRIVATE.JUICIO_LEAD_VIVO_POR_NUMERO)" "create function private.ensayo_llamador_mayusculas_2_13() returns jsonb language plpgsql stable set search_path = '' as \$f\$ begin return PRIVATE.JUICIO_LEAD_VIVO_POR_NUMERO(null, null); end \$f\$;" "$REV_LLAMADORES"
reversa_deriva "otro llamador de la pieza: una vista" "create view private.ensayo_vista_2_13 as select private.juicio_lead_vivo_por_numero(null::text, null::uuid) as v;" "$REV_LLAMADORES"
# Un trabajo programado que la nombra (tabla cron.job del laboratorio). Con jobid explícito: `cron.schedule` gastaría la secuencia, que el
# rollback no devuelve.
reversa_deriva "un trabajo programado (cron.job.command) llama a la pieza" "insert into cron.job (jobid, jobname, schedule, command) values (9213001, 'ensayo-2-13-llamador-de-la-pieza', '0 3 * * *', 'select private.juicio_lead_vivo_por_numero(null, null)');" "$REV_LLAMADORES"
reversa_deriva "un comentario en otra función que la nombra (falso positivo conservador)" "create function private.ensayo_comentario_2_13() returns void language plpgsql as \$f\$ begin -- antes se llamaba a private.juicio_lead_vivo_por_numero aquí
 null; end \$f\$;" "$REV_LLAMADORES"
reversa_deriva "LÍMITE: un llamador dinámico (EXECUTE con el nombre partido) no se ve: la reversa entra" "create function private.ensayo_llamador_dinamico_2_13() returns jsonb language plpgsql stable set search_path = '' as \$f\$ declare v jsonb; begin execute 'select private.' || 'juicio_lead_vivo' || '_por_numero(null, null)' into v; return v; end \$f\$;" "" "-" limite

# ── Los MUTANTES DE LA REVERSA ───────────────────────────────────────────────────────────────────────────────────────────────
echo "RM1. Mutante de la reversa SIN su comprobación de llamadores: el llamador PL/pgSQL tiene que COLARSE (el DROP sin CASCADE no lo ve)"
if python3 -I - "$DIR/reversa.sql" "$TMP/reversa-sin-llamadores.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- Nadie más usa la pieza: otros cuerpos de función"
fin = "  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_disp)\n       is distinct from"
if sql.count(ini) != 1 or fin not in sql[sql.index(ini):]:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (llamadores)')
i = sql.index(ini); j = sql.index(fin, i)  # la primera comprobación del disparador DESPUÉS del bloque (el postflight repite el texto)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "$LLAMADOR_PLPGSQL" > "$TMP/rm1.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm1.deriva.sql" --espera "$REV_LLAMADORES" \
    --reversa-archivo "$TMP/reversa-sin-llamadores.sql" > "$TMP/rm1.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm1.sql"
  if [[ "$(veredicto "$TMP/rm1.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm1.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comprobación, la reversa borró la pieza dejando a su llamador roto. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm1.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM1"; fallos=$((fallos + 1))
fi

echo "RM2. Mutante de la reversa SIN la comprobación de la ficha del disparador en su preflight: el GRANT aborta en su POSTFLIGHT"
if python3 -I - "$DIR/reversa.sql" "$TMP/reversa-sin-ficha.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  if not exists (select 1 from pg_proc p\n                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef\n"
fin = "  if (select md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text from pg_trigger t\n        where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_00_disponibilidad_update') is distinct from 'a585ac769d92cd1f2aba0c4cf49ca83a|O'\n"
if sql.count(fin) != 1 or ini not in sql[:sql.index(fin)]:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (ficha)')
j = sql.index(fin); i = sql.rindex(ini, 0, j)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "grant execute on function $D to authenticated;" > "$TMP/rm2.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm2.deriva.sql" --espera "la ficha del disparador no es la del 2.8" \
    --reversa-archivo "$TMP/reversa-sin-ficha.sql" > "$TMP/rm2.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm2.sql"
  if [[ "$(veredicto "$TMP/rm2.salida.txt")" == "VERDE" ]]; then
    echo "  ✓ defensa en dos capas: sin la del preflight, el GRANT aborta en el postflight → $(aborto "$TMP/rm2.salida.txt")"
  else
    echo "  ✗ el GRANT no abortó en el postflight → $(aborto "$TMP/rm2.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM2"; fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight de la migración y no dejan rastro; el control entra; el mutante del preflight muere."
  echo "DERIVAS DE LA REVERSA: el control y el límite medido entran; las $((nr - 2)) derivas abortan su preflight sin rastro; RM1 muere; RM2 aborta en el postflight."
  exit 0
fi
echo "DERIVAS: $fallos fallo(s)."
exit 1
