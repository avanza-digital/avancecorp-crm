-- Prueba de humo del flujo VIVO del portal, sin dejar nada: termina SIEMPRE en
-- raise, así que la transacción entera se deshace.
do $humo$
declare
  v_cliente uuid;
  v_id uuid;
  v_antes int;
  v_tras_alta int;
  v_tras_reloj int;
  v_tras_cambio int;
  v_fuga int;
begin
  select id into v_cliente from public.perfiles where rol='cliente' and activo limit 1;

  select count(*) into v_antes from public.audit_log where tabla='public.suscripciones_push';

  -- 1. Alta (lo que hace el portal al suscribir un dispositivo)
  insert into public.suscripciones_push (cliente_id, endpoint, p256dh, auth, dispositivo, user_agent, activo)
  values (v_cliente, 'https://fcm.googleapis.com/PRUEBA-HUMO', 'clave-p256dh-de-prueba', 'clave-auth-de-prueba', 'Prueba', 'humo', true)
  returning id into v_id;
  select count(*) into v_tras_alta from public.audit_log where tabla='public.suscripciones_push';

  -- 2. El upsert de cada carga del panel: mismas columnas, mismos valores
  update public.suscripciones_push
     set cliente_id = v_cliente, endpoint = 'https://fcm.googleapis.com/PRUEBA-HUMO',
         p256dh = 'clave-p256dh-de-prueba', auth = 'clave-auth-de-prueba',
         dispositivo = 'Prueba', activo = true, actualizado_en = now()
   where id = v_id;
  select count(*) into v_tras_reloj from public.audit_log where tabla='public.suscripciones_push';

  -- 3. Un cambio de verdad
  update public.suscripciones_push set activo = false where id = v_id;
  select count(*) into v_tras_cambio from public.audit_log where tabla='public.suscripciones_push';

  select count(*) into v_fuga from public.audit_log
  where tabla='public.suscripciones_push'
    and (data_antes::text || coalesce(data_despues::text,'')) like '%clave-p256dh-de-prueba%';

  if v_tras_alta <> v_antes + 1 then
    raise exception 'FALLO: el alta no dejó rastro (% -> %)', v_antes, v_tras_alta;
  end if;
  if v_tras_reloj <> v_tras_alta then
    raise exception 'FALLO: el guardado repetido del portal ENSUCIA la auditoría (% filas de más)', v_tras_reloj - v_tras_alta;
  end if;
  if v_tras_cambio <> v_tras_reloj + 1 then
    raise exception 'FALLO: un cambio real NO dejó rastro';
  end if;
  if v_fuga > 0 then
    raise exception 'FUGA: la clave push aparece en claro en % fila(s)', v_fuga;
  end if;

  raise exception 'HUMO_OK: alta auditada · el guardado repetido del portal NO ensucia · el cambio real sí queda · 0 fugas. Nada de esto se guarda: la transacción se deshace.';
end
$humo$;
