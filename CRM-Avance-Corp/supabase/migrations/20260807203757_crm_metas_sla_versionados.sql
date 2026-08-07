-- Metas comerciales y SLA versionados.
-- Publicaciones append-only; PEN/USD separados; snapshots SLA por evento.

begin;

set local lock_timeout = '10s';

-- ============================================================================
-- 1. Metas: periodo/revision -> vendedor -> categoria/moneda
-- ============================================================================

create table crm.meta_periodos (
  id uuid primary key default gen_random_uuid(),
  periodo date not null,
  revision integer not null check (revision > 0),
  revision_anterior_id uuid references crm.meta_periodos(id) on delete restrict,
  publicada_por uuid not null references public.perfiles(id) on delete restrict,
  publicada_en timestamptz not null default statement_timestamp(),
  constraint meta_periodos_primer_dia_mes
    check (periodo = date_trunc('month', periodo)::date),
  constraint meta_periodos_periodo_revision_uk unique (periodo, revision)
);

comment on table crm.meta_periodos is
  'Publicaciones mensuales inmutables. La revision mayor del periodo es la vigente.';

create index meta_periodos_revision_anterior_idx
  on crm.meta_periodos (revision_anterior_id)
  where revision_anterior_id is not null;
create index meta_periodos_vigente_idx
  on crm.meta_periodos (periodo, revision desc);
create index meta_periodos_publicada_por_idx on crm.meta_periodos (publicada_por);

create table crm.metas_vendedor (
  id uuid primary key default gen_random_uuid(),
  meta_periodo_id uuid not null references crm.meta_periodos(id) on delete restrict,
  vendedor_id uuid not null references crm.equipo(perfil_id) on delete restrict,
  supervisor_id uuid not null references crm.equipo(perfil_id) on delete restrict,
  conversion_objetivo numeric(5,2) not null check (conversion_objetivo between 0 and 100),
  creado_en timestamptz not null default statement_timestamp(),
  constraint metas_vendedor_personas_distintas check (vendedor_id <> supervisor_id),
  constraint metas_vendedor_periodo_vendedor_uk unique (meta_periodo_id, vendedor_id)
);

comment on table crm.metas_vendedor is
  'Meta individual inmutable. supervisor_id es snapshot de atribucion; RLS usa jerarquia vigente.';

create index metas_vendedor_vendedor_idx on crm.metas_vendedor (vendedor_id, meta_periodo_id);
create index metas_vendedor_supervisor_idx on crm.metas_vendedor (supervisor_id, meta_periodo_id);

create table crm.metas_vendedor_detalle (
  id uuid primary key default gen_random_uuid(),
  meta_vendedor_id uuid not null references crm.metas_vendedor(id) on delete restrict,
  categoria text not null check (categoria in ('nuevo', 'renovacion', 'upgrade')),
  moneda text not null check (moneda in ('PEN', 'USD')),
  capital_objetivo numeric(14,2) not null check (capital_objetivo between 0 and 100000000),
  contratos_objetivo integer not null check (contratos_objetivo between 0 and 1000),
  creado_en timestamptz not null default statement_timestamp(),
  constraint metas_vendedor_detalle_dimension_uk
    unique (meta_vendedor_id, categoria, moneda)
);

comment on table crm.metas_vendedor_detalle is
  'Seis dimensiones por vendedor: Nuevo/Renovacion/Upgrade x PEN/USD. No existe suma monetaria mixta.';

create index metas_vendedor_detalle_meta_idx on crm.metas_vendedor_detalle (meta_vendedor_id);

create or replace function private.trg_config_versionada_inmutable()
returns trigger
language plpgsql security definer set search_path = 'pg_catalog'
as $function$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    raise exception 'La configuracion publicada es inmutable; publica una nueva revision'
      using errcode = '55000';
  end if;
  return new;
end;
$function$;

create trigger trg_meta_periodos_inmutables
before update or delete on crm.meta_periodos
for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_metas_vendedor_inmutables
before update or delete on crm.metas_vendedor
for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_metas_vendedor_detalle_inmutables
before update or delete on crm.metas_vendedor_detalle
for each row execute function private.trg_config_versionada_inmutable();

create trigger trg_audit_meta_periodos after insert on crm.meta_periodos
for each row execute function private.log_audit_crm();
create trigger trg_audit_metas_vendedor after insert on crm.metas_vendedor
for each row execute function private.log_audit_crm();
create trigger trg_audit_metas_vendedor_detalle after insert on crm.metas_vendedor_detalle
for each row execute function private.log_audit_crm();

alter table crm.meta_periodos enable row level security;
alter table crm.metas_vendedor enable row level security;
alter table crm.metas_vendedor_detalle enable row level security;

revoke all on table crm.meta_periodos from public, anon, authenticated;
revoke all on table crm.metas_vendedor from public, anon, authenticated;
revoke all on table crm.metas_vendedor_detalle from public, anon, authenticated;
grant select on table crm.meta_periodos to authenticated, service_role;
grant select on table crm.metas_vendedor to authenticated, service_role;
grant select on table crm.metas_vendedor_detalle to authenticated, service_role;

create policy meta_periodos_select on crm.meta_periodos for select to authenticated
using ((select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) is not null);

create policy metas_vendedor_select on crm.metas_vendedor for select to authenticated
using ((select private.es_lector_global())
  or vendedor_id in (select private.vendedor_ids_visibles((select auth.uid()))));

create policy metas_vendedor_detalle_select
on crm.metas_vendedor_detalle for select to authenticated
using ((select private.es_lector_global()) or exists (
  select 1 from crm.metas_vendedor mv
  where mv.id = metas_vendedor_detalle.meta_vendedor_id
    and mv.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))
));

create or replace function crm.publicar_metas_vendedores(
  p_periodo date,
  p_expected_revision integer,
  p_metas jsonb
)
returns setof crm.meta_periodos
language plpgsql security definer set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_revision_actual integer;
  v_revision_nueva integer;
  v_anterior_id uuid;
  v_periodo_id uuid;
  v_total_vendedores integer;
  v_item record;
  v_detalle record;
  v_vendedor_id uuid;
  v_supervisor_id uuid;
  v_meta_vendedor_id uuid;
  v_conversion numeric;
  v_capital numeric;
  v_contratos numeric;
  v_categoria text;
  v_moneda text;
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar metas comerciales'
      using errcode = '42501';
  end if;
  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'expected_revision debe ser cero o positivo' using errcode = '22023';
  end if;
  if p_metas is null or jsonb_typeof(p_metas) <> 'object' then
    raise exception 'Las metas deben ser un objeto por vendedor' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.meta_periodos'),
    (p_periodo - date '2000-01-01')::integer
  );
  -- La publicacion fotografía un roster completo. El lock evita que una alta,
  -- baja o reasignacion concurrente lo cambie entre la validacion y el INSERT.
  lock table public.perfiles in share mode;
  lock table crm.equipo in share mode;

  select mp.id, mp.revision into v_anterior_id, v_revision_actual
  from crm.meta_periodos mp where mp.periodo = p_periodo
  order by mp.revision desc limit 1;
  v_revision_actual := coalesce(v_revision_actual, 0);
  if p_expected_revision <> v_revision_actual then
    raise exception 'Conflicto de revision: esperada %, vigente %',
      p_expected_revision, v_revision_actual using errcode = '40001';
  end if;
  v_revision_nueva := v_revision_actual + 1;

  if exists (
    select 1
    from crm.equipo v
    join public.perfiles pv on pv.id = v.perfil_id and pv.activo
    left join crm.equipo s on s.perfil_id = v.supervisor_id
    where private.rol_crm(v.perfil_id) = 'vendedor'
      and private.rol_crm(s.perfil_id) is distinct from 'supervisor'
  ) then
    raise exception 'Todos los vendedores activos deben tener supervisor activo'
      using errcode = '23514';
  end if;

  select count(*)::integer into v_total_vendedores
  from crm.equipo v
  where private.rol_crm(v.perfil_id) = 'vendedor';

  if (select count(*) from jsonb_object_keys(p_metas)) <> v_total_vendedores
     or exists (
       select 1 from crm.equipo v
       where private.rol_crm(v.perfil_id) = 'vendedor'
         and not (p_metas ? v.perfil_id::text)
     ) then
    raise exception 'Debe enviarse exactamente una meta por vendedor activo'
      using errcode = '22023';
  end if;

  insert into crm.meta_periodos (
    periodo, revision, revision_anterior_id, publicada_por
  ) values (p_periodo, v_revision_nueva, v_anterior_id, v_uid)
  returning id into v_periodo_id;

  for v_item in select key, value from jsonb_each(p_metas) loop
    begin v_vendedor_id := v_item.key::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de vendedor invalido' using errcode = '22023';
    end;

    if jsonb_typeof(v_item.value) <> 'object'
       or not (v_item.value ?& array['conversion_objetivo','detalles'])
       or (v_item.value - array['conversion_objetivo','detalles']) <> '{}'::jsonb
       or jsonb_typeof(v_item.value->'conversion_objetivo') is distinct from 'number'
       or jsonb_typeof(v_item.value->'detalles') is distinct from 'array'
       or jsonb_array_length(v_item.value->'detalles') <> 6 then
      raise exception 'Formato de meta invalido para %', v_vendedor_id using errcode = '22023';
    end if;
    v_conversion := (v_item.value->>'conversion_objetivo')::numeric;
    if v_conversion < 0 or v_conversion > 100 then
      raise exception 'Conversion fuera de rango para %', v_vendedor_id using errcode = '22023';
    end if;

    select v.supervisor_id into v_supervisor_id
    from crm.equipo v
    join crm.equipo s on s.perfil_id = v.supervisor_id
    where v.perfil_id = v_vendedor_id
      and private.rol_crm(v.perfil_id) = 'vendedor'
      and private.rol_crm(s.perfil_id) = 'supervisor';
    if not found then
      raise exception 'Vendedor o supervisor fuera de jerarquia activa' using errcode = '23503';
    end if;

    insert into crm.metas_vendedor (
      meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo
    ) values (v_periodo_id, v_vendedor_id, v_supervisor_id, v_conversion)
    returning id into v_meta_vendedor_id;

    for v_detalle in select value from jsonb_array_elements(v_item.value->'detalles') loop
      if jsonb_typeof(v_detalle.value) <> 'object'
         or not (v_detalle.value ?& array['categoria','moneda','capital_objetivo','contratos_objetivo'])
         or (v_detalle.value - array['categoria','moneda','capital_objetivo','contratos_objetivo']) <> '{}'::jsonb
         or jsonb_typeof(v_detalle.value->'categoria') is distinct from 'string'
         or jsonb_typeof(v_detalle.value->'moneda') is distinct from 'string'
         or jsonb_typeof(v_detalle.value->'capital_objetivo') is distinct from 'number'
         or jsonb_typeof(v_detalle.value->'contratos_objetivo') is distinct from 'number' then
        raise exception 'Detalle invalido para %', v_vendedor_id using errcode = '22023';
      end if;
      v_categoria := v_detalle.value->>'categoria';
      v_moneda := v_detalle.value->>'moneda';
      v_capital := (v_detalle.value->>'capital_objetivo')::numeric;
      v_contratos := (v_detalle.value->>'contratos_objetivo')::numeric;
      if v_categoria not in ('nuevo','renovacion','upgrade')
         or v_moneda not in ('PEN','USD')
         or v_capital < 0 or v_capital > 100000000
         or v_contratos < 0 or v_contratos > 1000 or trunc(v_contratos) <> v_contratos then
        raise exception 'Detalle fuera de rango para %', v_vendedor_id using errcode = '22023';
      end if;
      begin
        insert into crm.metas_vendedor_detalle (
          meta_vendedor_id,categoria,moneda,capital_objetivo,contratos_objetivo
        ) values (v_meta_vendedor_id,v_categoria,v_moneda,v_capital,v_contratos::integer);
      exception when unique_violation then
        raise exception 'Categoria/moneda repetida para %', v_vendedor_id using errcode = '22023';
      end;
    end loop;
  end loop;

  return query select mp.* from crm.meta_periodos mp where mp.id = v_periodo_id;
