#!/usr/bin/env bash
# DERIVAS del bloque 2.11 — la migración (y su reversa) se niegan si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una DERIVA rompe el catálogo ANTES:
# lo que se prueba aquí es el PREFLIGHT. La migración parchea por ancla única los dos núcleos (el del alta, que deja el 2.8; el de la
# base, de B10) y crea una pieza que usa la del 2.8: sin preflight, un cambio hecho a mano en ellos (o en lo que los llama o decide su
# efecto, en los CHECK de los que depende la comparación literal o en los trinquetes que barre), u otro objeto que llamara a los
# núcleos, se pisaría o se daría por bueno sin que nadie lo viera. Con cada deriva la migración tiene que ABORTAR en su preflight —con
# el mensaje que le corresponde, no con cualquier error— y dejar los dos núcleos, la pieza, la del 2.8, lo conservado del 2.4, el alta y
# las puertas de la base (definición, dueño, ACL, comentario) EXACTAMENTE como estaban.
#
# El paso 0 es el control: sin deriva, la migración entra. Después, los MUTANTES DEL PREFLIGHT: MP1, sin el inventario de los
# trinquetes, un trinquete de más se colaría (la migración entra: muere); MP2, sin la búsqueda de llamadores en el preflight, otro
# llamador aborta igual en el POSTFLIGHT (defensa en dos capas); MP3, sin ninguna de las dos, el llamador se cuela. Ronda 3 (Codex r1,
# P2): lo mismo con un TRABAJO PROGRAMADO que ya nombra la pieza nueva (MP2c aborta en el postflight; MP3c se cuela), y dos derivas
# previas más: un cron.job y una función que ya nombran la pieza antes de aplicar.
#
# Al final, las DERIVAS DE LA REVERSA: aplicar → un cambio posterior → la reversa tiene que abortar sin rastro (y el control: sin
# cambio, entra y devuelve los dos núcleos de antes y quita la pieza). Y dos MUTANTES DE LA REVERSA, sin su búsqueda de llamadores de
# la pieza: RM1, una vista que la usa hace fallar el borrado sin CASCADE (dos capas); RM2, una función PL/pgSQL que la llama (no
# registra dependencia) se queda rota: la reversa revierte y el mutante muere.
#
# El cambio de dueño solo lo puede hacer un superusuario: esas derivas corren enteras con EJECUTAR_SQL_ADMIN (el mismo ejecutor como
# supabase_admin). La deriva del trabajo programado escribe en la tabla `cron.job` del laboratorio (sin la extensión) con un jobid
# explícito: `cron.schedule` gastaría la secuencia, que el rollback no devuelve.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un .sql en el banco>" EJECUTAR_SQL_ADMIN="<el mismo, como supabase_admin>" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/reactivar-reconoce-cliente/derivas.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${EJECUTAR_SQL_ADMIN:?EJECUTAR_SQL_ADMIN: el mismo ejecutor del laboratorio como supabase_admin (para las derivas «cambio de dueño»)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/reactivar-reconoce-cliente
MIG="$(ls supabase/migrations/*_crm_reactivar_reconoce_cliente.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_reactivar_reconoce_cliente.sql"; exit 1; }
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

N='private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'
B='private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'
P28='private.juicio_cliente_convertido(text,text,text,uuid)'
P='private.juicio_cliente_conservado(uuid)'

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

echo "0. Control: sin deriva, la migración entra"
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
otro_set() { # otro_set <firma> → SQL que le añade un SET (cambia su definición)
  printf "alter function %s set statement_timeout = '30s';" "$1"
}

APLICADA='esta migración ya está aplicada'
N_CUERPO='no es el que deja el 2.8 ronda 4'
N_FICHA='la ficha del núcleo del alta no es la auditada'
N_COMENTARIO='el comentario del núcleo del alta no es el que deja el 2.8'
B_CUERPO='no es el de B10 (20261004223253)'
B_FICHA='la ficha del núcleo de la base no es la auditada'
B_COMENTARIO='el comentario del núcleo de la base no es el de B10'
PIEZA28='la pieza private.juicio_cliente_convertido no es la del 2.8 ronda 4'
DEPENDENCIAS='cambió algo que llama a los núcleos o decide su efecto'
LLAMADORES='otro posible llamador de los núcleos'
RESTRICCION='cambió o falta una restricción de crm.leads de la que depende la regla'
TRINQUETES='los private.assert_*() que barre la migración no son los auditados'

