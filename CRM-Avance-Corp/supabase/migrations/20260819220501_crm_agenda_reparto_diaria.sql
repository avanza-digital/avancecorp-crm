-- ============================================================================
-- CRM · Agenda diaria de reparto para Coordinación
--
-- Rosa programa únicamente los dos carriles que requieren orden comercial:
-- Landing y Formulario. La agenda deja claro cuál corresponde a Carmen y cuál
-- a Jor para cada fecha; el historial de actividades conserva la evidencia
-- real de los leads que sí entraron a cada bandeja.
--
-- La configuración y su bitácora viven en private. Coordinación no recibe
-- SELECT directo a esas tablas, a crm.leads ni a crm.actividades: las dos RPC
-- devuelven solo fecha, origen, supervisor y conteos agregados.
-- ============================================================================

begin;

set local lock_timeout = '5s';

create table if not exists private.agenda_reparto_destinos (
  supervisor_id uuid primary key references crm.equipo(perfil_id) on delete restrict,
  alias text not null check (char_length(btrim(alias)) between 1 and 40),
  orden smallint not null unique check (orden between 1 and 9),
  creado_en timestamptz not null default statement_timestamp()
);

create table if not exists private.agenda_reparto_diaria (
  fecha date not null,
  origen text not null check (origen in ('landing', 'formulario')),
  supervisor_id uuid not null references private.agenda_reparto_destinos(supervisor_id) on delete restrict,
  creado_por uuid not null references public.perfiles(id) on delete restrict,
  creado_en timestamptz not null default statement_timestamp(),
  actualizado_por uuid not null references public.perfiles(id) on delete restrict,
  actualizado_en timestamptz not null default statement_timestamp(),
  primary key (fecha, origen)
);

create table if not exists private.agenda_reparto_cambios (
  id bigint generated always as identity primary key,
  fecha date not null,
  origen text not null check (origen in ('landing', 'formulario')),
  supervisor_anterior_id uuid references private.agenda_reparto_destinos(supervisor_id) on delete restrict,
  supervisor_nuevo_id uuid not null references private.agenda_reparto_destinos(supervisor_id) on delete restrict,
  cambiado_por uuid not null references public.perfiles(id) on delete restrict,
  cambiado_en timestamptz not null default statement_timestamp()
);

create index if not exists agenda_reparto_cambios_fecha_idx
  on private.agenda_reparto_cambios (fecha desc, cambiado_en desc);

alter table private.agenda_reparto_destinos enable row level security;
alter table private.agenda_reparto_destinos force row level security;
alter table private.agenda_reparto_diaria enable row level security;
alter table private.agenda_reparto_diaria force row level security;
alter table private.agenda_reparto_cambios enable row level security;
alter table private.agenda_reparto_cambios force row level security;

revoke all on table private.agenda_reparto_destinos
  from public, anon, authenticated, service_role;
revoke all on table private.agenda_reparto_diaria
  from public, anon, authenticated, service_role;
revoke all on table private.agenda_reparto_cambios
  from public, anon, authenticated, service_role;

-- Configuración inicial solicitada: las dos supervisoras activas que Rosa usa
-- para este turno. Se busca por nombre para que un reset local sin los perfiles
-- de producción no falle; el destino queda fijado por UUID después del seed.
insert into private.agenda_reparto_destinos (supervisor_id, alias, orden)
select
  equipo.perfil_id,
  case perfil.nombre_completo
    when 'CARMEN JARAMILLO' then 'Carmen'
    when 'JORGE MARZANO' then 'Jor'
  end,
  case perfil.nombre_completo
    when 'CARMEN JARAMILLO' then 1
    when 'JORGE MARZANO' then 2
  end
from crm.equipo equipo
join public.perfiles perfil on perfil.id = equipo.perfil_id
where equipo.rol_crm = 'supervisor'
  and equipo.activo = true
  and perfil.activo = true
  and perfil.nombre_completo in ('CARMEN JARAMILLO', 'JORGE MARZANO')
on conflict (supervisor_id) do update
set alias = excluded.alias,
    orden = excluded.orden;

