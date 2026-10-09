#!/usr/bin/env bash
# Monta el banco PROPIO de «categoría por operación» sobre un stack local de Supabase YA arrancado (NUNCA producción).
#
#   1. config.toml propio en <stack>/supabase/ (copia de CRM-Avance-Corp/supabase/config.toml con project_id y puertos
#      propios —p. ej. avancecorp-categoria-20261008, 5600x—, realtime/studio/edge/analytics apagados y sin [functions.*]).
#   2. supabase start --workdir <stack> --ignore-health-check      (sin crm todavía: PostgREST da 503, es lo normal)
#   3. bash montar.sh <contenedor-db> <esquema.sql> <config-carga.sql> <storage-carga.sql>
#        <contenedor-db>      supabase_db_<project_id>
#        <esquema.sql>        supabase db dump --linked --schema public,crm,private --keep-comments (SOLO estructura; lo baja Miguel)
#        <config-carga.sql>   configuración de producción sin personas (24 tablas; la del banco de llamadas del 02/10 sirve)
#        <storage-carga.sql>  buckets y políticas de storage
#   4. psql … -f banco/mundo.sql  →  migración + registrador  →  prueba.sql, mutantes.py, 1-ENSAYO.sql, 2-REAL.sql…
#
# Paridad: el volcado escribe los permisos como diferencia contra el valor por defecto de Postgres. El stack añade sus
# privilegios por defecto en public al crear cada objeto; por eso se retiran MIENTRAS se carga (si no, el banco queda más
# permisivo que producción) y se reponen después. Comprobado el 08/10: `supabase db dump --local` del banco = el volcado de
# producción salvo el orden de dos bloques y la forma de escribir tres CHECK.
set -euo pipefail
C="${1:?contenedor de la base (supabase_db_<project_id>)}"
ESQUEMA="${2:?esquema.sql}"; CONFIG="${3:?config-carga.sql}"; STORAGE="${4:?storage-carga.sql}"
q() { docker exec -i -e PGPASSWORD=postgres "$C" psql -X -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
docker exec -e PGPASSWORD=postgres "$C" psql -X -U supabase_admin -h 127.0.0.1 -d postgres -Atc \
  "select current_setting('app.settings.jwt_secret', true) = 'super-secret-jwt-token-with-at-least-32-characters-long'" | grep -qx t \
  || { echo "ABORTADO: $C no es un banco local de Supabase"; exit 2; }

echo "== 1 · roles, extensiones, pg_cron e historial de migraciones (forma de producción)"
q <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'crm_metricas_bridge') then create role crm_metricas_bridge nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname = 'crm_gestion_diaria_lector') then create role crm_gestion_diaria_lector nologin inherit; end if;
end $$;
grant authenticated to crm_gestion_diaria_lector;
grant crm_metricas_bridge to postgres with inherit true, set true;
grant crm_gestion_diaria_lector to postgres with inherit true, set true;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pg_cron;
grant usage on schema cron to postgres with grant option;
grant all on all tables in schema cron to postgres with grant option;
grant all on all functions in schema cron to postgres with grant option;
grant all on all sequences in schema cron to postgres with grant option;
create schema if not exists supabase_migrations;
create table if not exists supabase_migrations.schema_migrations (version text primary key, statements text[], name text);
alter schema supabase_migrations owner to postgres;
alter table supabase_migrations.schema_migrations owner to postgres;
SQL

echo "== 2 · privilegios por defecto del stack en public, FUERA mientras se carga"
q <<'SQL'
alter default privileges for role postgres in schema public revoke all on functions from postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on tables from postgres, anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on sequences from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on functions from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on tables from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on sequences from postgres, anon, authenticated, service_role;
SQL

echo "== 3 · el volcado de producción (como supabase_admin: puede dar dueño a crm_metricas_bridge)"
LOG="$(mktemp)"
docker exec -i -e PGPASSWORD=postgres "$C" psql -X -U supabase_admin -h 127.0.0.1 -d postgres -q < "$ESQUEMA" > "$LOG" 2>&1 || true
echo "   errores de la carga: $(grep -c 'ERROR' "$LOG" || true) (se esperan 0)"; grep 'ERROR' "$LOG" | sort | uniq -c | head -5 || true

echo "== 4 · privilegios por defecto de supabase_admin en public, como estaban"
q <<'SQL'
alter default privileges for role supabase_admin in schema public grant all on sequences to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on tables to postgres, anon, authenticated, service_role;
SQL

echo "== 5 · configuración (sin personas) y storage"
q < "$CONFIG" > /dev/null
q <<'SQL'
begin;
set local session_replication_role = replica;
-- Filas de configuración que nacieron en migraciones POSTERIORES a la configuración del 02/10.
insert into crm.enfriamiento_politica (motivo, dias) select 'base_cargada', 30
 where not exists (select 1 from crm.enfriamiento_politica where motivo = 'base_cargada');            -- 20261004160034
insert into crm.configuracion_reparto (coordinacion_libre) select true
 where not exists (select 1 from crm.configuracion_reparto);                                           -- 20261007143121
insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion, tope_referidos_pct, nota)
select date '2026-10-01', 1.000, 0.15, 15.00, 'Miguel 2026-10-07: desde octubre el referido que cierra vale 1, con tope del 15 %.'
 where not exists (select 1 from crm.conversion_pesos where vigente_desde = date '2026-10-01');        -- 20261007160937
-- Las dos filas únicas de control que un volcado de solo esquema no trae.
insert into crm.sla_operacion_control(id) values (true) on conflict do nothing;
insert into crm.piloto_f8_control(singleton) values (true) on conflict do nothing;
commit;
SQL
q < "$STORAGE" > /dev/null
q -c "notify pgrst, 'reload schema';"
docker exec -e PGPASSWORD=postgres "$C" psql -X -U supabase_admin -h 127.0.0.1 -d postgres -At -F' | ' -c \
  "select 'funciones crm+private', count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private')"
echo "listo."