# El núcleo del alta (el que deja el 2.8): otro cuerpo; el mismo cuerpo con otro SET; su ACL; su dueño; su comentario.
deriva "el núcleo del alta tenía otro cuerpo" "$(cambia_cuerpo "$N" '-- 9. Con la identidad encendida, la ficha reactivada queda ENLAZADA a su persona (como al nacer y al tomar)')" "$N_CUERPO"
deriva "el núcleo del alta traía otro SET" "$(otro_set "$N")" "$N_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el núcleo del alta" "grant execute on function $N to authenticated;" "$N_FICHA"
deriva "el núcleo del alta había cambiado de dueño (lo hace un superusuario)" "alter function $N owner to supabase_admin;" "$N_FICHA" admin
deriva "el núcleo del alta traía otro comentario" "comment on function $N is 'comentario ajeno';" "$N_COMENTARIO"
# El núcleo de la base (B10): otro cuerpo; otro SET; INVOKER; su ACL; su dueño; su comentario.
deriva "el núcleo de la base tenía otro cuerpo" "$(cambia_cuerpo "$B" '-- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso')" "$B_CUERPO"
deriva "el núcleo de la base traía otro SET" "$(otro_set "$B")" "$B_CUERPO"
deriva "el núcleo de la base había pasado a security invoker" "alter function $B security invoker;" "$B_CUERPO"
deriva "authenticated ya tenía EXECUTE sobre el núcleo de la base" "grant execute on function $B to authenticated;" "$B_FICHA"
deriva "el núcleo de la base había cambiado de dueño (lo hace un superusuario)" "alter function $B owner to supabase_admin;" "$B_FICHA" admin
deriva "el núcleo de la base traía otro comentario" "comment on function $B is 'comentario ajeno';" "$B_COMENTARIO"
# La pieza del 2.8: otro cuerpo, su ACL, su comentario.
deriva "la pieza del 2.8 tenía otro cuerpo" "$(cambia_cuerpo "$P28" '-- 2. Si ningún teléfono casa, el DNI (D-27), con la misma prioridad')" "$PIEZA28"
deriva "authenticated ya tenía EXECUTE sobre la pieza del 2.8" "grant execute on function $P28 to authenticated;" "$PIEZA28"
deriva "la pieza del 2.8 traía otro comentario" "comment on function $P28 is 'comentario ajeno';" "$PIEZA28"
# Ya aplicada: la migración entera; o una función con el nombre de la pieza, con otra firma.
deriva "la migración ya estaba aplicada (reaplicar se niega)" "-- @@MIGRACION@@" "$APLICADA"
deriva "ya existía una private.juicio_cliente_conservado con otra firma" \
  "create function private.juicio_cliente_conservado(p text) returns jsonb language sql stable set search_path = '' as \$f\$ select null::jsonb \$f\$;" "$APLICADA"
