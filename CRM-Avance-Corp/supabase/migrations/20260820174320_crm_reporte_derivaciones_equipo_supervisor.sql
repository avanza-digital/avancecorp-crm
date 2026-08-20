-- ============================================================================
-- CRM · Reporte y reparto de derivaciones para Supervisión
--
-- La fuente histórica es `crm.lead_asignaciones`: cada episodio conserva el
-- monto y moneda que recibió el asesor, aunque el lead se edite después. La
-- pantalla no recibe teléfono, correo, DNI ni notas libres.
--
-- Las escrituras no duplican la auditoría: actualizan `crm.leads` y dejan que
-- los triggers existentes asienten la actividad de reasignación y el ledger.
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- El reporte filtra por supervisor que repartió, fecha y asesor. El índice
-- conserva también el orden de fecha para la franja diaria de operaciones.
create index if not exists lead_asignaciones_reporte_supervisor_fecha_idx
  on crm.lead_asignaciones (
    supervisor_origen_id,
    asignado_por,
    asignado_en desc,
    analista_id
  )
  where motivo_apertura in ('asignado', 'reasignado');

create index if not exists tareas_reversion_gestion_idx
  on crm.tareas (lead_id, creado_por, creado_en)
  where lead_id is not null;

-- RLS evalúa el WITH CHECK con el snapshot de inicio del statement. Si una
-- devolución ya tiene el lead bloqueado, un INSERT del antiguo asesor puede
-- haber aprobado esa policy, esperar por el FK y continuar después del COMMIT
-- sin volver a mirar al dueño nuevo. Este BEFORE toma el MISMO lock de fila y
-- revalida la autorización con EvalPlanQual. Resultado: gana la gestión o gana
-- la devolución, nunca las dos.
create or replace function private.trg_gestion_lead_serializada()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_autorizado boolean := false;
begin
  -- Los writers internos (auth.uid NULL) y los eventos de sistema ya tienen
  -- sus propios gates. No deben quedar atrapados al dispararse desde un UPDATE
  -- del lead que ya posee el lock.
  if v_actor is null
     or (
       tg_table_name = 'actividades'
       and new.tipo in ('cambio_etapa', 'reasignacion', 'conversion')
     ) then
    return new;
  end if;

  -- `crm.tareas` también admite tareas de perfil sin lead; no participan en
  -- una devolución y conservan su policy existente.
  if new.lead_id is null then
    return new;
  end if;

  -- `creado_en` no es inmutable durante INSERT en las tablas heredadas. Un
  -- asesor podría enviar una fecha anterior a la asignación y hacer invisible
  -- su gestión para el candado de devolución. Los inserts manuales reciben un
  -- sello del servidor; writers internos con auth.uid NULL conservan backfill.
  -- Se preservan antes los contratos heredados de NOT NULL/fecha finita: el
  -- sello no debe convertir un payload imposible en una escritura válida.
  if new.creado_en is null then
    raise exception 'La fecha de creación de la gestión es obligatoria'
      using errcode = '23502';
  end if;
  if not pg_catalog.isfinite(new.creado_en) then
    raise exception 'La fecha de creación de la gestión debe ser finita'
      using errcode = '23514';
  end if;

  if new.creado_por is distinct from v_actor then
    raise exception 'La gestión debe quedar atribuida al usuario autenticado'
      using errcode = '42501';
  end if;

  v_rol := private.rol_crm(v_actor);
  select true
    into v_autorizado
  from crm.leads lead
  where lead.id = new.lead_id
    and lead.activo = true
    and (
      v_rol = 'gerencia'
      or lead.vendedor_id = v_actor
      or (
        v_rol = 'supervisor'
        and (
          lead.vendedor_id in (
            select private.vendedor_ids_visibles(v_actor)
          )
          or (
            lead.vendedor_id is null
            and lead.asignado_supervisor_id in (
              select private.vendedor_ids_visibles(v_actor)
            )
          )
        )
      )
    )
  for update;

  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;

  -- El sello se toma DESPUÉS del lock y de la revalidación. `statement_timestamp`
  -- conservaría la hora previa a una espera: si una derivación ganara durante
  -- esa espera, la gestión podría quedar fechada antes del episodio y el
  -- supervisor aún la vería como reversible. `clock_timestamp` registra el
  -- orden causal ya serializado por el lock.
  new.creado_en := pg_catalog.clock_timestamp();

  return new;
