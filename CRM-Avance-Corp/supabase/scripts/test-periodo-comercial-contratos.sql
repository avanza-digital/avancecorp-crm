-- Gate transaccional del periodo comercial de contratos.
-- Requiere la migracion crm_periodo_comercial_contratos aplicada. Toda fila de
-- prueba, snapshot de producto y auditoria se revierte al terminar.

begin;

set local lock_timeout = '10s';

do $estructura$
declare
  v_def text;
begin
  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'contratos'
      and c.column_name = 'fecha_cierre_comercial'
      and c.data_type = 'date'
      and c.is_nullable = 'NO'
      and c.column_default is null
  ) then
    raise exception 'PCOM-01: fecha_cierre_comercial no es DATE NOT NULL sin default';
  end if;

  if not exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = 'contratos'
      and c.column_name = 'fuente_cierre_comercial'
      and c.data_type = 'text'
      and c.is_nullable = 'NO'
      and c.column_default like '%registro%'
  ) then
    raise exception 'PCOM-02: fuente_cierre_comercial no tiene el contrato esperado';
  end if;

  if exists (
    select 1
    from public.contratos c
    where c.fecha_cierre_comercial is null
       or not isfinite(c.fecha_cierre_comercial)
       or (
         c.fuente_cierre_comercial = 'migracion_inferida'
         and c.fecha_cierre_comercial is distinct from least(
           c.fecha_inicio,
           (c.creado_en at time zone 'America/Lima')::date
         )
       )
  ) then
    raise exception 'PCOM-03: el historico inferido no conserva la regla universal';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_indexes i
    where i.schemaname = 'public'
      and i.tablename = 'contratos'
      and i.indexname = 'idx_contratos_fecha_cierre_comercial'
  ) then
    raise exception 'PCOM-04: falta el indice comercial';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.contratos'::regclass
      and t.tgname = 'trg_definir_periodo_comercial_contrato'
      and not t.tgisinternal
      and t.tgenabled <> 'D'
  ) then
    raise exception 'PCOM-05: falta el trigger de altas';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure
  );
  if v_def not ilike '%fecha_cierre_comercial%'
     or position('where c.creado_en>=p_ini and c.creado_en<p_fin' in v_def) > 0 then
    raise exception 'PCOM-06: la produccion por vendedor conserva el reloj tecnico';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'crm.metricas_capital_mes_fn(integer)'::regprocedure
  );
  if v_def not ilike '%fecha_cierre_comercial%'
     or v_def ilike '%c.fecha_inicio%' then
    raise exception 'PCOM-07: capital mensual no consume la fecha comercial';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'private.metricas_conversiones_implementacion(date,date)'::regprocedure
  );
  if v_def not ilike '%fecha_cierre_comercial%'
     or position('c.creado_en >= v_ini and c.creado_en < v_fin' in v_def) > 0
     or position('ct.creado_en >= v_ini and ct.creado_en < v_fin' in v_def) > 0 then
    raise exception 'PCOM-08: conversiones conserva una ventana tecnica de contratos';
  end if;

  v_def := pg_catalog.pg_get_functiondef('public.metricas_directorio()'::regprocedure);
  if v_def not ilike '%fecha_cierre_comercial%'
     or v_def ilike '%fecha_inicio%' then
    raise exception 'PCOM-09: directorio no consume exclusivamente la fecha comercial';
  end if;

  if to_regprocedure('crm.contratos_por_periodo_comercial_fn(date)') is null
     or to_regprocedure(
       'crm.corregir_fecha_cierre_comercial(uuid,date,text)'
     ) is null then
    raise exception 'PCOM-10: faltan las RPC comerciales';
  end if;

  if pg_catalog.has_function_privilege(
       'anon', 'crm.contratos_por_periodo_comercial_fn(date)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon',
       'crm.corregir_fecha_cierre_comercial(uuid,date,text)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.contratos_por_periodo_comercial_fn(date)',
       'EXECUTE'
     )
     or not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.corregir_fecha_cierre_comercial(uuid,date,text)',
       'EXECUTE'
     ) then
    raise exception 'PCOM-11: los permisos de las RPC no son los esperados';
  end if;
end;
$estructura$;

do $comportamiento$
declare
  v_gerencia uuid;
  v_src public.contratos%rowtype;
  v_enero jsonb;
  v_febrero jsonb;
  v_respuesta jsonb;
  v_id_enero constant uuid := '7f100000-0000-4000-8000-000000000001';
  v_id_febrero constant uuid := '7f100000-0000-4000-8000-000000000002';
  v_id_sellado constant uuid := '7f100000-0000-4000-8000-000000000003';
  v_id_explicito constant uuid := '7f100000-0000-4000-8000-000000000004';