# Lo que llama a los núcleos o decide su efecto (las 22 de la lista): otro cuerpo, otro SET o un GRANT.
deriva "la pieza de lo conservado del 2.4 tenía otro cuerpo" "$(cambia_cuerpo 'private.alta_reactivar_bloqueo_conservado(uuid)' '-- Un lead ACTIVO con esos datos que el verificador no califica como bloqueo por sí solo')" "$DEPENDENCIAS"
deriva "el alta tenía otro cuerpo" "$(cambia_cuerpo 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)' '-- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,')" "$DEPENDENCIAS"
deriva "la puerta del documento tenía otro cuerpo" "$(cambia_cuerpo 'crm.crear_lead_documento_fn(jsonb,text,text)' '-- Antes de contactos/fila se bloquea la identidad existente, SIN crearla')" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre crm.reactivar_lead_base_v2" "grant execute on function crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text) to anon;" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre crm.reactivar_lead_base" "grant execute on function crm.reactivar_lead_base(uuid,uuid,text) to anon;" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre crm.registrar_intento_base_v2" "grant execute on function crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text) to anon;" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre crm.registrar_intento_base" "grant execute on function crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone) to anon;" "$DEPENDENCIAS"
deriva "el núcleo de reactivar sin capital tenía otro cuerpo" "$(cambia_cuerpo 'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)' '-- B10: la definición vive en private.base_gestion_reactivar_capital_core')" "$DEPENDENCIAS"
deriva "el núcleo del intento con capital tenía otro cuerpo" "$(cambia_cuerpo 'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)' '-- B10 (E8): con el capital del intento (obligatorio si el lead no lo tiene: lo exige el núcleo de reactivar)')" "$DEPENDENCIAS"
deriva "el núcleo del intento sin capital traía otro SET" "$(otro_set 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)')" "$DEPENDENCIAS"
deriva "la reapertura tenía otro cuerpo" "$(cambia_cuerpo 'crm.reabrir_lead_fn(uuid)' '-- F2.b [D-15]: la puerta del botón «Reabrir» del CRM (analista, supervisor o Gerencia, sobre un lead de su ámbito)')" "$DEPENDENCIAS"
deriva "el ámbito de la base traía otro SET" "$(otro_set 'private.base_gestion_lead_visible(uuid,text,uuid,uuid)')" "$DEPENDENCIAS"
deriva "el rol de la base traía otro SET" "$(otro_set 'private.base_gestion_rol(uuid)')" "$DEPENDENCIAS"
deriva "private.bloquear_contactos_lead traía otro SET (la clave del candado)" "$(otro_set 'private.bloquear_contactos_lead(text[],text[])')" "$DEPENDENCIAS"
deriva "private.normalizar_telefono tenía otra regla (los 9 dígitos ya no ganan el +51)" \
  "create or replace function private.normalizar_telefono(p text) returns text language sql immutable set search_path = '' as \$f\$ select case when p is null or btrim(p) = '' then p else '+' || regexp_replace(p, '[^0-9]', '', 'g') end \$f\$;" \
  "$DEPENDENCIAS"
deriva "private.juicio_persona traía otro SET" "$(otro_set 'private.juicio_persona(uuid,uuid)')" "$DEPENDENCIAS"
deriva "private.inversionista_canonica traía otro SET" "$(otro_set 'private.inversionista_canonica(uuid)')" "$DEPENDENCIAS"
deriva "private.juicio_reapertura tenía otro cuerpo" "$(cambia_cuerpo 'private.juicio_reapertura(uuid,text,text)' '-- Un CLIENTE del Portal con ese documento, aunque esté inactivo y sin ficha de persona, ya es cliente (Codex v3 M2)')" "$DEPENDENCIAS"
deriva "private.persona_vetada traía otro SET" "$(otro_set 'private.persona_vetada(uuid)')" "$DEPENDENCIAS"
deriva "anon ya tenía EXECUTE sobre private.rol_crm" "grant execute on function private.rol_crm(uuid) to anon;" "$DEPENDENCIAS"
deriva "el verificador (2 argumentos) tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text)'::regprocedure), 'null::uuid', '(null)::uuid'); end \$d\$;" \
  "$DEPENDENCIAS"
deriva "el verificador (3 argumentos) traía otro SET" "$(otro_set 'private.verificar_disponibilidad_lead_impl(text,text,uuid)')" "$DEPENDENCIAS"
# Otro LLAMADOR de los núcleos (el cambio lo alcanzaría): por su cuerpo, en minúsculas y en MAYÚSCULAS; por pg_depend (vista, función
# SQL BEGIN ATOMIC); un trabajo programado; y otro llamador del núcleo del alta.
LLAMADOR_PLPGSQL="create function private.ensayo_2_11_llamador() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return private.base_gestion_reactivar_capital_core(null, null, null, null, null, null); end \$f\$;"
LLAMADOR_MAYUSCULAS="create function private.ensayo_2_11_llamador_mayusculas() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return PRIVATE.BASE_GESTION_REACTIVAR_CAPITAL_CORE(null, null, null, null, null, null); end \$f\$;"
deriva "otra función PL/pgSQL llama al núcleo de la base" "$LLAMADOR_PLPGSQL" "$LLAMADORES"
deriva "otra función lo llama en MAYÚSCULAS (PRIVATE.BASE_GESTION_REACTIVAR_CAPITAL_CORE)" "$LLAMADOR_MAYUSCULAS" "$LLAMADORES"
deriva "una vista usa el núcleo de la base" "create view private.ensayo_2_11_vista as select private.base_gestion_reactivar_capital_core(null, null, null, null, null, null) as r;" "$LLAMADORES"
deriva "una función SQL BEGIN ATOMIC usa el núcleo de la base" \
  "create function private.ensayo_2_11_atomica() returns jsonb language sql volatile begin atomic select private.base_gestion_reactivar_capital_core(null, null, null, null, null, null); end;" \
  "$LLAMADORES"
