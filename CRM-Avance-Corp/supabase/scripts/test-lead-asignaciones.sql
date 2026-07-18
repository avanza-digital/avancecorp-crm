-- Oraculo transaccional autocontenido de la Fase 0C.
-- Exige la migracion aplicada y siempre revierte sus fixtures.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ledger-a@test.invalid', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ledger-b@test.invalid', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'ledger-s@test.invalid', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'ledger-g@test.invalid', now(), '{}', '{}', now(), now()),
  ('10000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'ledger-c@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('10000000-0000-4000-8000-000000000001', 'Analista A', 'ledger-a@test.invalid', 'comercial', true),
  ('10000000-0000-4000-8000-000000000002', 'Analista B', 'ledger-b@test.invalid', 'comercial', true),
  ('10000000-0000-4000-8000-000000000003', 'Supervisor S', 'ledger-s@test.invalid', 'comercial', true),
  ('10000000-0000-4000-8000-000000000004', 'Gerencia G', 'ledger-g@test.invalid', 'directorio', true),
  ('10000000-0000-4000-8000-000000000005', 'Cliente C', 'ledger-c@test.invalid', 'cliente', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('10000000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('10000000-0000-4000-8000-000000000001', 'vendedor', '10000000-0000-4000-8000-000000000003', true),
  ('10000000-0000-4000-8000-000000000002', 'vendedor', '10000000-0000-4000-8000-000000000003', true),
  ('10000000-0000-4000-8000-000000000004', 'gerencia', null, true);

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000004', true);

-- INSERT asignado abre el episodio, pero no inventa una reasignacion humana.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, creado_por, creado_en
)
values (
  '20000000-0000-4000-8000-000000000001', 'Lead ledger uno', '999100001',
  'landing', 'nuevo', 1000, 'PEN', 'nuevo',
  '10000000-0000-4000-8000-000000000001', null,
  '10000000-0000-4000-8000-000000000004', '2099-01-01T00:00:00Z'
);

do $test$
declare
  v_count integer;
  v_monto numeric;
begin
  select count(*), max(monto_estimado)
    into v_count, v_monto
  from crm.lead_asignaciones
  where lead_id = '20000000-0000-4000-8000-000000000001'
    and finalizado_en is null
    and analista_id = '10000000-0000-4000-8000-000000000001'
    and ciclo_n = 1
    and episodio_n = 1
    and motivo_apertura = 'ingreso';

  if v_count <> 1 or v_monto <> 1000 then
    raise exception 'T01 insert asignado no abrio snapshot correcto';
  end if;

  if (
    select l.creado_en >= '2099-01-01T00:00:00Z'::timestamptz
      or la.asignado_en is distinct from l.creado_en
    from crm.leads l
    join crm.lead_asignaciones la on la.lead_id = l.id
    where l.id = '20000000-0000-4000-8000-000000000001'
      and la.finalizado_en is null
  ) then
    raise exception 'T01b creado_en cliente altero el reloj servidor/SLA';
  end if;

  select count(*) into v_count
  from crm.actividades
  where lead_id = '20000000-0000-4000-8000-000000000001'
    and tipo = 'reasignacion';

  if v_count <> 0 then
    raise exception 'T02 insert genero movimiento humano duplicado';
  end if;
end;
$test$;

-- Una recalificacion no reescribe el snapshot anterior; el nuevo responsable
-- fotografia el valor vigente.
update crm.leads
set monto_estimado = 5000
where id = '20000000-0000-4000-8000-000000000001';

do $test$
begin
  if (
    select monto_estimado
    from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and finalizado_en is null
  ) <> 1000 then
    raise exception 'T03 snapshot abierto fue reescrito';
  end if;
end;
$test$;

-- A -> B -> bandeja -> global -> bandeja -> A.
update crm.leads
set vendedor_id = '10000000-0000-4000-8000-000000000002',
    asignado_supervisor_id = null
where id = '20000000-0000-4000-8000-000000000001';

update crm.leads
set vendedor_id = null,
    asignado_supervisor_id = '10000000-0000-4000-8000-000000000003'
where id = '20000000-0000-4000-8000-000000000001';

update crm.leads
set asignado_supervisor_id = null
where id = '20000000-0000-4000-8000-000000000001';

update crm.leads
set asignado_supervisor_id = '10000000-0000-4000-8000-000000000003'
where id = '20000000-0000-4000-8000-000000000001';

update crm.leads
set vendedor_id = '10000000-0000-4000-8000-000000000001',
    asignado_supervisor_id = null
where id = '20000000-0000-4000-8000-000000000001';

update crm.leads
set etapa = 'descartado',
    motivo_descarte = 'sin_interes'
where id = '20000000-0000-4000-8000-000000000001';

-- El resultado terminal ya esta cerrado; mover luego la custodia no lo cambia.
update crm.leads
set vendedor_id = null,
    asignado_supervisor_id = '10000000-0000-4000-8000-000000000003'
where id = '20000000-0000-4000-8000-000000000001';

-- Reapertura parqueada: aumenta ciclo aunque aun no abra episodio.
update crm.leads
set etapa = 'nuevo',
    motivo_descarte = null
where id = '20000000-0000-4000-8000-000000000001';

do $test$
begin
  if (
    select ciclo_actual
    from crm.leads
    where id = '20000000-0000-4000-8000-000000000001'
  ) <> 2 then
    raise exception 'T04 reapertura parqueada no incremento ciclo';
  end if;

  if exists (
    select 1
    from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and finalizado_en is null
  ) then
    raise exception 'T05 reapertura parqueada abrio episodio';
  end if;
end;
$test$;

update crm.leads
set vendedor_id = '10000000-0000-4000-8000-000000000002',
    asignado_supervisor_id = null
where id = '20000000-0000-4000-8000-000000000001';

select set_config('crm.op_privilegiada', 'on', true);
update crm.leads
set etapa = 'convertido',
    perfil_id = '10000000-0000-4000-8000-000000000005',
    convertido_en = statement_timestamp()
where id = '20000000-0000-4000-8000-000000000001';
select set_config('crm.op_privilegiada', 'off', true);

do $test$
declare
  v_total integer;
  v_open integer;
  v_mov integer;
begin
  select count(*), count(*) filter (where finalizado_en is null)
    into v_total, v_open
  from crm.lead_asignaciones
  where lead_id = '20000000-0000-4000-8000-000000000001';

  if v_total <> 4 or v_open <> 0 then
    raise exception 'T06 historia esperada 4/0, obtuvo %/%', v_total, v_open;
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and ciclo_n = 1 and episodio_n = 1
      and analista_id = '10000000-0000-4000-8000-000000000001'
      and motivo_cierre = 'transferido'
      and analista_destino_id = '10000000-0000-4000-8000-000000000002'
      and monto_estimado = 1000
  ) then
    raise exception 'T07 transferencia A no consistente';
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and ciclo_n = 1 and episodio_n = 2
      and analista_id = '10000000-0000-4000-8000-000000000002'
      and motivo_cierre = 'parqueado'
      and supervisor_destino_id = '10000000-0000-4000-8000-000000000003'
      and monto_estimado = 5000
  ) then
    raise exception 'T08 parqueo B no consistente';
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and ciclo_n = 1 and episodio_n = 3
      and analista_id = '10000000-0000-4000-8000-000000000001'
      and motivo_cierre = 'descartado'
      and resultado = 'descartado'
      and motivo_descarte_cierre = 'sin_interes'
  ) then
    raise exception 'T09 descarte atribuido no consistente';
  end if;

  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and ciclo_n = 2 and episodio_n = 1
      and analista_id = '10000000-0000-4000-8000-000000000002'
      and motivo_apertura = 'asignado'
      and motivo_cierre = 'convertido'
      and resultado = 'convertido'
  ) then
    raise exception 'T10 segundo ciclo/conversion no consistente';
  end if;

  select count(*) into v_mov
  from crm.actividades
  where lead_id = '20000000-0000-4000-8000-000000000001'
    and tipo = 'reasignacion';

  if v_mov <> 7 then
    raise exception 'T11 movimientos humanos esperaba 7, obtuvo %', v_mov;
  end if;
