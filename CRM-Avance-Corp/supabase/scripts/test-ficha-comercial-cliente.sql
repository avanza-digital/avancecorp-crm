-- Oráculo transaccional de la ficha comercial del cliente.
-- Requiere 20260825214823_crm_ficha_comercial_cliente_scope.sql.
-- Éxito = FICHA_CLIENTE_SCOPE_TX_OK; todo termina en ROLLBACK.

\set ON_ERROR_STOP on

begin;

do $estructura$
declare
  v_expuesta pg_catalog.pg_proc%rowtype;
  v_privada pg_catalog.pg_proc%rowtype;
  v_alcance pg_catalog.pg_proc%rowtype;
  v_capacidad pg_catalog.pg_proc%rowtype;
  v_crear pg_catalog.pg_proc%rowtype;
  v_actualizar pg_catalog.pg_proc%rowtype;
  v_alta_pdf pg_catalog.pg_proc%rowtype;
  v_correccion_pdf pg_catalog.pg_proc%rowtype;
begin
  if to_regprocedure('crm.cliente_ficha_fn(uuid)') is null
     or to_regprocedure('private.cliente_ficha_autorizada_fn(uuid)') is null
     or to_regprocedure('private.puede_consultar_cliente_fn(uuid)') is null
     or to_regprocedure('private.puede_consultar_cuentas_cliente_fn(uuid)') is null
     or to_regprocedure('private.puede_gestionar_cuentas_cliente(uuid)') is null
     or to_regprocedure(
       'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)'
     ) is null
     or to_regprocedure('public.crear_contrato(jsonb,jsonb)') is null
     or to_regprocedure('public.actualizar_contrato(uuid,jsonb,jsonb)') is null
     or to_regprocedure(
       'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
     ) is null
     or to_regprocedure(
       'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'
     ) is null
     or to_regclass(
       'private.contrato_escritura_atomica_capacidades'
     ) is null then
    raise exception 'FICHA-01: faltan las funciones de la ficha comercial';
  end if;

  select p.* into v_expuesta
  from pg_catalog.pg_proc p
  where p.oid = 'crm.cliente_ficha_fn(uuid)'::regprocedure;

  select p.* into v_privada
  from pg_catalog.pg_proc p
  where p.oid = 'private.cliente_ficha_autorizada_fn(uuid)'::regprocedure;

  select p.* into v_alcance
  from pg_catalog.pg_proc p
  where p.oid = 'private.puede_consultar_cliente_fn(uuid)'::regprocedure;

  select p.* into v_capacidad
  from pg_catalog.pg_proc p
  where p.oid =
    'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)'::regprocedure;

  select p.* into v_crear
  from pg_catalog.pg_proc p
  where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure;

  select p.* into v_actualizar
  from pg_catalog.pg_proc p
  where p.oid = 'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure;

  select p.* into v_alta_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure;

  select p.* into v_correccion_pdf
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb,timestamptz)'::regprocedure;

  if v_expuesta.prosecdef
     or v_expuesta.provolatile <> 's'
     or not (v_expuesta.proconfig @> array['search_path=""']) then
    raise exception 'FICHA-02: la RPC expuesta no conserva invoker/stable/search_path vacío';
  end if;

  if not v_privada.prosecdef
     or v_privada.provolatile <> 's'
     or not (v_privada.proconfig @> array['search_path=""']) then
    raise exception 'FICHA-03: el helper privado no conserva definer/stable/search_path vacío';
  end if;

  if not v_alcance.prosecdef
     or v_alcance.provolatile <> 's'
     or not (v_alcance.proconfig @> array['search_path=""']) then
    raise exception 'FICHA-03B: el helper de alcance no conserva definer/stable/search_path vacío';
  end if;

  if not v_capacidad.prosecdef
     or v_capacidad.provolatile <> 'v'
     or not (v_capacidad.proconfig @> array['search_path=""'])
     or pg_catalog.has_function_privilege(
       'authenticated',
       'private.tiene_capacidad_contrato_atomico(text,uuid,uuid)',
       'EXECUTE'
     )
     or pg_catalog.has_table_privilege(
       'authenticated',
       'private.contrato_escritura_atomica_capacidades',
       'SELECT,INSERT,UPDATE,DELETE'
     ) then
    raise exception 'FICHA-03C: la capacidad atómica no quedó privada y transaccional';
  end if;

  if not v_crear.prosecdef
     or v_crear.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_crear.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or not v_actualizar.prosecdef
     or v_actualizar.prosrc not ilike '%tiene_capacidad_contrato_atomico%'
     or v_actualizar.prosrc not ilike '%puede_gestionar_cuentas_cliente%'
     or not v_alta_pdf.prosecdef
     or v_alta_pdf.prosrc not ilike '%contrato_escritura_atomica_capacidades%'
     or not v_correccion_pdf.prosecdef
     or v_correccion_pdf.prosrc not ilike '%contrato_escritura_atomica_capacidades%'
     or v_correccion_pdf.prosrc not ilike '%p_revision_esperada is null%'
     or v_correccion_pdf.prosrc not ilike '%for update%'
     or v_correccion_pdf.pronargdefaults <> 1 then
    raise exception 'FICHA-03D: escritores o wrappers perdieron el gate atómico';
  end if;

  if to_regprocedure(
       'crm.actualizar_contrato_con_cuenta_pdf_v3(uuid,jsonb,jsonb)'
     ) is not null
     or to_regclass('crm.contratos_cartera') is null
     or not exists (
       select 1
       from information_schema.columns c
       where c.table_schema = 'crm'
         and c.table_name = 'contratos_cartera'
         and c.column_name = 'revision_contrato'
         and c.data_type = 'timestamp with time zone'
     )
     or not coalesce((
       select c.reloptions @> array['security_invoker=true']
       from pg_catalog.pg_class c
       where c.oid = 'crm.contratos_cartera'::regclass
     ), false) then
    raise exception 'FICHA-03F: la cartera no publicó el comprobante de vigencia con vista invoker';
  end if;

  if (
    select count(*)
    from pg_catalog.pg_proc p
    where p.prosrc ilike
      '%insert into private.contrato_escritura_atomica_capacidades%'
  ) <> 2 then
    raise exception 'FICHA-03E: una función distinta de los wrappers emite capacidades';
  end if;

  if not pg_catalog.has_function_privilege(
       'authenticated', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'anon', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     )
     or pg_catalog.has_function_privilege(
       'service_role', 'crm.cliente_ficha_fn(uuid)', 'EXECUTE'
     ) then
    raise exception 'FICHA-04: ACL inesperada en la RPC expuesta';
  end if;

  if exists (
    select 1
    from unnest(coalesce(v_expuesta.proargnames, '{}'::text[])) as salida(nombre)
    where salida.nombre like any (array[
      'banco%', 'tipo_cuenta%', 'numero_cuenta%', 'cci%',
      'titular_distinto%', 'beneficiario_nombre%', 'beneficiario_dni%',
      'domicilio', 'creado_por'
    ])
  ) then
    raise exception 'FICHA-05: la proyección publicó un campo bancario';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_policies p
    where p.schemaname = 'crm'
      and p.tablename = 'actividades_cliente'
      and p.policyname = 'actividades_cliente_select'
      and p.cmd = 'SELECT'
      and p.roles = array['authenticated']::name[]
  ) then
    raise exception 'FICHA-05B: el historial no usa el alcance actual del cliente';
  end if;
