#!/bin/bash
# Banco local de F2.6: el total del mes abierto suma el agregado fuera de
# roster (D8). Autocontenido: el texto VIEJO se extrae del repo
# (20260815003742), cuya fidelidad con prod está anclada por md5(prosrc)
# = 9a5025e4f70c2ee2def4264aae629716 (verificado el 27/08 contra el vivo).
# Las dependencias pesadas van con STUBS: lo que F2.6 cambia es pura
# agregación sobre las filas del núcleo, y el núcleo entra como fixture.
#
# 4 MUTANTES (patrón mutantes-para-probar-la-prueba): cada suma nueva tiene un
# mutante que la neutraliza; si el banco no lo caza, el banco no vale.
#
# Requiere: Postgres local en 127.0.0.1:5432 (usuario postgres).
# Uso: run-test-f2-6-total-fuera-roster-local.sh
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
MIGDIR="$(cd "$AQUI/../migrations" && pwd)"
FUENTE="$MIGDIR/20260815003742_crm_cierre_mes_lectura.sql"
MIG="$MIGDIR/20260827154448_crm_f2_6_total_incluye_fuera_de_roster.sql"
TEST="$AQUI/test-f2-6-total-fuera-roster.sql"
DB=crm_f2_6_banco
PSQL="psql -h 127.0.0.1 -p 5432 -U postgres -X -v ON_ERROR_STOP=1"
MD5_VIEJO="9a5025e4f70c2ee2def4264aae629716"
MD5_NUEVO="c7a7a103d6665acb9231976a3a2fcfa6"
TRABAJO="$(mktemp -d)"
trap 'rm -rf "$TRABAJO"' EXIT

# 1) Extraer el cuerpo viejo del repo y anclarlo por md5
python3 - "$FUENTE" "$TRABAJO" "$MD5_VIEJO" <<'PY'
import hashlib, sys
fuente, trabajo, md5_esp = sys.argv[1], sys.argv[2], sys.argv[3]
src = open(fuente, encoding="utf-8").read()
start = src.index("create or replace function crm.conversion_mensual_fn(p_periodo date)")
a = src.index("as $$", start) + len("as $$")
b = src.index("$$;", a)
body = src[a:b]
assert hashlib.md5(body.encode()).hexdigest() == md5_esp, "ancla rota: el cuerpo del fichero ya no es el texto vivo anclado"
plantilla = """create or replace function crm.%s(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$%s$$;
"""
with open(f"{trabajo}/crea-viejas.sql", "w", encoding="utf-8") as f:
    f.write(plantilla % ("conversion_mensual_sin_cartera_fn", body))
    f.write(plantilla % ("conversion_mensual_sin_cartera_fn_vieja", body))
print("ancla md5 del cuerpo viejo: OK")
PY

# 2) Mutantes: neutralizan una defensa cada uno (y silencian el postflight md5,
#    que si no cazaría al mutante por la razón equivocada)
python3 - "$MIG" "$TRABAJO" <<'PY'
import sys
mig, trabajo = sys.argv[1], sys.argv[2]
src = open(mig, encoding="utf-8").read()
apaga_postflight = ("raise exception 'POSTFLIGHT F2.6: md5", "raise notice 'mutante ignora md5")
mutantes = {
  "m1-sin-numerador": ("+ (select fr.numerador from fuera fr))", "+ 0::numeric)"),
  "m2-sin-analistas": ("+ (select fr.analistas from fuera fr))::int", "+ 0)::int"),
  "m3-sin-motivos":   ("select coalesce(b.divisor_por_motivo, '{}'::jsonb)\n      from base b", "select '{}'::jsonb\n      from base b"),
  "m4-sin-divisor":   ("+ (select fr.divisor from fuera fr))::int as divisor", "+ 0)::int as divisor"),
}
for nombre, (viejo, nuevo) in mutantes.items():
    assert src.count(viejo) == 1, f"{nombre}: blanco no único ({src.count(viejo)})"
    mutado = src.replace(viejo, nuevo).replace(*apaga_postflight)
    open(f"{trabajo}/{nombre}.sql", "w", encoding="utf-8").write(mutado)
print("4 mutantes generados")
PY

