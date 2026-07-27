-- Oraculo transaccional de crm.metricas_agenda_fn (Fase F agenda) — patron 4A-4C.
--
-- Se ejecuta SOLO contra un branch con 20260719013000 aplicada. TODO corre en
-- una unica transaccion que SIEMPRE se revierte: el exito es el error final
-- 'METRICAS_AGENDA_TX_OK' (cualquier otro error = fallo real).
--
-- Cubre: valores exactos por vendedor (toques sin 'nota', cierres del periodo
-- por actualizado_en, pct_completadas, reprogramaciones, foto de pendientes/
-- vencidas, leads sin accion), recorte de ambito (vendedor=el, supervisor=su
-- subarbol, gerencia=todos), validacion de periodo (22023), caller sin sesion
-- o fuera de crm.equipo (42501) y EXECUTE denegado a anon.

begin;

-- ── Fixtures (como postgres; UUIDs fijos del oraculo) ────────────────────────
-- G (gerencia) · S1 → V1 · S2 → V2. El periodo del test: ultimos 7 dias Lima.

insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, confirmation_token, recovery_token,
                        email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
       u.email, '', now(), '', '', '', ''
from (values
  ('bbbb1111-0000-4000-8000-000000000001'::uuid, 'oraculo-agf-g@test.local'),
  ('bbbb1111-0000-4000-8000-000000000002'::uuid, 'oraculo-agf-s1@test.local'),
  ('bbbb1111-0000-4000-8000-000000000003'::uuid, 'oraculo-agf-s2@test.local'),
  ('bbbb1111-0000-4000-8000-000000000004'::uuid, 'oraculo-agf-v1@test.local'),
  ('bbbb1111-0000-4000-8000-000000000005'::uuid, 'oraculo-agf-v2@test.local')
) as u(id, email);

