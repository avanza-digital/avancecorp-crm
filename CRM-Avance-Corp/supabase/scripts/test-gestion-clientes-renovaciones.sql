-- Gate transaccional: gestión postventa, renovaciones/upgrades y conversión.
-- Requiere 20260824231133 + 20260824233619. Crea y cierra una tarea real de
-- cliente, pero TODO se revierte al terminar.

begin;

set local lock_timeout = '10s';

do $estructura$
declare
  v_def text;
begin
  if to_regclass('crm.operaciones_cartera') is null
     or to_regclass('crm.actividades_cliente') is null then
    raise exception 'GCAR-01: faltan los ledger de operaciones o actividades';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'operaciones_cartera'
      and c.relrowsecurity
  ) or not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'actividades_cliente'
      and c.relrowsecurity
  ) then
    raise exception 'GCAR-02: RLS no está activa en ambos ledger';
  end if;

  if pg_catalog.has_table_privilege('anon', 'crm.operaciones_cartera', 'SELECT')
     or pg_catalog.has_table_privilege('anon', 'crm.actividades_cliente', 'SELECT')
     or pg_catalog.has_table_privilege('authenticated', 'crm.operaciones_cartera', 'INSERT,UPDATE,DELETE')
     or pg_catalog.has_table_privilege('authenticated', 'crm.actividades_cliente', 'INSERT,UPDATE,DELETE')
     or not pg_catalog.has_table_privilege('authenticated', 'crm.operaciones_cartera', 'SELECT')
     or not pg_catalog.has_table_privilege('authenticated', 'crm.actividades_cliente', 'SELECT') then
    raise exception 'GCAR-03: privilegios directos inesperados en los ledger';
  end if;

  if to_regprocedure('crm.metricas_cartera_fn(date)') is null
     or to_regprocedure('private.metricas_cartera_por_vendedor(date)') is null
     or to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb)') is null then
    raise exception 'GCAR-04: faltan funciones de métricas o cierre postventa';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.metricas_cartera_fn(date)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.metricas_cartera_fn(date)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE'
     ) then
    raise exception 'GCAR-05: permisos de las RPC no son los esperados';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.tareas'::regclass
      and c.conname = 'tareas_un_solo_sujeto'
      and pg_catalog.pg_get_constraintdef(c.oid)
          ilike '%num_nonnulls(lead_id, perfil_id) = 1%'
  ) then
    raise exception 'GCAR-06: una tarea no exige exactamente un sujeto';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.metricas_cartera_por_vendedor(date)'::regprocedure
  );
  if v_def not ilike '%partition by o.cliente_id, o.periodo%'
     or v_def not ilike '%orden_conversion = 1%'
     or v_def not ilike '%capital_adicional_pen%'
     or v_def not ilike '%capital_adicional_usd%' then
    raise exception 'GCAR-07: la deduplicación o el desglose económico cambió';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'::regprocedure
  );
  if v_def not ilike '%from crm.lead_asignaciones la%'
     or v_def not ilike '%coalesce(o.conversiones_clientes, 0)%'
     or v_def not ilike '%coalesce(d.divisor, 0)%'
     or v_def ilike '%count(*) filter (where%operaciones_cartera%as divisor%' then
    raise exception 'GCAR-08: operaciones no están separadas del divisor';
  end if;

  -- El bundle desplegado valida cumplimiento con strictObject. La migración de
  -- compatibilidad suma al campo existente `convertidos`, sin publicar todavía
  -- una rama extra `cartera` en esta RPC.
  v_def := pg_catalog.pg_get_functiondef(
    'crm.cumplimiento_metas_fn(date)'::regprocedure
  );
  if v_def not ilike '%''{convertidos}''%'
     or v_def ilike '%jsonb_build_object(''cartera''%' then
    raise exception 'GCAR-09: cumplimiento dejó de ser compatible con el bundle';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.cerrar_tarea(uuid,text,text,text,jsonb)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%v_tarea.perfil_id%' then
    raise exception 'GCAR-10: cerrar_tarea no conserva el historial postventa';
  end if;
end;
$estructura$;

do $invariantes$
declare
  v_periodo constant date := date '2026-08-01';
  v_conversiones_esperadas integer;
  v_conversiones_metricas integer;
  v_divisor_esperado integer;
  v_divisor_funcion integer;
  v_adicional_pen numeric;
  v_adicional_usd numeric;
  v_metricas_adicional_pen numeric;
  v_metricas_adicional_usd numeric;
  v_op_id uuid;
