#!/usr/bin/env bash
# DERIVAS del bloque 2.8 — la migración (y su reversa) se niegan si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una DERIVA rompe el catálogo ANTES:
# lo que se prueba aquí es el PREFLIGHT. La migración parchea por ancla única el núcleo y el disparador y reescribe la lista de
# columnas del disparador de tabla: sin preflight, un cambio hecho a mano en cualquiera de ellos (o en el alta, el verificador, una
# pieza de la que depende la regla o la ficha cuya edición protege) se pisaría o se daría por bueno sin que nadie lo viera. Con cada
# deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar todo
# (núcleo, disparador, disparadores de tabla, alta, ficha y puerta del DNI: definición, dueño, ACL, comentario) EXACTAMENTE como estaba.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Después, un MUTANTE DEL PREFLIGHT: sin comparar
# la definición de los disparadores de tabla, una lista de columnas cambiada a mano se pisaría sin aviso (la migración entra).
#
# Ronda 3 (Codex F2 y F5): también los ATRIBUTOS y PERMISOS de las dependencias (una función que pasa a DEFINER o a STRICT, un
# GRANT, un cambio de dueño), los CHECK de los que depende la comparación literal (quitado, cambiado o sin validar) y el inventario y
# las definiciones de los trinquetes que se barren (uno cambiado, uno nuevo, uno borrado): todo eso aborta ANTES del primer barrido.
#
# Al final, las DERIVAS DE LA REVERSA: aplicar → un cambio posterior → la reversa tiene que abortar sin rastro (y el control: sin
# cambio, entra y devuelve el 2.7 y B8). Ronda 3 (auditor F2, Codex F4): otro LLAMADOR de la pieza (una función PL/pgSQL, una vista,
# una función SQL BEGIN ATOMIC, una policy) también la hace abortar; y el LÍMITE declarado: una llamada construida en tiempo de
# ejecución no se ve (se mide: la reversa entra). RM3: sin su comprobación de llamadores, el llamador PL/pgSQL se cuela.
# Ronda 4 (Codex R2-F1, auditor P3-1): un llamador ESTÁTICO escrito en MAYÚSCULAS (`PRIVATE.JUICIO_CLIENTE_CONVERTIDO(…)`, que llama a
# la misma función) y un trabajo programado (`cron.job.command`) también la hacen abortar con «posible llamador: inspeccionar antes de
# revertir»; un comentario que la nombra también (falso positivo conservador, declarado). RM4 (la búsqueda de la ronda 3, que distingue
# mayúsculas) y RM5 (sin mirar cron.job) dejan colar los suyos. Derivas de instalación nuevas: el CHECK
# `leads_telefono_alternativo_crudo_cordura` quitado o cambiado, y las dos funciones de las que depende la clave del candado del
# alternativo (`private.bloquear_contactos_lead`, `private.normalizar_telefono`). El cambio de dueño solo lo puede hacer un superusuario: esa deriva corre entera con
# EJECUTAR_SQL_ADMIN (el mismo ejecutor como supabase_admin; la migración fija el dueño de la pieza en postgres, así que su postflight
# vale igual). Y dos MUTANTES DE LA REVERSA: sin su comprobación de la ficha del disparador en el preflight, un GRANT posterior aborta
# en su postflight (defensa en dos capas); sin ninguna de las dos, el GRANT se cuela.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/cliente-no-se-duplica-al-editar/derivas.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (para la deriva «cambio de dueño» de la reversa)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/cliente-no-se-duplica-al-editar
MIG="$(ls supabase/migrations/*_crm_cliente_no_se_duplica_al_editar.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_cliente_no_se_duplica_al_editar.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

