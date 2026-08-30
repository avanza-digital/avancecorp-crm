-- P-055 · Cierre de sesión de la persona REVOCADA (2026-08-30).
-- La F5.a le quitó los datos; esto le quita la SESIÓN.
-- Solo IVETT TEEVIN: las otras tres membresías revocadas son cuentas de prueba
-- del propio Miguel (avancecorp26+crm-*), y se deciden aparte.
begin;
set local lock_timeout = '5s';

do $$
declare
  v_id uuid := '4e929ee5-b708-4a97-81f8-945e331f2221';
  v_nombre text;
  v_sesiones integer; v_tokens integer;
  v_activo boolean; v_ban timestamptz;
begin
  select p.nombre_completo into v_nombre from public.perfiles p where p.id = v_id;
  if v_nombre is distinct from 'IVETT TEEVIN' then
    raise exception 'Preflight: el id no corresponde a IVETT TEEVIN sino a %', coalesce(v_nombre, '(no existe)');
  end if;
  if exists (select 1 from crm.equipo e where e.perfil_id = v_id and e.activo is true) then
    raise exception 'Preflight: esa persona NO está revocada en el CRM';
  end if;

  -- 1) El perfil del Portal, apagado (es la baja de la casa: nunca borrar).
  update public.perfiles set activo = false where id = v_id;

  -- 2) La sesión abierta, cerrada de verdad: sin esto, un navegador con la
  --    pestaña abierta sigue renovando su llave sola.
  update auth.refresh_tokens set revoked = true where user_id = v_id::text and revoked is false;
  delete from auth.sessions where user_id = v_id;

  -- 3) Y la puerta de entrada, cerrada: aunque alguien reactivara el perfil por
  --    error, no podría iniciar sesión sin levantar esto a mano.
  update auth.users set banned_until = 'infinity'::timestamptz where id = v_id;

  select p.activo into v_activo from public.perfiles p where p.id = v_id;
  select u.banned_until into v_ban from auth.users u where u.id = v_id;
  select count(*) into v_sesiones from auth.sessions where user_id = v_id;
  select count(*) into v_tokens from auth.refresh_tokens where user_id = v_id::text and revoked is false;

  if v_activo is not false or v_sesiones <> 0 or v_tokens <> 0 or v_ban is null then
    raise exception 'Postflight EN ROJO: activo=% sesiones=% tokens=% ban=%', v_activo, v_sesiones, v_tokens, v_ban;
  end if;
  raise notice 'OK';
end $$;

commit;

select p.nombre_completo, p.activo as perfil_activo, u.banned_until,
       (select count(*) from auth.sessions s where s.user_id = p.id) as sesiones,
       (select count(*) from auth.refresh_tokens r where r.user_id = p.id::text and r.revoked is false) as tokens_vivos
  from public.perfiles p join auth.users u on u.id = p.id
 where p.id = '4e929ee5-b708-4a97-81f8-945e331f2221';
