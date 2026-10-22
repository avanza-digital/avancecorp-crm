#!/usr/bin/env bash
# DERIVAS del bloque 2.9 — la migración (y su reversa) se niegan si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una DERIVA rompe el catálogo ANTES:
# lo que se prueba aquí es el PREFLIGHT. La migración parchea por ancla única el envoltorio de identidad de la carga de bases: sin
# preflight, un cambio hecho a mano en él (o en sus llamadores, la puerta, una pieza que decide su efecto, el CHECK del formato del
# alternativo o los trinquetes que barre), u otro objeto que lo usara, se pisaría o se daría por bueno sin que nadie lo viera. Con
# cada deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar el
# envoltorio, sus dos llamadores y la puerta (definición, dueño, ACL, comentario) EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Después, los MUTANTES DEL PREFLIGHT: MP1, sin el
# inventario de los trinquetes, un trinquete de más se colaría (la migración entra: muere); MP2, sin la búsqueda de llamadores en el
# preflight, otro llamador aborta igual en el POSTFLIGHT (defensa en dos capas); MP3, sin ninguna de las dos, el llamador se cuela.
#
# Al final, las DERIVAS DE LA REVERSA: aplicar → un cambio posterior → la reversa tiene que abortar sin rastro (y el control: sin cambio,
# entra y devuelve B8). Y los MUTANTES DE LA REVERSA: RM1, sin su comprobación de la ficha del envoltorio en el preflight, un GRANT
# posterior aborta en su postflight (dos capas); RM2, sin ninguna de las dos, el GRANT se cuela.
#
# RONDA 2 (auditor P3-2, Codex P2-1/P2-2): derivas del preflight con el verificador de 3 argumentos, la cadena del ámbito y la función
# del candado cambiados; un consumidor nuevo de la regla del ámbito y del núcleo; el candado de contacto del 2.8 r4 quitado (de la UPDATE
# o del INSERT del disparador) o sus disparadores de tabla deshabilitados o sin el alternativo. MP4: sin la comprobación del candado (en
# el preflight ni en el postflight), la deriva se cuela. En la reversa: un consumidor NUEVO del envoltorio, de la regla del ámbito, del
# núcleo y un trabajo programado la hacen abortar (revertir le quitaría el alternativo en silencio); RM3, sin esa búsqueda, se cuela.
# Lo que estas búsquedas NO ven: el SQL dinámico (un nombre armado en tiempo de ejecución); son conservadoras (un comentario bloquea).
#
# El cambio de dueño solo lo puede hacer un superusuario: esas derivas corren enteras con EJECUTAR_SQL_ADMIN (el mismo ejecutor como
# supabase_admin). La deriva del trabajo programado escribe en la tabla `cron.job` del laboratorio (sin la extensión) con un jobid
# explícito: `cron.schedule` gastaría la secuencia, que el rollback no devuelve.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/bases-alternativo-cliente/derivas.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (para las derivas «cambio de dueño»)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/bases-alternativo-cliente
MIG="$(ls supabase/migrations/*_crm_bases_alternativo_cliente.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_bases_alternativo_cliente.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

E='private.bases_carga_contacto_existente(text,text)'
N='private.bases_carga_cargar_lote_core(uuid,uuid,uuid,jsonb)'
A='private.bases_carga_fuera_de_ambito(uuid,text,text,text)'
P='crm.cargar_base_lote(uuid,uuid,jsonb)'

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
cambia_cuerpo() { # cambia_cuerpo <firma> <texto que aparece en un COMENTARIO del cuerpo> → SQL que recrea la función con ese texto + «.»
  printf "do \$d\$ begin execute replace(pg_get_functiondef('%s'::regprocedure), \$t\$%s\$t\$, \$t\$%s.\$t\$); end \$d\$;" "$1" "$2" "$2"
}

APLICADA='esta migración ya está aplicada'
ENV_CUERPO='no es el de B8 (20261004184501)'
ENV_FICHA='la ficha del envoltorio no es la auditada'
ENV_COMENTARIO='el comentario del envoltorio no es el de B8'
DEPENDENCIAS='cambió un llamador del envoltorio, la puerta o una pieza que decide su efecto'
LLAMADORES='otro posible consumidor del envoltorio, de la regla del ámbito o del núcleo'
CANDADO='falta el candado de contacto del 2.8 r4'
RESTRICCION='cambió o falta la restricción leads_telefono_alternativo_formato'
TRINQUETES='los private.assert_*() que barre la migración no son los auditados'

