-- Oraculo transaccional autocontenido del reparto de la cola (C1, coordinador).
-- Exito = token REPARTO_TX_OK; todo queda en rollback.
--
-- Cubre: gate de rol de las 3 RPC, proyeccion sin PII, filtro legal de la cola,
-- el camino feliz (bandeja + vendedor null), el veto legal P0429 con oraculo de
-- estado, destino invalido, lead fuera de cola y el aislamiento de las
-- superficies adyacentes. La CARRERA de reparto NO se prueba aqui (necesita dos
-- sesiones simultaneas): la cubre testReparto de test-rls.mjs.

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
  ('17000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'rep-cliente@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('17000000-0000-4000-8000-000000000001', 'Reparto Coordinadora', 'rep-coord@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000002', 'Reparto Supervisor', 'rep-sup@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000003', 'Reparto Vendedor', 'rep-vend@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000004', 'Reparto Gerencia', 'rep-ger@test.invalid', 'comercial', true),
  ('17000000-0000-4000-8000-000000000005', 'Reparto Cliente', 'rep-cliente@test.invalid', 'cliente', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('17000000-0000-4000-8000-000000000001', 'coordinador', null, true),
  ('17000000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('17000000-0000-4000-8000-000000000003', 'vendedor', '17000000-0000-4000-8000-000000000002', true),
  ('17000000-0000-4000-8000-000000000004', 'gerencia', null, true);

-- Cola global: ambos-null (se siembra como owner, sin pasar por la RLS).
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, no_contactar, creado_por
)
values
  ('18000000-0000-4000-8000-000000000001', 'REPARTO SQL CONTACTABLE', '999111001', 'nuevo', 'otro', 12000, 'PEN', null, null, true, false, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000002', 'REPARTO SQL NO INSISTA', '999111002', 'nuevo', 'otro', 8000, 'PEN', null, null, true, true, '17000000-0000-4000-8000-000000000002'),
  ('18000000-0000-4000-8000-000000000003', 'REPARTO SQL CON DUENO', '999111003', 'nuevo', 'otro', 5000, 'USD', '17000000-0000-4000-8000-000000000003', null, true, false, '17000000-0000-4000-8000-000000000002');

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
  if (select count(*) from crm.supervisores_para_reparto()) <> 1 then
    raise exception 'R06 supervisores_para_reparto no devolvio al unico supervisor activo';
  end if;
end;
$test$;

-- ── R2: superficies adyacentes cerradas para el rol nuevo ───────────────────
do $test$
begin
  if exists (select 1 from crm.clientes_basicos) then
    raise exception 'R07 la coordinadora ve PII de clientes (clientes_basicos)';
  end if;

  if exists (select 1 from crm.objetivos) then
    raise exception 'R08 la coordinadora ve las metas comerciales';
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

-- ── R6: gate de rol — vendedor queda fuera de las 3 RPC ────────────────────
select set_config('request.jwt.claim.sub', '17000000-0000-4000-8000-000000000003', true);
set local role authenticated;
do $test$
begin
  begin
    perform count(*) from crm.leads_por_repartir();
    raise exception 'R23 un vendedor pudo ver la cola por repartir';
  exception
    when insufficient_privilege then null;  -- 42501 esperado
  end;

  begin
    perform count(*) from crm.supervisores_para_reparto();
    raise exception 'R24 un vendedor pudo listar los supervisores de reparto';
  exception
    when insufficient_privilege then null;
  end;

  begin
    perform crm.repartir_lead(
      '18000000-0000-4000-8000-000000000002',
      '17000000-0000-4000-8000-000000000002');
    raise exception 'R25 un vendedor pudo repartir un lead';
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
    raise exception 'R26 un supervisor pudo ver la cola global por repartir';
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
    raise exception 'R27 gerencia no pudo leer la cola por repartir';
  end if;
end;
$test$;
reset role;

select 'REPARTO_TX_OK' as resultado;

rollback;
