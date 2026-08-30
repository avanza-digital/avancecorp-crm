-- PRUEBA DE SECRETOS de la F1.4 — ⛔ SOLO en un espejo desechable, NUNCA en
-- producción: escribe filas de prueba (perfil, agenda, dispositivo, operación).
--
-- Cómo montar el espejo y correrla:
--   psql "$PG/postgres" -c "create database f14_prueba"
--   psql "$PG/f14_prueba" -f supabase/scripts/espejo-f1-4-stubs.sql
--   psql "$PG/f14_prueba" -f supabase/migrations/20260829230000_crm_f1_4_regla_de_auditoria.sql
--   psql "$PG/f14_prueba" -f supabase/scripts/prueba-secretos-f1-4.sql
--
-- Qué demuestra: que el token ICS y las claves push NO llegan a public.audit_log
-- en claro, que el toque de `actualizado_en` no ensucia la auditoría, y que el
-- dinero de cartera sí deja rastro.
do $prueba$
declare
  v_token uuid := '11111111-2222-3333-4444-555555555555';
  v_persona uuid := gen_random_uuid();
  v_filtrado int;
  v_filas int;
  v_huella text;
begin
  insert into public.perfiles (id, rol) values (v_persona, 'analista');

  -- agenda_ics: alta, rotación y baja del token
  insert into crm.agenda_ics (perfil_id, token) values (v_persona, v_token);
  update crm.agenda_ics set token = gen_random_uuid() where perfil_id = v_persona;
  delete from crm.agenda_ics where perfil_id = v_persona;

  -- suscripciones_push: alta, toque de reloj (NO debe auditarse) y baja
  insert into public.suscripciones_push (cliente_id, endpoint, p256dh, auth, dispositivo)
  values (v_persona, 'https://push.example/xyz', 'clave-publica-secreta', 'clave-auth-secreta', 'iPhone');
  update public.suscripciones_push set actualizado_en = now() where cliente_id = v_persona;
  update public.suscripciones_push set activo = false where cliente_id = v_persona;
  delete from public.suscripciones_push where cliente_id = v_persona;

  -- operaciones_cartera: el dinero
  insert into crm.operaciones_cartera (capital_renovado, periodo) values (200000, date '2026-08-01');

  select count(*) into v_filtrado from public.audit_log
  where (data_antes::text || coalesce(data_despues::text,'')) ~
        '(11111111-2222-3333|clave-publica-secreta|clave-auth-secreta|push\.example)';

  select count(*) into v_filas from public.audit_log where tabla in ('crm.agenda_ics','public.suscripciones_push');
  select data_despues ->> 'token' into v_huella from public.audit_log
  where tabla = 'crm.agenda_ics' and operacion = 'INSERT';

  if v_filtrado > 0 then
    raise exception 'FUGA: % fila(s) de auditoría contienen el secreto en claro', v_filtrado;
  end if;
  -- 3 de agenda_ics (alta, rotación, baja) + 3 de push (alta, cambio de activo, baja).
  -- El toque de actualizado_en NO cuenta: por eso son 6 y no 7.
  if v_filas <> 6 then
    raise exception 'Se esperaban 6 movimientos auditados (el toque de reloj NO cuenta), hay %', v_filas;
  end if;
  if v_huella <> '***:' || left(md5(v_token::text), 8) then
    raise exception 'La huella del token no es la esperada: %', v_huella;
  end if;
  if not exists (select 1 from public.audit_log where tabla = 'crm.operaciones_cartera' and operacion = 'INSERT') then
    raise exception 'El dinero de cartera no dejó rastro';
  end if;

  raise notice 'SECRETOS OK: 6 movimientos auditados, 0 fugas, huella del token = %, el toque de reloj no ensucia', v_huella;
end
$prueba$;