insert into public.perfiles (id, nombre_completo, rol, activo)
values
  ('bbbb1111-0000-4000-8000-000000000001', 'ORACULO AGF GERENCIA',   'comercial', true),
  ('bbbb1111-0000-4000-8000-000000000002', 'ORACULO AGF SUP UNO',    'comercial', true),
  ('bbbb1111-0000-4000-8000-000000000003', 'ORACULO AGF SUP DOS',    'comercial', true),
  ('bbbb1111-0000-4000-8000-000000000004', 'ORACULO AGF VEND UNO',   'comercial', true),
  ('bbbb1111-0000-4000-8000-000000000005', 'ORACULO AGF VEND DOS',   'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('bbbb1111-0000-4000-8000-000000000001', 'gerencia',   null, true),
  ('bbbb1111-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('bbbb1111-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('bbbb1111-0000-4000-8000-000000000004', 'vendedor', 'bbbb1111-0000-4000-8000-000000000002', true),
  ('bbbb1111-0000-4000-8000-000000000005', 'vendedor', 'bbbb1111-0000-4000-8000-000000000003', true);

-- Filas de datos con triggers APAGADOS (replica): el oraculo fija tenencia,
-- estados cerrados, contadores y timestamps a mano, como una historia ya
-- ocurrida. Los CHECK siguen vigentes (no son triggers).
--
-- ⚠️ Y ESA FRASE TIENE DIENTES: apagar los triggers apaga los SELLOS, no las
-- restricciones. Toda columna que normalmente rellene un BEFORE hay que darla
-- aqui A MANO, o el CHECK correspondiente tumba los fixtures antes de la
-- primera asercion. Paso de verdad: `20260726151751` anadio
-- `tareas_cancelada_por_valida` y este oraculo, que no se re-corrio en aquel
-- ciclo, quedo roto en silencio hasta el dia siguiente.
set local session_replication_role = replica;

insert into crm.leads (id, nombre_completo, telefono, etapa, origen,
                       monto_estimado, moneda, vendedor_id, activo, creado_en)
values
  -- L1 de V1: el lead de trabajo — carga las tareas del oraculo (incluida la
  -- pendiente T4, asi que NO cuenta como sin accion).
  ('cccc1111-0000-4000-8000-000000000001', 'ORACULO AGF LEAD UNO', '+51900000701',
   'contactado', 'referido', 10000, 'PEN',
   'bbbb1111-0000-4000-8000-000000000004', true, now() - interval '10 days'),
  -- L2 de V2: abierto CON tarea pendiente → no cuenta como sin accion.
  ('cccc1111-0000-4000-8000-000000000002', 'ORACULO AGF LEAD DOS', '+51900000702',
   'nuevo', 'landing', 20000, 'PEN',
   'bbbb1111-0000-4000-8000-000000000005', true, now() - interval '3 days'),
  -- L3 de V1: abierto y SIN ninguna tarea → leads_sin_accion de V1 = 1.
  ('cccc1111-0000-4000-8000-000000000003', 'ORACULO AGF LEAD TRES', '+51900000703',
   'propuesta_enviada', 'oficina', 30000, 'PEN',
   'bbbb1111-0000-4000-8000-000000000004', true, now() - interval '6 days');

insert into crm.tareas (id, lead_id, vendedor_id, asignado_supervisor_id, tipo,
                        titulo, vence_en, estado, cancelada_por, reprogramaciones,
                        activo, creado_en, actualizado_en)
values
  -- V1 · cerradas DENTRO del periodo (actualizado_en = instante del cierre):
  ('dddd1111-0000-4000-8000-000000000001', 'cccc1111-0000-4000-8000-000000000001',
   'bbbb1111-0000-4000-8000-000000000004', 'bbbb1111-0000-4000-8000-000000000002',
   'llamada', 'ORACULO T1 completada', now() - interval '2 days', 'completada',
   null, 0, true, now() - interval '3 days', now() - interval '2 days'),
  ('dddd1111-0000-4000-8000-000000000002', 'cccc1111-0000-4000-8000-000000000001',
   'bbbb1111-0000-4000-8000-000000000004', 'bbbb1111-0000-4000-8000-000000000002',
   'reunion', 'ORACULO T2 no asistio', now() - interval '2 days', 'no_show',
   null, 0, true, now() - interval '4 days', now() - interval '2 days'),
  -- V1 · cancelada FUERA del periodo: no debe contar.
  -- `cancelada_por` EXPLICITO y no heredado del trigger: este bloque corre con
  -- `session_replication_role = replica`, asi que el BEFORE que sella la
  -- etiqueta NO dispara — pero el CHECK `tareas_cancelada_por_valida`
  -- (20260726151751) SI sigue vigente y exige que toda cancelada la lleve. Sin
  -- esta palabra el oraculo revienta en los FIXTURES, antes de llegar a una sola
  -- asercion. 'sistema' es la verdad literal: aqui no hay ningun asesor
  -- decidiendo nada, es una historia sembrada a mano.
  ('dddd1111-0000-4000-8000-000000000003', 'cccc1111-0000-4000-8000-000000000001',
   'bbbb1111-0000-4000-8000-000000000004', 'bbbb1111-0000-4000-8000-000000000002',
   'tarea', 'ORACULO T3 vieja', now() - interval '30 days', 'cancelada',
   'sistema', 0, true, now() - interval '31 days', now() - interval '30 days'),
  -- V1 · pendiente VENCIDA con 2 reprogramaciones (tocada ayer):
  ('dddd1111-0000-4000-8000-000000000004', 'cccc1111-0000-4000-8000-000000000001',
   'bbbb1111-0000-4000-8000-000000000004', 'bbbb1111-0000-4000-8000-000000000002',
   'llamada', 'ORACULO T4 vencida', now() - interval '1 hour', 'pendiente',
   null, 2, true, now() - interval '2 days', now() - interval '1 day'),
  -- V2 · pendiente futura sobre L2 (creada en el periodo):
  ('dddd1111-0000-4000-8000-000000000005', 'cccc1111-0000-4000-8000-000000000002',
   'bbbb1111-0000-4000-8000-000000000005', 'bbbb1111-0000-4000-8000-000000000003',
   'whatsapp', 'ORACULO T5 futura', now() + interval '2 days', 'pendiente',
   null, 0, true, now() - interval '1 day', now() - interval '1 day');

insert into crm.actividades (id, lead_id, tipo, detalle, creado_por, creado_en)
values
  -- V1 · 3 toques en el periodo + 1 'nota' (NO es toque) + 1 toque FUERA:
  ('eeee1111-0000-4000-8000-000000000001', 'cccc1111-0000-4000-8000-000000000001',
   'llamada_realizada', 'oraculo toque 1',
   'bbbb1111-0000-4000-8000-000000000004', now() - interval '2 days'),
  ('eeee1111-0000-4000-8000-000000000002', 'cccc1111-0000-4000-8000-000000000001',
   'whatsapp_enviado', 'oraculo toque 2',
   'bbbb1111-0000-4000-8000-000000000004', now() - interval '2 days'),
  ('eeee1111-0000-4000-8000-000000000003', 'cccc1111-0000-4000-8000-000000000001',
   'reunion_realizada', 'oraculo toque 3',
   'bbbb1111-0000-4000-8000-000000000004', now() - interval '2 days'),
  ('eeee1111-0000-4000-8000-000000000004', 'cccc1111-0000-4000-8000-000000000001',
   'nota', 'oraculo nota (no es toque)',
   'bbbb1111-0000-4000-8000-000000000004', now() - interval '2 days'),
  ('eeee1111-0000-4000-8000-000000000005', 'cccc1111-0000-4000-8000-000000000001',
   'llamada_realizada', 'oraculo toque viejo (fuera del periodo)',
   'bbbb1111-0000-4000-8000-000000000004', now() - interval '30 days');

set local session_replication_role = default;

-- ── Sesion S1 (supervisor): su subarbol EXACTO, con los valores de V1 ────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbb1111-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'bbbb1111-0000-4000-8000-000000000002', true);

do $$
declare
  v jsonb;
  fila jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v := crm.metricas_agenda_fn(v_hoy - 7, v_hoy);

  if jsonb_array_length(v->'vendedores') <> 2 then
    raise exception 'FALLO ambito S1: esperaba 2 filas (S1+V1), hay % — %',
      jsonb_array_length(v->'vendedores'), v->'vendedores';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v->'vendedores') e
    where e->>'vendedor_id' in ('bbbb1111-0000-4000-8000-000000000003',
                                'bbbb1111-0000-4000-8000-000000000005')
  ) then
    raise exception 'FALLO ambito S1: ve el subarbol de S2';
  end if;

  select e into fila from jsonb_array_elements(v->'vendedores') e
   where e->>'vendedor_id' = 'bbbb1111-0000-4000-8000-000000000004';
  if fila is null then
    raise exception 'FALLO S1: no encontro a V1 en el payload';
  end if;
  if (fila->>'toques')::int <> 3 then
    raise exception 'FALLO toques V1: esperaba 3 (la nota y el toque viejo no cuentan), hay %', fila->>'toques';
  end if;
  if (fila->>'reuniones_realizadas')::int <> 1 then
    raise exception 'FALLO reuniones_realizadas V1: esperaba 1, hay %', fila->>'reuniones_realizadas';
  end if;
  if (fila->>'completadas')::int <> 1 or (fila->>'no_asistio')::int <> 1
     or (fila->>'canceladas')::int <> 0 then
    raise exception 'FALLO cierres V1: esperaba 1/1/0 (la cancelada vieja no cuenta), hay %/%/%',
      fila->>'completadas', fila->>'no_asistio', fila->>'canceladas';
  end if;
  if (fila->>'pct_completadas')::numeric <> 50 then
    raise exception 'FALLO pct_completadas V1: esperaba 50, hay %', fila->>'pct_completadas';
  end if;
  -- Separacion asesor/sistema (20260726151751). Con 0 canceladas en el periodo
  -- las dos mitades son 0, pero las CLAVES tienen que estar: el contrato Valibot
  -- del front las declara opcionales solo para sobrevivir al desfase de deploy,
  -- no porque el servidor pueda dejar de mandarlas.
  if fila->'canceladas_asesor' is null or fila->'canceladas_sistema' is null then
    raise exception 'FALLO desglose V1: faltan canceladas_asesor/canceladas_sistema en el payload';
  end if;
  if (fila->>'canceladas_asesor')::int + (fila->>'canceladas_sistema')::int
     <> (fila->>'canceladas')::int then
    raise exception 'FALLO desglose V1: las dos mitades (%/%) no suman el total %',
      fila->>'canceladas_asesor', fila->>'canceladas_sistema', fila->>'canceladas';
  end if;
  -- Anulacion AJENA (20260727032429): la parte de canceladas_asesor que firmo
  -- OTRO. Misma regla que arriba — la clave tiene que ESTAR aunque valga 0.
  if fila->'canceladas_ajenas' is null then
    raise exception 'FALLO desglose V1: falta canceladas_ajenas en el payload';
  end if;
  -- Nunca puede superar a las humanas: es un subconjunto suyo. Si esto salta,
  -- el `is distinct from` del CTE `cierres` se rompio y el denominador de
  -- pct_completadas se estaria calculando en negativo.
  if (fila->>'canceladas_ajenas')::int > (fila->>'canceladas_asesor')::int then
    raise exception 'FALLO desglose V1: las ajenas (%) no pueden superar a las humanas (%)',
      fila->>'canceladas_ajenas', fila->>'canceladas_asesor';
  end if;
  if (fila->>'reprogramaciones')::int <> 2 then
    raise exception 'FALLO reprogramaciones V1: esperaba 2, hay %', fila->>'reprogramaciones';
  end if;
  if (fila->>'pendientes')::int <> 1 or (fila->>'vencidas')::int <> 1 then
    raise exception 'FALLO foto V1: esperaba pendientes=1 y vencidas=1, hay %/%',
      fila->>'pendientes', fila->>'vencidas';
  end if;
  if (fila->>'leads_sin_accion')::int <> 1 then
    raise exception 'FALLO leads_sin_accion V1: esperaba 1 (L3 sin ninguna tarea; L1 tiene la pendiente T4), hay %',
      fila->>'leads_sin_accion';
  end if;
  if (fila->>'tareas_creadas')::int <> 3 then
    raise exception 'FALLO tareas_creadas V1: esperaba 3 (T1,T2,T4; T3 es vieja), hay %', fila->>'tareas_creadas';
  end if;
  if (fila->>'reuniones_agendadas')::int <> 1 then
    raise exception 'FALLO reuniones_agendadas V1: esperaba 1 (T2), hay %', fila->>'reuniones_agendadas';
  end if;