end;
$function$;

comment on function private.trg_gestion_lead_serializada() is
  'Serializa INSERT manual de actividad/tarea contra cambios de dueño del lead, revalida el ámbito tras cualquier espera y sella la hora después del lock. Cierra el TOCTOU entre gestión del asesor y devolución del supervisor.';

revoke all on function private.trg_gestion_lead_serializada()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_01_gestion_lead_serializada on crm.actividades;
create trigger trg_01_gestion_lead_serializada
before insert on crm.actividades
for each row execute function private.trg_gestion_lead_serializada();

drop trigger if exists trg_01_gestion_lead_serializada on crm.tareas;
drop trigger if exists trg_tareas_02_gestion_lead_serializada on crm.tareas;
-- En tareas corre después de los gates 00/01 existentes para conservar sus
-- SQLSTATE/contratos; todavía es BEFORE y mantiene el lock antes del INSERT.
create trigger trg_tareas_02_gestion_lead_serializada
before insert on crm.tareas
for each row execute function private.trg_gestion_lead_serializada();

-- `leads_update` permite a un supervisor editar un lead visible. Sin una
-- guarda adicional podría hacer PATCH vendedor→su bandeja y saltarse toda la
-- validación de `revertir_derivacion_equipo_fn`, incluso después de gestión.
-- Esta válvula solo alcanza episodios de hoy que él mismo derivó; gerencia,
-- offboarding y el resto de transferencias conservan su comportamiento.
create or replace function private.trg_devolucion_equipo_solo_rpc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_inicio_hoy timestamptz := v_hoy::timestamp at time zone 'America/Lima';
  v_fin_hoy timestamptz := (v_hoy + 1)::timestamp at time zone 'America/Lima';
begin
  if v_actor is null
     or new.vendedor_id is not null
     or old.vendedor_id is null
     or new.asignado_supervisor_id is distinct from v_actor
     or private.rol_crm(v_actor) is distinct from 'supervisor'
     or coalesce(
       pg_catalog.current_setting('crm.reversion_derivacion_equipo', true),
       'off'
     ) = 'on' then
    return new;
  end if;

  if exists (
    select 1
    from crm.lead_asignaciones la
    where la.lead_id = old.id
      and la.analista_id = old.vendedor_id
      and la.asignado_por = v_actor
      and la.supervisor_origen_id = v_actor
      and la.asignado_en >= v_inicio_hoy
      and la.asignado_en < v_fin_hoy
      and la.finalizado_en is null
  ) then
    raise exception 'Usa la acción Devolver: la derivación debe validar primero que el asesor no tenga gestión'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

comment on function private.trg_devolucion_equipo_solo_rpc() is
  'Impide que un supervisor eluda revertir_derivacion_equipo_fn con un PATCH directo vendedor→bandeja sobre una derivación propia de hoy.';

revoke all on function private.trg_devolucion_equipo_solo_rpc()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_00_devolucion_equipo_solo_rpc on crm.leads;
create trigger trg_leads_00_devolucion_equipo_solo_rpc
before update of vendedor_id, asignado_supervisor_id on crm.leads
for each row execute function private.trg_devolucion_equipo_solo_rpc();

-- ── Lectura: foto histórica por asesor + derivaciones reversibles de hoy ───