end;
$test$;

-- Soft-delete y reactivacion conservan ciclo y abren episodio nuevo.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, creado_por
)
values (
  '20000000-0000-4000-8000-000000000002', 'Lead ledger dos', '999100002',
  'formulario', 'nuevo', 10000, 'PEN',
  '10000000-0000-4000-8000-000000000001', null,
  '10000000-0000-4000-8000-000000000004'
);

update crm.leads
set activo = false
where id = '20000000-0000-4000-8000-000000000002';

update crm.leads
set activo = true
where id = '20000000-0000-4000-8000-000000000002';

do $test$
begin
  if (
    select count(*)
    from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000002'
  ) <> 2
  or (
    select count(*)
    from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000002'
      and finalizado_en is null
  ) <> 1
  or not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000002'
      and ciclo_n = 1
      and episodio_n = 2
      and motivo_apertura = 'reactivado'
  ) then
    raise exception 'T12 soft-delete/reactivacion inconsistente';
  end if;
end;
$test$;

-- Un supervisor activo tambien puede tener cartera propia y cuenta como
-- analista; Gerencia nunca puede ser destinatario analitico.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, creado_por
)
values (
  '20000000-0000-4000-8000-000000000005', 'Lead supervisor propio', '999100005',
  'otro', 'nuevo', 75000, 'PEN',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004'
);