end $$;

reset role;

-- ── Sesion V1 (vendedor): solo el mismo ──────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbb1111-0000-4000-8000-000000000004","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'bbbb1111-0000-4000-8000-000000000004', true);

do $$
declare
  v jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v := crm.metricas_agenda_fn(v_hoy - 7, v_hoy);
  if jsonb_array_length(v->'vendedores') <> 1
     or (v->'vendedores'->0->>'vendedor_id') <> 'bbbb1111-0000-4000-8000-000000000004' then
    raise exception 'FALLO ambito V1: esperaba verse solo a si mismo — %', v->'vendedores';
  end if;

  -- Validacion de periodo: desde > hasta y hasta futuro → 22023.
  begin
    perform crm.metricas_agenda_fn(v_hoy, v_hoy - 1);
    raise exception 'FALLO validacion: acepto desde > hasta';
  exception when sqlstate '22023' then null;
  end;
  begin
    perform crm.metricas_agenda_fn(v_hoy, v_hoy + 1);
    raise exception 'FALLO validacion: acepto un hasta futuro';
  exception when sqlstate '22023' then null;
  end;
end $$;

reset role;

-- ── Sesion G (gerencia): los 4 con cartera posible (sin la propia gerencia) ──
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"bbbb1111-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', 'bbbb1111-0000-4000-8000-000000000001', true);