begin
  if exists (
    select 1
    from crm.operaciones_cartera o
    join public.contratos nuevo on nuevo.id = o.contrato_nuevo_id
    where nuevo.cliente_id is distinct from o.cliente_id
       or nuevo.moneda is distinct from o.moneda
       or nuevo.categoria is distinct from o.tipo
  ) then
    raise exception 'GCAR-11: una operación no coincide con su contrato nuevo';
  end if;

  if exists (
    select 1
    from crm.operaciones_cartera o
    join public.contratos nuevo on nuevo.id = o.contrato_nuevo_id
    left join public.contratos origen on origen.id = o.contrato_origen_id
    where o.tipo = 'renovacion' and (
      not o.elegible_conversion
      or (
        o.desglose_completo and (
          origen.id is null
          or origen.cliente_id is distinct from o.cliente_id
          or origen.estado is distinct from 'renovado'
          or origen.renovado_a_id is distinct from nuevo.id
          or nuevo.capital is distinct from o.capital_renovado + o.capital_adicional
        )
      )
      or (
        not o.desglose_completo and (
          o.fuente is distinct from 'backfill_agosto_2026'
          or o.contrato_origen_id is not null
          or o.capital_renovado is not null
          or o.capital_adicional is not null
        )
      )
    )
  ) then
    raise exception 'GCAR-12: una renovación no respeta cierre, enlace o desglose';
  end if;

  if exists (
    with primero as (
      select c.cliente_id,
             min(date_trunc('month', c.fecha_cierre_comercial)::date) as periodo
      from public.contratos c
      group by c.cliente_id
    )
    select 1
    from crm.operaciones_cartera o
    join primero p using (cliente_id)
    where o.tipo = 'upgrade'
      and o.elegible_conversion is distinct from (o.periodo > p.periodo)
  ) then
    raise exception 'GCAR-13: elegibilidad de upgrade no sigue el primer mes';
  end if;

  select count(*) into v_conversiones_esperadas
  from (
    select o.cliente_id
    from crm.operaciones_cartera o
    where o.periodo = v_periodo and o.elegible_conversion
    group by o.cliente_id
  ) x;

  select coalesce(sum(m.conversiones_clientes), 0)::integer
    into v_conversiones_metricas
  from private.metricas_cartera_por_vendedor(v_periodo) m;

  if v_conversiones_metricas is distinct from v_conversiones_esperadas then
    raise exception 'GCAR-14: % conversiones métricas vs % clientes elegibles',
      v_conversiones_metricas, v_conversiones_esperadas;
  end if;

  select
    coalesce(sum(o.capital_adicional) filter (where o.moneda = 'PEN'), 0),
    coalesce(sum(o.capital_adicional) filter (where o.moneda = 'USD'), 0)
    into v_adicional_pen, v_adicional_usd
  from crm.operaciones_cartera o
  where o.periodo = v_periodo and o.tipo = 'renovacion';

  select
    coalesce(sum(m.capital_adicional_pen), 0),
    coalesce(sum(m.capital_adicional_usd), 0)
    into v_metricas_adicional_pen, v_metricas_adicional_usd
  from private.metricas_cartera_por_vendedor(v_periodo) m;

  if v_metricas_adicional_pen is distinct from v_adicional_pen
     or v_metricas_adicional_usd is distinct from v_adicional_usd then
    raise exception 'GCAR-15: capital adicional no cuadra por moneda';
  end if;

  with recibidos as (
    select la.analista_id, la.lead_id,
           (array_agg(la.origen order by la.asignado_en))[1] = 'referido' as referido
    from crm.lead_asignaciones la
    where la.asignado_en >= timestamptz '2026-08-01 00:00:00-05'
      and la.asignado_en < timestamptz '2026-09-01 00:00:00-05'
    group by la.analista_id, la.lead_id
  )
  select count(*) filter (where not r.referido)::integer
    into v_divisor_esperado
  from recibidos r;

  select coalesce(sum(x.divisor), 0)::integer
    into v_divisor_funcion
  from private.conversion_mensual_por_vendedor(
    timestamptz '2026-08-01 00:00:00-05',
    timestamptz '2026-09-01 00:00:00-05',
    true, '{}'::uuid[], 0.15
  ) x;

  if v_divisor_funcion is distinct from v_divisor_esperado then
    raise exception 'GCAR-16: el divisor cambió con operaciones (% vs %)',
      v_divisor_funcion, v_divisor_esperado;
  end if;

  select o.id into v_op_id
  from crm.operaciones_cartera o order by o.creado_en, o.id limit 1;
  if v_op_id is null then
    raise exception 'GCAR-17: el gate necesita al menos una operación';
  end if;
  begin
    update crm.operaciones_cartera set creado_en = creado_en where id = v_op_id;
    raise exception 'GCAR-18: el ledger permitió UPDATE';
  exception when sqlstate 'P0409' then
    null;
  end;