end;
$function$;

comment on function crm.publicar_metas_vendedores(date,integer,jsonb) is
  'Publica revision mensual completa; expected_revision evita ultimo-escritor-gana.';

revoke all on function crm.publicar_metas_vendedores(date,integer,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crm.publicar_metas_vendedores(date,integer,jsonb) to authenticated;

-- Lectura atomica del editor: siempre devuelve el roster activo completo. Si el
-- mes aun no tiene publicacion, revision=0 y las seis dimensiones nacen en cero.
create or replace function crm.configuracion_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_publicada_por uuid;
  v_publicada_por_nombre text;
  v_payload jsonb;
begin
  if v_uid is null
     or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_periodo is null or p_periodo <> date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode = '22023';
  end if;

  select mp.id,mp.revision,mp.publicada_en,mp.publicada_por,p.nombre_completo
    into v_periodo_id,v_revision,v_publicada_en,v_publicada_por,v_publicada_por_nombre
  from crm.meta_periodos mp
  left join public.perfiles p on p.id=mp.publicada_por
  where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision := coalesce(v_revision,0);

  with dimensiones as (
    select * from (values
      ('nuevo'::text,'PEN'::text),('nuevo','USD'),
      ('renovacion','PEN'),('renovacion','USD'),
      ('upgrade','PEN'),('upgrade','USD')
    ) d(categoria,moneda)
  ), roster as (
    select e.perfil_id as vendedor_id,p.nombre_completo,e.supervisor_id,
           ps.nombre_completo as supervisor_nombre
    from crm.equipo e
    join public.perfiles p on p.id=e.perfil_id
    join crm.equipo s on s.perfil_id=e.supervisor_id
    join public.perfiles ps on ps.id=s.perfil_id
    where private.rol_crm(e.perfil_id)='vendedor'
      and private.rol_crm(s.perfil_id)='supervisor'
      and (
        private.es_lector_global()
        or e.perfil_id in (select private.vendedor_ids_visibles(v_uid))
      )
  )
  select jsonb_build_object(
    'version',1,
    'periodo',p_periodo,
    'revision',v_revision,
    'publicada_en',v_publicada_en,
    'publicada_por',v_publicada_por,
    'publicada_por_nombre',v_publicada_por_nombre,
    'puede_editar',coalesce(private.rol_crm(v_uid)='gerencia',false),
    'vendedores',coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id',r.vendedor_id,
        'nombre',r.nombre_completo,
        'supervisor_id',r.supervisor_id,
        'supervisor_nombre',r.supervisor_nombre,
        'conversion_objetivo',coalesce(mv.conversion_objetivo,0),
        'detalles',(
          select jsonb_agg(jsonb_build_object(
            'categoria',d.categoria,
            'moneda',d.moneda,
            'capital_objetivo',coalesce(md.capital_objetivo,0),
            'contratos_objetivo',coalesce(md.contratos_objetivo,0)
          ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
          from dimensiones d
          left join crm.metas_vendedor_detalle md
            on md.meta_vendedor_id=mv.id
           and md.categoria=d.categoria and md.moneda=d.moneda
        )
      ) order by r.supervisor_nombre,r.nombre_completo)
      from roster r
      left join crm.metas_vendedor mv
        on mv.meta_periodo_id=v_periodo_id and mv.vendedor_id=r.vendedor_id
    ),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

revoke all on function crm.configuracion_metas_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.configuracion_metas_fn(date) to authenticated;

-- ============================================================================
-- 2. Politicas SLA versionadas
-- ============================================================================

create table crm.sla_politicas (
  id uuid primary key default gen_random_uuid(),
  version integer not null unique check (version > 0),
  version_anterior_id uuid references crm.sla_politicas(id) on delete restrict,
  vigente_desde timestamptz not null unique,
  zona_horaria text not null check (zona_horaria='America/Lima'),
  tipo_reloj text not null check (tipo_reloj='corrido'),
  primera_gestion_minutos integer not null check (primera_gestion_minutos between 1 and 43200),
  primer_contacto_minutos integer not null check (primer_contacto_minutos between 1 and 43200),
  publicada_por uuid references public.perfiles(id) on delete restrict,
  publicada_en timestamptz not null default statement_timestamp(),
  constraint sla_contacto_despues_gestion
    check (primer_contacto_minutos >= primera_gestion_minutos)
);

comment on table crm.sla_politicas is
  'Versiones SLA globales inmutables. Se aplica la mayor vigente_desde no posterior al evento.';
comment on column crm.sla_politicas.primera_gestion_minutos is
  'Primer intento: llamada realizada/no contestada, WhatsApp enviado/recibido o reunion realizada.';
comment on column crm.sla_politicas.primer_contacto_minutos is
  'Contacto efectivo: llamada realizada, WhatsApp recibido o reunion realizada.';

create index sla_politicas_version_anterior_idx on crm.sla_politicas(version_anterior_id)
  where version_anterior_id is not null;
create index sla_politicas_vigencia_idx on crm.sla_politicas(vigente_desde desc);
create index sla_politicas_publicada_por_idx on crm.sla_politicas(publicada_por)
  where publicada_por is not null;

create table crm.sla_politica_etapas (
  id uuid primary key default gen_random_uuid(),
  politica_id uuid not null references crm.sla_politicas(id) on delete restrict,
  etapa text not null check (etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')),
  maximo_minutos integer not null check (maximo_minutos between 1 and 43200),
  constraint sla_politica_etapas_dimension_uk unique(politica_id,etapa)
);
create index sla_politica_etapas_politica_idx on crm.sla_politica_etapas(politica_id);

-- Version 1 reproduce los hardcodes previos: 24h/72h/72h/120h.
with p as (
  insert into crm.sla_politicas(
    version,vigente_desde,zona_horaria,tipo_reloj,
    primera_gestion_minutos,primer_contacto_minutos
  ) values (1,'-infinity','America/Lima','corrido',1440,1440)
  returning id
)
insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
select p.id,x.etapa,x.minutos from p cross join (values
  ('nuevo'::text,1440),('contactado',4320),
  ('reunion_agendada',4320),('propuesta_enviada',7200)
) x(etapa,minutos);

create trigger trg_sla_politicas_inmutables
before update or delete on crm.sla_politicas
for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_sla_politica_etapas_inmutables
before update or delete on crm.sla_politica_etapas
for each row execute function private.trg_config_versionada_inmutable();
create trigger trg_audit_sla_politicas after insert on crm.sla_politicas
for each row execute function private.log_audit_crm();
create trigger trg_audit_sla_politica_etapas after insert on crm.sla_politica_etapas
for each row execute function private.log_audit_crm();

alter table crm.sla_politicas enable row level security;
alter table crm.sla_politica_etapas enable row level security;
revoke all on table crm.sla_politicas from public,anon,authenticated;
revoke all on table crm.sla_politica_etapas from public,anon,authenticated;
grant select on table crm.sla_politicas to authenticated,service_role;
grant select on table crm.sla_politica_etapas to authenticated,service_role;

create policy sla_politicas_select on crm.sla_politicas for select to authenticated
using ((select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) is not null);
create policy sla_politica_etapas_select on crm.sla_politica_etapas for select to authenticated
using ((select private.es_lector_global())
  or (select private.rol_crm((select auth.uid()))) is not null);

create or replace function private.sla_politica_vigente(p_instante timestamptz)
returns uuid language sql stable set search_path=''
as $function$
  select p.id from crm.sla_politicas p
  where p.vigente_desde<=p_instante
  order by p.vigente_desde desc,p.version desc limit 1
$function$;

create or replace function crm.publicar_politica_sla(
  p_expected_version integer,
  p_vigente_desde timestamptz,
  p_config jsonb
)
returns setof crm.sla_politicas
language plpgsql security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_actual integer;
  v_anterior uuid;
  v_ultimo_desde timestamptz;
  v_desde timestamptz := coalesce(p_vigente_desde,statement_timestamp());
  v_id uuid;
  v_gestion numeric;
  v_contacto numeric;
  v_regla record;
  v_etapa text;
  v_maximo numeric;
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia activa puede publicar politicas SLA' using errcode='42501';
  end if;
  if p_expected_version is null or p_expected_version<1 then
    raise exception 'expected_version invalido' using errcode='22023';
  end if;
  if p_config is null or jsonb_typeof(p_config)<>'object'
    or not (p_config ?& array['zona_horaria','tipo_reloj','primera_gestion_minutos','primer_contacto_minutos','etapas'])
    or (p_config-array['zona_horaria','tipo_reloj','primera_gestion_minutos','primer_contacto_minutos','etapas'])<>'{}'::jsonb
    or jsonb_typeof(p_config->'zona_horaria') is distinct from 'string'
    or jsonb_typeof(p_config->'tipo_reloj') is distinct from 'string'
    or jsonb_typeof(p_config->'primera_gestion_minutos') is distinct from 'number'
    or jsonb_typeof(p_config->'primer_contacto_minutos') is distinct from 'number'
    or jsonb_typeof(p_config->'etapas') is distinct from 'array'
    or jsonb_array_length(p_config->'etapas')<>4 then
    raise exception 'Formato SLA invalido' using errcode='22023';
  end if;
  if p_config->>'zona_horaria'<>'America/Lima' or p_config->>'tipo_reloj'<>'corrido' then
    raise exception 'Solo America/Lima y reloj corrido' using errcode='22023';
  end if;
  v_gestion := (p_config->>'primera_gestion_minutos')::numeric;
  v_contacto := (p_config->>'primer_contacto_minutos')::numeric;
  if trunc(v_gestion)<>v_gestion or trunc(v_contacto)<>v_contacto
    or v_gestion<1 or v_gestion>43200
    or v_contacto<v_gestion or v_contacto>43200 then
    raise exception 'Plazos SLA fuera de rango' using errcode='22023';
  end if;
  if not isfinite(v_desde) or v_desde<statement_timestamp() then
    raise exception 'La vigencia debe iniciar ahora o en el futuro' using errcode='22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.sla_politicas'),1);
  select p.id,p.version,p.vigente_desde into v_anterior,v_actual,v_ultimo_desde
  from crm.sla_politicas p order by p.version desc limit 1;
  if p_expected_version<>v_actual then
    raise exception 'Conflicto de version SLA: esperada %, vigente %',p_expected_version,v_actual
      using errcode='40001';
  end if;
  if v_desde<=v_ultimo_desde then
    raise exception 'La vigencia debe ser posterior a la ultima politica' using errcode='22023';
  end if;

  insert into crm.sla_politicas(
    version,version_anterior_id,vigente_desde,zona_horaria,tipo_reloj,
    primera_gestion_minutos,primer_contacto_minutos,publicada_por
  ) values (v_actual+1,v_anterior,v_desde,'America/Lima','corrido',
    v_gestion::integer,v_contacto::integer,v_uid) returning id into v_id;

  for v_regla in select value from jsonb_array_elements(p_config->'etapas') loop
    if jsonb_typeof(v_regla.value)<>'object'
      or not (v_regla.value ?& array['etapa','maximo_minutos'])
      or (v_regla.value-array['etapa','maximo_minutos'])<>'{}'::jsonb
      or jsonb_typeof(v_regla.value->'etapa') is distinct from 'string'
      or jsonb_typeof(v_regla.value->'maximo_minutos') is distinct from 'number' then
      raise exception 'Regla SLA invalida' using errcode='22023';
    end if;
    v_etapa:=v_regla.value->>'etapa'; v_maximo:=(v_regla.value->>'maximo_minutos')::numeric;
    if v_etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
      or trunc(v_maximo)<>v_maximo or v_maximo<1 or v_maximo>43200 then
      raise exception 'Regla SLA fuera de rango' using errcode='22023';
    end if;
    begin
      insert into crm.sla_politica_etapas(politica_id,etapa,maximo_minutos)
      values(v_id,v_etapa,v_maximo::integer);
    exception when unique_violation then
      raise exception 'Etapa SLA repetida: %',v_etapa using errcode='22023';
    end;
  end loop;
  return query select p.* from crm.sla_politicas p where p.id=v_id;
