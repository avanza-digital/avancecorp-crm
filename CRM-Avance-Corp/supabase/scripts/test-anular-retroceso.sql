-- Oraculo transaccional autocontenido de ANULAR CON AUTORIA + RETROCESO DE ETAPA.
-- Exito = token ANULAR_TX_OK; todo queda en rollback.
--
-- Los dos pedidos de Miguel (2026-07-26) que cubre:
--   1. "si se anula la reu y no se reagenda una en ese mismo momento, deberia
--      bajar de etapa"
--   2. "separa lo que cancela el sistema y lo que cancela el asesor"
--
-- Igual que en test-avance-etapa.sql, la mitad de las aserciones son NEGATIVAS,
-- y aqui por una razon mas fuerte: este es el UNICO mecanismo del sistema que
-- BAJA una etapa. Un embudo que se desinfla solo borra progreso comercial real
-- y no hay deshacer — el `cambio_etapa` entra en un log inmutable. Ante la duda,
-- no debe bajar.
--
-- Cubre: el sello de autoria en UPDATE y en INSERT, el CHECK bicondicional (el
-- que en la 1a version no restringia nada porque `null in (...)` es NULL), el
-- portazo al PATCH directo, las cuatro guardas del retroceso, el anclaje al
-- ciclo del lead reabierto, la composicion anular+reagendar en el mismo gesto
-- (que debe ser un NO-OP, cero cambio_etapa) y la superficie de las funciones.
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
  ('4a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'an-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('4a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'an-v1@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('4a000000-0000-4000-8000-000000000001', 'Anular Supervisor', 'an-sup@test.invalid', 'comercial', true),
  ('4a000000-0000-4000-8000-000000000002', 'Anular Vendedor', 'an-v1@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('4a000000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('4a000000-0000-4000-8000-000000000002', 'vendedor', '4a000000-0000-4000-8000-000000000001', true);

-- Siete leads, uno por escenario. Todos arrancan donde los deja el trigger de
-- SUBIDA (`reunion_agendada`) salvo los que prueban lo contrario.
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, activo, creado_por
)
values
  ('4b000000-0000-4000-8000-000000000001', 'Anular Baja OK', '+51910000001', 'reunion_agendada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000002', 'Anular Sin Contacto', '+51910000002', 'reunion_agendada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000003', 'Anular Otra Reunion', '+51910000003', 'reunion_agendada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000004', 'Anular Ya Realizada', '+51910000004', 'reunion_agendada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000005', 'Anular Propuesta', '+51910000005', 'propuesta_enviada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000006', 'Anular Reagenda', '+51910000006', 'reunion_agendada', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002'),
  ('4b000000-0000-4000-8000-000000000007', 'Anular Sistema', '+51910000007', 'contactado', 'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000002', true, '4a000000-0000-4000-8000-000000000002');

-- Equipo AJENO (fuera del subarbol de 4a…001), para la asercion de escalada
-- V15c. Se siembra AQUI, como sistema: private.trg_leads_guard_tenencia no deja
-- que un vendedor asigne un lead a otro equipo, asi que hacerlo dentro del test
-- —ya con la sesion de vend1— abortaria por la razon equivocada.
insert into auth.users (
  id, aud, role, email, email_confirmed_at, raw_app_meta_data,
  raw_user_meta_data, created_at, updated_at
)
values
  ('4a000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'an-sup2@test.invalid', now(), '{}', '{}', now(), now()),
  ('4a000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'an-v2@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('4a000000-0000-4000-8000-000000000003', 'Anular Supervisor Ajeno', 'an-sup2@test.invalid', 'comercial', true),
  ('4a000000-0000-4000-8000-000000000004', 'Anular Vendedor Ajeno', 'an-v2@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('4a000000-0000-4000-8000-000000000003', 'supervisor', null, true),
  ('4a000000-0000-4000-8000-000000000004', 'vendedor', '4a000000-0000-4000-8000-000000000003', true);

insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, activo, creado_por
)
values
  ('4b000000-0000-4000-8000-000000000009', 'Anular Equipo Ajeno', '+51910000009', 'reunion_agendada',
   'referido', 1000, 'PEN', '4a000000-0000-4000-8000-000000000004', true,
   '4a000000-0000-4000-8000-000000000004');

-- Lead de la COLA GLOBAL (sin dueno): el gate de ambito debe dejarlo quieto.
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, activo, creado_por
)
values
  ('4b000000-0000-4000-8000-000000000008', 'Anular Cola Global', '+51910000008', 'reunion_agendada',
   'referido', 1000, 'PEN', null, null, true, '4a000000-0000-4000-8000-000000000002');

-- Contacto real en el timeline de todos menos el "Sin Contacto" y el de la cola.
--
-- `creado_en` EXPLICITO, y no es cosmetica: `crm.leads.creado_en` lo FUERZA
-- private.trg_leads_guard_tenencia con statement_timestamp(), mientras que
-- crm.actividades usa el DEFAULT now() = transaction_timestamp(), que dentro de
-- UNA transaccion es constante desde el `begin` — o sea ANTERIOR. Sin esto,
-- private.inicio_ciclo_lead deja fuera del ciclo TODO lo que se siembra aqui, y
-- el oraculo se vuelve verde por la razon equivocada en unos casos y rojo en
-- otros (el peor: el retroceso correria justo en el lead que ya tuvo su
-- reunion). En produccion no pasa porque cada request es su propia transaccion.
insert into crm.actividades (lead_id, tipo, creado_por, creado_en)
select id, 'llamada_realizada', '4a000000-0000-4000-8000-000000000002', statement_timestamp()
from crm.leads
where id in ('4b000000-0000-4000-8000-000000000001',
             '4b000000-0000-4000-8000-000000000003',
             '4b000000-0000-4000-8000-000000000004',
             '4b000000-0000-4000-8000-000000000005',
             '4b000000-0000-4000-8000-000000000006',
             '4b000000-0000-4000-8000-000000000007',
             '4b000000-0000-4000-8000-000000000009');

-- El lead 04 ademas TUVO la reunion: ese hito no se puede borrar por limpiar
-- una tarea residual.
insert into crm.actividades (lead_id, tipo, creado_por, creado_en)
values ('4b000000-0000-4000-8000-000000000004', 'reunion_realizada',
        '4a000000-0000-4000-8000-000000000002', statement_timestamp());

-- Reuniones pendientes. Nacen con el flag de sistema apagado, asi que pasan por
-- el camino normal (y el trigger de subida no las mueve: ya estan arriba).
insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
values
  ('4c000000-0000-4000-8000-000000000001', '4b000000-0000-4000-8000-000000000001', 'reunion', 'ORACULO reunion baja', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000002', '4b000000-0000-4000-8000-000000000002', 'reunion', 'ORACULO reunion sin contacto', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000003', '4b000000-0000-4000-8000-000000000003', 'reunion', 'ORACULO reunion A', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-00000000000a', '4b000000-0000-4000-8000-000000000003', 'reunion', 'ORACULO reunion B', now() + interval '4 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000004', '4b000000-0000-4000-8000-000000000004', 'reunion', 'ORACULO reunion ya realizada', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000005', '4b000000-0000-4000-8000-000000000005', 'reunion', 'ORACULO reunion propuesta', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000006', '4b000000-0000-4000-8000-000000000006', 'reunion', 'ORACULO reunion reagenda', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000007', '4b000000-0000-4000-8000-000000000007', 'whatsapp', 'ORACULO tarea sistema', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000008', '4b000000-0000-4000-8000-000000000008', 'reunion', 'ORACULO reunion cola global', now() + interval '3 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-000000000009', '4b000000-0000-4000-8000-000000000001', 'llamada', 'ORACULO llamada que sobra', now() + interval '2 days', '4a000000-0000-4000-8000-000000000002'),
  ('4c000000-0000-4000-8000-00000000000c', '4b000000-0000-4000-8000-000000000009', 'reunion', 'ORACULO reunion ajena', now() + interval '3 days', '4a000000-0000-4000-8000-000000000004');

-- A partir de aqui, el vendedor. Todo lo que sigue corre con SU sesion: el
-- portazo, la etiqueta 'asesor' y el gate de ambito dependen de auth.uid().
select set_config('request.jwt.claims',
  '{"sub":"4a000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

-- ── V01: el CHECK bicondicional prohibe LAS DOS mitades ─────────────────────
-- La 1a version de la migracion escribia `cancelada_por in ('asesor','sistema')`
-- sin `is not null`, y eso NO restringe nada: `null in (...)` da NULL y un CHECK
-- solo se viola con FALSE. La fila "cancelada sin autor" entraba tan campante.
do $test$
declare
  v_ok boolean := false;
begin
  begin
    -- Mitad A: cancelada SIN autor.
    perform set_config('crm.op_tarea', 'on', true);
    insert into crm.tareas (lead_id, tipo, titulo, vence_en, estado, cancelada_por, creado_por)
    values ('4b000000-0000-4000-8000-000000000001', 'llamada', 'ORACULO check A',
            now() + interval '1 day', 'cancelada', null, '4a000000-0000-4000-8000-000000000002');
    perform set_config('crm.op_tarea', 'off', true);
  exception when check_violation then
    v_ok := true;
  end;
  perform set_config('crm.op_tarea', 'off', true);
  if not v_ok then
    -- Puede no violar el CHECK si el BEFORE la sello a 'sistema' (que es lo
    -- correcto y suficiente): se acepta ese camino, pero NUNCA quedar en null.
    if exists (select 1 from crm.tareas
                where lead_id = '4b000000-0000-4000-8000-000000000001'
                  and titulo = 'ORACULO check A' and cancelada_por is null) then
      raise exception 'V01 una tarea cancelada NO puede quedarse sin autor';
    end if;
  end if;
end;
$test$;

do $test$
declare
  v_ok boolean := false;
begin
  begin
    -- Mitad B: PENDIENTE con autor. Aqui el sello del INSERT (M2) tambien lo
    -- neutraliza; se acepta cualquiera de los dos frenos, pero no que pase.
    insert into crm.tareas (lead_id, tipo, titulo, vence_en, cancelada_por, creado_por)
    values ('4b000000-0000-4000-8000-000000000001', 'llamada', 'ORACULO check B',
            now() + interval '1 day', 'asesor', '4a000000-0000-4000-8000-000000000002');
  exception when check_violation then
    v_ok := true;
  end;
  if not v_ok and exists (
      select 1 from crm.tareas
       where titulo = 'ORACULO check B' and cancelada_por is not null) then
    raise exception 'V02 una tarea PENDIENTE no puede llevar autor de cancelacion';
  end if;
end;
$test$;

-- ── V01c: el CHECK exige autor DE VERDAD (el `is not null` de A1) ──────────
-- V01 y V02 NO pueden detectar la regresion que motivo el NO-GO: el sello del
-- INSERT (M2) reescribe la etiqueta ANTES de que el CHECK evalue, asi que pasan
-- igual con el `is not null` puesto o quitado. La unica forma de aserir la
-- correccion es mirar la definicion del constraint. Que ya no haya camino de
-- datos que llegue al CHECK es lo DESEABLE — pero entonces el candado tiene que
-- verificarse como candado, no por sus efectos.
do $test$
declare v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conname = 'tareas_cancelada_por_valida'
     and c.conrelid = 'crm.tareas'::regclass;
  if v_def is null then
    raise exception 'V01c no existe el CHECK tareas_cancelada_por_valida';
  end if;
  if v_def !~* 'cancelada_por IS NOT NULL' then
    raise exception 'V01c el CHECK no exige autor (%): null in (...) es NULL y un CHECK solo se viola con FALSE', v_def;
  end if;
end;
$test$;

-- ── V03: el PATCH directo deja de poder anular ──────────────────────────────
do $test$
declare
  v_ok boolean := false;
begin
  begin
    update crm.tareas set estado = 'cancelada'
     where id = '4c000000-0000-4000-8000-000000000001';
  exception when raise_exception then
    v_ok := true;
  end;
  if not v_ok then
    raise exception 'V03 anular por UPDATE directo tiene que pasar por crm.cerrar_tarea()';
  end if;
end;
$test$;

-- ── V04: la etiqueta no se puede inyectar desde el payload ──────────────────
do $test$
declare
  v_autor text;
begin
  update crm.tareas set cancelada_por = 'sistema', nota = 'ORACULO intento de sello'
   where id = '4c000000-0000-4000-8000-000000000001';
  select cancelada_por into v_autor from crm.tareas
   where id = '4c000000-0000-4000-8000-000000000001';
  if v_autor is not null then
    raise exception 'V04 el cliente no puede escribir cancelada_por (quedo %)', v_autor;
  end if;
end;
$test$;

-- ── V05–V08: EL CASO DE MIGUEL. Anular la unica reunion baja la etapa ───────
do $test$
declare
  v_etapa text;
  v_autor text;
  v_n int;
  v_auto boolean;
  v_res jsonb;
begin
  v_res := crm.cerrar_tarea('4c000000-0000-4000-8000-000000000001', 'cancelada', null, null, null);

  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000001';
  if v_etapa <> 'contactado' then
    raise exception 'V05 anular la unica reunion debe devolver el lead a contactado (quedo en %)', v_etapa;
  end if;
  if v_res->>'retroceso' <> 'contactado' then
    raise exception 'V06 la RPC debe DECIR el retroceso para que la UI lo cante (dijo %)', v_res->>'retroceso';
  end if;

  select cancelada_por into v_autor from crm.tareas
   where id = '4c000000-0000-4000-8000-000000000001';
  if v_autor <> 'asesor' then
    raise exception 'V07 la anulacion humana debe quedar firmada por el asesor (quedo %)', v_autor;
  end if;

  -- Un solo cambio_etapa, y marcado como automatico (lo movio el sistema por
  -- orden de una persona, no la persona arrastrando la tarjeta).
  select count(*), bool_and((metadata->>'automatico')::boolean) into v_n, v_auto
  from crm.actividades
   where lead_id = '4b000000-0000-4000-8000-000000000001' and tipo = 'cambio_etapa';
  if v_n <> 1 then
    raise exception 'V08 el retroceso debe escribir EXACTAMENTE un cambio_etapa (escribio %)', v_n;
  end if;
  if v_auto is distinct from true then
    raise exception 'V08b el cambio_etapa del retroceso debe marcarse automatico (%)', v_auto;
  end if;
end;
$test$;

-- ── V09: anular una LLAMADA no mueve nada ───────────────────────────────────
do $test$
declare
  v_etapa text;
begin
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000009', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000001';
  if v_etapa <> 'contactado' then
    raise exception 'V09 anular una llamada no puede mover la etapa (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V10: sin NINGUN contacto real, el retroceso llega hasta `nuevo` ─────────
do $test$
declare
  v_etapa text;
begin
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000002', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000002';
  if v_etapa <> 'nuevo' then
    raise exception 'V10 sin contacto en el timeline el retroceso debe llegar a nuevo (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V11: si QUEDA otra reunion viva, no baja nada ───────────────────────────
do $test$
declare
  v_etapa text;
  v_n int;
begin
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000003', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000003';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V11 con otra reunion viva el lead se queda en reunion_agendada (quedo en %)', v_etapa;
  end if;
  select count(*) into v_n from crm.actividades
   where lead_id = '4b000000-0000-4000-8000-000000000003' and tipo = 'cambio_etapa';
  if v_n <> 0 then
    raise exception 'V11b un retroceso que no ocurre no puede ensuciar el log (% filas)', v_n;
  end if;
end;
$test$;

-- ── V12: si la reunion LLEGO A OCURRIR, no baja ─────────────────────────────
do $test$
declare
  v_etapa text;
begin
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000004', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000004';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V12 con reunion_realizada en el timeline no se baja (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V13: desde `propuesta_enviada` no se toca ───────────────────────────────
do $test$
declare
  v_etapa text;
begin
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000005', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000005';
  if v_etapa <> 'propuesta_enviada' then
    raise exception 'V13 desde propuesta_enviada la etapa no la sostiene la reunion (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V14: ANULAR Y REAGENDAR EN EL MISMO GESTO ES UN NO-OP ───────────────────
-- Esta es la aserticion que justifica que el retroceso viva INLINE al final de
-- la RPC y no en un AFTER UPDATE: con el trigger, la reunion nueva todavia no
-- existia, la etapa bajaba y subia, y quedaban DOS cambio_etapa espurios en un
-- log inmutable. Aqui tienen que ser CERO.
do $test$
declare
  v_etapa text;
  v_n int;
begin
  perform crm.cerrar_tarea(
    '4c000000-0000-4000-8000-000000000006', 'cancelada', null, null,
    jsonb_build_object(
      'tipo', 'reunion',
      'titulo', 'ORACULO reunion reagendada',
      'vence_en', (now() + interval '9 days')::text
    ));
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000006';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V14 reagendar en el mismo gesto no puede mover la etapa (quedo en %)', v_etapa;
  end if;
  select count(*) into v_n from crm.actividades
   where lead_id = '4b000000-0000-4000-8000-000000000006' and tipo = 'cambio_etapa';
  if v_n <> 0 then
    raise exception 'V14b anular+reagendar debe ser neto CERO en el log (escribio % cambio_etapa)', v_n;
  end if;
end;
$test$;

-- ── V15: la tarea de un lead sin dueno esta fuera del ambito de cualquiera ──
-- OJO: esta asercion NO prueba el gate del retroceso. La RPC corta antes, en su
-- propio filtro de ambito, porque la tarea hereda vendedor_id null del lead. Se
-- deja porque la parada temprana tambien hay que sostenerla, pero el gate de
-- verdad se ejercita en V15b y V15c.
do $test$
declare
  v_etapa text;
  v_sqlstate text;
  v_msg text := null;
begin
  -- El resultado sale del bloque por una VARIABLE, no por un `raise` dentro del
  -- propio `begin`: ahi lo atraparia su mismo handler y el mensaje del fallo
  -- saldria disfrazado del error que se estaba comprobando.
  begin
    perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000008', 'cancelada', null, null, null);
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_msg = message_text;
  end;
  if v_msg is null then
    raise exception 'V15 la RPC debio rechazar una tarea sin dueno';
  end if;
  -- AFIRMAR EL MOTIVO: un `when others` mudo deja el test verde el dia que esto
  -- empiece a fallar por cualquier otra razon.
  if v_msg not like '%fuera de tu ambito%' then
    raise exception 'V15 el rechazo debe ser por ambito, no por % (%)', v_sqlstate, v_msg;
  end if;
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000008';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V15 un lead de la cola global no puede retroceder (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V15b: tarea EN ambito, lead SIN dueno → lo para el GATE del retroceso ───
-- Se desincroniza tarea<->lead a proposito: el BEFORE UPDATE de tareas no
-- restaura `vendedor_id`, y asi quedaria una fila anterior a 20260725221530.
-- Ahora la RPC SI acepta (la tarea esta en el ambito del vendedor) y la unica
-- defensa que queda en pie es `coalesce(l.vendedor_id, l.asignado_supervisor_id)
-- is not null` dentro del retroceso.
do $test$
declare v_etapa text;
begin
  update crm.tareas set vendedor_id = '4a000000-0000-4000-8000-000000000002'
   where id = '4c000000-0000-4000-8000-000000000008';
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-000000000008', 'cancelada', null, null, null);
  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000008';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V15b un lead SIN DUENO no puede retroceder aunque la tarea si sea mia (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V15c: LA ESCALADA. Lead de OTRO equipo, tarea colada en mi ambito ───────
-- El caso que distingue una migracion CON gate de ambito de una SIN el: la RPC
-- pasa (la tarea es mia) y lo unico que impide mover el embudo de un equipo
-- ajeno es `private.puede_ver_cartera`. Sin esa rama, este test pintaria verde
-- con un agujero de escalada abierto.
do $test$
declare v_etapa text;
begin
  -- La tarea se cuela en MI ambito; el lead sigue siendo del otro equipo.
  update crm.tareas set vendedor_id = '4a000000-0000-4000-8000-000000000002'
   where id = '4c000000-0000-4000-8000-00000000000c';

  perform crm.cerrar_tarea('4c000000-0000-4000-8000-00000000000c', 'cancelada', null, null, null);

  select etapa into v_etapa from crm.leads where id = '4b000000-0000-4000-8000-000000000009';
  if v_etapa <> 'reunion_agendada' then
    raise exception 'V15c ESCALADA: se movio el embudo de un equipo ajeno (quedo en %)', v_etapa;
  end if;
end;
$test$;

-- ── V16: la otra mitad de la separacion — lo que cancela el SISTEMA ─────────
do $test$
declare
  v_autor text;
  v_estado text;
begin
  update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes'
   where id = '4b000000-0000-4000-8000-000000000007';
  select estado, cancelada_por into v_estado, v_autor from crm.tareas
   where id = '4c000000-0000-4000-8000-000000000007';
  if v_estado <> 'cancelada' then
    raise exception 'V16 descartar el lead debe cancelar sus pendientes (quedo %)', v_estado;
  end if;
  if v_autor <> 'sistema' then
    raise exception 'V16b la cancelacion automatica NO es gestion del asesor (quedo %)', v_autor;
  end if;
end;
$test$;

-- ── V17: la GUC de sistema no se filtra a la siguiente anulacion humana ─────
-- Gemela de la asercion de no-fuga de `crm.avance_auto` en test-avance-etapa.
do $test$
declare
  v_autor text;
begin
  insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
  values ('4c000000-0000-4000-8000-00000000000b', '4b000000-0000-4000-8000-000000000005',
          'llamada', 'ORACULO tras el descarte', now() + interval '2 days',
          '4a000000-0000-4000-8000-000000000002');
  perform crm.cerrar_tarea('4c000000-0000-4000-8000-00000000000b', 'cancelada', null, null, null);
  select cancelada_por into v_autor from crm.tareas
   where id = '4c000000-0000-4000-8000-00000000000b';
  if v_autor <> 'asesor' then
    raise exception 'V17 crm.cancela_sistema se filtro: la anulacion humana quedo como % ', v_autor;
  end if;
end;
$test$;

-- ── V18: la metrica separa, y saca del denominador lo del sistema ──────────
do $test$
declare
  v jsonb;
  fila jsonb;
begin
  v := crm.metricas_agenda_fn((now() at time zone 'America/Lima')::date,
                              (now() at time zone 'America/Lima')::date);
  select e into fila from jsonb_array_elements(v->'vendedores') e
   where e->>'vendedor_id' = '4a000000-0000-4000-8000-000000000002';
  if fila is null then
    raise exception 'V18 el vendedor del oraculo no aparece en el payload';
  end if;
  if fila->'canceladas_asesor' is null or fila->'canceladas_sistema' is null then
    raise exception 'V18b faltan las claves del desglose en el payload';
  end if;
  if (fila->>'canceladas_asesor')::int + (fila->>'canceladas_sistema')::int
     <> (fila->>'canceladas')::int then
    raise exception 'V18c las dos mitades (%/%) no suman el total %',
      fila->>'canceladas_asesor', fila->>'canceladas_sistema', fila->>'canceladas';
  end if;
  if (fila->>'canceladas_sistema')::int < 1 then
    raise exception 'V18d el descarte del lead debe contarse como cancelacion del SISTEMA';
  end if;
  if (fila->>'canceladas_asesor')::int < 1 then
    raise exception 'V18e las anulaciones humanas deben contarse aparte';
  end if;
end;
$test$;

-- ── V19–V21: superficie de ataque de las funciones nuevas ──────────────────
do $test$
begin
  if has_function_privilege('authenticated', 'private.retroceso_por_anular_reunion(uuid,uuid,uuid)', 'EXECUTE') then
    raise exception 'V19 authenticated no debe poder ejecutar el retroceso suelto (le dejaria pasar su propio uid)';
  end if;
  if has_function_privilege('anon', 'private.retroceso_por_anular_reunion(uuid,uuid,uuid)', 'EXECUTE') then
    raise exception 'V20 anon no debe poder ejecutar el retroceso';
  end if;
  if has_function_privilege('authenticated', 'private.inicio_ciclo_lead(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.inicio_ciclo_lead(uuid)', 'EXECUTE') then
    raise exception 'V21 el helper de ciclo lee crm.leads saltandose la RLS: no se expone';
  end if;
  -- V22: al reves que las tres de arriba. `CREATE OR REPLACE` conserva la ACL,
  -- pero es LA trampa que el repo documenta (un DROP+CREATE la borra) y el
  -- precio de equivocarse es que NADIE puede cerrar tareas en todo el CRM.
  if not has_function_privilege('authenticated',
       'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE') then
    raise exception 'V22 el CREATE OR REPLACE le quito el EXECUTE a authenticated';
  end if;
  if not has_function_privilege('service_role',
       'crm.cerrar_tarea(uuid,text,text,text,jsonb)', 'EXECUTE') then
    raise exception 'V22b service_role perdio el EXECUTE de cerrar_tarea';
  end if;
end;
$test$;

select 'ANULAR_TX_OK' as resultado;

rollback;