deriva "un trabajo programado (cron.job.command) nombra el núcleo de la base" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9211001, 'ensayo-2-11-llamador-del-nucleo', '0 3 * * *', 'select private.base_gestion_reactivar_capital_core(null, null, null, null, null, null)');" \
  "$LLAMADORES"
deriva "otra función PL/pgSQL llama al núcleo del alta" \
  "create function private.ensayo_2_11_otra_alta() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return private.alta_reactivar_retirado(null, null, null, null, null, null, null, null); end \$f\$;" \
  "$LLAMADORES"
# Ronda 3 (Codex r1, P2): algo que ya NOMBRA la pieza nueva antes de que exista (un trabajo programado; una función escrita de antemano,
# que PL/pgSQL deja crear aunque la pieza no exista).
CRON_PIEZA="insert into cron.job (jobid, jobname, schedule, command) values (9211003, 'ensayo-2-11-nombra-la-pieza', '0 3 * * *', 'select private.juicio_cliente_conservado(null::uuid)');"
deriva "un trabajo programado (cron.job.command) ya nombra la PIEZA NUEVA antes de aplicar" "$CRON_PIEZA" "$LLAMADORES"
deriva "otra función PL/pgSQL ya nombra la PIEZA NUEVA antes de aplicar" \
  "create function private.ensayo_2_11_pieza_previa() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return private.juicio_cliente_conservado(null::uuid); end \$f\$;" \
  "$LLAMADORES"
# Las premisas de la comparación literal: los CHECK del alternativo y del DNI, quitados o cambiados.
deriva "el CHECK leads_telefono_alternativo_formato estaba quitado" "alter table crm.leads drop constraint leads_telefono_alternativo_formato;" "$RESTRICCION"
deriva "el CHECK leads_telefono_alternativo_formato era otro (y sin validar)" \
  "alter table crm.leads drop constraint leads_telefono_alternativo_formato, add constraint leads_telefono_alternativo_formato check (telefono_alternativo is null or telefono_alternativo ~ '^\\+[0-9]{8,15}\$') not valid;" \
  "$RESTRICCION"
deriva "el CHECK leads_dni_check estaba quitado" "alter table crm.leads drop constraint leads_dni_check;" "$RESTRICCION"
# Los trinquetes que barre: uno con otro cuerpo; uno de más.
deriva "un trinquete tenía otro cuerpo" "$(cambia_cuerpo 'private.assert_tareas_pendientes_base()' 'La policy de lectura de tareas, tal cual se auditó el 19/09/2026')" "$TRINQUETES"
deriva "había un trinquete de más" "create function private.assert_ensayo_2_11() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" "$TRINQUETES"

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
    sql = quitar(sql, "  -- Nadie más llama a los dos núcleos (el cambio lo alcanzaría)",
                 "  -- Las premisas de la comparación literal de la pieza del 2.8")
    if que == 'llamadores-ambos':
        sql = quitar(sql, "  -- Nadie más que los dos núcleos usa la pieza, y los llamadores de los núcleos son los de antes",
                     "  select string_agg(e.nombre, ', ' order by e.nombre) into v_mal")
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
  "create function private.assert_ensayo_2_11() returns text language sql stable set search_path = '' as \$f\$ select 'ok'::text \$f\$;" ""