end;
$function$;

revoke all on function crm.publicar_politica_sla(integer,timestamptz,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function crm.publicar_politica_sla(integer,timestamptz,jsonb) to authenticated;

create or replace function crm.configuracion_sla_fn()
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_ultima_version integer;
  v_payload jsonb;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select max(version) into v_ultima_version from crm.sla_politicas;
  select jsonb_build_object(
    'version',1,
    'expected_version',v_ultima_version,
    'puede_editar',coalesce(private.rol_crm(v_uid)='gerencia',false),
    'politica',jsonb_build_object(
      'id',p.id,'version',p.version,'version_anterior_id',p.version_anterior_id,
      'vigente_desde',p.vigente_desde,'zona_horaria',p.zona_horaria,
      'tipo_reloj',p.tipo_reloj,
      'primera_gestion_minutos',p.primera_gestion_minutos,
      'primer_contacto_minutos',p.primer_contacto_minutos,
      'publicada_por',p.publicada_por,
      'publicada_por_nombre',(select perfil.nombre_completo
        from public.perfiles perfil where perfil.id=p.publicada_por),
      'publicada_en',p.publicada_en,
      'etapas',(select jsonb_agg(jsonb_build_object(
        'etapa',e.etapa,'maximo_minutos',e.maximo_minutos
      ) order by array_position(array['nuevo','contactado','reunion_agendada','propuesta_enviada'],e.etapa))
      from crm.sla_politica_etapas e where e.politica_id=p.id)
    )
  ) into v_payload
  from crm.sla_politicas p
  where p.id=private.sla_politica_vigente(statement_timestamp());
  return v_payload;
end;
$function$;

revoke all on function crm.configuracion_sla_fn()
  from public,anon,authenticated,service_role;
grant execute on function crm.configuracion_sla_fn() to authenticated;

-- ============================================================================
-- 3. Snapshots SLA por ciclo, asignacion y etapa
-- ============================================================================

create table crm.lead_sla_ciclos (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id) on delete restrict,
  ciclo_n integer not null check(ciclo_n>0),
  politica_id uuid not null references crm.sla_politicas(id) on delete restrict,
  iniciado_en timestamptz not null,
  primera_gestion_limite_en timestamptz not null,
  primer_contacto_limite_en timestamptz not null,
  primera_gestion_en timestamptz,
  primer_contacto_en timestamptz,
  aproximado boolean not null default false,
  creado_en timestamptz not null default statement_timestamp(),
  constraint lead_sla_ciclos_unico unique(lead_id,ciclo_n),
  constraint lead_sla_ciclos_limites check(
    primera_gestion_limite_en>=iniciado_en
    and primer_contacto_limite_en>=primera_gestion_limite_en
    and (primera_gestion_en is null or primera_gestion_en>=iniciado_en)
    and (primer_contacto_en is null or primer_contacto_en>=iniciado_en)
    and (primer_contacto_en is null or (
      primera_gestion_en is not null and primer_contacto_en>=primera_gestion_en
    ))
  )
);
comment on table crm.lead_sla_ciclos is
  'SLA global por ciclo: politica/deadlines inmutables y primer intento/contacto sellados desde actividades.';
create index lead_sla_ciclos_lead_fecha_idx on crm.lead_sla_ciclos(lead_id,iniciado_en desc);
create index lead_sla_ciclos_periodo_idx on crm.lead_sla_ciclos(iniciado_en,politica_id);

