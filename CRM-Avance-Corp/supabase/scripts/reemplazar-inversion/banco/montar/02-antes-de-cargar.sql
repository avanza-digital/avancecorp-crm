-- Banco reemplazo-inv (copiado de foto-sla-f2) · lo que el volcado de esquema espera y la imagen 17.6.1.105 no trae igual que producción.
-- Todo leído en producción el 15/10/2026 (catálogo, solo lectura). Ejecutar como supabase_admin, ANTES de cargar.
\set ON_ERROR_STOP 1

-- 1. Extensiones: el mismo conjunto y esquema que producción.
--    La imagen trae pg_graphql instalada; producción NO (sus disparadores de eventos graphql_watch_* no existen allí).
drop extension if exists pg_graphql;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pg_trgm with schema extensions;
create extension if not exists unaccent with schema extensions;
create extension if not exists hypopg with schema extensions;
create extension if not exists index_advisor with schema extensions;
create extension if not exists pg_cron;     -- supautils la deja en pg_catalog, como en producción
create extension if not exists pg_net;      -- en producción: extnamespace public (sus objetos van en el esquema net).
-- Nota: la única función que usa net.http_post (private.despertar_push_tasa) sale antes si el vault no tiene
-- sus secretos, y el vault del banco está vacío: el banco no puede llamar a nada externo.

-- 2. Roles del CRM con la forma EXACTA de producción. Allí los creó postgres (CREATEROLE), por eso postgres
--    tiene además la membresía automática con ADMIN (inherit=false, set=false) concedida por supabase_admin.
set role postgres;
create role crm_metricas_bridge nologin noinherit;
create role crm_gestion_diaria_lector nologin inherit;
grant authenticated to crm_gestion_diaria_lector;                        -- inherit=true set=true grantor=postgres
grant crm_metricas_bridge to postgres with inherit true, set false;      -- como en producción
grant crm_gestion_diaria_lector to postgres with inherit true, set true; -- como en producción
reset role;

-- 3. auth.uid()/role()/email() de producción (leen request.jwt.claim.* Y request.jwt.claims, como PostgREST 14)
--    y auth.jwt(), que la imagen no trae y el CRM usa. Texto idéntico al de producción (se verifica por md5(prosrc)).
create or replace function auth.uid() returns uuid language sql stable as $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;
create or replace function auth.role() returns text language sql stable as $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;
create or replace function auth.email() returns text language sql stable as $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;
set role supabase_auth_admin;   -- como GoTrue en producción: dueño supabase_auth_admin
create or replace function auth.jwt() returns jsonb language sql stable as $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;
reset role;

-- 4. auth.users con las 35 columnas de producción (GoTrue renombró dos y añadió catorce). Solo columnas:
--    los índices y restricciones de auth.users no se copian.
alter table auth.users rename column confirmed_at to email_confirmed_at;
alter table auth.users rename column email_change_token to email_change_token_new;
alter table auth.users
  add column phone text default null::character varying,
  add column phone_confirmed_at timestamptz,
  add column phone_change text default ''::character varying,
  add column phone_change_token character varying(255) default ''::character varying,
  add column phone_change_sent_at timestamptz,
  add column confirmed_at timestamptz generated always as (least(email_confirmed_at, phone_confirmed_at)) stored,
  add column email_change_token_current character varying(255) default ''::character varying,
  add column email_change_confirm_status smallint default 0,
  add column banned_until timestamptz,
  add column reauthentication_token character varying(255) default ''::character varying,
  add column reauthentication_sent_at timestamptz,
  add column is_sso_user boolean not null default false,
  add column deleted_at timestamptz,
  add column is_anonymous boolean not null default false;

-- 5. search_path de supabase_admin con el mismo texto que producción ("$user" sin barra invertida).
alter role supabase_admin set search_path to "$user", public, auth, extensions;

-- 6. Durante la carga, los objetos los crea supabase_admin. Sus privilegios por defecto en public darían a
--    anon/authenticated/service_role permisos que producción no tiene (el volcado solo CONCEDE respecto al
--    valor de fábrica; no revoca lo que añaden estos defaults). Se apagan aquí y se restauran en 03.
alter default privileges for role supabase_admin in schema public revoke all on tables from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on functions from postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public revoke all on sequences from postgres, anon, authenticated, service_role;
