#!/usr/bin/env bash
# MUTANTES del ensayo del bloque 2.13 — por cada defensa, un mutante que la neutraliza (catálogo en mutantes.py).
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe la regla a propósito, DESPUÉS de instalar la migración real (cuyo
# postflight sella el cuerpo bueno) y antes del oráculo, en la misma transacción que termina en rollback, y se exige que el oráculo
# (`pruebas.sql`) lo GRITE: un mutante solo cuenta como MUERTO si el ensayo sale ROJO y además nombra TODOS los fallos que declara
# («FALLO <caso>»). Un rojo por otra causa —un error de montaje— no prueba la defensa que ese mutante rompe; un mutante que no se
# pudo instalar (su fragmento ya no aparece las veces declaradas) cuenta como superviviente.
#
# (Lo que se rompe ANTES de la migración —la deriva de catálogo que su preflight tiene que rechazar— va en `derivas.sh`.)
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción:
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" DIR_ENSAYO=<carpeta> \
#     bash supabase/scripts/alternativo-cliente-no-toma-lead/mutantes.sh
# DIR_ENSAYO es obligatoria: ahí quedan los SQL generados y sus salidas (este guion no escribe en carpetas temporales).
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/alternativo-cliente-no-toma-lead
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  # (stdin cerrado: el ejecutor del laboratorio usa `docker exec -i` y se comería la lista de mutantes del bucle)
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1 < /dev/null
  codigo=$?
  # 9 = el ejecutor del laboratorio comparó la base antes y después y CAMBIÓ. Un ensayo no escribe: se para todo y se avisa.
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}

veredicto() { grep -Eo 'ENSAYO (VERDE|ROJO)[^:]*' "$1" | head -n 1; }
nombra() { # nombra <salida> <prefijo> → ¿alguna línea empieza por «FALLO <prefijo>»? (comparación literal)
  awk -v p="FALLO $2" 'index($0, p) == 1 { ok = 1 } END { exit ok ? 0 : 1 }' "$1"
}

fallos=0
n=0

echo "0. El ensayo sin mutar debe estar VERDE"
node "$DIR/armar-ensayo.mjs" > "$TMP/base.sql" || exit 1
corre "$TMP/base.sql"
v="$(veredicto "$TMP/base.salida.txt")"
if [[ "$v" == *"VERDE"* ]]; then
  echo "  ✓ base → $v"
else
  echo "  ✗ base → ${v:-sin veredicto} (arreglar el ensayo antes de mutar)"
  fallos=$((fallos + 1))
fi

lista="$(python3 -I "$DIR/mutantes.py" lista)" || { echo "✗ no se pudo leer el catálogo de mutantes"; exit 1; }
while IFS='|' read -r id desc casos <&3; do
  [[ -z "$id" ]] && continue
  n=$((n + 1))
  echo "$n. Mutante $id: $desc"
  if ! python3 -I "$DIR/mutantes.py" sql "$id" "$TMP/$id.mutante.sql"; then
    echo "  ✗ no se pudo construir el mutante"; fallos=$((fallos + 1)); continue
  fi
  node "$DIR/armar-ensayo.mjs" --mutante "$TMP/$id.mutante.sql" > "$TMP/$id.sql" || exit 1
  corre "$TMP/$id.sql"
  salida="$TMP/$id.salida.txt"
  v="$(veredicto "$salida")"
  nombrados="$(grep -Eo '^FALLO [^:]+' "$salida" | sed -E 's/^FALLO ([^ ]{1,40}).*/\1/' | sort -u | tr '\n' ';' | sed 's/;$//; s/;/ · /g')"
  faltan=""
  IFS=';' read -r -a debe <<< "$casos"
  for d in "${debe[@]}"; do
    nombra "$salida" "$d" || faltan="$faltan «FALLO ${d}»"
  done
  # La marca separa «el mutante no se pudo instalar» (no se juzga: cuenta como superviviente) de «el oráculo lo detectó».
  if ! grep -q 'MUTANTE_INSTALADO' "$salida"; then
    echo "  ✗ NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$salida" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"; fallos=$((fallos + 1))
  elif [[ -n "$faltan" ]]; then
    echo "  ✗ ROJO SIN NOMBRAR SU FALLO (falta$faltan): $v: $nombrados"; fallos=$((fallos + 1))
  else
    echo "  ✓ muere por su fallo ($v): $nombrados"
  fi
done 3<<< "$lista"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los $n mutantes murieron, cada uno por su fallo. El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) o sin juzgar — hay defensas sin prueba."
exit 1
