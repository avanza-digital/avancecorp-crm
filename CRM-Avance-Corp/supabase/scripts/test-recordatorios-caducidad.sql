\set ON_ERROR_STOP on

-- Oráculo autocontenido de private.caducar_recordatorios_disponibilidad()
-- (F3 del plan «lead libre» — condición M2 del auditor-rls, 2026-08-18: el
-- barrido nocturno correría en producción sin que nadie lo hubiera visto
-- ejecutarse jamás con filas). Se ejecuta en un PostgreSQL vacío y desechable:
--   psql -f test-recordatorios-caducidad.sql
-- Monta la frontera mínima con las piezas REALES ancladas por md5 (la lección
-- «ejecutar contra la FORMA real»): private.log_audit_crm al byte de prod y
-- public.audit_log con su forma exacta (fila_id text NULL, usuario_id uuid
-- NULL — de information_schema de prod 2026-08-18); el resto son stubs que
-- solo existen para las guardas de dependencias. Aplica LA MIGRACIÓN REAL F3
-- (con sus propias guardas y el aviso esperado de pg_cron ausente), siembra
-- tres recordatorios (vigente / vencido en gracia / vencido caducado) con el
-- trigger de sellado DESACTIVADO — la siembra fabrica pasado, cosa que el
-- sellado veta a propósito; el sellado ya lo prueba la matriz RLS — y
-- verifica: borra EXACTAMENTE 1, sobreviven los 2 correctos, y el audit del
-- DELETE nace con usuario_id NULL (el mundo del cron) y data_antes completa.
-- Éxito = código 0 y el token RECORDATORIOS_CADUCIDAD_TX_OK al final.

do $$
declare v_rol text;
begin
  foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
    if not exists (select 1 from pg_catalog.pg_roles where rolname = v_rol) then
      execute pg_catalog.format('create role %I nologin', v_rol);
    end if;
  end loop;
end;
$$;

create schema auth;
create schema crm;
create schema private;

-- auth.uid() del mundo real: NULL sin claims — exactamente el mundo del cron.
create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

-- ── Piezas REALES ancladas ───────────────────────────────────────────────────
-- public.audit_log: espejo de la forma de prod (information_schema 2026-08-18).
create table public.audit_log (
  id uuid not null default gen_random_uuid(),
  tabla text not null,
  operacion text not null,
  fila_id text,
  usuario_id uuid,
  ts timestamptz not null default now(),
  data_antes jsonb,
  data_despues jsonb
);

create table public.perfiles (
  id uuid primary key,
  nombre_completo text,
  rol text not null,
  activo boolean not null default true
);

-- private.log_audit_crm: CUERPO VIGENTE DE PRODUCCIÓN (md5 anclado abajo).
create function private.log_audit_crm()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

do $$
declare v_md5 text;
begin
  select md5(p.prosrc) into v_md5
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'log_audit_crm';
  if v_md5 is distinct from '461846328cab450929731c0ca9edd319' then
    raise exception 'log_audit_crm difiere del vigente en prod (md5 %): re-anclar este oráculo', v_md5;
  end if;
end $$;

-- ── Stubs: existen SOLO para las guardas de dependencias de la migración ─────
create table crm.politica_abandono (singleton boolean primary key);
create table crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  tipo text,
  detalle text,
  creado_en timestamptz not null default now()
);
create function private.normalizar_telefono(p text)
returns text language sql immutable set search_path = ''
as $$ select case when p ~ '^\+519[0-9]{8}$' then p else null end $$;
create function private.rol_crm(p uuid)
returns text language sql stable set search_path = ''
as $$ select 'vendedor'::text $$;

-- ── La migración REAL, con sus guardas (pg_cron ausente → notice esperado) ───
\ir ../migrations/20260818045032_crm_lead_libre_f3_recordar.sql

-- ── Siembra: tres destinos, con el sellado desactivado (fabrica PASADO) ──────
insert into public.perfiles (id, nombre_completo, rol)
values ('11111111-1111-1111-1111-111111111111', 'VENDEDOR ORACULO', 'vendedor');

alter table crm.recordatorios_disponibilidad
  disable trigger trg_recordatorios_disponibilidad_00_sellar;

insert into crm.recordatorios_disponibilidad (perfil_id, telefono, recordar_en) values
  ('11111111-1111-1111-1111-111111111111', '+51996600331', now() + interval '7 days'),
  ('11111111-1111-1111-1111-111111111111', '+51996600332', now() - interval '3 days'),
  ('11111111-1111-1111-1111-111111111111', '+51996600333', now() - interval '10 days');

alter table crm.recordatorios_disponibilidad
  enable trigger trg_recordatorios_disponibilidad_00_sellar;

-- ── El barrido, en el mundo del cron (auth.uid() NULL) y sus verdades ────────
do $$
declare
  v_borrados integer;
  v_quedan integer;
  v_audit record;
begin
  if (select auth.uid()) is not null then
    raise exception 'el oráculo debe correr sin claims: auth.uid() tiene que ser NULL';
  end if;

  v_borrados := private.caducar_recordatorios_disponibilidad();
  if v_borrados <> 1 then
    raise exception 'el barrido debía borrar EXACTAMENTE 1 (vencido hace 10 días) y borró %', v_borrados;
  end if;

  select count(*) into v_quedan from crm.recordatorios_disponibilidad;
  if v_quedan <> 2 then
    raise exception 'debían sobrevivir 2 filas (vigente + vencido en gracia) y quedan %', v_quedan;
  end if;
  if exists (
    select 1 from crm.recordatorios_disponibilidad where telefono = '+51996600333'
  ) then
    raise exception 'el vencido hace 10 días sobrevivió al barrido';
  end if;
  if not exists (
    select 1 from crm.recordatorios_disponibilidad where telefono = '+51996600332'
  ) then
    raise exception 'el vencido EN GRACIA (3 días) no debía caducar todavía';
  end if;

  -- El rastro del cron: DELETE auditado con usuario_id NULL y data_antes entera.
  select * into v_audit
  from public.audit_log
  where tabla = 'crm.recordatorios_disponibilidad' and operacion = 'DELETE';
  if v_audit is null then
    raise exception 'el DELETE del barrido no dejó rastro en audit_log';
  end if;
  if v_audit.usuario_id is not null then
    raise exception 'el audit del cron debía firmar usuario_id NULL y trae %', v_audit.usuario_id;
  end if;
  if v_audit.data_antes ->> 'telefono' is distinct from '+51996600333' then
    raise exception 'data_antes no conserva la fila borrada: %', v_audit.data_antes;
  end if;

  -- Idempotencia del barrido: una segunda pasada inmediata no borra nada.
  v_borrados := private.caducar_recordatorios_disponibilidad();
  if v_borrados <> 0 then
    raise exception 'la segunda pasada debía borrar 0 y borró %', v_borrados;
  end if;
end $$;

select 'RECORDATORIOS_CADUCIDAD_TX_OK' as resultado;