create or replace function crm.agenda_reparto_diaria(
  p_desde date default ((statement_timestamp() at time zone 'America/Lima')::date),
  p_dias integer default 7
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  if p_desde is null or p_dias is null or p_dias < 1 or p_dias > 14 then
    raise exception 'La agenda requiere una fecha y entre 1 y 14 días'
      using errcode = '22023';
  end if;

  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver la agenda de reparto'
      using errcode = '42501';
  end if;

  with
  dias as materialized (
    select serie::date as fecha
    from pg_catalog.generate_series(
      p_desde::timestamp,
      (p_desde + (p_dias - 1))::timestamp,
      interval '1 day'
    ) as serie
  ),
  destinos as materialized (
    select destino.supervisor_id, destino.alias, destino.orden, perfil.nombre_completo
    from private.agenda_reparto_destinos destino
    join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
    join public.perfiles perfil on perfil.id = destino.supervisor_id
    where equipo.rol_crm = 'supervisor'
      and equipo.activo = true
      and perfil.activo = true
    order by destino.orden
  ),
  agenda as materialized (
    select
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias as supervisor_alias,
      destino.nombre_completo as supervisor_nombre,
      coalesce(realizados.total_leads, 0) as derivados
    from dias dia
    cross join (values ('landing'::text, 1), ('formulario'::text, 2)) as origen(origen, orden)
    left join private.agenda_reparto_diaria plan
      on plan.fecha = dia.fecha and plan.origen = origen.origen
    left join destinos destino on destino.supervisor_id = plan.supervisor_id
    left join lateral (
      select count(*)::int as total_leads
      from crm.actividades actividad
      join crm.leads lead on lead.id = actividad.lead_id
      where actividad.tipo = 'reasignacion'
        and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
        and actividad.metadata ->> 'supervisor_nuevo' = plan.supervisor_id::text
        and lead.origen = origen.origen
        and actividad.creado_en >= (dia.fecha::timestamp at time zone 'America/Lima')
        and actividad.creado_en < ((dia.fecha + 1)::timestamp at time zone 'America/Lima')
    ) realizados on true
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'fecha_desde', p_desde,
    'destinos', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'perfil_id', destino.supervisor_id,
          'nombre', destino.nombre_completo,
          'alias', destino.alias
        ) order by destino.orden
      )
      from destinos destino
    ), '[]'::jsonb),
    'dias', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'fecha', dia.fecha,
          'asignaciones', coalesce((
            select pg_catalog.jsonb_agg(
              pg_catalog.jsonb_build_object(
                'origen', fila.origen,
                'supervisor_id', fila.supervisor_id,
                'supervisor_nombre', fila.supervisor_nombre,
                'supervisor_alias', fila.supervisor_alias,
                'derivados', fila.derivados
              ) order by fila.orden
            )
            from agenda fila
            where fila.fecha = dia.fecha
          ), '[]'::jsonb)
        ) order by dia.fecha
      )
      from dias dia
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