N='private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'
D='private.trg_leads_disponibilidad_atomica()'
P='private.juicio_cliente_convertido(text,text,text,uuid)'
F='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'

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
NUCLEO_CUERPO='no es el que deja el bloque 2.7'
NUCLEO_FICHA='la ficha del núcleo no es la auditada'
NUCLEO_COMENTARIO='el comentario del núcleo no es el que deja el 2.7'
DISP_CUERPO='no es el de bases cargadas (B8'
DISP_FICHA='la ficha del disparador no es la auditada'
DISP_COMENTARIO='el comentario del disparador no es el de B8'
DISPARADORES='los disparadores de tabla trg_leads_00_disponibilidad_insert/_update no son los auditados'
ALTA='crm.crear_lead_si_disponible no es la que deja el 2.4'
VERIFICADOR='no es el fijado por la carga de bases'
PIEZAS='cambió una pieza de la que depende la regla o la ficha cuya edición protege'
RESTRICCIONES='cambió o falta una restricción de crm.leads de la que depende la regla'
TRINQUETES='los private.assert_*() que barre la migración no son los auditados'

# El núcleo que deja el 2.7: otro cuerpo; el mismo cuerpo con otro SET; INVOKER (las tres cambian su definición); su ACL; su comentario.
deriva "el núcleo tenía otro cuerpo" "$(cambia_cuerpo "$N" 'Acceso CRM revocado')" "$NUCLEO_CUERPO"
deriva "el núcleo traía otro SET" "alter function $N set statement_timeout = '30s';" "$NUCLEO_CUERPO"
deriva "el núcleo había pasado a security invoker" "alter function $N security invoker;" "$NUCLEO_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el núcleo" "grant execute on function $N to authenticated;" "$NUCLEO_FICHA"
deriva "el núcleo traía otro comentario" "comment on function $N is 'comentario ajeno';" "$NUCLEO_COMENTARIO"
# El disparador de B8: otro cuerpo; otro SET; su ACL; su comentario.
deriva "el disparador tenía otro cuerpo" "$(cambia_cuerpo "$D" 'Telefono invalido')" "$DISP_CUERPO"
deriva "el disparador traía otro SET" "alter function $D set statement_timeout = '30s';" "$DISP_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el disparador" "grant execute on function $D to authenticated;" "$DISP_FICHA"
deriva "el disparador traía otro comentario" "comment on function $D is 'comentario ajeno';" "$DISP_COMENTARIO"
# Los disparadores de tabla: otra lista de columnas; el de la edición deshabilitado; el del INSERT deshabilitado.
GATILLO_OTRA_LISTA="create or replace trigger trg_leads_00_disponibilidad_update before update of telefono, dni, no_contactar, etapa, activo on crm.leads for each row execute function $D;"
deriva "el disparador de la edición tenía otra lista de columnas" "$GATILLO_OTRA_LISTA" "$DISPARADORES"
deriva "el disparador de la edición estaba deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_update;" "$DISPARADORES"
deriva "el disparador del INSERT estaba deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_insert;" "$DISPARADORES"
# El alta del 2.4: otro cuerpo; anon con EXECUTE.
deriva "crm.crear_lead_si_disponible tenía otro cuerpo" "$(cambia_cuerpo "$F" 'El nombre es obligatorio')" "$ALTA"
deriva "anon ya tenía EXECUTE sobre el alta" "grant execute on function $F to anon;" "$ALTA"
# El verificador sellado por la carga de bases.
deriva "el verificador (3 argumentos) tenía otro cuerpo" "$(cambia_cuerpo 'private.verificar_disponibilidad_lead_impl(text,text,uuid)' 'Un solo lead TOTAL por persona')" "$VERIFICADOR"
# Las piezas que usa la regla y la ficha cuya edición protege.
deriva "private.juicio_persona tenía otro cuerpo" "$(cambia_cuerpo 'private.juicio_persona(uuid,uuid)' 'sin asesor asignado')" "$PIEZAS"
deriva "private.bases_carga_nace_dormido tenía otro cuerpo" "$(cambia_cuerpo 'private.bases_carga_nace_dormido(text,text,text,boolean)' 'un NULL nunca habilita')" "$PIEZAS"
deriva "crm.editar_lead_fn tenía otro cuerpo" "$(cambia_cuerpo 'crm.editar_lead_fn(uuid,jsonb)' 'nunca un «ok» sin escribir')" "$PIEZAS"
deriva "crm.fijar_dni_lead_fn tenía otro cuerpo" "$(cambia_cuerpo 'crm.fijar_dni_lead_fn(uuid,text)' 'Lead no encontrado o fuera de tu ambito')" "$PIEZAS"
deriva "crm.fijar_documento_lead_fn tenía otro cuerpo" "$(cambia_cuerpo 'crm.fijar_documento_lead_fn(uuid,text,text,uuid,text)' 'El lead está cerrado')" "$PIEZAS"
# Ronda 3 (Codex F2): atributos, permisos y dueño de las dependencias, no solo su cuerpo.
deriva "crm.editar_lead_fn había pasado a security definer" "alter function crm.editar_lead_fn(uuid,jsonb) security definer;" "$PIEZAS"
deriva "private.juicio_persona había pasado a STRICT" "alter function private.juicio_persona(uuid,uuid) strict;" "$PIEZAS"
deriva "authenticated ya tenía EXECUTE sobre private.juicio_persona" "grant execute on function private.juicio_persona(uuid,uuid) to authenticated;" "$PIEZAS"
deriva "authenticated ya tenía EXECUTE sobre el verificador (3 argumentos)" "grant execute on function private.verificar_disponibilidad_lead_impl(text,text,uuid) to authenticated;" "$PIEZAS"
deriva "anon ya tenía EXECUTE sobre crm.editar_lead_documento_fn" "grant execute on function crm.editar_lead_documento_fn(uuid,jsonb,text,text,uuid,text) to anon;" "$PIEZAS"
deriva "private.juicio_persona había cambiado de dueño (lo hace un superusuario)" "alter function private.juicio_persona(uuid,uuid) owner to supabase_admin;" "$PIEZAS" admin
# Ronda 3 (Codex F2): los CHECK de los que depende la comparación literal del alternativo y el DNI.
deriva "faltaba el CHECK leads_telefono_alternativo_formato" "alter table crm.leads drop constraint leads_telefono_alternativo_formato;" "$RESTRICCIONES"
deriva "el CHECK leads_dni_check era otro" "alter table crm.leads drop constraint leads_dni_check, add constraint leads_dni_check check (dni is null or dni ~ '^[0-9]{8,9}\$');" "$RESTRICCIONES"
deriva "el CHECK leads_telefono_alternativo_excluyentes estaba sin validar (NOT VALID)" "alter table crm.leads drop constraint leads_telefono_alternativo_excluyentes, add constraint leads_telefono_alternativo_excluyentes check (telefono_alternativo is null or telefono_alternativo_crudo is null) not valid;" "$RESTRICCIONES"
# Ronda 4 (auditor r2, hueco): el CHECK del alternativo sin validar, quitado o cambiado.
deriva "faltaba el CHECK leads_telefono_alternativo_crudo_cordura" "alter table crm.leads drop constraint leads_telefono_alternativo_crudo_cordura;" "$RESTRICCIONES"
deriva "el CHECK leads_telefono_alternativo_crudo_cordura era otro (hasta 50 caracteres)" "alter table crm.leads drop constraint leads_telefono_alternativo_crudo_cordura, add constraint leads_telefono_alternativo_crudo_cordura check (telefono_alternativo_crudo is null or (btrim(telefono_alternativo_crudo) <> '' and length(telefono_alternativo_crudo) <= 50));" "$RESTRICCIONES"
# Ronda 4 (auditor P3-4): las dos funciones de las que depende la clave del candado del alternativo.
deriva "private.bloquear_contactos_lead tenía otro cuerpo (otro prefijo de clave)" "$(cambia_cuerpo 'private.bloquear_contactos_lead(text[],text[])' 'avancecrm:lead:')" "$PIEZAS"
deriva "authenticated ya tenía EXECUTE sobre private.bloquear_contactos_lead" "grant execute on function private.bloquear_contactos_lead(text[],text[]) to authenticated;" "$PIEZAS"
deriva "private.normalizar_telefono tenía otra regla (los 9 dígitos ya no ganan el +51)" "create or replace function private.normalizar_telefono(p text) returns text language sql immutable set search_path = '' as \$f\$ select case when p is null or btrim(p) = '' then p else '+' || regexp_replace(p, '[^0-9]', '', 'g') end \$f\$;" "$PIEZAS"
# Ronda 3 (Codex F5): el inventario y las definiciones de los trinquetes, ANTES del primer barrido.
deriva "un trinquete barrido tenía otro cuerpo" "$(cambia_cuerpo 'private.assert_gestion_diaria()' 'OK: Gestion Diaria [')" "$TRINQUETES"
deriva "había un trinquete más" "create function private.assert_ensayo_deriva_2_8() returns text language sql stable as \$f\$ select 'OK' \$f\$;" "$TRINQUETES"
deriva "faltaba un trinquete" "drop function private.assert_gestion_diaria_lectura();" "$TRINQUETES"
# Ya aplicada: otra función con el nombre de la pieza; la migración entera ya aplicada.
deriva "ya existía otra private.juicio_cliente_convertido (otra firma)" \
  "create function private.juicio_cliente_convertido(p text) returns jsonb language sql stable set search_path = '' as \$f\$ select null::jsonb \$f\$;" \
  "$APLICADA"
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "$APLICADA"