end;
$estructura$;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('f4100000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ficha-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ficha-vendedor-a@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ficha-vendedor-b@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ficha-gerencia@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'ficha-directorio@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'ficha-coordinador@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'ficha-revocado@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000008', 'authenticated', 'authenticated', 'ficha-ajeno@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000009', 'authenticated', 'authenticated', 'ficha-sup-b@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000101', 'authenticated', 'authenticated', 'ficha-cliente-a@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000102', 'authenticated', 'authenticated', 'ficha-cliente-b@test.invalid', now(), '{}', '{}', now(), now()),
  ('f4100000-0000-4000-8000-000000000103', 'authenticated', 'authenticated', 'ficha-cliente-sin-asesor@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (
  id, nombre_completo, nombres, apellidos, correo, rol, activo, domicilio,
  asesor_perfil_id, creado_por
)
values
  ('f4100000-0000-4000-8000-000000000001', 'Ficha Supervisor', 'Ficha', 'Supervisor', 'ficha-sup@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000002', 'Ficha Vendedor A', 'Ficha', 'Vendedor A', 'ficha-vendedor-a@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000003', 'Ficha Vendedor B', 'Ficha', 'Vendedor B', 'ficha-vendedor-b@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000004', 'Ficha Gerencia', 'Ficha', 'Gerencia', 'ficha-gerencia@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000005', 'Ficha Directorio', 'Ficha', 'Directorio', 'ficha-directorio@test.invalid', 'directorio', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000006', 'Ficha Coordinador', 'Ficha', 'Coordinador', 'ficha-coordinador@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000007', 'Ficha Revocado', 'Ficha', 'Revocado', 'ficha-revocado@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000008', 'Ficha Ajeno', 'Ficha', 'Ajeno', 'ficha-ajeno@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000009', 'Ficha Supervisor B', 'Ficha', 'Supervisor B', 'ficha-sup-b@test.invalid', 'comercial', true, null, null, null),
  ('f4100000-0000-4000-8000-000000000101', 'Cliente Ficha A', 'Cliente', 'Ficha A', 'ficha-cliente-a@test.invalid', 'cliente', true, 'Av. Alcance 101', 'f4100000-0000-4000-8000-000000000002', 'f4100000-0000-4000-8000-000000000002'),
  ('f4100000-0000-4000-8000-000000000102', 'Cliente Ficha B', 'Cliente', 'Ficha B', 'ficha-cliente-b@test.invalid', 'cliente', true, 'Av. Alcance 102', 'f4100000-0000-4000-8000-000000000003', 'f4100000-0000-4000-8000-000000000003'),
  ('f4100000-0000-4000-8000-000000000103', 'Cliente Ficha Sin Asesor', 'Cliente', 'Ficha Sin Asesor', 'ficha-cliente-sin-asesor@test.invalid', 'cliente', true, 'Av. Alcance 103', null, 'f4100000-0000-4000-8000-000000000002');

-- El alta PDF necesita los datos legales del titular y del responsable que
-- confirma la inversión. Solo se completan los tres perfiles usados por los
-- positivos atómicos del oráculo.
update public.perfiles
set tipo_documento = 'DNI',
    dni = case id
      when 'f4100000-0000-4000-8000-000000000001'::uuid then '71000001'
      when 'f4100000-0000-4000-8000-000000000002'::uuid then '71000002'
      else '71000101'
    end,
    telefono = case id
      when 'f4100000-0000-4000-8000-000000000001'::uuid then '987000001'
      when 'f4100000-0000-4000-8000-000000000002'::uuid then '987000002'
      else '987000101'
    end
where id in (
  'f4100000-0000-4000-8000-000000000001',
  'f4100000-0000-4000-8000-000000000002',
  'f4100000-0000-4000-8000-000000000101'
);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('f4100000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('f4100000-0000-4000-8000-000000000002', 'vendedor', 'f4100000-0000-4000-8000-000000000001', true),
  ('f4100000-0000-4000-8000-000000000009', 'supervisor', null, true),
  ('f4100000-0000-4000-8000-000000000003', 'vendedor', 'f4100000-0000-4000-8000-000000000009', true),
  ('f4100000-0000-4000-8000-000000000004', 'gerencia', null, true),
  ('f4100000-0000-4000-8000-000000000005', 'directorio', null, true),
  ('f4100000-0000-4000-8000-000000000006', 'coordinador', null, true),
  ('f4100000-0000-4000-8000-000000000007', 'vendedor', 'f4100000-0000-4000-8000-000000000009', false);

-- El vendedor histórico se invierte a propósito: la lectura debe seguir al
-- asesor ACTUAL del cliente, no a quien registró la gestión en el pasado.
insert into crm.actividades_cliente (
  id, cliente_id, vendedor_id, tipo, detalle, creado_por
)
values
  ('f4110000-0000-4000-8000-000000000101', 'f4100000-0000-4000-8000-000000000101', 'f4100000-0000-4000-8000-000000000003', 'nota', 'Historial del cliente A', 'f4100000-0000-4000-8000-000000000003'),
  ('f4110000-0000-4000-8000-000000000102', 'f4100000-0000-4000-8000-000000000102', 'f4100000-0000-4000-8000-000000000002', 'nota', 'Historial del cliente B', 'f4100000-0000-4000-8000-000000000002');

-- Dos contratos con el mismo creador: uno pertenece al cliente actualmente
-- asignado y el otro a un cliente que quedó sin asesor. El segundo no debe
-- aparecer por haber sido creado por el vendedor A.
set local session_replication_role = replica;

insert into crm.productos_inversion (
  id, codigo, estado, revision, es_legacy, permite_altas_legacy
) values (
  'f4120000-0000-4000-8000-000000000001', 'FICHA-ORACULO', 'activo', 1, false, false
);

insert into crm.producto_versiones (
  id, producto_id, numero_version, estado, nombre, vigente_desde,
  revision, publicada_en
) values (
  'f4130000-0000-4000-8000-000000000001',
  'f4120000-0000-4000-8000-000000000001',
  1, 'publicada', 'Opción comercial de prueba', current_date, 1, now()
);

insert into crm.producto_condiciones (
  id, version_id, orden, categoria, moneda, plazo_meses, modalidad,
  tipo_interes, capital_minimo, capital_maximo, tasa_referencia,
  tasa_minima, tasa_maxima, activa, es_legacy
) values (
  'f4140000-0000-4000-8000-000000000001',
  'f4130000-0000-4000-8000-000000000001',
  1, 'nuevo', 'PEN', 12, 'mensual', 'simple',
  1000, 100000, 12, 10, 15, true, false
);

insert into public.contratos (
  id, numero_contrato, cliente_id, capital, moneda, tasa_anual,
  modalidad, tipo_interes, categoria, estado, fecha_inicio,
  fecha_vencimiento, creado_por, producto_condicion_id,
  fecha_cierre_comercial, fuente_cierre_comercial
) values
  (
    'f4150000-0000-4000-8000-000000000101', 'FICHA-ASIGNADO',
    'f4100000-0000-4000-8000-000000000101', 10000, 'PEN', 12,
    'mensual', 'simple', 'nuevo', 'activo', current_date,
    current_date + 365, 'f4100000-0000-4000-8000-000000000002',
    'f4140000-0000-4000-8000-000000000001', current_date, 'registro'
  ),
  (
    'f4150000-0000-4000-8000-000000000103', 'FICHA-SIN-ASESOR',
    'f4100000-0000-4000-8000-000000000103', 15000, 'PEN', 12,
    'mensual', 'simple', 'nuevo', 'activo', current_date,
    current_date + 365, 'f4100000-0000-4000-8000-000000000002',
    'f4140000-0000-4000-8000-000000000001', current_date, 'registro'
  );

insert into public.cronograma_pagos (
  id, contrato_id, numero_cuota, fecha_programada, monto_programado,
  estado, tipo
) values
  (
    'f4160000-0000-4000-8000-000000000101',
    'f4150000-0000-4000-8000-000000000101', 1,
    current_date + 30, 100, 'pendiente', 'cuota'
  ),
  (
    'f4160000-0000-4000-8000-000000000103',
    'f4150000-0000-4000-8000-000000000103', 1,
    current_date + 30, 150, 'pendiente', 'cuota'
  );

insert into public.contrato_titulares (
  id, contrato_id, orden, nombre_completo, tipo_documento, documento
) values
  (
    'f4170000-0000-4000-8000-000000000101',
    'f4150000-0000-4000-8000-000000000101', 1,
    'Cotitular asignado', 'DNI', '70000001'
  ),
  (
    'f4170000-0000-4000-8000-000000000103',
    'f4150000-0000-4000-8000-000000000103', 1,
    'Cotitular sin asesor', 'DNI', '70000003'
  );

insert into crm.cuentas_bancarias (
  id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci,
  titular_distinto, activa, origen, creado_por
) values
  (
    'f4180000-0000-4000-8000-000000000101',
    'f4100000-0000-4000-8000-000000000101', 'PEN', 'BANCO FICHA A',
    'ahorros', '19100000000101', '00219100000000000101', false,
    true, 'contrato', 'f4100000-0000-4000-8000-000000000002'
  ),
  (
    'f4180000-0000-4000-8000-000000000103',
    'f4100000-0000-4000-8000-000000000103', 'PEN', 'BANCO SIN ASESOR',
    'ahorros', '19100000000103', '00219100000000000103', false,
    true, 'contrato', 'f4100000-0000-4000-8000-000000000002'
  );

insert into crm.operaciones_cartera (
  id, cliente_id, vendedor_id, tipo, contrato_nuevo_id,
  fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
  elegible_conversion, desglose_completo, fuente, creado_por
) values (
  'f4190000-0000-4000-8000-000000000101',
  'f4100000-0000-4000-8000-000000000101',
  'f4100000-0000-4000-8000-000000000002',
  'upgrade', 'f4150000-0000-4000-8000-000000000101',
  current_date, date_trunc('month', current_date)::date, 'PEN',
  null, null, true, true, 'flujo_cartera',
  'f4100000-0000-4000-8000-000000000002'
);

set local session_replication_role = origin;

-- Vendedor A: ve solo el cliente que tiene asignado. Ser creador de un cliente
-- sin asesor no amplía la lectura de la ficha.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $vendedor$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1 then
    raise exception 'FICHA-06: el vendedor no ve a su cliente asignado';
  end if;
  if (select correo from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101'))
       is distinct from 'ficha-cliente-a@test.invalid' then
    raise exception 'FICHA-07: la ficha propia no devolvió el contacto esperado';
  end if;
  if exists (select 1 from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000102'))
     or exists (select 1 from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000103'))
     or exists (select 1 from crm.cliente_ficha_fn('ffffffff-ffff-4fff-8fff-ffffffffffff')) then
    raise exception 'FICHA-08: el vendedor distinguió un cliente ajeno, sin asesor o inexistente';
  end if;
  if (select count(*) from crm.actividades_cliente where cliente_id = 'f4100000-0000-4000-8000-000000000101') <> 1
     or exists (
       select 1 from crm.actividades_cliente
       where cliente_id = 'f4100000-0000-4000-8000-000000000102'
     ) then
    raise exception 'FICHA-08B: el historial no siguió la asignación actual del vendedor A';
  end if;
  if not exists (
       select 1 from crm.contratos_cartera_fn()
       where id = 'f4150000-0000-4000-8000-000000000101'
     )
     or exists (
       select 1 from crm.contratos_cartera_fn()
       where id = 'f4150000-0000-4000-8000-000000000103'
     ) then
    raise exception 'FICHA-08D: los contratos no siguen exclusivamente la asignación actual';
  end if;
  if not public.puede_ver_contrato('f4150000-0000-4000-8000-000000000101')
     or public.puede_ver_contrato('f4150000-0000-4000-8000-000000000103') then
    raise exception 'FICHA-08E: el detalle contractual conservó el permiso por creador';
  end if;
  if (select count(*) from crm.cronograma_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or exists (
       select 1 from crm.cronograma_contrato_fn('f4150000-0000-4000-8000-000000000103')
     )
     or (select count(*) from crm.titulares_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or exists (
       select 1 from crm.titulares_contrato_fn('f4150000-0000-4000-8000-000000000103')
     ) then
    raise exception 'FICHA-08F: cronograma o co-titulares conservaron datos fuera de cartera';
  end if;
  if (select count(*) from crm.cuentas_bancarias_cliente_fn(
       'f4100000-0000-4000-8000-000000000101', 'PEN'
     )) <> 1 then
    raise exception 'FICHA-08G: el vendedor no recibió la cuenta de su cliente actual';
  end if;
  begin
    perform crm.cuentas_bancarias_cliente_fn(
      'f4100000-0000-4000-8000-000000000103', 'PEN'
    );
    raise exception 'FICHA-08H: el creador conservó banca de un cliente sin asesor';
  exception
    when insufficient_privilege then null;
  end;
  if (select count(*) from crm.operaciones_cartera where cliente_id = 'f4100000-0000-4000-8000-000000000101') <> 1
     or exists (
       select 1 from crm.operaciones_cartera
       where cliente_id <> 'f4100000-0000-4000-8000-000000000101'
     ) then
    raise exception 'FICHA-08I: los movimientos de inversión no siguieron la asignación actual';
  end if;
end;
$vendedor$;
reset role;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $vendedor_b$
begin
  if (select count(*) from crm.actividades_cliente where cliente_id = 'f4100000-0000-4000-8000-000000000102') <> 1
     or exists (
       select 1 from crm.actividades_cliente
       where cliente_id = 'f4100000-0000-4000-8000-000000000101'
     ) then
    raise exception 'FICHA-08C: el historial no siguió la asignación actual del vendedor B';
  end if;
end;
$vendedor_b$;
reset role;

-- Supervisor: hereda el cliente del vendedor A, no el del vendedor B.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $supervisor$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1
     or exists (select 1 from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000102'))
     or exists (select 1 from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000103')) then
    raise exception 'FICHA-09: el alcance del supervisor no coincide con su equipo';
  end if;
  if (select count(*) from crm.actividades_cliente) <> 1 then
    raise exception 'FICHA-09B: el historial del supervisor no coincide con su equipo';
  end if;
  if (select count(*) from crm.contratos_cartera_fn()) <> 1
     or (select count(*) from crm.operaciones_cartera) <> 1 then
    raise exception 'FICHA-09C: contratos o movimientos del supervisor no coinciden con su equipo';
  end if;
end;
$supervisor$;
reset role;

-- Si el asesor queda inactivo, su supervisor conserva la ficha, contratos,
-- documentos y banca para reasignar con contexto; ninguna ruta de inversión
-- puede operar hasta que exista un responsable activo.
set local session_replication_role = replica;
update crm.equipo
set activo = false
where perfil_id = 'f4100000-0000-4000-8000-000000000002';
set local session_replication_role = origin;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $supervisor_asesor_inactivo$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1
     or not exists (
       select 1 from crm.contratos_cartera_fn()
       where id = 'f4150000-0000-4000-8000-000000000101'
     )
     or (select count(*) from crm.cronograma_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.titulares_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.cuentas_bancarias_cliente_fn(
       'f4100000-0000-4000-8000-000000000101', 'PEN'
     )) <> 1 then
    raise exception 'FICHA-09D: el supervisor perdió contexto al desactivarse el asesor';
  end if;

  begin
    perform crm.crear_contrato_con_cuenta(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000101',
        'moneda', 'PEN'
      ),
      '[]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'FICHA-09E: el supervisor operó con un asesor inactivo';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000101',
        'moneda', 'PEN'
      ),
      '[]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'FICHA-09E2: la capacidad PDF ignoró al asesor inactivo';
  exception
    when insufficient_privilege then null;
  end;
end;
$supervisor_asesor_inactivo$;
reset role;

do $candado_operacion$
begin
  if private.puede_gestionar_cuentas_cliente('f4100000-0000-4000-8000-000000000101') then
    raise exception 'FICHA-09F: el candado de mutación aceptó un asesor inactivo';
  end if;
  if not private.puede_consultar_cuentas_cliente_fn('f4100000-0000-4000-8000-000000000101') then
    raise exception 'FICHA-09G: el candado de lectura bancaria bloqueó la reasignación pendiente';
  end if;
  if not private.puede_leer_contrato_pdf('f4150000-0000-4000-8000-000000000101') then
    raise exception 'FICHA-09H: el documento contractual quedó ligado al candado de mutación';
  end if;
end;
$candado_operacion$;

set local session_replication_role = replica;
update crm.equipo
set activo = true
where perfil_id = 'f4100000-0000-4000-8000-000000000002';
set local session_replication_role = origin;

-- P1 · Alta/corrección libre desde la ficha. Un perfil Portal `comercial`
-- que además es vendedor CRM activo solo entra por los wrappers PDF; la
-- llamada pública directa y un token fabricado siguen respondiendo 42501.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
select set_config('crm.producto_condicion_id', '', true);
select set_config(
  'crm.contrato_escritura_atomica_token',
  'f41f0000-0000-4000-8000-000000000001',
  true
);
set local role authenticated;
do $alta_directa_bloqueada$
begin
  if public.es_analista() or public.es_gestor_cartera() then
    raise exception 'FICHA-09I: el vendedor comercial heredó un poder Portal administrativo';
  end if;

  begin
    perform public.crear_contrato(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000101',
        'numero_contrato', 'FICHA-DIRECTO-BLOQUEADO',
        'capital', 11000,
        'moneda', 'PEN',
        'tasa_anual', 12,
        'modalidad', 'mensual',
        'tipo_interes', 'simple',
        'categoria', 'nuevo',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '1 year')::date
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1,
        'fecha_programada', current_date + 30,
        'monto_programado', 110,
        'tipo', 'cuota'
      ))
    );
    raise exception 'FICHA-09J: public.crear_contrato aceptó una llamada comercial directa';
  exception
    when sqlstate '42501' then null;
  end;
end;
$alta_directa_bloqueada$;

select set_config(
  'crm.contrato_escritura_atomica_token',
  'estado-previo-alta',
  true
);
select crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb_build_object(
    'cliente_id', 'f4100000-0000-4000-8000-000000000101',
    'numero_contrato', 'FICHA-ATOM-VENDEDOR',
    'capital', 11000,
    'moneda', 'PEN',
    'tasa_anual', 12,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '1 year')::date,
    'titulares', '[]'::jsonb
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date + 30,
    'monto_programado', 110,
    'tipo', 'cuota'
  )),
  jsonb_build_object(
    'tipo', 'existente',
    'cuenta_id', 'f4180000-0000-4000-8000-000000000101'
  )
)::text as alta_atomica_vendedor \gset

do $alta_restaura_capacidad$
begin
  if current_setting('crm.contrato_escritura_atomica_token', true)
       is distinct from 'estado-previo-alta' then
    raise exception 'FICHA-09K: el alta no restauró la capacidad previa';
  end if;
end;
$alta_restaura_capacidad$;
select set_config('crm.contrato_escritura_atomica_token', '', true);
reset role;

do $alta_atomica_vendedor_ok$
declare
  v_id uuid;
begin
  select c.id into v_id
  from public.contratos c
  where c.numero_contrato = 'FICHA-ATOM-VENDEDOR';

  if v_id is null
     or not exists (
       select 1
       from public.contratos c
       join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
       where c.id = v_id
         and c.creado_por = 'f4100000-0000-4000-8000-000000000002'
         and c.numero_contrato = 'FICHA-ATOM-VENDEDOR'
         and pc.es_legacy
         and pc.legacy_contrato_id = c.id
     )
     or (select count(*) from private.contrato_pdf_jobs j
         where j.contrato_id = v_id and j.revision = 1
           and j.estado = 'pendiente') <> 1
     or exists (
       select 1 from private.contrato_escritura_atomica_capacidades
     )
     or exists (
       select 1 from public.contratos
       where numero_contrato = 'FICHA-DIRECTO-BLOQUEADO'
     ) then
    raise exception 'FICHA-09L: el alta del vendedor no confirmó contrato, PDF y snapshot legacy exactos';
  end if;
end;
$alta_atomica_vendedor_ok$;

-- El oráculo completo corre en una sola transacción y now() es estable. Se
-- adelanta R0 un segundo sin ejecutar reglas de negocio para que la corrección
-- B produzca un token distinto, como ocurriría entre dos RPC reales.
set local session_replication_role = replica;
update public.contratos
set actualizado_en = now() - interval '1 second'
where numero_contrato = 'FICHA-ATOM-VENDEDOR';
set local session_replication_role = origin;

select revision_contrato::text as revision_inicial_vendedor
from crm.contratos_cartera
where numero_contrato = 'FICHA-ATOM-VENDEDOR'
\gset

-- La misma llamada pública de corrección queda cerrada. El wrapper v3 abre
-- solo este contrato, dentro de las cinco horas, y reserva la revisión 2.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
select set_config('crm.producto_condicion_id', '', true);
select set_config(
  'crm.contrato_escritura_atomica_token',
  'f41f0000-0000-4000-8000-000000000002',
  true
);
select set_config(
  'test.ficha_contrato_id',
  (select c.id::text from public.contratos c
   where c.numero_contrato = 'FICHA-ATOM-VENDEDOR'),
  true
);
set local role authenticated;
do $correccion_directa_bloqueada$
declare
  v_id uuid := current_setting('test.ficha_contrato_id', true)::uuid;
begin
  begin
    perform public.actualizar_contrato(
      v_id,
      jsonb_build_object(
        'numero_contrato', 'FICHA-ATOM-VENDEDOR',
        'capital', 12000,
        'moneda', 'PEN',
        'tasa_anual', 12.5,
        'modalidad', 'mensual',
        'tipo_interes', 'simple',
        'categoria', 'nuevo',
        'fecha_inicio', current_date,
        'fecha_vencimiento', (current_date + interval '1 year')::date,
        'notas_internas', 'Ajuste comercial validado'
      ),
      jsonb_build_array(jsonb_build_object(
        'numero_cuota', 1,
        'fecha_programada', current_date + 30,
        'monto_programado', 125,
        'tipo', 'cuota'
      ))
    );
    raise exception 'FICHA-09M: public.actualizar_contrato aceptó una llamada comercial directa';
  exception
    when sqlstate '42501' then null;
  end;
end;
$correccion_directa_bloqueada$;

select set_config(
  'crm.contrato_escritura_atomica_token',
  'estado-previo-correccion',
  true
);
select set_config(
  'crm.contrato_pdf_revision_autorizada',
  'estado-previo-revision',
  true
);
select crm.actualizar_contrato_con_cuenta_pdf_v3(
  (:'alta_atomica_vendedor'::jsonb->>'id')::uuid,
  jsonb_build_object(
    'numero_contrato', 'FICHA-ATOM-VENDEDOR',
    'capital', 12000,
    'moneda', 'PEN',
    'tasa_anual', 12.5,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '1 year')::date,
    'notas_internas', 'Ajuste comercial validado'
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date + 30,
    'monto_programado', 125,
    'tipo', 'cuota'
  )),
  :'revision_inicial_vendedor'::timestamptz
)::text as correccion_atomica_vendedor \gset

do $correccion_restaura_capacidad$
begin
  if current_setting('crm.contrato_escritura_atomica_token', true)
       is distinct from 'estado-previo-correccion'
     or current_setting('crm.contrato_pdf_revision_autorizada', true)
       is distinct from 'estado-previo-revision' then
    raise exception 'FICHA-09N: la corrección no restauró sus capacidades previas';
  end if;
end;
$correccion_restaura_capacidad$;
select set_config('crm.contrato_escritura_atomica_token', '', true);
select set_config('crm.contrato_pdf_revision_autorizada', '', true);
reset role;

do $correccion_atomica_vendedor_ok$
declare
  v_id uuid;
begin
  select c.id into v_id
  from public.contratos c
  where c.numero_contrato = 'FICHA-ATOM-VENDEDOR';

  if not exists (
       select 1
       from public.contratos c
       join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
       where c.id = v_id
         and c.capital = 12000
         and c.tasa_anual = 12.5
         and pc.es_legacy
         and pc.legacy_contrato_id = c.id
     )
     or not exists (
       select 1
       from private.contrato_pdf_jobs j
       where j.contrato_id = v_id
         and j.revision = 2
         and j.estado = 'pendiente'
         and (j.snapshot->'contrato'->>'capital')::numeric = 12000
     )
     or (select count(*) from private.contrato_pdf_jobs j
         where j.contrato_id = v_id) <> 2
     or exists (
       select 1 from private.contrato_escritura_atomica_capacidades
     ) then
    raise exception 'FICHA-09O: la corrección no reservó revisión 2 y snapshot legacy actualizado';
  end if;
end;
$correccion_atomica_vendedor_ok$;

create temporary table ficha_cas_correccion_snapshot
on commit drop
as
select
  c.id as contrato_id,
  :'revision_inicial_vendedor'::timestamptz as revision_r0,
  coalesce(c.actualizado_en, c.creado_en, 'epoch'::timestamptz) as revision_r1,
  to_jsonb(c) as contrato,
  coalesce((
    select jsonb_agg(to_jsonb(cp) order by cp.numero_cuota, cp.id)
    from public.cronograma_pagos cp
    where cp.contrato_id = c.id
  ), '[]'::jsonb) as cronograma,
  coalesce((
    select jsonb_agg(to_jsonb(t) order by t.orden, t.id)
    from public.contrato_titulares t
    where t.contrato_id = c.id
  ), '[]'::jsonb) as titulares,
  coalesce((
    select jsonb_agg(to_jsonb(j) order by j.revision, j.id)
    from private.contrato_pdf_jobs j
    where j.contrato_id = c.id
  ), '[]'::jsonb) as pdf_jobs
from public.contratos c
where c.numero_contrato = 'FICHA-ATOM-VENDEDOR';

grant select on table ficha_cas_correccion_snapshot to authenticated;

do $revision_cambio_tras_b$
begin
  if not exists (
    select 1
    from ficha_cas_correccion_snapshot s
    where s.revision_r0 is not null
      and s.revision_r1 is not null
      and s.revision_r1 is distinct from s.revision_r0
  ) then
    raise exception 'FICHA-09O2: la corrección B no publicó un comprobante de vigencia nuevo';
  end if;
end;
$revision_cambio_tras_b$;

-- La pestaña A conserva R0. Ni ese valor vencido ni omitirlo pueden tocar el
-- contrato, cronograma, titulares, snapshots PDF o capacidades internas.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $cas_correccion_conflicto$
declare
  v_id uuid;
  v_r0 timestamptz;
  v_payload jsonb;
  v_cronograma jsonb;
begin
  select s.contrato_id, s.revision_r0
    into v_id, v_r0
  from ficha_cas_correccion_snapshot s;
  v_payload := jsonb_build_object(
    'numero_contrato', 'FICHA-ATOM-VENDEDOR',
    'capital', 12500,
    'moneda', 'PEN',
    'tasa_anual', 13,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '1 year')::date,
    'notas_internas', 'Esta versión no debe guardarse'
  );
  v_cronograma := jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date + 45,
    'monto_programado', 140,
    'tipo', 'cuota'
  ));

  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(
      v_id, v_payload, v_cronograma, v_r0
    );
    raise exception 'FICHA-09O3: una pestaña con R0 sobrescribió la corrección B';
  exception
    when serialization_failure then null;
  end;

  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(
      v_id, v_payload, v_cronograma, null
    );
    raise exception 'FICHA-09O4: una corrección sin comprobante de vigencia se guardó';
  exception
    when serialization_failure then null;
  end;
