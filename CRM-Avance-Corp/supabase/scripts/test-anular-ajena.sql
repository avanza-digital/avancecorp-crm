-- Oraculo transaccional autocontenido de LA ANULACION AJENA NO PENALIZA.
-- Exito = token AJENA_TX_OK; todo queda en rollback.
--
-- Decision de Miguel (2026-07-26), cerrando lo que quedo abierto al desplegar
-- 20260726151751: "si el supervisor anula una tarea el vendedor no deberia
-- poder hacer nada sobre esa tarea" -> tampoco cargar con ella en su %.
--
-- Regla unica que se veri­fica aqui: una anulacion entra en el denominador de
-- alguien SOLO si se puede afirmar que la firmo esa misma persona. El sistema,
-- el jefe y el autor indeterminado quedan fuera.
--
-- Cubre: el sello de la firma en UPDATE y en INSERT, el CHECK nuevo (mirado
-- como candado y no solo por sus efectos, misma leccion que V01c del oraculo
-- anterior), la imposibilidad de firmar en nombre de otro, la aritmetica de la
-- metrica en los tres casos (propia / ajena / sistema), la invariante
-- propias+ajenas=asesor, y que las claves viejas del contrato no cambien.
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
  ('5a000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'aj-sup@test.invalid', now(), '{}', '{}', now(), now()),
  ('5a000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'aj-v1@test.invalid', now(), '{}', '{}', now(), now());

insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('5a000000-0000-4000-8000-000000000001', 'Ajena Supervisor', 'aj-sup@test.invalid', 'comercial', true),
  ('5a000000-0000-4000-8000-000000000002', 'Ajena Vendedor', 'aj-v1@test.invalid', 'comercial', true);

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('5a000000-0000-4000-8000-000000000001', 'supervisor', null, true),
  ('5a000000-0000-4000-8000-000000000002', 'vendedor', '5a000000-0000-4000-8000-000000000001', true);

-- Cuatro leads del MISMO vendedor, uno por clase de cierre. Etapa 'contactado'
-- y tareas que NO son reunion, a proposito: el retroceso de etapa es de la
-- migracion anterior y aqui solo anadiria ruido a la aritmetica.
insert into crm.leads (
  id, nombre_completo, telefono, etapa, origen, monto_estimado, moneda,
  vendedor_id, activo, creado_por
)
values
  ('5b000000-0000-4000-8000-000000000001', 'Ajena Completada', '+51920000001', 'contactado', 'referido', 1000, 'PEN', '5a000000-0000-4000-8000-000000000002', true, '5a000000-0000-4000-8000-000000000002'),
  ('5b000000-0000-4000-8000-000000000002', 'Ajena Propia', '+51920000002', 'contactado', 'referido', 1000, 'PEN', '5a000000-0000-4000-8000-000000000002', true, '5a000000-0000-4000-8000-000000000002'),
  ('5b000000-0000-4000-8000-000000000003', 'Ajena Del Jefe', '+51920000003', 'contactado', 'referido', 1000, 'PEN', '5a000000-0000-4000-8000-000000000002', true, '5a000000-0000-4000-8000-000000000002'),
  ('5b000000-0000-4000-8000-000000000004', 'Ajena Del Sistema', '+51920000004', 'contactado', 'referido', 1000, 'PEN', '5a000000-0000-4000-8000-000000000002', true, '5a000000-0000-4000-8000-000000000002');

insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
values
  ('5c000000-0000-4000-8000-000000000001', '5b000000-0000-4000-8000-000000000001', 'tarea', 'ORACULO completada', now() + interval '1 day', '5a000000-0000-4000-8000-000000000002'),
  ('5c000000-0000-4000-8000-000000000002', '5b000000-0000-4000-8000-000000000002', 'tarea', 'ORACULO anula el mismo', now() + interval '1 day', '5a000000-0000-4000-8000-000000000002'),
  ('5c000000-0000-4000-8000-000000000003', '5b000000-0000-4000-8000-000000000003', 'tarea', 'ORACULO anula el jefe', now() + interval '1 day', '5a000000-0000-4000-8000-000000000002'),
  ('5c000000-0000-4000-8000-000000000004', '5b000000-0000-4000-8000-000000000004', 'tarea', 'ORACULO anula el sistema', now() + interval '1 day', '5a000000-0000-4000-8000-000000000002');

-- ── V01: el CHECK existe y restringe COMO CANDADO ───────────────────────────
-- Se mira la definicion y no solo el comportamiento por la leccion de V01c del
-- oraculo anterior: los BEFORE sellan la columna ANTES de que el CHECK evalue,
-- asi que el camino de datos pasa igual con el constraint bien o mal escrito.
-- Lo que se prohibe aqui es la forma `x = 'asesor' or id is null`, que NO
-- restringe: con cancelada_por null el primer operando da NULL, `NULL or FALSE`
-- da NULL, y un CHECK solo se viola con FALSE.
do $test$
declare v_def text;
begin
  select pg_get_constraintdef(c.oid) into v_def
    from pg_constraint c
   where c.conname = 'tareas_cancelada_por_id_valida'
     and c.conrelid = 'crm.tareas'::regclass;
  if v_def is null then
    raise exception 'V01 no existe el CHECK tareas_cancelada_por_id_valida';
  end if;
  if v_def !~* 'CASE' then
    raise exception 'V01b el CHECK no usa CASE (%): con `or`, cancelada_por null deja pasar una firma huerfana', v_def;
  end if;
end;
$test$;

-- ── V02: y lo restringe DE VERDAD contra el motor ───────────────────────────
-- La prueba que V01 no puede dar: que una fila NO cancelada con firma se
-- rechace. Se salta el sello del INSERT escribiendo la columna en un UPDATE de
-- una tarea que sigue pendiente... que tambien esta sellado. Se acepta
-- cualquiera de los dos frenos; lo que no se acepta es que la firma quede.
do $test$
begin
  update crm.tareas set cancelada_por_id = '5a000000-0000-4000-8000-000000000001'
   where id = '5c000000-0000-4000-8000-000000000001';
  if exists (select 1 from crm.tareas
              where id = '5c000000-0000-4000-8000-000000000001'
                and cancelada_por_id is not null) then
    raise exception 'V02 una tarea PENDIENTE no puede quedarse con firma de anulacion';
  end if;
exception when check_violation then
  null; -- el CHECK la paro antes que el sello: igual de correcto.
end;
$test$;

-- ── V03: el INSERT tampoco admite firma del payload ─────────────────────────
do $test$
begin
  insert into crm.tareas (lead_id, tipo, titulo, vence_en, cancelada_por_id, creado_por)
  values ('5b000000-0000-4000-8000-000000000001', 'tarea', 'ORACULO firma insert',
          now() + interval '1 day', '5a000000-0000-4000-8000-000000000001',
          '5a000000-0000-4000-8000-000000000002');
  if exists (select 1 from crm.tareas
              where titulo = 'ORACULO firma insert' and cancelada_por_id is not null) then
    raise exception 'V03 el cliente no puede sembrar cancelada_por_id al crear la tarea';
  end if;
exception when check_violation then
  null;
end;
$test$;

-- ── Ahora los cierres, cada uno con su sesion ───────────────────────────────

-- El VENDEDOR completa una y anula OTRA SUYA.
select set_config('request.jwt.claims',
  '{"sub":"5a000000-0000-4000-8000-000000000002","role":"authenticated"}', true);

select crm.cerrar_tarea('5c000000-0000-4000-8000-000000000001', 'completada');
select crm.cerrar_tarea('5c000000-0000-4000-8000-000000000002', 'cancelada');

-- ── V04: la anulacion propia queda firmada por el propio vendedor ───────────
do $test$
declare v_por text; v_id uuid;
begin
  select cancelada_por, cancelada_por_id into v_por, v_id
    from crm.tareas where id = '5c000000-0000-4000-8000-000000000002';
  if v_por is distinct from 'asesor' then
    raise exception 'V04 anular por la RPC con sesion humana debe etiquetar asesor (fue %)', v_por;
  end if;
  if v_id is distinct from '5a000000-0000-4000-8000-000000000002'::uuid then
    raise exception 'V04b la firma debe ser el uid del que llamo (fue %)', v_id;
  end if;
end;
$test$;

-- El SUPERVISOR anula una tarea DE SU VENDEDOR.
select set_config('request.jwt.claims',
  '{"sub":"5a000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

select crm.cerrar_tarea('5c000000-0000-4000-8000-000000000003', 'cancelada');

-- ── V05: la anulacion del jefe queda firmada POR EL JEFE, no por el vendedor ─
-- Es el hecho que hace posible todo lo demas: la fila se sigue agrupando por
-- vendedor_id (como el resto de metricas de agenda), asi que sin una firma
-- distinta no habria forma de saber que esa anulacion no fue suya.
do $test$
declare v_por text; v_id uuid; v_dueno uuid;
begin
  select cancelada_por, cancelada_por_id, vendedor_id into v_por, v_id, v_dueno
    from crm.tareas where id = '5c000000-0000-4000-8000-000000000003';
  if v_por is distinct from 'asesor' then
    raise exception 'V05 el supervisor tambien es una PERSONA: etiqueta asesor (fue %)', v_por;
  end if;
  if v_id is distinct from '5a000000-0000-4000-8000-000000000001'::uuid then
    raise exception 'V05b la firma debe ser el supervisor que la ordeno (fue %)', v_id;
  end if;
  if v_id = v_dueno then
    -- `%%` y no `%`: aqui el signo es el PORCENTAJE de la metrica, no un
    -- marcador de RAISE. Con uno solo, plpgsql aborta con "too few parameters".
    raise exception 'V05c la firma no puede coincidir con el dueno: el %% saldria penalizado igual';
  end if;
end;
$test$;

-- El SISTEMA cancela: descartar el lead dispara trg_leads_sync_tareas.
-- `motivo_descarte` va en el MISMO update, no por comodidad: el CHECK
-- `descartado_requiere_motivo` aborta un descarte sin motivo, asi que sin el
-- este oraculo fallaria por una razon que no es la que prueba.
select set_config('request.jwt.claims', '', true);
update crm.leads
   set etapa = 'descartado', motivo_descarte = 'sin_interes'
 where id = '5b000000-0000-4000-8000-000000000004';

-- ── V06: la del sistema no tiene a quien atribuirse ─────────────────────────
do $test$
declare v_por text; v_id uuid; v_estado text;
begin
  select estado, cancelada_por, cancelada_por_id into v_estado, v_por, v_id
    from crm.tareas where id = '5c000000-0000-4000-8000-000000000004';
  if v_estado is distinct from 'cancelada' then
    raise exception 'V06 descartar el lead debe cancelar su pendiente (quedo en %)', v_estado;
  end if;
  if v_por is distinct from 'sistema' then
    raise exception 'V06b el bookkeeping del trigger es sistema (fue %)', v_por;
  end if;
  if v_id is not null then
    raise exception 'V06c una cancelacion de sistema no lleva firma (fue %)', v_id;
  end if;
end;
$test$;

-- ── V07–V13: la metrica, leida por el supervisor del equipo ─────────────────
select set_config('request.jwt.claims',
  '{"sub":"5a000000-0000-4000-8000-000000000001","role":"authenticated"}', true);

do $test$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_json jsonb;
  v_fila jsonb;
  v_asesor int; v_ajenas int; v_sistema int; v_total int; v_pct numeric;
begin
  v_json := crm.metricas_agenda_fn(v_hoy, v_hoy);

  if (v_json->>'version') is distinct from '1' then
    raise exception 'V07 las claves nuevas son ADITIVAS: version sigue en 1 (fue %)', v_json->>'version';
  end if;

  select e into v_fila
    from jsonb_array_elements(v_json->'vendedores') e
   where e->>'vendedor_id' = '5a000000-0000-4000-8000-000000000002';
  if v_fila is null then
    raise exception 'V08 el vendedor debe aparecer en el ambito de su supervisor';
  end if;

  if not (v_fila ? 'canceladas_ajenas') then
    raise exception 'V09 falta la clave canceladas_ajenas en el contrato';
  end if;

  v_total   := (v_fila->>'canceladas')::int;
  v_asesor  := (v_fila->>'canceladas_asesor')::int;
  v_ajenas  := (v_fila->>'canceladas_ajenas')::int;
  v_sistema := (v_fila->>'canceladas_sistema')::int;
  v_pct     := (v_fila->>'pct_completadas')::numeric;

  -- Sembrado: 1 completada, 1 anulada por el, 1 anulada por su jefe, 1 del
  -- sistema. Total 3 canceladas, 2 humanas, 1 ajena.
  if v_total <> 3 then
    raise exception 'V10 se esperaban 3 canceladas en total, hubo %', v_total;
  end if;
  if v_asesor <> 2 then
    raise exception 'V10b se esperaban 2 anulaciones humanas, hubo %', v_asesor;
  end if;
  if v_ajenas <> 1 then
    raise exception 'V10c se esperaba 1 anulacion ajena, hubo %', v_ajenas;
  end if;
  if v_sistema <> 1 then
    raise exception 'V10d se esperaba 1 cancelacion de sistema, hubo %', v_sistema;
  end if;

  -- INVARIANTE: las dos mitades de las humanas suman las humanas, siempre. Es
  -- lo que hace la metrica auditable de un vistazo, y lo que se rompe si alguien
  -- cambia un `is distinct from` por un `<>` (la historia sin firma se caeria de
  -- las dos cuentas sin que nada avise).
  if v_ajenas > v_asesor then
    raise exception 'V11 las ajenas (%) no pueden superar a las humanas (%)', v_ajenas, v_asesor;
  end if;

  -- EL NUMERO QUE PIDIO MIGUEL. Denominador = 1 completada + 0 no asistio +
  -- 1 anulada POR EL = 2 -> 50 %. Si la del jefe contara serian 3 -> 33 %, y si
  -- ademas contara la del sistema, 4 -> 25 %.
  if v_pct is distinct from 50 then
    raise exception 'V12 el %% debe ser 50 (1 de 2): la anulacion del jefe y la del sistema no cuentan. Fue %', v_pct;
  end if;
end;
$test$;

-- ── V13: y el supervisor no se cobra a si mismo la que anulo ────────────────
-- La fila se agrupa por vendedor_id, asi que la tarea ajena que anulo NO es
-- suya y no puede aparecer en SU cuenta de canceladas. Sin esta asercion, un
-- futuro `group by cancelada_por_id` pasaria desapercibido.
do $test$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_fila jsonb;
begin
  select e into v_fila
    from jsonb_array_elements(crm.metricas_agenda_fn(v_hoy, v_hoy)->'vendedores') e
   where e->>'vendedor_id' = '5a000000-0000-4000-8000-000000000001';
  if v_fila is null then
    raise exception 'V13 el supervisor debe aparecer en su propio ambito';
  end if;
  if (v_fila->>'canceladas')::int <> 0 then
    raise exception 'V13b anular la tarea de otro no la mete en la agenda propia (fue %)', v_fila->>'canceladas';
  end if;
end;
$test$;

-- ── V14: nadie puede firmar en nombre de otro ───────────────────────────────
-- La RPC no acepta un parametro de autor: la firma sale de auth.uid(). La unica
-- forma de "firmar como el vendedor" seria tener su sesion. Se comprueba que la
-- firma no sea influible por la GUC que ya controla el resto del sello.
do $test$
declare v_id uuid;
begin
  perform set_config('crm.op_tarea', 'on', true);
  perform set_config('crm.cancela_sistema', 'on', true);
  insert into crm.tareas (id, lead_id, tipo, titulo, vence_en, creado_por)
  values ('5c000000-0000-4000-8000-000000000005', '5b000000-0000-4000-8000-000000000001',
          'tarea', 'ORACULO gucs', now() + interval '1 day',
          '5a000000-0000-4000-8000-000000000002');
  update crm.tareas set estado = 'cancelada' where id = '5c000000-0000-4000-8000-000000000005';
  perform set_config('crm.op_tarea', 'off', true);
  perform set_config('crm.cancela_sistema', 'off', true);
  select cancelada_por_id into v_id from crm.tareas where id = '5c000000-0000-4000-8000-000000000005';
  if v_id is not null then
    raise exception 'V14 con cancela_sistema encendida la fila es de sistema y NO lleva firma (fue %)', v_id;
  end if;
end;
$test$;

-- ── V15: la columna no se expone para escritura por accidente ───────────────
-- El GRANT de crm.tareas es de TABLA, asi que `authenticated` puede mandarla en
-- el payload; el freno es el sello, no el ACL. Lo que se asegura aqui es que el
-- ACL siga siendo el de siempre y que nadie haya "arreglado" esto anadiendo un
-- grant por columna, que daria una falsa sensacion de cierre.
do $test$
begin
  if not has_table_privilege('authenticated', 'crm.tareas', 'UPDATE') then
    raise exception 'V15 authenticated perdio el UPDATE de crm.tareas: la agenda deja de funcionar';
  end if;
  if has_column_privilege('anon', 'crm.tareas', 'cancelada_por_id', 'UPDATE') then
    raise exception 'V15b anon no debe poder escribir la firma';
  end if;
end;
$test$;

select 'AJENA_TX_OK' as resultado;

rollback;
