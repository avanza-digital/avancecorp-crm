#!/bin/bash
# Banco local de F2.1 (pantalla Conversiones sobre la tabla-base).
#
# Monta un mundo minimo (stubs del catalogo + las funciones VIVAS de F1 y sus
# ayudantes), aplica la migracion 2.1 y corre test-f2-conversiones.sql, que
# comprueba con numeros calculados a mano: el numerador ya NO es la columna
# muerta, el bloque `nucleo` cuadra con el nucleo real (sonda de paridad), los
# anulados no cuentan y el referido viaja con su peso (D6).
#
# Despues repite todo con MUTANTES: cada uno neutraliza una defensa y DEBE
# morir (patron mutantes-para-probar-la-prueba).
#
# Uso: run-test-f2-conversiones-local.sh <dir-fuentes-vivos-f1> <dir-vivos-f2>
set -euo pipefail
VIVOS1="${1:?dir con f1-vivos/*.sql}"
VIVOS2="${2:?dir con f2-vivos/*.sql}"
MIGDIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
MIG_F1="$MIGDIR/20260826233000_crm_f1_conversion_episodios.sql"
MIG_F21="$MIGDIR/20260827020000_crm_f2_1_conversiones_nucleo.sql"
TEST="$(cd "$(dirname "$0")" && pwd)/test-f2-conversiones.sql"
DB=crm_f2_banco
PSQL="psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1"
GERENCIA='11111111-1111-4111-8111-111111111111'