# El envoltorio de B8: otro cuerpo; el mismo cuerpo con otro SET; DEFINER (las tres cambian su definición); su ACL; su dueño; su comentario.
deriva "el envoltorio tenía otro cuerpo" "$(cambia_cuerpo "$E" 'Sin agregados de conteo (censo)')" "$ENV_CUERPO"
deriva "el envoltorio traía otro SET" "alter function $E set statement_timeout = '30s';" "$ENV_CUERPO"
deriva "el envoltorio había pasado a security definer" "alter function $E security definer;" "$ENV_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el envoltorio" "grant execute on function $E to authenticated;" "$ENV_FICHA"
deriva "el envoltorio había cambiado de dueño (lo hace un superusuario)" "alter function $E owner to supabase_admin;" "$ENV_FICHA" admin
deriva "el envoltorio traía otro comentario" "comment on function $E is 'comentario ajeno';" "$ENV_COMENTARIO"
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "$APLICADA"
# Sus dos llamadores, la puerta y lo que decide su efecto: otro cuerpo, un GRANT, otra regla.
deriva "el núcleo de la carga tenía otro cuerpo" "$(cambia_cuerpo "$N" 'la primera aparición gana')" "$DEPENDENCIAS"
deriva "la regla del ámbito tenía otro cuerpo" "$(cambia_cuerpo "$A" 'también al convertir un P0429')" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre la puerta crm.cargar_base_lote" "grant execute on function $P to anon;" "$DEPENDENCIAS"
deriva "el verificador (2 argumentos) tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text)'::regprocedure), 'null::uuid', '(null)::uuid'); end \$d\$;" \
  "$DEPENDENCIAS"
deriva "private.normalizar_telefono tenía otra regla (los 9 dígitos ya no ganan el +51)" \
  "create or replace function private.normalizar_telefono(p text) returns text language sql immutable set search_path = '' as \$f\$ select case when p is null or btrim(p) = '' then p else '+' || regexp_replace(p, '[^0-9]', '', 'g') end \$f\$;" \
  "$DEPENDENCIAS"
deriva "private.base_gestion_lead_visible tenía otro cuerpo" "$(cambia_cuerpo 'private.base_gestion_lead_visible(uuid,text,uuid,uuid)' 'un NULL nunca autoriza')" "$DEPENDENCIAS"
deriva "private.bases_carga_lead_ref tenía otro cuerpo" "$(cambia_cuerpo 'private.bases_carga_lead_ref(uuid,text,uuid)' 'se puede devolver o guardar en un recibo')" "$DEPENDENCIAS"
# Ronda 2: el verificador efectivo (3 argumentos), la cadena del ámbito y la función del candado.
deriva "el verificador (3 argumentos) tenía otro cuerpo" "$(cambia_cuerpo 'private.verificar_disponibilidad_lead_impl(text,text,uuid)' 'Un solo lead TOTAL por persona')" "$DEPENDENCIAS"
deriva "private.rol_crm tenía otro cuerpo" "$(cambia_cuerpo 'private.rol_crm(uuid)' 'Directorio es una capacidad de lectura')" "$DEPENDENCIAS"
deriva "private.vendedor_ids_visibles tenía otro cuerpo" "$(cambia_cuerpo 'private.vendedor_ids_visibles(uuid)' 'defensa en profundidad: no enumerar equipos ajenos')" "$DEPENDENCIAS"
deriva "private.es_lector_global tenía otro cuerpo" "$(cambia_cuerpo 'private.es_lector_global()' 'El fallback histórico solo aplica sin membresía')" "$DEPENDENCIAS"
deriva "authenticated ya tenía EXECUTE sobre private.bloquear_contactos_lead" "grant execute on function private.bloquear_contactos_lead(text[],text[]) to authenticated;" "$DEPENDENCIAS"
# Otro LLAMADOR del envoltorio (el cambio lo alcanzaría): por su cuerpo, en minúsculas y en MAYÚSCULAS; por pg_depend (vista, función
# SQL BEGIN ATOMIC); un trabajo programado.
LLAMADOR_PLPGSQL="create function private.ensayo_2_9_llamador() returns bigint language plpgsql stable set search_path = '' as \$f\$ begin return (select count(*) from private.bases_carga_contacto_existente('+51900000000', null)); end \$f\$;"
LLAMADOR_MAYUSCULAS="create function private.ensayo_2_9_llamador_mayusculas() returns bigint language plpgsql stable set search_path = '' as \$f\$ begin return (select count(*) from PRIVATE.BASES_CARGA_CONTACTO_EXISTENTE('+51900000000', null)); end \$f\$;"
deriva "otra función PL/pgSQL llama al envoltorio" "$LLAMADOR_PLPGSQL" "$LLAMADORES"
deriva "otra función lo llama en MAYÚSCULAS (PRIVATE.BASES_CARGA_CONTACTO_EXISTENTE)" "$LLAMADOR_MAYUSCULAS" "$LLAMADORES"
deriva "una vista usa el envoltorio" "create view private.ensayo_2_9_vista as select * from private.bases_carga_contacto_existente('+51900000000', null);" "$LLAMADORES"
deriva "una función SQL BEGIN ATOMIC usa el envoltorio" \
  "create function private.ensayo_2_9_atomica() returns bigint language sql stable begin atomic select count(*) from private.bases_carga_contacto_existente('+51900000000', null); end;" \
  "$LLAMADORES"