do $test$
begin
  if not exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000005'
      and analista_id = '10000000-0000-4000-8000-000000000003'
      and finalizado_en is null
  ) then
    raise exception 'T12b supervisor activo no recibio episodio propio';
  end if;

  update crm.leads
  set ciclo_actual = 999
  where id = '20000000-0000-4000-8000-000000000002';

  if (select ciclo_actual from crm.leads
      where id = '20000000-0000-4000-8000-000000000002') <> 1 then
    raise exception 'T12c cliente pudo falsificar ciclo_actual';
  end if;
end;
$test$;

-- Un lead inactivo no puede saltar directamente a terminal: primero recupera
-- una responsabilidad operativa y solo entonces se atribuye el resultado.
insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, creado_por
)
values (
  '20000000-0000-4000-8000-000000000004', 'Lead ledger cuatro', '999100004',
  'otro', 'nuevo', 50000, 'PEN',
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000004'
);

update crm.leads
set activo = false
where id = '20000000-0000-4000-8000-000000000004';

do $test$
begin
  begin
    update crm.leads
    set etapa = 'descartado', motivo_descarte = 'otro'
    where id = '20000000-0000-4000-8000-000000000004';
    raise exception 'T13 no rechazo descarte inactivo';
  exception when others then
    if sqlerrm = 'T13 no rechazo descarte inactivo' then raise; end if;
  end;

  begin
    perform set_config('crm.op_privilegiada', 'on', true);
    update crm.leads
    set etapa = 'convertido',
        perfil_id = '10000000-0000-4000-8000-000000000005',
        convertido_en = statement_timestamp()
    where id = '20000000-0000-4000-8000-000000000004';
    raise exception 'T14 no rechazo conversion inactiva';
  exception when others then
    if sqlerrm = 'T14 no rechazo conversion inactiva' then raise; end if;
  end;
  perform set_config('crm.op_privilegiada', 'off', true);
end;
$test$;

update crm.leads
set activo = true
where id = '20000000-0000-4000-8000-000000000004';

update crm.leads
set etapa = 'descartado', motivo_descarte = 'otro'
where id = '20000000-0000-4000-8000-000000000004';

do $test$
begin
  if (select count(*) from crm.lead_asignaciones
      where lead_id = '20000000-0000-4000-8000-000000000004') <> 2
     or (select count(*) from crm.lead_asignaciones
         where lead_id = '20000000-0000-4000-8000-000000000004'
           and resultado = 'descartado') <> 1 then
    raise exception 'T15 reactivacion previa al cierre no produjo resultado atribuido';
  end if;
end;
$test$;

