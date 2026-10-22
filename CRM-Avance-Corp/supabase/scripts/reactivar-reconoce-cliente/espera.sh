#!/usr/bin/env bash
# ESPERA ENTRE DOS SESIONES del bloque 2.11 — la reactivación queda serializada con quien toca el mismo número.
#
# La pieza nueva (`private.juicio_cliente_conservado`) toma los candados de contacto de lo que el lead CONSERVA antes de juzgarlo, con
# la MISMA clave que el disparador de disponibilidad: un cliente que se pone a la vez ese número como alternativo (o la conversión de
# un lead con ese número) y la reactivación se esperan, y la regla juzga con lo que el otro confirmó. Aquí se mide con DOS conexiones a
# la vez (cada una en su transacción, las dos con rollback):
#   · sesión A: toma el candado de contacto del número X y lo retiene unos segundos (`armar-ensayo.mjs --espera-a`), mirando en
#     pg_locks si alguien espera por él;
#   · sesión B: la migración REAL y un lead que conserva X (`espera-b.sql`): «pieza» llama a la pieza; «alta», un alta que reactiva una
#     ficha retirada cuyo alternativo es X; «base», `crm.reactivar_lead_base_v2` de un contacto cuyo teléfono es X ⇒ B tiene que ESPERAR
#     a A (tiempo medido en B; la espera vista por A).
# Mutante M15 (la pieza sin el candado): en «pieza» B NO espera (el candado va antes del juicio: es la pieza la que lo toma). En «alta»
# y «base» B esperaría igual en el disparador, al escribir (después de juzgar): por eso el «dónde» lo prueba «pieza».
# RONDA 3 (Codex r1, P3) — el ORDEN candado → juicio, modo «orden» (`espera-orden-b.sql`): un mutante que juzgue ANTES y tome los
# candados después (M17) esperaría igual y pediría las mismas claves (K1). Se distingue SIN confirmar nada: el juicio es lo único de la
# pieza que lee public.perfiles, y Postgres retiene el candado de tabla de cada relación leída hasta el final de la transacción. B llama
# a la pieza en una transacción que no ha tocado perfiles; A, mientras B espera por el candado de X, mira en pg_locks si B ya tiene
# perfiles: con la migración, «no» (el candado fue antes); con M17, «sí» (juzgó antes). B comprueba al terminar que el juicio sí la toma.
# La carrera con COMMIT (que quien llega segundo juzgue con lo que el otro confirmó) se ensaya en la branch (F4.6,
# `f46-contencion-con-commit.sql`): en el laboratorio compartido nada se confirma.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Cada ejecutor con su propio paso:
#   EJECUTAR_SQL_A="python3 …/lab_sql.py --paso espera-a" EJECUTAR_SQL_B="python3 …/lab_sql.py --paso espera-b" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/reactivar-reconoce-cliente/espera.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL_A:?EJECUTAR_SQL_A: comando que ejecuta un .sql en el banco local para la sesión A (nunca producción)}"
: "${EJECUTAR_SQL_B:?EJECUTAR_SQL_B: el mismo ejecutor para la sesión B (otro paso)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"
DIR=supabase/scripts/reactivar-reconoce-cliente
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1
# El md5 del cuerpo de la pieza que SELLA el postflight de la migración: B tiene que ejecutar exactamente ese cuerpo (sin mutante) o
# uno distinto (con mutante).
MIG="$(ls supabase/migrations/*_crm_reactivar_reconoce_cliente.sql)"
PIEZA_MD5="$(grep -B1 'la pieza no quedó exactamente como se ensayó' "$MIG" | grep -o "'[0-9a-f]\{32\}/" | head -n 1 | tr -d "'/")"
[[ "${#PIEZA_MD5}" == "32" ]] || { echo "No encuentro en la migración el md5 que sella la pieza"; exit 1; }
fallos=0
resumen=""

