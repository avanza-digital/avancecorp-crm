\set ON_ERROR_STOP on

-- Esquema minimo, fiel en las columnas que atraviesa C0.1. Las funciones de
-- negocio se extraen de las migraciones canonicas; aqui no se reimplementa su
-- aritmetica.
create schema auth;
create schema crm;
create schema private;

create function auth.uid()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table public.perfiles (
  id uuid primary key,
  nombre_completo text not null,
  nombres text,
  apellidos text,
  correo text,
  rol text not null,
  activo boolean not null default true,
  asesor_perfil_id uuid,
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table public.contratos (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid,
  numero_contrato text,
  capital numeric,
  moneda text,
  categoria text,
  estado text,
  fecha_cierre_comercial date,
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.equipo (
  perfil_id uuid primary key,
  rol_crm text not null,
  supervisor_id uuid,
  activo boolean not null default true,
  capacidad_leads_objetivo integer,
  creado_por uuid,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table crm.leads (
  id uuid primary key default gen_random_uuid(),
  nombre_completo text not null,
  telefono text not null,
  correo text,
  dni text,
  distrito text,
  origen text not null,
  etapa text not null,
  motivo_descarte text,
  monto_estimado numeric,
  moneda text not null,
  categoria_interes text,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  perfil_id uuid,
  contrato_id uuid,
  convertido_en timestamptz,
  nota text,
  activo boolean not null default true,
  creado_por uuid,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table crm.actividades (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid,
  tipo text,
  detalle text,
  metadata jsonb not null default '{}'::jsonb,
  creado_por uuid,
  creado_en timestamptz not null default now()
);

create table crm.lead_asignaciones (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  ciclo_n integer not null,
  episodio_n integer not null,
  analista_id uuid not null,
  motivo_apertura text not null,
  asignado_en timestamptz not null,
  asignado_por uuid,
  supervisor_origen_id uuid,
  monto_estimado numeric,
  moneda text not null,
  origen text not null,
  categoria_interes text,
  finalizado_en timestamptz,
  finalizado_por uuid,
  motivo_cierre text,
  analista_destino_id uuid,
  supervisor_destino_id uuid,
  resultado text,
  resultado_en timestamptz,
  motivo_descarte_cierre text,
  aproximado boolean not null default false,
  sla_global_iniciado_en timestamptz,
  sla_global_aproximado boolean not null default false,
  sla_politica_asignacion_id uuid,
  primera_gestion_limite_en timestamptz,
  primer_contacto_limite_en timestamptz,
  creado_en timestamptz not null default now(),
  unique (lead_id, ciclo_n, episodio_n)
);

create table crm.conversion_pesos (
  vigente_desde date primary key,
  peso_referido numeric not null
);

create table crm.operaciones_cartera (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null,
  vendedor_id uuid not null,
  tipo text not null,
  contrato_origen_id uuid,
  contrato_nuevo_id uuid not null,
  fecha_operacion date not null,
  periodo date not null,
  moneda text not null,
  capital_renovado numeric,
  capital_adicional numeric,
  elegible_conversion boolean not null,
  desglose_completo boolean not null default true,
  fuente text not null,
  creado_por uuid not null,
  creado_en timestamptz not null default now()
);

create table crm.ajustes_mes_cerrado (
  id uuid primary key default gen_random_uuid(),
  vendedor_id uuid not null,
  periodo_origen date not null,
  lead_id uuid not null unique,
  motivo text not null,
  creado_por uuid not null,
  creado_en timestamptz not null default now(),
  numerador numeric not null,
  capital_pen numeric not null default 0,
  capital_usd numeric not null default 0,
  detalle jsonb not null default '[]'::jsonb,
  pendiente_numerador numeric not null,
  pendiente_pen numeric not null default 0,
  pendiente_usd numeric not null default 0,
  pendiente_detalle jsonb not null default '[]'::jsonb,
  saldado_en timestamptz
);

create table crm.cierres_externos (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null,
  vendedor_id uuid not null,
  anulado_en timestamptz
);

create table crm.cierres_avance_anulados (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null unique,
  acreditado_a uuid,
  anulado_en timestamptz not null default now()
);

create table crm.periodos_cerrados (
  periodo date primary key,
  cerrado_en timestamptz not null default now(),
  cerrado_por uuid,
  automatico boolean not null default true,
  ponderacion_referido numeric not null,
  meta_revision integer not null,
  cobertura jsonb not null
);

create table crm.cierre_mes_vendedor (
  periodo date not null,
  vendedor_id uuid not null,
  nombre_completo text not null,
  supervisor_id uuid,
  supervisor_nombre text,
  divisor integer not null,
  divisor_aproximado integer not null default 0,
  divisor_por_motivo jsonb not null default '{}'::jsonb,
  cierres_no_referidos integer not null,
  cierres_referidos integer not null,
  cierres_de_arrastre integer not null,
  numerador numeric not null,
  conversion_pct numeric,
  estado text not null,
  referidos_recibidos integer not null,
  referidos_dados_de_alta integer not null,
  referidos_aporta_pct numeric,
  procedencia jsonb not null default '[]'::jsonb,
  ajuste_numerador numeric not null default 0,
  ajuste_pen numeric not null default 0,
  ajuste_usd numeric not null default 0,
  conversion_objetivo numeric,
  detalles jsonb not null default '[]'::jsonb,
  primary key (periodo, vendedor_id)
);

create table crm.sla_politicas (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique,
  vigente_desde timestamptz not null unique,
  primera_gestion_minutos integer not null,
  primer_contacto_minutos integer not null
);

insert into crm.sla_politicas(
  version, vigente_desde, primera_gestion_minutos, primer_contacto_minutos
) values (1, '-infinity', 1440, 1440);

grant usage on schema crm, private to authenticated, service_role;
revoke all on schema private from public, anon;

-- ACL canonico de cimientos_crm: el oraculo dinamico del banco corre como
-- authenticated y contrasta el roster visible sin elevarse a postgres.
grant select on table crm.equipo to authenticated;
