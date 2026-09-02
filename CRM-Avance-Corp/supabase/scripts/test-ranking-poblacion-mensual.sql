-- Regresion conjunta de las tres superficies del ranking mensual:
-- cosecha (`metricas_conversiones_equipo_fn`), conversion y cumplimiento /
-- capital. La poblacion de un mes historico sale del MES, no del roster de hoy.
-- Ejecutar solo en una base local/desechable con las migraciones aplicadas.
-- Todo queda dentro de la transaccion y termina en ROLLBACK.

\set ON_ERROR_STOP on

begin;

do $oraculo$
declare
  v_g uuid := '91000000-0000-4000-8000-000000000001';
  v_sup_mes uuid := '91000000-0000-4000-8000-000000000002';
  v_sup_hoy uuid := '91000000-0000-4000-8000-000000000003';
  v_vendedor_mes uuid := '91000000-0000-4000-8000-000000000004';
  v_vendedor_hoy uuid := '91000000-0000-4000-8000-000000000005';
  v_meta_rev1 uuid := '91000000-0000-4000-8000-000000000006';
  v_meta_rev2 uuid := '91000000-0000-4000-8000-000000000007';
  v_mv_rev1 uuid := '91000000-0000-4000-8000-000000000008';
  v_mv_rev2 uuid := '91000000-0000-4000-8000-000000000009';
  v_meta_actual uuid := '91000000-0000-4000-8000-000000000010';
  v_mv_actual uuid := '91000000-0000-4000-8000-000000000011';
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes_abierto date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_mes_cerrado date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_fin_abierto date;
  v_fin_cerrado date;
  v_cosecha jsonb;
  v_conversion jsonb;
  v_capital jsonb;
  v_ids_cosecha uuid[];
  v_ids_conversion uuid[];
  v_ids_capital uuid[];
