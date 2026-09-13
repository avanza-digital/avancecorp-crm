-- Banco desechable: tablas mínimas y Auth simulado. Las funciones de negocio
-- se cargan SIN cambios desde la captura saneada del catálogo de producción.
do $$ begin
  if current_database()<>'citas_integracion_20260908' then
    raise exception 'Sólo banco local aislado de Citas';
  end if;
end $$;
create schema crm;
create schema private;
create schema auth;
create role authenticated nologin;
create role anon nologin;
create role service_role nologin;
create function auth.uid() returns uuid language sql stable as
  'select nullif(current_setting(''request.jwt.claim.sub'',true),'''')::uuid';
create table public.perfiles(id uuid primary key,activo boolean default true,nombre_completo text,rol text);
create table crm.equipo(perfil_id uuid primary key,activo boolean default true,rol_crm text,supervisor_id uuid);
create table crm.leads(id uuid primary key default gen_random_uuid(),creado_en timestamptz default now(),
  nombre_completo text not null,telefono text not null,monto_estimado numeric not null,
  origen text not null default 'referido',moneda text not null default 'PEN',alta_manual boolean default false,
  etapa text default 'nuevo',perfil_id uuid,contrato_id uuid,convertido_en timestamptz,vendedor_id uuid,activo boolean default true);
create table crm.tareas(id uuid primary key default gen_random_uuid(),lead_id uuid,vendedor_id uuid,perfil_id uuid,
  asignado_supervisor_id uuid,tipo text,estado text default 'pendiente',vence_en timestamptz not null,titulo text,
  modalidad_reunion text,resultado_reunion text,cancelada_por text,cancelada_por_id uuid,activo boolean default true,
  creado_en timestamptz default now(),nota text,detalle_cierre_reunion text,motivo_no_realizada text,
  reagendada_de uuid,resultado_actividad_id uuid);
create index on crm.tareas(lead_id,vence_en);
create index on crm.tareas(vence_en) where tipo='reunion' and activo;
create table crm.actividades(id uuid primary key default gen_random_uuid(),lead_id uuid,tipo text,creado_en timestamptz);
create table crm.lead_asignaciones(id uuid default gen_random_uuid(),lead_id uuid,analista_id uuid,origen text,moneda text,
  aproximado boolean default false,asignado_en timestamptz,ciclo_n int default 1,episodio_n int default 1,
  resultado text,resultado_en timestamptz,finalizado_en timestamptz,motivo_apertura text,motivo_cierre text,
  sla_global_iniciado_en timestamptz,sla_politica_asignacion_id uuid,primera_gestion_limite_en timestamptz,primer_contacto_limite_en timestamptz);
create index on crm.lead_asignaciones(lead_id,asignado_en);
create table crm.operaciones_cartera(id uuid,cliente_id uuid,vendedor_id uuid,tipo text,periodo date,
  fecha_operacion date,creado_en timestamptz,elegible_conversion boolean,contrato_nuevo_id uuid,moneda text);
create table crm.cierres_externos(lead_id uuid,es_cierre_inicial boolean default true,anulado_en timestamptz);
create table crm.cierres_avance_anulados(lead_id uuid,motivo text,anulado_por uuid);
-- No se usan importes, pesos ni operaciones de cartera en las aserciones.
create function private.peso_referido_conversion(date) returns numeric language sql stable as 'select 0.15::numeric';
create function private.analista_atribuido_cadena(uuid) returns uuid language sql stable as 'select null::uuid';
create table private.analitica_leads_citas_exenciones(objeto text primary key,tipo text not null,
  huella text not null,razon text not null,declarado_en timestamptz default now());
create table private.analitica_leads_citas_tope(id boolean primary key default true,tope integer,actualizado_en timestamptz default now());
create table private.analitica_lc_sello(id boolean primary key default true,sello text,sellado_en timestamptz default now());
-- Una deuda ajena explícita prueba que la candidata no la exonera ni oculta.
create function private.deuda_ajena_prueba() returns bigint language sql as 'select count(*) from crm.leads';
insert into private.analitica_leads_citas_exenciones(objeto,tipo,huella,razon)
values('private.otra_exencion_prueba()','funcion','evidencia_de_prueba','Registro ajeno que debe conservarse byte por byte durante la candidata de Citas.');
insert into private.analitica_leads_citas_tope(tope) values(30);
grant usage on schema crm,private,auth to authenticated;
grant usage on schema crm,auth to anon;
alter table crm.leads enable row level security;
alter table crm.tareas enable row level security;
alter table crm.actividades enable row level security;
alter table crm.lead_asignaciones enable row level security;
alter table private.analitica_leads_citas_exenciones enable row level security;
alter table private.analitica_leads_citas_tope enable row level security;
alter table private.analitica_lc_sello enable row level security;