create or replace function crm.reporte_derivaciones_equipo_fn(
  p_desde date default null,
  p_hasta date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_desde date;
  v_hasta date;
  v_inicio_periodo timestamptz;
  v_fin_periodo timestamptz;
  v_inicio_hoy timestamptz;
  v_fin_hoy timestamptz;
  v_payload jsonb;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede consultar las derivaciones de su equipo'
      using errcode = '42501';
  end if;

  if p_desde is null and p_hasta is null then
    v_desde := v_hoy - 1;
    v_hasta := v_hoy - 1;
  elsif p_desde is null or p_hasta is null then
    raise exception 'Indica ambas fechas del reporte'
      using errcode = '22023';
  else
    v_desde := p_desde;
    v_hasta := p_hasta;
  end if;

  if v_desde > v_hasta then
    raise exception 'La fecha inicial no puede ser posterior a la fecha final'
      using errcode = '22023';
  end if;
  if v_hasta > v_hoy then
    raise exception 'El reporte no admite fechas futuras'
      using errcode = '22023';
  end if;
  if v_hasta - v_desde > 365 then
    raise exception 'El rango máximo del reporte es de 366 días'
      using errcode = '22023';
  end if;

  v_inicio_periodo := v_desde::timestamp at time zone 'America/Lima';
  v_fin_periodo := (v_hasta + 1)::timestamp at time zone 'America/Lima';
  v_inicio_hoy := v_hoy::timestamp at time zone 'America/Lima';
  v_fin_hoy := (v_hoy + 1)::timestamp at time zone 'America/Lima';

  with asesores as materialized (
    select
      e.perfil_id as asesor_id,
      p.nombre_completo as asesor_nombre
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm = 'vendedor'
      and e.supervisor_id = v_actor
      and e.activo = true
      and p.activo = true
  ),
  episodios_periodo as materialized (
    select la.*
    from crm.lead_asignaciones la
    join asesores a on a.asesor_id = la.analista_id
    where la.asignado_por = v_actor
      and la.supervisor_origen_id = v_actor
      and la.asignado_en >= v_inicio_periodo
      and la.asignado_en < v_fin_periodo
      and la.motivo_apertura in ('asignado', 'reasignado')
      -- Una devolución previa a la gestión deshace la carga para efectos de
      -- equidad. El episodio permanece en el ledger como auditoría, pero no
      -- debe seguir sumando leads ni capital al asesor que ya no lo conserva.
      and (
        la.motivo_cierre is distinct from 'parqueado'
        or la.supervisor_destino_id is distinct from v_actor
      )
  ),
  agregados_periodo as materialized (
    select
      ep.analista_id as asesor_id,
      pg_catalog.count(*)::integer as derivados,
      coalesce(pg_catalog.sum(ep.monto_estimado) filter (where ep.moneda = 'PEN'), 0)::numeric as capital_pen,
      coalesce(pg_catalog.sum(ep.monto_estimado) filter (where ep.moneda = 'USD'), 0)::numeric as capital_usd,
      pg_catalog.count(*) filter (
        where not exists (
          select 1
          from crm.actividades actividad
          where actividad.lead_id = ep.lead_id
            and actividad.creado_por = ep.analista_id
            and actividad.creado_en >= ep.asignado_en
            and (ep.finalizado_en is null or actividad.creado_en <= ep.finalizado_en)
            and actividad.tipo in (
              'llamada_realizada',
              'llamada_no_contestada',
              'whatsapp_enviado',
              'whatsapp_recibido',
              'reunion_realizada'
            )
        )
      )::integer as sin_primer_contacto
    from episodios_periodo ep
    group by ep.analista_id
  ),
  repartido_hoy as materialized (
    select
      la.analista_id as asesor_id,
      pg_catalog.count(*)::integer as total
    from crm.lead_asignaciones la
    join asesores a on a.asesor_id = la.analista_id
    where la.asignado_por = v_actor
      and la.supervisor_origen_id = v_actor
      and la.asignado_en >= v_inicio_hoy
      and la.asignado_en < v_fin_hoy
      and la.motivo_apertura in ('asignado', 'reasignado')
      and (
        la.motivo_cierre is distinct from 'parqueado'
        or la.supervisor_destino_id is distinct from v_actor
      )
    group by la.analista_id
  ),
  movimientos_hoy as materialized (
    select
      la.lead_id,
      la.analista_id as asesor_id,
      a.asesor_nombre,
      l.nombre_completo,
      la.monto_estimado,
      la.moneda,
      la.asignado_en as derivado_en,
      not exists (
        select 1
        from crm.actividades actividad
        where actividad.lead_id = la.lead_id
          and actividad.creado_por = la.analista_id
          and actividad.creado_en >= la.asignado_en
      )
      and not exists (
        select 1
        from crm.tareas tarea
        where tarea.lead_id = la.lead_id
          and tarea.creado_por = la.analista_id
          and tarea.creado_en >= la.asignado_en
      ) as reversible
    from crm.lead_asignaciones la
    join asesores a on a.asesor_id = la.analista_id
    join crm.leads l on l.id = la.lead_id
    where la.asignado_por = v_actor
      and la.supervisor_origen_id = v_actor
      and la.asignado_en >= v_inicio_hoy
      and la.asignado_en < v_fin_hoy
      and la.motivo_apertura in ('asignado', 'reasignado')
      and la.finalizado_en is null
      and l.vendedor_id = la.analista_id
      and l.activo = true
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
  )
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'generado_en', pg_catalog.statement_timestamp(),
    'periodo', pg_catalog.jsonb_build_object(
      'desde', v_desde,
      'hasta', v_hasta,
      'dias', v_hasta - v_desde + 1,
      'zona', 'America/Lima'
    ),
    'asesores', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'asesor_id', a.asesor_id,
          'asesor_nombre', a.asesor_nombre,
          'derivados', coalesce(ap.derivados, 0),
          'capital_pen', coalesce(ap.capital_pen, 0),
          'capital_usd', coalesce(ap.capital_usd, 0),
          'sin_primer_contacto', coalesce(ap.sin_primer_contacto, 0),
          'contactados', coalesce(ap.derivados, 0) - coalesce(ap.sin_primer_contacto, 0),
          'contactabilidad_pct', case
            when coalesce(ap.derivados, 0) = 0 then 0
            else pg_catalog.round(
              ((coalesce(ap.derivados, 0) - coalesce(ap.sin_primer_contacto, 0))::numeric
                / ap.derivados::numeric) * 100,
              1
            )
          end,
          'repartido_hoy', coalesce(rh.total, 0)
        )
        order by a.asesor_nombre, a.asesor_id
      )
      from asesores a
      left join agregados_periodo ap on ap.asesor_id = a.asesor_id
      left join repartido_hoy rh on rh.asesor_id = a.asesor_id
    ), '[]'::jsonb),
    'movimientos_hoy', coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'lead_id', mh.lead_id,
          'asesor_id', mh.asesor_id,
          'asesor_nombre', mh.asesor_nombre,
          'nombre_completo', mh.nombre_completo,
          'monto_estimado', mh.monto_estimado,
          'moneda', mh.moneda,
          'derivado_en', mh.derivado_en,
          'reversible', mh.reversible
        )
        order by mh.derivado_en desc, mh.lead_id
      )
      from movimientos_hoy mh
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.reporte_derivaciones_equipo_fn(date, date) is
  'Reporte histórico del supervisor sobre las derivaciones hechas desde su bandeja. El capital se lee del snapshot inmutable crm.lead_asignaciones; incluye solo su equipo directo vigente y los leads de hoy que todavía puede devolver antes de que el asesor los gestione.';