create or replace function crm.guardar_agenda_reparto_diaria(
  p_fecha date,
  p_landing uuid,
  p_formulario uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_landing_anterior uuid;
  v_formulario_anterior uuid;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede guardar la agenda de reparto'
      using errcode = '42501';
  end if;

  if p_fecha is null or p_landing is null or p_formulario is null then
    raise exception 'Fecha, Landing y Formulario son obligatorios'
      using errcode = '22023';
  end if;

  if p_fecha < v_hoy then
    raise exception 'La agenda de días anteriores es un registro y no puede modificarse'
      using errcode = '22023';
  end if;

  if p_landing = p_formulario then
    raise exception 'Landing y Formulario deben quedar en supervisoras distintas'
      using errcode = '22023';
  end if;

  if (select count(*) from private.agenda_reparto_destinos destino
      join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
      join public.perfiles perfil on perfil.id = destino.supervisor_id
      where destino.supervisor_id in (p_landing, p_formulario)
        and equipo.rol_crm = 'supervisor'
        and equipo.activo = true
        and perfil.activo = true) <> 2 then
    raise exception 'La agenda solo puede usar a Carmen o Jor mientras estén activas'
      using errcode = '22023';
  end if;

  -- Serializa ediciones del mismo día: evita que dos pestañas de Rosa generen
  -- una agenda y una bitácora que no correspondan entre sí.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('agenda-reparto:' || p_fecha::text, 0)
  );

  select supervisor_id into v_landing_anterior
  from private.agenda_reparto_diaria
  where fecha = p_fecha and origen = 'landing'
  for update;

  select supervisor_id into v_formulario_anterior
  from private.agenda_reparto_diaria
  where fecha = p_fecha and origen = 'formulario'
  for update;

  -- Una vez que hubo reparto real de ese carril, no se reescribe el plan de
  -- hoy. Así «conforme al plan» conserva un significado verificable.
  if p_fecha = v_hoy and v_landing_anterior is distinct from p_landing and exists (
    select 1
    from crm.actividades actividad
    join crm.leads lead on lead.id = actividad.lead_id
    where actividad.tipo = 'reasignacion'
      and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
      and lead.origen = 'landing'
      and actividad.creado_en >= (p_fecha::timestamp at time zone 'America/Lima')
      and actividad.creado_en < ((p_fecha + 1)::timestamp at time zone 'America/Lima')
  ) then
    raise exception 'Landing ya tiene derivaciones hoy; su plan quedó registrado'
      using errcode = '22023';
  end if;

  if p_fecha = v_hoy and v_formulario_anterior is distinct from p_formulario and exists (
    select 1
    from crm.actividades actividad
    join crm.leads lead on lead.id = actividad.lead_id
    where actividad.tipo = 'reasignacion'
      and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
      and lead.origen = 'formulario'
      and actividad.creado_en >= (p_fecha::timestamp at time zone 'America/Lima')
      and actividad.creado_en < ((p_fecha + 1)::timestamp at time zone 'America/Lima')
  ) then
    raise exception 'Formulario ya tiene derivaciones hoy; su plan quedó registrado'
      using errcode = '22023';
  end if;

  insert into private.agenda_reparto_diaria (
    fecha, origen, supervisor_id, creado_por, actualizado_por
  )
  values
    (p_fecha, 'landing', p_landing, v_actor, v_actor),
    (p_fecha, 'formulario', p_formulario, v_actor, v_actor)
  on conflict (fecha, origen) do update
  set supervisor_id = excluded.supervisor_id,
      actualizado_por = excluded.actualizado_por,
      actualizado_en = statement_timestamp();

  if v_landing_anterior is distinct from p_landing then
    insert into private.agenda_reparto_cambios (
      fecha, origen, supervisor_anterior_id, supervisor_nuevo_id, cambiado_por
    ) values (
      p_fecha, 'landing', v_landing_anterior, p_landing, v_actor
    );
  end if;

  if v_formulario_anterior is distinct from p_formulario then
    insert into private.agenda_reparto_cambios (
      fecha, origen, supervisor_anterior_id, supervisor_nuevo_id, cambiado_por
    ) values (
      p_fecha, 'formulario', v_formulario_anterior, p_formulario, v_actor
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'fecha', p_fecha,
    'guardado_en', statement_timestamp()
  );
end;
$function$;

comment on function crm.agenda_reparto_diaria(date, integer) is
  'Agenda de Landing y Formulario con Carmen/Jor y el conteo real diario de entradas a bandeja. Sin PII; solo Coordinacion o Gerencia.';
comment on function crm.guardar_agenda_reparto_diaria(date, uuid, uuid) is
  'Guarda el turno diario Landing/Formulario para Carmen y Jor. Conserva bitácora privada e impide reescribir un carril de hoy que ya tuvo reparto.';

revoke all on function crm.agenda_reparto_diaria(date, integer)
  from public, anon, authenticated, service_role;
revoke all on function crm.guardar_agenda_reparto_diaria(date, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.agenda_reparto_diaria(date, integer) to authenticated;
grant execute on function crm.guardar_agenda_reparto_diaria(date, uuid, uuid) to authenticated;

commit;