deriva "otra función consume la regla del ámbito" \
  "create function private.ensayo_2_9_consume_ambito() returns boolean language sql stable set search_path = '' as \$f\$ select private.bases_carga_fuera_de_ambito(null::uuid, null::text, '+51900000000', null::text) \$f\$;" \
  "$LLAMADORES"
deriva "otra función consume el núcleo de la carga" \
  "create function private.ensayo_2_9_consume_nucleo() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin if false then return private.bases_carga_cargar_lote_core(null, null, null, null); end if; return null; end \$f\$;" \
  "$LLAMADORES"
deriva "un trabajo programado (cron.job.command) nombra el envoltorio" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9029001, 'ensayo-2-9-llamador-del-envoltorio', '0 3 * * *', 'select count(*) from private.bases_carga_contacto_existente(''+51900000000'', null)');" \
  "$LLAMADORES"
# La premisa de la comparación literal: el CHECK del formato del alternativo, quitado o cambiado.
deriva "el CHECK leads_telefono_alternativo_formato estaba quitado" "alter table crm.leads drop constraint leads_telefono_alternativo_formato;" "$RESTRICCION"
deriva "el CHECK leads_telefono_alternativo_formato era otro (y sin validar)" \
  "alter table crm.leads drop constraint leads_telefono_alternativo_formato, add constraint leads_telefono_alternativo_formato check (telefono_alternativo is null or telefono_alternativo ~ '^\\+[0-9]{8,15}\$') not valid;" \
  "$RESTRICCION"
# Ronda 2: el candado de contacto del 2.8 r4 del que depende el orden frente a quien pone ese número como alternativo de un cliente.
D='private.trg_leads_disponibilidad_atomica()'
DISP_SIN_ALT_UPDATE="do \$d\$ begin execute replace(pg_get_functiondef('$D'::regprocedure), 'array[old.telefono, new.telefono, old.telefono_alternativo, new.telefono_alternativo],', 'array[old.telefono, new.telefono],'); end \$d\$;"
DISP_SIN_ALT_INSERT="do \$d\$ begin execute replace(pg_get_functiondef('$D'::regprocedure), 'array[new.telefono, new.telefono_alternativo], array[new.dni]', 'array[new.telefono], array[new.dni]'); end \$d\$;"
GATILLO_SIN_ALT="create or replace trigger trg_leads_00_disponibilidad_update before update of telefono, dni, no_contactar, etapa, activo, motivo_descarte on crm.leads for each row execute function $D;"
deriva "el disparador sin el alternativo en el candado de la UPDATE (el de antes del 2.8 r4)" "$DISP_SIN_ALT_UPDATE" "$CANDADO"
deriva "el disparador sin el alternativo en el candado del INSERT" "$DISP_SIN_ALT_INSERT" "$CANDADO"
deriva "el disparador de la edición estaba deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_update;" "$CANDADO"
deriva "el disparador del INSERT estaba deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_insert;" "$CANDADO"
deriva "el disparador de la edición sin el alternativo en su lista de columnas" "$GATILLO_SIN_ALT" "$CANDADO"
# Los trinquetes que barre: uno con otro cuerpo; uno de más.
deriva "un trinquete tenía otro cuerpo" "$(cambia_cuerpo 'private.assert_tareas_pendientes_base()' 'La policy de lectura de tareas, tal cual se auditó el 19/09/2026')" "$TRINQUETES"
deriva "había un trinquete de más" "create function private.assert_ensayo_2_9() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" "$TRINQUETES"