create table crm.lead_sla_etapas (
  id uuid primary key default gen_random_uuid(),
  lead_id uuid not null references crm.leads(id) on delete restrict,
  ciclo_n integer not null check(ciclo_n>0),
  episodio_n integer not null check(episodio_n>0),
  etapa text not null check(etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')),
  politica_id uuid not null references crm.sla_politicas(id) on delete restrict,
  iniciado_en timestamptz not null,
  limite_en timestamptz not null,
  finalizado_en timestamptz,
  motivo_cierre text check(motivo_cierre in ('cambio_etapa','cierre_terminal','reapertura','desactivacion')),
  aproximado boolean not null default false,
  creado_en timestamptz not null default statement_timestamp(),
  constraint lead_sla_etapas_ciclo_fk foreign key(lead_id,ciclo_n)
    references crm.lead_sla_ciclos(lead_id,ciclo_n) on delete restrict,
  constraint lead_sla_etapas_episodio_uk unique(lead_id,ciclo_n,episodio_n),
  constraint lead_sla_etapas_intervalo check(
    limite_en>=iniciado_en
    and (finalizado_en is null or finalizado_en>=iniciado_en)
    and ((finalizado_en is null)=(motivo_cierre is null))
  )
);
comment on table crm.lead_sla_etapas is
  'Episodios por etapa con politica y deadline fotografiados al entrar.';
create unique index lead_sla_etapas_un_abierto_idx on crm.lead_sla_etapas(lead_id)
  where finalizado_en is null;
create index lead_sla_etapas_lead_fecha_idx on crm.lead_sla_etapas(lead_id,iniciado_en desc);
create index lead_sla_etapas_periodo_idx
  on crm.lead_sla_etapas(iniciado_en,politica_id,etapa);

alter table crm.lead_sla_ciclos enable row level security;
alter table crm.lead_sla_etapas enable row level security;
revoke all on table crm.lead_sla_ciclos from public,anon,authenticated,service_role;
revoke all on table crm.lead_sla_etapas from public,anon,authenticated,service_role;
grant select on table crm.lead_sla_ciclos to service_role;
grant select on table crm.lead_sla_etapas to service_role;

-- Backfill del ciclo actual usando el reloj global ya endurecido. La politica 1
-- es efectiva desde -infinity y reproduce los umbrales historicos.
insert into crm.lead_sla_ciclos(
  lead_id,ciclo_n,politica_id,iniciado_en,
  primera_gestion_limite_en,primer_contacto_limite_en,
  primera_gestion_en,primer_contacto_en,aproximado
)
select l.id,l.ciclo_actual,p.id,l.sla_global_iniciado_en,
  l.sla_global_iniciado_en+p.primera_gestion_minutos*interval '1 minute',
  l.sla_global_iniciado_en+p.primer_contacto_minutos*interval '1 minute',
  case when ev.primera_gestion_en is not null
    then greatest(ev.primera_gestion_en,l.sla_global_iniciado_en) end,
  case when ev.primer_contacto_en is not null
    then greatest(ev.primer_contacto_en,l.sla_global_iniciado_en) end,
  l.sla_global_aproximado
    or coalesce(ev.primera_gestion_en<l.sla_global_iniciado_en,false)
    or coalesce(ev.primer_contacto_en<l.sla_global_iniciado_en,false)
from crm.leads l
join lateral (
  select sp.* from crm.sla_politicas sp
  where sp.vigente_desde<=l.sla_global_iniciado_en
  order by sp.vigente_desde desc,sp.version desc limit 1
) p on true
left join lateral (
  select
    min(a.creado_en) filter(where a.tipo in (
      'llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'
    )) as primera_gestion_en,
    min(a.creado_en) filter(where a.tipo in (
      'llamada_realizada','whatsapp_recibido','reunion_realizada'
    )) as primer_contacto_en
  from crm.actividades a
  where a.lead_id=l.id and a.creado_en>=l.sla_global_iniciado_en
) ev on true;

-- Solo se reconstruye el episodio abierto: el historico previo no se inventa.
insert into crm.lead_sla_etapas(
  lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en,aproximado
)
select l.id,l.ciclo_actual,1,l.etapa,p.id,
  greatest(coalesce(ent.creado_en,l.sla_global_iniciado_en),l.sla_global_iniciado_en),
  greatest(coalesce(ent.creado_en,l.sla_global_iniciado_en),l.sla_global_iniciado_en)
    +pe.maximo_minutos*interval '1 minute',
  l.sla_global_aproximado or ent.creado_en is null
    or ent.creado_en<l.sla_global_iniciado_en
from crm.leads l
left join lateral (
  select a.creado_en from crm.actividades a
  where a.lead_id=l.id and a.tipo='cambio_etapa'
    and a.metadata->>'etapa_nueva'=l.etapa
    and a.creado_en>=l.sla_global_iniciado_en
  order by a.creado_en desc,a.id desc limit 1
) ent on true
join lateral (
  select sp.* from crm.sla_politicas sp
  where sp.vigente_desde<=coalesce(ent.creado_en,l.sla_global_iniciado_en)
  order by sp.vigente_desde desc,sp.version desc limit 1
) p on true
join crm.sla_politica_etapas pe on pe.politica_id=p.id and pe.etapa=l.etapa
where l.activo and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada');

alter table crm.lead_asignaciones
  add column sla_politica_asignacion_id uuid references crm.sla_politicas(id) on delete restrict,
  add column primera_gestion_limite_en timestamptz,
  add column primer_contacto_limite_en timestamptz;

-- Backfill de esquema, no evento comercial: evita audit falso y el guard del ledger.
alter table crm.lead_asignaciones disable trigger trg_lead_asignaciones_00_inmutables;
alter table crm.lead_asignaciones disable trigger trg_audit_lead_asignaciones;
with elegidas as (
  select la.id,p.id as politica_id,p.primera_gestion_minutos,p.primer_contacto_minutos
  from crm.lead_asignaciones la
  join lateral (
    select sp.* from crm.sla_politicas sp
    where sp.vigente_desde<=la.asignado_en
    order by sp.vigente_desde desc,sp.version desc limit 1
  ) p on true
)
update crm.lead_asignaciones la set
  sla_politica_asignacion_id=e.politica_id,
  primera_gestion_limite_en=la.asignado_en+e.primera_gestion_minutos*interval '1 minute',
  primer_contacto_limite_en=la.asignado_en+e.primer_contacto_minutos*interval '1 minute'
from elegidas e where e.id=la.id;
alter table crm.lead_asignaciones enable trigger trg_audit_lead_asignaciones;
alter table crm.lead_asignaciones enable trigger trg_lead_asignaciones_00_inmutables;

alter table crm.lead_asignaciones
  alter column sla_politica_asignacion_id set not null,
  alter column primera_gestion_limite_en set not null,
  alter column primer_contacto_limite_en set not null,
  add constraint lead_asignaciones_sla_versionado_limites check(
    primera_gestion_limite_en>=asignado_en
    and primer_contacto_limite_en>=primera_gestion_limite_en
  ) not valid;
alter table crm.lead_asignaciones validate constraint lead_asignaciones_sla_versionado_limites;
create index lead_asignaciones_sla_politica_idx
  on crm.lead_asignaciones(sla_politica_asignacion_id,asignado_en desc);

-- Los hitos viven fuera del ledger de asignaciones: ese ledger solo admite
-- INSERT/cierre y su guard preexistente no debe relajarse para registrar SLA.
create table crm.lead_asignacion_sla_hitos (
  id uuid primary key default gen_random_uuid(),
  lead_asignacion_id uuid not null unique
    references crm.lead_asignaciones(id) on delete restrict,
  primera_gestion_en timestamptz,
  primer_contacto_en timestamptz,
  creado_en timestamptz not null default statement_timestamp(),
  constraint lead_asignacion_sla_hitos_orden check(
    primer_contacto_en is null or (
      primera_gestion_en is not null and primer_contacto_en>=primera_gestion_en
    )
  )
);
comment on table crm.lead_asignacion_sla_hitos is
  'Primer intento y contacto efectivo inmutables por episodio de responsabilidad.';

insert into crm.lead_asignacion_sla_hitos(
  lead_asignacion_id,primera_gestion_en,primer_contacto_en
)
select la.id,ev.primera_gestion_en,ev.primer_contacto_en
from crm.lead_asignaciones la
left join lateral (
  select
    min(a.creado_en) filter(where a.tipo in (
      'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
      'whatsapp_recibido','reunion_realizada'
    )) as primera_gestion_en,
    min(a.creado_en) filter(where a.tipo in (
      'llamada_realizada','whatsapp_recibido','reunion_realizada'
    )) as primer_contacto_en
  from crm.actividades a
  where a.lead_id=la.lead_id and a.creado_por=la.analista_id
    and a.creado_en>=la.asignado_en
    and a.creado_en<coalesce(la.finalizado_en,'infinity'::timestamptz)
) ev on true;

alter table crm.lead_asignacion_sla_hitos enable row level security;
revoke all on table crm.lead_asignacion_sla_hitos
  from public,anon,authenticated,service_role;
grant select on table crm.lead_asignacion_sla_hitos to service_role;

create or replace function private.trg_lead_sla_ciclos_guard()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
begin
  if tg_op='DELETE' then raise exception 'Los ciclos SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Los ciclos SLA solo se escriben desde eventos CRM' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en
    or old.primera_gestion_limite_en is distinct from new.primera_gestion_limite_en
    or old.primer_contacto_limite_en is distinct from new.primer_contacto_limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null and old.primer_contacto_en is distinct from new.primer_contacto_en) then
    raise exception 'Snapshot/eventos SLA inmutables' using errcode='55000';
  end if;
  return new;
end;
$function$;

create or replace function private.trg_lead_sla_etapas_guard()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
begin
  if tg_op='DELETE' then raise exception 'Las etapas SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Las etapas SLA solo se escriben desde crm.leads' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.finalizado_en is not null or new.finalizado_en is null or new.motivo_cierre is null
    or old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.episodio_n is distinct from new.episodio_n
    or old.etapa is distinct from new.etapa or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en or old.limite_en is distinct from new.limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en then
    raise exception 'Solo se permite cerrar una etapa SLA abierta' using errcode='55000';
  end if;
  return new;
end;
$function$;

create trigger trg_lead_sla_ciclos_guard
before insert or update or delete on crm.lead_sla_ciclos
for each row execute function private.trg_lead_sla_ciclos_guard();
create trigger trg_lead_sla_etapas_guard
before insert or update or delete on crm.lead_sla_etapas
for each row execute function private.trg_lead_sla_etapas_guard();
create trigger trg_audit_lead_sla_ciclos after insert or update on crm.lead_sla_ciclos
for each row execute function private.log_audit_crm();
create trigger trg_audit_lead_sla_etapas after insert or update on crm.lead_sla_etapas
for each row execute function private.log_audit_crm();

create or replace function private.trg_lead_asignaciones_sla_versionado()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
declare v_p crm.sla_politicas%rowtype;
begin
  if tg_op='INSERT' then
    select p.* into v_p from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(new.asignado_en);
    if not found then raise exception 'No existe politica SLA para la asignacion'; end if;
    new.sla_politica_asignacion_id:=v_p.id;
    new.primera_gestion_limite_en:=new.asignado_en+v_p.primera_gestion_minutos*interval '1 minute';
    new.primer_contacto_limite_en:=new.asignado_en+v_p.primer_contacto_minutos*interval '1 minute';
  elsif old.sla_politica_asignacion_id is distinct from new.sla_politica_asignacion_id
    or old.primera_gestion_limite_en is distinct from new.primera_gestion_limite_en
    or old.primer_contacto_limite_en is distinct from new.primer_contacto_limite_en then
    raise exception 'Snapshot SLA de asignacion inmutable' using errcode='55000';
  end if;
  return new;
end;
$function$;
create trigger trg_lead_asignaciones_01_sla_versionado
before insert or update on crm.lead_asignaciones
for each row execute function private.trg_lead_asignaciones_sla_versionado();

create or replace function private.trg_lead_asignacion_sla_hitos_guard()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
declare
  v_asignado_en timestamptz;
  v_finalizado_en timestamptz;
