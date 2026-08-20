-- Oráculo transaccional del reporte y reparto de Supervisión.
-- Requiere el fixture de `npm run seed:demo` en una branch Supabase.
-- No deja datos: toda la prueba termina en ROLLBACK.

\set ON_ERROR_STOP on

begin;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

do $estructura$
declare
  v_reporte regprocedure := to_regprocedure('crm.reporte_derivaciones_equipo_fn(date,date)');
  v_derivar regprocedure := to_regprocedure('crm.derivar_leads_equipo_fn(uuid[],uuid[])');
  v_revertir regprocedure := to_regprocedure('crm.revertir_derivacion_equipo_fn(uuid)');
begin
  if v_reporte is null or v_derivar is null or v_revertir is null then
    raise exception 'D01 faltan una o más RPC del reporte de derivaciones';
  end if;

  if (select count(*) from pg_proc p where p.oid in (v_reporte, v_derivar, v_revertir)
        and p.prosecdef and p.proconfig @> array['search_path=""']) <> 3 then
    raise exception 'D02 las tres RPC deben ser SECURITY DEFINER con search_path vacío';
  end if;

  if not has_function_privilege('authenticated', v_reporte, 'execute')
     or not has_function_privilege('authenticated', v_derivar, 'execute')
     or not has_function_privilege('authenticated', v_revertir, 'execute')
     or has_function_privilege('anon', v_reporte, 'execute')
     or has_function_privilege('anon', v_derivar, 'execute')
     or has_function_privilege('anon', v_revertir, 'execute')
     or has_function_privilege('service_role', v_reporte, 'execute')
     or has_function_privilege('service_role', v_derivar, 'execute')
     or has_function_privilege('service_role', v_revertir, 'execute') then
    raise exception 'D03 ACL incorrecta en las RPC de derivaciones';
  end if;

  if to_regclass('crm.lead_asignaciones_reporte_supervisor_fecha_idx') is null then
    raise exception 'D04 falta el índice del reporte de derivaciones';
  end if;
end;
$estructura$;

select set_config(
  'test.derivaciones.supervisor',
  (select p.id::text from public.perfiles p where p.nombre_completo = 'SUPERVISOR UNO'),
  true
);
select set_config(
  'test.derivaciones.asesor',
  (select p.id::text from public.perfiles p where p.nombre_completo = 'VENDEDOR DOS'),
  true
);
select set_config(
  'test.derivaciones.asesor_ajeno',
  (select p.id::text from public.perfiles p where p.nombre_completo = 'VENDEDOR TRES'),
  true
);
select set_config(
  'test.derivaciones.lead',
  (select l.id::text from crm.leads l where l.nombre_completo = 'LUIS GARCIA DEMO'),
  true
);
select set_config(
  'test.derivaciones.lead_ocupado',
  (select l.id::text from crm.leads l where l.nombre_completo = 'JUAN PEREZ DEMO'),
  true
);

do $fixture$
begin
  if nullif(current_setting('test.derivaciones.supervisor', true), '') is null
     or nullif(current_setting('test.derivaciones.asesor', true), '') is null
     or nullif(current_setting('test.derivaciones.asesor_ajeno', true), '') is null
     or nullif(current_setting('test.derivaciones.lead', true), '') is null
     or nullif(current_setting('test.derivaciones.lead_ocupado', true), '') is null then
    raise exception 'D05 el fixture requerido no está sembrado';
  end if;
end;
$fixture$;

select set_config(
  'request.jwt.claim.sub',
  current_setting('test.derivaciones.supervisor'),
  true
);
set local role authenticated;

do $comportamiento$
declare
  v_supervisor uuid := current_setting('test.derivaciones.supervisor')::uuid;
  v_asesor uuid := current_setting('test.derivaciones.asesor')::uuid;
  v_asesor_ajeno uuid := current_setting('test.derivaciones.asesor_ajeno')::uuid;
  v_lead uuid := current_setting('test.derivaciones.lead')::uuid;
  v_lead_ocupado uuid := current_setting('test.derivaciones.lead_ocupado')::uuid;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_antes jsonb;
  v_despues jsonb;
  v_final jsonb;
  v_asesor_antes jsonb;
  v_asesor_despues jsonb;
  v_asesor_final jsonb;
  v_movimiento jsonb;
  v_snapshot jsonb;
  v_asesor_snapshot jsonb;
  v_capital_snapshot numeric;
  v_actividades_antes integer;