end;
$invariantes$;

do $postventa$
declare
  v_actor uuid;
  v_cliente uuid;
  v_asesor uuid;
  v_actividades_lead_antes integer;
  v_respuesta jsonb;
  v_tarea constant uuid := '7f200000-0000-4000-8000-000000000001';
  v_siguiente constant uuid := '7f200000-0000-4000-8000-000000000002';
begin
  select e.perfil_id into v_actor
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'gerencia' and e.activo and p.activo
  order by e.perfil_id limit 1;

  select p.id, p.asesor_perfil_id into v_cliente, v_asesor
  from public.perfiles p
  join crm.equipo e on e.perfil_id = p.asesor_perfil_id
  where p.rol = 'cliente' and p.activo
    and e.activo and e.rol_crm in ('vendedor', 'supervisor')
  order by p.id limit 1;

  if v_actor is null or v_cliente is null or v_asesor is null then
    raise exception 'GCAR-19: el gate necesita Gerencia y un cliente con asesor';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_actor::text, true);
  select count(*) into v_actividades_lead_antes from crm.actividades;

  insert into crm.tareas (
    id, perfil_id, tipo, titulo, nota, vence_en, estado, activo, creado_por
  ) values (
    v_tarea, v_cliente, 'llamada', 'TEST postventa de cliente', null,
    timestamptz '2090-01-10 10:00:00-05', 'pendiente', true, v_actor
  );

  if not exists (
    select 1 from crm.tareas t
    where t.id = v_tarea and t.lead_id is null
      and t.perfil_id = v_cliente and t.vendedor_id = v_asesor
  ) then
    raise exception 'GCAR-20: el trigger no atribuyó la tarea al dueño de cartera';
  end if;

  v_respuesta := crm.cerrar_tarea(
    v_tarea,
    'completada',
    'llamada_realizada',
    'Resultado postventa transaccional',
    jsonb_build_object(
      'id', v_siguiente,
      'tipo', 'whatsapp',
      'titulo', 'TEST siguiente postventa',
      'vence_en', '2090-01-11T15:00:00.000Z'
    )
  );

  if coalesce((v_respuesta->>'ok')::boolean, false) is not true
     or (v_respuesta->>'actividad_cliente_id')::uuid is null
     or (v_respuesta->>'siguiente_id')::uuid is distinct from v_siguiente then
    raise exception 'GCAR-21: cerrar_tarea devolvió una respuesta incompleta: %', v_respuesta;
  end if;

  if not exists (
    select 1 from crm.actividades_cliente a
    where a.tarea_id = v_tarea and a.cliente_id = v_cliente
      and a.vendedor_id = v_asesor and a.tipo = 'llamada_realizada'
      and a.detalle = 'Resultado postventa transaccional'
  ) then
    raise exception 'GCAR-22: el cierre no escribió el historial del cliente';
  end if;

  if not exists (
    select 1 from crm.tareas t
    where t.id = v_siguiente and t.estado = 'pendiente'
      and t.lead_id is null and t.perfil_id = v_cliente
      and t.vendedor_id = v_asesor
  ) then
    raise exception 'GCAR-23: la siguiente gestión perdió cliente o asesor';
  end if;

  if (select count(*) from crm.actividades) is distinct from v_actividades_lead_antes then
    raise exception 'GCAR-24: la postventa contaminó actividades de leads';
  end if;
end;
$postventa$;

select 'GESTION_CLIENTES_RENOVACIONES_OK' as resultado;

rollback;