begin
  if tg_op='DELETE' then
    raise exception 'Los hitos SLA de asignacion no se eliminan' using errcode='55000';
  end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on'
    or pg_trigger_depth()<2 then
    raise exception 'Los hitos SLA solo se sellan desde eventos CRM' using errcode='42501';
  end if;
  select a.asignado_en,a.finalizado_en into v_asignado_en,v_finalizado_en
  from crm.lead_asignaciones a where a.id=new.lead_asignacion_id;
  if not found then raise exception 'Asignacion SLA inexistente' using errcode='23503'; end if;
  if tg_op='UPDATE' and (
    old.id is distinct from new.id
    or old.lead_asignacion_id is distinct from new.lead_asignacion_id
    or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null
      and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null
      and old.primer_contacto_en is distinct from new.primer_contacto_en)
  ) then
    raise exception 'Los hitos SLA de asignacion son inmutables' using errcode='55000';
  end if;
  if (new.primera_gestion_en is not null and (
      new.primera_gestion_en<v_asignado_en
      or (v_finalizado_en is not null and new.primera_gestion_en>v_finalizado_en)
    )) or (new.primer_contacto_en is not null and (
      new.primera_gestion_en is null
      or new.primer_contacto_en<new.primera_gestion_en
      or (v_finalizado_en is not null and new.primer_contacto_en>v_finalizado_en)
    )) then
    raise exception 'Hito SLA fuera del episodio de asignacion' using errcode='23514';
  end if;
  return new;
end;
$function$;

create trigger trg_lead_asignacion_sla_hitos_guard
before insert or update or delete on crm.lead_asignacion_sla_hitos
for each row execute function private.trg_lead_asignacion_sla_hitos_guard();
create trigger trg_audit_lead_asignacion_sla_hitos
after insert or update on crm.lead_asignacion_sla_hitos
for each row execute function private.log_audit_crm();

create or replace function private.trg_lead_asignaciones_crear_sla_hitos()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
begin
  perform set_config('crm.sla_writer','on',true);
  insert into crm.lead_asignacion_sla_hitos(lead_asignacion_id) values(new.id);
  perform set_config('crm.sla_writer','off',true);
  return null;
end;
$function$;
create trigger trg_lead_asignaciones_02_crear_sla_hitos
after insert on crm.lead_asignaciones
for each row execute function private.trg_lead_asignaciones_crear_sla_hitos();

create or replace function private.trg_leads_sla_versionado()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
declare
  v_en timestamptz;
  v_p crm.sla_politicas%rowtype;
  v_maximo integer;
  v_n integer;
  v_motivo text;
begin
  v_en:=case when tg_op='INSERT' then new.sla_global_iniciado_en else statement_timestamp() end;
  perform set_config('crm.sla_writer','on',true);

  if tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual then
    select p.* into v_p from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(new.sla_global_iniciado_en);
    if not found then raise exception 'No existe politica SLA para el ciclo'; end if;
    insert into crm.lead_sla_ciclos(
      lead_id,ciclo_n,politica_id,iniciado_en,primera_gestion_limite_en,primer_contacto_limite_en
    ) values(new.id,new.ciclo_actual,v_p.id,new.sla_global_iniciado_en,
      new.sla_global_iniciado_en+v_p.primera_gestion_minutos*interval '1 minute',
      new.sla_global_iniciado_en+v_p.primer_contacto_minutos*interval '1 minute');
  end if;

  if tg_op='UPDATE' and (
    new.ciclo_actual is distinct from old.ciclo_actual or new.etapa is distinct from old.etapa
    or (old.activo and not new.activo)
  ) then
    v_motivo:=case
      when new.ciclo_actual is distinct from old.ciclo_actual then 'reapertura'
      when old.activo and not new.activo then 'desactivacion'
      when new.etapa in ('convertido','descartado') then 'cierre_terminal'
      else 'cambio_etapa' end;
    update crm.lead_sla_etapas set finalizado_en=v_en,motivo_cierre=v_motivo
    where lead_id=new.id and finalizado_en is null;
  end if;

  if new.activo and new.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and (tg_op='INSERT' or new.ciclo_actual is distinct from old.ciclo_actual
      or new.etapa is distinct from old.etapa or (not old.activo and new.activo)) then
    select p.* into v_p
    from crm.sla_politicas p
    where p.id=private.sla_politica_vigente(v_en);
    if not found then raise exception 'No existe politica SLA vigente'; end if;
    select pe.maximo_minutos into v_maximo
    from crm.sla_politica_etapas pe
    where pe.politica_id=v_p.id and pe.etapa=new.etapa;
    if not found then raise exception 'No existe SLA para etapa %',new.etapa; end if;
    select coalesce(max(e.episodio_n),0)+1 into v_n from crm.lead_sla_etapas e
    where e.lead_id=new.id and e.ciclo_n=new.ciclo_actual;
    insert into crm.lead_sla_etapas(
      lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en
    ) values(new.id,new.ciclo_actual,v_n,new.etapa,v_p.id,v_en,
      v_en+v_maximo*interval '1 minute');
  end if;
  perform set_config('crm.sla_writer','off',true);
  return new;
end;
$function$;

-- Corre antes del AFTER que abre lead_asignaciones (orden alfabetico).
create trigger trg_leads_02_sla_versionado
after insert or update on crm.leads
for each row execute function private.trg_leads_sla_versionado();

create or replace function private.trg_actividades_sla_versionado()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
declare
  v_contacto boolean;
  v_evento_en timestamptz:=statement_timestamp();
begin
  if new.lead_id is null or new.tipo not in (
    'llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'
  ) then return null; end if;
  v_contacto:=new.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada');
  perform set_config('crm.sla_writer','on',true);
  update crm.lead_sla_ciclos c set
    primera_gestion_en=coalesce(c.primera_gestion_en,v_evento_en),
    primer_contacto_en=case when v_contacto then coalesce(c.primer_contacto_en,v_evento_en)
      else c.primer_contacto_en end
  from crm.leads l
  where l.id=new.lead_id and c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
    and (c.primera_gestion_en is null or (v_contacto and c.primer_contacto_en is null));

  -- El ledger de responsabilidad conserva sus propios hitos: una transferencia
  -- posterior no reasigna el trabajo del analista anterior ni obliga a releer
  -- timestamps de actividades controlables por el payload.
  update crm.lead_asignacion_sla_hitos h set
    primera_gestion_en=coalesce(h.primera_gestion_en,v_evento_en),
    primer_contacto_en=case when v_contacto
      then coalesce(h.primer_contacto_en,v_evento_en) else h.primer_contacto_en end
  from crm.lead_asignaciones a
  where a.id=h.lead_asignacion_id and a.lead_id=new.lead_id
    and a.analista_id=new.creado_por and a.finalizado_en is null
    and v_evento_en>=a.asignado_en
    and (h.primera_gestion_en is null or (v_contacto and h.primer_contacto_en is null));
  perform set_config('crm.sla_writer','off',true);
  return null;
end;
$function$;

-- Audit primero; sello SLA antes del avance automatico de etapa (trg_zz_*).
create trigger trg_zy_actividades_sla_versionado after insert on crm.actividades
for each row when(new.tipo in (
  'llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'
)) execute function private.trg_actividades_sla_versionado();

revoke all on function private.trg_config_versionada_inmutable()
  from public,anon,authenticated,service_role;
