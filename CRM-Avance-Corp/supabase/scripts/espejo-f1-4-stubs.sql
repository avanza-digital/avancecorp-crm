-- Espejo mínimo para validar la migración F1.4 (mismos nombres y formas)
create schema if not exists crm;
create schema if not exists private;
create schema if not exists auth;
create schema if not exists cron;
create schema if not exists supabase_migrations;
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
end $$;

create function auth.uid() returns uuid language sql stable as $$ select null::uuid $$;

create table public.perfiles (id uuid primary key, rol text, activo boolean default true);
create table public.audit_log (
  id uuid primary key default gen_random_uuid(), tabla text not null, operacion text not null,
  fila_id text, usuario_id uuid references public.perfiles(id) on delete set null,
  ts timestamptz not null default now(), data_antes jsonb, data_despues jsonb,
  constraint audit_log_operacion_check check (operacion in ('INSERT','UPDATE','DELETE','demo_marca')));
create table supabase_migrations.schema_migrations (version text primary key, name text, statements text[]);

create function private.log_audit_crm()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'crm'
AS $function$
declare
  v_fila uuid;
begin
  v_fila := coalesce(
    (to_jsonb(coalesce(new, old)) ->> 'id')::uuid,
    (to_jsonb(coalesce(new, old)) ->> 'perfil_id')::uuid
  );
  insert into public.audit_log (tabla, operacion, fila_id, usuario_id, data_antes, data_despues)
  values (
    tg_table_schema || '.' || tg_table_name,
    tg_op,
    v_fila,
    (select auth.uid()),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end
  );
  return coalesce(new, old);
end;
$function$
;

create function public.log_audit_change() returns trigger language plpgsql as $$ begin return coalesce(new,old); end $$;

-- Las tres que reciben rastro
create table crm.operaciones_cartera (id uuid primary key default gen_random_uuid(), capital_renovado numeric, periodo date);
create table crm.agenda_ics (perfil_id uuid primary key, token uuid, creado_en timestamptz default now(), rotado_en timestamptz);
create table public.suscripciones_push (id uuid primary key default gen_random_uuid(), cliente_id uuid, endpoint text,
  p256dh text, auth text, dispositivo text, user_agent text, activo boolean default true,
  creado_en timestamptz default now(), actualizado_en timestamptz default now());
-- Las dos exentas
create table crm.usuario_eventos (id bigint generated always as identity primary key, actor_id uuid);
create table public.novedades_leidas (id uuid primary key default gen_random_uuid(), perfil_id uuid);

-- pg_cron de mentira, con la misma superficie que usa la migración
create table cron.job (jobid bigint generated always as identity primary key, jobname text unique,
  schedule text, command text, active boolean default true, username text default current_user);
create function cron.schedule(p_nombre text, p_horario text, p_cmd text) returns bigint
language plpgsql as $$
declare v_id bigint;
begin
  insert into cron.job (jobname, schedule, command) values (p_nombre, p_horario, p_cmd)
  on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
  returning jobid into v_id;
  return v_id;
end $$;
create function cron.unschedule(p_nombre text) returns boolean language sql as $$
  delete from cron.job where jobname = p_nombre returning true $$;

-- perfiles ya tiene su auditor en producción; el espejo lo replica
create trigger trg_audit_perfiles after insert or update or delete on public.perfiles
  for each row execute function public.log_audit_change();

-- Réplica del fallo real que la auditoría encontró: tablas «auditadas» a medias
create table crm.metas_vendedor (id uuid primary key default gen_random_uuid(), meta numeric);
create trigger trg_audit_metas_vendedor after insert on crm.metas_vendedor
  for each row execute function private.log_audit_crm();
create table crm.lead_asignaciones (id uuid primary key default gen_random_uuid(), lead_id uuid);
create trigger trg_audit_lead_asignaciones after insert or update on crm.lead_asignaciones
  for each row execute function private.log_audit_crm();
