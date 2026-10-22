#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el oráculo lo grite. Una deriva rompe el
# catálogo ANTES: lo que se prueba aquí es el PREFLIGHT de la migración. `create or replace` conserva dueño y ACL, y
# reemplaza el cuerpo que encuentre: sin preflight, un cambio hecho a mano en `crm.crear_lead_si_disponible` (o en el
# verificador o en una pieza de la que depende la rama) se borraría o se daría por bueno sin que nadie lo viera. Con cada
# deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le corresponde, no con cualquier error— y dejar
# el alta, su ACL y su comentario EXACTAMENTE como estaban, y sin núcleo.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración entra. Sin él, un envoltorio roto daría
# «abortó» siempre. Al final va un MUTANTE DEL PREFLIGHT: una copia de la migración sin la comparación de `is_grantable`
# tiene que dejarse colar la deriva «WITH GRANT OPTION» (la migración entra): así se sabe que es esa comparación, y no otra
# cosa, la que protege.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Todo ocurre en transacciones que terminan en
# rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/reactivar-lead-retirado/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin ella van a una carpeta temporal que se
# borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/reactivar-lead-retirado
MIG="$(ls supabase/migrations/*_crm_alta_reactiva_lead_retirado.sql)"
[[ "$(printf '%s\n' "$MIG" | wc -l | tr -d ' ')" == "1" ]] || { echo "Se esperaba UNA migración *_crm_alta_reactiva_lead_retirado.sql"; exit 1; }
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

F='crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)'

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ.
  # Un ensayo no escribe: se para todo y se avisa.
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'DERIVA (VERDE|ROJO)' "$1" | head -n 1; }
aborto() { grep -m 1 -E '^la migración (ABORTÓ|NO abortó)' "$1" | cut -c1-230; }

fallos=0
n=0

echo "0. Control: sin deriva, la migración entra por el mismo envoltorio"
: > "$TMP/d0.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d0.deriva.sql" > "$TMP/d0.sql" || exit 1
corre "$TMP/d0.sql"
if [[ "$(veredicto "$TMP/d0.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d0.salida.txt"; then
  echo "  ✓ control → $(aborto "$TMP/d0.salida.txt")"
else
  echo "  ✗ control → la migración no entró sin deriva: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d0.salida.txt" | cut -c1-230)"
  fallos=$((fallos + 1))
fi

deriva() { # deriva <nombre> <sentencia(s) SQL> <texto del preflight que debe abortar>
  local salida
  n=$((n + 1))
  salida="$TMP/d$n.salida.txt"
  echo "$n. Deriva: $1"
  printf '%s\n' "$2" > "$TMP/d$n.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d$n.deriva.sql" --espera "$3" > "$TMP/d$n.sql" || exit 1
  corre "$TMP/d$n.sql"
  # La marca separa «la deriva no se pudo instalar» (no se juzga) de «la migración se negó». El veredicto VERDE lo da el
  # propio ensayo: abortó con el texto esperado del preflight Y la foto (cuerpo, ACL, comentario, sin núcleo) es idéntica a
  # la de antes de intentar la migración.
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "DERIVA VERDE" ]]; then
    echo "  ✓ el preflight se negó y no dejó rastro → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

CUERPO='crm.crear_lead_si_disponible cambió desde que se auditó'
FICHA='la ficha de crm.crear_lead_si_disponible no es la auditada'
COMENTARIO='el comentario de crm.crear_lead_si_disponible cambió'
VERIFICADOR='no es el fijado por la carga de bases'
PIEZA='cambió una pieza de la que depende la rama'
DISPARADOR='falta o está deshabilitado un disparador'
APLICADA='ya está aplicada'

# D1 — el CUERPO del alta ya no es el auditado (md5 de `prosrc` distinto, aunque sea por un punto en un mensaje).
deriva "crm.crear_lead_si_disponible tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('$F'::regprocedure), 'El nombre es obligatorio', 'El nombre es obligatorio.'); end \$d\$;" \
  "$CUERPO"

# D2 y D3 — el cuerpo es el mismo pero la DEFINICIÓN no: un `SET` añadido, o INVOKER (md5 de `pg_get_functiondef` distinto).
deriva "crm.crear_lead_si_disponible traía otro SET además de search_path y lock_timeout" \
  "alter function $F set statement_timeout = '30s';" \
  "$CUERPO"
deriva "crm.crear_lead_si_disponible había pasado a security invoker" \
  "alter function $F security invoker;" \
  "$CUERPO"

# D4, D5 y D6 — la ACL no es la auditada (no entra en el md5 del cuerpo): anon con EXECUTE, EXECUTE con opción de concesión,
# authenticated sin EXECUTE. `create or replace` los conservaría.
deriva "anon ya tenía EXECUTE sobre el alta" \
  "grant execute on function $F to anon;" \
  "$FICHA"
GRANT_OPTION="grant execute on function $F to authenticated with grant option;"
deriva "authenticated tenía EXECUTE WITH GRANT OPTION sobre el alta" \
  "$GRANT_OPTION" \
  "$FICHA"