revoke all on function private.sla_politica_vigente(timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function private.trg_lead_sla_ciclos_guard()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_lead_sla_etapas_guard()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_lead_asignaciones_sla_versionado()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_lead_asignacion_sla_hitos_guard()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_lead_asignaciones_crear_sla_hitos()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_leads_sla_versionado()
  from public,anon,authenticated,service_role;
revoke all on function private.trg_actividades_sla_versionado()
  from public,anon,authenticated,service_role;

-- ============================================================================
-- 4. Lecturas de cumplimiento y metricas (contratos genericos, no "24h")
-- ============================================================================

create or replace function crm.cumplimiento_metas_fn(p_periodo date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);

  with contratos_confirmados as materialized (
    -- Una fila de public.contratos es la confirmacion canonica. Solo entra si
    -- esta enlazada al CRM; DISTINCT ON impide duplicarla ante datos legacy con
    -- mas de un lead apuntando al mismo contrato.
    select distinct on(c.id)
      c.id,l.vendedor_id,c.categoria,c.moneda,c.capital
    from public.contratos c
    join crm.leads l on l.contrato_id=c.id
    where c.creado_en>=v_ini and c.creado_en<v_fin
      and l.vendedor_id is not null
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
    order by c.id,l.convertido_en desc nulls last,l.id
  ), reales as (
    select vendedor_id,categoria,moneda,
      count(*)::integer as contratos_real,
      coalesce(sum(capital),0) as capital_real
    from contratos_confirmados group by vendedor_id,categoria,moneda
  ), conversiones as (
    -- La conversion mide decisiones terminales del periodo, no contratos:
    -- convertido / (convertido + descartado), atribuido por vendedor.
    select l.vendedor_id,
      count(*) filter(where l.etapa='convertido')::integer as convertidos,
      count(*)::integer as resueltos,
      case when count(*)>0 then round(
        100.0*count(*) filter(where l.etapa='convertido')/count(*),2
      ) end as conversion_real
    from crm.leads l
    where l.vendedor_id is not null
      and (
        (l.etapa='convertido' and l.convertido_en>=v_ini and l.convertido_en<v_fin)
        or (l.etapa='descartado' and l.descartado_en>=v_ini and l.descartado_en<v_fin)
      )
    group by l.vendedor_id
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_resueltos'
    ),
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

comment on function crm.cumplimiento_metas_fn(date) is
  'Cumplimiento de la ultima revision del mes. Capital y contratos provienen de contratos confirmados enlazados al CRM; conversion = leads convertidos / (convertidos + descartados) cerrados en el periodo. Capital PEN/USD permanece separado por dimension.';
revoke all on function crm.cumplimiento_metas_fn(date)
  from public,anon,authenticated,service_role;
grant execute on function crm.cumplimiento_metas_fn(date) to authenticated;

create or replace function crm.metricas_sla_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := now();
  v_payload jsonb;
begin
  if v_uid is null or not coalesce(
    private.rol_crm(v_uid)='gerencia' or private.es_lector_global(),
    false
  ) then raise exception 'No autorizado' using errcode='42501'; end if;
  if p_desde is null or p_hasta is null or p_desde>p_hasta
    or p_hasta>v_hoy or p_hasta-p_desde>365 then
    raise exception 'Periodo invalido' using errcode='22023';
  end if;
  v_ini:=p_desde::timestamp at time zone 'America/Lima';
  v_fin:=(p_hasta+1)::timestamp at time zone 'America/Lima';

  with ciclos as materialized (
    select c.*,p.version as politica_version,p.primera_gestion_minutos,
      p.primer_contacto_minutos
    from crm.lead_sla_ciclos c join crm.sla_politicas p on p.id=c.politica_id
    where c.iniciado_en>=v_ini and c.iniciado_en<v_fin
  ), ciclos_gestion as (
    select politica_id,politica_version,primera_gestion_minutos as objetivo_minutos,
      count(*)::int total,
      count(*) filter(where primera_gestion_en is not null or v_ahora>=primera_gestion_limite_en)::int evaluables,
      count(*) filter(where primera_gestion_en<=primera_gestion_limite_en)::int cumplidos,
      count(*) filter(where primera_gestion_en>primera_gestion_limite_en
        or (primera_gestion_en is null and v_ahora>=primera_gestion_limite_en))::int fuera_objetivo,
      count(*) filter(where primera_gestion_en is null and v_ahora<primera_gestion_limite_en)::int pendientes
    from ciclos group by politica_id,politica_version,primera_gestion_minutos
  ), ciclos_contacto as (
    select politica_id,politica_version,primer_contacto_minutos as objetivo_minutos,
      count(*)::int total,
      count(*) filter(where primer_contacto_en is not null or v_ahora>=primer_contacto_limite_en)::int evaluables,
      count(*) filter(where primer_contacto_en<=primer_contacto_limite_en)::int cumplidos,
      count(*) filter(where primer_contacto_en>primer_contacto_limite_en
        or (primer_contacto_en is null and v_ahora>=primer_contacto_limite_en))::int fuera_objetivo,
      count(*) filter(where primer_contacto_en is null and v_ahora<primer_contacto_limite_en)::int pendientes
    from ciclos group by politica_id,politica_version,primer_contacto_minutos
  ), asignaciones_base as materialized (
    select la.*,p.version as politica_version,p.primera_gestion_minutos,
      p.primer_contacto_minutos,h.primera_gestion_en,h.primer_contacto_en
    from crm.lead_asignaciones la
    join crm.sla_politicas p on p.id=la.sla_politica_asignacion_id
    join crm.lead_asignacion_sla_hitos h on h.lead_asignacion_id=la.id
    where la.asignado_en>=v_ini and la.asignado_en<v_fin
  ), asignaciones_gestion as (
    select sla_politica_asignacion_id as politica_id,politica_version,
      primera_gestion_minutos as objetivo_minutos,count(*)::int total,
      count(*) filter(where primera_gestion_en is not null or finalizado_en is not null
        or v_ahora>=primera_gestion_limite_en)::int evaluables,
      count(*) filter(where primera_gestion_en<=primera_gestion_limite_en)::int cumplidos,
      count(*) filter(where primera_gestion_en>primera_gestion_limite_en
        or (primera_gestion_en is null
          and (finalizado_en is not null or v_ahora>=primera_gestion_limite_en)))::int fuera_objetivo,
      count(*) filter(where primera_gestion_en is null and finalizado_en is null
        and v_ahora<primera_gestion_limite_en)::int pendientes
    from asignaciones_base
    group by sla_politica_asignacion_id,politica_version,primera_gestion_minutos
  ), asignaciones_contacto as (
    select sla_politica_asignacion_id as politica_id,politica_version,
      primer_contacto_minutos as objetivo_minutos,count(*)::int total,
      count(*) filter(where primer_contacto_en is not null or finalizado_en is not null
        or v_ahora>=primer_contacto_limite_en)::int evaluables,
      count(*) filter(where primer_contacto_en<=primer_contacto_limite_en)::int cumplidos,
      count(*) filter(where primer_contacto_en>primer_contacto_limite_en
        or (primer_contacto_en is null
          and (finalizado_en is not null or v_ahora>=primer_contacto_limite_en)))::int fuera_objetivo,
      count(*) filter(where primer_contacto_en is null and finalizado_en is null
        and v_ahora<primer_contacto_limite_en)::int pendientes
    from asignaciones_base
    group by sla_politica_asignacion_id,politica_version,primer_contacto_minutos
  ), etapas as (
    select e.politica_id,p.version as politica_version,e.etapa,pe.maximo_minutos as objetivo_minutos,
      count(*)::int total,
      count(*) filter(where e.finalizado_en is not null or v_ahora>=e.limite_en)::int evaluables,
      count(*) filter(where e.finalizado_en<=e.limite_en)::int cumplidos,
      count(*) filter(where e.finalizado_en>e.limite_en
        or (e.finalizado_en is null and v_ahora>=e.limite_en))::int fuera_objetivo,
      count(*) filter(where e.finalizado_en is null and v_ahora<e.limite_en)::int pendientes
    from crm.lead_sla_etapas e
    join crm.sla_politicas p on p.id=e.politica_id
    join crm.sla_politica_etapas pe on pe.politica_id=e.politica_id and pe.etapa=e.etapa
    where e.iniciado_en>=v_ini and e.iniciado_en<v_fin
    group by e.politica_id,p.version,e.etapa,pe.maximo_minutos
  )
  select jsonb_build_object(
    'version',1,'generado_en',v_ahora,
    'periodo',jsonb_build_object('desde',p_desde,'hasta',p_hasta,'zona','America/Lima'),
    'ciclos',jsonb_build_object(
      'primera_gestion',coalesce((select jsonb_agg(to_jsonb(x) order by politica_version) from ciclos_gestion x),'[]'::jsonb),
      'primer_contacto',coalesce((select jsonb_agg(to_jsonb(x) order by politica_version) from ciclos_contacto x),'[]'::jsonb)
    ),
    'asignaciones',jsonb_build_object(
      'primera_gestion',coalesce((select jsonb_agg(to_jsonb(x) order by politica_version) from asignaciones_gestion x),'[]'::jsonb),
      'primer_contacto',coalesce((select jsonb_agg(to_jsonb(x) order by politica_version) from asignaciones_contacto x),'[]'::jsonb)
    ),
    'etapas',coalesce((select jsonb_agg(to_jsonb(x)
      order by politica_version,array_position(array['nuevo','contactado','reunion_agendada','propuesta_enviada'],etapa))
      from etapas x),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$;

comment on function crm.metricas_sla_fn(date,date) is
  'Metricas genericas por politica para ciclos, asignaciones y etapas. Distingue primer intento de contacto efectivo; no contiene literales 24h.';
revoke all on function crm.metricas_sla_fn(date,date)
  from public,anon,authenticated,service_role;
grant execute on function crm.metricas_sla_fn(date,date) to authenticated;

-- Estado vivo para las superficies operativas. El navegador NO recalcula los
-- deadlines con la politica vigente: cada lead recibe exactamente las
-- fotografias de ciclo, asignacion y etapa que le correspondieron al iniciar.
create or replace function crm.estado_sla_leads_fn()
returns table (
  lead_id uuid,
  ciclo_politica_id uuid,
  ciclo_politica_version integer,
  primera_gestion_limite_en timestamptz,
  primera_gestion_en timestamptz,
  primer_contacto_limite_en timestamptz,
  primer_contacto_en timestamptz,
  ciclo_aproximado boolean,
  asignacion_id uuid,
  asignacion_politica_id uuid,
  asignacion_politica_version integer,
  asignacion_primera_gestion_limite_en timestamptz,
  asignacion_primera_gestion_en timestamptz,
  asignacion_primer_contacto_limite_en timestamptz,
  asignacion_primer_contacto_en timestamptz,
  etapa_politica_id uuid,
  etapa_politica_version integer,
  etapa text,
  etapa_iniciada_en timestamptz,
  etapa_limite_en timestamptz,
  etapa_objetivo_minutos integer,
  etapa_aproximada boolean
)
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector_global boolean;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector_global := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector_global) then
    raise exception 'No autorizado' using errcode='42501';
  end if;

  return query
  select
    l.id,
    c.politica_id,
    pc.version,
    c.primera_gestion_limite_en,
    c.primera_gestion_en,
    c.primer_contacto_limite_en,
    c.primer_contacto_en,
    c.aproximado,
    a.id,
    a.sla_politica_asignacion_id,
    pa.version,
    a.primera_gestion_limite_en,
    ah.primera_gestion_en,
    a.primer_contacto_limite_en,
    ah.primer_contacto_en,
    e.politica_id,
    pe.version,
    e.etapa,
    e.iniciado_en,
    e.limite_en,
    re.maximo_minutos,
    e.aproximado
  from crm.leads l
  join crm.lead_sla_ciclos c
    on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  join crm.sla_politicas pc on pc.id=c.politica_id
  left join lateral (
    select la.*
    from crm.lead_asignaciones la
    where la.lead_id=l.id and la.finalizado_en is null
    order by la.episodio_n desc
    limit 1
  ) a on true
  left join crm.sla_politicas pa on pa.id=a.sla_politica_asignacion_id
  left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id=a.id
  left join crm.lead_sla_etapas e
    on e.lead_id=l.id and e.ciclo_n=l.ciclo_actual and e.finalizado_en is null
  left join crm.sla_politicas pe on pe.id=e.politica_id
  left join crm.sla_politica_etapas re
    on re.politica_id=e.politica_id and re.etapa=e.etapa
  where l.activo is true
    and (
      l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (
        l.vendedor_id is null
        and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))
      )
      or v_rol='gerencia'
      or v_lector_global
    )
  order by l.id;
