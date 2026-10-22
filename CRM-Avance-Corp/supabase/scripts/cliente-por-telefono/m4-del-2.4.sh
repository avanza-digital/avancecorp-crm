#!/usr/bin/env bash
# EL MUTANTE M4 DEL BLOQUE 2.4 («la rama reactiva convertidos») CON Y SIN EL BLOQUE 2.7 (ronda 2 del 2.7, D-22).
#
# El caso 3d del oráculo del 2.4 (`reactivar-lead-retirado/pruebas.sql`) era el que mataba a M4: un convertido retirado registrado
# con su teléfono y su DNI. Con el 2.7 encima, el alta NUEVA sobre un convertido ya no llega a la rama del 2.4 (la regla del
# teléfono/DNI responde antes), así que 3d lleva ahora un subcaso de REINTENTO sobre una ficha que quedó convertida —el único
# camino que el 2.7 no intercepta— con el mismo prefijo de fallo («3d-convertido-retirado:»), para que M4 siga muriendo con y sin
# el 2.7 y la declaración de `reactivar-lead-retirado/mutantes.sh` siga valiendo sin tocarla.
#
# Este guion lo comprueba en el laboratorio (como los demás: transacciones que terminan en rollback). M4 se construye con los
# MISMOS fragmentos que `reactivar-lead-retirado/mutantes.sh` (el filtro `and l.etapa <> 'convertido'` cinco veces y la
# recomprobación `or v_lead.etapa = 'convertido'`) y se instala sobre el núcleo vivo (el del 2.4, o el del 2.7 si la migración está
# delante), antes del fixture B7 y del oráculo del 2.4:
#   0a/0b  controles: el oráculo del 2.4 sin y con el 2.7 → VERDE
#   1/2    M4 sin y con el 2.7 → ROJO nombrando «FALLO 3d-convertido-retirado:»
# Uso (NUNCA contra producción):
#   EJECUTAR_SQL="<comando que ejecuta un archivo .sql en el banco>" DIR_ENSAYO=<carpeta> bash supabase/scripts/cliente-por-telefono/m4-del-2.4.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL:?EJECUTAR_SQL: comando que ejecuta un archivo .sql en el banco local (nunca producción)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"

DIR=supabase/scripts/cliente-por-telefono
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1
N='private.alta_reactivar_retirado(uuid,uuid,text,text,uuid,uuid,jsonb,jsonb)'

corre() { # corre <archivo.sql> → deja la salida completa en <archivo>.salida.txt
  local codigo
  # shellcheck disable=SC2086  # EJECUTAR_SQL es un comando con sus argumentos
  $EJECUTAR_SQL "$1" > "${1%.sql}.salida.txt" 2>&1
  codigo=$?
  if [[ "$codigo" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($1). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
}
veredicto() { grep -Eo 'ENSAYO (VERDE|ROJO)[^:]*' "$1" | head -n 1; }
nombrados() { grep -Eo '^FALLO [^:]+' "$1" | sort -u | tr '\n' ';' | sed 's/;$//; s/;/ · /g'; }

fallos=0

# M4, con los fragmentos de reactivar-lead-retirado/mutantes.sh (cada uno tiene que aparecer las veces declaradas).
python3 - "$TMP/m4.mutante.sql" "$N" <<'PY'
import sys
salida, firma = sys.argv[1:]
frags = [("and l.etapa <> 'convertido'\n", "", 5), (" or v_lead.etapa = 'convertido'", "", 1)]
sql = []
for vigente, mutado, veces in frags:
    sql.append("""do $mutar$
declare
  v_def text;
  v_veces integer;
begin
  v_def := pg_get_functiondef('%s'::regprocedure);
  v_veces := (length(v_def) - length(replace(v_def, $vigente$%s$vigente$, ''))) / length($vigente$%s$vigente$);
  if v_veces <> %s then
    raise exception 'MUTANTE NO APLICABLE: el fragmento aparece %% veces en %s (debían ser %s)', v_veces;
  end if;
  execute replace(v_def, $vigente$%s$vigente$, $mutado$%s$mutado$);
end;
$mutar$;
""" % (firma, vigente, vigente, veces, firma, veces, vigente, mutado))
open(salida, 'w', encoding='utf-8').write('\n'.join(sql))
PY

control() { # control <nombre> <args del armador>...
  local f="$TMP/$1.sql"
  node "$DIR/armar-ensayo.mjs" "${@:2}" > "$f" || exit 1
  corre "$f"
  local v; v="$(veredicto "${f%.sql}.salida.txt")"
  if [[ "$v" == *"VERDE"* ]]; then echo "  ✓ $1 → $v"; else echo "  ✗ $1 → ${v:-sin veredicto}: $(nombrados "${f%.sql}.salida.txt")"; fallos=$((fallos + 1)); fi
}
mutado() { # mutado <nombre> <args del armador>...
  local f="$TMP/$1.sql" s
  node "$DIR/armar-ensayo.mjs" "${@:2}" --mutante "$TMP/m4.mutante.sql" > "$f" || exit 1
  corre "$f"
  s="${f%.sql}.salida.txt"
  local v; v="$(veredicto "$s")"
  if ! grep -q 'MUTANTE_INSTALADO' "$s"; then
    echo "  ✗ $1 → NO SE PUDO INSTALAR: $(grep -m 1 'ERROR' "$s" | cut -c1-200)"; fallos=$((fallos + 1))
  elif [[ "$v" != *"ROJO"* ]]; then
    echo "  ✗ $1 → MUTANTE SUPERVIVIENTE: ${v:-sin veredicto}"; fallos=$((fallos + 1))
  elif ! awk 'index($0, "FALLO 3d-convertido-retirado:") == 1 { ok = 1 } END { exit ok ? 0 : 1 }' "$s"; then
    echo "  ✗ $1 → ROJO SIN NOMBRAR «FALLO 3d-convertido-retirado:» ($v): $(nombrados "$s")"; fallos=$((fallos + 1))
  else
    echo "  ✓ $1 → muere por su fallo ($v): $(nombrados "$s")"
  fi
}

echo "0. Controles: el oráculo del 2.4 sin mutar"
control "c-sin-2.7" --oraculo-24 --sin-migracion
control "c-con-2.7" --oraculo-24
echo "1. M4 del 2.4 («la rama reactiva convertidos») SIN el 2.7"
mutado "m4-sin-2.7" --oraculo-24 --sin-migracion
echo "2. M4 del 2.4 CON el 2.7 encima"
mutado "m4-con-2.7" --oraculo-24

echo
if [[ "$fallos" -eq 0 ]]; then
  echo "M4 DEL 2.4: los controles salen VERDE y M4 muere nombrando «3d-convertido-retirado:» con y sin el 2.7."
  exit 0
fi
echo "M4 DEL 2.4: $fallos sin el veredicto esperado."
exit 1
