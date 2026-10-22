#!/usr/bin/env bash
# ESPERA ENTRE DOS SESIONES del bloque 2.8 (ronda 4; auditor de permisos r2, P3-4) — la carrera del alternativo, serializada.
#
# El disparador toma candado también por el teléfono ALTERNATIVO viejo y nuevo, con la MISMA clave que el teléfono principal para el
# mismo número. Aquí se mide con DOS conexiones a la vez (cada una en su transacción, las dos con rollback):
#   · sesión A: un CLIENTE pone X como su alternativo (copia del disparador nuevo sobre un clon temporal del cliente: ver
#     `armar-ensayo.mjs --espera-a`) y retiene el candado;
#   · sesión B: la migración REAL y la ficha REAL (`crm.editar_lead_fn`) ponen X como alternativo («alt») o como teléfono («tel») de
#     OTRO lead ⇒ B tiene que ESPERAR a A (tiempo medido en B; la petición en espera, vista por A en pg_locks, con pg_blocking_pids).
# Modos: VERDE (la migración del repo) ⇒ B espera en los dos escenarios; ROJO (la de la ronda 3, si se da MIGRACION_RONDA3) y el
# mutante MK1 (sin el alternativo en el candado del UPDATE) ⇒ B NO espera; el mutante MK2 (el alternativo con OTRA clave, la del
# DNI) ⇒ B espera si pone X como alternativo pero NO si lo pone como teléfono (por eso la clave tiene que ser la MISMA). Las dos
# sesiones imprimen el md5 del cuerpo que ejecutan: tiene que coincidir. La carrera con COMMIT (y el veredicto de quien llega
# segundo) se ensaya en la branch (F4.6).
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Cada ejecutor con su propio paso:
#   EJECUTAR_SQL_A="python3 …/lab_sql.py --paso espera-a" EJECUTAR_SQL_B="python3 …/lab_sql.py --paso espera-b" \
#     DIR_ENSAYO=<carpeta> [MIGRACION_RONDA3=<migración de la ronda 3>] bash supabase/scripts/cliente-no-se-duplica-al-editar/espera.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL_A:?EJECUTAR_SQL_A: comando que ejecuta un .sql en el banco local para la sesión A (nunca producción)}"
: "${EJECUTAR_SQL_B:?EJECUTAR_SQL_B: el mismo ejecutor para la sesión B (otro paso)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"
MIGRACION_RONDA3="${MIGRACION_RONDA3:-}"
DIR=supabase/scripts/cliente-no-se-duplica-al-editar
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1
fallos=0
resumen=""

dato() { grep -Eo "$2" "$1" | head -n 1; }
par() { # par <id> <alt|tel> <sí|no> [opciones del armador: --migracion m · --mutante m]
  local id=$1 esc=$2 debe=$3 ca cb pa ms vista md5a md5b res ha hb ok
  shift 3
  echo "$id. escenario $esc, B debe esperar: $debe"
  node "$DIR/armar-ensayo.mjs" --espera-a "$@" > "$TMP/$id.a.sql" || exit 1
  node "$DIR/armar-ensayo.mjs" --espera-b "$esc" "$@" > "$TMP/$id.b.sql" || exit 1
  # shellcheck disable=SC2086  # los ejecutores son comandos con sus argumentos
  $EJECUTAR_SQL_A "$TMP/$id.a.sql" > "$TMP/$id.a.salida.txt" 2>&1 < /dev/null &
  pa=$!
  # shellcheck disable=SC2086
  $EJECUTAR_SQL_B "$TMP/$id.b.sql" > "$TMP/$id.b.salida.txt" 2>&1 < /dev/null
  cb=$?
  wait "$pa"; ca=$?
  if [[ "$ca" -eq 9 || "$cb" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($id). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
  ms="$(dato "$TMP/$id.b.salida.txt" 'espera de B = [0-9]+ ms' | grep -Eo '[0-9]+')"
  vista="$(dato "$TMP/$id.a.salida.txt" 'espera vista: (sí|no)' | awk '{print $3}')"
  md5a="$(dato "$TMP/$id.a.salida.txt" 'nombres reales\): [0-9a-f]{32}' | grep -Eo '[0-9a-f]{32}')"
  md5b="$(dato "$TMP/$id.b.salida.txt" 'disparador real \(md5\): [0-9a-f]{32}' | grep -Eo '[0-9a-f]{32}')"
  res="$(dato "$TMP/$id.b.salida.txt" 'resultado de la edición: [^ |]+' | sed -E 's/^.*: //')"
  ha="$(grep -c 'huella de la base: IGUAL' "$TMP/$id.a.salida.txt")"; hb="$(grep -c 'huella de la base: IGUAL' "$TMP/$id.b.salida.txt")"
  ok=1
  [[ -n "$ms" && -n "$vista" && -n "$md5a" && "$md5a" == "$md5b" && "$res" == "ok" && "$ha" == "1" && "$hb" == "1" ]] || ok=0
  if [[ "$debe" == "sí" ]]; then
    [[ "$ok" == "1" && "$vista" == "sí" && "${ms:-0}" -ge 1500 ]] || ok=0
  else
    [[ "$ok" == "1" && "$vista" == "no" && "${ms:-99999}" -lt 500 ]] || ok=0
  fi
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ B esperó ${ms} ms · A vio la espera: $vista · cuerpos iguales ($md5a) · edición $res · huellas IGUAL"
  else
    echo "  ✗ NO ES LO ESPERADO: B esperó ${ms:-?} ms · A vio la espera: ${vista:-?} · cuerpos A=${md5a:-?} B=${md5b:-?} · edición ${res:-?} · huellas A=$ha B=$hb"
    fallos=$((fallos + 1))
  fi
  resumen="$resumen$id|$esc|$debe|${ms:-?}|${vista:-?}|${md5b:-?}"$'\n'
}

for esc in alt tel; do
  par "verde-$esc" "$esc" sí
done
if [[ -n "$MIGRACION_RONDA3" ]]; then
  for esc in alt tel; do
    par "rojo-r3-$esc" "$esc" no --migracion "$MIGRACION_RONDA3"
  done
else
  echo "(ROJO con la migración de la ronda 3: NO EJECUTADO — falta MIGRACION_RONDA3)"
fi
for m in MK1 MK2; do
  python3 -I "$DIR/mutantes.py" sql "$m" "$TMP/$m.mutante.sql" || { echo "✗ no se pudo construir $m"; fallos=$((fallos + 1)); continue; }
done
for esc in alt tel; do
  par "mk1-$esc" "$esc" no --mutante "$TMP/MK1.mutante.sql"
done
par "mk2-alt" alt sí --mutante "$TMP/MK2.mutante.sql"
par "mk2-tel" tel no --mutante "$TMP/MK2.mutante.sql"

echo
echo "id|escenario|B debe esperar|espera medida en B (ms)|A vio la espera|md5 del cuerpo del disparador"
printf '%s' "$resumen"
echo
if [[ "$fallos" -eq 0 ]]; then
  echo "ESPERA: con la migración B espera a A (alternativo y teléfono); sin la clave del alternativo (ronda 3, MK1) no espera; con otra clave (MK2) solo espera alternativo contra alternativo."
  exit 0
fi
echo "ESPERA: $fallos par(es) sin el resultado esperado."
exit 1
