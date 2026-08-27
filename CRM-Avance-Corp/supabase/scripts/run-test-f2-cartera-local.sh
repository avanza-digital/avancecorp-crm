#!/bin/bash
# Banco local de F2.4 (la ventana de 45 dias deja de ser METRICA; sigue siendo
# la de la VISTA). Uso: run-test-f2-cartera-local.sh <f1-vivos> <f2-vivos>
set -euo pipefail
V1="${1:?}"; V2="${2:?}"
MIGDIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
AQUI="$(cd "$(dirname "$0")" && pwd)"
DB=crm_f24_banco
MIG="$MIGDIR/20260827070000_crm_f2_4_cartera_metrica_mes.sql"

montar() {
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -c "drop database if exists $DB" -c "create database $DB"
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL' >/dev/null
create schema crm; create schema private; create schema auth;
create function auth.uid() returns uuid language sql stable
  as 'select nullif(pg_catalog.current_setting(''test.uid'', true), '''')::uuid';
create table public.perfiles (id uuid primary key, nombre_completo text, activo boolean default true);
create table public.contratos (id uuid primary key default gen_random_uuid(), capital numeric,
  moneda text, creado_en timestamptz, fecha_cierre_comercial date);
create table crm.equipo (perfil_id uuid primary key, rol_crm text, supervisor_id uuid,
  activo boolean default true, capacidad_leads_objetivo int);
create table crm.leads (id uuid primary key, etapa text, moneda text, monto_estimado numeric,
  vendedor_id uuid, asignado_supervisor_id uuid, creado_en timestamptz, actualizado_en timestamptz,
  convertido_en timestamptz, contrato_id uuid, activo boolean default true, origen text,
  motivo_descarte text, perfil_id uuid);
create table crm.actividades (id uuid primary key default gen_random_uuid(), lead_id uuid,
  tipo text, creado_en timestamptz, creado_por uuid, metadata jsonb);
create table crm.lead_asignaciones (id uuid primary key default gen_random_uuid(), analista_id uuid,
  lead_id uuid, origen text not null, motivo_apertura text, aproximado boolean default false,
  asignado_en timestamptz, resultado text, resultado_en timestamptz, finalizado_en timestamptz);
create table crm.operaciones_cartera (id uuid primary key default gen_random_uuid(), cliente_id uuid,
  vendedor_id uuid, tipo text, fecha_operacion date, periodo date, moneda text,
  capital_renovado numeric, capital_adicional numeric, elegible_conversion boolean,
  creado_en timestamptz not null default now());
create table crm.conversion_pesos (vigente_desde date primary key, peso_referido numeric);
insert into crm.conversion_pesos values ('2026-01-01', 0.15);
create table private.anulados_stub (lead_id uuid primary key);
create function private.cierre_anulado(l uuid) returns boolean language sql stable set search_path=''
  as 'select exists (select 1 from private.anulados_stub a where a.lead_id = l)';
create function private.es_lector_global() returns boolean language sql stable as 'select false';
create function private.rol_crm(p uuid) returns text language sql stable set search_path=''
  as 'select e.rol_crm from crm.equipo e where e.perfil_id = p and e.activo';
create function private.vendedor_ids_visibles(p uuid) returns setof uuid language sql stable
  set search_path='' as 'select e.perfil_id from crm.equipo e where e.perfil_id = p or e.supervisor_id = p';
create function private.puede_operar_reparto_crm() returns boolean language sql stable as 'select false';
SQL
  for f in private__cierre_externo_anulado private__etiqueta_mes_es private__conversion_mensual_por_vendedor; do
    psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$V1/$f.sql" >/dev/null
  done
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$V2/private__peso_referido_conversion.sql" >/dev/null
  for f in crm__metricas_vendedores_fn crm__resumen_cartera_fn crm__series_comerciales_fn; do
    psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$V2/$f.sql" >/dev/null
  done
  # PROD: las tres son {postgres, authenticated}. El banco lo replica o el
  # postflight fallaria por un artefacto del banco.
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB <<'SQL2' >/dev/null
do $r$ begin if not exists (select 1 from pg_roles where rolname='authenticated')
  then create role authenticated; end if; end $r$;
revoke all on function crm.metricas_vendedores_fn() from public;
revoke all on function crm.resumen_cartera_fn() from public;
revoke all on function crm.series_comerciales_fn(integer) from public;
grant execute on function crm.metricas_vendedores_fn() to authenticated;
grant execute on function crm.resumen_cartera_fn() to authenticated;
grant execute on function crm.series_comerciales_fn(integer) to authenticated;
SQL2
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
    "$MIGDIR/20260826233000_crm_f1_conversion_episodios.sql" \
    | psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}
aplicar() {
  # Las anclas md5 son contra PROD; en el banco solo se neutraliza el aviso.
  sed "s/raise exception '% .% viva NO es la esperada (% vs %); re-capturar antes de F2.4',/null; raise notice '% % % %',/" "$1" \
    | psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}

echo "════ F2.4 · CASO REAL ════"
montar; aplicar "$MIG"
psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-cartera.sql"

echo
echo "════ F2.4 · MUTANTES ════"
T=$(mktemp -d)
declare -a N=(
  "C1 la metrica vuelve a contar la cartera visible (45 dias)"
  "C2 el nucleo del mes cuenta los cierres anulados"
  "C3 se borra la ventana de 45 dias de la VISTA (D1 solo cambio la metrica)"
  "C4 series vuelve a decidir cliente por la columna muerta"
)
declare -a S=(
  "s/coalesce(nm.cierres_no_referidos, 0) + coalesce(nm.cierres_referidos, 0)/count(a.id) filter (where a.etapa = 'convertido')::int + 0 * coalesce(nm.cierres_referidos, 0)/"
  "s/where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos/where e.tipo = 'cierre' and not e.fue_referido)::int as cierres_no_referidos/"
  "s/and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)/and true/"
  "s/(cn.lead_id is not null) as es_cliente/(l.contrato_id is not null) as es_cliente/"
)
for i in 0 1 2 3; do
  M="$T/m$i.sql"; sed "${S[$i]}" "$MIG" > "$M"
  if cmp -s "$MIG" "$M"; then echo "❌ ${N[$i]}: el sed no toco nada"; exit 1; fi
  montar; set +e; aplicar "$M" 2>/dev/null; RCM=$?
  if [ $RCM -ne 0 ]; then set -e; echo "✅ ${N[$i]}: cazado (postflight aborto)"; continue; fi
  SAL=$(psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-cartera.sql" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${N[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SAL" | grep -q "ORACULO"; then echo "✅ ${N[$i]}: cazado"
  else echo "❌ ${N[$i]}: murio por otra cosa:"; echo "$SAL" | tail -3; exit 1; fi
done
rm -rf "$T"
echo
echo "✅ BANCO F2.4 COMPLETO: metrica al mes + vista intacta + 4/4 mutantes muertos"
