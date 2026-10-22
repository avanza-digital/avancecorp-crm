#!/usr/bin/env bash
# ESPERA ENTRE DOS SESIONES del bloque 2.10 — la conversión con el DNI de un cliente antiguo queda serializada detrás de quien tiene el
# candado del DOCUMENTO (otra conversión con ese DNI, el resolver, la puerta del DNI de la ficha): la puerta lo toma ANTES de juzgar y
# absorber. Se mide con DOS conexiones a la vez (cada una en su transacción, las dos con rollback):
#   · sesión A: toma el candado del documento del DNI fijo y lo retiene unos segundos (`armar-ensayo.mjs --espera-a`), mirando en
#     pg_locks si alguien espera por él;
#   · sesión B: las migraciones (2.11, 2.16 y la real) y la preparación de la conversión de un lead nuevo con ese DNI, con un cliente
#     antiguo retirado sembrado (`espera-b.sql`) ⇒ B tiene que ESPERAR a A y, al soltarse, absorber al antiguo.
#   · control: B sola ⇒ no espera.
# La carrera con COMMIT (que quien llega segundo juzgue con lo que el otro confirmó: convertir y editar/retirar el antiguo a la vez) NO se
# puede ensayar en el laboratorio compartido: `f46-contencion-con-commit.sql` es el guion para la branch.
#
# Se corre en el banco Docker local (el laboratorio), NUNCA contra producción. Cada ejecutor con su propio paso:
#   EJECUTAR_SQL_A="python3 …/lab_sql.py --paso espera-a" EJECUTAR_SQL_B="python3 …/lab_sql.py --paso espera-b" \
#     DIR_ENSAYO=<carpeta> bash supabase/scripts/conversion-cliente-antiguo/espera.sh
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
: "${EJECUTAR_SQL_A:?EJECUTAR_SQL_A: comando que ejecuta un .sql en el banco local para la sesión A (nunca producción)}"
: "${EJECUTAR_SQL_B:?EJECUTAR_SQL_B: el mismo ejecutor para la sesión B (otro paso)}"
: "${DIR_ENSAYO:?DIR_ENSAYO: carpeta donde dejar los SQL generados y sus salidas}"
DIR=supabase/scripts/conversion-cliente-antiguo
TMP="$DIR_ENSAYO"
mkdir -p "$TMP" || exit 1
MIG="$(ls supabase/migrations/*_crm_conversion_cliente_antiguo_misma_ficha.sql)"
# El md5 del cuerpo de la puerta que SELLA el postflight de la migración (la línea «crm.preparar_persona_lead_inversion_fn no quedó
# exactamente como se ensayó» va precedida por la huella): B tiene que ejecutar exactamente ese cuerpo.
PUERTA_MD5="$(grep -B1 'crm.preparar_persona_lead_inversion_fn no quedó exactamente como se ensayó' "$MIG" | grep -o "'[0-9a-f]\{32\}/" | head -n 1 | tr -d "'/")"
[[ "${#PUERTA_MD5}" == "32" ]] || { echo "No encuentro en la migración el md5 que sella la puerta"; exit 1; }
fallos=0
resumen=""

dato() { grep -Eo "$2" "$1" | head -n 1; }
par() { # par <id> <con A: sí|no> <B debe esperar: sí|no>
  local id=$1 conA=$2 debe=$3 ca=0 cb pa ms vista visto md5b res hb ok
  echo "$id. sesión A: $conA · B debe esperar: $debe"
  node "$DIR/armar-ensayo.mjs" --espera-b > "$TMP/$id.b.sql" || exit 1
  if [[ "$conA" == "sí" ]]; then
    node "$DIR/armar-ensayo.mjs" --espera-a > "$TMP/$id.a.sql" || exit 1
    # shellcheck disable=SC2086
    $EJECUTAR_SQL_A "$TMP/$id.a.sql" > "$TMP/$id.a.salida.txt" 2>&1 < /dev/null &
    pa=$!
    sleep 1
  fi
  # shellcheck disable=SC2086
  $EJECUTAR_SQL_B "$TMP/$id.b.sql" > "$TMP/$id.b.salida.txt" 2>&1 < /dev/null
  cb=$?
  if [[ "$conA" == "sí" ]]; then wait "$pa"; ca=$?; fi
  if [[ "$ca" -eq 9 || "$cb" -eq 9 ]]; then
    echo "!!! La base cambió durante un ensayo ($id). Se detiene todo: avisar antes de seguir." >&2
    exit 9
  fi
  ms="$(dato "$TMP/$id.b.salida.txt" 'espera de B = [0-9]+ ms' | grep -Eo '[0-9]+')"
  visto="$(dato "$TMP/$id.b.salida.txt" 'candado de A visto antes: (sí|no)' | awk '{print $NF}')"
  res="$(dato "$TMP/$id.b.salida.txt" 'resultado de la llamada: [^ ]+' | sed -E 's/^.*: //')"
  md5b="$(dato "$TMP/$id.b.salida.txt" 'puerta md5\(prosrc\)=[0-9a-f]{32}' | grep -Eo '[0-9a-f]{32}')"
  hb="$(grep -c 'huella de la base: IGUAL' "$TMP/$id.b.salida.txt")"
  vista="-"
  if [[ "$conA" == "sí" ]]; then vista="$(dato "$TMP/$id.a.salida.txt" 'espera vista: (sí|no)' | awk '{print $3}')"; fi
  ok=1
  [[ -n "$ms" && "$res" == ok:absorbido && "$hb" == "1" && "$md5b" == "$PUERTA_MD5" ]] || ok=0
  if [[ "$debe" == "sí" ]]; then
    [[ "$ok" == "1" && "$visto" == "sí" && "$vista" == "sí" && "${ms:-0}" -ge 1500 && "$(grep -c 'huella de la base: IGUAL' "$TMP/$id.a.salida.txt")" == "1" ]] || ok=0
  else
    [[ "$ok" == "1" && "$visto" == "no" && "${ms:-99999}" -lt 500 ]] || ok=0
  fi
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ B esperó ${ms} ms · candado de A visto antes: $visto · A vio la espera: $vista · llamada $res · puerta $md5b · huellas IGUAL"
  else
    echo "  ✗ NO ES LO ESPERADO: B esperó ${ms:-?} ms · candado visto: ${visto:-?} · A vio la espera: ${vista:-?} · llamada ${res:-?} · puerta ${md5b:-?} (esperada $PUERTA_MD5) · huella B=$hb"
    echo "    (B: $(grep -m1 -E 'ERROR' "$TMP/$id.b.salida.txt" | cut -c1-220))"
    fallos=$((fallos + 1))
  fi
  resumen="$resumen$id|A:$conA|B debe esperar:$debe|${ms:-?} ms|visto antes:${visto:-?}|A vio:${vista:-?}|${res:-?}"$'\n'
}

par "verde-documento" sí sí
par "control-sin-a" no no

echo
echo "puerta sellada por el postflight: $PUERTA_MD5"
printf '%s' "$resumen"
echo
if [[ "$fallos" -eq 0 ]]; then
  echo "ESPERA: con A reteniendo el candado del documento, la preparación de la conversión espera y después absorbe; sin A, no espera."
  exit 0
fi
echo "ESPERA: $fallos par(es) sin el resultado esperado."
exit 1
