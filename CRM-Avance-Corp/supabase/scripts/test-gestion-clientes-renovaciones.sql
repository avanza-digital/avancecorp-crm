-- Gate transaccional: gestión postventa, renovaciones/upgrades y conversión.
-- Requiere 20260824231133 + 20260824233619 + 20260825005519. Crea y cierra
-- tareas reales de cliente, pero TODO se revierte al terminar.

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
     or to_regprocedure('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)') is null then
    raise exception 'GCAR-04: faltan funciones de métricas o cierre postventa';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.metricas_cartera_fn(date)', 'EXECUTE'
     ) or pg_catalog.has_function_privilege(
       'anon', 'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.metricas_cartera_fn(date)', 'EXECUTE'
     ) or not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)', 'EXECUTE'
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
  -- C0.1 reemplaza este helper atómicamente: la llamada a episodios es la
  -- señal de corte. Un cuerpo híbrido entra a la rama C0.1 y debe fallar.
  if v_def ilike '%private.conversion_episodios(%' then
    if v_def not ilike '%where e.tipo = ''operacion''%'
       or v_def ilike '%row_number()%'
       or v_def ilike '%orden_conversion%'
       or v_def ilike '%elegible_conversion%'
       or v_def not ilike '%capital_adicional_pen%'
       or v_def not ilike '%capital_adicional_usd%' then
      raise exception 'GCAR-07: cartera C0.1 no deriva limpiamente de episodios operación';
    end if;
  else
    if v_def not ilike '%partition by o.cliente_id, o.periodo%'
       or v_def not ilike '%orden_conversion = 1%'
       or v_def not ilike '%capital_adicional_pen%'
       or v_def not ilike '%capital_adicional_usd%' then
      raise exception 'GCAR-07: la deduplicación o el desglose económico legacy cambió';
    end if;
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'::regprocedure
  );
  if v_def ilike '%private.conversion_episodios(%' then
    if v_def not ilike '%from ep e where e.tipo = ''recibido''%'
       or v_def not ilike '%from ep e where e.tipo = ''operacion''%'
       or v_def not ilike '%coalesce(o.conversiones_clientes, 0)%'
       or v_def not ilike '%coalesce(d.divisor, 0)%'
       or v_def not ilike '%/ d.divisor%'
       or v_def ilike '%conversiones_clientes%as divisor%' then
      raise exception 'GCAR-08: episodios operación entraron al divisor del núcleo F1';
    end if;
  elsif v_def not ilike '%from crm.lead_asignaciones la%'
        or v_def not ilike '%coalesce(o.conversiones_clientes, 0)%'
        or v_def not ilike '%coalesce(d.divisor, 0)%'
        or v_def ilike '%count(*) filter (where%operaciones_cartera%as divisor%' then
    raise exception 'GCAR-08: operaciones no están separadas del divisor legacy';
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
    'crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)'::regprocedure
  );
  if v_def not ilike '%insert into crm.actividades_cliente%'
     or v_def not ilike '%v_tarea.perfil_id%'
     or v_def not ilike '%then p_resultado_reunion else null end%'
     or v_def not ilike '%then p_motivo_no_realizada else null end%' then
    raise exception 'GCAR-10: cerrar_tarea no conserva historial o clasificación postventa';
  end if;
end;
$estructura$;

-- Fixture hermético: la antigua versión esperaba que el backfill productivo
-- hubiera dejado al menos una operación. Eso hacía que una base limpia fallara
-- antes de probar el ledger. Este upgrade vive en la transacción del gate y se
-- revierte al final junto con todo lo demás.
do $fixture_upgrade$
declare
  v_periodo constant date := date '2026-08-01';
  v_contrato_id constant uuid := '7f300000-0000-4000-8000-000000000001';
  v_cronograma_id constant uuid := '7f500000-0000-4000-8000-000000000001';
  v_operacion_id constant uuid := '7f400000-0000-4000-8000-000000000001';
  v_plantilla record;
  v_actor uuid;
  v_filas integer;
