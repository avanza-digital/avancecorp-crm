-- Banco REDUCIDO y sintetico: contratos de columnas/FKs, v1 real y auditor real.
-- Los tres helpers de identidad/ambito y el veto son DOBLES declarados; esto
-- prueba el uso de su resultado, no sustituye test-rls contra Supabase completo.
create role anon;
create role authenticated;
create role service_role;
create schema auth;
create schema crm;
create schema private;
create schema fixture;
grant usage on schema auth,crm,private to authenticated,anon,service_role;
create table public.perfiles(id uuid primary key,nombre_completo text,rol_fixture text,
  global_fixture boolean not null default false,activo_fixture boolean not null default true);
create table fixture.ambito(actor uuid,vendedor uuid,primary key(actor,vendedor));
create table fixture.vetos(lead_id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
create function private.rol_crm(p_id uuid) returns text language sql stable security definer set search_path='' as $$
  select p.rol_fixture from public.perfiles p where p.id=p_id and p.activo_fixture
$$;
create function private.es_lector_global() returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.perfiles p where p.id=auth.uid() and p.global_fixture and p.activo_fixture)
$$;
create function private.vendedor_ids_visibles(p_id uuid) returns setof uuid language sql stable security definer set search_path='' as $$
  select a.vendedor from fixture.ambito a join public.perfiles p on p.id=a.actor where a.actor=p_id and p.activo_fixture
$$;
create function private.persona_vetada(p_id uuid) returns boolean language sql stable as $$
  select exists(select 1 from fixture.vetos v where v.lead_id=p_id)
$$;
create table public.audit_log(id bigint generated always as identity,tabla text,operacion text,
  fila_id uuid,usuario_id uuid references public.perfiles(id),data_antes jsonb,data_despues jsonb);
-- Misma implementacion viva: conserva JSON incluso para claves no UUID.
create function private.log_audit_crm() returns trigger language plpgsql security definer set search_path='' as $$
declare v_fila uuid;v_actor uuid;
begin
  begin
    v_fila:=coalesce((pg_catalog.to_jsonb(coalesce(new,old))->>'id')::uuid,
                     (pg_catalog.to_jsonb(coalesce(new,old))->>'perfil_id')::uuid);
  exception when invalid_text_representation then v_fila:=null;
  end;
  select p.id into v_actor from public.perfiles p where p.id=(select auth.uid());
  insert into public.audit_log(tabla,operacion,fila_id,usuario_id,data_antes,data_despues)
  values(tg_table_schema||'.'||tg_table_name,tg_op,v_fila,v_actor,
    case when tg_op in ('UPDATE','DELETE') then pg_catalog.to_jsonb(old) end,
    case when tg_op in ('INSERT','UPDATE') then pg_catalog.to_jsonb(new) end);
  return coalesce(new,old);
end;
$$;
create table crm.sla_politicas(id uuid primary key,version integer unique not null,
  vigente_desde timestamptz unique not null);
create table crm.sla_politica_etapas(id uuid primary key default gen_random_uuid(),
  politica_id uuid not null references crm.sla_politicas(id),etapa text not null
  check(etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')),
  maximo_minutos integer not null,unique(politica_id,etapa));
create function private.sla_politica_vigente(p_instante timestamptz) returns uuid
language sql stable set search_path='' as $$
  select p.id from crm.sla_politicas p where p.vigente_desde<=p_instante
  order by p.vigente_desde desc,p.version desc limit 1
$$;
create table crm.leads(id uuid primary key,nombre_completo text,activo boolean not null default true,
  etapa text not null,vendedor_id uuid references public.perfiles(id),asignado_supervisor_id uuid references public.perfiles(id),
  creado_en timestamptz not null,ciclo_actual integer not null);
create table crm.lead_sla_ciclos(id uuid primary key,lead_id uuid not null references crm.leads(id),
  ciclo_n integer not null,politica_id uuid references crm.sla_politicas(id),iniciado_en timestamptz not null,
  primera_gestion_limite_en timestamptz,primera_gestion_en timestamptz,
  primer_contacto_limite_en timestamptz,primer_contacto_en timestamptz,aproximado boolean not null default false,
  unique(lead_id,ciclo_n));
create table crm.lead_asignaciones(id uuid primary key,lead_id uuid not null references crm.leads(id),
  ciclo_n integer not null,episodio_n integer not null,analista_id uuid references public.perfiles(id),
  asignado_en timestamptz not null,finalizado_en timestamptz,sla_politica_asignacion_id uuid references crm.sla_politicas(id),
  primera_gestion_limite_en timestamptz,primer_contacto_limite_en timestamptz);
create unique index una_asignacion on crm.lead_asignaciones(lead_id) where finalizado_en is null;
create table crm.lead_asignacion_sla_hitos(id uuid primary key,lead_asignacion_id uuid not null unique references crm.lead_asignaciones(id),
  primera_gestion_en timestamptz,primer_contacto_en timestamptz);
create table crm.lead_sla_etapas(id uuid primary key,lead_id uuid not null references crm.leads(id),
  ciclo_n integer not null,episodio_n integer not null,etapa text not null,
  politica_id uuid not null references crm.sla_politicas(id),iniciado_en timestamptz not null,
  limite_en timestamptz not null,finalizado_en timestamptz,aproximado boolean not null default false);
create unique index una_etapa on crm.lead_sla_etapas(lead_id,ciclo_n) where finalizado_en is null;
create table crm.actividades(id uuid primary key,lead_id uuid not null references crm.leads(id),tipo text not null,
  creado_en timestamptz not null,creado_por uuid references public.perfiles(id));
create index actividades_lead_fecha on crm.actividades(lead_id,creado_en desc);
create table crm.tareas(id uuid primary key,lead_id uuid not null references crm.leads(id),tipo text not null,
  titulo text not null,vence_en timestamptz not null,reprogramaciones smallint not null default 0,
  vendedor_id uuid references public.perfiles(id),asignado_supervisor_id uuid references public.perfiles(id),
  creado_por uuid references public.perfiles(id),activo boolean not null default true,
  estado text not null default 'pendiente',reagendada_de uuid references crm.tareas(id));
create index tareas_pendientes on crm.tareas(lead_id,vence_en,id) where activo and estado='pendiente';

-- Solo actores sinteticos, ningun dato de clientes reales.
insert into public.perfiles values
('00000000-0000-0000-0000-000000000001','Analista A','analista',false,true),
('00000000-0000-0000-0000-000000000002','Analista B','analista',false,true),
('00000000-0000-0000-0000-000000000003','Supervisor','supervisor',false,true),
('00000000-0000-0000-0000-000000000004','Gerencia','gerencia',false,true),
('00000000-0000-0000-0000-000000000005','Directorio',null,true,true),
('00000000-0000-0000-0000-000000000006','Inactivo','analista',false,false),
('00000000-0000-0000-0000-000000000007','Sin acceso',null,false,true);
insert into fixture.ambito select id,id from public.perfiles;
insert into fixture.ambito values('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001');
insert into crm.sla_politicas values
('10000000-0000-0000-0000-000000000001',1,'-infinity'),
('10000000-0000-0000-0000-000000000002',2,'2026-01-01Z');
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select p.id,r.etapa,r.minutos from crm.sla_politicas p
cross join (values ('nuevo',1440),('contactado',11520),('reunion_agendada',21600),('propuesta_enviada',28800)) r(etapa,minutos);
