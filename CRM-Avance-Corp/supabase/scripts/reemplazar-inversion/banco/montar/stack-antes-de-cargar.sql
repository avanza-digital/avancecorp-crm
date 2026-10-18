-- Stack local completo (Auth + PostgREST + Storage) para el gate de RLS (test-rls.mjs): lo que el volcado de esquema de
-- producción espera y el stack no trae. Versión reducida de 02-antes-de-cargar.sql: aquí auth.users, auth.uid()/jwt() y
-- storage.objects ya los crean GoTrue y Storage. Ejecutar como supabase_admin, ANTES de cargar el volcado.
\set ON_ERROR_STOP 1
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists hypopg with schema extensions;
create extension if not exists index_advisor with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net;

set role postgres;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'crm_metricas_bridge') then
    create role crm_metricas_bridge nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'crm_gestion_diaria_lector') then
    create role crm_gestion_diaria_lector nologin inherit;
  end if;
end $$;
grant authenticated to crm_gestion_diaria_lector;
grant crm_metricas_bridge to postgres with inherit true, set false;
grant crm_gestion_diaria_lector to postgres with inherit true, set true;
reset role;

alter default privileges for role supabase_admin in schema public revoke all on tables from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on functions from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on sequences from postgres, anon, authenticated, service_role;