-- Doble tenencia y Gerencia como destinatario analitico se rechazan.
do $test$
begin
  begin
    insert into crm.leads (
      nombre_completo, telefono, origen, monto_estimado, moneda, vendedor_id,
      asignado_supervisor_id, creado_por
    ) values (
      'Invalido doble tenencia', '999100010', 'otro', 1000, 'PEN',
      '10000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000003',
      '10000000-0000-4000-8000-000000000004'
    );
    raise exception 'T16 no rechazo doble tenencia';
  exception when others then
    if sqlerrm = 'T16 no rechazo doble tenencia' then raise; end if;
  end;

  begin
    insert into crm.leads (
      nombre_completo, telefono, origen, monto_estimado, moneda, vendedor_id, creado_por
    ) values (
      'Invalido gerencia analista', '999100011', 'otro', 1000, 'PEN',
      '10000000-0000-4000-8000-000000000004',
      '10000000-0000-4000-8000-000000000004'
    );
    raise exception 'T17 no rechazo gerencia como analista';
  exception when others then
    if sqlerrm = 'T17 no rechazo gerencia como analista' then raise; end if;
  end;
end;
$test$;

insert into crm.leads (
  id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, creado_por
)
values (
  '20000000-0000-4000-8000-000000000003', 'Lead ledger tres', '999100003',
  'otro', 'nuevo', 20000, 'PEN',
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000004'
);

-- Propietario + terminal debe ser dos operaciones; conversion parqueada falla.
do $test$
begin
  begin
    update crm.leads
    set vendedor_id = '10000000-0000-4000-8000-000000000002',
        etapa = 'descartado',
        motivo_descarte = 'otro'
    where id = '20000000-0000-4000-8000-000000000003';
    raise exception 'T18 no rechazo owner+terminal';
  exception when others then
    if sqlerrm = 'T18 no rechazo owner+terminal' then raise; end if;
  end;
end;
$test$;

update crm.leads
set vendedor_id = null,
    asignado_supervisor_id = '10000000-0000-4000-8000-000000000003'
where id = '20000000-0000-4000-8000-000000000003';

do $test$
begin
  begin
    perform set_config('crm.op_privilegiada', 'on', true);
    update crm.leads
    set etapa = 'convertido',
        perfil_id = '10000000-0000-4000-8000-000000000005',
        convertido_en = statement_timestamp()
    where id = '20000000-0000-4000-8000-000000000003';
    raise exception 'T19 no rechazo conversion parqueada';
  exception when others then
    if sqlerrm = 'T19 no rechazo conversion parqueada' then raise; end if;
  end;
  perform set_config('crm.op_privilegiada', 'off', true);
end;
$test$;

-- Destinos invalidos y cola global no gerencial se rechazan antes del ledger.
update crm.equipo
set activo = false
where perfil_id = '10000000-0000-4000-8000-000000000002';

do $test$
begin
  begin
    update crm.leads
    set vendedor_id = '10000000-0000-4000-8000-000000000002',
        asignado_supervisor_id = null
    where id = '20000000-0000-4000-8000-000000000003';
    raise exception 'T19b no rechazo analista inactivo';
  exception when others then
    if sqlerrm = 'T19b no rechazo analista inactivo' then raise; end if;
  end;

  begin
    update crm.leads
    set vendedor_id = null,
        asignado_supervisor_id = '10000000-0000-4000-8000-000000000001'
    where id = '20000000-0000-4000-8000-000000000003';
    raise exception 'T19c no rechazo vendedor como bandeja';
  exception when others then
    if sqlerrm = 'T19c no rechazo vendedor como bandeja' then raise; end if;
  end;
end;
$test$;

update crm.equipo
set activo = true
where perfil_id = '10000000-0000-4000-8000-000000000002';

select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
do $test$
begin
  begin
    update crm.leads
    set asignado_supervisor_id = null
    where id = '20000000-0000-4000-8000-000000000003';
    raise exception 'T19d no rechazo cola global por supervisor';
  exception when others then
    if sqlerrm = 'T19d no rechazo cola global por supervisor' then raise; end if;
  end;
end;
$test$;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000004', true);

-- El writer interno tampoco puede reabrir una fila cerrada. INSERT/DELETE
-- directos quedan fuera de la unica ruta de escritura autorizada.
do $test$
declare
  v_id uuid;
