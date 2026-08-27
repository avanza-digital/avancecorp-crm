-- Gate transaccional autocontenido de public.crear_contrato para Mi cartera.
-- Requiere 20260824231133 aplicada y el producto técnico creado por las
-- migraciones de catálogo. Todos los usuarios, contratos, cuotas y operaciones
-- de este archivo desaparecen con el ROLLBACK final.

\set ON_ERROR_STOP on

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regclass('crm.operaciones_cartera') is null then
    raise exception 'GCAR-C01: falta la RPC o el ledger de operaciones';
  end if;
  if not exists (
    select 1 from crm.productos_inversion p
    where p.codigo = 'HISTORICO-SIN-CATALOGO' and p.es_legacy
  ) or not exists (select 1 from crm.producto_condiciones) then
    raise exception 'GCAR-C02: falta el catálogo técnico para fotografiar contratos';
  end if;
end;
$preflight$;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('7fc10000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'gcar-contratos-gerencia@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc10000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'gcar-contratos-vendedor@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc10000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'gcar-contratos-supervisor@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc20000-0000-4000-8000-000000000001', 'authenticated', 'authenticated',
   'gcar-renovable@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc20000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'gcar-temprano@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc20000-0000-4000-8000-000000000003', 'authenticated', 'authenticated',
   'gcar-upgrade-historico@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc20000-0000-4000-8000-000000000004', 'authenticated', 'authenticated',
   'gcar-upgrade-primero@test.invalid', now(), '{}', '{}', now(), now()),
  ('7fc20000-0000-4000-8000-000000000005', 'authenticated', 'authenticated',
   'gcar-contrato-nuevo@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (
  id, nombre_completo, correo, rol, activo, asesor_perfil_id, creado_por
)
values
  ('7fc10000-0000-4000-8000-000000000001', 'GCAR GERENCIA CONTRATOS',
   'gcar-contratos-gerencia@test.invalid', 'comercial', true, null, null),
  ('7fc10000-0000-4000-8000-000000000002', 'GCAR VENDEDOR CONTRATOS',
   'gcar-contratos-vendedor@test.invalid', 'comercial', true, null,
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc10000-0000-4000-8000-000000000003', 'GCAR SUPERVISOR CONTRATOS',
   'gcar-contratos-supervisor@test.invalid', 'comercial', true, null,
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc20000-0000-4000-8000-000000000001', 'GCAR CLIENTE RENOVABLE',
   'gcar-renovable@test.invalid', 'cliente', true,
   '7fc10000-0000-4000-8000-000000000002',
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc20000-0000-4000-8000-000000000002', 'GCAR CLIENTE TEMPRANO',
   'gcar-temprano@test.invalid', 'cliente', true,
   '7fc10000-0000-4000-8000-000000000002',
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc20000-0000-4000-8000-000000000003', 'GCAR CLIENTE UPGRADE HISTORICO',
   'gcar-upgrade-historico@test.invalid', 'cliente', true,
   '7fc10000-0000-4000-8000-000000000002',
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc20000-0000-4000-8000-000000000004', 'GCAR CLIENTE UPGRADE PRIMERO',
   'gcar-upgrade-primero@test.invalid', 'cliente', true,
   '7fc10000-0000-4000-8000-000000000002',
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc20000-0000-4000-8000-000000000005', 'GCAR CLIENTE CONTRATO NUEVO',
   'gcar-contrato-nuevo@test.invalid', 'cliente', true,
   '7fc10000-0000-4000-8000-000000000002',
   '7fc10000-0000-4000-8000-000000000001');

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo, creado_por)
values
  ('7fc10000-0000-4000-8000-000000000001', 'gerencia', null, true, null),
  ('7fc10000-0000-4000-8000-000000000003', 'supervisor', null, true,
   '7fc10000-0000-4000-8000-000000000001'),
  ('7fc10000-0000-4000-8000-000000000002', 'vendedor',
   '7fc10000-0000-4000-8000-000000000003', true,
   '7fc10000-0000-4000-8000-000000000001');

-- Los tres contratos origen son historia controlada. Se construyen con los
-- triggers apagados solo para fijar fechas/estados imposibles de obtener hoy;
-- toda operación que se prueba después corre con los triggers activos.
set local session_replication_role = replica;