end;
$cas_correccion_conflicto$;
reset role;

do $cas_correccion_sin_efectos$
begin
  if exists (
    select 1
    from ficha_cas_correccion_snapshot s
    join public.contratos c on c.id = s.contrato_id
    where to_jsonb(c) is distinct from s.contrato
       or coalesce((
         select jsonb_agg(to_jsonb(cp) order by cp.numero_cuota, cp.id)
         from public.cronograma_pagos cp
         where cp.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.cronograma
       or coalesce((
         select jsonb_agg(to_jsonb(t) order by t.orden, t.id)
         from public.contrato_titulares t
         where t.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.titulares
       or coalesce((
         select jsonb_agg(to_jsonb(j) order by j.revision, j.id)
         from private.contrato_pdf_jobs j
         where j.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.pdf_jobs
  ) or exists (
    select 1 from private.contrato_escritura_atomica_capacidades
  ) then
    raise exception 'FICHA-09O5: un conflicto CAS dejó cambios parciales o capacidad reutilizable';
  end if;
end;
$cas_correccion_sin_efectos$;

-- Renovar usa el comprobante del contrato anterior. La pestaña B cambia ese
-- contrato con R0; la pestaña A no puede cerrar ni renovar usando el R0 viejo.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
select set_config('crm.producto_condicion_id', '', true);
set local role authenticated;
select crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb_build_object(
    'cliente_id', 'f4100000-0000-4000-8000-000000000101',
    'numero_contrato', 'FICHA-RENOVACION-ORIGEN',
    'capital', 15000,
    'moneda', 'PEN',
    'tasa_anual', 12,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', (current_date - interval '1 year')::date,
    'fecha_vencimiento', current_date,
    'titulares', '[]'::jsonb
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date,
    'monto_programado', 15000,
    'tipo', 'cuota'
  )),
  jsonb_build_object(
    'tipo', 'existente',
    'cuenta_id', 'f4180000-0000-4000-8000-000000000101'
  )
)::text as alta_origen_renovacion \gset
reset role;

set local session_replication_role = replica;
update public.contratos
set actualizado_en = now() - interval '2 seconds'
where numero_contrato = 'FICHA-RENOVACION-ORIGEN';
set local session_replication_role = origin;

select revision_contrato::text as revision_origen_r0
from crm.contratos_cartera
where numero_contrato = 'FICHA-RENOVACION-ORIGEN'
\gset

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
select crm.actualizar_contrato_con_cuenta_pdf_v3(
  (:'alta_origen_renovacion'::jsonb->>'id')::uuid,
  jsonb_build_object(
    'numero_contrato', 'FICHA-RENOVACION-ORIGEN',
    'capital', 15500,
    'moneda', 'PEN',
    'tasa_anual', 12.5,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', (current_date - interval '1 year')::date,
    'fecha_vencimiento', current_date,
    'notas_internas', 'Versión confirmada por la pestaña B'
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date,
    'monto_programado', 15500,
    'tipo', 'cuota'
  )),
  :'revision_origen_r0'::timestamptz
)::text as correccion_origen_b \gset
reset role;

create temporary table ficha_cas_renovacion_snapshot
on commit drop
as
select
  c.id as contrato_id,
  :'revision_origen_r0'::timestamptz as revision_r0,
  coalesce(c.actualizado_en, c.creado_en, 'epoch'::timestamptz) as revision_r1,
  to_jsonb(c) as contrato,
  coalesce((
    select jsonb_agg(to_jsonb(cp) order by cp.numero_cuota, cp.id)
    from public.cronograma_pagos cp
    where cp.contrato_id = c.id
  ), '[]'::jsonb) as cronograma,
  coalesce((
    select jsonb_agg(to_jsonb(t) order by t.orden, t.id)
    from public.contrato_titulares t
    where t.contrato_id = c.id
  ), '[]'::jsonb) as titulares,
  coalesce((
    select jsonb_agg(to_jsonb(j) order by j.revision, j.id)
    from private.contrato_pdf_jobs j
    where j.contrato_id = c.id
  ), '[]'::jsonb) as pdf_jobs,
  (select count(*) from public.contratos ct
   where ct.cliente_id = c.cliente_id) as contratos_cliente,
  (select count(*) from crm.operaciones_cartera o
   where o.cliente_id = c.cliente_id) as operaciones_cliente
from public.contratos c
where c.numero_contrato = 'FICHA-RENOVACION-ORIGEN';

grant select on table ficha_cas_renovacion_snapshot to authenticated;

do $revision_origen_cambio_tras_b$
begin
  if not exists (
    select 1 from ficha_cas_renovacion_snapshot s
    where s.revision_r0 is not null
      and s.revision_r1 is not null
      and s.revision_r1 is distinct from s.revision_r0
  ) then
    raise exception 'FICHA-09O6: la pestaña B no cambió el comprobante del contrato anterior';
  end if;
end;
$revision_origen_cambio_tras_b$;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $cas_renovacion_conflicto$
declare
  v_id uuid;
  v_r0 timestamptz;
  v_payload jsonb;
  v_cronograma jsonb;
  v_cuenta jsonb;
begin
  select s.contrato_id, s.revision_r0
    into v_id, v_r0
  from ficha_cas_renovacion_snapshot s;
  v_cronograma := jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date + 30,
    'monto_programado', 150,
    'tipo', 'cuota'
  ));
  v_cuenta := jsonb_build_object(
    'tipo', 'existente',
    'cuenta_id', 'f4180000-0000-4000-8000-000000000101'
  );
  v_payload := jsonb_build_object(
    'cliente_id', 'f4100000-0000-4000-8000-000000000101',
    'numero_contrato', 'FICHA-RENOVACION-STALE',
    'capital', 15000,
    'moneda', 'PEN',
    'tasa_anual', 12,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'renovacion',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '1 year')::date,
    'contrato_origen_id', v_id,
    'contrato_origen_revision', v_r0,
    'capital_renovado', 15000,
    'capital_adicional', 0,
    'titulares', '[]'::jsonb
  );

  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      v_payload, v_cronograma, v_cuenta
    );
    raise exception 'FICHA-09O7: una renovación con R0 cerró el contrato cambiado por B';
  exception
    when serialization_failure then null;
  end;

  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_set(
        v_payload - 'contrato_origen_revision',
        '{numero_contrato}',
        '"FICHA-RENOVACION-SIN-REVISION"'::jsonb
      ),
      v_cronograma,
      v_cuenta
    );
    raise exception 'FICHA-09O8: una renovación sin comprobante fue confirmada';
  exception
    when serialization_failure then null;
  end;