# ── MUTANTES DEL PREFLIGHT ──────────────────────────────────────────────────────────────────────────────────────────────
mutar_migracion() { # mutar_migracion <trinquetes|llamadores-preflight|llamadores-ambos> <destino>
  python3 -I - "$MIG" "$2" "$1" <<'PY'
import sys
origen, destino, que = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
def quitar(sql, ini, fin, veces_ini=1):
    if sql.count(ini) != veces_ini:
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE (%s: %d)' % (ini.strip()[:60], sql.count(ini)))
    i = sql.index(ini); j = sql.index(fin, i)
    return sql[:i] + sql[j:]
if que == 'trinquetes':
    sql = quitar(sql, "  -- El inventario y las DEFINICIONES de los trinquetes que se barren abajo",
                 "  -- Fotos para el postflight")
elif que in ('llamadores-preflight', 'llamadores-ambos'):
    sql = quitar(sql, "  -- Nadie más consume el envoltorio (salvo el núcleo y el ámbito), la regla del ámbito (salvo el núcleo) ni el núcleo (salvo la puerta):",
                 "  -- La premisa de la comparación literal")
    if que == 'llamadores-ambos':
        sql = quitar(sql, "  -- Nadie más consume el envoltorio, el ámbito ni el núcleo (lo mismo que el preflight, sin cron",
                     "  if (select md5(pg_get_constraintdef(c.oid))")
elif que == 'candado-ambos':
    sql = quitar(sql, "  -- El candado de contacto del 2.8 r4 (Codex P2-1, auditor P3-2):",
                 "  -- Nadie más consume el envoltorio (salvo el núcleo y el ámbito)")
    sql = quitar(sql, "  -- El candado de contacto del 2.8 r4: intacto.",
                 "  -- Nadie más consume el envoltorio, el ámbito ni el núcleo (lo mismo que el preflight, sin cron")
else:
    sys.exit('mutante desconocido')
open(destino, 'w', encoding='utf-8').write(sql)
PY
}
mutante_preflight() { # mutante_preflight <id> <descripción> <qué quitar> <deriva SQL> <espera | vacío = debe ENTRAR>
  echo "$1. $2"
  if ! mutar_migracion "$3" "$TMP/$1.migracion.sql"; then
    echo "  ✗ no se pudo construir $1"; fallos=$((fallos + 1)); return
  fi
  printf '%s\n' "$4" > "$TMP/$1.deriva.sql"
  if [[ -n "$5" ]]; then
    node "$DIR/armar-ensayo.mjs" --migracion "$TMP/$1.migracion.sql" --deriva "$TMP/$1.deriva.sql" --espera "$5" > "$TMP/$1.sql" || exit 1
  else
    node "$DIR/armar-ensayo.mjs" --migracion "$TMP/$1.migracion.sql" --deriva "$TMP/$1.deriva.sql" --espera 'NO DEBE ABORTAR' > "$TMP/$1.sql" || exit 1
  fi
  ejecuta "$EJECUTAR_SQL" "$TMP/$1.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/$1.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/$1.salida.txt" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ -n "$5" ]]; then
    if [[ "$(veredicto "$TMP/$1.salida.txt")" == "VERDE" ]]; then
      echo "  ✓ sin esa comprobación del preflight, la migración aborta igual en su POSTFLIGHT sin rastro → $(aborto "$TMP/$1.salida.txt")"
    else
      echo "  ✗ $1 → $(aborto "$TMP/$1.salida.txt")"; fallos=$((fallos + 1))
    fi
  elif grep -q '^la migración NO abortó' "$TMP/$1.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comprobación, la deriva se coló y la migración entró. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/$1.salida.txt")"; fallos=$((fallos + 1))
  fi
}
mutante_preflight MP1 "Mutante del preflight SIN el inventario de los trinquetes: un trinquete de más tiene que COLARSE" trinquetes \
  "create function private.assert_ensayo_2_9() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" ""
