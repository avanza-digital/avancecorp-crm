-- Oráculo transaccional de Base para gestión.
-- Éxito = BASE_GESTION_DESCARTES_TX_OK; todos los fixtures terminan en ROLLBACK.
--
-- Cubre: alcance por supervisor, lectura global de Gerencia, denegación a
-- vendedor/anon, proyección sin PII, recuperabilidad, atomicidad ante un lote
-- mixto, veto No Insista, reparto equilibrado y conservación del ledger.

begin;
set local statement_timeout = '60s';

select pg_catalog.set_config('request.jwt.claims', '', true);
select pg_catalog.set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('b4500000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'base-sup-uno@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'base-sup-dos@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'base-origen@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'base-destino-uno@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'base-destino-dos@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'base-ajeno@test.invalid', now(), '{}', '{}', now(), now()),
  ('b4500000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'base-gerencia@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('b4500000-0000-4000-8000-000000000001', 'Base Supervisor Uno', 'base-sup-uno@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000002', 'Base Supervisor Dos', 'base-sup-dos@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000003', 'Base Asesor Origen', 'base-origen@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000004', 'Base Destino Uno', 'base-destino-uno@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000005', 'Base Destino Dos', 'base-destino-dos@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000006', 'Base Asesor Ajeno', 'base-ajeno@test.invalid', 'comercial', true),
  ('b4500000-0000-4000-8000-000000000007', 'Base Gerencia', 'base-gerencia@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('b4500000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('b4500000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('b4500000-0000-4000-8000-000000000003', 'vendedor', 'b4500000-0000-4000-8000-000000000001', true),
  ('b4500000-0000-4000-8000-000000000004', 'vendedor', 'b4500000-0000-4000-8000-000000000001', true),
  ('b4500000-0000-4000-8000-000000000005', 'vendedor', 'b4500000-0000-4000-8000-000000000001', true),
  ('b4500000-0000-4000-8000-000000000006', 'vendedor', 'b4500000-0000-4000-8000-000000000002', true),
  ('b4500000-0000-4000-8000-000000000007', 'gerencia', null, true);

insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  categoria_interes, vendedor_id, asignado_supervisor_id, activo,
  no_contactar, creado_por
)
values
  ('b4510000-0000-4000-8000-000000000001', 'Base Recuperable Uno', '999451001', 'nuevo', 'landing', 10000, 'PEN', 'nuevo', 'b4500000-0000-4000-8000-000000000003', null, true, false, 'b4500000-0000-4000-8000-000000000007'),
  ('b4510000-0000-4000-8000-000000000002', 'Base Recuperable Dos', '999451002', 'nuevo', 'formulario', 20000, 'USD', 'nuevo', 'b4500000-0000-4000-8000-000000000003', null, true, false, 'b4500000-0000-4000-8000-000000000007'),
  ('b4510000-0000-4000-8000-000000000003', 'Base Otro Equipo', '999451003', 'nuevo', 'referido', 30000, 'PEN', 'nuevo', 'b4500000-0000-4000-8000-000000000006', null, true, false, 'b4500000-0000-4000-8000-000000000007'),
  ('b4510000-0000-4000-8000-000000000004', 'Base Datos Invalidos', '999451004', 'nuevo', 'oficina', 40000, 'PEN', 'nuevo', 'b4500000-0000-4000-8000-000000000003', null, true, false, 'b4500000-0000-4000-8000-000000000007'),
  ('b4510000-0000-4000-8000-000000000005', 'Base No Insista', '999451005', 'nuevo', 'otro', 50000, 'PEN', 'nuevo', 'b4500000-0000-4000-8000-000000000003', null, true, true, 'b4500000-0000-4000-8000-000000000007');

-- Descartes reales: los triggers sellan el lead y cierran el episodio del ledger.
select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000003', true);
set local role authenticated;
update crm.leads
set etapa = 'descartado',
    motivo_descarte = case
      when id = 'b4510000-0000-4000-8000-000000000004' then 'datos_invalidos'
      when id = 'b4510000-0000-4000-8000-000000000005' then 'no_responde'
      else 'sin_interes'
    end
where id in (
  'b4510000-0000-4000-8000-000000000001',
  'b4510000-0000-4000-8000-000000000002',
  'b4510000-0000-4000-8000-000000000004',
  'b4510000-0000-4000-8000-000000000005'
);
reset role;

select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000006', true);
set local role authenticated;
update crm.leads
set etapa = 'descartado', motivo_descarte = 'competencia'
where id = 'b4510000-0000-4000-8000-000000000003';
reset role;

-- Vendedor autenticado: puede ejecutar la firma, pero el gate interno lo niega.
select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  begin
    perform pg_catalog.count(*) from crm.rescate_descartes_meses();
    raise exception 'BG01 un vendedor pudo consultar Base para gestión';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- Anon ni siquiera recibe EXECUTE.
do $test$
begin
  if pg_catalog.has_function_privilege(
    'anon',
    'crm.rescate_descartes_meses()'::regprocedure,
    'EXECUTE'
  ) then
    raise exception 'BG02 anon conserva EXECUTE sobre Base para gestión';
  end if;
end;
$test$;

-- Supervisor uno: cuatro episodios propios, dos recuperables y cero del otro equipo.
select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
  v_total integer;
  v_pendientes integer;
  v_proyeccion jsonb;
begin
  select pg_catalog.count(*) into v_total
  from crm.rescate_descartes_mes(v_mes)
  where lead_id between 'b4510000-0000-4000-8000-000000000001'::uuid
                    and 'b4510000-0000-4000-8000-000000000005'::uuid;
  if v_total <> 4 then
    raise exception 'BG03 el supervisor debería ver 4 descartes propios, ve %', v_total;
  end if;

  if exists (
    select 1 from crm.rescate_descartes_mes(v_mes)
    where lead_id = 'b4510000-0000-4000-8000-000000000003'
  ) then
    raise exception 'BG04 el supervisor vio un descarte de otro equipo';
  end if;

  select total::integer, pendientes::integer
    into v_total, v_pendientes
  from crm.rescate_descartes_meses()
  where mes = v_mes;
  if v_total <> 4 or v_pendientes <> 2 then
    raise exception 'BG05 franja mensual incorrecta: total %, pendientes %', v_total, v_pendientes;
  end if;

  if (select puede_rescatar from crm.rescate_descartes_mes(v_mes)
      where lead_id = 'b4510000-0000-4000-8000-000000000004') then
    raise exception 'BG06 datos inválidos apareció como recuperable';
  end if;
  if (select puede_rescatar from crm.rescate_descartes_mes(v_mes)
      where lead_id = 'b4510000-0000-4000-8000-000000000005') then
    raise exception 'BG07 No Insista apareció como recuperable';
  end if;

  select pg_catalog.to_jsonb(fila) into v_proyeccion
  from crm.rescate_descartes_mes(v_mes) fila
  where fila.lead_id = 'b4510000-0000-4000-8000-000000000001';
  if v_proyeccion ?| array['telefono', 'correo', 'dni', 'nota', 'no_contactar'] then
    raise exception 'BG08 la RPC expuso PII o notas libres: %', v_proyeccion;
  end if;
end;
$test$;

-- Lote mixto: un episodio ajeno invalida TODO y el propio no se mueve.
do $test$
declare
  v_propio uuid;
  v_inexistente uuid := 'b4590000-0000-4000-8000-000000000999';
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  select episodio_id into v_propio from crm.rescate_descartes_mes(v_mes)
  where lead_id = 'b4510000-0000-4000-8000-000000000001';

  begin
    perform crm.rescatar_descartes(
      array[v_propio, v_inexistente],
      array['b4500000-0000-4000-8000-000000000004'::uuid],
      true
    );
    raise exception 'BG09 un lote con episodio ajeno fue aceptado';
  exception
    when sqlstate 'P0002' then null;
  end;

  if (select etapa from crm.leads where id = 'b4510000-0000-4000-8000-000000000001') <> 'descartado' then
    raise exception 'BG10 el lote fallido dejó un rescate parcial';
  end if;
end;
$test$;

-- No Insista también aborta el bloque completo.
do $test$
declare
  v_valido uuid;
  v_vetado uuid;
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  select episodio_id into v_valido from crm.rescate_descartes_mes(v_mes)
  where lead_id = 'b4510000-0000-4000-8000-000000000001';
  select episodio_id into v_vetado from crm.rescate_descartes_mes(v_mes)
  where lead_id = 'b4510000-0000-4000-8000-000000000005';

  begin
    perform crm.rescatar_descartes(
      array[v_valido, v_vetado],
      array['b4500000-0000-4000-8000-000000000004'::uuid],
      true
    );
    raise exception 'BG11 un lote No Insista fue aceptado';
  exception
    when sqlstate 'P0429' then null;
  end;

  if (select etapa from crm.leads where id = 'b4510000-0000-4000-8000-000000000001') <> 'descartado' then
    raise exception 'BG12 No Insista dejó un rescate parcial';
  end if;
end;
$test$;

-- Camino feliz: incluye al asesor origen entre los destinos. La ronda debe
-- saltarlo y continuar desde el destino realmente usado (Destino Uno, Dos).
do $test$
declare
  v_uno uuid;
  v_dos uuid;
  v_resultado jsonb;
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  select episodio_id into v_uno from crm.rescate_descartes_mes(v_mes)
  where lead_id = 'b4510000-0000-4000-8000-000000000001';
  select episodio_id into v_dos from crm.rescate_descartes_mes(v_mes)
  where lead_id = 'b4510000-0000-4000-8000-000000000002';

  v_resultado := crm.rescatar_descartes(
    array[v_uno, v_dos],
    array[
      'b4500000-0000-4000-8000-000000000003'::uuid,
      'b4500000-0000-4000-8000-000000000004'::uuid,
      'b4500000-0000-4000-8000-000000000005'::uuid
    ],
    true
  );
  if v_resultado->>'rescatados' <> '2' then
    raise exception 'BG13 confirmación de rescate incorrecta: %', v_resultado;
  end if;

  if (select vendedor_id from crm.leads where id = 'b4510000-0000-4000-8000-000000000001')
     <> 'b4500000-0000-4000-8000-000000000004' then
    raise exception 'BG14 el primer lead no llegó a Destino Uno';
  end if;
  if (select vendedor_id from crm.leads where id = 'b4510000-0000-4000-8000-000000000002')
     <> 'b4500000-0000-4000-8000-000000000005' then
    raise exception 'BG15 la ronda no avanzó a Destino Dos';
  end if;

  if exists (
    select 1 from crm.leads
    where id in ('b4510000-0000-4000-8000-000000000001', 'b4510000-0000-4000-8000-000000000002')
      and (etapa <> 'nuevo' or motivo_descarte is not null)
  ) then
    raise exception 'BG16 los leads no reabrieron limpios en Nuevo';
  end if;

end;
$test$;

do $test$
declare
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  if (select pg_catalog.count(*) from crm.rescate_descartes_mes(v_mes)
      where lead_id in ('b4510000-0000-4000-8000-000000000001', 'b4510000-0000-4000-8000-000000000002')
        and estado = 'rescatado' and puede_rescatar = false) <> 2 then
    raise exception 'BG19 el historial no marcó los episodios como rescatados';
  end if;
  if (select pendientes from crm.rescate_descartes_meses() where mes = v_mes) is distinct from 0 then
    raise exception 'BG20 la franja conserva pendientes que ya fueron rescatados';
  end if;
end;
$test$;
reset role;

-- Las tablas del ledger no se exponen al rol autenticado. El oráculo de
-- persistencia se hace como dueño, después de probar la RPC real.
do $test$
begin
  if (select pg_catalog.count(*) from crm.lead_asignaciones
      where lead_id in ('b4510000-0000-4000-8000-000000000001', 'b4510000-0000-4000-8000-000000000002')
        and resultado = 'descartado') <> 2 then
    raise exception 'BG17 el rescate modificó el episodio histórico';
  end if;
  if (select pg_catalog.count(*) from crm.lead_asignaciones
      where lead_id in ('b4510000-0000-4000-8000-000000000001', 'b4510000-0000-4000-8000-000000000002')
        and finalizado_en is null and motivo_apertura = 'reabierto') <> 2 then
    raise exception 'BG18 el rescate no abrió dos episodios nuevos';
  end if;
end;
$test$;

-- El otro supervisor solo ve su propio episodio.
select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
declare
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  if (select pg_catalog.count(*) from crm.rescate_descartes_mes(v_mes)
      where lead_id between 'b4510000-0000-4000-8000-000000000001'::uuid
                        and 'b4510000-0000-4000-8000-000000000005'::uuid) <> 1 then
    raise exception 'BG21 el segundo supervisor no quedó aislado a su equipo';
  end if;
end;
$test$;
reset role;

-- Gerencia ve todos los equipos, pero tampoco recibe PII.
select pg_catalog.set_config('request.jwt.claim.sub', 'b4500000-0000-4000-8000-000000000007', true);
set local role authenticated;
do $test$
declare
  v_mes date := pg_catalog.date_trunc('month', current_timestamp at time zone 'America/Lima')::date;
begin
  if (select pg_catalog.count(*) from crm.rescate_descartes_mes(v_mes)
      where lead_id between 'b4510000-0000-4000-8000-000000000001'::uuid
                        and 'b4510000-0000-4000-8000-000000000005'::uuid) <> 5 then
    raise exception 'BG22 Gerencia no vio los cinco episodios globales';
  end if;
end;
$test$;
reset role;

select 'BASE_GESTION_DESCARTES_TX_OK' as resultado;
rollback;
