#!/bin/bash
# Banco local de F1 (conversion_episodios): paridad byte a byte del nucleo
# viejo vs nuevo sobre stubs del catalogo, con 4 MUTANTES que prueban que la
# prueba muerde (patron mutantes-para-probar-la-prueba).
#
# Requiere: Postgres local en 127.0.0.1:5432 (usuario postgres) y los fuentes
# VIVOS capturados de prod en $VIVOS (los baja la sesion con la Management API).
#
# Uso: run-test-conversion-episodios-local.sh <dir-fuentes-vivos>
set -euo pipefail
VIVOS="${1:?dir con f1-vivos/*.sql}"
MIG="$(cd "$(dirname "$0")/../migrations" && pwd)/20260826233000_crm_f1_conversion_episodios.sql"
TEST="$(cd "$(dirname "$0")" && pwd)/test-conversion-episodios.sql"
DB=crm_f1_banco
PSQL="psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1"
MD5_NUCLEO_PROD="49601295f0ce72a9ec7d795fc014a60e"

montar() {  # $1 = fichero de migracion a aplicar (original o mutante)
  $PSQL -q -c "drop database if exists $DB" -c "create database $DB"
  $PSQL -q -d $DB <<'SQL'
create schema crm; create schema private; create schema auth;
create or replace function auth.uid() returns uuid language sql as 'select null::uuid';
-- stubs de las DOS tablas que lee la tabla-base (misma forma, sin FKs)
create table crm.lead_asignaciones (
  id uuid default gen_random_uuid(),
  analista_id uuid not null, lead_id uuid not null,
  origen text, motivo_apertura text, aproximado boolean default false,
  asignado_en timestamptz not null, resultado text,
  resultado_en timestamptz, finalizado_en timestamptz);
create table crm.operaciones_cartera (
  id uuid default gen_random_uuid(),
  cliente_id uuid not null, vendedor_id uuid not null, tipo text not null,
  contrato_origen_id uuid, contrato_nuevo_id uuid,
  fecha_operacion date not null, periodo date not null, moneda text not null,
  capital_renovado numeric, capital_adicional numeric,
  elegible_conversion boolean not null, desglose_completo boolean default true,
  fuente text default 'flujo_cartera', creado_por uuid,
  creado_en timestamptz default now());
-- stub del canal de anulacion (cierre_externo_anulado VIVO se apoya aqui)
create table private.anulados_stub (lead_id uuid primary key);
create function private.cierre_anulado(p_lead_id uuid) returns boolean
language sql stable set search_path = ''
as 'select exists (select 1 from private.anulados_stub a where a.lead_id = p_lead_id)';
SQL
  # helpers y nucleo VIVOS, byte a byte
  $PSQL -q -d $DB -f "$VIVOS/private__cierre_externo_anulado.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS/private__etiqueta_mes_es.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS/private__conversion_mensual_por_vendedor.sql" >/dev/null
  # ancla: el banco reproduce el md5 de prod o no vale nada
  local md5_local
  md5_local=$($PSQL -t -A -d $DB -c "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='conversion_mensual_por_vendedor'")
  if [ "$md5_local" != "$MD5_NUCLEO_PROD" ]; then
    echo "❌ ancla rota: nucleo local $md5_local ≠ prod $MD5_NUCLEO_PROD"; exit 1
  fi
  # copia _vieja del nucleo (mismo cuerpo, otro nombre) para comparar
  sed 's/conversion_mensual_por_vendedor(/conversion_mensual_por_vendedor_vieja(/' \
    "$VIVOS/private__conversion_mensual_por_vendedor.sql" | $PSQL -q -d $DB -f - >/dev/null
  # la migracion F1 (reemplaza el nombre real; preflight md5 debe pasar)
  $PSQL -q --single-transaction -d $DB -f "$1" >/dev/null
}

echo "════ CASO REAL: migracion original ════"
montar "$MIG"
$PSQL -d $DB -f "$TEST"

echo
echo "════ MUTANTES (cada uno DEBE romper la paridad o el oraculo) ════"
TMPD=$(mktemp -d)
declare -a NOMBRES=(
  "M1 count sin distinct (doble cierre del mismo lead)"
  "M2 sin filtro de anulados"
  "M3 cartera sin el tope de 1 por cliente/mes"
  "M4 origen del ULTIMO episodio en vez del primero"
)
declare -a SEDS=(
  's/count(distinct c\.lead_id)/count(c.lead_id)/g'
  's/ and not e\.anulado//'
  's/and o\.orden_conversion = 1/and o.orden_conversion >= 1/'
  "s/la\.asignado_en asc))\[1\] = 'referido'/la.asignado_en desc))[1] = 'referido'/"
)
for i in 0 1 2 3; do
  MUT="$TMPD/mutante$i.sql"
  sed "${SEDS[$i]}" "$MIG" > "$MUT"
  if cmp -s "$MIG" "$MUT"; then echo "❌ ${NOMBRES[$i]}: el sed no toco nada"; exit 1; fi
  montar "$MUT"
  set +e
  SALIDA=$($PSQL -d $DB -f "$TEST" 2>&1)
  RC=$?
  set -e
  if [ $RC -eq 0 ]; then
    echo "❌ ${NOMBRES[$i]}: SOBREVIVIO (la prueba no muerde)"; exit 1
  fi
  if echo "$SALIDA" | grep -q "PARIDAD ROTA\|ORACULO ROTO"; then
    echo "✅ ${NOMBRES[$i]}: cazado ($(echo "$SALIDA" | grep -o 'PARIDAD ROTA\|ORACULO ROTO' | head -1))"
  else
    echo "❌ ${NOMBRES[$i]}: murio por OTRA cosa (revisar):"; echo "$SALIDA" | tail -5; exit 1
  fi
done
rm -rf "$TMPD"
echo
echo "✅ BANCO F1 COMPLETO: paridad byte a byte + oraculo + contrato + 4/4 mutantes muertos"
