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
  v_cliente_sin_meta uuid := '91000000-0000-4000-8000-000000000012';
  v_contrato_sin_meta uuid := '91000000-0000-4000-8000-000000000013';
  v_contrato_sup_cierre uuid := '91000000-0000-4000-8000-000000000015';
  v_contrato_sup_abierto uuid := '91000000-0000-4000-8000-000000000016';
  v_lead_sup_abierto uuid := '91000000-0000-4000-8000-000000000019';
  v_sla uuid := '91000000-0000-4000-8000-000000000020';
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_mes_abierto date := (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date;
  v_mes_cerrado date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_mes_sin_meta date := (date_trunc('month', now() at time zone 'America/Lima') - interval '8 months')::date;
  v_fin_abierto date;
  v_fin_cerrado date;
  v_cosecha jsonb;
  v_conversion jsonb;
  v_capital jsonb;
  v_ids_cosecha uuid[];
  v_ids_conversion uuid[];
  v_ids_capital uuid[];
  v_cartera_def text;
begin
  v_fin_abierto := (v_mes_abierto + interval '1 month - 1 day')::date;
  v_fin_cerrado := (v_mes_cerrado + interval '1 month - 1 day')::date;

  insert into auth.users (id) values
    (v_g), (v_sup_mes), (v_sup_hoy), (v_vendedor_mes), (v_vendedor_hoy),
    (v_cliente_sin_meta);

  insert into public.perfiles (id, nombre_completo, rol, activo) values
    (v_g, 'GERENCIA RANKING MES', 'admin', true),
    (v_sup_mes, 'SUPERVISOR DEL MES', 'comercial', true),
    (v_sup_hoy, 'SUPERVISOR DE HOY', 'comercial', true),
    -- La baja historica debe sobrevivir en el ranking de su mes.
    (v_vendedor_mes, 'VENDEDOR DEL MES', 'comercial', false),
    (v_vendedor_hoy, 'VENDEDOR NUEVO', 'comercial', true),
    (v_cliente_sin_meta, 'CLIENTE SIN META', 'cliente', true);

  insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
    (v_g, 'gerencia', null, true),
    (v_sup_mes, 'supervisor', null, true),
    (v_sup_hoy, 'supervisor', null, true),
    -- Hoy ya no esta activo y su supervisor actual tampoco es el sellado.
    (v_vendedor_mes, 'vendedor', v_sup_hoy, false),
    (v_vendedor_hoy, 'vendedor', v_sup_hoy, true);

  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  values (v_mes_sin_meta, 0.15, 'oraculo ranking mensual')
  on conflict do nothing;

  insert into crm.sla_politicas (
    id, version, vigente_desde, zona_horaria, tipo_reloj,
    primera_gestion_minutos, primer_contacto_minutos
  ) values (
    v_sla, 1, (v_mes_sin_meta - interval '1 year')::timestamptz,
    'America/Lima', 'corrido', 60, 120
  );
  insert into crm.sla_politica_etapas (
    politica_id, etapa, maximo_minutos
  ) values (v_sla, 'nuevo', 1440);

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

  -- Un vendedor puede producir aunque gerencia no le haya publicado meta. El
  -- cierre no puede borrar ese dinero: debe congelarlo bajo su supervisor
  -- vigente, con objetivos cero y las seis dimensiones canonicas completas.
  -- El dump de esquema no incluye el catalogo tecnico de productos. Solo esta
  -- fila historica de fixture salta sus triggers; el cierre y todos sus nucleos
  -- se ejecutan despues con los triggers otra vez activos.
  set local session_replication_role = replica;
  insert into public.contratos (
    id, numero_contrato, cliente_id, capital, moneda, modalidad,
    fecha_inicio, fecha_vencimiento, estado, creado_por, creado_en, categoria,
    producto_condicion_id, fecha_cierre_comercial, analista_cierre_id
  ) values
  (
    v_contrato_sin_meta, 'RANKING-SIN-META-001', v_cliente_sin_meta,
    43210, 'PEN', 'mensual', v_mes_sin_meta + 3, v_mes_sin_meta + 368,
    'activo', v_vendedor_mes,
    (v_mes_sin_meta + interval '3 days 16 hours')::timestamptz,
    'nuevo', '91000000-0000-4000-8000-000000000014',
    v_mes_sin_meta + 3, v_vendedor_mes
  ),
  -- La inversión es real, pero su responsable de cierre es supervisor: debe
  -- sumar al total empresa y quedar nominada fuera del ranking.
  (
    v_contrato_sup_cierre, 'RANKING-SUP-CIERRE-001', v_cliente_sin_meta,
    7777, 'PEN', 'mensual', v_mes_sin_meta + 4, v_mes_sin_meta + 369,
    'activo', v_sup_hoy,
    (v_mes_sin_meta + interval '4 days 16 hours')::timestamptz,
    'nuevo', '91000000-0000-4000-8000-000000000017',
    v_mes_sin_meta + 4, v_sup_hoy
  ),
  -- Mismo caso con el mes historico aun abierto: prueba la rama viva que usa
  -- Gerencia antes de que exista la foto definitiva.
  (
    v_contrato_sup_abierto, 'RANKING-SUP-ABIERTO-001', v_cliente_sin_meta,
    8888, 'PEN', 'mensual', v_mes_abierto + 4, v_mes_abierto + 369,
    'activo', v_sup_hoy,
    (v_mes_abierto + interval '4 days 16 hours')::timestamptz,
    'nuevo', '91000000-0000-4000-8000-000000000018',
    v_mes_abierto + 4, v_sup_hoy
  );
  set local session_replication_role = origin;

  -- Un episodio comercial abierto del supervisor hace visible la grieta exacta
  -- del contador: aporta al total empresa, pero no crea otro analista.
  set local session_replication_role = replica;
  insert into crm.leads (
    id, nombre_completo, telefono, monto_estimado,
    etapa, origen, vendedor_id, creado_en, sla_global_iniciado_en
  ) values (
    v_lead_sup_abierto, 'LEAD DE SUPERVISOR FUERA DE RANKING',
    '+51910000019', 1000,
    'nuevo', 'formulario', v_sup_hoy,
    (v_mes_abierto + interval '1 day 16 hours')::timestamptz,
    (v_mes_abierto + interval '1 day 16 hours')::timestamptz
  );
  insert into crm.lead_asignaciones (
    lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
    asignado_en, monto_estimado, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id,
    primera_gestion_limite_en, primer_contacto_limite_en
  ) values (
    v_lead_sup_abierto, 1, 1, v_sup_hoy, 'ingreso',
    (v_mes_abierto + interval '2 days 16 hours')::timestamptz,
    1000, 'PEN', 'formulario',
    (v_mes_abierto + interval '1 day 16 hours')::timestamptz,
    v_sla,
    (v_mes_abierto + interval '2 days 17 hours')::timestamptz,
    (v_mes_abierto + interval '2 days 18 hours')::timestamptz
  );
  set local session_replication_role = origin;

  perform set_config('test.uid', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_conversion := crm.cerrar_periodo(v_mes_sin_meta);
  if (v_conversion->>'ok')::boolean is not true
     or (v_conversion->>'meta_revision')::int <> 0
     or (v_conversion->>'vendedores')::int <> 1 then
    raise exception 'CIERRE SIN META ROTO: %', v_conversion;
  end if;
  if not exists (
    select 1
    from crm.cierre_mes_vendedor f
    cross join lateral jsonb_array_elements(f.detalles) d
    where f.periodo = v_mes_sin_meta
      and f.vendedor_id = v_vendedor_mes
      and f.supervisor_id = v_sup_hoy
      and f.supervisor_nombre = 'SUPERVISOR DE HOY'
      and f.conversion_objetivo = 0
      and jsonb_array_length(f.detalles) = 6
      and f.cartera ?& array[
        'conversiones_clientes', 'conversiones_renovacion',
        'conversiones_upgrade', 'operaciones_renovacion',
        'operaciones_upgrade', 'capital_renovado_pen',
        'capital_renovado_usd', 'capital_adicional_pen',
        'capital_adicional_usd', 'renovaciones_sin_desglose'
      ]
      and d->>'categoria' = 'nuevo'
      and d->>'moneda' = 'PEN'
      and (d->>'capital_objetivo')::numeric = 0
      and (d->>'contratos_objetivo')::int = 0
      and (d->>'capital_real')::numeric = 43210
      and (d->>'contratos_real')::int = 1
  ) then
    raise exception 'FOTO SIN META ROTA: la venta real no quedo congelada con objetivo cero';
  end if;
  if exists (
    select 1 from crm.cierre_mes_vendedor f
    where f.periodo = v_mes_sin_meta and f.vendedor_id = v_sup_hoy
  ) then
    raise exception 'RANKING ROTO: el supervisor recibio una fila rankeable';
  end if;
  if not exists (
    select 1
    from crm.periodos_cerrados pc
    cross join lateral jsonb_array_elements(pc.cobertura->'fuera_ranking') fr
    cross join lateral jsonb_array_elements(fr.value->'detalles') d
    where pc.periodo = v_mes_sin_meta
      and jsonb_array_length(pc.cobertura->'fuera_ranking') = 1
      and (fr.value->>'persona_id')::uuid = v_sup_hoy
      and fr.value->>'nombre' = 'SUPERVISOR DE HOY'
      and fr.value->>'rol_crm' = 'supervisor'
      and fr.value->>'motivo' = 'supervisor'
      and d.value->>'categoria' = 'nuevo'
      and d.value->>'moneda' = 'PEN'
      and (d.value->>'capital_real')::numeric = 7777
      and (d.value->>'contratos_real')::int = 1
  ) then
    raise exception 'FUERA DE RANKING ROTO: la inversion del supervisor no quedo nominada en la foto';
  end if;

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
  if jsonb_array_length(v_capital->'fuera_ranking') <> 1
     or (v_capital#>>'{fuera_ranking,0,persona_id}')::uuid <> v_sup_hoy
     or v_capital#>>'{fuera_ranking,0,rol_crm}' <> 'supervisor'
     or not exists (
       select 1
       from jsonb_array_elements(v_capital#>'{fuera_ranking,0,detalles}') d
       where d.value->>'categoria' = 'nuevo'
         and d.value->>'moneda' = 'PEN'
         and (d.value->>'capital_real')::numeric = 8888
         and (d.value->>'contratos_real')::int = 1
     ) then
    raise exception 'FUERA DE RANKING ABIERTO ROTO: %', v_capital->'fuera_ranking';
  end if;
  if (v_conversion#>>'{total,analistas}')::int <> jsonb_array_length(v_conversion->'responsables')
     or (v_conversion#>>'{total,analistas}')::int <> 1
     or (v_conversion#>>'{total,divisor}')::int <> 1
     or (v_conversion#>>'{total,numerador}')::numeric <> 0
     or (v_conversion#>>'{cobertura,fuera_de_roster,analistas}')::int <> 1
     or (v_conversion#>>'{cobertura,fuera_de_roster,divisor}')::int <> 1
     or (v_conversion#>>'{cobertura,fuera_de_roster,numerador}')::numeric <> 0
     or v_conversion->'cartera' is distinct from v_conversion#>'{total,cartera}'
     or (v_conversion->>'revision')::int <> 2
     or (v_cosecha->>'revision')::int <> 2
     or (v_capital->>'revision')::int <> 2
     or (v_conversion#>>'{cierre,cerrado}')::boolean
        is distinct from (v_cosecha#>>'{cierre,cerrado}')::boolean
     or (v_conversion#>>'{cierre,cerrado}')::boolean
        is distinct from (v_capital#>>'{cierre,cerrado}')::boolean then
    raise exception 'CONTADOR/TOKENS/CARTERA ROTOS en mes abierto: conversion %, cosecha %, capital %',
      v_conversion, v_cosecha, v_capital;
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
    (v_mes_cerrado, true, 0.15, 1, $_fuera$
      {
        "medible": true,
        "fuera_ranking": [{
          "persona_id": "91000000-0000-4000-8000-000000000003",
          "nombre": "SUPERVISOR DE HOY",
          "rol_crm": "supervisor",
          "motivo": "supervisor",
          "conversion": {
            "divisor": 4,
            "divisor_aproximado": 0,
            "divisor_por_motivo": {"asignacion": 4},
            "cierres_no_referidos": 1,
            "cierres_referidos": 0,
            "cierres_de_arrastre": 0,
            "referidos_recibidos": 0,
            "numerador": 1
          },
          "detalles": [
            {"categoria":"nuevo","moneda":"PEN","capital_objetivo":0,"capital_real":7000,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":1,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0},
            {"categoria":"nuevo","moneda":"USD","capital_objetivo":0,"capital_real":0,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":0,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0},
            {"categoria":"renovacion","moneda":"PEN","capital_objetivo":0,"capital_real":0,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":0,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0},
            {"categoria":"renovacion","moneda":"USD","capital_objetivo":0,"capital_real":0,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":0,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0},
            {"categoria":"upgrade","moneda":"PEN","capital_objetivo":0,"capital_real":0,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":0,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0},
            {"categoria":"upgrade","moneda":"USD","capital_objetivo":0,"capital_real":0,"capital_cumplimiento_pct":null,"contratos_objetivo":0,"contratos_real":0,"contratos_cumplimiento_pct":null,"capital_ajuste":0,"contratos_ajuste":0}
          ],
          "cartera": {
            "conversiones_clientes": 1,
            "conversiones_renovacion": 1,
            "conversiones_upgrade": 0,
            "operaciones_renovacion": 1,
            "operaciones_upgrade": 0,
            "capital_renovado_pen": 5000,
            "capital_renovado_usd": 0,
            "capital_adicional_pen": 0,
            "capital_adicional_usd": 0,
            "renovaciones_sin_desglose": 0
          }
        }]
      }
    $_fuera$::jsonb);
  insert into crm.cierre_mes_vendedor (
    periodo, vendedor_id, nombre_completo, supervisor_id, supervisor_nombre,
    divisor, divisor_aproximado, divisor_por_motivo,
    cierres_no_referidos, cierres_referidos, cierres_de_arrastre,
    numerador, conversion_pct, estado,
    referidos_recibidos, referidos_dados_de_alta, referidos_aporta_pct,
    procedencia, conversion_objetivo, detalles, cartera
  ) values (
    v_mes_cerrado, v_vendedor_mes, 'VENDEDOR DEL MES', v_sup_mes, 'SUPERVISOR DEL MES',
    0, 0, '{}'::jsonb,
    0, 0, 0,
    0, null, 'sin_actividad',
    0, 0, null,
    '[]'::jsonb, 0,
    jsonb_build_array(
      jsonb_build_object('categoria','nuevo','moneda','PEN','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0),
      jsonb_build_object('categoria','nuevo','moneda','USD','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0),
      jsonb_build_object('categoria','renovacion','moneda','PEN','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0),
      jsonb_build_object('categoria','renovacion','moneda','USD','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0),
      jsonb_build_object('categoria','upgrade','moneda','PEN','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0),
      jsonb_build_object('categoria','upgrade','moneda','USD','capital_objetivo',0,'capital_real',0,'capital_cumplimiento_pct',null,'contratos_objetivo',0,'contratos_real',0,'contratos_cumplimiento_pct',null,'capital_ajuste',0,'contratos_ajuste',0)
    ),
    '{"conversiones_clientes":2,"conversiones_renovacion":1,"conversiones_upgrade":1,"operaciones_renovacion":1,"operaciones_upgrade":1,"capital_renovado_pen":12000,"capital_renovado_usd":300,"capital_adicional_pen":2000,"capital_adicional_usd":50,"renovaciones_sin_desglose":0}'::jsonb
  );

  -- Si una lectura cerrada toca el nucleo vivo de cartera, debe caer. Las dos
  -- RPC mensuales tienen que sobrevivir y servir solo la columna congelada.
  select pg_get_functiondef(
    'private.metricas_cartera_por_vendedor(date)'::regprocedure
  ) into v_cartera_def;
  execute $mutante$
    create or replace function private.metricas_cartera_por_vendedor(p_periodo date)
    returns table (
      vendedor_id uuid, conversiones_clientes integer,
      conversiones_renovacion integer, conversiones_upgrade integer,
      operaciones_renovacion integer, operaciones_upgrade integer,
      capital_renovado_pen numeric, capital_renovado_usd numeric,
      capital_adicional_pen numeric, capital_adicional_usd numeric,
      renovaciones_sin_desglose integer
    ) language plpgsql stable security definer set search_path='' as $f$
    begin
      raise exception 'CARTERA VIVA INVOCADA EN MES CERRADO';
    end;
    $f$
  $mutante$;

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
     or (v_conversion#>>'{cartera,conversiones_clientes}')::int <> 2
     or (v_capital#>>'{vendedores,0,convertidos}')::int <> 2
     or jsonb_array_length(v_capital->'fuera_ranking') <> 0
     or (v_conversion->>'revision')::int <> 1
     or (v_cosecha->>'revision')::int <> 1
     or (v_capital->>'revision')::int <> 1
     or (v_conversion#>>'{cierre,cerrado}')::boolean is not true
     or (v_cosecha#>>'{cierre,cerrado}')::boolean is not true
     or (v_capital#>>'{cierre,cerrado}')::boolean is not true then
    raise exception 'FOTO/TOKENS ROTOS en mes cerrado: conversion %, cosecha %, capital %',
      v_conversion, v_cosecha, v_capital;
  end if;

  -- Gerencia conserva el total empresarial, pero el supervisor externo no
  -- aparece entre responsables ni aumenta el contador de analistas.
  perform set_config('test.uid', v_g::text, true);
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  v_conversion := crm.conversion_mensual_fn(v_mes_cerrado);
  v_capital := crm.cumplimiento_metas_fn(v_mes_cerrado);
  if (v_conversion#>>'{total,analistas}')::int <> 1
     or (v_conversion#>>'{total,divisor}')::int <> 4
     or (v_conversion#>>'{total,numerador}')::numeric <> 1
     or (v_conversion#>>'{cobertura,fuera_de_roster,analistas}')::int <> 1
     or (v_conversion#>>'{cartera,conversiones_clientes}')::int <> 3
     or jsonb_array_length(v_conversion->'responsables') <> 1
     or (v_conversion#>>'{responsables,0,vendedor_id}')::uuid <> v_vendedor_mes
     or jsonb_array_length(v_capital->'vendedores') <> 1
     or jsonb_array_length(v_capital->'fuera_ranking') <> 1
     or (v_capital#>>'{fuera_ranking,0,persona_id}')::uuid <> v_sup_hoy
     or (v_capital#>>'{fuera_ranking,0,detalles,0,capital_real}')::numeric <> 7000 then
    raise exception 'TOTAL EMPRESA / FUERA DE RANKING CERRADO ROTO: conversion %, capital %',
      v_conversion, v_capital;
  end if;

  execute v_cartera_def;

  perform set_config('test.uid', v_sup_hoy::text, true);
  perform set_config('request.jwt.claim.sub', v_sup_hoy::text, true);
  if jsonb_array_length(crm.metricas_conversiones_equipo_fn(v_mes_cerrado, v_fin_cerrado)->'responsables') <> 0
     or jsonb_array_length(crm.conversion_mensual_fn(v_mes_cerrado)->'responsables') <> 0
     or jsonb_array_length(crm.cumplimiento_metas_fn(v_mes_cerrado)->'vendedores') <> 0
     or jsonb_array_length(crm.cumplimiento_metas_fn(v_mes_cerrado)->'fuera_ranking') <> 0
     or (crm.conversion_mensual_fn(v_mes_cerrado)#>>'{cartera,conversiones_clientes}')::int <> 0 then
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

  raise notice 'RANKING POBLACION MENSUAL OK: cosecha/conversion/capital, sin meta, fuera de ranking, altas, bajas, transferencia y scopes';
end;
$oraculo$;

rollback;

select 'TEST-RANKING-POBLACION-MENSUAL: TODO VERDE' as resultado;