do $$
declare
  v jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v := crm.metricas_agenda_fn(v_hoy - 7, v_hoy);
  if (
    select count(*) from jsonb_array_elements(v->'vendedores') e
    where (e->>'vendedor_id') like 'bbbb1111-%'
  ) <> 4 then
    raise exception 'FALLO ambito G: esperaba a los 4 del oraculo (S1,S2,V1,V2) — %', v->'vendedores';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v->'vendedores') e
    where e->>'vendedor_id' = 'bbbb1111-0000-4000-8000-000000000001'
  ) then
    raise exception 'FALLO universo: la gerencia no lleva cartera y no debe listarse';
  end if;
end $$;

reset role;

-- ── Sin sesion valida: 42501 ─────────────────────────────────────────────────
set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '', true);

do $$
declare v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  begin
    perform crm.metricas_agenda_fn(v_hoy - 7, v_hoy);
    raise exception 'FALLO gate: acepto un caller sin auth.uid()';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- ── anon: sin EXECUTE siquiera ───────────────────────────────────────────────
set local role anon;

do $$
declare v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  begin
    perform crm.metricas_agenda_fn(v_hoy - 7, v_hoy);
    raise exception 'FALLO grants: anon pudo ejecutar la RPC';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;

-- Exito = este error exacto (revierte TODA la transaccion; cero fixtures).
do $$ begin raise exception 'METRICAS_AGENDA_TX_OK'; end $$;
