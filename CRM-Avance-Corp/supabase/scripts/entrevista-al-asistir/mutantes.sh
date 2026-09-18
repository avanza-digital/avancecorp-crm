#!/usr/bin/env bash
# MUTANTES del ensayo — por cada defensa, un mutante que la neutraliza.
#
# Una suite verde puede estar midiendo otra cosa. Aquí se rompe el arreglo a
# propósito y se exige que el oráculo (`pruebas.sql`) lo GRITE: si un mutante
# sobrevive —el ensayo sigue verde con la defensa quitada—, esa defensa NO está
# probada y este guion falla.
#
# Igual que el ensayo, todo termina en rollback: producción no se toca.
#
# Uso:  bash supabase/scripts/entrevista-al-asistir/mutantes.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BASE="$TMP/ensayo.sql"
node supabase/scripts/entrevista-al-asistir/armar-ensayo.mjs > "$BASE" || exit 1

corre() { # corre <archivo> → imprime el veredicto del oráculo en una línea
  npx --yes supabase@2.114.0 db query --linked --file "$1" 2>&1 \
    | tr -d '\n' \
    | sed -e 's/.*ENSAYO /ENSAYO /' -e 's/:.*//' -e 's/\\n.*//'
}

fallos=0

exigir_rojo() { # exigir_rojo <nombre> <archivo>
  local nombre="$1" archivo="$2" veredicto
  veredicto="$(corre "$archivo")"
  if [[ "$veredicto" == *"ROJO"* ]]; then
    echo "  ✓ $nombre → el oráculo lo detectó ($veredicto)"
  else
    echo "  ✗ $nombre → MUTANTE SUPERVIVIENTE: $veredicto"
    fallos=$((fallos + 1))
  fi
}

echo "0. El ensayo sin mutar debe estar VERDE"
veredicto="$(corre "$BASE")"
if [[ "$veredicto" == *"VERDE"* ]]; then
  echo "  ✓ base → $veredicto"
else
  echo "  ✗ base → $veredicto (arreglar el ensayo antes de mutar)"
  fallos=$((fallos + 1))
fi

# M1 — sin validación del capital: una entrevista podría quedar sin cifra, con
# la moneda equivocada o con tres decimales. Deben caer 4a, 4b, 4c, 4d y 4e.
echo "1. Mutante: se borra la validación del capital"
python3 - "$BASE" "$TMP/m1.sql" <<'PY'
import sys
s = open(sys.argv[1]).read()
ini = s.index("  if p_estado = 'completada' and coalesce(p_resultado_reunion, '') <> 'no_interesado' then")
fin = s.index("  -- ¿ES UN REPLAY?")
open(sys.argv[2], 'w').write(s[:ini] + s[fin:])
PY
exigir_rojo "M1 capital sin validar" "$TMP/m1.sql"

# M2 — sin la marca de avance automático: el historial le atribuiría al analista
# un cambio de etapa que él no pidió. Debe caer 1f.
echo "2. Mutante: el avance deja de marcarse como automático"
sed "s/perform set_config('crm.avance_auto', 'on', true);/perform set_config('crm.avance_auto', 'off', true);/" \
  "$BASE" > "$TMP/m2.sql"
exigir_rojo "M2 avance sin marcar" "$TMP/m2.sql"

# M3 — el capital solo se asienta mientras la etapa sube: la SEGUNDA entrevista
# de la misma persona perdería la cifra que el analista acaba de declarar.
# Debe caer 3.
echo "3. Mutante: el capital solo se escribe si la etapa sube"
python3 - "$BASE" "$TMP/m3.sql" <<'PY'
import sys
s = open(sys.argv[1]).read()
viejo = """     and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada');"""
nuevo = """     and l.etapa in ('nuevo', 'contactado', 'reunion_agendada');"""
assert viejo in s, 'el UPDATE cambió: revisar el mutante M3'
open(sys.argv[2], 'w').write(s.replace(viejo, nuevo))
PY
exigir_rojo "M3 capital solo al subir" "$TMP/m3.sql"

# M4 — sin la guarda de replay: repetir la operación con otra cifra reescribe el
# capital mientras se devuelve la respuesta vieja. Debe caer el caso 8.
echo "4. Mutante: el replay vuelve a escribir"
python3 - "$BASE" "$TMP/m4.sql" <<'PY'
import sys
s = open(sys.argv[1]).read()
viejo = "  if coalesce(v_replay, false) then"
assert viejo in s, "la guarda de replay cambió: revisar M4"
open(sys.argv[2], 'w').write(s.replace(viejo, "  if false then", 1))
PY
exigir_rojo "M4 replay que reescribe" "$TMP/m4.sql"

# M5 — sin el fallo ruidoso: un lead que ya no admite entrevista devolvería «ok»
# con el capital perdido en el camino. Debe caer el caso 9.
echo "5. Mutante: el UPDATE que no toca ninguna fila devuelve ok"
python3 - "$BASE" "$TMP/m5.sql" <<'PY'
import sys
s = open(sys.argv[1]).read()
ini = s.index("  if v_filas <> 1 then")
fin = s.index("  select l.etapa into v_etapa from crm.leads l where l.id = p_lead;")
open(sys.argv[2], 'w').write(s[:ini] + s[fin:])
PY
exigir_rojo "M5 exito silencioso" "$TMP/m5.sql"

# M6 — si se exigiera capital también con «no interesado», el analista tendría
# que inventárselo. Debe caer el caso 7.
echo "6. Mutante: «no interesado» también exige capital"
python3 - "$BASE" "$TMP/m6.sql" <<'PY'
import sys
s = open(sys.argv[1]).read()
viejo = "  if p_estado = 'completada' and coalesce(p_resultado_reunion, '') <> 'no_interesado' then"
assert viejo in s, "la excepción de no_interesado cambió: revisar M6"
open(sys.argv[2], 'w').write(s.replace(viejo, "  if p_estado = 'completada' then", 1))
PY
exigir_rojo "M6 no_interesado con capital" "$TMP/m6.sql"

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "MUTANTES: los 6 murieron. El oráculo prueba lo que dice probar."
  exit 0
fi
echo "MUTANTES: $fallos superviviente(s) — hay defensas sin prueba."
exit 1