end;
$cas_renovacion_conflicto$;
reset role;

do $cas_renovacion_sin_efectos$
begin
  if exists (
    select 1
    from ficha_cas_renovacion_snapshot s
    join public.contratos c on c.id = s.contrato_id
    where to_jsonb(c) is distinct from s.contrato
       or coalesce((
         select jsonb_agg(to_jsonb(cp) order by cp.numero_cuota, cp.id)
         from public.cronograma_pagos cp
         where cp.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.cronograma
       or coalesce((
         select jsonb_agg(to_jsonb(t) order by t.orden, t.id)
         from public.contrato_titulares t
         where t.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.titulares
       or coalesce((
         select jsonb_agg(to_jsonb(j) order by j.revision, j.id)
         from private.contrato_pdf_jobs j
         where j.contrato_id = c.id
       ), '[]'::jsonb) is distinct from s.pdf_jobs
       or (select count(*) from public.contratos ct
           where ct.cliente_id = c.cliente_id) <> s.contratos_cliente
       or (select count(*) from crm.operaciones_cartera o
           where o.cliente_id = c.cliente_id) <> s.operaciones_cliente
  )
     or exists (
       select 1 from public.contratos
       where numero_contrato in (
         'FICHA-RENOVACION-STALE',
         'FICHA-RENOVACION-SIN-REVISION'
       )
     )
     or exists (
       select 1 from private.contrato_escritura_atomica_capacidades
     ) then
    raise exception 'FICHA-09O9: el conflicto de renovación dejó contrato, operación, PDF o capacidad parcial';
  end if;
end;
$cas_renovacion_sin_efectos$;

-- Un cliente de otro equipo no se vuelve operable por entrar al wrapper.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $alta_cliente_ajeno_bloqueada$
begin
  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000102',
        'moneda', 'PEN'
      ),
      '[]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'FICHA-09P: el wrapper abrió un cliente de otro equipo';
  exception
    when sqlstate '42501' then null;
  end;
end;
$alta_cliente_ajeno_bloqueada$;
reset role;

-- El supervisor activo también puede confirmar desde la misma ficha, sin
-- apropiarse del contrato ni seleccionar artificialmente un catálogo.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000001', true);
select set_config('crm.producto_condicion_id', '', true);
set local role authenticated;
select crm.crear_contrato_con_cuenta_pdf_v2(
  jsonb_build_object(
    'cliente_id', 'f4100000-0000-4000-8000-000000000101',
    'numero_contrato', 'FICHA-ATOM-SUPERVISOR',
    'capital', 13000,
    'moneda', 'PEN',
    'tasa_anual', 13,
    'modalidad', 'mensual',
    'tipo_interes', 'simple',
    'categoria', 'nuevo',
    'fecha_inicio', current_date,
    'fecha_vencimiento', (current_date + interval '1 year')::date,
    'titulares', '[]'::jsonb
  ),
  jsonb_build_array(jsonb_build_object(
    'numero_cuota', 1,
    'fecha_programada', current_date + 30,
    'monto_programado', 130,
    'tipo', 'cuota'
  )),
  jsonb_build_object(
    'tipo', 'existente',
    'cuenta_id', 'f4180000-0000-4000-8000-000000000101'
  )
)::text as alta_atomica_supervisor \gset
reset role;

do $alta_atomica_supervisor_ok$
declare
  v_id uuid;
begin
  select c.id into v_id
  from public.contratos c
  where c.numero_contrato = 'FICHA-ATOM-SUPERVISOR';

  if v_id is null
     or not exists (
       select 1
       from public.contratos c
       join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
       where c.id = v_id
         and c.creado_por = 'f4100000-0000-4000-8000-000000000001'
         and pc.es_legacy
         and pc.legacy_contrato_id = c.id
     )
     or (select count(*) from private.contrato_pdf_jobs j
         where j.contrato_id = v_id and j.revision = 1
           and j.estado = 'pendiente') <> 1
     or exists (
       select 1 from private.contrato_escritura_atomica_capacidades
     ) then
    raise exception 'FICHA-09Q: el alta del supervisor no confirmó PDF y snapshot legacy';
  end if;
end;
$alta_atomica_supervisor_ok$;

-- Gerencia y Directorio: lectura global, incluido el cliente sin asesor.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $gerencia$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000102')) <> 1
     or (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000103')) <> 1 then
    raise exception 'FICHA-10: Gerencia no recibió la lectura global esperada';
  end if;
  if (select count(*) from crm.actividades_cliente) <> 2 then
    raise exception 'FICHA-10B: Gerencia no recibió el historial global esperado';
  end if;
  if (select count(*) from crm.contratos_cartera_fn()
      where id in (
        'f4150000-0000-4000-8000-000000000101',
        'f4150000-0000-4000-8000-000000000103'
      )) <> 2
     or (select count(*) from crm.operaciones_cartera) <> 1 then
    raise exception 'FICHA-10C: Gerencia no recibió contratos y movimientos globales (contratos %, movimientos %)',
      (select count(*) from crm.contratos_cartera_fn()
       where id in (
         'f4150000-0000-4000-8000-000000000101',
         'f4150000-0000-4000-8000-000000000103'
       )),
      (select count(*) from crm.operaciones_cartera);
  end if;
end;
$gerencia$;
reset role;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000005', true);
set local role authenticated;
do $directorio$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000102')) <> 1
     or (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000103')) <> 1 then
    raise exception 'FICHA-11: Directorio no recibió la lectura global esperada';
  end if;
  if (select count(*) from crm.actividades_cliente) <> 2 then
    raise exception 'FICHA-11B: Directorio no recibió el historial global esperado';
  end if;
  if (select count(*) from crm.contratos_cartera_fn()
      where id in (
        'f4150000-0000-4000-8000-000000000101',
        'f4150000-0000-4000-8000-000000000103'
      )) <> 2
     or (select count(*) from crm.operaciones_cartera) <> 1 then
    raise exception 'FICHA-11C: Directorio no recibió contratos y movimientos globales';
  end if;
  begin
    perform crm.cuentas_bancarias_cliente_fn(
      'f4100000-0000-4000-8000-000000000101', 'PEN'
    );
    raise exception 'FICHA-11D: Directorio recibió banca desde la ficha';
  exception
    when insufficient_privilege then null;
  end;
end;
$directorio$;
reset role;

-- Una reasignación mueve de inmediato ficha, contratos, cuentas, historial y
-- movimientos de inversión. El evento queda en el mismo historial para que el
-- nuevo asesor entienda el cambio sin depender de quien creó al cliente.
update public.perfiles
set asesor_perfil_id = 'f4100000-0000-4000-8000-000000000003'
where id = 'f4100000-0000-4000-8000-000000000101';

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $asesor_anterior$
begin
  if exists (select 1 from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101'))
     or exists (
       select 1 from crm.contratos_cartera_fn()
       where id = 'f4150000-0000-4000-8000-000000000101'
     )
     or exists (
       select 1 from crm.actividades_cliente
       where cliente_id = 'f4100000-0000-4000-8000-000000000101'
     )
     or exists (
       select 1 from crm.operaciones_cartera
       where cliente_id = 'f4100000-0000-4000-8000-000000000101'
     ) then
    raise exception 'FICHA-11E: el asesor anterior conservó datos después de la reasignación';
  end if;
  if public.puede_ver_contrato('f4150000-0000-4000-8000-000000000101') then
    raise exception 'FICHA-11F: el asesor anterior conservó el detalle contractual';
  end if;
  begin
    perform crm.cuentas_bancarias_cliente_fn(
      'f4100000-0000-4000-8000-000000000101', 'PEN'
    );
    raise exception 'FICHA-11G: el asesor anterior conservó la banca';
  exception
    when insufficient_privilege then null;
  end;
end;
$asesor_anterior$;
reset role;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $asesor_nuevo$
begin
  if (select count(*) from crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101')) <> 1
     or not exists (
       select 1 from crm.contratos_cartera_fn()
       where id = 'f4150000-0000-4000-8000-000000000101'
     )
     or (select count(*) from crm.cronograma_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.titulares_contrato_fn('f4150000-0000-4000-8000-000000000101')) <> 1
     or (select count(*) from crm.cuentas_bancarias_cliente_fn(
       'f4100000-0000-4000-8000-000000000101', 'PEN'
     )) <> 1
     or (select count(*) from crm.operaciones_cartera where cliente_id = 'f4100000-0000-4000-8000-000000000101') <> 1 then
    raise exception 'FICHA-11H: el asesor nuevo no recibió la ficha comercial completa';
  end if;
  if (select count(*) from crm.actividades_cliente where cliente_id = 'f4100000-0000-4000-8000-000000000101') <> 2
     or not exists (
       select 1 from crm.actividades_cliente
       where cliente_id = 'f4100000-0000-4000-8000-000000000101'
         and tipo = 'reasignacion'
         and detalle ilike '%Ficha Vendedor A%Ficha Vendedor B%'
     ) then
    raise exception 'FICHA-11I: la reasignación no quedó visible en el historial del nuevo asesor';
  end if;
end;
$asesor_nuevo$;
reset role;

-- Coordinador, miembro revocado y perfil ajeno al CRM: cero PII.
select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000006', true);
set local role authenticated;
do $coordinador$
begin
  begin
    perform crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101');
    raise exception 'FICHA-12: Coordinador pudo leer la ficha de un cliente';
  exception
    when insufficient_privilege then null;
  end;
end;
$coordinador$;
reset role;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000007', true);
set local role authenticated;
do $revocado$
begin
  begin
    perform crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101');
    raise exception 'FICHA-13: una membresía revocada conservó acceso a la ficha';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000101',
        'moneda', 'PEN'
      ),
      '[]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'FICHA-13B: una membresía revocada usó el alta atómica';
  exception
    when sqlstate '42501' then null;
  end;
end;
$revocado$;
reset role;

select set_config('request.jwt.claim.sub', 'f4100000-0000-4000-8000-000000000008', true);
set local role authenticated;
do $ajeno$
begin
  begin
    perform crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101');
    raise exception 'FICHA-14: un perfil ajeno al CRM pudo leer la ficha';
  exception
    when insufficient_privilege then null;
  end;


  begin
    perform crm.crear_contrato_con_cuenta_pdf_v2(
      jsonb_build_object(
        'cliente_id', 'f4100000-0000-4000-8000-000000000101',
        'moneda', 'PEN'
      ),
      '[]'::jsonb,
      '{}'::jsonb
    );
    raise exception 'FICHA-14B: un perfil ajeno usó el alta atómica';
  exception
    when sqlstate '42501' then null;
  end;

  begin
    perform crm.actualizar_contrato_con_cuenta_pdf_v3(
      'f4150000-0000-4000-8000-000000000101',
      '{}'::jsonb,
      '[]'::jsonb,
      null
    );
    raise exception 'FICHA-14D: un perfil ajeno recibió conflicto en vez de rechazo de permiso';
  exception
    when sqlstate '42501' then null;
  end;
end;
$ajeno$;
reset role;

do $sin_capacidades_filtradas$
begin
  if exists (
    select 1 from private.contrato_escritura_atomica_capacidades
  ) or nullif(
    current_setting('crm.contrato_escritura_atomica_token', true),
    ''
  ) is not null then
    raise exception 'FICHA-14C: una ruta rechazada dejó una capacidad reutilizable';
  end if;
end;
$sin_capacidades_filtradas$;

-- Anon ni siquiera puede ejecutar la RPC.
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
do $anon$
begin
  begin
    perform crm.cliente_ficha_fn('f4100000-0000-4000-8000-000000000101');
    raise exception 'FICHA-15: anon pudo ejecutar la ficha';
  exception
    when insufficient_privilege then null;
  end;
end;
$anon$;
reset role;

select 'FICHA_CLIENTE_SCOPE_TX_OK' as resultado;

rollback;
