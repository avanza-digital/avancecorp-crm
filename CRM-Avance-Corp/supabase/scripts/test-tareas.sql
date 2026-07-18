-- Oraculo transaccional de crm.tareas (Agenda Fase A) — patron 4A-4C.
--
-- Se ejecuta SOLO contra un branch con la migracion 20260718180001 aplicada.
-- TODO corre en una unica transaccion que SIEMPRE se revierte: el exito es el
-- error final 'TAREAS_TX_OK' (cualquier otro error = fallo real del contrato).
-- Complementa (no reemplaza) el gate RLS con sesiones reales de test-rls.mjs.
--
-- Cubre: RLS por ambito (vendedor/supervisor/bandeja/gerencia), bloqueo de
-- cierre por UPDATE directo, contador de reprogramaciones, DELETE denegado,
-- RPC cerrar_tarea (resultado al log + siguiente encadenada), triggers de
-- coherencia (reasignacion propaga, descarte cancela) y CHECKs de dominio.

begin;

-- ── Fixtures minimos (como postgres; UUIDs fijos del oraculo) ────────────────
-- Jerarquia: G (gerencia) · S1 -> V1 · S2 -> V2. Leads: L1(V1), L2(V2), LP(parkeado S1).

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, confirmation_token, recovery_token,
                        email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
       u.email, '', now(), '', '', '', ''
from (values
  ('aaaa0000-0000-4000-8000-000000000001'::uuid, 'oraculo-g@test.local'),
  ('aaaa0000-0000-4000-8000-000000000002'::uuid, 'oraculo-s1@test.local'),
  ('aaaa0000-0000-4000-8000-000000000003'::uuid, 'oraculo-s2@test.local'),
  ('aaaa0000-0000-4000-8000-000000000004'::uuid, 'oraculo-v1@test.local'),
  ('aaaa0000-0000-4000-8000-000000000005'::uuid, 'oraculo-v2@test.local')
) as u(id, email);

