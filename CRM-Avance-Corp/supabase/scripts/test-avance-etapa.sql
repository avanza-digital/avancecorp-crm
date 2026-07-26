-- Oraculo transaccional autocontenido del AVANCE AUTOMATICO DE ETAPA.
-- Exito = token AVANCE_TX_OK; todo queda en rollback.
--
-- Las dos invariantes centrales:
--   1. La etapa SUBE sola cuando el hecho ya ocurrio (conversacion registrada,
--      reunion agendada) — el vendedor no tiene que mover la tarjeta a mano.
--   2. La etapa NUNCA sube por algo que NO ocurrio. Ese es el pecado capital:
--      un embudo que se infla solo es peor que uno que no se mueve. Por eso la
--      mitad de las aserciones son NEGATIVAS (que NO avance).
--
-- Cubre: los 3 tipos que avanzan y los 3 que no, idempotencia, no-recursion,
-- leads cerrados/inactivos, la marca `automatico` del timeline, las 5 guardas
-- de la reunion (tipo, rebote de no-show, fecha pasada, sin contacto previo,
-- retroceso desde propuesta_enviada), el camino server-side entero via
-- crm.cerrar_tarea, y que el avance no toque el reloj de tenencia ni el ciclo.
--
-- Solo contra un BRANCH de Supabase, nunca contra produccion.

begin;

set local lock_timeout = '5s';

