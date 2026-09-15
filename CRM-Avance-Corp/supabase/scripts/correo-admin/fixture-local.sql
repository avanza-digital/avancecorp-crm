-- Banco SINTÉTICO aislado. Solo las columnas/permisos relevantes al correo.
create schema if not exists crm;
create schema if not exists private;
grant usage on schema crm to authenticated,service_role;
create table public.perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  rol text not null, activo boolean not null default true,
  correo text unique, actualizado_en timestamptz default now(),
  nombre_completo text default 'CLIENTE DE PRUEBA',
  debe_cambiar_password boolean default false
);
alter table public.perfiles enable row level security;
grant all on public.perfiles to service_role;
grant select,update on public.perfiles to authenticated;
create policy perfiles_lectura on public.perfiles for select to authenticated using(true);
create policy perfiles_escritura on public.perfiles for update to authenticated using(true) with check(true);
create function public.es_admin() returns boolean language sql security definer set search_path='' as $$
 select exists(select 1 from public.perfiles where id=auth.uid() and activo and rol in('admin','superadmin'));
$$;
create table crm.audit_log_test(tabla text, operacion text, datos jsonb);
create function private.log_audit_crm() returns trigger language plpgsql security definer set search_path='' as $$
begin
  insert into crm.audit_log_test values(tg_table_name,tg_op,to_jsonb(new));
  return new;
end;
$$;
alter role authenticator set pgrst.db_schemas='public,graphql_public,crm';
notify pgrst,'reload config';