insert into public.contratos (
  id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
  modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, estado,
  creado_por, creado_en, categoria, producto_condicion_id,
  fecha_cierre_comercial, fuente_cierre_comercial
)
values
  (
    '7fc30000-0000-4000-8000-000000000001', 'GCAR-ORIGEN-RENOVABLE',
    '7fc20000-0000-4000-8000-000000000001', 1000, 'PEN', 15,
    'mensual', 'simple',
    ((now() at time zone 'America/Lima')::date - interval '1 year')::date,
    (now() at time zone 'America/Lima')::date, 'vencido',
    '7fc10000-0000-4000-8000-000000000002', now() - interval '1 year',
    'nuevo', (select id from crm.producto_condiciones order by id limit 1),
    ((date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date),
    'registro'
  ),
  (
    '7fc30000-0000-4000-8000-000000000002', 'GCAR-ORIGEN-TEMPRANO',
    '7fc20000-0000-4000-8000-000000000002', 1000, 'PEN', 15,
    'mensual', 'simple',
    ((now() at time zone 'America/Lima')::date - interval '1 year')::date,
    ((now() at time zone 'America/Lima')::date + 1), 'activo',
    '7fc10000-0000-4000-8000-000000000002', now() - interval '1 year',
    'nuevo', (select id from crm.producto_condiciones order by id limit 1),
    ((date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date),
    'registro'
  ),
  (
    '7fc30000-0000-4000-8000-000000000003', 'GCAR-ORIGEN-UPGRADE',
    '7fc20000-0000-4000-8000-000000000003', 1200, 'PEN', 15,
    'mensual', 'simple',
    ((now() at time zone 'America/Lima')::date - interval '2 months')::date,
    ((now() at time zone 'America/Lima')::date + interval '10 months')::date,
    'activo', '7fc10000-0000-4000-8000-000000000002',
    now() - interval '2 months', 'nuevo',
    (select id from crm.producto_condiciones order by id limit 1),
    ((date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date),
    'registro'
  );

insert into public.cronograma_pagos (
  id, contrato_id, numero_cuota, fecha_programada,
  monto_programado, estado, tipo
)
values
  ('7fc40000-0000-4000-8000-000000000001',
   '7fc30000-0000-4000-8000-000000000001', 1,
   (now() at time zone 'America/Lima')::date - 30, 100, 'vencido', 'cuota'),
  ('7fc40000-0000-4000-8000-000000000002',
   '7fc30000-0000-4000-8000-000000000001', 2,
   (now() at time zone 'America/Lima')::date, 100, 'pendiente', 'cuota'),
  ('7fc40000-0000-4000-8000-000000000003',
   '7fc30000-0000-4000-8000-000000000001', 3,
   (now() at time zone 'America/Lima')::date - 60, 100, 'pagado', 'cuota');

set local session_replication_role = origin;

select pg_catalog.set_config(
  'request.jwt.claim.sub',
  '7fc10000-0000-4000-8000-000000000001',
  true
);

do $reglas$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_periodo date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_respuesta jsonb;
  v_contrato_nuevo uuid;
  v_operacion uuid;
  v_ops_antes integer;
  v_contratos_antes integer;
  v_fallo boolean;
  v_metricas record;
begin
  select count(*) into v_ops_antes from crm.operaciones_cartera;
  select count(*) into v_contratos_antes from public.contratos;

  -- Contrato nuevo: crea contrato y cuota, pero no inventa una operación de
  -- renovación/upgrade ni un indicador de conversión.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_respuesta := public.crear_contrato(
    jsonb_build_object(
      'numero_contrato', 'GCAR-CONTRATO-NUEVO',
      'cliente_id', '7fc20000-0000-4000-8000-000000000005',
      'capital', 500, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
      'categoria', 'nuevo'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
      'monto_programado', 100, 'tipo', 'cuota'
    ))
  );
  if (v_respuesta->>'id')::uuid is null
     or v_respuesta->>'operacion_id' is not null
     or v_respuesta->>'conversion_elegible' is not null
     or not exists (
       select 1 from public.cronograma_pagos q
       where q.contrato_id = (v_respuesta->>'id')::uuid
         and q.estado = 'pendiente'
     )
     or exists (
       select 1 from crm.operaciones_cartera o
       where o.contrato_nuevo_id = (v_respuesta->>'id')::uuid
     ) then
    raise exception 'GCAR-C03: el contrato nuevo perdió cuota o inventó operación';
  end if;

  -- Fallo posterior al INSERT del contrato y de una primera cuota: la sentencia
  -- completa debe revertirse y el contrato origen debe seguir intacto.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_fallo := false;
  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'numero_contrato', 'GCAR-RENOVACION-ROLLBACK',
        'cliente_id', '7fc20000-0000-4000-8000-000000000001',
        'capital', 1100, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
        'categoria', 'renovacion',
        'contrato_origen_id', '7fc30000-0000-4000-8000-000000000001',
        'capital_renovado', 800, 'capital_adicional', 300
      ),
      jsonb_build_array(
        jsonb_build_object(
          'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
          'monto_programado', 100, 'tipo', 'cuota'
        ),
        jsonb_build_object(
          'numero_cuota', 2, 'fecha_programada', v_hoy + 60,
          'monto_programado', 100, 'tipo', 'tipo_invalido'
        )
      )
    );
  exception when check_violation then
    v_fallo := true;
  end;
  if not v_fallo
     or exists (select 1 from public.contratos where numero_contrato = 'GCAR-RENOVACION-ROLLBACK')
     or (select count(*) from crm.operaciones_cartera) <> v_ops_antes
     or (select count(*) from public.contratos) <> v_contratos_antes + 1
     or exists (
       select 1 from public.cronograma_pagos
       where contrato_id = '7fc30000-0000-4000-8000-000000000001'
         and estado = 'trasladado'
     ) then
    raise exception 'GCAR-C04: el fallo del cronograma dejó escritura parcial';
  end if;

  -- El puente económico debe cerrar exactamente.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_fallo := false;
  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'numero_contrato', 'GCAR-RENOVACION-SUMA-INVALIDA',
        'cliente_id', '7fc20000-0000-4000-8000-000000000001',
        'capital', 1200, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
        'categoria', 'renovacion',
        'contrato_origen_id', '7fc30000-0000-4000-8000-000000000001',
        'capital_renovado', 800, 'capital_adicional', 300
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
        'monto_programado', 100, 'tipo', 'cuota'
      ))
    );
  exception when sqlstate '22023' then
    v_fallo := true;
  end;
  if not v_fallo then
    raise exception 'GCAR-C05: aceptó capital nuevo distinto al puente';
  end if;

  -- Antes de la fecha fin la renovación está cerrada.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_fallo := false;
  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'numero_contrato', 'GCAR-RENOVACION-TEMPRANA',
        'cliente_id', '7fc20000-0000-4000-8000-000000000002',
        'capital', 1000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', v_hoy + 1, 'fecha_vencimiento', v_hoy + 366,
        'categoria', 'renovacion',
        'contrato_origen_id', '7fc30000-0000-4000-8000-000000000002',
        'capital_renovado', 1000, 'capital_adicional', 0
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', v_hoy + 31,
        'monto_programado', 100, 'tipo', 'cuota'
      ))
    );
  exception when sqlstate '22023' then
    v_fallo := true;
  end;
  if not v_fallo then
    raise exception 'GCAR-C06: aceptó renovación antes de la fecha fin';
  end if;

  -- Renovación válida realizada por Gerencia y acreditada al dueño de cartera.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_respuesta := public.crear_contrato(
    jsonb_build_object(
      'numero_contrato', 'GCAR-RENOVACION-VALIDA',
      'cliente_id', '7fc20000-0000-4000-8000-000000000001',
      'capital', 1100, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
      'categoria', 'renovacion',
      'contrato_origen_id', '7fc30000-0000-4000-8000-000000000001',
      'capital_renovado', 800, 'capital_adicional', 300
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
      'monto_programado', 100, 'tipo', 'cuota'
    ))
  );
  v_contrato_nuevo := (v_respuesta->>'id')::uuid;
  v_operacion := (v_respuesta->>'operacion_id')::uuid;

  if v_contrato_nuevo is null or v_operacion is null
     or coalesce((v_respuesta->>'conversion_elegible')::boolean, false) is not true
     or not exists (
       select 1 from crm.operaciones_cartera o
       where o.id = v_operacion
         and o.cliente_id = '7fc20000-0000-4000-8000-000000000001'
         and o.vendedor_id = '7fc10000-0000-4000-8000-000000000002'
         and o.tipo = 'renovacion'
         and o.contrato_origen_id = '7fc30000-0000-4000-8000-000000000001'
         and o.contrato_nuevo_id = v_contrato_nuevo
         and o.moneda = 'PEN'
         and o.capital_renovado = 800
         and o.capital_adicional = 300
         and o.desglose_completo
         and o.fuente = 'flujo_cartera'
     ) then
    raise exception 'GCAR-C07: la renovación perdió desglose o atribución';
  end if;

  if not exists (
       select 1 from public.contratos c
       where c.id = '7fc30000-0000-4000-8000-000000000001'
         and c.estado = 'renovado' and c.renovado_a_id = v_contrato_nuevo
         and c.cerrado_por = '7fc10000-0000-4000-8000-000000000001'
     )
     or (select count(*) from public.cronograma_pagos
         where contrato_id = '7fc30000-0000-4000-8000-000000000001'
           and estado = 'trasladado') <> 2
     or (select count(*) from public.cronograma_pagos
         where contrato_id = '7fc30000-0000-4000-8000-000000000001'
           and estado = 'pagado') <> 1 then
    raise exception 'GCAR-C08: cierre, enlace o traslado de cuotas incorrecto';
  end if;

  -- El origen ya renovado no puede reutilizarse.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_fallo := false;
  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'numero_contrato', 'GCAR-RENOVACION-DUPLICADA',
        'cliente_id', '7fc20000-0000-4000-8000-000000000001',
        'capital', 1000, 'moneda', 'PEN', 'tasa_anual', 15,
        'modalidad', 'mensual', 'tipo_interes', 'simple',
        'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
        'categoria', 'renovacion',
        'contrato_origen_id', '7fc30000-0000-4000-8000-000000000001',
        'capital_renovado', 1000, 'capital_adicional', 0
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
        'monto_programado', 100, 'tipo', 'cuota'
      ))
    );
  exception when sqlstate 'P0409' then
    v_fallo := true;
  end;
  if not v_fallo then
    raise exception 'GCAR-C09: permitió renovar dos veces el mismo origen';
  end if;

  -- Dos upgrades del mismo cliente histórico son operaciones distintas, pero
  -- solo una conversión cliente-periodo. El primero es USD y el segundo PEN.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_respuesta := public.crear_contrato(
    jsonb_build_object(
      'numero_contrato', 'GCAR-UPGRADE-HISTORICO-USD',
      'cliente_id', '7fc20000-0000-4000-8000-000000000003',
      'capital', 2500, 'moneda', 'USD', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
      'categoria', 'upgrade'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
      'monto_programado', 100, 'tipo', 'cuota'
    ))
  );
  if coalesce((v_respuesta->>'conversion_elegible')::boolean, false) is not true then
    raise exception 'GCAR-C10: el upgrade histórico USD no quedó elegible';
  end if;

  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_respuesta := public.crear_contrato(
    jsonb_build_object(
      'numero_contrato', 'GCAR-UPGRADE-HISTORICO-PEN',
      'cliente_id', '7fc20000-0000-4000-8000-000000000003',
      'capital', 1800, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
      'categoria', 'upgrade'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
      'monto_programado', 100, 'tipo', 'cuota'
    ))
  );
  if coalesce((v_respuesta->>'conversion_elegible')::boolean, false) is not true then
    raise exception 'GCAR-C11: el segundo upgrade histórico no quedó elegible';
  end if;

  -- Si el primer contrato del cliente se etiqueta como upgrade, se registra la
  -- operación para trazabilidad, pero no suma conversión en ese mismo mes.
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  v_respuesta := public.crear_contrato(
    jsonb_build_object(
      'numero_contrato', 'GCAR-UPGRADE-PRIMER-MES',
      'cliente_id', '7fc20000-0000-4000-8000-000000000004',
      'capital', 2000, 'moneda', 'PEN', 'tasa_anual', 15,
      'modalidad', 'mensual', 'tipo_interes', 'simple',
      'fecha_inicio', v_hoy, 'fecha_vencimiento', v_hoy + 365,
      'categoria', 'upgrade'
    ),
    jsonb_build_array(jsonb_build_object(
      'numero_cuota', 1, 'fecha_programada', v_hoy + 30,
      'monto_programado', 100, 'tipo', 'cuota'
    ))
  );
  if (v_respuesta->>'conversion_elegible')::boolean is not false then
    raise exception 'GCAR-C12: el upgrade del primer mes contó como conversión';
  end if;

  select * into v_metricas
  from private.metricas_cartera_por_vendedor(v_periodo)
  where vendedor_id = '7fc10000-0000-4000-8000-000000000002';

  if v_metricas.vendedor_id is null
     or v_metricas.conversiones_clientes is distinct from 2
     or v_metricas.conversiones_renovacion is distinct from 1
     or v_metricas.conversiones_upgrade is distinct from 1
     or v_metricas.operaciones_renovacion is distinct from 1
     or v_metricas.operaciones_upgrade is distinct from 3
     or v_metricas.capital_renovado_pen is distinct from 800::numeric
     or v_metricas.capital_adicional_pen is distinct from 300::numeric
     or v_metricas.capital_renovado_usd is distinct from 0::numeric
     or v_metricas.capital_adicional_usd is distinct from 0::numeric
     or v_metricas.renovaciones_sin_desglose is distinct from 0 then
    raise exception 'GCAR-C13: métricas, deduplicación o monedas inesperadas: %',
      row_to_json(v_metricas);
  end if;
end;
$reglas$;

-- Fuerza ahora los constraints diferidos: una renovación/upgrade sin ledger no
-- podría esconderse detrás del ROLLBACK final.
set constraints all immediate;

select 'CREAR_CONTRATO_CARTERA_OK' as resultado;

rollback;