mutante_preflight MP2 "Mutante del preflight SIN la búsqueda de llamadores: otro llamador aborta en el POSTFLIGHT (dos capas)" llamadores-preflight \
  "$LLAMADOR_PLPGSQL" "otro objeto consume el envoltorio"
mutante_preflight MP3 "Mutante SIN la búsqueda de llamadores en el preflight NI en el postflight: el llamador tiene que COLARSE" llamadores-ambos \
  "$LLAMADOR_PLPGSQL" ""
mutante_preflight MP4 "Mutante SIN la comprobación del candado del 2.8 r4 (preflight y postflight): el disparador sin el alternativo tiene que COLARSE" candado-ambos \
  "$DISP_SIN_ALT_UPDATE" ""

# ══ DERIVAS DE LA REVERSA ════════════════════════════════════════════════════════════════════════════════════════════════════
nr=0
reversa_deriva() { # reversa_deriva <nombre> <sentencia(s) SQL> <texto que debe abortar | vacío = control> [admin]
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
    else echo "  ✓ control: sin deriva, la reversa entra y devuelve el envoltorio de B8"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_CUERPO='el envoltorio no es el que deja la migración'
REV_FICHA='la ficha del envoltorio no es la esperada'
REV_COMENTARIO='el comentario del envoltorio no es el que deja la migración'
REV_DEPENDENCIAS='cambió un llamador del envoltorio, la puerta o una pieza que decide su efecto: revisar a mano'
reversa_deriva "control (sin deriva): la reversa entra y devuelve el envoltorio de B8" "" ""
reversa_deriva "un SET statement_timeout añadido al envoltorio" "alter function $E set statement_timeout = '30s';" "$REV_CUERPO"
reversa_deriva "el envoltorio con otro cuerpo" "$(cambia_cuerpo "$E" 'teléfono de la fila llega normalizado')" "$REV_CUERPO"
reversa_deriva "un GRANT EXECUTE a authenticated sobre el envoltorio" "grant execute on function $E to authenticated;" "$REV_FICHA"
reversa_deriva "el envoltorio cambió de dueño (lo hace un superusuario)" "alter function $E owner to supabase_admin;" "$REV_FICHA" admin
reversa_deriva "el comentario del envoltorio cambió" "comment on function $E is 'comentario ajeno';" "$REV_COMENTARIO"
reversa_deriva "el núcleo de la carga cambió después" "$(cambia_cuerpo "$N" 'la primera aparición gana')" "$REV_DEPENDENCIAS"
# Ronda 2 (Codex P2-2): un CONSUMIDOR nuevo, posterior a la migración, del envoltorio, de la regla del ámbito, del núcleo; un trabajo
# programado. Revertir le quitaría el alternativo de los clientes en silencio: la reversa tiene que negarse y no dejar rastro.
REV_CONSUMIDORES='posible consumidor del envoltorio, de la regla del ámbito o del núcleo'
reversa_deriva "un consumidor nuevo del envoltorio (PL/pgSQL)" "$LLAMADOR_PLPGSQL" "$REV_CONSUMIDORES"
reversa_deriva "un consumidor nuevo de la regla del ámbito" \
  "create function private.ensayo_2_9_consume_ambito() returns boolean language sql stable set search_path = '' as \$f\$ select private.bases_carga_fuera_de_ambito(null::uuid, null::text, '+51900000000', null::text) \$f\$;" \
  "$REV_CONSUMIDORES"
reversa_deriva "un consumidor nuevo del núcleo de la carga" \
  "create function private.ensayo_2_9_consume_nucleo() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin if false then return private.bases_carga_cargar_lote_core(null, null, null, null); end if; return null; end \$f\$;" \
  "$REV_CONSUMIDORES"
reversa_deriva "un trabajo programado nuevo nombra el envoltorio" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9029002, 'ensayo-2-9-consumidor-posterior', '0 3 * * *', 'select count(*) from private.bases_carga_contacto_existente(''+51900000000'', null)');" \
  "$REV_CONSUMIDORES"

