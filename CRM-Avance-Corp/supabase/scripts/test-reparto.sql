-- Oraculo transaccional autocontenido del reparto de la cola (C1, coordinador).
-- Exito = token REPARTO_TX_OK; todo queda en rollback.
--
-- Cubre: gate de rol de las 3 RPC, proyeccion sin PII, filtro legal de la cola,
-- el camino feliz (bandeja + vendedor null), el veto legal P0429 con oraculo de
-- estado, turno diario obligatorio, desglose de entregas reales (incluido un
-- legado fuera de turno), destino invalido, lead fuera de cola y aislamiento.
-- La CARRERA de reparto NO se prueba aqui (necesita dos sesiones simultaneas):
-- la cubre testReparto de test-rls.mjs.

begin;

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('17000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'rep-coord@test.invalid', now(), '{}', '{}', now(), now()),
  ('17000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'rep-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('17000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'rep-vend@test.invalid', now(), '{}', '{}', now(), now()),
  ('17000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'rep-ger@test.invalid', now(), '{}', '{}', now(), now()),
  ('17000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'rep-cliente@test.invalid', now(), '{}', '{}', now(), now()),
  ('17000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'rep-sup-dos@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('17000000-0000-4000-8000-000000000001', 'Reparto Coordinadora', 'rep-coord@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000002', 'Reparto Supervisor', 'rep-sup@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000003', 'Reparto Vendedor', 'rep-vend@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000004', 'Reparto Gerencia', 'rep-ger@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000005', 'Reparto Cliente', 'rep-cliente@test.invalid', 'cliente', true),
  ('17000000-0000-4000-8000-000000000006', 'Reparto Supervisora Dos', 'rep-sup-dos@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('17000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('17000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('17000000-0000-4000-8000-000000000003', 'vendedor', '17000000-0000-4000-8000-000000000002', true),
  ('17000000-0000-4000-8000-000000000004', 'gerencia', null, true),
  ('17000000-0000-4000-8000-000000000006', 'supervisor', null, true);

-- El seed real de la migración reconoce los nombres de producción. Este
-- oráculo usa UUIDs aislados, por eso habilita explícitamente sus dos destinos.
insert into private.agenda_reparto_destinos (supervisor_id, alias, orden)
values
  ('17000000-0000-4000-8000-000000000002', 'Carmen', 1),
  ('17000000-0000-4000-8000-000000000006', 'Jor', 2);

-- Cola global: ambos-null (se siembra como owner, sin pasar por la RLS).
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por
)
values
  ('18000000-0000-4000-8000-000000000001', 'REPARTO SQL CONTACTABLE', '999111001', 'nuevo', 'landing', 12000, 'PEN', null, null, true, false, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000002', 'REPARTO SQL NO INSISTA', '999111002', 'nuevo', 'otro', 8000, 'PEN', null, null, true, true, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000003', 'REPARTO SQL CON DUENO', '999111003', 'nuevo', 'otro', 5000, 'USD', '17000000-0000-4000-8000-000000000003', null, true, false, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000004', 'REPARTO SQL REFERIDO', '999111004', 'nuevo', 'referido', 4000, 'PEN', '17000000-0000-4000-8000-000000000003', null, true, false, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000005', 'REPARTO SQL WALKING', '999111005', 'nuevo', 'oficina', 3000, 'PEN', null, '17000000-0000-4000-8000-000000000002', true, false, '17000000-0000-4000-8000-000000000002'),
  -- Evidencia heredada anterior al candado: Landing terminó en la supervisora
  -- dos. La agenda nueva debe mostrarla, aunque no coincida con el turno.
  ('18000000-0000-4000-8000-000000000006', 'REPARTO SQL LEGADO FUERA TURNO', '999111006', 'nuevo', 'landing', 3500, 'PEN', null, '17000000-0000-4000-8000-000000000006', true, false, '17000000-0000-4000-8000-000000000002');

insert into crm.actividades (
  id, lead_id, tipo, detalle, metadata, creado_por, creado_en
)
values (
  '19000000-0000-4000-8000-000000000001',
  '18000000-0000-4000-8000-000000000006',
  'reasignacion',
  'Sonda de entrega heredada fuera del turno',
  jsonb_build_object(
    'movimiento', 'entra_bandeja',
    'supervisor_nuevo', '17000000-0000-4000-8000-000000000006'
  ),
  '17000000-0000-4000-8000-000000000001',
  statement_timestamp()
);

-- ── R1: la coordinadora ve la cola, sin PII y sin el lead No Insista ─────────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000001', true);
set local role authenticated;

do $test$
declare
  v_n int;
begin
  select count(*) into v_n from crm.leads_por_repartir();
  if v_n <> 1 then
    raise exception 'R01 la cola deberia tener exactamente 1 lead contactable, tiene %', v_n;
  end if;

  if not exists (select 1 from crm.leads_por_repartir() where id = '18000000-0000-4000-8000-000000000001') then
    raise exception 'R02 el lead contactable no aparece en la cola';
  end if;

  if exists (select 1 from crm.leads_por_repartir() where id = '18000000-0000-4000-8000-000000000002') then
    raise exception 'R03 LEGAL: un lead no_contactar aparecio en la cola (Ley 29571)';
  end if;

  if exists (select 1 from crm.leads_por_repartir() where id = '18000000-0000-4000-8000-000000000003') then
    raise exception 'R04 un lead con dueno aparecio en la cola global';
  end if;

  -- Ambito RLS: la coordinadora NO ve leads por la tabla, solo por la RPC.
  if exists (select 1 from crm.leads) then
    raise exception 'R05 la coordinadora ve filas de crm.leads por RLS (deberia ser vacio)';
  end if;

  -- Destinos disponibles: solo supervisores activos.
  if (select count(*) from crm.supervisores_para_reparto()) <> 2 then
    raise exception 'R06 supervisores_para_reparto no devolvio a las dos supervisoras activas';
  end if;
end;
$test$;

-- ── R2: superficies adyacentes cerradas para el rol nuevo ───────────────────
do $test$
begin
  if exists (select 1 from crm.clientes_basicos) then
    raise exception 'R07 la coordinadora ve PII de clientes (clientes_basicos)';
  end if;

  if jsonb_array_length(
    coalesce(
      crm.configuracion_metas_fn(date_trunc('month',current_date)::date)->'vendedores',
      '[]'::jsonb
    )
  ) <> 0 then
    raise exception 'R08 la coordinadora ve metas comerciales fuera de su ambito';
  end if;

  begin
    perform crm.existe_cliente_por_dni('99999999');
    raise exception 'R09 la coordinadora pudo sondear DNIs de clientes';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;

  begin
    perform crm.metricas_agenda_fn(current_date - 7, current_date);
    raise exception 'R10 la coordinadora pudo leer las metricas de agenda';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;
end;
$test$;

-- ── R3: veto legal con SQLSTATE propio + oraculo de estado ───────────────────
do $test$
declare
  v_sqlstate text;
begin
  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000002',
      '17000000-0000-4000-8000-000000000002');
    raise exception 'R11 LEGAL: se pudo repartir un lead marcado No Insista';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0429' then
        raise exception 'R12 LEGAL: el veto uso el SQLSTATE % en vez de P0429', v_sqlstate;
      end if;
  end;
end;
$test$;

-- El RAISE revierte su propio subbloque: el lead debe seguir en la cola global.
do $test$
begin
  if exists (
    select 1 from crm.leads
    where id = '18000000-0000-4000-8000-000000000002'
      and (asignado_supervisor_id is not null or vendedor_id is not null)
  ) then
    raise exception 'R13 LEGAL: el lead No Insista salio de la cola global';
  end if;
end;
$test$;
reset role;

-- ── R4: destino invalido y lead fuera de cola ───────────────────────────────
set local role authenticated;
do $test$
declare
  v_sqlstate text;
begin
  -- Destino = vendedor (no supervisor) → 22023 con mensaje humano.
  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000001',
      '17000000-0000-4000-8000-000000000003');
    raise exception 'R14 se pudo repartir a un destino que no es supervisor';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'R15 destino invalido devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;

  -- Lead con dueno → P0002 (no esta en la cola).
  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000003',
      '17000000-0000-4000-8000-000000000002');
    raise exception 'R16 se pudo repartir un lead que ya tiene dueno';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> 'P0002' then
        raise exception 'R17 lead fuera de cola devolvio % en vez de P0002', v_sqlstate;
      end if;
  end;
end;
$test$;

-- ── R4-bis: agenda Landing/Formulario, sin abrir PII ───────────────────────
do $test$
declare
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_agenda jsonb;
  v_sqlstate text;
begin
  perform crm.guardar_agenda_reparto_diaria(
    v_hoy,
    '17000000-0000-4000-8000-000000000002',
    '17000000-0000-4000-8000-000000000006'
  );

  v_agenda := crm.agenda_reparto_diaria(v_hoy, 1);
  if v_agenda->>'version' <> '1'
     or jsonb_array_length(coalesce(v_agenda->'destinos', '[]'::jsonb)) <> 2 then
    raise exception 'R17a la agenda no devolvio sus dos destinos habilitados';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(v_agenda->'dias') as d(fecha date, asignaciones jsonb)
    cross join lateral jsonb_to_recordset(d.asignaciones) as a(
      origen text, supervisor_id uuid, supervisor_alias text, derivados int,
      fuera_turno int, entregas jsonb
    )
    where d.fecha = v_hoy
      and a.origen = 'landing'
      and a.supervisor_id = '17000000-0000-4000-8000-000000000002'
      and a.supervisor_alias = 'Carmen'
      and a.derivados = 1
      and a.fuera_turno = 1
      and exists (
        select 1
        from jsonb_to_recordset(a.entregas) as entrega(
          supervisor_id uuid, derivados int, coincide_turno boolean
        )
        where entrega.supervisor_id = '17000000-0000-4000-8000-000000000006'
          and entrega.derivados = 1
          and entrega.coincide_turno = false
      )
  ) then
    raise exception 'R17b Landing no mostró el turno y la entrega real fuera de turno';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_agenda->'dias') as d(fila)
    where d.fila::text ~* 'telefono|correo|dni|nota|nombre_completo'
  ) then
    raise exception 'R17c la agenda expuso PII de leads';
  end if;

  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000001',
      '17000000-0000-4000-8000-000000000006'
    );
    raise exception 'R17f se pudo repartir Landing contra el turno guardado';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'R17g reparto contra turno devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;

  if exists (
    select 1
    from crm.leads
    where id = '18000000-0000-4000-8000-000000000001'
      and (asignado_supervisor_id is not null or vendedor_id is not null)
  ) then
    raise exception 'R17h el rechazo contra turno movio el lead';
  end if;

  begin
    perform crm.guardar_agenda_reparto_diaria(
      v_hoy,
      '17000000-0000-4000-8000-000000000002',
      '17000000-0000-4000-8000-000000000002'
    );
    raise exception 'R17d la agenda acepto la misma supervisora para ambos orígenes';
  exception
    when others then
      v_sqlstate := SQLSTATE;
      if v_sqlstate <> '22023' then
        raise exception 'R17e agenda invalida devolvio % en vez de 22023', v_sqlstate;
      end if;
  end;