dato() { grep -Eo "$2" "$1" | head -n 1; }
par() { # par <id> <pieza|alta|base|orden> <B debe esperar: sí|no> <perfiles tomada por B mientras esperaba: sí|no|-> [--mutante m]
  local id=$1 via=$2 debe=$3 perf=$4 ca cb pa ms vista perfil perfb md5b res ha hb ok
  shift 4
  echo "$id. vía $via, B debe esperar: $debe$([[ "$perf" != "-" ]] && echo ", perfiles tomada por B mientras esperaba: $perf")"
  node "$DIR/armar-ensayo.mjs" --espera-a > "$TMP/$id.a.sql" || exit 1
  node "$DIR/armar-ensayo.mjs" --espera-b "$via" "$@" > "$TMP/$id.b.sql" || exit 1
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
  perfil="$(dato "$TMP/$id.a.salida.txt" 'perfiles tomada por quien esperaba: (sí|no|-)' | awk '{print $NF}')"
  perfb="$(dato "$TMP/$id.b.salida.txt" 'perfiles tomada al terminar: (sí|no)' | awk '{print $NF}')"
  md5b="$(dato "$TMP/$id.b.salida.txt" 'cuerpo de la pieza \(md5\): [0-9a-f]{32}' | grep -Eo '[0-9a-f]{32}')"
  res="$(dato "$TMP/$id.b.salida.txt" 'resultado de la llamada: [^ ]+' | sed -E 's/^.*: //')"
  ha="$(grep -c 'huella de la base: IGUAL' "$TMP/$id.a.salida.txt")"; hb="$(grep -c 'huella de la base: IGUAL' "$TMP/$id.b.salida.txt")"
  ok=1
  [[ -n "$ms" && -n "$vista" && -n "$md5b" && "$res" == ok:* && "$ha" == "1" && "$hb" == "1" ]] || ok=0
  # Sin mutante, B ejecutó EXACTAMENTE la pieza que sella el postflight; con mutante, otra.
  if [[ "$*" == *--mutante* ]]; then [[ "$md5b" != "$PIEZA_MD5" ]] || ok=0; else [[ "$md5b" == "$PIEZA_MD5" ]] || ok=0; fi
  if [[ "$debe" == "sí" ]]; then
    [[ "$ok" == "1" && "$vista" == "sí" && "${ms:-0}" -ge 1500 ]] || ok=0
  else
    [[ "$ok" == "1" && "$vista" == "no" && "${ms:-99999}" -lt 500 ]] || ok=0
  fi
  # Modo «orden»: lo que A vio de perfiles mientras B esperaba tiene que ser lo esperado, y B tiene que confirmar que el juicio SÍ la toma
  # (si no la tomara, la observación no significaría nada).
  if [[ "$perf" != "-" ]]; then
    [[ "$ok" == "1" && "$perfil" == "$perf" && "$perfb" == "sí" ]] || ok=0
  fi
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ B esperó ${ms} ms · A vio la espera: $vista$([[ "$perf" != "-" ]] && echo " · perfiles tomada por B mientras esperaba: $perfil (al terminar: $perfb)") · pieza $md5b · llamada $res · huellas IGUAL"
  else
    echo "  ✗ NO ES LO ESPERADO: B esperó ${ms:-?} ms · A vio la espera: ${vista:-?} · perfiles mientras esperaba: ${perfil:-?} (al terminar: ${perfb:-?}) · pieza ${md5b:-?} · llamada ${res:-?} · huellas A=$ha B=$hb"
    echo "    (A: $(grep -m1 -E 'ERROR' "$TMP/$id.a.salida.txt" | cut -c1-160)) (B: $(grep -m1 -E 'ERROR' "$TMP/$id.b.salida.txt" | cut -c1-200))"
    fallos=$((fallos + 1))
  fi
  resumen="$resumen$id|$via|$debe|${ms:-?}|${vista:-?}|${perf}|${perfil:-?}|${res:-?}"$'\n'
}

for via in pieza alta base; do
  par "verde-$via" "$via" sí -
done
python3 -I "$DIR/mutantes.py" sql M15 "$TMP/M15.mutante.sql" || { echo "✗ no se pudo construir M15"; exit 1; }
par "m15-pieza" pieza no - --mutante "$TMP/M15.mutante.sql"
# Ronda 3: el ORDEN candado → juicio. Con la migración, B espera y NO tiene perfiles mientras espera; con M17 (juzga antes), B espera
# igual pero YA tiene perfiles: el mutante muere.
par "verde-orden" orden sí no
python3 -I "$DIR/mutantes.py" sql M17 "$TMP/M17.mutante.sql" || { echo "✗ no se pudo construir M17"; exit 1; }
par "m17-orden" orden sí sí --mutante "$TMP/M17.mutante.sql"

echo
echo "pieza sellada por el postflight: $PIEZA_MD5"
echo "id|vía|B debe esperar|espera medida en B (ms)|A vio la espera|perfiles esperada|perfiles vista por A|llamada"
printf '%s' "$resumen"
echo
if [[ "$fallos" -eq 0 ]]; then
  echo "ESPERA: con la migración B espera a A en la pieza, en el alta y en la base; sin el candado de la pieza (M15), la pieza no espera; en el modo orden, con la migración B no tiene perfiles mientras espera (el candado va antes del juicio) y con M17 (juzga antes) sí la tiene: muere."
  exit 0
fi
echo "ESPERA: $fallos par(es) sin el resultado esperado."
exit 1