begin
  select c.*, p.asesor_perfil_id
    into v_plantilla
  from public.contratos c
  join public.perfiles p on p.id = c.cliente_id
  join crm.equipo a on a.perfil_id = p.asesor_perfil_id
  where c.estado = 'activo'
    and p.rol = 'cliente'
    and p.activo
    and p.asesor_perfil_id is not null
    and a.activo
    and a.rol_crm in ('vendedor', 'supervisor')
    and date_trunc('month', c.fecha_cierre_comercial)::date < v_periodo
    and not exists (
      select 1
      from crm.operaciones_cartera o
      where o.cliente_id = c.cliente_id
        and o.periodo = v_periodo
        and o.elegible_conversion
    )
  order by c.numero_contrato, c.id
  limit 1;

  if not found then
    raise exception
      'GCAR-F01: falta contrato activo anterior sin conversión elegible en agosto';
  end if;

  select e.perfil_id into v_actor
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'gerencia' and e.activo and p.activo
  order by e.perfil_id
  limit 1;
  if not found then
    raise exception 'GCAR-F01B: falta Gerencia activa para el fixture';
  end if;

  -- La RPC vigente puede usar el puente legacy mientras siga abierto. Vaciar
  -- la selección fuerza el mismo snapshot exacto que recibe un alta sin
  -- producto explícito y evita heredar estado de sesión de otro gate.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);

  insert into public.contratos (
    id,
    numero_contrato,
    cliente_id,
    capital,
    moneda,
    tasa_anual,
    modalidad,
    tipo_interes,
    fecha_inicio,
    fecha_vencimiento,
    estado,
    notas_internas,
    creado_por,
    categoria
  ) values (
    v_contrato_id,
    '2090-08-990099',
    v_plantilla.cliente_id,
    v_plantilla.capital,
    v_plantilla.moneda,
    v_plantilla.tasa_anual,
    v_plantilla.modalidad,
    v_plantilla.tipo_interes,
    date '2026-08-15',
    date '2027-08-15',
    'activo',
    'Fixture transaccional de upgrade para el gate GCAR',
    v_actor,
    'upgrade'
  );
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'GCAR-F02: se insertaron % contratos de fixture', v_filas;
  end if;

  -- `crear_contrato` rechaza cronogramas vacíos. Esta cuota deja al fixture
  -- con la misma forma mínima alcanzable por la RPC, no solo por SQL directo.
  insert into public.cronograma_pagos (
    id, contrato_id, numero_cuota, fecha_programada,
    monto_programado, estado, tipo
  ) values (
    v_cronograma_id, v_contrato_id, 1, date '2026-09-15',
    v_plantilla.capital, 'pendiente', 'cuota'
  );
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'GCAR-F03: se insertaron % cuotas de fixture', v_filas;
  end if;

  insert into crm.operaciones_cartera (
    id,
    cliente_id,
    vendedor_id,
    tipo,
    contrato_origen_id,
    contrato_nuevo_id,
    fecha_operacion,
    periodo,
    moneda,
    capital_renovado,
    capital_adicional,
    elegible_conversion,
    desglose_completo,
    fuente,
    creado_por
  ) values (
    v_operacion_id,
    v_plantilla.cliente_id,
    v_plantilla.asesor_perfil_id,
    'upgrade',
    null,
    v_contrato_id,
    date '2026-08-15',
    v_periodo,
    v_plantilla.moneda,
    null,
    null,
    true,
    true,
    'flujo_cartera',
    v_actor
  );
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'GCAR-F04: se insertaron % operaciones de fixture', v_filas;
  end if;

  if not exists (
    select 1
    from public.contratos c
    join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
    where c.id = v_contrato_id
      and c.cliente_id = v_plantilla.cliente_id
      and c.categoria = 'upgrade'
      and c.creado_por = v_actor
      and c.fecha_cierre_comercial = date '2026-08-15'
      and pc.es_legacy
      and pc.legacy_contrato_id = c.id
  ) then
    raise exception 'GCAR-F05: contrato o snapshot de producto de fixture inesperado';
  end if;

  if (select count(*) from public.cronograma_pagos cp
      where cp.id = v_cronograma_id
        and cp.contrato_id = v_contrato_id
        and cp.numero_cuota = 1
        and cp.fecha_programada = date '2026-09-15'
        and cp.monto_programado = v_plantilla.capital
        and cp.estado = 'pendiente'
        and cp.tipo = 'cuota') <> 1 then
    raise exception 'GCAR-F06: cronograma mínimo de fixture inesperado';
  end if;

  if (select count(*) from crm.operaciones_cartera o
      where o.id = v_operacion_id
        and o.cliente_id = v_plantilla.cliente_id
        and o.vendedor_id = v_plantilla.asesor_perfil_id
        and o.tipo = 'upgrade'
        and o.contrato_nuevo_id = v_contrato_id
        and o.periodo = v_periodo
        and o.creado_por = v_actor
        and o.elegible_conversion
        and o.desglose_completo) <> 1 then
    raise exception 'GCAR-F07: operación de fixture inesperada';
  end if;
end;
$fixture_upgrade$;