begin
  v_fin_abierto := (v_mes_abierto + interval '1 month - 1 day')::date;
  v_fin_cerrado := (v_mes_cerrado + interval '1 month - 1 day')::date;

  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g, 'GERENCIA RANKING MES', 'admin', true),
    (v_sup_mes, 'SUPERVISOR DEL MES', 'comercial', true),
    (v_sup_hoy, 'SUPERVISOR DE HOY', 'comercial', true),
    -- La baja historica debe sobrevivir en el ranking de su mes.
    (v_vendedor_mes, 'VENDEDOR DEL MES', 'comercial', false),
    (v_vendedor_hoy, 'VENDEDOR NUEVO', 'comercial', true);

  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
    (v_g, 'gerencia', null, true),
    (v_sup_mes, 'supervisor', null, true),
    (v_sup_hoy, 'supervisor', null, true),
    -- Hoy ya no esta activo y su supervisor actual tampoco es el sellado.
    (v_vendedor_mes, 'vendedor', v_sup_hoy, false),
    (v_vendedor_hoy, 'vendedor', v_sup_hoy, true);

  -- Dos revisiones del mes abierto: la RPC debe elegir la ultima. La primera
  -- contenia al vendedor actual; la vigente contiene al vendedor historico.
  insert into crm.meta_periodos
    (id, periodo, revision, publicada_por, publicada_en) values
    (v_meta_rev1, v_mes_abierto, 1, v_g, now() - interval '1 hour'),
    (v_meta_rev2, v_mes_abierto, 2, v_g, now());
  insert into crm.metas_vendedor
    (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mv_rev1, v_meta_rev1, v_vendedor_hoy, v_sup_hoy, 20),
    (v_mv_rev2, v_meta_rev2, v_vendedor_mes, v_sup_mes, 20);

  -- El control del mes vigente tiene una publicacion alineada con el roster
  -- vivo. El alta de septiembre NO puede colarse en la foto de agosto.
  insert into crm.meta_periodos
    (id, periodo, revision, publicada_por, publicada_en) values
    (v_meta_actual, v_mes_actual, 1, v_g, now());
  insert into crm.metas_vendedor
    (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo) values
    (v_mv_actual, v_meta_actual, v_vendedor_hoy, v_sup_hoy, 20);

  perform set_config('test.uid', v_g::text, true);
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  v_cosecha := crm.metricas_conversiones_equipo_fn(v_mes_abierto, v_fin_abierto);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_cosecha
  from jsonb_array_elements(v_cosecha->'responsables') e;
  v_conversion := crm.conversion_mensual_fn(v_mes_abierto);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_conversion
  from jsonb_array_elements(v_conversion->'responsables') e;
  v_capital := crm.cumplimiento_metas_fn(v_mes_abierto);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_capital
  from jsonb_array_elements(v_capital->'vendedores') e;
  if v_ids_cosecha is distinct from array[v_vendedor_mes]
     or v_ids_conversion is distinct from v_ids_cosecha
     or v_ids_capital is distinct from v_ids_cosecha then
    raise exception 'MES ABIERTO ROTO: esperaba foto %, cosecha %, conversion %, capital %',
      array[v_vendedor_mes], v_ids_cosecha, v_ids_conversion, v_ids_capital;
  end if;
  if v_conversion->'cartera' is distinct from v_conversion#>'{total,cartera}'
     or v_conversion->'cartera' is distinct from v_capital->'cartera' then
    raise exception 'WRAPPER CARTERA ROTO en mes abierto: conversion %, total %, capital %',
      v_conversion->'cartera', v_conversion#>'{total,cartera}', v_capital->'cartera';
  end if;

  -- Durante el ajuste, los tres contratos recortan la foto por el ambito
  -- vigente. La transferencia ya esta bajo SUPERVISOR DE HOY, aunque la foto
  -- mensual conserve el supervisor anterior para mostrarlo y auditarlo.
  perform set_config('test.uid', v_sup_hoy::text, true);
  perform set_config('request.jwt.claim.sub', v_sup_hoy::text, true);
  v_cosecha := crm.metricas_conversiones_equipo_fn(v_mes_abierto, v_fin_abierto);
  v_conversion := crm.conversion_mensual_fn(v_mes_abierto);
  v_capital := crm.cumplimiento_metas_fn(v_mes_abierto);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_cosecha from jsonb_array_elements(v_cosecha->'responsables') e;
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_conversion from jsonb_array_elements(v_conversion->'responsables') e;
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_capital from jsonb_array_elements(v_capital->'vendedores') e;
  if v_ids_cosecha is distinct from array[v_vendedor_mes]
     or v_ids_conversion is distinct from v_ids_cosecha
     or v_ids_capital is distinct from v_ids_cosecha then
    raise exception 'AMBITO ABIERTO ROTO para supervisor actual: cosecha %, conversion %, capital %',
      v_ids_cosecha, v_ids_conversion, v_ids_capital;
  end if;

  perform set_config('test.uid', v_sup_mes::text, true);
  perform set_config('request.jwt.claim.sub', v_sup_mes::text, true);
  if jsonb_array_length(crm.metricas_conversiones_equipo_fn(v_mes_abierto, v_fin_abierto)->'responsables') <> 0
     or jsonb_array_length(crm.conversion_mensual_fn(v_mes_abierto)->'responsables') <> 0
     or jsonb_array_length(crm.cumplimiento_metas_fn(v_mes_abierto)->'vendedores') <> 0 then
    raise exception 'AMBITO ABIERTO ROTO: el supervisor anterior vio una transferencia fuera de su ambito vigente';
  end if;

  -- Foto sellada. El vendedor pertenecia al supervisor del mes, aunque hoy el
  -- roster lo coloque bajo otro y ambos flags del vendedor esten apagados.
  insert into crm.periodos_cerrados
    (periodo, automatico, ponderacion_referido, meta_revision, cobertura)
  values
    (v_mes_cerrado, true, 0.15, 1, '{"medible":true}'::jsonb);
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct,
    procedencia, detalles
  ) values (
    v_mes_cerrado, v_vendedor_mes, 'VENDEDOR DEL MES', v_sup_mes, 'SUPERVISOR DEL MES',
    0, 0, '{}'::jsonb,
    0, 0, 0,
    0, null, 'sin_actividad',
    0, 0, null,
    '[]'::jsonb, '[]'::jsonb
  );

  perform set_config('test.uid', v_sup_mes::text, true);
  perform set_config('request.jwt.claim.sub', v_sup_mes::text, true);
  v_cosecha := crm.metricas_conversiones_equipo_fn(v_mes_cerrado, v_fin_cerrado);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_cosecha
  from jsonb_array_elements(v_cosecha->'responsables') e;
  v_conversion := crm.conversion_mensual_fn(v_mes_cerrado);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_conversion
  from jsonb_array_elements(v_conversion->'responsables') e;
  v_capital := crm.cumplimiento_metas_fn(v_mes_cerrado);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_capital
  from jsonb_array_elements(v_capital->'vendedores') e;
  if v_ids_cosecha is distinct from array[v_vendedor_mes]
     or v_ids_conversion is distinct from v_ids_cosecha
     or v_ids_capital is distinct from v_ids_cosecha then
    raise exception 'MES CERRADO ROTO para supervisor sellado: cosecha %, conversion %, capital %',
      v_ids_cosecha, v_ids_conversion, v_ids_capital;
  end if;
  if v_conversion->'cartera' is distinct from v_conversion#>'{total,cartera}'
     or v_conversion->'cartera' is distinct from v_capital->'cartera' then
    raise exception 'WRAPPER CARTERA ROTO en mes cerrado: conversion %, total %, capital %',
      v_conversion->'cartera', v_conversion#>'{total,cartera}', v_capital->'cartera';
  end if;

  perform set_config('test.uid', v_sup_hoy::text, true);
  perform set_config('request.jwt.claim.sub', v_sup_hoy::text, true);
  if jsonb_array_length(crm.metricas_conversiones_equipo_fn(v_mes_cerrado, v_fin_cerrado)->'responsables') <> 0
     or jsonb_array_length(crm.conversion_mensual_fn(v_mes_cerrado)->'responsables') <> 0
     or jsonb_array_length(crm.cumplimiento_metas_fn(v_mes_cerrado)->'vendedores') <> 0 then
    raise exception 'MES CERRADO ROTO: el supervisor actual vio la foto sellada del supervisor anterior';
  end if;

  -- Control: el mes actual y un rango historico LIBRE conservan el roster de
  -- hoy. La correccion solo se activa para un mes calendario historico entero.
  perform set_config('test.uid', v_g::text, true);
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  v_cosecha := crm.metricas_conversiones_equipo_fn(v_mes_actual, v_hoy);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_cosecha
  from jsonb_array_elements(v_cosecha->'responsables') e;
  v_conversion := crm.conversion_mensual_fn(v_mes_actual);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_conversion
  from jsonb_array_elements(v_conversion->'responsables') e;
  v_capital := crm.cumplimiento_metas_fn(v_mes_actual);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_capital
  from jsonb_array_elements(v_capital->'vendedores') e;
  if v_ids_cosecha is distinct from array[v_vendedor_hoy]
     or v_ids_conversion is distinct from v_ids_cosecha
     or v_ids_capital is distinct from v_ids_cosecha then
    raise exception 'CONTROL MES ACTUAL ROTO: esperaba alta vigente %, cosecha %, conversion %, capital %',
      array[v_vendedor_hoy], v_ids_cosecha, v_ids_conversion, v_ids_capital;
  end if;

  v_cosecha := crm.metricas_conversiones_equipo_fn(v_mes_abierto + 5, v_mes_abierto + 10);
  select coalesce(array_agg((e.value->>'vendedor_id')::uuid order by e.value->>'vendedor_id'), '{}'::uuid[])
    into v_ids_cosecha
  from jsonb_array_elements(v_cosecha->'responsables') e;
  if v_ids_cosecha is distinct from array[v_vendedor_hoy] then
    raise exception 'CONTROL RANGO LIBRE ROTO: esperaba roster vigente %, obtuvo %',
      v_vendedor_hoy, v_ids_cosecha;
  end if;

  -- Las tres puertas siguen fail-closed sin identidad. Esta sonda prueba el
  -- gate de conducta; el postflight de la migracion prueba ademas el ACL.
  perform set_config('test.uid', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform crm.metricas_conversiones_equipo_fn(v_mes_abierto, v_fin_abierto);
    raise exception 'GATE ROTO: cosecha acepto una llamada sin identidad';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform crm.conversion_mensual_fn(v_mes_abierto);
    raise exception 'GATE ROTO: conversion acepto una llamada sin identidad';
  exception when sqlstate '42501' then null;
  end;
  begin
    perform crm.cumplimiento_metas_fn(v_mes_abierto);
    raise exception 'GATE ROTO: capital acepto una llamada sin identidad';
  exception when sqlstate '42501' then null;
  end;

  raise notice 'RANKING POBLACION MENSUAL OK: cosecha/conversion/capital, altas, bajas, transferencia y scopes';
end;
$oraculo$;

rollback;

select 'TEST-RANKING-POBLACION-MENSUAL: TODO VERDE' as resultado;