mutante_preflight MP2 "Mutante del preflight SIN la búsqueda de llamadores: otro llamador aborta en el POSTFLIGHT (dos capas)" llamadores-preflight \
  "$LLAMADOR_PLPGSQL" "otro objeto usa la pieza o los núcleos"
mutante_preflight MP3 "Mutante SIN la búsqueda de llamadores en el preflight NI en el postflight: el llamador tiene que COLARSE" llamadores-ambos \
  "$LLAMADOR_PLPGSQL" ""
mutante_preflight MP2c "Mutante del preflight SIN la búsqueda de llamadores: un cron.job que NOMBRA LA PIEZA aborta en el POSTFLIGHT (dos capas; Codex r1 P2)" llamadores-preflight \
  "$CRON_PIEZA" "otro objeto usa la pieza o los núcleos"
mutante_preflight MP3c "Mutante SIN la búsqueda en el preflight NI en el postflight: el cron.job que nombra la pieza tiene que COLARSE" llamadores-ambos \
  "$CRON_PIEZA" ""

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
    else echo "  ✓ control: sin deriva, la reversa entra, devuelve los dos núcleos de antes y quita la pieza"; fi
  else
    echo "  ✗ LA REVERSA NO SE COMPORTÓ COMO DEBÍA → $(aborto "$salida")"; fallos=$((fallos + 1))
  fi
}
REV_PIEZA='la pieza no es la que deja la migración'
REV_FICHA='la ficha de la pieza no es la esperada'
REV_COMENTARIO='el comentario de la pieza no es el que deja la migración'
REV_NUCLEO='un núcleo no es el que deja la migración'
REV_COM_NUCLEO='el comentario de un núcleo no es el que deja la migración'
REV_LLAMADOR='otro posible llamador de la pieza'
REV_DEPENDENCIAS='cambió algo que llama a los núcleos o decide su efecto: revisar a mano'
OTRO_DE_LA_PIEZA="create function private.ensayo_2_11_usa_la_pieza() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return private.juicio_cliente_conservado(null); end \$f\$;"
VISTA_DE_LA_PIEZA="create view private.ensayo_2_11_vista_pieza as select private.juicio_cliente_conservado(null::uuid) as r;"
reversa_deriva "control (sin deriva): la reversa entra, devuelve los dos núcleos de antes y quita la pieza" "" ""
reversa_deriva "un SET statement_timeout añadido a la pieza" "$(otro_set "$P")" "$REV_PIEZA"
reversa_deriva "la pieza con otro cuerpo" "$(cambia_cuerpo "$P" '-- La regla del 2.7/2.8 (D-22, D-25, D-27, D-30): esos datos contra el teléfono, el alternativo y el DNI de cada lead CONVERTIDO')" "$REV_PIEZA"
reversa_deriva "un GRANT EXECUTE a authenticated sobre la pieza" "grant execute on function $P to authenticated;" "$REV_FICHA"
reversa_deriva "la pieza cambió de dueño (lo hace un superusuario)" "alter function $P owner to supabase_admin;" "$REV_FICHA" admin
reversa_deriva "el comentario de la pieza cambió" "comment on function $P is 'comentario ajeno';" "$REV_COMENTARIO"
reversa_deriva "el núcleo del alta cambió después" "$(cambia_cuerpo "$N" '-- 9. Con la identidad encendida, la ficha reactivada queda ENLAZADA a su persona (como al nacer y al tomar)')" "$REV_NUCLEO"
reversa_deriva "el núcleo de la base cambió después" "$(cambia_cuerpo "$B" '-- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso')" "$REV_NUCLEO"
reversa_deriva "el comentario del núcleo de la base cambió" "comment on function $B is 'comentario ajeno';" "$REV_COM_NUCLEO"
reversa_deriva "otra función PL/pgSQL usa la pieza" "$OTRO_DE_LA_PIEZA" "$REV_LLAMADOR"
reversa_deriva "otra función la usa en MAYÚSCULAS" \
  "create function private.ensayo_2_11_usa_la_pieza_mayusculas() returns jsonb language plpgsql volatile set search_path = '' as \$f\$ begin return PRIVATE.JUICIO_CLIENTE_CONSERVADO(null); end \$f\$;" \
  "$REV_LLAMADOR"