-- Sembrar como sistema (auth.uid() null).
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('3a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'av-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('3a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'av-v1@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('3a000000-0000-4000-8000-000000000001', 'Avance Supervisor', 'av-sup@test.invalid', 'comercial', true),
  ('3a000000-0000-4000-8000-000000000002', 'Avance Vendedor', 'av-v1@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('3a000000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('3a000000-0000-4000-8000-000000000002', 'vendedor', '3a000000-0000-4000-8000-000000000001', true);

-- Ocho leads, todos del mismo vendedor, cada uno para un escenario.
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, activo, creado_por
)
values
  ('3b000000-0000-4000-8000-000000000001', 'Avance Conversacion', '+51900000001', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000002', 'Avance Intento', '+51900000002', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000003', 'Avance Cerrado', '+51900000003', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000004', 'Avance Reunion OK', '+51900000004', 'contactado', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000005', 'Avance Reunion Virgen', '+51900000005', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000006', 'Avance Propuesta', '+51900000006', 'propuesta_enviada', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000007', 'Avance Via RPC', '+51900000007', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-000000000008', 'Avance Inactivo', '+51900000008', 'nuevo', 'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', true, '3a000000-0000-4000-8000-000000000002');

-- Lead de la COLA GLOBAL (sin vendedor Y sin bandeja): el estado normal entre
-- el importador y el reparto de Rosa. Es el vector de C1. Se siembra como
-- sistema porque el guard de tenencia solo deja liberar a la cola a gerencia.
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, creado_por
)
values
  ('3b000000-0000-4000-8000-000000000009', 'Avance Cola Global', '+51900000009', 'nuevo',
   'referido', 1000, 'PEN', null, null, true, '3a000000-0000-4000-8000-000000000002'),
  ('3b000000-0000-4000-8000-00000000000a', 'Avance No Insista', '+51900000010', 'nuevo',
   'referido', 1000, 'PEN', '3a000000-0000-4000-8000-000000000002', null, true,
   '3a000000-0000-4000-8000-000000000002');

update crm.leads set no_contactar = true where id = '3b000000-0000-4000-8000-00000000000a';

-- El lead de la cola global llega ya "trabajado" (peor caso para C1: la guarda
-- del EXISTS de contacto real esta satisfecha y solo queda el gate de ambito).
insert into crm.actividades (lead_id, tipo, creado_por)
values ('3b000000-0000-4000-8000-000000000009', 'llamada_no_contestada',
        '3a000000-0000-4000-8000-000000000002');

-- ── V01–V03: la conversacion avanza, una sola vez, y se marca automatica ─────
do $test$
declare
  v_etapa text;
  v_n int;
  v_auto boolean;
  v_tenencia timestamptz;
  v_tenencia2 timestamptz;
  v_ciclo int;
begin
  select tenencia_desde, ciclo_actual into v_tenencia, v_ciclo
  from crm.leads where id = '3b000000-0000-4000-8000-000000000001';

  insert into crm.actividades (lead_id, tipo, detalle, creado_por)
  values ('3b000000-0000-4000-8000-000000000001', 'llamada_realizada', 'ORACULO contesto',
          '3a000000-0000-4000-8000-000000000002');

  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000001';
  if v_etapa <> 'contactado' then
    raise exception 'V01 una conversacion sobre un lead nuevo debe subirlo a contactado (quedo en %)', v_etapa;
  end if;

  select count(*) into v_n from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000001' and tipo = 'cambio_etapa';
  if v_n <> 1 then
    raise exception 'V02 el avance debe escribir EXACTAMENTE un cambio_etapa (escribio %)', v_n;
  end if;

  -- `order by` obligatorio: la actividad disparadora y su cambio_etapa nacen
  -- con el MISMO `now()` (timestamp de transaccion), asi que un SELECT INTO sin
  -- orden es no determinista en cuanto hay mas de una fila.
  -- bool_and sobre TODAS las filas: `id` es gen_random_uuid(), asi que un
  -- `order by … limit 1` desempataria al azar y no por causalidad.
  select bool_and((metadata->>'automatico')::boolean) into v_auto from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000001' and tipo = 'cambio_etapa';
  if v_auto is distinct from true then
    raise exception 'V03 el cambio_etapa automatico debe quedar marcado como tal en metadata (%)', v_auto;
  end if;

  -- IDEMPOTENCIA: dos conversaciones mas no vuelven a mover nada.
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000001', 'whatsapp_recibido', '3a000000-0000-4000-8000-000000000002'),
         ('3b000000-0000-4000-8000-000000000001', 'reunion_realizada', '3a000000-0000-4000-8000-000000000002');

  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000001';
  select count(*) into v_n from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000001' and tipo = 'cambio_etapa';
  if v_etapa <> 'contactado' or v_n <> 1 then
    raise exception 'V04 el avance no es idempotente: etapa=% cambios=%', v_etapa, v_n;
  end if;

  -- El avance NO puede tocar el reloj del vendedor ni el contador de ciclos:
  -- son otra invariante (ver test-tenencia.sql) y esto es una regresion facil.
  select tenencia_desde, ciclo_actual into v_tenencia2, v_n
  from crm.leads where id = '3b000000-0000-4000-8000-000000000001';
  if v_tenencia2 is distinct from v_tenencia then
    raise exception 'V05 el avance de etapa movio tenencia_desde (% -> %)', v_tenencia, v_tenencia2;
  end if;
  if v_n is distinct from v_ciclo then
    raise exception 'V06 el avance de etapa movio ciclo_actual (% -> %)', v_ciclo, v_n;
  end if;
end;
$test$;

-- ── V07–V10: lo que NO debe avanzar ──────────────────────────────────────────
do $test$
declare
  v_etapa text;
  v_n int;
  v_auto boolean;
begin
  -- "No contesto" y "mensaje enviado" son INTENTOS, no conversacion.
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000002', 'llamada_no_contestada', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000002';
  if v_etapa <> 'nuevo' then
    raise exception 'V07 llamada_no_contestada NO debe avanzar la etapa (quedo en %)', v_etapa;
  end if;

  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000002', 'whatsapp_enviado', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000002';
  if v_etapa <> 'nuevo' then
    raise exception 'V08 whatsapp_enviado NO debe avanzar la etapa (quedo en %)', v_etapa;
  end if;

  -- Una nota interna no es haber hablado con nadie.
  insert into crm.actividades (lead_id, tipo, detalle, creado_por)
  values ('3b000000-0000-4000-8000-000000000002', 'nota', 'ORACULO nota', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000002';
  if v_etapa <> 'nuevo' then
    raise exception 'V09 una nota NO debe avanzar la etapa (quedo en %)', v_etapa;
  end if;

  -- NO CASCADA + EL FLAG NO SE FILTRA. Un cambio de etapa MANUAL en la misma
  -- transaccion en la que ya hubo avances automaticos (V01-V06 mas arriba) debe
  -- escribir UN solo cambio_etapa y quedar marcado como MANUAL. Si
  -- `crm.avance_auto` se filtrara entre statements, el sistema podria
  -- atribuirse movimientos que ordeno una persona — o al reves.
  update crm.leads set etapa = 'reunion_agendada'
   where id = '3b000000-0000-4000-8000-000000000002';
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000002';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V10 un cambio de etapa manual se corrompio (quedo en %)', v_etapa;
  end if;

  select count(*) into v_n from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000002' and tipo = 'cambio_etapa';
  if v_n <> 1 then
    raise exception 'V10b cascada: % cambios de etapa por un unico update manual', v_n;
  end if;

  select bool_and((metadata->>'automatico')::boolean) into v_auto from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000002' and tipo = 'cambio_etapa';
  if v_auto is distinct from false then
    raise exception 'V10c el flag crm.avance_auto se filtro: un cambio MANUAL quedo marcado automatico';
  end if;
end;
$test$;

-- ── V11–V12: leads cerrados e inactivos no reviven ───────────────────────────
do $test$
declare v_etapa text;
begin
  update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde'
   where id = '3b000000-0000-4000-8000-000000000003';
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000003', 'llamada_realizada', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000003';
  if v_etapa <> 'descartado' then
    raise exception 'V11 un lead descartado no puede revivir por una actividad (quedo en %)', v_etapa;
  end if;

  update crm.leads set activo = false where id = '3b000000-0000-4000-8000-000000000008';
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000008', 'llamada_realizada', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000008';
  if v_etapa <> 'nuevo' then
    raise exception 'V12 un lead inactivo no debe avanzar de etapa (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V13–V18: la reunion agendada y sus guardas ───────────────────────────────
do $test$
declare
  v_etapa text;
  v_filas int;
begin
  -- El lead 4 ya viene 'contactado' pero SIN actividades: la reunion no puede
  -- avanzarlo todavia (nadie registro haberlo tocado).
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000004', 'reunion', 'ORACULO reunion sin contacto',
          now() + interval '2 days', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000004';
  if v_etapa <> 'contactado' then
    raise exception 'V13 sin NINGUN contacto registrado la reunion no debe avanzar (quedo en %)', v_etapa;
  end if;

  -- Con un contacto real registrado, ahora si.
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000004', 'llamada_no_contestada', '3a000000-0000-4000-8000-000000000002');
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000004', 'reunion', 'ORACULO reunion real',
          now() + interval '2 days', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000004';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V14 agendar reunion sobre un lead trabajado debe subirlo (quedo en %)', v_etapa;
  end if;

  -- Guarda: una tarea de otro TIPO nunca mueve el embudo.
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000005', 'llamada_no_contestada', '3a000000-0000-4000-8000-000000000002');
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000005', 'llamada', 'ORACULO llamada',
          now() + interval '1 day', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000005';
  if v_etapa <> 'nuevo' then
    raise exception 'V15 una tarea de llamada no debe mover la etapa (quedo en %)', v_etapa;
  end if;

  -- Guarda: agendar en el PASADO no es agendar.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000005', 'reunion', 'ORACULO reunion vencida',
          now() - interval '1 day', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000005';
  if v_etapa <> 'nuevo' then
    raise exception 'V16 una reunion con fecha pasada no debe avanzar (quedo en %)', v_etapa;
  end if;

  -- LA GUARDA QUE MAS IMPORTA: el rebote automatico tras un no-show. Ascender
  -- por un planton seria la mentira mas facil de fabricar del sistema.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, reagendada_de, creado_por)
  select '3b000000-0000-4000-8000-000000000005', 'reunion', 'ORACULO reagenda post no-show',
         now() + interval '3 days', t.id, '3a000000-0000-4000-8000-000000000002'
    from crm.tareas t
   where t.lead_id = '3b000000-0000-4000-8000-000000000005' and t.tipo = 'llamada';
  -- Sin esto la asercion pasaria EN VACIO si el subselect no encontrara la
  -- tarea de origen: no se insertaria nada y la etapa seguiria igual "por
  -- casualidad", no por la guarda.
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception 'V17 fixture rota: se esperaba insertar 1 reagenda, se insertaron %', v_filas;
  end if;
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000005';
  if v_etapa <> 'nuevo' then
    raise exception 'V17 la reagenda tras un no-show NO puede ascender el lead (quedo en %)', v_etapa;
  end if;

  -- Guarda: jamas un RETROCESO desde propuesta_enviada (reiniciaria el SLA
  -- de 120h a 72h y falsearia el avance del embudo hacia atras).
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-000000000006', 'reunion_realizada', '3a000000-0000-4000-8000-000000000002');
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000006', 'reunion', 'ORACULO reunion de cierre',
          now() + interval '2 days', '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000006';
  if v_etapa <> 'propuesta_enviada' then
    raise exception 'V18 una reunion NO puede retroceder un lead en propuesta_enviada (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V19–V21: el camino REAL del vendedor, entero, via crm.cerrar_tarea ───────
-- Es el que mas importa: la RPC es SECURITY DEFINER y escribe server-side,
-- donde el navegador no puede interceptar nada. Si el avance no funcionara por
-- aqui, cerrar una tarea desde la agenda dejaria el embudo sin mover.
insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
values ('3c000000-0000-4000-8000-000000000001', '3b000000-0000-4000-8000-000000000007',
        'llamada', 'ORACULO llamar', now() + interval '1 hour',
        '3a000000-0000-4000-8000-000000000002');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"3a000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '3a000000-0000-4000-8000-000000000002', true);

do $test$
declare
  v_res jsonb;
  v_etapa text;
  v_estado text;
  v_n int;
begin
  v_res := crm.cerrar_tarea(
    '3c000000-0000-4000-8000-000000000001',
    'completada',
    'llamada_realizada',
    'ORACULO contesto por RPC',
    jsonb_build_object(
      'tipo', 'reunion',
      'titulo', 'ORACULO reunion encadenada',
      'vence_en', (now() + interval '2 days')::text
    )
  );
  if coalesce(v_res->>'ok', '') <> 'true' then
    raise exception 'V19 la RPC cerrar_tarea no devolvio ok';
  end if;

  select estado into v_estado from crm.tareas where id = '3c000000-0000-4000-8000-000000000001';
  if v_estado <> 'completada' then
    raise exception 'V19 la tarea no quedo completada (%)', v_estado;
  end if;

  -- El lead recorrio DOS escalones en la misma transaccion, en orden: la
  -- actividad del resultado lo subio a 'contactado' y la reunion encadenada a
  -- 'reunion_agendada'. Es exactamente lo que espeja el store del front.
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000007';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V20 cerrar con contacto y encadenar reunion debe dejar el lead en reunion_agendada (quedo en %)', v_etapa;
  end if;

  select count(*) into v_n from crm.actividades
   where lead_id = '3b000000-0000-4000-8000-000000000007' and tipo = 'cambio_etapa';
  if v_n <> 2 then
    raise exception 'V21 esperaba 2 cambios de etapa (nuevo->contactado->reunion_agendada), hubo %', v_n;
  end if;
end;
$test$;

reset role;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

-- ── V22: C1 — un supervisor NO asciende un lead de la cola global ────────────
-- El hallazgo critico de la auditoria, como test de regresion permanente.
--
-- La policy `tareas_insert` NUNCA consulta `crm.leads`: valida el vendedor_id
-- de la fila NUEVA, que `trg_tareas_before_insert` (SECURITY DEFINER) ya derivo
-- del lead saltandose la RLS. Para un lead de la cola global ese valor sale
-- null y la rama `supervisor|gerencia AND vendedor_id IS NULL` deja pasar el
-- INSERT. Sin el gate de ambito DENTRO del trigger de avance, ese INSERT movia
-- la etapa de un lead que `leads_select` ni siquiera deja VER al supervisor.
--
-- El INSERT de la tarea SI debe funcionar (ese hueco de `tareas_insert` es
-- previo y se sale del alcance de esta migracion); lo que no puede pasar es que
-- ARRASTRE una escritura sobre crm.leads.
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"3a000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub', '3a000000-0000-4000-8000-000000000001', true);

do $test$
declare
  v_etapa text;
  v_visible int;
begin
  select count(*) into v_visible from crm.leads
   where id = '3b000000-0000-4000-8000-000000000009';
  if v_visible <> 0 then
    raise exception 'V22 fixture rota: el supervisor no deberia VER el lead de la cola global (vio %)', v_visible;
  end if;

  -- DOS CAPAS, y desde la migracion 20260725221530 la PRIMERA ya lo para:
  -- `tareas_insert` exige que el lead sea VISIBLE, y este no lo es. Antes de esa
  -- migracion el INSERT pasaba y solo lo frenaba el gate del trigger; ahora ni
  -- llega. Se afirma la DENEGACION en vez de darla por buena — si algun dia la
  -- policy se relajara, este bloque lo canta en vez de pasar en silencio.
  begin
    insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
    values ('3b000000-0000-4000-8000-000000000009', 'reunion', 'ORACULO reunion cola global',
            now() + interval '2 days', '3a000000-0000-4000-8000-000000000001');
    raise exception 'V22 REGRESION: la policy tareas_insert acepto una tarea sobre un lead invisible';
  exception
    when insufficient_privilege then
      null; -- 42501 esperado: la policy hizo su trabajo
  end;
end;
$test$;

reset role;
select set_config('request.jwt.claims', '', true);
select set_config('request.jwt.claim.sub', '', true);

do $test$
declare v_etapa text;
begin
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000009';
  if v_etapa <> 'nuevo' then
    raise exception 'V22 ESCALADA: un supervisor ascendio un lead de la cola global que ni puede ver (quedo en %)', v_etapa;
  end if;

  -- LA SEGUNDA CAPA, AISLADA. Con la policy denegando el INSERT, la asercion de
  -- arriba pasaria igual aunque el gate del trigger no existiera: se probaria a
  -- si misma. Aqui se FABRICA la tarea como sistema (sin RLS de por medio) para
  -- comprobar que el gate de ambito del trigger la frena por su cuenta. Sin
  -- esto, tapar la policy habria dejado el gate sin cobertura y nadie lo notaria
  -- el dia que alguien la relaje.
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, creado_por)
  values ('3b000000-0000-4000-8000-000000000009', 'reunion', 'ORACULO reunion fabricada',
          now() + interval '2 days', '3a000000-0000-4000-8000-000000000001');

  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-000000000009';
  if v_etapa <> 'nuevo' then
    raise exception 'V22b DEFENSA EN PROFUNDIDAD: ni saltandose la policy puede ascender un lead sin dueno (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V23: el "No Insista" registra el hecho igual ─────────────────────────────
-- Decision explicita (2026-07-25): un lead con `no_contactar` SI avanza de
-- etapa cuando alguien registra una conversacion. Registrar lo que paso NO es
-- aprobarlo — la persona pudo llamarnos ella — y bloquear el avance dejaria el
-- dato inconsistente con su propio timeline. Lo que la Ley 29571 prohibe es
-- CONTACTAR, y de eso se ocupa el kill-switch de motor-siguiente.ts, que ya no
-- propone insistir. Queda fijado aqui para que el dia que Miguel decida lo
-- contrario, el cambio sea deliberado y no un descubrimiento.
do $test$
declare v_etapa text;
begin
  insert into crm.actividades (lead_id, tipo, creado_por)
  values ('3b000000-0000-4000-8000-00000000000a', 'whatsapp_recibido',
          '3a000000-0000-4000-8000-000000000002');
  select etapa into v_etapa from crm.leads where id = '3b000000-0000-4000-8000-00000000000a';
  if v_etapa <> 'contactado' then
    raise exception 'V23 un No Insista que RESPONDE debe registrarse igual (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V24–V26: superficie de ataque de las funciones nuevas ────────────────────
do $test$
begin
  if has_function_privilege('authenticated', 'private.trg_actividades_avance_etapa()', 'EXECUTE') then
    raise exception 'V24 authenticated no debe poder ejecutar el trigger de avance por contacto';
  end if;
  if has_function_privilege('authenticated', 'private.trg_tareas_avance_etapa()', 'EXECUTE') then
    raise exception 'V25 authenticated no debe poder ejecutar el trigger de avance por reunion';
  end if;
  if has_function_privilege('anon', 'private.trg_actividades_avance_etapa()', 'EXECUTE')
     or has_function_privilege('anon', 'private.trg_tareas_avance_etapa()', 'EXECUTE') then
    raise exception 'V26 anon no debe poder ejecutar los triggers de avance';
  end if;
end;
$test$;

select 'AVANCE_TX_OK' as resultado;

rollback;