begin
  select id into v_id
  from crm.lead_asignaciones
  where lead_id = '20000000-0000-4000-8000-000000000001'
    and ciclo_n = 1
    and episodio_n = 1;

  begin
    perform set_config('crm.ledger_writer', 'on', true);
    update crm.lead_asignaciones
    set finalizado_en = finalizado_en
    where id = v_id;
    raise exception 'T20 no rechazo update de cerrado';
  exception when others then
    if sqlerrm = 'T20 no rechazo update de cerrado' then raise; end if;
  end;

  begin
    insert into crm.lead_asignaciones (
      lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
      asignado_en, moneda, origen
    ) values (
      '20000000-0000-4000-8000-000000000003', 1, 99,
      '10000000-0000-4000-8000-000000000001', 'asignado',
      statement_timestamp(), 'PEN', 'otro'
    );
    raise exception 'T21 no rechazo insert directo';
  exception when others then
    if sqlerrm = 'T21 no rechazo insert directo' then raise; end if;
  end;

  begin
    delete from crm.lead_asignaciones where id = v_id;
    raise exception 'T22 no rechazo delete directo';
  exception when others then
    if sqlerrm = 'T22 no rechazo delete directo' then raise; end if;
  end;

  begin
    delete from crm.leads
    where id = '20000000-0000-4000-8000-000000000001';
    raise exception 'T22b no preservo ledger al borrar el lead padre';
  exception when others then
    if sqlerrm = 'T22b no preservo ledger al borrar el lead padre' then raise; end if;
  end;
end;
$test$;

-- La Data API no puede leer ni escribir el ledger directamente. La V1 lo hara
-- mediante una RPC agregada con gate de Gerencia.
do $test$
begin
  if not (
    select c.relrowsecurity
    from pg_class c
    where c.oid = 'crm.lead_asignaciones'::regclass
  ) then
    raise exception 'T23 RLS no esta habilitado en el ledger';
  end if;

  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'crm'
      and p.tablename = 'lead_asignaciones'
  ) then
    raise exception 'T24 el ledger no debe exponer policies directas en 0C';
  end if;

  if has_table_privilege('anon', 'crm.lead_asignaciones', 'SELECT')
     or has_table_privilege('authenticated', 'crm.lead_asignaciones', 'SELECT')
     or has_table_privilege('service_role', 'crm.lead_asignaciones', 'SELECT')
     or has_table_privilege('anon', 'crm.lead_asignaciones', 'INSERT')
     or has_table_privilege('anon', 'crm.lead_asignaciones', 'UPDATE')
     or has_table_privilege('anon', 'crm.lead_asignaciones', 'DELETE')
     or has_table_privilege('authenticated', 'crm.lead_asignaciones', 'INSERT')
     or has_table_privilege('authenticated', 'crm.lead_asignaciones', 'UPDATE')
     or has_table_privilege('authenticated', 'crm.lead_asignaciones', 'DELETE')
     or has_table_privilege('service_role', 'crm.lead_asignaciones', 'INSERT')
     or has_table_privilege('service_role', 'crm.lead_asignaciones', 'UPDATE')
     or has_table_privilege('service_role', 'crm.lead_asignaciones', 'DELETE') then
    raise exception 'T25 un rol API conserva privilegios directos sobre el ledger';
  end if;

  if has_function_privilege(
       'authenticated',
       'private.clasificar_movimiento_tenencia(uuid,uuid,uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'private.trg_leads_asignaciones()',
       'EXECUTE'
     ) then
    raise exception 'T26 una funcion interna conserva EXECUTE para roles API';
  end if;
end;
$test$;

select jsonb_build_object(
  'resultado', '0C_TX_ORACLE_OK',
  'lead1_episodios', (
    select count(*) from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000001'
  ),
  'lead2_abiertos', (
    select count(*) from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000002'
      and finalizado_en is null
  ),
  'lead3_abiertos', (
    select count(*) from crm.lead_asignaciones
    where lead_id = '20000000-0000-4000-8000-000000000003'
      and finalizado_en is null
  ),
  'movimientos_lead1', (
    select count(*) from crm.actividades
    where lead_id = '20000000-0000-4000-8000-000000000001'
      and tipo = 'reasignacion'
  )
) as validacion;

rollback;