end;
$test$;

-- ── R5: camino feliz — el lead entra a la bandeja, sin vendedor ─────────────
do $test$
declare
  v_res jsonb;
begin
  v_res := crm.repartir_lead(
    '18000000-0000-4000-8000-000000000001',
    '17000000-0000-4000-8000-000000000002');

  if v_res->>'asignado_supervisor_id' <> '17000000-0000-4000-8000-000000000002' then
    raise exception 'R18 la RPC no devolvio el supervisor destino';
  end if;
end;
$test$;
reset role;

do $test$
declare
  v_sup uuid;
  v_vend uuid;
begin
  select asignado_supervisor_id, vendedor_id into v_sup, v_vend
  from crm.leads where id = '18000000-0000-4000-8000-000000000001';

  if v_sup <> '17000000-0000-4000-8000-000000000002' or v_vend is not null then
    raise exception 'R19 tenencia incorrecta tras el reparto (sup=%, vend=%)', v_sup, v_vend;
  end if;

  -- La actividad la escribe el trigger, acreditando a la coordinadora.
  if not exists (
    select 1 from crm.actividades
    where lead_id = '18000000-0000-4000-8000-000000000001'
      and creado_por = '17000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'R20 no quedo traza del movimiento acreditada a la coordinadora';
  end if;

  -- El parqueo a bandeja NO abre episodio en el ledger (por diseno).
  if exists (
    select 1 from crm.lead_asignaciones
    where lead_id = '18000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'R21 el parqueo a bandeja abrio un episodio de ledger';
  end if;

  -- Ya no esta en la cola: repartirlo otra vez debe fallar.
  if exists (
    select 1 from crm.leads
    where id = '18000000-0000-4000-8000-000000000001'
      and vendedor_id is null and asignado_supervisor_id is null
  ) then
    raise exception 'R22 el lead sigue en la cola global tras repartirlo';
  end if;
end;
$test$;

-- ── R5-bis: historial de derivaciones, sin abrir SELECT sobre leads ─────────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_agenda jsonb;
begin
  if not exists (
    select 1
    from crm.historial_derivaciones()
    where lead_id = '18000000-0000-4000-8000-000000000001'
      and movimiento = 'entra_bandeja'
      and responsable_anterior = 'Sin asignar'
      and responsable_nuevo = 'Bandeja de REPARTO SUPERVISOR'
      and derivado_por_nombre = 'REPARTO COORDINADORA'
  ) then
    raise exception 'R23 el historial no devolvió la derivación a la bandeja';
  end if;

  if exists (
    select 1
    from crm.historial_derivaciones() h
    where to_jsonb(h) ?| array['telefono', 'correo', 'dni', 'nota']
  ) then
    raise exception 'R24 el historial expuso una columna de contacto o nota';
  end if;

  -- Repetir el mismo turno después de las entregas es idempotente.
  perform crm.guardar_agenda_reparto_diaria(
    v_hoy,
    '17000000-0000-4000-8000-000000000002',
    '17000000-0000-4000-8000-000000000006'
  );

  -- Después de guardado, ese carril sí queda congelado por la evidencia real.
  begin
    perform crm.guardar_agenda_reparto_diaria(
      v_hoy,
      '17000000-0000-4000-8000-000000000006',
      '17000000-0000-4000-8000-000000000002'
    );
    raise exception 'R24a la agenda permitió cambiar Landing después de repartir';
  exception
    when sqlstate '22023' then null;
  end;

  v_agenda := crm.agenda_reparto_diaria(v_hoy, 1);
  if not exists (
    select 1
    from jsonb_to_recordset(v_agenda->'dias') as d(fecha date, asignaciones jsonb)
    cross join lateral jsonb_to_recordset(d.asignaciones) as a(
      origen text, supervisor_id uuid, derivados int, fuera_turno int
    )
    where d.fecha = v_hoy
      and a.origen = 'landing'
      and a.supervisor_id = '17000000-0000-4000-8000-000000000002'
      and a.derivados = 2
      and a.fuera_turno = 1
  ) then
    raise exception 'R24b la agenda no reflejo la derivacion real de Landing';
  end if;
end;
$test$;
reset role;

-- ── R5-ter: foto compacta de distribución, sin abrir leads ni etapas ───────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000001', true);
set local role authenticated;
do $test$
declare
  v_panel jsonb;
  v_referido jsonb;
  v_walking jsonb;
  v_analista jsonb;
begin
  v_panel := crm.panel_distribucion_reparto();
  if coalesce((v_panel->>'total_leads')::int, -1) <> 5 then
    raise exception 'R24a panel debio contar 5 leads activos distribuidos, devolvio %', v_panel->>'total_leads';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(v_panel->'supervisores') as x(perfil_id uuid, total_leads int)
    where x.perfil_id = '17000000-0000-4000-8000-000000000002'
      and x.total_leads = 4
  ) then
    raise exception 'R24b el total del supervisor no suma su bandeja y la de sus analistas';
  end if;

  if not exists (
    select 1
    from jsonb_to_recordset(v_panel->'analistas') as x(perfil_id uuid, total_leads int)
    where x.perfil_id = '17000000-0000-4000-8000-000000000003'
      and x.total_leads = 2
  ) then
    raise exception 'R24c el total del analista debe contar solo sus asignados directos';
  end if;

  v_referido := crm.panel_distribucion_reparto(p_origen := 'referido');
  v_walking := crm.panel_distribucion_reparto(p_origen := 'oficina');
  v_analista := crm.panel_distribucion_reparto(p_analista := '17000000-0000-4000-8000-000000000003');
  if coalesce((v_referido->>'total_leads')::int, -1) <> 1
     or coalesce((v_walking->>'total_leads')::int, -1) <> 1 then
    raise exception 'R24d el panel no filtró correctamente Referido y Walking';
  end if;

  if coalesce((v_analista->>'total_leads')::int, -1) <> 2 then
    raise exception 'R24d2 al filtrar analista no deben entrar los leads de la bandeja del supervisor';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_panel->'supervisores') as x(fila)
    where x.fila ?| array['telefono', 'correo', 'dni', 'etapa', 'capacidad']
  ) or exists (
    select 1
    from jsonb_array_elements(v_panel->'analistas') as x(fila)
    where x.fila ?| array['telefono', 'correo', 'dni', 'etapa', 'capacidad']
  ) then
    raise exception 'R24e el panel expuso PII, etapas o capacidad';
  end if;
