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
MIG_F22="$MIGDIR/20260827033000_crm_f2_2_ranking_nucleo.sql"
TEST22="$(cd "$(dirname "$0")" && pwd)/test-f2-ranking.sql"
TEST="$(cd "$(dirname "$0")" && pwd)/test-f2-conversiones.sql"
FIXTURE="$(cd "$(dirname "$0")" && pwd)/fixture-f2-conversion.sql"
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
  perfil_id uuid, contrato_id uuid, convertido_en timestamptz, creado_por uuid,
  -- el ranking exige `activo is true` (espejo de leads_select); la pantalla
  -- Conversiones no lo mira. La columna vive en la tabla real.
  activo boolean not null default true);
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
-- Lo que 2.2 necesita ademas: ambito del supervisor y filtro del desglose.
create table crm.equipo_supervision (supervisor_id uuid, vendedor_id uuid);
create function private.vendedor_ids_visibles(p uuid) returns setof uuid
language sql stable set search_path = ''
as 'select es.vendedor_id from crm.equipo_supervision es where es.supervisor_id = p';
create function private.filtrar_desglose_sujetos_crm(
  p_payload jsonb, p_clave text, p_campo text, p_roles text[]) returns jsonb
language sql stable set search_path = ''
as \$ff\$
  select jsonb_set(p_payload, array[p_clave], coalesce((
    select jsonb_agg(e.value order by e.ord)
    from jsonb_array_elements(p_payload->p_clave) with ordinality e(value, ord)
    where private.rol_crm((e.value->>p_campo)::uuid) = any(p_roles)
  ), '[]'::jsonb), true)
\$ff\$;

-- gerencia que ejecuta (auth.uid())
insert into public.perfiles (id) values ('$GERENCIA'::uuid);
insert into crm.equipo (perfil_id, rol_crm) values ('$GERENCIA'::uuid, 'gerencia');
SQL
  $PSQL -q -d $DB -f "$VIVOS1/private__cierre_externo_anulado.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS1/private__etiqueta_mes_es.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS1/private__conversion_mensual_por_vendedor.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS2/private__peso_referido_conversion.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS2/private__metricas_conversiones_implementacion.sql" >/dev/null
  $PSQL -q -d $DB -f "$VIVOS2/crm__metricas_conversiones_equipo_fn.sql" >/dev/null
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
  $PSQL -q -d $DB -f "$FIXTURE" >/dev/null
}

# El ranking es una RPC publica: en PROD su ACL es {postgres,authenticated}.
montar22() {  # $1 = migracion 2.2 (original o mutante)
  montar "$MIG_F21"
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB \
    -c "do \$r\$ begin if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if; end \$r\$;" >/dev/null
  $PSQL -q -d $DB -c \
    "revoke all on function crm.metricas_conversiones_equipo_fn(date,date) from public;" -c \
    "grant execute on function crm.metricas_conversiones_equipo_fn(date,date) to authenticated;" >/dev/null
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

echo
echo "════ F2.2 · CASO REAL ════"
montar22 "$MIG_F22"
$PSQL -d $DB -f "$TEST22"

echo
echo "════ F2.2 · MUTANTES ════"
TMPD2=$(mktemp -d)
declare -a N22=(
  "R1 vuelve al numerador muerto del ranking (contrato_id)"
  "R2 el ranking pierde el gate de rol"
  "R3 el ranking deja de filtrar el desglose por rol"
  "R4 el nucleo del ranking ignora el ambito (siempre global)"
)
declare -a S22=(
  "s/(l.id in (select ec.lead_id from ep_cosecha ec)) as contrato/(l.contrato_id is not null) as contrato/"
  "s/    raise exception 'No autorizado' using errcode = '42501';/    null;/"
  "s/  return private.filtrar_desglose_sujetos_crm(/  return v_payload; -- /"
  "s/      v_ini, v_fin, v_periodo, v_global, v_visibles, v_factor/      v_ini, v_fin, v_periodo, true, null, v_factor/"
)
for i in 0 1 2 3; do
  MUT="$TMPD2/mut$i.sql"
  sed "${S22[$i]}" "$MIG_F22" > "$MUT"
  if cmp -s "$MIG_F22" "$MUT"; then echo "❌ ${N22[$i]}: el sed no toco nada"; exit 1; fi
  montar22 "$MUT" 2>/dev/null || { echo "✅ ${N22[$i]}: cazado (postflight aborto la migracion)"; continue; }
  set +e
  SAL=$($PSQL -d $DB -f "$TEST22" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${N22[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SAL" | grep -q "ORACULO ROTO"; then echo "✅ ${N22[$i]}: cazado"
  else echo "❌ ${N22[$i]}: murio por OTRA cosa:"; echo "$SAL" | tail -4; exit 1; fi
done
rm -rf "$TMPD2"
echo
echo "✅ BANCO F2.2 COMPLETO: oraculo + ambito + 4/4 mutantes muertos"