insert into public.perfiles (id, nombre_completo, rol, activo)
values
  ('aaaa0000-0000-4000-8000-000000000001', 'ORACULO GERENTE',    'comercial', true),
  ('aaaa0000-0000-4000-8000-000000000002', 'ORACULO SUPERVISOR1','comercial', true),
  ('aaaa0000-0000-4000-8000-000000000003', 'ORACULO SUPERVISOR2','comercial', true),
  ('aaaa0000-0000-4000-8000-000000000004', 'ORACULO VENDEDOR1',  'comercial', true),
  ('aaaa0000-0000-4000-8000-000000000005', 'ORACULO VENDEDOR2',  'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('aaaa0000-0000-4000-8000-000000000001', 'gerencia',   null, true),
  ('aaaa0000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('aaaa0000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('aaaa0000-0000-4000-8000-000000000004', 'vendedor',   'aaaa0000-0000-4000-8000-000000000002', true),
  ('aaaa0000-0000-4000-8000-000000000005', 'vendedor',   'aaaa0000-0000-4000-8000-000000000003', true);

insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda,
                       vendedor_id, asignado_supervisor_id, creado_por)
values
  ('bbbb0000-0000-4000-8000-000000000001', 'ORACULO LEAD V1', '+51911000001', 'oficina',
   10000, 'PEN', 'aaaa0000-0000-4000-8000-000000000004', null,
   'aaaa0000-0000-4000-8000-000000000004'),
  ('bbbb0000-0000-4000-8000-000000000002', 'ORACULO LEAD V2', '+51911000002', 'oficina',
   20000, 'USD', 'aaaa0000-0000-4000-8000-000000000005', null,
   'aaaa0000-0000-4000-8000-000000000005'),
  ('bbbb0000-0000-4000-8000-000000000003', 'ORACULO LEAD PARKEADO', '+51911000003', 'oficina',
   30000, 'PEN', null, 'aaaa0000-0000-4000-8000-000000000002',
   'aaaa0000-0000-4000-8000-000000000002');

-- Tareas: la tenencia la deriva el trigger del lead (no se declara aqui).
insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
values
  ('cccc0000-0000-4000-8000-000000000001', 'bbbb0000-0000-4000-8000-000000000001',
   'llamada', 'ORACULO TAREA V1', now() + interval '2 hours',
   'aaaa0000-0000-4000-8000-000000000004'),
  ('cccc0000-0000-4000-8000-000000000002', 'bbbb0000-0000-4000-8000-000000000002',
   'whatsapp', 'ORACULO TAREA V2', now() + interval '3 hours',
   'aaaa0000-0000-4000-8000-000000000005'),
  ('cccc0000-0000-4000-8000-000000000003', 'bbbb0000-0000-4000-8000-000000000003',
   'tarea', 'ORACULO TAREA BANDEJA', now() + interval '4 hours',
   'aaaa0000-0000-4000-8000-000000000002');

-- La derivacion de tenencia quedo coherente con el lead.
do $$
begin
  if (select vendedor_id from crm.tareas where id='cccc0000-0000-4000-8000-000000000001')
     is distinct from 'aaaa0000-0000-4000-8000-000000000004'::uuid then
    raise exception 'FALLO fixtures: la tarea V1 no derivo la tenencia del lead';
  end if;
  if (select vendedor_id from crm.tareas where id='cccc0000-0000-4000-8000-000000000003') is not null
     or (select asignado_supervisor_id from crm.tareas where id='cccc0000-0000-4000-8000-000000000003')
        is distinct from 'aaaa0000-0000-4000-8000-000000000002'::uuid then
    raise exception 'FALLO fixtures: la tarea de bandeja no derivo el parkeo';
  end if;
end $$;

-- ── Sesion V1 (vendedor): ve SOLO lo suyo ────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaa0000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaa0000-0000-4000-8000-000000000004', true);

do $$
declare v_n int;
begin
  select count(*) into v_n from crm.tareas where titulo like 'ORACULO %';
  if v_n <> 1 then
    raise exception 'FALLO RLS V1: esperaba 1 tarea visible, vio %', v_n;
  end if;
  if not exists (select 1 from crm.tareas where id='cccc0000-0000-4000-8000-000000000001') then
    raise exception 'FALLO RLS V1: no ve SU tarea';
  end if;
end $$;

-- V1 no alcanza la tarea de V2 por UPDATE (0 filas, sin error: RLS la oculta).
do $$
declare v_n int;
begin
  update crm.tareas set titulo = 'HACKEADA'
   where id = 'cccc0000-0000-4000-8000-000000000002';
  get diagnostics v_n = row_count;
  if v_n <> 0 then
    raise exception 'FALLO RLS V1: pudo actualizar una tarea ajena';
  end if;
end $$;

-- Completar por UPDATE directo esta vetado (va por la RPC).
do $$
begin
  begin
    update crm.tareas set estado = 'completada'
     where id = 'cccc0000-0000-4000-8000-000000000001';
    raise exception 'FALLO trigger: permitio completar por UPDATE directo';
  exception when raise_exception then
    if sqlerrm like 'FALLO%' then raise; end if; -- el veto real re-lanza otro texto
  end;
end $$;

-- Reprogramar SI, y el contador lo lleva el sistema.
do $$
declare v_rep smallint;
begin
  update crm.tareas set vence_en = vence_en + interval '1 day'
   where id = 'cccc0000-0000-4000-8000-000000000001';
  select reprogramaciones into v_rep from crm.tareas
   where id = 'cccc0000-0000-4000-8000-000000000001';
  if v_rep <> 1 then
    raise exception 'FALLO reprogramaciones: esperaba 1, hay %', v_rep;
  end if;
end $$;

-- DELETE: nadie del API (grant ausente → insufficient_privilege).
do $$
begin
  begin
    delete from crm.tareas where id = 'cccc0000-0000-4000-8000-000000000001';
    raise exception 'FALLO grants: DELETE permitido a authenticated';
  exception when insufficient_privilege then
    null; -- correcto
  end;
end $$;

-- RPC cerrar_tarea: completa + registra en el log + agenda la siguiente.
do $$
declare
  v_res jsonb;
  v_sig uuid;
begin
  v_res := crm.cerrar_tarea(
    'cccc0000-0000-4000-8000-000000000001',
    'completada',
    'llamada_realizada',
    'ORACULO resultado',
    jsonb_build_object(
      'tipo', 'whatsapp',
      'titulo', 'ORACULO SIGUIENTE',
      'vence_en', (now() + interval '3 days')::text
    )
  );
  if coalesce(v_res->>'ok','') <> 'true' then
    raise exception 'FALLO RPC: no devolvio ok';
  end if;
  if (select estado from crm.tareas where id='cccc0000-0000-4000-8000-000000000001') <> 'completada' then
    raise exception 'FALLO RPC: la tarea no quedo completada';
  end if;
  if not exists (
    select 1 from crm.actividades
    where lead_id = 'bbbb0000-0000-4000-8000-000000000001'
      and tipo = 'llamada_realizada' and detalle = 'ORACULO resultado'
  ) then
    raise exception 'FALLO RPC: el resultado no llego al log de actividades';
  end if;
  v_sig := (v_res->>'siguiente_id')::uuid;
  if v_sig is null or not exists (
    select 1 from crm.tareas
    where id = v_sig and estado = 'pendiente' and titulo = 'ORACULO SIGUIENTE'
      and vendedor_id = 'aaaa0000-0000-4000-8000-000000000004'
  ) then
    raise exception 'FALLO RPC: la tarea siguiente no quedo pendiente con la tenencia del lead';
  end if;
  -- Una cerrada es inmutable.
  begin
    update crm.tareas set titulo = 'REABIERTA'
     where id = 'cccc0000-0000-4000-8000-000000000001';
    raise exception 'FALLO inmutabilidad: una tarea cerrada acepto UPDATE';
  exception when raise_exception then
    if sqlerrm like 'FALLO%' then raise; end if;
  end;
end $$;

reset role;

-- ── Sesion S1 (supervisor): subarbol + bandeja, jamas el otro subarbol ───────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaa0000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaa0000-0000-4000-8000-000000000002', true);

do $$
declare v_n int;
begin
  -- Ve: la completada de V1, la SIGUIENTE de V1 y su bandeja = 3. Jamas la de V2.
  select count(*) into v_n from crm.tareas where titulo like 'ORACULO %';
  if v_n <> 3 then
    raise exception 'FALLO RLS S1: esperaba 3 tareas visibles, vio %', v_n;
  end if;
  if exists (select 1 from crm.tareas where id='cccc0000-0000-4000-8000-000000000002') then
    raise exception 'FALLO RLS S1: ve el subarbol ajeno';
  end if;
end $$;

reset role;

-- ── Sesion G (gerencia): ve todo ─────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"aaaa0000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'aaaa0000-0000-4000-8000-000000000001', true);

do $$
declare v_n int;
begin
  select count(*) into v_n from crm.tareas where titulo like 'ORACULO %';
  if v_n <> 4 then
    raise exception 'FALLO RLS gerencia: esperaba 4 tareas, vio %', v_n;
  end if;
end $$;

reset role;

-- ── Coherencia con el ciclo de vida del lead (como postgres) ─────────────────

-- Reasignar L2: V2 -> V1 debe arrastrar su tarea pendiente.
update crm.leads set vendedor_id = 'aaaa0000-0000-4000-8000-000000000004'
 where id = 'bbbb0000-0000-4000-8000-000000000002';
do $$
begin
  if (select vendedor_id from crm.tareas where id='cccc0000-0000-4000-8000-000000000002')
     is distinct from 'aaaa0000-0000-4000-8000-000000000004'::uuid then
    raise exception 'FALLO sync: la tarea pendiente no siguio al lead reasignado';
  end if;
end $$;

-- Descartar L1 debe cancelar su tarea pendiente (la SIGUIENTE creada por la RPC).
update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes'
 where id = 'bbbb0000-0000-4000-8000-000000000001';
do $$
begin
  if exists (
    select 1 from crm.tareas
    where lead_id = 'bbbb0000-0000-4000-8000-000000000001' and estado = 'pendiente'
  ) then
    raise exception 'FALLO sync: un lead descartado dejo tareas pendientes vivas';
  end if;
end $$;

-- ── CHECKs de dominio ────────────────────────────────────────────────────────
do $$
begin
  -- Sin sujeto.
  begin
    insert into crm.tareas (tipo, titulo, vence_en)
    values ('tarea', 'ORACULO SIN SUJETO', now() + interval '1 day');
    raise exception 'FALLO CHECK: acepto tarea sin lead ni perfil';
  exception when check_violation then null;
  end;
  -- Tipo invalido.
  begin
    insert into crm.tareas (lead_id, tipo, titulo, vence_en)
    values ('bbbb0000-0000-4000-8000-000000000003', 'email', 'ORACULO TIPO MALO',
            now() + interval '1 day');
    raise exception 'FALLO CHECK: acepto tipo de tarea invalido';
  exception when check_violation then null;
  end;
end $$;

-- Columnas legales del lead presentes y con default correcto.
do $$
begin
  if (select no_contactar from crm.leads where id='bbbb0000-0000-4000-8000-000000000003') <> false then
    raise exception 'FALLO legal: no_contactar sin default false';
  end if;
end $$;

-- ── Exito = este error (revierte TODO el oraculo) ────────────────────────────
do $$ begin raise exception 'TAREAS_TX_OK'; end $$;