revoke all on function crm.reporte_derivaciones_equipo_fn(date, date)
  from public, anon, authenticated, service_role;
grant execute on function crm.reporte_derivaciones_equipo_fn(date, date)
  to authenticated;

-- ── Escritura: derivar un borrador completo de forma atómica ────────────────

create or replace function crm.derivar_leads_equipo_fn(
  p_lead_ids uuid[],
  p_asesor_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_total integer;
  v_distintos integer;
  v_destinos_solicitados integer;
  v_destinos_validos integer := 0;
  v_leads_encontrados integer := 0;
  v_indice integer;
  v_asesor record;
  v_lead record;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede derivar leads de su equipo'
      using errcode = '42501';
  end if;

  -- Los cambios canónicos de jerarquía/offboarding toman esta misma clave en
  -- modo exclusivo antes de bloquear equipo y luego leads. Aquí basta modo
  -- compartido: varias derivaciones pueden convivir, pero ninguna se cruza
  -- con una baja/traslado y se evita el ciclo equipo → lead / lead → equipo.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  if p_lead_ids is null
     or pg_catalog.array_length(p_lead_ids, 1) is null
     or pg_catalog.array_ndims(p_lead_ids) <> 1
     or pg_catalog.array_lower(p_lead_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_lead_ids, 1) < 1
     or pg_catalog.array_length(p_lead_ids, 1) > 100
     or pg_catalog.array_position(p_lead_ids, null) is not null then
    raise exception 'Selecciona entre 1 y 100 leads válidos para derivar'
      using errcode = '22023';
  end if;

  if p_asesor_ids is null
     or pg_catalog.array_ndims(p_asesor_ids) <> 1
     or pg_catalog.array_lower(p_asesor_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_asesor_ids, 1) is distinct from pg_catalog.array_length(p_lead_ids, 1)
     or pg_catalog.array_position(p_asesor_ids, null) is not null then
    raise exception 'Cada lead debe tener exactamente un asesor destino'
      using errcode = '22023';
  end if;

  v_total := pg_catalog.array_length(p_lead_ids, 1);
  select pg_catalog.count(*)::integer
    into v_distintos
  from (
    select distinct lead_id
    from pg_catalog.unnest(p_lead_ids) as entrada(lead_id)
  ) distintos;
  if v_distintos <> v_total then
    raise exception 'Un mismo lead no se puede derivar dos veces en el mismo guardado'
      using errcode = '22023';
  end if;

  select pg_catalog.count(*)::integer
    into v_destinos_solicitados
  from (
    select distinct asesor_id
    from pg_catalog.unnest(p_asesor_ids) as entrada(asesor_id)
  ) destinos;

  -- Bloqueo determinista: dos supervisores no pueden ganar una carrera sobre
  -- el mismo lead ni dejar un borrador parcialmente aplicado.
  for v_lead in
    select
      l.id,
      l.vendedor_id,
      l.asignado_supervisor_id,
      l.activo,
      l.etapa,
      l.no_contactar
    from crm.leads l
    where l.id = any(p_lead_ids)
    order by l.id
    for update
  loop
    v_leads_encontrados := v_leads_encontrados + 1;
    if v_lead.vendedor_id is not null
       or v_lead.asignado_supervisor_id is distinct from v_actor
       or v_lead.activo is not true
       or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
      raise exception 'El lead % ya no está disponible en tu bandeja', v_lead.id
        using errcode = 'P0001';
    end if;
    if v_lead.no_contactar is true then
      raise exception 'El lead % está marcado No Insista y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
  end loop;

  if v_leads_encontrados <> v_total then
    raise exception 'Uno de los leads seleccionados ya no existe'
      using errcode = 'P0001';
  end if;

  -- El precheck evita que un usuario sin rol use la RPC para bloquear filas
  -- ajenas. Esta segunda lectura sí bloquea y vuelve a validar al supervisor:
  -- Gerencia no puede desactivarlo mientras el guardado está en curso.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de derivar'
      using errcode = '42501';
  end if;

  -- Orden global de locks: leads → supervisor → asesores (igual que devolver).
  -- La pertenencia no es una foto optimista: bloqueamos, en orden
  -- determinista, tanto la membresía CRM como el perfil activo. Así Gerencia
  -- no puede mover/desactivar al asesor entre la validación y el UPDATE de los
  -- leads. El trigger de tenencia valida rol/activo, pero no supervisor_id.
  for v_asesor in
    select asesor_equipo.perfil_id
    from crm.equipo asesor_equipo
    join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
    where asesor_equipo.perfil_id = any(p_asesor_ids)
      and asesor_equipo.rol_crm = 'vendedor'
      and asesor_equipo.supervisor_id = v_actor
      and asesor_equipo.activo = true
      and asesor_perfil.activo = true
    order by asesor_equipo.perfil_id
    for no key update of asesor_equipo, asesor_perfil
  loop
    v_destinos_validos := v_destinos_validos + 1;
  end loop;

  if v_destinos_validos <> v_destinos_solicitados then
    raise exception 'Uno de los asesores destino ya no pertenece a tu equipo activo'
      using errcode = '42501';
  end if;

  for v_indice in 1..v_total loop
    update crm.leads
    set vendedor_id = p_asesor_ids[v_indice],
        asignado_supervisor_id = null
    where id = p_lead_ids[v_indice];
  end loop;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'derivados', v_total,
    'lead_ids', pg_catalog.to_jsonb(p_lead_ids)
  );