# ── MUTANTE DEL PREFLIGHT: sin comparar la definición de los disparadores de tabla, la otra lista de columnas se pisaría sin aviso ──
echo "M. Mutante del preflight: una copia de la migración SIN comparar los disparadores de tabla tiene que dejar entrar la deriva «otra lista de columnas»"
if python3 -I - "$MIG" "$TMP/mig-sin-disparadores.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- Los dos disparadores de tabla de disponibilidad, exactos y habilitados.\n"
fin = "  -- El alta del 2.4 (esta migración no la toca"
if sql.count(ini) != 1 or sql.count(fin) != 1:
    sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE')
i = sql.index(ini); j = sql.index(fin)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "$GATILLO_OTRA_LISTA" > "$TMP/mp.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-disparadores.sql" --deriva "$TMP/mp.deriva.sql" --espera "$DISPARADORES" > "$TMP/mp.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/mp.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp.salida.txt" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp.salida.txt")" == "ROJO" ]] && grep -q '^la migración NO abortó' "$TMP/mp.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comparación, la lista cambiada a mano se pisó y la migración entró. Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/mp.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del preflight"; fallos=$((fallos + 1))
fi

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
    elif [[ "${5:-}" == "limite" ]]; then echo "  ✓ límite medido: no se detecta; la reversa entra y devuelve el 2.7 y B8 (el llamador dinámico queda roto)"
    else echo "  ✓ control: sin deriva, la reversa entra y devuelve el 2.7 y B8"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_PIEZA='la pieza private.juicio_cliente_convertido no es la que dejó la migración'
