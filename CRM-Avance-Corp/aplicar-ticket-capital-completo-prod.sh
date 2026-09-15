#!/usr/bin/env bash
# Aplica a PRODUCCIÓN las dos migraciones del ticket de Citas «todo el capital cuenta»
# (decisión de Miguel, 15/09/2026):
#   20260915170017 — re-declara la exención analítica de crm.cierres_externos_fn tras F8
#                    (sin ella, el gate analítico de prod falla y bloquea Citas)
#   20260915170018 — el lector de Citas devuelve TODO el capital del mes por analista
#
# ORDEN: publicar el FRONT antes (el front anterior rechaza filas de capital sin lead).
# Ensayadas en producción dentro de un bloque deshecho el 15/09 (ver MIGRACIONES.md).
#
# Hace TRES cosas y para en la primera que falle:
#   1. aplica los ficheros VERBATIM (mismo byte que el repo), en orden
#   2. los registra en el índice (db query ejecuta pero NO registra)
#   3. comprueba EJECUTANDO como Gerencia — la respuesta de la 1 no es evidencia
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)
M1=supabase/migrations/20260915170017_crm_analitica_exencion_cierres_externos_f8.sql
M2=supabase/migrations/20260915170018_crm_citas_ticket_capital_completo.sql

echo "── 1/3 · aplicando las migraciones ───────────────────────────"
npx --yes supabase@latest db query --linked --file "$M1"
npx --yes supabase@latest db query --linked --file "$M2"

echo "── 2/3 · registrando en el índice ────────────────────────────"
printf "insert into supabase_migrations.schema_migrations(version) values ('20260915170017'),('20260915170018') on conflict do nothing;\n" > "$S/reg.sql"
npx --yes supabase@latest db query --linked --file "$S/reg.sql"

echo "── 3/3 · comprobando (gate + lectura real de septiembre) ─────"
cat > "$S/ver.sql" <<'SQL'
select set_config('request.jwt.claims','{"sub":"bf1c562e-ed08-4cc3-92a8-34f1fa3e9127","role":"authenticated"}',false);
with r as (select private.citas_gerencia_consulta(date '2026-09-01',date '2026-09-30') as j)
select
  (select count(*) from supabase_migrations.schema_migrations where version in ('20260915170017','20260915170018')) as registradas_esperado_2,
  private.assert_analitica_leads_citas() as gate_esperado_ok,
  md5(pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure))<>'4ad2b90baf96b11b63a626122bd5d64b' as lector_cambio_esperado_true,
  (select huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
     from private.analitica_leads_citas_exenciones e join pg_proc p on p.oid=e.objeto::regprocedure
    where e.objeto='private.citas_gerencia_consulta(date,date)') as huella_vigente_esperado_true,
  jsonb_array_length(r.j->'gestion'->'capital') as episodios_capital_sep_esperado_77_o_mas,
  (select count(*) from jsonb_array_elements(r.j->'gestion'->'capital') k where k->>'analista_id'='244439ac-dbc7-4d27-91d1-941c5dbc6dd5') as adelayda_operaciones_esperado_5_o_mas,
  (select sum((k->>'monto')::numeric) from jsonb_array_elements(r.j->'gestion'->'capital') k where k->>'analista_id'='244439ac-dbc7-4d27-91d1-941c5dbc6dd5' and k->>'moneda'='PEN') as adelayda_pen_esperado_230000_o_mas,
  (select count(*) from jsonb_array_elements(r.j->'gestion'->'capital') k where k->>'identidad_persona' is null) as sin_identidad_esperado_0,
  (select count(*) from jsonb_array_elements(r.j->'gestion'->'capital') k where k->>'lead_id' is not null
     and not exists(select 1 from jsonb_array_elements(r.j->'gestion'->'poblacion') p where p->>'lead_id'=k->>'lead_id')) as leads_de_capital_fuera_de_poblacion_esperado_0,
  (select string_agg(distinct kk, ',') from jsonb_array_elements(r.j->'gestion'->'capital') k, jsonb_object_keys(k) kk) as claves
from r;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"