end;
$function$;

comment on function crm.derivar_leads_equipo_fn(uuid[], uuid[]) is
  'Guarda atómicamente un borrador de derivaciones desde la bandeja propia del supervisor hacia asesores directos activos. Los triggers de crm.leads escriben el historial humano y el ledger; no hay una bitácora paralela.';

revoke all on function crm.derivar_leads_equipo_fn(uuid[], uuid[])
  from public, anon, authenticated, service_role;
grant execute on function crm.derivar_leads_equipo_fn(uuid[], uuid[])
  to authenticated;

-- ── Escritura: devolver una derivación de hoy antes de que sea gestionada ───

create or replace function crm.revertir_derivacion_equipo_fn(
  p_lead_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_inicio_hoy timestamptz := v_hoy::timestamp at time zone 'America/Lima';
  v_fin_hoy timestamptz := (v_hoy + 1)::timestamp at time zone 'America/Lima';
  v_lead crm.leads%rowtype;
  v_episodio crm.lead_asignaciones%rowtype;
  v_asesor_bloqueado uuid;
begin
  if p_lead_id is null then
    raise exception 'Indica el lead que deseas devolver'
      using errcode = '22023';
  end if;

  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede devolver derivaciones de su equipo'
      using errcode = '42501';
  end if;

  -- Interlock compartido con la jerarquía: offboarding usa la misma clave en
  -- exclusivo antes de tocar equipo/leads. Debe ocurrir antes del row lock.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select l.*
    into v_lead
  from crm.leads l
  where l.id = p_lead_id
  for update;
  if not found then
    raise exception 'El lead ya no está disponible'
      using errcode = 'P0001';
  end if;

  -- Revalida bajo lock el rol que pasó el precheck. Esto impide completar la
  -- devolución si Gerencia desactivó al supervisor mientras esperaba el lead.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de devolver'
      using errcode = '42501';
  end if;

  -- Mismo orden que el guardado masivo: lead → supervisor → asesor. La
  -- membresía y los perfiles quedan estables hasta terminar la devolución.
  select asesor_equipo.perfil_id
    into v_asesor_bloqueado
  from crm.equipo asesor_equipo
  join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
  where asesor_equipo.perfil_id = v_lead.vendedor_id
    and asesor_equipo.rol_crm = 'vendedor'
    and asesor_equipo.supervisor_id = v_actor
    and asesor_equipo.activo = true
    and asesor_perfil.activo = true
  for no key update of asesor_equipo, asesor_perfil;

  if not found then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  select la.*
    into v_episodio
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id
    and la.analista_id = v_lead.vendedor_id
    and la.asignado_por = v_actor
    and la.supervisor_origen_id = v_actor
    and la.asignado_en >= v_inicio_hoy
    and la.asignado_en < v_fin_hoy
    and la.finalizado_en is null
  order by la.asignado_en desc
  limit 1
  for update of la;

  if not found
     or v_lead.activo is not true
     or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from crm.actividades actividad
    where actividad.lead_id = p_lead_id
      and actividad.creado_por = v_episodio.analista_id
      and actividad.creado_en >= v_episodio.asignado_en
  ) or exists (
    select 1
    from crm.tareas tarea
    where tarea.lead_id = p_lead_id
      and tarea.creado_por = v_episodio.analista_id
      and tarea.creado_en >= v_episodio.asignado_en
  ) then
    raise exception 'No puedes devolver este lead porque el asesor ya registró gestión; su historial se conserva'
      using errcode = 'P0001';
  end if;

  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'on', true);
  update crm.leads
  set vendedor_id = null,
      asignado_supervisor_id = v_actor
  where id = p_lead_id;
  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'off', true);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'lead_id', p_lead_id,
    'devuelto_a_bandeja', true
  );