reversa_deriva "una vista usa la pieza" "$VISTA_DE_LA_PIEZA" "$REV_LLAMADOR"
reversa_deriva "un trabajo programado (cron.job.command) nombra la pieza" \
  "insert into cron.job (jobid, jobname, schedule, command) values (9211002, 'ensayo-2-11-usa-la-pieza', '0 3 * * *', 'select private.juicio_cliente_conservado(null)');" \
  "$REV_LLAMADOR"
reversa_deriva "la reapertura cambió después (una dependencia)" "$(cambia_cuerpo 'crm.reabrir_lead_fn(uuid)' '-- F2.b [D-15]: la puerta del botón «Reabrir» del CRM (analista, supervisor o Gerencia, sobre un lead de su ámbito)')" "$REV_DEPENDENCIAS"

# ── MUTANTES DE LA REVERSA: sin su búsqueda de llamadores de la pieza ─────────────────────────────────────────────────
mutar_reversa() { # mutar_reversa <destino>
  python3 -I - "$DIR/reversa.sql" "$1" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
ini = "  -- Nadie más usa la pieza (su borrado lo rompería): cuerpos de función sin distinguir mayúsculas, pg_depend y cron.job.\n"
fin = "  select string_agg(e.firma, ', ' order by e.firma) into v_mal\n"
if sql.count(ini) != 1:
    sys.exit('MUTANTE DE LA REVERSA NO APLICABLE')
i = sql.index(ini); j = sql.index(fin, i)
open(destino, 'w', encoding='utf-8').write(sql[:i] + sql[j:])
PY
}
if mutar_reversa "$TMP/reversa-sin-llamadores.sql"; then
  echo "RM1. Mutante de la reversa SIN su búsqueda de llamadores: una VISTA que usa la pieza hace fallar el borrado sin CASCADE (dos capas)"
  printf '%s\n' "$VISTA_DE_LA_PIEZA" > "$TMP/rm1.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm1.deriva.sql" --espera "cannot drop function" \
    --reversa-archivo "$TMP/reversa-sin-llamadores.sql" > "$TMP/rm1.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm1.sql"
  if [[ "$(veredicto "$TMP/rm1.salida.txt")" == "VERDE" ]]; then
    echo "  ✓ sin la búsqueda, la reversa aborta igual en el borrado sin rastro → $(aborto "$TMP/rm1.salida.txt")"
  else
    echo "  ✗ RM1 → $(aborto "$TMP/rm1.salida.txt")"; fallos=$((fallos + 1))
  fi
  echo "RM2. Mutante de la reversa SIN su búsqueda de llamadores: una función PL/pgSQL que usa la pieza tiene que COLARSE (queda rota)"
  printf '%s\n' "$OTRO_DE_LA_PIEZA" > "$TMP/rm2.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --reversa-deriva "$TMP/rm2.deriva.sql" --espera "$REV_LLAMADOR" \
    --reversa-archivo "$TMP/reversa-sin-llamadores.sql" > "$TMP/rm2.sql" || exit 1
  ejecuta "$EJECUTAR_SQL" "$TMP/rm2.sql"
  if [[ "$(veredicto "$TMP/rm2.salida.txt")" == "ROJO" ]] && grep -q -E '^la reversa NO abortó' "$TMP/rm2.salida.txt"; then
    echo "  ✓ el mutante muere: sin la búsqueda, la reversa revirtió dejando rota la función que usaba la pieza. Es ella la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: $(aborto "$TMP/rm2.salida.txt")"; fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante de la reversa"; fallos=$((fallos + 2))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: el control entra; las $n derivas abortan en el preflight sin rastro; MP1, MP3 y MP3c mueren, MP2 y MP2c abortan en el postflight; las $((nr - 1)) derivas de la reversa abortan sin rastro y su control entra; RM1 aborta en el borrado y RM2 muere."
  exit 0
fi
echo "DERIVAS: $fallos fallo(s) — hay defensas del preflight o de la reversa sin prueba."
exit 1