REV_NUCLEO_DEF='el núcleo no tiene exactamente la definición que dejó la migración'
REV_NUCLEO_FICHA='la ficha o el comentario del núcleo no son los que dejó la migración'
REV_DISP_DEF='el disparador no tiene exactamente la definición que dejó la migración'
REV_DISP_FICHA='la ficha o el comentario del disparador no son los que dejó la migración'
REV_DISPARADORES='los disparadores de tabla de disponibilidad no son los que dejó la migración'
REV_LLAMADORES='posible llamador de la pieza private.juicio_cliente_convertido'
reversa_deriva "control (sin deriva): la reversa entra y devuelve el núcleo del 2.7 y el disparador de B8" "" ""
reversa_deriva "un SET statement_timeout añadido al disparador" "alter function $D set statement_timeout = '30s';" "$REV_DISP_DEF"
reversa_deriva "un GRANT EXECUTE a authenticated sobre el disparador" "grant execute on function $D to authenticated;" "$REV_DISP_FICHA"
reversa_deriva "el disparador cambió de dueño (lo hace un superusuario)" "alter function $D owner to supabase_admin;" "$REV_DISP_FICHA" admin
reversa_deriva "el comentario del disparador cambió" "comment on function $D is 'comentario ajeno';" "$REV_DISP_FICHA"
reversa_deriva "un SET statement_timeout añadido al núcleo" "alter function $N set statement_timeout = '30s';" "$REV_NUCLEO_DEF"
reversa_deriva "el comentario del núcleo cambió" "comment on function $N is 'comentario ajeno';" "$REV_NUCLEO_FICHA"
reversa_deriva "un GRANT EXECUTE a authenticated sobre la pieza" "grant execute on function $P to authenticated;" "$REV_PIEZA"
reversa_deriva "la pieza con otro cuerpo" "$(cambia_cuerpo "$P" 'Si ningún teléfono casa, el DNI (D-27)')" "$REV_PIEZA"
reversa_deriva "el disparador de la edición deshabilitado" "alter table crm.leads disable trigger trg_leads_00_disponibilidad_update;" "$REV_DISPARADORES"
# Ronda 3 (auditor F2, Codex F4): otro LLAMADOR de la pieza. PL/pgSQL no registra dependencias (búsqueda en los cuerpos); la vista,
# la función SQL BEGIN ATOMIC y la policy sí (pg_depend).
LLAMADOR_PLPGSQL="create function private.ensayo_llamador_de_la_pieza() returns jsonb language plpgsql stable set search_path = '' as \$f\$ begin return private.juicio_cliente_convertido(null, null, null, null); end \$f\$;"
reversa_deriva "otra función PL/pgSQL llama a la pieza" "$LLAMADOR_PLPGSQL" "$REV_LLAMADORES"
reversa_deriva "una vista usa la pieza" "create view private.ensayo_vista_de_la_pieza as select private.juicio_cliente_convertido(null, null, null, null) as j;" "$REV_LLAMADORES"
reversa_deriva "una función SQL BEGIN ATOMIC usa la pieza" "create function private.ensayo_atomica_de_la_pieza() returns jsonb language sql stable begin atomic select private.juicio_cliente_convertido(null, null, null, null); end;" "$REV_LLAMADORES"
reversa_deriva "una policy usa la pieza" "create policy ensayo_policy_de_la_pieza on crm.leads as permissive for select to postgres using (private.juicio_cliente_convertido(null, null, null, null) is null);" "$REV_LLAMADORES"
# LÍMITE DECLARADO (medido, no protegido): una llamada con el nombre construido en tiempo de ejecución no se ve; la reversa entra
# (y esa función fallaría al llamarse). Se juzga como el control: tiene que ENTRAR.
reversa_deriva "LÍMITE: un llamador dinámico (EXECUTE con el nombre partido) no se ve: la reversa entra" "create function private.ensayo_llamador_dinamico() returns jsonb language plpgsql stable set search_path = '' as \$f\$ declare v jsonb; begin execute 'select private.' || 'juicio_cliente' || '_convertido(null, null, null, null)' into v; return v; end \$f\$;" "" "" limite
# Ronda 4 (Codex R2-F1 + auditor P3-1). Un llamador ESTÁTICO en MAYÚSCULAS: el identificador sin comillas llama a la misma función (la
# deriva lo llama una vez para demostrarlo) y PL/pgSQL no registra la dependencia; la búsqueda, sin distinguir mayúsculas, lo ve.
LLAMADOR_MAYUSCULAS="create function private.ensayo_llamador_mayusculas() returns jsonb language plpgsql stable set search_path = '' as \$f\$ BEGIN RETURN PRIVATE.JUICIO_CLIENTE_CONVERTIDO(NULL, NULL, NULL, NULL); END \$f\$; do \$p\$ begin perform private.ensayo_llamador_mayusculas(); end \$p\$;"
reversa_deriva "un llamador PL/pgSQL ESTÁTICO en MAYÚSCULAS (PRIVATE.JUICIO_CLIENTE_CONVERTIDO)" "$LLAMADOR_MAYUSCULAS" "$REV_LLAMADORES"
# Un trabajo programado que la nombra (el laboratorio tiene la tabla cron.job de pg_cron como tabla de ensayo, sin la extensión). Con
# jobid explícito: `cron.schedule` gastaría la secuencia cron.job_jobid_seq, que el rollback no devuelve (no es transaccional).
CRON_LLAMADOR="insert into cron.job (jobid, jobname, schedule, command) values (9028001, 'ensayo-2-8-llamador-de-la-pieza', '0 3 * * *', 'select private.juicio_cliente_convertido(null, null, null, null)');"
reversa_deriva "un trabajo programado (cron.job.command) llama a la pieza" "$CRON_LLAMADOR" "$REV_LLAMADORES"
# Falso positivo CONSERVADOR (declarado): un comentario que nombra la pieza también bloquea; se inspecciona antes de revertir.
reversa_deriva "falso positivo conservador: un comentario que nombra la pieza (bloquea: inspeccionar)" "create function private.ensayo_comentario_de_la_pieza() returns integer language plpgsql stable set search_path = '' as \$f\$ begin -- antes se llamaba a private.juicio_cliente_convertido; ya no
return 1; end \$f\$;" "$REV_LLAMADORES"