montar() {  # $1 = migración a aplicar (la real o un mutante)
  $PSQL -q -c "drop database if exists $DB" -c "create database $DB" >/dev/null
  $PSQL -q -d $DB <<'SQL' >/dev/null
create schema crm; create schema private; create schema auth;
-- identidad fija: una gerencia
create function auth.uid() returns uuid language sql stable
as $$ select '00000000-0000-0000-0000-00000000c0fe'::uuid $$;
create function private.rol_crm(p uuid) returns text language sql stable
  set search_path = '' as $$ select 'gerencia'::text $$;
create function private.es_lector_global() returns boolean language sql stable
  set search_path = '' as $$ select false $$;
create function private.vendedor_ids_visibles(p uuid) returns setof uuid
  language sql stable set search_path = '' as $$ select null::uuid where false $$;
-- mes cerrado: tabla vacía => siempre camino del mes ABIERTO
create table crm.periodos_cerrados (
  periodo date primary key, ponderacion_referido numeric,
  cerrado_en timestamptz, automatico boolean, cobertura jsonb);
-- roster y núcleo como FIXTURES
create table private.roster_stub (vendedor_id uuid, supervisor_id uuid);
create function private.roster_metas_vendedores()
returns table (vendedor_id uuid, supervisor_id uuid)
language sql stable set search_path = ''
as $$ select r.vendedor_id, r.supervisor_id from private.roster_stub r $$;
create function private.vendedores_sin_supervisor()
returns table (vendedor_id uuid, motivo text)
language sql stable set search_path = ''
as $$ select null::uuid, null::text where false $$;
create function private.peso_referido_conversion(p date) returns numeric
  language sql stable set search_path = '' as $$ select 0.15::numeric $$;
create table private.nucleo_stub (
  analista_id uuid, divisor integer, divisor_aproximado integer,
  divisor_por_motivo jsonb, cierres_no_referidos integer,
  cierres_referidos integer, cierres_de_arrastre integer,
  numerador numeric, conversion_pct numeric, procedencia jsonb,
  referidos_recibidos integer, referidos_aporta_pct numeric);
create function private.conversion_mensual_por_vendedor(
  p_ini timestamptz, p_fin timestamptz, p_global boolean,
  p_visibles uuid[], p_factor numeric)
returns table (
  analista_id uuid, divisor integer, divisor_aproximado integer,
  divisor_por_motivo jsonb, cierres_no_referidos integer,
  cierres_referidos integer, cierres_de_arrastre integer,
  numerador numeric, conversion_pct numeric, procedencia jsonb,
  referidos_recibidos integer, referidos_aporta_pct numeric)
language sql stable set search_path = ''
as $$ select * from private.nucleo_stub $$;
-- suelo del ledger: una asignación exacta previa al mes => medible
create table crm.lead_asignaciones (
  lead_id uuid, analista_id uuid, asignado_en timestamptz,
  aproximado boolean default false, resultado text,
  resultado_en timestamptz, finalizado_en timestamptz);
insert into crm.lead_asignaciones (lead_id, analista_id, asignado_en)
values (gen_random_uuid(), gen_random_uuid(), '2026-07-01T12:00:00Z');
-- leads: vacía (alta de referidos 0, sonda 0)
create table crm.leads (
  id uuid, origen text, creado_en timestamptz, creado_por uuid,
  etapa text, convertido_en timestamptz, vendedor_id uuid,
  asignado_supervisor_id uuid);
-- ajuste de meses pagados: vacío por defecto
create table private.ajuste_stub (vendedor_id uuid, numerador numeric, origenes jsonb);
create function private.ajuste_pendiente_por_vendedor()
returns table (vendedor_id uuid, numerador numeric, origenes jsonb)
language sql stable set search_path = ''
as $$ select a.vendedor_id, a.numerador, a.origenes from private.ajuste_stub a $$;
create function private.conversion_con_ajuste(p_bruto numeric, p_pendiente numeric)
returns numeric language sql immutable set search_path = ''
as $$ select greatest(coalesce(p_bruto, 0) - coalesce(p_pendiente, 0), 0) $$;
create function private.etiqueta_mes_es(p date) returns text
  language sql immutable set search_path = '' as $$ select 'agosto 2026'::text $$;
-- identidad: el filtro de sujetos no participa de lo que F2.6 cambia y las
-- DOS versiones pasan por el mismo stub
create function private.filtrar_desglose_sujetos_crm(
  p_payload jsonb, p_clave text, p_campo text, p_roles text[])
returns jsonb language sql stable set search_path = ''
as $$ select p_payload $$;
SQL
  # el texto viejo bajo el nombre real (para el preflight) y bajo _vieja
  $PSQL -q -d $DB -f "$TRABAJO/crea-viejas.sql" >/dev/null
  local md5_local
  md5_local=$($PSQL -t -A -d $DB -c "select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='conversion_mensual_sin_cartera_fn'")
  if [ "$md5_local" != "$MD5_VIEJO" ]; then
    echo "❌ ancla rota en el banco: $md5_local ≠ $MD5_VIEJO"; exit 1
  fi
  $PSQL -q --single-transaction -d $DB -f "$1" >/dev/null
}

echo "── migración real ──"
montar "$MIG"
md5_tras=$($PSQL -t -A -d $DB -c "select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='conversion_mensual_sin_cartera_fn'")
if [ "$md5_tras" != "$MD5_NUEVO" ]; then
  echo "❌ la migración no dejó el texto esperado: $md5_tras ≠ $MD5_NUEVO"; exit 1
fi
$PSQL -d $DB -f "$TEST"

echo "── mutantes (deben FALLAR) ──"
for m in m1-sin-numerador m2-sin-analistas m3-sin-motivos m4-sin-divisor; do
  montar "$TRABAJO/$m.sql"
  if $PSQL -q -d $DB -f "$TEST" >/dev/null 2>&1; then
    echo "❌ el mutante $m SOBREVIVIÓ: esa defensa no está probada"; exit 1
  fi
  echo "✅ mutante $m cazado"
done

echo "BANCO F2.6 ✅ migración verde y 4/4 mutantes cazados"