# ── MUTANTES DE LA REVERSA: su comprobación de la ficha del envoltorio, en el preflight y en el postflight ─────────────────
mutar_reversa() { # mutar_reversa <preflight|ambos> <destino>
  python3 -I - "$DIR/reversa.sql" "$2" "$1" <<'PY'
import sys
origen, destino, que = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  if not exists (select 1 from pg_proc p where p.oid = v_env and p.proowner = 'postgres'::regrole::oid and not p.prosecdef\n"
fin = "    raise exception 'REVERSA bases_alternativo_cliente: la ficha del envoltorio no es la esperada (dueño postgres, security invoker, stable, search_path vacío, EXECUTE solo para postgres sin opción de concesión): revisar a mano';\n  end if;\n"
if sql.count(ini) != 2 or sql.count(fin) != 2:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE')
def quitar_primera(s):
    i = s.index(ini); j = s.index(fin, i) + len(fin)
    return s[:i] + s[j:]
sql = quitar_primera(sql)              # la del preflight (la primera)
if que == 'ambos':
    sql = quitar_primera(sql)          # y la del postflight
open(destino, 'w', encoding='utf-8').write(sql)
PY
}
printf '%s\n' "grant execute on function $E to authenticated;" > "$TMP/rm.deriva.sql"
echo "RM1. Mutante de la reversa SIN la comprobación de la ficha del envoltorio en el preflight: el GRANT aborta en el postflight"
if mutar_reversa preflight "$TMP/reversa-sin-ficha-preflight.sql"; then
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera "$REV_FICHA" \
    --reversa-archivo "$TMP/reversa-sin-ficha-preflight.sql" > "$TMP/rm1.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm1.sql"
  if [[ "$(veredicto "$TMP/rm1.salida.txt")" == "VERDE" ]]; then
    echo "  ✓ sin la comprobación del preflight, la reversa aborta en su postflight sin rastro → $(aborto "$TMP/rm1.salida.txt")"
  else
    echo "  ✗ RM1 → $(aborto "$TMP/rm1.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM1"; fallos=$((fallos + 1))
fi
echo "RM2. Mutante de la reversa SIN ninguna de las dos comprobaciones: el GRANT tiene que COLARSE"
if mutar_reversa ambos "$TMP/reversa-sin-ficha.sql"; then
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera "$REV_FICHA" \
    --reversa-archivo "$TMP/reversa-sin-ficha.sql" > "$TMP/rm2.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm2.sql"
  if [[ "$(veredicto "$TMP/rm2.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm2.salida.txt"; then
    echo "  ✓ el mutante muere: sin esas comprobaciones, la reversa revirtió dejando el GRANT. Son ellas las que protegen."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm2.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM2"; fallos=$((fallos + 1))
fi

echo "RM3. Mutante de la reversa SIN su búsqueda de consumidores: un consumidor nuevo del envoltorio tiene que COLARSE (perdería el alternativo)"
if python3 -I - "$DIR/reversa.sql" "$TMP/reversa-sin-consumidores.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- Nadie más consume el envoltorio (salvo el núcleo y el ámbito), la regla del ámbito (salvo el núcleo) ni el núcleo (salvo la puerta)\n"
fin = "end\n$preflight$;"
if sql.count(ini) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (consumidores)')
i = sql.index(ini); j = sql.index(fin, i)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "$LLAMADOR_PLPGSQL" > "$TMP/rm3.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm3.deriva.sql" --espera "$REV_CONSUMIDORES" \
    --reversa-archivo "$TMP/reversa-sin-consumidores.sql" > "$TMP/rm3.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm3.sql"
  if [[ "$(veredicto "$TMP/rm3.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm3.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa búsqueda, la reversa devolvió B8 dejando al consumidor sin el alternativo. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm3.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM3"; fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: el control entra; las $n derivas abortan en el preflight sin rastro; MP1, MP3 y MP4 mueren y MP2 aborta en el postflight; las $((nr - 1)) derivas de la reversa abortan sin rastro y su control entra; RM1 aborta en el postflight y RM2 y RM3 mueren."
  exit 0
fi
echo "DERIVAS: $fallos fallo(s) — hay defensas del preflight o de la reversa sin prueba."
exit 1