end;
$function$;

comment on function crm.revertir_derivacion_equipo_fn(uuid) is
  'Devuelve a la bandeja del supervisor una derivación de hoy que sigue vigente y sin gestión del asesor. El episodio se cierra como parqueado y la actividad de reasignación conserva la auditoría.';

revoke all on function crm.revertir_derivacion_equipo_fn(uuid)
  from public, anon, authenticated, service_role;
grant execute on function crm.revertir_derivacion_equipo_fn(uuid)
  to authenticated;

-- ── Postflight estructural: si una superficie queda más abierta o incompleta,
-- toda la migración revierte antes del COMMIT. El comportamiento con sesiones
-- reales vive en supabase/scripts/test-reporte-derivaciones-equipo.sql.
do $postflight$
declare
  v_reporte regprocedure := pg_catalog.to_regprocedure(
    'crm.reporte_derivaciones_equipo_fn(date,date)'
  );
  v_derivar regprocedure := pg_catalog.to_regprocedure(
    'crm.derivar_leads_equipo_fn(uuid[],uuid[])'
  );
  v_revertir regprocedure := pg_catalog.to_regprocedure(
    'crm.revertir_derivacion_equipo_fn(uuid)'
  );
  v_guard regprocedure := pg_catalog.to_regprocedure(
    'private.trg_gestion_lead_serializada()'
  );
  v_guard_devolucion regprocedure := pg_catalog.to_regprocedure(
    'private.trg_devolucion_equipo_solo_rpc()'
  );