montar() {  # $1 = migracion 2.1 a aplicar (original o mutante)
  $PSQL -q -c "drop database if exists $DB" -c "create database $DB"
  $PSQL -q -d $DB <<SQL
create schema crm; create schema private; create schema auth;
-- auth.uid() CONMUTABLE: sin esto el gate de rol jamas se prueba y un mutante
-- que lo borre sobrevive a toda la suite (objecion de Codex, punto 7).
create or replace function auth.uid() returns uuid language sql stable
  as 'select nullif(pg_catalog.current_setting(''test.uid'', true), '''')::uuid';

create table public.perfiles (id uuid primary key, activo boolean not null default true);
create table public.contratos (
  id uuid primary key default gen_random_uuid(), capital numeric, moneda text,
  creado_en timestamptz default now(), fecha_cierre_comercial date);
create table crm.equipo (perfil_id uuid primary key, activo boolean not null default true, rol_crm text not null);
create table crm.leads (
  id uuid primary key, creado_en timestamptz not null, origen text,
  categoria_interes text, etapa text, vendedor_id uuid, asignado_supervisor_id uuid,
  perfil_id uuid, contrato_id uuid, convertido_en timestamptz, creado_por uuid);
create table crm.actividades (lead_id uuid, tipo text, metadata jsonb default '{}'::jsonb);
create table crm.tareas (lead_id uuid, tipo text, estado text);
create table crm.lead_asignaciones (
  id uuid default gen_random_uuid() primary key,
  analista_id uuid not null, lead_id uuid not null,
  origen text not null, motivo_apertura text, aproximado boolean default false,
  asignado_en timestamptz not null, resultado text,
  resultado_en timestamptz, finalizado_en timestamptz);
create table crm.operaciones_cartera (
  id uuid default gen_random_uuid() primary key,
  cliente_id uuid not null, vendedor_id uuid not null, tipo text not null,
  contrato_origen_id uuid, contrato_nuevo_id uuid,
  fecha_operacion date not null, periodo date not null, moneda text not null,
  capital_renovado numeric, capital_adicional numeric,
  elegible_conversion boolean not null, desglose_completo boolean default true,
  fuente text default 'flujo_cartera', creado_por uuid,
  creado_en timestamptz not null default now());
create table crm.conversion_pesos (vigente_desde date primary key, peso_referido numeric not null);
insert into crm.conversion_pesos values ('2026-01-01', 0.15);

create table private.anulados_stub (lead_id uuid primary key);
create function private.cierre_anulado(p_lead_id uuid) returns boolean
language sql stable set search_path = ''
as 'select exists (select 1 from private.anulados_stub a where a.lead_id = p_lead_id)';
create function private.es_lector_global() returns boolean language sql stable as 'select false';
create function private.rol_crm(p uuid) returns text language sql stable set search_path = ''
as 'select e.rol_crm from crm.equipo e where e.perfil_id = p and e.activo';

-- gerencia que ejecuta (auth.uid())
insert into public.perfiles (id) values ('$GERENCIA'::uuid);
insert into crm.equipo (perfil_id, rol_crm) values ('$GERENCIA'::uuid, 'gerencia');
SQL
  $PSQL -q -d $DB -f "$VIVOS1/private__cierre_externo_anulado.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS1/private__etiqueta_mes_es.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS1/private__conversion_mensual_por_vendedor.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS2/private__peso_referido_conversion.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS2/private__metricas_conversiones_implementacion.sql" >/dev/null
  # En PROD estas funciones tienen la ACL cerrada al owner ({postgres=X/postgres});
  # el banco lo replica o el postflight de ACL fallaria por un artefacto del banco.
  $PSQL -q -d $DB -c "revoke all on function private.metricas_conversiones_implementacion(date,date) from public;" >/dev/null
  # F1 (crea la tabla-base y redefine el nucleo); su preflight md5 no aplica en
  # banco: se salta con un stub de anclas ya verificadas en el banco de F1.
  # Las anclas md5 son contra PRODUCCION; en el banco se neutraliza SOLO el
  # aviso de re-captura (el resto de preflight/postflight corre intacto).
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
      "$MIG_F1" | $PSQL -q --single-transaction -d $DB -f - >/dev/null
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
      "$1" | $PSQL -q --single-transaction -d $DB -f - >/dev/null
}

echo "════ CASO REAL: migracion 2.1 original ════"
montar "$MIG_F21"
$PSQL -d $DB -f "$TEST"

echo
echo "════ MUTANTES (cada uno DEBE morir) ════"
TMPD=$(mktemp -d)
declare -a NOMBRES=(
  "M1 vuelve al numerador muerto (contrato_id)"
  "M2 el nucleo cuenta los cierres anulados"
  "M3 el referido pesa 1 en el numerador del nucleo"
  "M4 la cosecha no espera a la maduracion (corta en el rango)"
  "M5 la cartera del mes entero se cuela en un rango parcial"
  "M6 la sonda de convertidos sin cierre mira el conjunto equivocado"
  "M7 se borra el gate de rol (cualquiera veria la pantalla)"
  "M8 el recomputo pierde la cartera (numerador diverge del nucleo)"
)
declare -a SEDS=(
  "s/(cb.id in (select ec.lead_id from ep_cosecha ec)) as h_contrato/(cb.contrato_id is not null) as h_contrato/"
  "s/and not e.anulado and not e.fue_referido)::int as cierres_no_referidos/and not e.fue_referido)::int as cierres_no_referidos/"
  "s/+ v_factor \* coalesce(sum(nv.cierres_referidos), 0)/+ 1 * coalesce(sum(nv.cierres_referidos), 0)/"
  "s/v_cosecha_fin := greatest(v_fin, now());/v_cosecha_fin := v_fin;/"
  "s/     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date/     and (true/"
  "s/and c2.id not in (select ec2.lead_id from ep_cosecha ec2)/and c2.id is not null/"
  "s/    raise exception 'No autorizado' using errcode = '42501';/    null;/"
  "s/count(\*) filter (where e.tipo = 'operacion')::int as operaciones/0::int as operaciones/"
)
for i in 0 1 2 3 4 5 6 7; do
  MUT="$TMPD/mut$i.sql"
  sed "${SEDS[$i]}" "$MIG_F21" > "$MUT"
  if cmp -s "$MIG_F21" "$MUT"; then echo "❌ ${NOMBRES[$i]}: el sed no toco nada"; exit 1; fi
  montar "$MUT"
  set +e
  SALIDA=$($PSQL -d $DB -f "$TEST" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${NOMBRES[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SALIDA" | grep -q "ORACULO ROTO"; then
    echo "✅ ${NOMBRES[$i]}: cazado"
  else
    echo "❌ ${NOMBRES[$i]}: murio por OTRA cosa:"; echo "$SALIDA" | tail -4; exit 1
  fi
done
rm -rf "$TMPD"
echo
echo "✅ BANCO F2.1 COMPLETO: oraculo + gate de rol + sondas + 8/8 mutantes muertos"
