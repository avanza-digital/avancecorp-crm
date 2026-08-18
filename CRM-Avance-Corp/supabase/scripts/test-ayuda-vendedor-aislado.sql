\set ON_ERROR_STOP on

-- Frontera mínima para ejecutar el motor en una base desechable. No reemplaza
-- el oráculo contra el esquema completo: permite comprobar sintaxis, ranking,
-- contrato y ACL sin depender de datos ni migraciones históricas del CRM.

do $bootstrap$
declare
  v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_roles where rolname = v_rol) then
      execute format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$bootstrap$;

create schema auth;
create schema crm;
create schema private;
create schema extensions;

-- Replica el estado actual detectado por el advisor remoto. La migración debe
-- reubicar pg_trgm sin reconstruir ni depender del search_path de la sesión.
create extension pg_trgm with schema public;

grant usage on schema auth, crm to authenticated;
grant usage on schema crm to anon, service_role;

create or replace function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;

grant execute on function auth.uid() to anon, authenticated, service_role;

create table public.perfiles (
  id uuid primary key,
  nombre_completo text not null,
  correo text not null unique,
  rol text not null,
  activo boolean not null default true
);

create table crm.equipo (
  perfil_id uuid primary key references public.perfiles(id),
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true
);

create or replace function private.rol_crm(p_perfil_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select e.rol_crm
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
    and e.activo
    and p.activo
    and e.rol_crm in ('vendedor', 'supervisor', 'gerencia', 'coordinador');
$function$;

\ir ../migrations/20260818034822_crm_ayuda_vendedor_servidor.sql
\ir test-ayuda-vendedor.sql
