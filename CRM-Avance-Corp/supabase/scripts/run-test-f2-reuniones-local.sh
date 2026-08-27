#!/bin/bash
# Banco local de F2.5 (Reuniones sobre la tabla-base).
# Uso: run-test-f2-reuniones-local.sh <dir-f1-vivos> <dir-f2-vivos>
set -euo pipefail
VIVOS1="${1:?}"; VIVOS2="${2:?}"
MIGDIR="$(cd "$(dirname "$0")/../migrations" && pwd)"
AQUI="$(cd "$(dirname "$0")" && pwd)"
DB=crm_f25_banco
MD5_PROD="3ea6d18217d1af6c28ba1f68330c6535"

montar() {
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -c "drop database if exists $DB" -c "create database $DB"
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 -d $DB <<'SQL' >/dev/null
create schema crm; create schema private; create schema auth;
create function auth.uid() returns uuid language sql stable
  as 'select nullif(pg_catalog.current_setting(''test.uid'', true), '''')::uuid';
create table public.perfiles (id uuid primary key, nombre_completo text, activo boolean default true);
create table public.contratos (id uuid primary key default gen_random_uuid(), capital numeric,
  moneda text, creado_en timestamptz, fecha_cierre_comercial date);
create table crm.equipo (perfil_id uuid primary key, rol_crm text, supervisor_id uuid, activo boolean default true);
create table crm.leads (id uuid primary key, origen text, perfil_id uuid, contrato_id uuid,
  convertido_en timestamptz, activo boolean default true, etapa text, creado_en timestamptz);
create table crm.tareas (id uuid primary key default gen_random_uuid(), lead_id uuid, vendedor_id uuid,
  tipo text, estado text, activo boolean default true, vence_en timestamptz,
  modalidad_reunion text, cancelada_por text, cancelada_por_id uuid,
  creado_en timestamptz, resultado_reunion text, notas text, titulo text,
  completada_en timestamptz, reprogramada_de uuid);
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
SQL
  for f in private__cierre_externo_anulado private__etiqueta_mes_es private__conversion_mensual_por_vendedor; do
    psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$VIVOS1/$f.sql" >/dev/null
  done
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$VIVOS2/private__peso_referido_conversion.sql" >/dev/null
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB -f "$VIVOS2/private__metricas_reuniones_implementacion.sql" >/dev/null
  local m
  m=$(psql -h 127.0.0.1 -p 5432 -U postgres -X -t -A -d $DB -c "select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='metricas_reuniones_implementacion'")
  if [ "$m" != "$MD5_PROD" ]; then echo "❌ ancla rota: $m ≠ $MD5_PROD"; exit 1; fi
  # PROD tiene la ACL cerrada al owner; el banco lo replica o el postflight
  # fallaria por un artefacto del banco, no por la migracion.
  psql -h 127.0.0.1 -p 5432 -U postgres -X -q -d $DB \
    -c "revoke all on function private.metricas_reuniones_implementacion(date,date) from public;" >/dev/null
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" \
    "$MIGDIR/20260826233000_crm_f1_conversion_episodios.sql" \
    | psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}
aplicar() {
  sed "s/raise exception '[^']*re-capturar[^']*';/null;/" "$1" \
    | psql -h 127.0.0.1 -p 5432 -U postgres -X -q -v ON_ERROR_STOP=1 --single-transaction -d $DB -f - >/dev/null
}

echo "════ F2.5 · CASO REAL ════"
montar
aplicar "$MIGDIR/20260827060000_crm_f2_5_reuniones_nucleo.sql"
psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-reuniones.sql"

echo
echo "════ F2.5 · MUTANTES ════"
T=$(mktemp -d)
declare -a N=(
  "U1 vuelve al numerador muerto (contrato enlazado)"
  "U2 cuenta los cierres anulados"
  "U3 la pierna de cierres se corta en el rango (pierde el de agosto)"
  "U4 no exige que el cierre sea POSTERIOR a la reunion"
)
declare -a S=(
  "s/exists (select 1 from cierres_del_nucleo cn\n               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)\n        as metrica_conversion_contrato/(contrato_id is not null and contrato_creado_en >= vence_en)\n        as metrica_conversion_contrato/"
  "s/where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null/where e.tipo = 'cierre' and e.lead_id is not null/"
  "s/v_ini, greatest(v_fin, v_ahora), null::date/v_ini, v_fin, null::date/"
  "s/and cn.cerrado_en >= base.vence_en/and true/"
)
for i in 0 1 2 3; do
  M="$T/m$i.sql"
  if [ $i -eq 0 ]; then
    python3 - "$MIGDIR/20260827060000_crm_f2_5_reuniones_nucleo.sql" "$M" <<'PY'
import sys, io
s = io.open(sys.argv[1], encoding='utf-8').read()
old = """      exists (select 1 from cierres_del_nucleo cn
               where cn.lead_id = base.lead_id and cn.cerrado_en >= base.vence_en)
        as metrica_conversion_contrato"""
new = """      (contrato_id is not null and contrato_creado_en >= vence_en)
        as metrica_conversion_contrato"""
assert old in s
io.open(sys.argv[2], 'w', encoding='utf-8').write(s.replace(old, new))
PY
  else
    sed "${S[$i]}" "$MIGDIR/20260827060000_crm_f2_5_reuniones_nucleo.sql" > "$M"
  fi
  if cmp -s "$MIGDIR/20260827060000_crm_f2_5_reuniones_nucleo.sql" "$M"; then
    echo "❌ ${N[$i]}: el sed no toco nada"; exit 1; fi
  montar
  set +e
  aplicar "$M" 2>/dev/null
  RCM=$?
  if [ $RCM -ne 0 ]; then set -e; echo "✅ ${N[$i]}: cazado (postflight aborto)"; continue; fi
  SAL=$(psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1 -d $DB -f "$AQUI/test-f2-reuniones.sql" 2>&1); RC=$?
  set -e
  if [ $RC -eq 0 ]; then echo "❌ ${N[$i]}: SOBREVIVIO"; exit 1; fi
  if echo "$SAL" | grep -q "ORACULO"; then echo "✅ ${N[$i]}: cazado"
  else echo "❌ ${N[$i]}: murio por otra cosa:"; echo "$SAL" | tail -3; exit 1; fi
done
rm -rf "$T"
echo
echo "✅ BANCO F2.5 COMPLETO: oraculo + gate + 4/4 mutantes muertos"
