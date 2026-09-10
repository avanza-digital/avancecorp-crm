-- CRM · Reparto conforme al turno y trazabilidad inmediata de Coordinación.
--
-- Incidente 2026-09-10: el turno decía Landing → Jor, pero 20 Landing fueron
-- enviados a Carmen. La mutación aceptaba cualquier supervisor activo y la
-- agenda contaba únicamente los movimientos que coincidían con el plan; por
-- eso el error quedaba oculto. Este cambio convierte el turno en una regla del
-- servidor y muestra todas las entregas reales, incluidas las históricas fuera
-- de turno, sin exponer datos personales de los leads.

begin;

set local search_path = '';
set local lock_timeout = '5s';
set local statement_timeout = '60s';

select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('crm.reparto_turno_obligatorio'),
  pg_catalog.hashtext('migracion')
);

-- agenda_reparto_diaria pertenece al censo sellado de analítica. Se bloquean
-- su registro y su sello para reemplazar la función y recertificarla juntos.
lock table private.analitica_leads_citas_exenciones in share row exclusive mode;
lock table private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  v_reparto text;
  v_agenda text;
  v_guardado text;
begin
  if pg_catalog.to_regprocedure('private.repartir_lead_implementacion(uuid,uuid)') is null
     or pg_catalog.to_regprocedure('crm.agenda_reparto_diaria(date,integer)') is null
     or pg_catalog.to_regprocedure('crm.guardar_agenda_reparto_diaria(date,uuid,uuid)') is null
     or pg_catalog.to_regclass('private.agenda_reparto_diaria') is null
     or pg_catalog.to_regclass('private.agenda_reparto_destinos') is null then
    raise exception 'Reparto por turno: faltan las funciones o tablas base de la agenda';
  end if;

  perform private.assert_analitica_leads_citas();

  select p.prosrc into v_reparto
  from pg_catalog.pg_proc p
  where p.oid = 'private.repartir_lead_implementacion(uuid,uuid)'::pg_catalog.regprocedure;

  if pg_catalog.strpos(v_reparto, 'private.persona_vetada') = 0 then
    raise exception 'Reparto por turno: la implementación viva perdió el veto de persona';
  end if;

  select p.prosrc into v_agenda
  from pg_catalog.pg_proc p
  where p.oid = 'crm.agenda_reparto_diaria(date,integer)'::pg_catalog.regprocedure;

  if pg_catalog.strpos(v_agenda, 'entra_bandeja') = 0
     or pg_catalog.strpos(v_agenda, 'supervisor_nuevo') = 0 then
    raise exception 'Reparto por turno: cambió la fuente de evidencia de la agenda';
  end if;

  select p.prosrc into v_guardado
  from pg_catalog.pg_proc p
  where p.oid = 'crm.guardar_agenda_reparto_diaria(date,uuid,uuid)'::pg_catalog.regprocedure;

  if pg_catalog.strpos(v_guardado, 'agenda-reparto:') = 0 then
    raise exception 'Reparto por turno: guardar agenda ya no usa el candado diario esperado';
  end if;
end;
$preflight$;

-- La implementación privada conserva todos sus vetos y el CAS de la cola.
-- Para Landing/Formulario agrega un candado compartido con guardar_agenda:
-- muchos repartos pueden correr a la vez, pero ninguno se cruza con un cambio
-- del turno del mismo día.
create or replace function private.repartir_lead_implementacion(
  p_lead uuid,
  p_supervisor uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.statement_timestamp() at time zone 'America/Lima')::date;
  v_lead crm.leads%rowtype;
  v_sup_nombre text;
  v_turno_supervisor uuid;
  v_turno_nombre text;
  v_origen_nombre text;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador', 'gerencia')
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads'
      using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios'
      using errcode = '22023';
  end if;

  select perfil.nombre_completo into v_sup_nombre
  from crm.equipo equipo
  join public.perfiles perfil on perfil.id = equipo.perfil_id
  where equipo.perfil_id = p_supervisor
    and equipo.rol_crm = 'supervisor'
    and equipo.activo = true
    and perfil.activo = true;

  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads lead
  where lead.id = p_lead
    and lead.activo = true
    and lead.vendedor_id is null
    and lead.asignado_supervisor_id is null
    and lead.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
  for update;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  -- F2.b (b2): el veto pertenece a la persona, no solo a esta fila de lead.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede repartir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- Turno obligatorio 2026-09-10. El navegador lo preselecciona, pero esta es
  -- la garantía real: también cubre pestañas antiguas, llamadas manuales y
  -- dos sesiones simultáneas.
  if v_lead.origen in ('landing', 'formulario') then
    perform pg_catalog.pg_advisory_xact_lock_shared(
      pg_catalog.hashtextextended('agenda-reparto:' || v_hoy::text, 0)
    );

    select
      agenda.supervisor_id,
      coalesce(destino.alias, perfil.nombre_completo)
    into v_turno_supervisor, v_turno_nombre
    from private.agenda_reparto_diaria agenda
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id = agenda.supervisor_id
    left join public.perfiles perfil
      on perfil.id = agenda.supervisor_id
    where agenda.fecha = v_hoy
      and agenda.origen = v_lead.origen;

    v_origen_nombre := case v_lead.origen
      when 'landing' then 'Landing'
      else 'Formulario'
    end;

    if not found then
      raise exception 'Antes de repartir %, guarda el turno de hoy en «Coordinación → supervisores»',
        v_origen_nombre
        using errcode = '22023';
    end if;

    if p_supervisor is distinct from v_turno_supervisor then
      raise exception 'Según el turno de hoy, % corresponde a %. El destino no se cambió',
        v_origen_nombre,
        coalesce(v_turno_nombre, 'la supervisora programada')
        using errcode = '22023';
    end if;
  end if;

  update crm.leads
  set asignado_supervisor_id = p_supervisor
  where id = p_lead
    and activo = true
    and vendedor_id is null
    and asignado_supervisor_id is null;

  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return pg_catalog.jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'repartido_en', pg_catalog.statement_timestamp()
  );