begin
  select e.perfil_id
    into v_gerencia
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'gerencia'
    and e.activo
    and p.activo
  order by e.perfil_id
  limit 1;

  select c.*
    into v_src
  from public.contratos c
  where c.cliente_id is not null
  order by c.creado_en, c.id
  limit 1;

  if v_gerencia is null or v_src.id is null then
    raise exception 'PCOM-12: el gate necesita Gerencia y un contrato fuente';
  end if;

  if exists (
    select 1 from public.contratos c
    where c.fecha_cierre_comercial >= date '1901-01-01'
      and c.fecha_cierre_comercial < date '1901-03-01'
  ) then
    raise exception 'PCOM-13: los meses centinela ya contienen contratos';
  end if;

  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_gerencia::text, true);

  insert into public.contratos (
    id, cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, estado, notas_internas,
    creado_por, creado_en, categoria
  ) values (
    v_id_enero, v_src.cliente_id, 'TEST-PCOM-190101', v_src.capital,
    v_src.moneda, v_src.tasa_anual, v_src.modalidad, v_src.tipo_interes,
    date '1901-01-31', date '1902-01-31', 'activo',
    'Fixture transaccional del periodo comercial',
    coalesce(v_src.creado_por, v_gerencia),
    timestamptz '2026-08-15 12:00:00-05', v_src.categoria
  );

  insert into public.contratos (
    id, cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
    tipo_interes, fecha_inicio, fecha_vencimiento, estado, notas_internas,
    creado_por, creado_en, categoria
  ) values (
    v_id_febrero, v_src.cliente_id, 'TEST-PCOM-190201', v_src.capital,
    v_src.moneda, v_src.tasa_anual, v_src.modalidad, v_src.tipo_interes,
    date '1901-02-01', date '1902-02-01', 'activo',
    'Fixture transaccional del periodo comercial',
    coalesce(v_src.creado_por, v_gerencia),
    timestamptz '2026-08-15 12:00:00-05', v_src.categoria
  );

  if not exists (
    select 1
    from public.contratos c
    where c.id = v_id_enero
      and c.fecha_cierre_comercial = date '1901-01-31'
      and c.fuente_cierre_comercial = 'fecha_inicio_inferida'
  ) or not exists (
    select 1
    from public.contratos c
    where c.id = v_id_febrero
      and c.fecha_cierre_comercial = date '1901-02-01'
      and c.fuente_cierre_comercial = 'fecha_inicio_inferida'
  ) then
    raise exception 'PCOM-14: un alta tardia no fue inferida por fecha_inicio';
  end if;

  begin
    insert into public.contratos (
      id, cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
      tipo_interes, fecha_inicio, fecha_vencimiento, estado, notas_internas,
      creado_por, creado_en, categoria, fecha_cierre_comercial
    ) values (
      v_id_explicito, v_src.cliente_id, 'TEST-PCOM-EXPLICITO', v_src.capital,
      v_src.moneda, v_src.tasa_anual, v_src.modalidad, v_src.tipo_interes,
      date '1901-03-01', date '1902-03-01', 'activo',
      'Una alta no puede imponer el periodo comercial',
      coalesce(v_src.creado_por, v_gerencia),
      timestamptz '2026-08-15 12:00:00-05', v_src.categoria,
      date '1901-01-30'
    );
    raise exception 'PCOM-14a: se acepto una fecha comercial explicita en el alta';
  exception when insufficient_privilege then
    null;
  end;

  begin
    update public.contratos
       set fecha_cierre_comercial = date '1901-01-30'
     where id = v_id_enero;
    raise exception 'PCOM-14b: se acepto una correccion directa sin motivo';
  exception when insufficient_privilege then
    null;
  end;

  v_enero := crm.contratos_por_periodo_comercial_fn(date '1901-01-01');
  v_febrero := crm.contratos_por_periodo_comercial_fn(date '1901-02-01');

  if (v_enero #>> '{totales,contratos}')::integer <> 1
     or not exists (
       select 1 from jsonb_array_elements(v_enero->'contratos') j
       where (j->>'id')::uuid = v_id_enero
     )
     or exists (
       select 1 from jsonb_array_elements(v_enero->'contratos') j
       where (j->>'id')::uuid = v_id_febrero
     ) then
    raise exception 'PCOM-15: el limite superior de enero es incorrecto';
  end if;

  if (v_febrero #>> '{totales,contratos}')::integer <> 1
     or not exists (
       select 1 from jsonb_array_elements(v_febrero->'contratos') j
       where (j->>'id')::uuid = v_id_febrero
     )
     or exists (
       select 1 from jsonb_array_elements(v_febrero->'contratos') j
       where (j->>'id')::uuid = v_id_enero
     ) then
    raise exception 'PCOM-16: el limite inferior de febrero es incorrecto';
  end if;

  begin
    perform crm.contratos_por_periodo_comercial_fn(date '1901-01-15');
    raise exception 'PCOM-17: se acepto un periodo que no inicia el mes';
  exception when invalid_parameter_value then
    null;
  end;

  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  begin
    perform crm.contratos_por_periodo_comercial_fn(date '1901-01-01');
    raise exception 'PCOM-18: una identidad sin rol leyo el reporte global';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform crm.corregir_fecha_cierre_comercial(
      v_id_enero, date '1901-01-30', 'Sin autoridad comercial'
    );
    raise exception 'PCOM-18b: una identidad sin rol corrigio un contrato';
  exception when insufficient_privilege then
    null;
  end;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_gerencia::text, true);
  v_respuesta := crm.corregir_fecha_cierre_comercial(
    v_id_enero,
    date '1901-02-02',
    'Correccion transaccional del gate PCOM'
  );

  if not coalesce((v_respuesta->>'ok')::boolean, false)
     or not coalesce((v_respuesta->>'cambio')::boolean, false)
     or not exists (
       select 1
       from public.contratos c
       where c.id = v_id_enero
         and c.fecha_cierre_comercial = date '1901-02-02'
         and c.fuente_cierre_comercial = 'correccion_manual'
     )
     or not exists (
       select 1
       from public.audit_log a
       where a.tabla = 'contratos.fecha_cierre_comercial'
         and a.operacion = 'UPDATE'
         and a.fila_id = v_id_enero::text
         and a.data_despues->>'motivo' = 'Correccion transaccional del gate PCOM'
     ) then
    raise exception 'PCOM-19: la correccion o su auditoria no quedaron completas';
  end if;

  v_enero := crm.contratos_por_periodo_comercial_fn(date '1901-01-01');
  v_febrero := crm.contratos_por_periodo_comercial_fn(date '1901-02-01');
  if (v_enero #>> '{totales,contratos}')::integer <> 0
     or (v_febrero #>> '{totales,contratos}')::integer <> 2 then
    raise exception 'PCOM-20: corregir no movio el contrato entre meses';
  end if;

  begin
    perform crm.corregir_fecha_cierre_comercial(
      v_id_enero, date '1901-02-03', 'x'
    );
    raise exception 'PCOM-20b: se acepto un motivo demasiado corto';
  exception when invalid_parameter_value then
    null;
  end;

  begin
    perform crm.corregir_fecha_cierre_comercial(
      v_id_enero,
      ((clock_timestamp() at time zone 'America/Lima')::date + 1),
      'Esta fecha futura debe rechazarse'
    );
    raise exception 'PCOM-21: se acepto una fecha futura';
  exception when invalid_parameter_value then
    null;
  end;

  insert into crm.periodos_cerrados (
    periodo, automatico, ponderacion_referido, meta_revision, cobertura
  ) values (
    date '1901-01-01', true, 0.15, 1,
    jsonb_build_object('fixture', 'PCOM')
  );

  begin
    insert into public.contratos (
      id, cliente_id, numero_contrato, capital, moneda, tasa_anual, modalidad,
      tipo_interes, fecha_inicio, fecha_vencimiento, estado, notas_internas,
      creado_por, creado_en, categoria
    ) values (
      v_id_sellado, v_src.cliente_id, 'TEST-PCOM-SELLADO', v_src.capital,
      v_src.moneda, v_src.tasa_anual, v_src.modalidad, v_src.tipo_interes,
      date '1901-01-15', date '1902-01-15', 'activo',
      'Este contrato debe rechazarse por mes sellado',
      coalesce(v_src.creado_por, v_gerencia),
      timestamptz '2026-08-15 12:00:00-05', v_src.categoria
    );
    raise exception 'PCOM-22: se inserto un contrato en un mes sellado';
  exception when sqlstate 'P0409' then
    null;
  end;

  begin
    perform crm.corregir_fecha_cierre_comercial(
      v_id_enero,
      date '1901-01-31',
      'El destino sellado debe rechazar la correccion'
    );
    raise exception 'PCOM-23: se movio un contrato hacia un mes sellado';
  exception when sqlstate 'P0409' then
    null;
  end;
end;
$comportamiento$;

-- Ejecutar, no solo inspeccionar, los cuatro consumidores recompilados. Esto
-- detecta errores que PL/pgSQL puede diferir hasta la primera llamada real.
do $consumidores$
declare
  v_gerencia uuid;
  v_directorio uuid;
  v_meta_id uuid;
  v_periodo date;
begin
  select e.perfil_id into v_gerencia
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'gerencia' and e.activo and p.activo
  order by e.perfil_id limit 1;

  select p.id into v_directorio
  from public.perfiles p
  where p.rol = 'directorio' and p.activo
  order by p.id limit 1;

  select mp.id, mp.periodo into v_meta_id, v_periodo
  from crm.meta_periodos mp
  order by mp.periodo desc, mp.revision desc
  limit 1;

  if v_gerencia is null or v_directorio is null then
    raise exception 'PCOM-24: faltan identidades para ejecutar consumidores';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub', v_gerencia::text, true);
  perform crm.metricas_capital_mes_fn(12);
  perform private.metricas_conversiones_implementacion(
    date '2026-01-01', date '2026-08-24'
  );
  perform count(*)
  from private.produccion_mes_por_vendedor(
    (coalesce(v_periodo, date '2026-07-01')::timestamp
      at time zone 'America/Lima'),
    ((coalesce(v_periodo, date '2026-07-01') + interval '1 month')::timestamp
      at time zone 'America/Lima'),
    v_meta_id
  );

  perform pg_catalog.set_config('request.jwt.claim.sub', v_directorio::text, true);
  perform public.metricas_directorio();
end;
$consumidores$;

rollback;

select 'PERIODO_COMERCIAL_CONTRATOS_OK' as resultado;
