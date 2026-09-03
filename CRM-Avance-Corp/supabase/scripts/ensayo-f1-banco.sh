#!/usr/bin/env bash
# ENSAYO F1 EN BANCO — SOLO contra un banco a paridad con produccion (NUNCA prod).
# Prueba el gate G1: reconstruible (aplica desde cero), reversible (rollback) y
# seguro (oraculo). Requisito previo: el banco ya replayado a paridad (203
# migraciones) por el arnes supabase/scripts/banco/ (via 1, replay manual).
#
# Uso:  BANCO='postgresql://postgres.<ref>:<pass>@aws-0-us-east-2.pooler.supabase.com:5432/postgres' \
#       S=/ruta/scratchpad  ./ensayo-f1-banco.sh
#   - BANCO: cadena del POOLER en modo sesion (puerto 5432) del branch.
#   - S: scratchpad con banco-pooler.txt (para el arnes de concurrencia).
set -euo pipefail
: "${BANCO:?exporta BANCO=<pooler del branch, puerto 5432>}"
DIR="$(cd "$(dirname "$0")" && pwd)"
MIG="$DIR/../migrations/20260903160000_crm_f1_identidad_empresas_inversiones.sql"
ORA="$DIR/oraculo-f1-multiempresa.sql"
CONC="$DIR/oraculo-f1-concurrencia.sh"
RB="$DIR/rollback-f1-multiempresa.sql"
PSQL=(psql "$BANCO" -v ON_ERROR_STOP=1 -q -c "set timezone='America/Lima';")

echo "== 0. Verificar paridad minima del banco (203 migraciones + nucleo) =="
"${PSQL[@]}" -c "do \$\$ begin
  if (select count(*) from supabase_migrations.schema_migrations) < 203 then
    raise exception 'El banco no esta a paridad (< 203 migraciones): replayar primero con el arnes banco/';
  end if;
  if to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])') is null then
    raise exception 'Falta el nucleo: el banco no reprodujo el esquema crm';
  end if;
  if to_regclass('crm.inversionistas') is not null then
    raise exception 'F1 ya esta aplicada en el banco: resetear o revertir antes de ensayar';
  end if;
end \$\$;"

echo "== 1. APLICAR F1 (reconstruible, pasada 1) =="
"${PSQL[@]}" -f "$MIG"

echo "== 2. ORACULO de gate (API cerrada, resolver idempotente/unico, PII enmascarada) =="
"${PSQL[@]}" -f "$ORA"

echo "== 3. ORACULO de CONCURRENCIA (N carreras del mismo documento -> una identidad) =="
BANCO="$BANCO" S="${S:-}" bash "$CONC"

echo "== 4. REVERSA (reversible) =="
"${PSQL[@]}" -f "$RB"

echo "== 5. RE-APLICAR F1 (reconstruible tras revertir, pasada 2) =="
"${PSQL[@]}" -f "$MIG"

echo "== 6. REVERSA FINAL (dejar el banco limpio) =="
"${PSQL[@]}" -f "$RB"

echo ""
echo "ENSAYO F1 EN BANCO: VERDE — aplica desde cero (x2), oraculos en verde y reversa limpia."