begin
  if v_reporte is null or v_derivar is null or v_revertir is null
     or v_guard is null or v_guard_devolucion is null then
    raise exception 'POSTFLIGHT: faltan una o más RPC/guardas del reporte de derivaciones';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_proc p
    where p.oid in (v_reporte, v_derivar, v_revertir)
      and p.prosecdef
      and p.prorettype = 'jsonb'::pg_catalog.regtype
      and p.proconfig @> array['search_path=""']
  ) <> 3 then
    raise exception 'POSTFLIGHT: las tres RPC deben ser DEFINER, devolver jsonb y fijar search_path vacío';
  end if;

  if (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_reporte) <> 's'
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_derivar) <> 'v'
     or (select p.provolatile from pg_catalog.pg_proc p where p.oid = v_revertir) <> 'v' then
    raise exception 'POSTFLIGHT: volatilidad incorrecta en las RPC de derivaciones';
  end if;

  if not pg_catalog.has_function_privilege('authenticated', v_reporte, 'execute')
     or not pg_catalog.has_function_privilege('authenticated', v_derivar, 'execute')
     or not pg_catalog.has_function_privilege('authenticated', v_revertir, 'execute')
     or pg_catalog.has_function_privilege('anon', v_reporte, 'execute')
     or pg_catalog.has_function_privilege('anon', v_derivar, 'execute')
     or pg_catalog.has_function_privilege('anon', v_revertir, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_reporte, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_derivar, 'execute')
     or pg_catalog.has_function_privilege('service_role', v_revertir, 'execute') then
    raise exception 'POSTFLIGHT: ACL incorrecta en las RPC de derivaciones';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid in (v_reporte, v_derivar, v_revertir)
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'POSTFLIGHT: PUBLIC conserva EXECUTE en una RPC de derivaciones';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    where p.oid = v_guard
      and p.prosecdef
      and p.prorettype = 'trigger'::pg_catalog.regtype
      and p.proconfig @> array['search_path=""']
  )
  or pg_catalog.has_function_privilege('authenticated', v_guard, 'execute')
  or pg_catalog.has_function_privilege('anon', v_guard, 'execute')
  or pg_catalog.has_function_privilege('service_role', v_guard, 'execute')
  or exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid = v_guard
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'POSTFLIGHT: la guarda concurrente perdió hardening o ACL';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    where p.oid = v_guard_devolucion
      and p.prosecdef
      and p.prorettype = 'trigger'::pg_catalog.regtype
      and p.proconfig @> array['search_path=""']
      and pg_catalog.strpos(p.prosrc, 'crm.reversion_derivacion_equipo') > 0
  )
  or pg_catalog.has_function_privilege('authenticated', v_guard_devolucion, 'execute')
  or pg_catalog.has_function_privilege('anon', v_guard_devolucion, 'execute')
  or pg_catalog.has_function_privilege('service_role', v_guard_devolucion, 'execute')
  or exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where p.oid = v_guard_devolucion
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ) then
    raise exception 'POSTFLIGHT: la guarda anti-PATCH perdió hardening, válvula o ACL';
  end if;

  if (
    select pg_catalog.count(*)
    from pg_catalog.pg_trigger t
    where (
      (t.tgname = 'trg_01_gestion_lead_serializada'
       and t.tgrelid = 'crm.actividades'::pg_catalog.regclass)
      or
      (t.tgname = 'trg_tareas_02_gestion_lead_serializada'
       and t.tgrelid = 'crm.tareas'::pg_catalog.regclass)
    )
      and t.tgfoid = v_guard
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) <> 2 then
    raise exception 'POSTFLIGHT: la guarda concurrente no quedó activa en actividades y tareas';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgname = 'trg_leads_00_devolucion_equipo_solo_rpc'
      and t.tgrelid = 'crm.leads'::pg_catalog.regclass
      and t.tgfoid = v_guard_devolucion
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    raise exception 'POSTFLIGHT: la guarda anti-PATCH no quedó activa en crm.leads';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm'
      and c.relname = 'lead_asignaciones_reporte_supervisor_fecha_idx'
      and i.indrelid = 'crm.lead_asignaciones'::pg_catalog.regclass
      and i.indisvalid
      and i.indisready
      and not i.indisunique
      and i.indnkeyatts = 4
      and pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'supervisor_origen_id'
      and pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = 'asignado_por'
      and pg_catalog.pg_get_indexdef(i.indexrelid, 3, true) = 'asignado_en'
      and pg_catalog.pg_get_indexdef(i.indexrelid, 4, true) = 'analista_id'
      and pg_catalog.pg_get_indexdef(i.indexrelid)
          like '%(supervisor_origen_id, asignado_por, asignado_en DESC, analista_id)%'
      and pg_catalog.pg_get_expr(i.indpred, i.indrelid)
          = '(motivo_apertura = ANY (ARRAY[''asignado''::text, ''reasignado''::text]))'
  ) then
    raise exception 'POSTFLIGHT: el índice parcial del reporte falta o no coincide con su contrato';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index i
    join pg_catalog.pg_class c on c.oid = i.indexrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm'
      and c.relname = 'tareas_reversion_gestion_idx'
      and i.indrelid = 'crm.tareas'::pg_catalog.regclass
      and i.indisvalid
      and i.indisready
      and not i.indisunique
      and i.indnkeyatts = 3
      and pg_catalog.pg_get_indexdef(i.indexrelid, 1, true) = 'lead_id'
      and pg_catalog.pg_get_indexdef(i.indexrelid, 2, true) = 'creado_por'
      and pg_catalog.pg_get_indexdef(i.indexrelid, 3, true) = 'creado_en'
      and pg_catalog.pg_get_expr(i.indpred, i.indrelid) = '(lead_id IS NOT NULL)'
  ) then
    raise exception 'POSTFLIGHT: el índice de gestión para devolución falta o no coincide';
  end if;

  raise notice 'POSTFLIGHT OK: 3 RPC + 3 triggers de guarda + ACL cerradas + 2 índices válidos';
end;
$postflight$;

commit;