end;
$function$;

revoke all on function private.repartir_lead_implementacion(uuid, uuid)
  from public, anon, authenticated, service_role;

comment on function private.repartir_lead_implementacion(uuid, uuid) is
  'Implementación privada del reparto. Conserva veto de persona y CAS; Landing/Formulario exigen el destino de la agenda Lima del día bajo candado compartido.';

-- El plan y lo ocurrido dejan de confundirse: derivados cuenta TODAS las
-- entradas reales del origen y entregas las desglosa por supervisor. Una fila
-- histórica contraria al turno queda visible en fuera_turno en vez de borrarse
-- del conteo por no coincidir con el plan.
create or replace function crm.agenda_reparto_diaria(
  p_desde date default ((pg_catalog.statement_timestamp() at time zone 'America/Lima')::date),
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
    select
      destino.supervisor_id,
      destino.alias,
      destino.orden,
      perfil.nombre_completo
    from private.agenda_reparto_destinos destino
    join crm.equipo equipo on equipo.perfil_id = destino.supervisor_id
    join public.perfiles perfil on perfil.id = destino.supervisor_id
    where equipo.rol_crm = 'supervisor'
      and equipo.activo = true
      and perfil.activo = true
  ),
  movimientos as materialized (
    select
      (actividad.creado_en at time zone 'America/Lima')::date as fecha,
      lead.origen,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', '') as supervisor_id,
      perfil.nombre_completo as supervisor_nombre,
      destino.alias as supervisor_alias,
      pg_catalog.count(*)::integer as derivados
    from crm.actividades actividad
    join crm.leads lead on lead.id = actividad.lead_id
    left join public.perfiles perfil
      on perfil.id::text = actividad.metadata ->> 'supervisor_nuevo'
    left join private.agenda_reparto_destinos destino
      on destino.supervisor_id::text = actividad.metadata ->> 'supervisor_nuevo'
    where actividad.tipo = 'reasignacion'
      and actividad.metadata ->> 'movimiento' = 'entra_bandeja'
      and lead.origen in ('landing', 'formulario')
      and actividad.creado_en >= (p_desde::timestamp at time zone 'America/Lima')
      and actividad.creado_en < ((p_desde + p_dias)::timestamp at time zone 'America/Lima')
    group by
      (actividad.creado_en at time zone 'America/Lima')::date,
      lead.origen,
      coalesce(actividad.metadata ->> 'supervisor_nuevo', ''),
      perfil.nombre_completo,
      destino.alias
  ),
  agenda as materialized (
    select
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias as supervisor_alias,
      destino.nombre_completo as supervisor_nombre,
      coalesce(pg_catalog.sum(movimiento.derivados), 0)::integer as derivados,
      coalesce(
        pg_catalog.sum(movimiento.derivados) filter (
          where movimiento.supervisor_id is distinct from plan.supervisor_id::text
        ),
        0
      )::integer as fuera_turno,
      coalesce(
        pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'supervisor_id', nullif(movimiento.supervisor_id, ''),
            'supervisor_nombre', coalesce(
              movimiento.supervisor_nombre,
              'Supervisor no disponible'
            ),
            'supervisor_alias', movimiento.supervisor_alias,
            'derivados', movimiento.derivados,
            'coincide_turno', coalesce(
              movimiento.supervisor_id = plan.supervisor_id::text,
              false
            )
          ) order by coalesce(
            movimiento.supervisor_alias,
            movimiento.supervisor_nombre,
            movimiento.supervisor_id
          )
        ) filter (where movimiento.derivados is not null),
        '[]'::jsonb
      ) as entregas
    from dias dia
    cross join (values ('landing'::text, 1), ('formulario'::text, 2)) as origen(origen, orden)
    left join private.agenda_reparto_diaria plan
      on plan.fecha = dia.fecha
      and plan.origen = origen.origen
    left join destinos destino
      on destino.supervisor_id = plan.supervisor_id
    left join movimientos movimiento
      on movimiento.fecha = dia.fecha
      and movimiento.origen = origen.origen
    group by
      dia.fecha,
      origen.origen,
      origen.orden,
      plan.supervisor_id,
      destino.alias,
      destino.nombre_completo
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
                'derivados', fila.derivados,
                'fuera_turno', fila.fuera_turno,
                'entregas', fila.entregas
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

