#!/usr/bin/env bash
# ORÁCULO DE CONCURRENCIA F1 — SOLO en el BANCO. Dispara N llamadas SIMULTÁNEAS
# al resolver con el MISMO documento y exige que quede UNA sola identidad.
# Uso: S=/ruta/scratchpad ./oraculo-f1-concurrencia.sh   (lee $S/banco-pooler.txt)
set -euo pipefail
: "${S:?exporta S=/ruta/al/scratchpad con banco-pooler.txt}"
PG="$(cat "$S/banco-pooler.txt")"
TIPO="DNI"; DOC="99887766"; N="${N:-12}"
echo "Sembrando $N llamadas simultáneas resolver($TIPO,$DOC) en el banco…"
# Limpieza previa idempotente del doc de prueba (por si un run anterior lo dejó).
psql "$PG" -v ON_ERROR_STOP=1 -q -c "set timezone='America/Lima';" \
  -c "delete from crm.inversionista_identificadores where documento_normalizado='$DOC';" >/dev/null || true
pids=()
for i in $(seq 1 "$N"); do
  psql "$PG" -qtA -c "set timezone='America/Lima';" \
    -c "select private.inversionista_resolver('$TIPO','$DOC');" >/dev/null 2>&1 &
  pids+=("$!")
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=$((fail+1)); done
echo "Llamadas terminadas (fallos de conexión: $fail)."
read -r INV IDENT < <(psql "$PG" -qtA -F' ' -c "set timezone='America/Lima';" -c "
  select
    (select count(distinct inversionista_id) from crm.inversionista_identificadores where documento_normalizado='$DOC' and estado='vigente'),
    (select count(*) from crm.inversionista_identificadores where documento_normalizado='$DOC' and estado='vigente');")
echo "Identidades distintas para $DOC: $INV ; identificadores vigentes: $IDENT"
if [[ "$INV" == "1" && "$IDENT" == "1" ]]; then
  echo "ORÁCULO CONCURRENCIA F1: VERDE — $N carreras produjeron UNA identidad."
  exit 0
else
  echo "ORÁCULO CONCURRENCIA F1: ROJO — se esperaba 1/1, hubo $INV/$IDENT." >&2
  exit 1
fi