# ── MUTANTES DE LA REVERSA: sus comprobaciones de la ficha del disparador son las que protegen ─────────────────────────────────
#    RM1 — sin la del PREFLIGHT: el GRANT posterior a authenticated sobre el disparador aborta en su POSTFLIGHT (ficha y ACL exactas de B8).
#    RM2 — sin la del preflight NI la del postflight: la reversa revierte dejando el GRANT. Muere = se cuela.
mutar_reversa() { # mutar_reversa <preflight|ambos> <destino>
  python3 -I - "$DIR/reversa.sql" "$2" "$1" <<'PY'
import sys
origen, destino, modo = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ficha = """not exists (select 1 from pg_proc p
                  where p.oid = v_disp and p.proowner = 'postgres'::regrole::oid and p.prosecdef
                    and p.proconfig @> array['search_path=""'] and p.proconfig @> array['lock_timeout=5s'] and cardinality(p.proconfig) = 2)
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = v_disp)
        is distinct from array['postgres:EXECUTE:false']
     or has_function_privilege('anon', v_disp, 'EXECUTE') or has_function_privilege('authenticated', v_disp, 'EXECUTE')
     or has_function_privilege('service_role', v_disp, 'EXECUTE')"""
pre = "  if " + ficha + "\n     or md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then\n"
if sql.count(pre) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (preflight)')
sql = sql.replace(pre, "  if md5(coalesce(obj_description(v_disp, 'pg_proc'), '')) is distinct from '4a3fee01861a0fc10af38eb3fc338eb2' then\n")
if modo == 'ambos':
    post = "\n     or " + ficha + " then\n    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el disparador no quedó como lo dejó B8"
    if sql.count(post) != 1:
        sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (postflight)')
    sql = sql.replace(post, " then\n    raise exception 'REVERSA cliente_no_se_duplica_al_editar: el disparador no quedó como lo dejó B8")
open(destino, 'w', encoding='utf-8').write(sql)
PY
}
printf '%s\n' "grant execute on function $D to authenticated;" > "$TMP/rm.deriva.sql"
echo "RM1. Mutante de la reversa SIN la comprobación de la ficha del disparador en el preflight: el GRANT aborta en el postflight"
if mutar_reversa preflight "$TMP/reversa-sin-ficha-preflight.sql"; then
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera 'el disparador no quedó como lo dejó B8' \
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
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm.deriva.sql" --espera "$REV_DISP_FICHA" \
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