end;
$function$;

comment on function crm.estado_sla_leads_fn() is
  'Fotografias SLA vivas por lead visible. La UI usa deadlines/versiones sellados y nunca reaplica retroactivamente la politica actual.';
revoke all on function crm.estado_sla_leads_fn()
  from public,anon,authenticated,service_role;
grant execute on function crm.estado_sla_leads_fn() to authenticated;

-- ============================================================================
-- 5. Distribucion deja de exponer el SLA fijo historico
-- ============================================================================

-- La V2 historica mezclaba capacidad/distribucion con un SLA fijo de 24 horas
-- y umbrales de etapa fijos. La fuente canonica de tiempos ahora son
-- configuracion_sla_fn, metricas_sla_fn y estado_sla_leads_fn. Se conserva el
-- nucleo private antiguo porque la V1 de rollback y el entrypoint autorizado
-- aun dependen de el; sus ACL siguen cerradas. El unico contrato V2 expuesto se
-- sanea aqui, sin conceder acceso directo a private ni alterar su autorizacion.
do $membership$
begin
  execute format('grant crm_metricas_bridge to %I', current_user);
end;
$membership$;

create or replace function crm.metricas_distribucion_leads_v2_fn(
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_payload jsonb;
  v_analistas jsonb;
begin
  v_payload := private.metricas_distribucion_leads_autorizada(
    p_desde,
    p_hasta,
    2::smallint
  );

  if v_payload is null
     or jsonb_typeof(v_payload) <> 'object'
     or jsonb_typeof(v_payload->'cohorte') <> 'object'
     or jsonb_typeof(v_payload->'alcances') <> 'object'
     or jsonb_typeof(v_payload->'resumen') <> 'object'
     or jsonb_typeof(v_payload->'analistas') <> 'array'
     or jsonb_typeof(v_payload->'calidad') <> 'object' then
    raise exception 'Contrato interno de distribucion V2 inesperado'
      using errcode = '55000';
  end if;

  v_payload := jsonb_set(
    v_payload,
    '{cohorte}',
    (v_payload->'cohorte')
      - 'criterio_sla_global'
      - 'politica_pausas',
    false
  );
  v_payload := jsonb_set(
    v_payload,
    '{alcances}',
    (v_payload->'alcances')
      - 'operacion_sla'
      - 'sla_principal'
      - 'sla_operativo',
    false
  );
  v_payload := jsonb_set(
    v_payload,
    '{resumen}',
    (v_payload->'resumen')
      - 'sla_evaluables'
      - 'sla_en_24h'
      - 'sla_global_ciclos_cohorte'
      - 'sla_global_leads_unicos_cohorte'
      - 'sla_global_contactos'
      - 'sla_global_evaluables'
      - 'sla_global_en_24h'
      - 'primer_contacto_global_mediana_minutos'
      - 'sla_global_sin_contacto_vencidos_actuales',
    false
  );

  if exists (
    select 1
    from jsonb_array_elements(v_payload->'analistas') as fila(elemento)
    where jsonb_typeof(fila.elemento) <> 'object'
       or jsonb_typeof(fila.elemento->'operacion') <> 'object'
  ) then
    raise exception 'Contrato interno de analistas V2 inesperado'
      using errcode = '55000';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_set(
        fila.elemento,
        '{operacion}',
        (fila.elemento->'operacion')
          - 'contactos'
          - 'contactos_asignacion'
          - 'sla_evaluables'
          - 'sla_en_24h'
          - 'sla_asignacion_evaluables'
          - 'sla_asignacion_en_24h'
          - 'primer_contacto_mediana_minutos'
          - 'primer_contacto_asignacion_mediana_minutos'
          - 'estancados_actual',
        false
      )
      order by fila.orden
    ),
    '[]'::jsonb
  )
  into v_analistas
  from jsonb_array_elements(v_payload->'analistas')
    with ordinality as fila(elemento, orden);

  v_payload := jsonb_set(v_payload, '{analistas}', v_analistas, false);
  v_payload := jsonb_set(
    v_payload,
    '{calidad}',
    (v_payload->'calidad') - 'ciclos_sla_global_aproximados_cohorte',
    false
  );

  return v_payload;
end;
$function$;

revoke all on function crm.metricas_distribucion_leads_v2_fn(date,date)
  from public,anon,authenticated,service_role;
grant execute on function crm.metricas_distribucion_leads_v2_fn(date,date)
  to authenticated;
comment on function crm.metricas_distribucion_leads_v2_fn(date,date) is
  'JSON V2 de distribucion, capacidad y resultados; no transporta SLA. Autorizacion private fail-closed mediante crm_metricas_bridge.';

do $contract$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_roles r on r.oid=p.proowner
    where n.nspname='crm'
      and p.proname='metricas_distribucion_leads_v2_fn'
      and pg_get_function_identity_arguments(p.oid)='p_desde date, p_hasta date'
      and r.rolname='crm_metricas_bridge'
      and p.prosecdef
  ) then
    raise exception 'El RPC V2 de distribucion perdio owner o SECURITY DEFINER'
      using errcode='55000';
  end if;
end;
$contract$;

do $membership$
begin
  execute format('revoke crm_metricas_bridge from %I', current_user);
end;
$membership$;

-- ============================================================================
-- 6. Retiro explicito de las dos fuentes legacy de metas
-- ============================================================================

-- Ninguna de las dos formas antiguas es mapeable sin inventar informacion:
-- crm.objetivos era por rol y objetivos_vendedores no separaba categoria/USD.
-- Se preservan como archivo SQL inmutable y sin acceso Data API; no participan
-- en configuracion_metas_fn ni cumplimiento_metas_fn.
alter table crm.objetivos rename to objetivos_legacy_archivo;
alter table crm.objetivos_vendedores rename to objetivos_vendedores_legacy_archivo;

-- El archivo no forma parte de la Data API. Retirar tambien las politicas
-- heredadas evita conservar evaluaciones de autorizacion sin consumidores y
-- mantiene limpio el advisor de RLS; service_role conserva el SELECT directo
-- mediante BYPASSRLS y el grant minimo declarado mas abajo.
drop policy if exists crm_actor_activo_gate
  on crm.objetivos_legacy_archivo;
drop policy if exists objetivos_select
  on crm.objetivos_legacy_archivo;
drop policy if exists crm_actor_activo_gate
  on crm.objetivos_vendedores_legacy_archivo;
drop policy if exists objetivos_vendedores_select
  on crm.objetivos_vendedores_legacy_archivo;

comment on table crm.objetivos_legacy_archivo is
  'ARCHIVO NO CANONICO: metas antiguas por rol, imposibles de repartir por vendedor/categoria/moneda sin inventar datos.';
comment on table crm.objetivos_vendedores_legacy_archivo is
  'ARCHIVO NO CANONICO: metas individuales previas sin categoria ni USD. La fuente vigente es meta_periodos/metas_vendedor/metas_vendedor_detalle.';

create or replace function private.trg_archivo_metas_legacy_inmutable()
returns trigger language plpgsql security definer set search_path='pg_catalog'
as $function$
begin
  raise exception 'El archivo legacy de metas es inmutable' using errcode='55000';
end;
$function$;

create trigger trg_objetivos_legacy_archivo_inmutable
before insert or update or delete on crm.objetivos_legacy_archivo
for each row execute function private.trg_archivo_metas_legacy_inmutable();
create trigger trg_objetivos_vendedores_legacy_archivo_inmutable
before insert or update or delete on crm.objetivos_vendedores_legacy_archivo
for each row execute function private.trg_archivo_metas_legacy_inmutable();

revoke all on table crm.objetivos_legacy_archivo
  from public,anon,authenticated,service_role;
revoke all on table crm.objetivos_vendedores_legacy_archivo
  from public,anon,authenticated,service_role;
grant select on table crm.objetivos_legacy_archivo to service_role;
grant select on table crm.objetivos_vendedores_legacy_archivo to service_role;

drop function crm.fijar_objetivos(date,jsonb);
drop function crm.fijar_objetivos_vendedores(date,jsonb);

revoke all on function private.trg_archivo_metas_legacy_inmutable()
  from public,anon,authenticated,service_role;

-- ============================================================================
-- 7. Hardening integral de actores y sujetos operativos
-- ============================================================================

-- Los agregados historicos se conservan, pero sus desgloses vivos nunca deben
-- convertir una fila cruda de crm.equipo en autoridad o identidad operativa.
create or replace function private.filtrar_desglose_sujetos_crm(
  p_payload jsonb,
  p_clave text,
  p_clave_id text,
  p_roles text[]
)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_elemento jsonb;
  v_id uuid;
  v_filtrados jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(p_payload->p_clave) <> 'array' then
    raise exception 'Contrato interno de metricas inesperado'
      using errcode='55000';
  end if;

  for v_elemento in
    select elemento.value
    from jsonb_array_elements(p_payload->p_clave) elemento
  loop
    begin
      v_id := (v_elemento->>p_clave_id)::uuid;
    exception when invalid_text_representation then
      raise exception 'Identidad interna de metricas invalida'
        using errcode='55000';
    end;

    if private.rol_crm(v_id) = any(p_roles) then
      v_filtrados := v_filtrados || jsonb_build_array(v_elemento);
    end if;
  end loop;

  return jsonb_set(p_payload,array[p_clave],v_filtrados,false);
end;
$function$;