begin
  v_antes := crm.reporte_derivaciones_equipo_fn(v_hoy, v_hoy);
  select elemento into v_asesor_antes
  from jsonb_array_elements(v_antes->'asesores') elemento
  where elemento->>'asesor_id' = v_asesor::text;

  if v_asesor_antes is null then
    raise exception 'D06 el reporte no incluye al asesor directo activo';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_antes->'asesores') elemento
    where elemento->>'asesor_id' = v_asesor_ajeno::text
  ) then
    raise exception 'D07 el reporte incluyó a un asesor de otro supervisor';
  end if;

  select count(*) into v_actividades_antes from crm.actividades where lead_id = v_lead;
  begin
    perform crm.derivar_leads_equipo_fn(array[v_lead, v_lead], array[v_asesor, v_asesor]);
    raise exception 'D08 el borrador duplicado fue aceptado';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform crm.derivar_leads_equipo_fn(
      array_fill(v_lead, array[1], array[0]),
      array_fill(v_asesor, array[1], array[0])
    );
    raise exception 'D08b se aceptaron arrays con límite inferior distinto de 1';
  exception
    when sqlstate '22023' then null;
  end;

  begin
    perform crm.derivar_leads_equipo_fn(array[v_lead], array[v_asesor_ajeno]);
    raise exception 'D09 el asesor de otro equipo fue aceptado';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    perform crm.derivar_leads_equipo_fn(
      array[v_lead, v_lead_ocupado],
      array[v_asesor, v_asesor]
    );
    raise exception 'D10 un borrador mixto parcialmente inválido fue aceptado';
  exception
    when sqlstate 'P0001' then null;
  end;

  if (select vendedor_id is null and asignado_supervisor_id = v_supervisor
      from crm.leads where id = v_lead) is distinct from true then
    raise exception 'D11 un borrador rechazado cambió la tenencia del lead';
  end if;

  perform crm.derivar_leads_equipo_fn(array[v_lead], array[v_asesor]);

  if (select vendedor_id = v_asesor and asignado_supervisor_id is null
      from crm.leads where id = v_lead) is distinct from true then
    raise exception 'D12 la derivación válida no entregó el lead al asesor';
  end if;
  if (select count(*) from crm.actividades where lead_id = v_lead) <> v_actividades_antes + 1 then
    raise exception 'D13 la derivación no dejó exactamente una actividad de reasignación';
  end if;

  v_despues := crm.reporte_derivaciones_equipo_fn(v_hoy, v_hoy);
  select elemento into v_asesor_despues
  from jsonb_array_elements(v_despues->'asesores') elemento
  where elemento->>'asesor_id' = v_asesor::text;

  if (v_asesor_despues->>'derivados')::integer <> (v_asesor_antes->>'derivados')::integer + 1
     or (v_asesor_despues->>'repartido_hoy')::integer <> (v_asesor_antes->>'repartido_hoy')::integer + 1
     or (v_asesor_despues->>'capital_pen')::numeric <> (v_asesor_antes->>'capital_pen')::numeric + 1000 then
    raise exception 'D14 cards tras derivar: antes %, después %', v_asesor_antes, v_asesor_despues;
  end if;

  select elemento into v_movimiento
  from jsonb_array_elements(v_despues->'movimientos_hoy') elemento
  where elemento->>'lead_id' = v_lead::text;
  if v_movimiento is null or (v_movimiento->>'reversible')::boolean is not true then
    raise exception 'D15 la derivación de hoy no aparece reversible';
  end if;
  if v_movimiento ?| array['telefono', 'correo', 'dni', 'notas'] then
    raise exception 'D16 el movimiento expone PII de contacto o notas';
  end if;

  -- El capital es una foto del momento de entrega, no el monto vivo del lead.
  v_capital_snapshot := (v_asesor_despues->>'capital_pen')::numeric;
  update crm.leads
  set monto_estimado = monto_estimado + 777
  where id = v_lead;
  v_snapshot := crm.reporte_derivaciones_equipo_fn(v_hoy, v_hoy);
  select elemento into v_asesor_snapshot
  from jsonb_array_elements(v_snapshot->'asesores') elemento
  where elemento->>'asesor_id' = v_asesor::text;
  if (v_asesor_snapshot->>'capital_pen')::numeric <> v_capital_snapshot then
    raise exception 'D17 el capital histórico cambió al editar el monto vivo del lead';
  end if;

  -- Ni siquiera sin gestión se acepta el atajo PATCH: toda devolución propia
  -- de hoy debe atravesar la RPC y su validación serializada.
  begin
    update crm.leads
    set vendedor_id = null,
        asignado_supervisor_id = v_supervisor
    where id = v_lead;
    raise exception 'D17b un PATCH directo eludió la RPC de devolución'
      using errcode = 'P0099';
  exception
    when sqlstate '42501' then null;
  end;
  if (select vendedor_id = v_asesor and asignado_supervisor_id is null
      from crm.leads where id = v_lead) is distinct from true then
    raise exception 'D17c el PATCH directo rechazado cambió la tenencia';
  end if;

  -- Cualquier gestión del asesor, incluida una nota, bloquea la devolución.
  -- El payload intenta retrofecharla: la guarda debe reemplazar ese timestamp
  -- controlable por un sello del servidor. La subtransacción se
  -- revierte al capturar el rechazo, por lo que luego aún podemos probar el OK.
  begin
    perform set_config('request.jwt.claim.sub', v_asesor::text, true);
    insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
    values (v_lead, 'nota', 'SONDA TRANSACCIONAL', v_asesor, timestamptz '2000-01-01 00:00Z');
    perform set_config('request.jwt.claim.sub', v_supervisor::text, true);
    perform crm.revertir_derivacion_equipo_fn(v_lead);
    raise exception 'D18 se devolvió un lead después de que el asesor lo gestionó'
      using errcode = 'P0099';
  exception
    when sqlstate 'P0001' then null;
  end;

  begin
    perform set_config('request.jwt.claim.sub', v_asesor::text, true);
    insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
    values (v_lead, 'tarea', 'SONDA TRANSACCIONAL', now() + interval '1 day', v_asesor);
    perform set_config('request.jwt.claim.sub', v_supervisor::text, true);
    perform crm.revertir_derivacion_equipo_fn(v_lead);
    raise exception 'D19 se devolvió un lead después de que el asesor creó una tarea'
      using errcode = 'P0099';
  exception
    when sqlstate 'P0001' then null;
  end;

  perform set_config('request.jwt.claim.sub', v_supervisor::text, true);
  perform crm.revertir_derivacion_equipo_fn(v_lead);

  if (select vendedor_id is null and asignado_supervisor_id = v_supervisor
      from crm.leads where id = v_lead) is distinct from true then
    raise exception 'D20 la devolución no regresó el lead a la bandeja correcta';
  end if;

  v_final := crm.reporte_derivaciones_equipo_fn(v_hoy, v_hoy);
  select elemento into v_asesor_final
  from jsonb_array_elements(v_final->'asesores') elemento
  where elemento->>'asesor_id' = v_asesor::text;

  if (v_asesor_final->>'derivados')::integer <> (v_asesor_antes->>'derivados')::integer
     or (v_asesor_final->>'repartido_hoy')::integer <> (v_asesor_antes->>'repartido_hoy')::integer
     or (v_asesor_final->>'capital_pen')::numeric <> (v_asesor_antes->>'capital_pen')::numeric then
    raise exception 'D21 devolver no deshizo los cards: antes %, final %', v_asesor_antes, v_asesor_final;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_final->'movimientos_hoy') elemento
    where elemento->>'lead_id' = v_lead::text
  ) then
    raise exception 'D22 el lead devuelto sigue apareciendo en movimientos de hoy';
  end if;
end;
$comportamiento$;

-- Un vendedor autenticado no puede usar ninguna de las tres superficies.
select set_config(
  'request.jwt.claim.sub',
  current_setting('test.derivaciones.asesor'),
  true
);
do $autorizacion$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_lead uuid := current_setting('test.derivaciones.lead')::uuid;
  v_asesor uuid := current_setting('test.derivaciones.asesor')::uuid;
begin
  begin
    perform crm.reporte_derivaciones_equipo_fn(v_hoy, v_hoy);
    raise exception 'D23 un vendedor consultó el reporte de supervisión';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform crm.derivar_leads_equipo_fn(array[v_lead], array[v_asesor]);
    raise exception 'D24 un vendedor usó la RPC de derivación';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform crm.revertir_derivacion_equipo_fn(v_lead);
    raise exception 'D25 un vendedor usó la RPC de devolución';
  exception when sqlstate '42501' then null;
  end;
end;
$autorizacion$;

select 'REPORTE_DERIVACIONES_TX_OK' as resultado;
rollback;