deriva "authenticated había perdido EXECUTE sobre el alta" \
  "revoke execute on function $F from authenticated;" \
  "$FICHA"

# D7 — el comentario ya no es el auditado: el nuevo se escribiría encima sin saberlo.
deriva "crm.crear_lead_si_disponible traía otro comentario" \
  "comment on function $F is 'comentario ajeno';" \
  "$COMENTARIO"

# D8 y D9 — el verificador ya no es el que fija la carga de bases: otro cuerpo (3 argumentos) o otra configuración (2 argumentos;
# entra en la huella compuesta aunque el cuerpo sea el mismo).
deriva "el verificador (3 argumentos) tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure), 'Un solo lead TOTAL por persona', 'Un solo lead TOTAL por persona.'); end \$d\$;" \
  "$VERIFICADOR"
deriva "el verificador (2 argumentos) traía un SET lock_timeout" \
  "alter function private.verificar_disponibilidad_lead_impl(text,text) set lock_timeout = '5s';" \
  "$VERIFICADOR"

# D10 y D11 — una pieza de la que depende la rama cambió: el guard de tenencia; el disparador «reabrir solo por RPC».
deriva "private.trg_leads_guard_tenencia tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.trg_leads_guard_tenencia()'::regprocedure), 'Un lead convertido no se puede reabrir', 'Un lead convertido no se puede reabrir.'); end \$d\$;" \
  "$PIEZA"
deriva "private.trg_leads_zz_reapertura_solo_rpc tenía otro cuerpo" \
  "do \$d\$ begin execute replace(pg_get_functiondef('private.trg_leads_zz_reapertura_solo_rpc()'::regprocedure), 'juzgan a la persona y enlazan el lead', 'juzgan a la persona y enlazan el lead.'); end \$d\$;" \
  "$PIEZA"

# D12 — un disparador del que depende la rama estaba deshabilitado.
deriva "el disparador trg_leads_zz_reapertura_solo_rpc estaba deshabilitado" \
  "alter table crm.leads disable trigger trg_leads_zz_reapertura_solo_rpc;" \
  "$DISPARADOR"

# D13 — la migración YA está aplicada: reaplicarla se niega (el núcleo ya existe).
deriva "la migración ya estaba aplicada (reaplicar se niega)" \
  "-- @@MIGRACION@@" \
  "$APLICADA"

# ── MUTANTE DEL PREFLIGHT: sin la comparación de is_grantable, la deriva WITH GRANT OPTION tiene que COLARSE ──────────────
echo "M. Mutante del preflight: una copia de la migración SIN comparar is_grantable tiene que dejar entrar la deriva WITH GRANT OPTION"
if python3 - "$MIG" "$TMP/mig-sin-grantable.sql" <<'PY'
import sys
origen, destino = sys.argv[1:]
sql = open(origen, encoding='utf-8').read()
cambios = [
    # (el alta en el preflight; el núcleo y su pieza en el postflight)
    ("(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)",
     "(select array_agg(a.grantee::regrole::text || ':' || a.privilege_type order by a.grantee::regrole::text)", 3),
    ("is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false']",
     "is distinct from array['authenticated:EXECUTE', 'postgres:EXECUTE']", 1),
    # (el núcleo y su pieza: dos comprobaciones en el postflight)
    ("is distinct from array['postgres:EXECUTE:false']",
     "is distinct from array['postgres:EXECUTE']", 2),
]
for vigente, mutado, veces in cambios:
    n = sql.count(vigente)
    if n != veces:
        sys.exit('MUTANTE DEL PREFLIGHT NO APLICABLE: el fragmento aparece %d veces (debía ser %d): %s' % (n, veces, vigente[:80]))
    sql = sql.replace(vigente, mutado)
open(destino, 'w', encoding='utf-8').write(sql)
PY
then
  printf '%s\n' "$GRANT_OPTION" > "$TMP/mp.deriva.sql"
  node "$DIR/armar-ensayo.mjs" --migracion "$TMP/mig-sin-grantable.sql" --deriva "$TMP/mp.deriva.sql" \
    --espera "$FICHA" > "$TMP/mp.sql" || exit 1
  corre "$TMP/mp.sql"
  if ! grep -q 'DERIVA_INSTALADA' "$TMP/mp.salida.txt"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$TMP/mp.salida.txt" | cut -c1-200)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$TMP/mp.salida.txt")" == "DERIVA ROJO" ]] && grep -q '^la migración NO abortó' "$TMP/mp.salida.txt"; then
    echo "  ✓ el mutante muere: sin comparar is_grantable, la deriva se coló (la migración entró). Es esa comparación la que protege."
  else
    echo "  ✗ MUTANTE SUPERVIVIENTE: el preflight sin is_grantable abortó igualmente → $(aborto "$TMP/mp.salida.txt")"
    fallos=$((fallos + 1))
  fi
else
  echo "  ✗ no se pudo construir el mutante del preflight"
  fallos=$((fallos + 1))
fi

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight y no dejan rastro; el control entra; el mutante del preflight muere."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — el preflight no protege lo que dice."
exit 1