end;
$test$;
reset role;

-- ── R6: gate de rol — vendedor queda fuera de las 3 RPC ────────────────────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  begin
    perform count(*) from crm.leads_por_repartir();
    raise exception 'R25 un vendedor pudo ver la cola por repartir';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;

  begin
    perform count(*) from crm.supervisores_para_reparto();
    raise exception 'R26 un vendedor pudo listar los supervisores de reparto';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000002',
      '17000000-0000-4000-8000-000000000002');
    raise exception 'R27 un vendedor pudo repartir un lead';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform count(*) from crm.historial_derivaciones();
    raise exception 'R28 un vendedor pudo leer el historial de derivaciones';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.panel_distribucion_reparto();
    raise exception 'R28b un vendedor pudo leer el panel de distribución';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.agenda_reparto_diaria((statement_timestamp() at time zone 'America/Lima')::date, 1);
    raise exception 'R28c un vendedor pudo leer la agenda de reparto';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.guardar_agenda_reparto_diaria(
      (statement_timestamp() at time zone 'America/Lima')::date,
      '17000000-0000-4000-8000-000000000002',
      '17000000-0000-4000-8000-000000000006'
    );
    raise exception 'R28d un vendedor pudo cambiar la agenda de reparto';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── R6-bis: el supervisor tampoco reparte la cola global (es tarea del coord) ─
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000002', true);
set local role authenticated;
do $test$
begin
  begin
    perform count(*) from crm.leads_por_repartir();
    raise exception 'R29 un supervisor pudo ver la cola global por repartir';
  exception
    when insufficient_privilege then null;
  end;
end;
$test$;
reset role;

-- ── R7: gerencia SI puede repartir (co-titular del gate) ────────────────────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000004', true);
set local role authenticated;
do $test$
begin
  if (select count(*) from crm.leads_por_repartir()) is null then
    raise exception 'R30 gerencia no pudo leer la cola por repartir';
  end if;
end;
$test$;
reset role;

select 'REPARTO_TX_OK' as resultado;

rollback;
