-- La agenda puede empezar a registrarse después del primer reparto del día.
-- Solo se bloquea reescribir un carril que YA tenía turno y evidencia real.

begin;

set local lock_timeout = '5s';

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

  -- El primer registro de hoy se permite aunque el reparto haya empezado:
  -- Rosa puede dejar asentado el turno vigente. A partir de ahí, si ya hay
  -- evidencia de reparto, el carril no se reescribe sobre esa evidencia.
  if p_fecha = v_hoy
    and v_landing_anterior is not null
    and v_landing_anterior is distinct from p_landing
    and exists (
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

  if p_fecha = v_hoy
    and v_formulario_anterior is not null
    and v_formulario_anterior is distinct from p_formulario
    and exists (
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

comment on function crm.guardar_agenda_reparto_diaria(date, uuid, uuid) is
  'Guarda el turno diario Landing/Formulario para Carmen y Jor. Permite el primer registro de hoy aun si hubo reparto y bloquea reescribir un carril previamente guardado con evidencia real.';

commit;