-- Distribucion mezcla deliberadamente historia e inventario vivo. Una persona
-- que ya no tiene rol efectivo permanece para conciliacion, pero jamas queda
-- marcada como activa/disponible ni su bandeja como destino activo.
create or replace function private.sanitizar_sujetos_distribucion_crm(
  p_payload jsonb
)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_elemento jsonb;
  v_id uuid;
  v_analistas jsonb := '[]'::jsonb;
  v_bandejas jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(p_payload->'analistas') <> 'array'
     or jsonb_typeof(p_payload#>'{por_repartir,bandejas}') <> 'array' then
    raise exception 'Contrato interno de distribucion inesperado'
      using errcode='55000';
  end if;

  for v_elemento in
    select elemento.value from jsonb_array_elements(p_payload->'analistas') elemento
  loop
    begin
      v_id := (v_elemento->>'analista_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Identidad interna de distribucion invalida'
        using errcode='55000';
    end;
    if not coalesce(
      private.rol_crm(v_id) in ('vendedor','supervisor'),
      false
    ) then
      v_elemento := v_elemento || jsonb_build_object(
        'activo',false,
        'disponible_para_recibir',false
      );
    end if;
    v_analistas := v_analistas || jsonb_build_array(v_elemento);
  end loop;

  for v_elemento in
    select elemento.value
    from jsonb_array_elements(p_payload#>'{por_repartir,bandejas}') elemento
  loop
    begin
      v_id := (v_elemento->>'supervisor_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Bandeja interna de distribucion invalida'
        using errcode='55000';
    end;
    if private.rol_crm(v_id) is distinct from 'supervisor' then
      v_elemento := v_elemento || jsonb_build_object('supervisor_activo',false);
    end if;
    v_bandejas := v_bandejas || jsonb_build_array(v_elemento);
  end loop;

  p_payload := jsonb_set(p_payload,'{analistas}',v_analistas,false);
  return jsonb_set(p_payload,'{por_repartir,bandejas}',v_bandejas,false);
end;
$function$;

revoke all on function private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])
  from public,anon,authenticated,service_role;
revoke all on function private.sanitizar_sujetos_distribucion_crm(jsonb)
  from public,anon,authenticated,service_role;

-- Reemplaza el ultimo gate directo de distribucion. Los cores siguen siendo
-- historicos; esta unica frontera canoniza actor y disponibilidad de sujetos.
create or replace function private.metricas_distribucion_leads_autorizada(
  p_desde date,
  p_hasta date,
  p_version smallint
)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'Solo Gerencia o un lector global puede consultar estas metricas'
      using errcode='42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde>p_hasta
     or p_hasta>v_hoy or p_hasta-p_desde>365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode='22023';
  end if;

  if p_version=1 then
    v_payload:=private.metricas_distribucion_leads_core(p_desde,p_hasta,v_ahora);
  elsif p_version=2 then
    v_payload:=private.metricas_distribucion_leads_v2_core(p_desde,p_hasta,v_ahora);
  else
    raise exception 'Version de metricas no soportada' using errcode='22023';
  end if;
  return private.sanitizar_sujetos_distribucion_crm(v_payload);
end;
$function$;

-- Las tres metricas antiguas conservan sus agregados globales, pero se guardan
-- como implementaciones privadas. Los entrypoints finales anteponen rol efectivo
-- y eliminan del desglose vivo cualquier sujeto enmascarado.
alter function crm.metricas_agenda_fn(date,date) set schema private;
alter function private.metricas_agenda_fn(date,date)
  rename to metricas_agenda_implementacion;
revoke all on function private.metricas_agenda_implementacion(date,date)
  from public,anon,authenticated,service_role;

create function crm.metricas_agenda_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor) in ('vendedor','supervisor','gerencia')
    or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_agenda_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'vendedores','vendedor_id',array['vendedor','supervisor']
  );
end;
$function$;

alter function crm.metricas_conversiones_fn(date,date) set schema private;
alter function private.metricas_conversiones_fn(date,date)
  rename to metricas_conversiones_implementacion;
revoke all on function private.metricas_conversiones_implementacion(date,date)
  from public,anon,authenticated,service_role;

create function crm.metricas_conversiones_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_conversiones_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'responsables','vendedor_id',array['vendedor']
  );
end;
$function$;

alter function crm.metricas_reuniones_fn(date,date) set schema private;
alter function private.metricas_reuniones_fn(date,date)
  rename to metricas_reuniones_implementacion;
revoke all on function private.metricas_reuniones_implementacion(date,date)
  from public,anon,authenticated,service_role;

create function crm.metricas_reuniones_fn(p_desde date,p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path=''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_payload:=private.metricas_reuniones_implementacion(p_desde,p_hasta);
  return private.filtrar_desglose_sujetos_crm(
    v_payload,'responsables','responsable_id',array['vendedor','supervisor']
  );
end;
$function$;

revoke all on function crm.metricas_agenda_fn(date,date)
  from public,anon,authenticated,service_role;
revoke all on function crm.metricas_conversiones_fn(date,date)
  from public,anon,authenticated,service_role;
revoke all on function crm.metricas_reuniones_fn(date,date)
  from public,anon,authenticated,service_role;
grant execute on function crm.metricas_agenda_fn(date,date) to authenticated;
grant execute on function crm.metricas_conversiones_fn(date,date) to authenticated;
grant execute on function crm.metricas_reuniones_fn(date,date) to authenticated;

-- Capacidad es inventario vivo, no historia: actor y objetivo pasan por el rol
-- efectivo antes de delegar en la implementacion auditada existente.
alter function crm.actualizar_capacidad_leads_objetivo(uuid,integer)
  set schema private;
alter function private.actualizar_capacidad_leads_objetivo(uuid,integer)
  rename to actualizar_capacidad_leads_objetivo_implementacion;
revoke all on function private.actualizar_capacidad_leads_objetivo_implementacion(uuid,integer)
  from public,anon,authenticated,service_role;

create function crm.actualizar_capacidad_leads_objetivo(
  p_analista_id uuid,
  p_capacidad_leads_objetivo integer
)
returns table(perfil_id uuid,capacidad_leads_objetivo smallint)
language plpgsql security definer set search_path=''
as $function$
begin
  if private.rol_crm((select auth.uid())) is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede configurar la capacidad de los analistas'
      using errcode='42501';
  end if;
  if not coalesce(
    private.rol_crm(p_analista_id) in ('vendedor','supervisor'),
    false
  ) then
    raise exception 'Analista activo no encontrado' using errcode='P0002';
  end if;
  return query
  select * from private.actualizar_capacidad_leads_objetivo_implementacion(
    p_analista_id,p_capacidad_leads_objetivo
  );
end;
$function$;

revoke all on function crm.actualizar_capacidad_leads_objetivo(uuid,integer)
  from public,anon,authenticated,service_role;
grant execute on function crm.actualizar_capacidad_leads_objetivo(uuid,integer)
  to authenticated;

-- Toda tarea pendiente y activa requiere un dueño efectivo. El trigger cubre
-- RLS, service_role y las siguientes tareas creadas desde funciones definer.
create or replace function private.trg_tareas_destino_efectivo()
returns trigger
language plpgsql security definer set search_path=''
as $function$
begin
  if new.activo is true and new.estado='pendiente' then
    if new.vendedor_id is null and new.asignado_supervisor_id is null then
      raise exception 'La tarea pendiente requiere un destino CRM efectivo'
        using errcode='23514';
    end if;
    if new.vendedor_id is not null and not private.es_destino_crm_activo(
      new.vendedor_id,array['vendedor','supervisor']
    ) then
      raise exception 'El responsable de la tarea no tiene rol CRM efectivo'
        using errcode='23514';
    end if;
    if new.asignado_supervisor_id is not null and not private.es_destino_crm_activo(
      new.asignado_supervisor_id,array['supervisor']
    ) then
      raise exception 'La bandeja de la tarea no pertenece a un Supervisor efectivo'
        using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_tareas_01_destino_efectivo_insert on crm.tareas;
create trigger trg_tareas_01_destino_efectivo_insert
before insert on crm.tareas
for each row execute function private.trg_tareas_destino_efectivo();
drop trigger if exists trg_tareas_01_destino_efectivo_update on crm.tareas;
create trigger trg_tareas_01_destino_efectivo_update
before update of vendedor_id,asignado_supervisor_id,activo,estado on crm.tareas
for each row execute function private.trg_tareas_destino_efectivo();

drop policy if exists tareas_destino_efectivo_insert on crm.tareas;
create policy tareas_destino_efectivo_insert on crm.tareas
as restrictive for insert to authenticated
with check (
  not (activo is true and estado='pendiente')
  or (
    (vendedor_id is not null or asignado_supervisor_id is not null)
    and
    (vendedor_id is null or private.rol_crm(vendedor_id) in ('vendedor','supervisor'))
    and (asignado_supervisor_id is null or private.rol_crm(asignado_supervisor_id)='supervisor')
  )
);
drop policy if exists tareas_destino_efectivo_update on crm.tareas;
create policy tareas_destino_efectivo_update on crm.tareas
as restrictive for update to authenticated
using (true)
with check (
  not (activo is true and estado='pendiente')
  or (
    (vendedor_id is not null or asignado_supervisor_id is not null)
    and
    (vendedor_id is null or private.rol_crm(vendedor_id) in ('vendedor','supervisor'))
    and (asignado_supervisor_id is null or private.rol_crm(asignado_supervisor_id)='supervisor')
  )
);

revoke all on function private.trg_tareas_destino_efectivo()
  from public,anon,authenticated,service_role;

-- El importador server-to-server resuelve por correo exclusivamente a traves
-- del mismo rol efectivo; la Edge no vuelve a reconstruir la regla con tablas.
create or replace function crm.destinos_importacion_por_correo_fn(p_correos text[])
returns table(correo text,perfil_id uuid)
language sql stable security definer set search_path=''
as $function$
  select lower(p.correo),p.id
  from public.perfiles p
  where p.correo is not null
    and lower(p.correo) in (
      select lower(btrim(correo_solicitado))
      from unnest(coalesce(p_correos,array[]::text[])) correo_solicitado
      where nullif(btrim(correo_solicitado),'') is not null
    )
    and private.rol_crm(p.id) in ('vendedor','supervisor');
$function$;

revoke all on function crm.destinos_importacion_por_correo_fn(text[])
  from public,anon,authenticated,service_role;
grant execute on function crm.destinos_importacion_por_correo_fn(text[])
  to service_role;

commit;