set constraints trg_contratos_operacion_cartera_commit immediate;

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
  v_conversiones_upgrade_esperadas integer;
  v_conversiones_upgrade_metricas integer;
  v_operaciones_upgrade_esperadas integer;
  v_operaciones_upgrade_metricas integer;
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

  select count(*) filter (where x.tipo = 'upgrade')::integer
    into v_conversiones_upgrade_esperadas
  from (
    select distinct on (o.cliente_id) o.tipo
    from crm.operaciones_cartera o
    where o.periodo = v_periodo and o.elegible_conversion
    order by o.cliente_id, o.fecha_operacion, o.creado_en, o.id
  ) x;

  select count(*)::integer
    into v_operaciones_upgrade_esperadas
  from crm.operaciones_cartera o
  where o.periodo = v_periodo and o.tipo = 'upgrade';

  select
    coalesce(sum(m.conversiones_upgrade), 0)::integer,
    coalesce(sum(m.operaciones_upgrade), 0)::integer
    into v_conversiones_upgrade_metricas, v_operaciones_upgrade_metricas
  from private.metricas_cartera_por_vendedor(v_periodo) m;

  if v_conversiones_upgrade_metricas
       is distinct from v_conversiones_upgrade_esperadas
     or v_operaciones_upgrade_metricas
       is distinct from v_operaciones_upgrade_esperadas then
    raise exception
      'GCAR-14B: buckets upgrade inesperados: conversiones %/% operaciones %/%',
      v_conversiones_upgrade_metricas, v_conversiones_upgrade_esperadas,
      v_operaciones_upgrade_metricas, v_operaciones_upgrade_esperadas;
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
  v_asesor_nuevo constant uuid := '7f100000-0000-4000-8000-000000000003';
  v_actividades_lead_antes integer;
  v_tareas_pendientes_antes integer;
  v_respuesta jsonb;
  v_tarea constant uuid := '7f200000-0000-4000-8000-000000000001';
  v_siguiente constant uuid := '7f200000-0000-4000-8000-000000000002';
  v_reunion constant uuid := '7f200000-0000-4000-8000-000000000003';
  v_cancelada constant uuid := '7f200000-0000-4000-8000-000000000004';
  v_atomica constant uuid := '7f200000-0000-4000-8000-000000000005';
  v_fallo_esperado boolean := false;
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
    raise exception 'GCAR-19: el gate necesita Gerencia y un cliente con analista';
  end if;

  -- Segundo responsable autocontenido para demostrar la reasignación real de
  -- cartera. El usuario, perfil y membresía viven solo dentro de este BEGIN y
  -- desaparecen con el ROLLBACK final del gate.
  insert into auth.users (
    id, aud, role, email, email_confirmed_at, raw_app_meta_data,
    raw_user_meta_data, created_at, updated_at
  ) values (
    v_asesor_nuevo, 'authenticated', 'authenticated',
    'gcar-supervisor-destino@test.invalid', now(), '{}', '{}', now(), now()
  );

  insert into public.perfiles (
    id, nombre_completo, correo, rol, activo, creado_por
  ) values (
    v_asesor_nuevo, 'GCAR SUPERVISOR DESTINO',
    'gcar-supervisor-destino@test.invalid', 'comercial', true, v_actor
  );

  insert into crm.equipo (
    perfil_id, rol_crm, supervisor_id, activo, creado_por
  ) values (
    v_asesor_nuevo, 'supervisor', null, true, v_actor
  );

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
    raise exception 'GCAR-23: la siguiente gestión perdió cliente o analista';
  end if;

  -- Reunión completada: clasificación exacta + timeline de cliente se
  -- confirman en la misma llamada, sin tocar crm.actividades de leads.
  insert into crm.tareas (
    id, perfil_id, tipo, titulo, vence_en, modalidad_reunion, ubicacion_reunion,
    estado, activo, creado_por
  ) values (
    v_reunion, v_cliente, 'reunion', 'TEST reunión clasificada',
    timestamptz '2090-01-12 10:00:00-05', 'presencial', 'Oficina Avance',
    'pendiente', true, v_actor
  );

  v_respuesta := crm.cerrar_tarea(
    v_reunion,
    'completada',
    'reunion_realizada',
    'Solicitó propuesta de upgrade',
    null,
    'interesado',
    null
  );

  if (v_respuesta->>'actividad_cliente_id')::uuid is null
     or not exists (
       select 1 from crm.actividades_cliente a
       where a.tarea_id = v_reunion and a.cliente_id = v_cliente
         and a.tipo = 'reunion_realizada'
         and a.detalle = 'Solicitó propuesta de upgrade'
     )
     or not exists (
       select 1 from crm.tareas t
       where t.id = v_reunion and t.estado = 'completada'
         and t.resultado_reunion = 'interesado'
         and t.motivo_no_realizada is null
         and t.detalle_cierre_reunion = 'Solicitó propuesta de upgrade'
     ) then
    raise exception 'GCAR-25: la reunión de cliente perdió clasificación o historial';
  end if;

  -- Cancelación: no inventa actividad, pero conserva motivo y explicación.
  insert into crm.tareas (
    id, perfil_id, tipo, titulo, vence_en, modalidad_reunion, ubicacion_reunion,
    estado, activo, creado_por
  ) values (
    v_cancelada, v_cliente, 'reunion', 'TEST reunión cancelada',
    timestamptz '2090-01-13 10:00:00-05', 'presencial', 'Oficina Avance',
    'pendiente', true, v_actor
  );

  v_respuesta := crm.cerrar_tarea(
    v_cancelada,
    'cancelada',
    null,
    'El cliente pidió cancelar',
    null,
    null,
    'cancelada_cliente'
  );

  if exists (
       select 1 from crm.actividades_cliente a where a.tarea_id = v_cancelada
     ) or not exists (
       select 1 from crm.tareas t
       where t.id = v_cancelada and t.estado = 'cancelada'
         and t.resultado_reunion is null
         and t.motivo_no_realizada = 'cancelada_cliente'
         and t.detalle_cierre_reunion = 'El cliente pidió cancelar'
     ) then
    raise exception 'GCAR-26: la cancelación perdió motivo o inventó actividad';
  end if;

  -- Atomicidad real: el helper de siguiente acción falla DESPUÉS del INSERT
  -- del timeline y del UPDATE de la tarea. La excepción debe revertir ambos.
  insert into crm.tareas (
    id, perfil_id, tipo, titulo, vence_en, modalidad_reunion, ubicacion_reunion,
    estado, activo, creado_por
  ) values (
    v_atomica, v_cliente, 'reunion', 'TEST rollback atómico',
    timestamptz '2090-01-14 10:00:00-05', 'presencial', 'Oficina Avance',
    'pendiente', true, v_actor
  );

  begin
    perform crm.cerrar_tarea(
      v_atomica,
      'completada',
      'reunion_realizada',
      'Este detalle no debe persistir',
      jsonb_build_object(
        'tipo', 'tipo_invalido',
        'titulo', 'Siguiente inválida',
        'vence_en', '2090-01-15T15:00:00.000Z'
      ),
      'seguimiento',
      null
    );
  exception when others then
    v_fallo_esperado := true;
  end;

  if not v_fallo_esperado
     or exists (
       select 1 from crm.actividades_cliente a where a.tarea_id = v_atomica
     ) or not exists (
       select 1 from crm.tareas t
       where t.id = v_atomica and t.estado = 'pendiente'
         and t.resultado_reunion is null
         and t.motivo_no_realizada is null
         and t.detalle_cierre_reunion is null
     ) then
    raise exception 'GCAR-27: cerrar_tarea dejó una escritura parcial';
  end if;

  if (select count(*) from crm.actividades) is distinct from v_actividades_lead_antes then
    raise exception 'GCAR-24: la postventa contaminó actividades de leads';
  end if;

  -- Reasignar el cliente debe mover TODA su agenda pendiente, sin borrar
  -- tareas ni reescribir quién atendió las gestiones históricas ya cerradas.
  select count(*) into v_tareas_pendientes_antes
  from crm.tareas t
  where t.perfil_id = v_cliente and t.activo and t.estado = 'pendiente';

  update public.perfiles
     set asesor_perfil_id = v_asesor_nuevo
   where id = v_cliente;

  if (select asesor_perfil_id from public.perfiles where id = v_cliente)
       is distinct from v_asesor_nuevo
     or (select count(*) from crm.tareas t
         where t.perfil_id = v_cliente and t.activo and t.estado = 'pendiente')
       is distinct from v_tareas_pendientes_antes
     or exists (
       select 1 from crm.tareas t
       where t.perfil_id = v_cliente and t.activo and t.estado = 'pendiente'
         and (
           t.vendedor_id is distinct from v_asesor_nuevo
           or t.asignado_supervisor_id is not null
         )
     )
     or not exists (
       select 1 from crm.tareas t
       where t.id = v_siguiente and t.perfil_id = v_cliente
         and t.estado = 'pendiente' and t.vendedor_id = v_asesor_nuevo
     )
     or not exists (
       select 1 from crm.tareas t
       where t.id = v_atomica and t.perfil_id = v_cliente
         and t.estado = 'pendiente' and t.vendedor_id = v_asesor_nuevo
     ) then
    raise exception 'GCAR-28: la reasignación perdió o dejó atrás tareas pendientes';
  end if;

  if not exists (
       select 1 from crm.tareas t
       where t.id = v_tarea and t.estado = 'completada'
         and t.vendedor_id = v_asesor
     ) or not exists (
       select 1 from crm.actividades_cliente a
       where a.tarea_id = v_tarea and a.cliente_id = v_cliente
         and a.vendedor_id = v_asesor
     ) then
    raise exception 'GCAR-29: la reasignación reescribió la atribución histórica';
  end if;
end;
$postventa$;

select 'GESTION_CLIENTES_RENOVACIONES_OK' as resultado;

rollback;
