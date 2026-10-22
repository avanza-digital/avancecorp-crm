#!/usr/bin/env bash
# DERIVAS PREVIAS — la migración se niega si el catálogo ya no es el auditado.
#
# Un mutante (`mutantes.sh`) rompe algo DESPUÉS de la migración y exige que el
# oráculo lo grite. Una deriva rompe la ficha ANTES: lo que se prueba aquí es el
# PREFLIGHT de la migración. `create or replace` conserva dueño y ACL, así que
# un EXECUTE concedido de antes sobreviviría al cambio; y con la hora anulable
# o con el trigger recortado la regla no protegería lo que dice. Con cada
# deriva la migración tiene que ABORTAR en su preflight —con el mensaje que le
# corresponde, no con cualquier error— y el candado tiene que quedar con su
# huella original.
#
# El paso 0 es el control: sin deriva, por el mismo envoltorio, la migración
# entra. Sin él, un envoltorio roto daría «abortó» siempre.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción.
# Todo ocurre en transacciones que terminan en rollback:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" \
#     bash supabase/scripts/no-asistio-espera-hora/derivas.sh
# Con DIR_ENSAYO=<carpeta> se conservan ahí los SQL generados y sus salidas; sin
# ella van a una carpeta temporal que se borra al terminar.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"

DIR=supabase/scripts/no-asistio-espera-hora
if [[ -n "${DIR_ENSAYO:-}" ]]; then
  TMP="$DIR_ENSAYO"
  mkdir -p "$TMP" || exit 1
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
fi

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
aborto() { grep -m 1 -E '^la migración (ABORTÓ|NO abortó)' "$1" | cut -c1-200; }

fallos=0
n=0

echo "0. Control: sin deriva, la migración entra por el mismo envoltorio"
: > "$TMP/d0.deriva.sql"
node "$DIR/armar-ensayo.mjs" --deriva "$TMP/d0.deriva.sql" > "$TMP/d0.sql" || exit 1
corre "$TMP/d0.sql"
if [[ "$(veredicto "$TMP/d0.salida.txt")" == "DERIVA VERDE" ]] && grep -q '^la migración NO abortó' "$TMP/d0.salida.txt"; then
  echo "  ✓ control → $(aborto "$TMP/d0.salida.txt")"
else
  echo "  ✗ control → la migración no entró sin deriva: $(grep -m 1 -E 'ERROR|^la migración' "$TMP/d0.salida.txt" | cut -c1-200)"
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
  # La marca separa «la deriva no se pudo instalar» (no se juzga) de «la
  # migración se negó». El veredicto VERDE lo da el propio ensayo: abortó con el
  # texto esperado del preflight Y la huella del candado sigue siendo la original.
  if ! grep -q 'DERIVA_INSTALADA' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR LA DERIVA: $(grep -m 1 'ERROR' "$salida" | cut -c1-160)"
    fallos=$((fallos + 1))
  elif [[ "$(veredicto "$salida")" == "DERIVA VERDE" ]]; then
    echo "  ✓ el preflight se negó y el candado quedó intacto → $(aborto "$salida")"
  else
    echo "  ✗ LA MIGRACIÓN NO SE NEGÓ COMO DEBÍA → $(aborto "$salida")"
    fallos=$((fallos + 1))
  fi
}

# El trigger del candado con otra forma. `drop` + `create` dentro de la
# transacción del ensayo: se deshace con el rollback.
recrear_trigger() { # recrear_trigger <cláusula OF> <cláusula WHEN>
  printf 'drop trigger trg_tareas_00_before_update on crm.tareas;\ncreate trigger trg_tareas_00_before_update before update %s on crm.tareas for each row %s execute function private.trg_tareas_before_update();' "$1" "$2"
}

# D1 — un EXECUTE concedido de antes. `create or replace` lo conservaría y la
# comparación «antes = después» del postflight lo daría por bueno.
deriva "authenticated ya tenía EXECUTE sobre el candado" \
  "grant execute on function private.trg_tareas_before_update() to authenticated;" \
  "Algún rol distinto del dueño tiene EXECUTE sobre el candado de crm.tareas: revisar antes de añadir la regla"

# D2 — el candado ya no era `security definer`.
deriva "el candado ya no era security definer" \
  "alter function private.trg_tareas_before_update() security invoker;" \
  "El candado de crm.tareas no tiene la ficha auditada"

# D3 — el candado traía otra configuración además del `search_path` vacío.
deriva "el candado traía otro SET además del search_path" \
  "alter function private.trg_tareas_before_update() set lock_timeout = '5s';" \
  "El candado de crm.tareas no tiene la ficha auditada"

# D4 — la hora pactada admite NULL: `old.vence_en > reloj` no se cumpliría y
# «No asistió» pasaría en una cita sin hora.
deriva "crm.tareas.vence_en ya admitía NULL" \
  "alter table crm.tareas alter column vence_en drop not null;" \
  "crm.tareas.vence_en no es NOT NULL"

# D5 y D6 — el trigger recortado: con WHEN o con lista de columnas habría UPDATE
# que no pasarían por la regla.
deriva "el trigger del candado tenía cláusula WHEN" \
  "$(recrear_trigger '' 'when (old.estado is distinct from new.estado)')" \
  "El candado ya no cuelga de crm.tareas como se auditó"

deriva "el trigger del candado tenía lista de columnas" \
  "$(recrear_trigger 'of estado' '')" \
  "El candado ya no cuelga de crm.tareas como se auditó"

# D7 — el trigger deshabilitado: la regla quedaría instalada sin proteger nada.
deriva "el trigger del candado estaba deshabilitado" \
  "alter table crm.tareas disable trigger trg_tareas_00_before_update;" \
  "El candado ya no cuelga de crm.tareas como se auditó"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "DERIVAS: las $n abortan en el preflight y dejan la huella original; el control entra."
  exit 0
fi
echo "DERIVAS: $fallos sin el veredicto esperado — el preflight no protege lo que dice."
exit 1