echo "RM3. Mutante de la reversa SIN su comprobación de llamadores: el llamador PL/pgSQL tiene que COLARSE (el DROP sin CASCADE no lo ve)"
if python3 -I - "$DIR/reversa.sql" "$TMP/reversa-sin-llamadores.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- Nadie más usa la pieza (ronda 3; ronda 4"
fin = "  if (select md5(p.prosrc) || '/' || md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = v_nucleo)"
if sql.count(ini) != 1 or fin not in sql[sql.index(ini):]:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (llamadores)')
i = sql.index(ini); j = sql.index(fin, i)  # la primera comprobación del núcleo DESPUÉS del bloque (el postflight repite el texto)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
then
  printf '%s\n' "$LLAMADOR_PLPGSQL" > "$TMP/rm3.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm3.deriva.sql" --espera "$REV_LLAMADORES" \
    --reversa-archivo "$TMP/reversa-sin-llamadores.sql" > "$TMP/rm3.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm3.sql"
  if [[ "$(veredicto "$TMP/rm3.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm3.salida.txt"; then
    echo "  ✓ el mutante muere: sin esa comprobación, la reversa borró la pieza dejando a su llamador roto. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm3.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir RM3"; fallos=$((fallos + 1))
fi

# ── Ronda 4: RM4 (la búsqueda de la ronda 3, que distingue mayúsculas) y RM5 (sin mirar cron.job) ────────────────────────────────
mutar_llamadores() { # mutar_llamadores <mayusculas|cron> <destino>
  python3 -I - "$DIR/reversa.sql" "$2" "$1" <<'PY'
import sys
origen, destino, modo = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
if modo == 'mayusculas':
    viejo = "position('juicio_cliente_convertido' in lower(coalesce(p.prosrc, ''))) > 0"
    nuevo = "position('juicio_cliente_convertido' in coalesce(p.prosrc, '')) > 0"
else:
    i = sql.find("  if to_regclass('cron.job') is not null then\n")
    j = sql.find("    v_mal := nullif(concat_ws(', ', v_mal, v_cron), '');\n  end if;\n", i)
    if i < 0 or j < 0 or sql.count("  if to_regclass('cron.job') is not null then\n") != 1:
        sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (cron)')
    viejo = sql[i:j + len("    v_mal := nullif(concat_ws(', ', v_mal, v_cron), '');\n  end if;\n")]
    nuevo = ''
if sql.count(viejo) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE (%s)' % modo)
open(destino, 'w', encoding='utf-8').write(sql.replace(viejo, nuevo))
PY
}
rm_colarse() { # rm_colarse <id> <modo> <deriva> <descripción>
  echo "$1. Mutante de la reversa $4: la deriva tiene que COLARSE"
  if mutar_llamadores "$2" "$TMP/reversa-$1.sql"; then
    printf '%s\n' "$3" > "$TMP/$1.deriva.sql"
    node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/$1.deriva.sql" --espera "$REV_LLAMADORES" \
      --reversa-archivo "$TMP/reversa-$1.sql" > "$TMP/$1.sql" || exit 1
    ejecuta "$EJECUTAR_SQL" "$TMP/$1.sql"
    if [[ "$(veredicto "$TMP/$1.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/$1.salida.txt"; then
      echo "  ✓ el mutante muere: sin esa comprobación, la reversa borró la pieza dejando a su llamador roto. Es ella la que protege."
    else
      echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/$1.salida.txt")"; fallos=$((fallos + 1))
    fi
  else
    echo "  ✗ no se pudo construir $1"; fallos=$((fallos + 1))
  fi
}
rm_colarse RM4 mayusculas "$LLAMADOR_MAYUSCULAS" "con la búsqueda de la ronda 3 (distingue mayúsculas)"
rm_colarse RM5 cron "$CRON_LLAMADOR" "sin mirar cron.job"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight de la migración y no dejan rastro; el control entra; el mutante del preflight muere."
  echo "DERIVAS DE LA REVERSA: el control y el límite medido entran; las $((nr - 2)) derivas abortan su preflight sin rastro; RM1 aborta en el postflight; RM2, RM3, RM4 y RM5 mueren."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — un preflight no protege lo que dice."
exit 1