comment on function crm.agenda_reparto_diaria(date, integer) is
  'Primera etapa del reparto: plan Landing/Formulario y todas las entregas reales de Coordinación desglosadas por supervisor, con total fuera de turno. Sin PII; solo Coordinación o Gerencia.';

revoke all on function crm.agenda_reparto_diaria(date, integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.agenda_reparto_diaria(date, integer) to authenticated;

-- Recertifica solo esta función y vuelve a sellar la lista completa.
do $reseal$
declare
  v_actualizadas integer;
  v_selladas integer;
begin
  update private.analitica_leads_citas_exenciones exencion
  set
    huella = (
      select pg_catalog.md5(pg_catalog.regexp_replace(pg_catalog.regexp_replace(
        pg_catalog.lower(coalesce(procedimiento.prosrc, pg_catalog.pg_get_functiondef(procedimiento.oid))),
        '--[^\n]*', ' ', 'g'
      ), '/\*.*?\*/', ' ', 'g'))
      from pg_catalog.pg_proc procedimiento
      where procedimiento.oid = pg_catalog.to_regprocedure(exencion.objeto)
    ),
    razon = 'Operativa de reparto: muestra el turno y cuenta todas las entregas reales de Coordinación por destino; evidencia de flujo, no métrica de conversión.'
  where exencion.objeto = 'crm.agenda_reparto_diaria(date,integer)';

  get diagnostics v_actualizadas = row_count;
  if v_actualizadas <> 1 then
    raise exception 'Reparto por turno: se esperaba recertificar una función, se actualizaron %',
      v_actualizadas;
  end if;

  update private.analitica_lc_sello
  set
    sello = private.huella_exenciones_analitica_lc(),
    sellado_en = pg_catalog.now()
  where id;

  get diagnostics v_selladas = row_count;
  if v_selladas <> 1 then
    raise exception 'Reparto por turno: no se pudo renovar el sello del censo';
  end if;
end;
$reseal$;

do $postflight$
declare
  v_reparto text;
  v_agenda text;
begin
  select p.prosrc into v_reparto
  from pg_catalog.pg_proc p
  where p.oid = 'private.repartir_lead_implementacion(uuid,uuid)'::pg_catalog.regprocedure;

  select p.prosrc into v_agenda
  from pg_catalog.pg_proc p
  where p.oid = 'crm.agenda_reparto_diaria(date,integer)'::pg_catalog.regprocedure;

  if pg_catalog.strpos(v_reparto, 'pg_advisory_xact_lock_shared') = 0
     or pg_catalog.strpos(v_reparto, 'agenda_reparto_diaria') = 0
     or pg_catalog.strpos(v_reparto, 'private.persona_vetada') = 0 then
    raise exception 'POSTFLIGHT reparto por turno: la mutación perdió una garantía';
  end if;

  if pg_catalog.strpos(v_agenda, 'fuera_turno') = 0
     or pg_catalog.strpos(v_agenda, '''entregas''') = 0 then
    raise exception 'POSTFLIGHT reparto por turno: la agenda no expone la evidencia real';
  end if;

  if pg_catalog.has_function_privilege(
       'authenticated',
       'private.repartir_lead_implementacion(uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.agenda_reparto_diaria(date,integer)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.agenda_reparto_diaria(date,integer)',
       'EXECUTE'
     ) then
    raise exception 'POSTFLIGHT reparto por turno: ACL incorrecta';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    where p.oid = 'crm.agenda_reparto_diaria(date,integer)'::pg_catalog.regprocedure
      and p.prosecdef = true
      and p.provolatile = 's'
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'POSTFLIGHT reparto por turno: atributos incorrectos en agenda_reparto_diaria';
  end if;

  perform private.assert_analitica_leads_citas();
end;
$postflight$;

commit;
