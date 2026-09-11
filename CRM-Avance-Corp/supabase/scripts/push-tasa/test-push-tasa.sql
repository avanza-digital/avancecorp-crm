\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() !~ '^crm_push_tasa_' then raise exception 'Este banco exige una base local crm_push_tasa_*'; end if;
end $$;
create temp table resultados_push(etiqueta text);
create function pg_temp.ok(p_condicion boolean,p_etiqueta text) returns void language plpgsql as $$
begin
  if p_condicion is distinct from true then raise exception 'FAIL: %',p_etiqueta; end if;
  insert into resultados_push values(p_etiqueta);
end $$;
create function pg_temp.actor(p_id uuid) returns void language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('sub',p_id,'session_id',p_id,'role','authenticated')::text,true);
$$;
create function pg_temp.servicio() returns void language sql as $$
  select set_config('request.jwt.claims','{"role":"service_role"}',true);
$$;
create temp sequence consecutivo_push;
create function pg_temp.nueva_solicitud(p_actor uuid default 'f3000000-0000-0000-0000-000000000001') returns uuid
language plpgsql as $$
declare v_num bigint := nextval('consecutivo_push'); v_lead uuid := gen_random_uuid(); v_resultado jsonb;
begin
  perform pg_temp.actor(p_actor);
  insert into crm.leads(id,nombre_completo,telefono,dni,origen,monto_estimado,vendedor_id,creado_por)
  values(v_lead,'QA PUSH SINTETICO '||v_num,'+51997'||lpad(v_num::text,6,'0'),
    '797'||lpad(v_num::text,5,'0'),'otro',20000,'f3000000-0000-0000-0000-000000000001',p_actor);
  v_resultado := crm.solicitar_tasa_fn(jsonb_build_object('lead_id',v_lead,
    'categoria','nuevo','capital',20000,'moneda','PEN','modalidad','mensual',
    'tipo_interes','simple','fecha_inicio',current_date+1,
    'fecha_vencimiento',(current_date+1)+interval '1 year',
    'tasa_solicitada',18,'motivo','Prueba sintética de notificaciones'));
  return (v_resultado->>'id')::uuid;
end $$;

-- Actores existentes del banco F3; todos los cambios del fixture se revierten.
insert into auth.sessions(id,user_id,aal)
select perfil_id,perfil_id,'aal1' from crm.equipo where perfil_id::text like 'f300%'
on conflict(id) do update set not_after=null;
update crm.multiempresa_flags set activo=false where nombre in ('resolver_en_puertas','inversiones_escritura');
insert into crm.politica_rentabilidad(version,vigente_desde,tasa_base_nueva,tope_tecnico,vigencia_solicitud_dias,modo)
select coalesce(max(version),0)+1,clock_timestamp()-interval '1 hour',15,50,7,'enforcement' from crm.politica_rentabilidad;

select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in
  ('crm.dispositivos_push_tasa'::regclass,'crm.envios_push_tasa'::regclass)),'RLS activada en ambas tablas');
select pg_temp.ok(not has_table_privilege('authenticated','crm.dispositivos_push_tasa','SELECT')
  and not has_table_privilege('authenticated','crm.envios_push_tasa','INSERT'),'sin acceso directo de authenticated');
select pg_temp.ok(not has_function_privilege('anon','crm.verificar_cron_push_tasa_fn(text,bigint)','EXECUTE')
  and not has_function_privilege('authenticated','crm.verificar_cron_push_tasa_fn(text,bigint)','EXECUTE'),
  'solo el servicio puede validar firmas del cron');
select pg_temp.ok(not has_function_privilege('anon','crm.registrar_push_tasa_fn(text,text,text)','EXECUTE')
  and not has_function_privilege('authenticated','crm.tomar_envios_push_tasa_fn(integer)','EXECUTE')
  and not has_function_privilege('authenticated','crm.confirmar_envio_push_tasa_fn(uuid,uuid,text,integer)','EXECUTE'),
  'anon no registra; un usuario no reclama ni confirma avisos');
select pg_temp.ok(not exists(select 1 from pg_policy where polrelid in
  ('crm.dispositivos_push_tasa'::regclass,'crm.envios_push_tasa'::regclass)), 'tablas cerradas sin policy DELETE');

select pg_temp.actor('f3000000-0000-0000-0000-000000000001');
set local role authenticated;
do $$ begin
  begin perform crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('B',87),repeat('a',22));
    raise exception 'Un vendedor pudo suscribirse'; exception when insufficient_privilege then null; end;
  begin perform * from crm.dispositivos_push_tasa;
    raise exception 'El usuario leyó claves'; exception when insufficient_privilege then null; end;
  begin perform crm.tomar_envios_push_tasa_fn(10);
    raise exception 'El usuario reclamó avisos'; exception when insufficient_privilege then null; end;
  begin perform crm.materializar_envio_push_tasa_fn(gen_random_uuid(),gen_random_uuid());
    raise exception 'El usuario materializó avisos'; exception when insufficient_privilege then null; end;
  begin perform crm.confirmar_envio_push_tasa_fn(gen_random_uuid(),gen_random_uuid(),'enviado',201);
    raise exception 'El usuario confirmó avisos'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select pg_temp.ok(true,'denegaciones reales con SET ROLE authenticated');

select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
select pg_temp.ok((crm.estado_push_tasa_fn()->>'configurado')::boolean=false,'sin configuración no aparenta estar listo');
create temp table ids_push(nombre text primary key,id uuid);
insert into ids_push values('telefono',crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('B',87),repeat('a',22)));
insert into ids_push values('tablet',crm.registrar_push_tasa_fn('https://web.push.apple.com/solo-banco',repeat('C',87),repeat('b',22)));
select pg_temp.ok(crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('B',87),repeat('a',22))=
  (select id from ids_push where nombre='telefono'),'activar dos veces conserva el mismo dispositivo');
select pg_temp.ok((select count(*)=2 from crm.dispositivos_push_tasa),'dos dispositivos de una cuenta');
do $$ declare destino text; begin
  foreach destino in array array['https://127.0.0.1/internal','http://fcm.googleapis.com/a',
      'https://fcm.googleapis.com.evil.invalid/a','https://fcm.googleapis.com@evil.invalid/a'] loop
    begin perform crm.registrar_push_tasa_fn(destino,repeat('B',87),repeat('a',22));
      raise exception 'Se aceptó un destino peligroso'; exception when invalid_parameter_value then null; end;
  end loop;
end $$;
select pg_temp.ok(true,'SQL rechaza destinos peligrosos');

-- Una segunda Gerencia no puede apropiarse del endpoint ni desactivar otro.
select pg_temp.servicio();
update crm.equipo set rol_crm='gerencia' where perfil_id='f3000000-0000-0000-0000-000000000003';
select pg_temp.actor('f3000000-0000-0000-0000-000000000003');
do $$ begin
  begin perform crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('B',87),repeat('a',22));
    raise exception 'Otro gerente tomó el endpoint'; exception when insufficient_privilege then null; end;
end $$;
select crm.desactivar_push_tasa_fn((select id from ids_push where nombre='telefono'));
select pg_temp.ok((select activo from crm.dispositivos_push_tasa where id=(select id from ids_push where nombre='telefono')),
  'desactivar un dispositivo ajeno no lo altera');
select pg_temp.ok(crm.estado_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco')->'dispositivo'='null'::jsonb,
  'otro gerente no descubre el dispositivo');
insert into ids_push values('otro-gerente',crm.registrar_push_tasa_fn('https://updates.push.services.mozilla.com/wpush/v2/solo-banco',repeat('D',87),repeat('c',22)));

insert into ids_push values('solicitud',pg_temp.nueva_solicitud());
select pg_temp.ok((select count(*)=3 from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='solicitud')),
  'RPC real de solicitud crea un aviso por dispositivo elegible');
select pg_temp.ok((select count(*)=count(distinct (solicitud_id,dispositivo_id)) from crm.envios_push_tasa),'sin duplicados de solicitud/dispositivo');
insert into ids_push values('propia',pg_temp.nueva_solicitud('f3000000-0000-0000-0000-000000000002'));
select pg_temp.ok((select count(*)=1 from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='propia')),
  'la solicitud propia solo avisa a otra Gerencia');
select pg_temp.servicio();
create temp table lote_push as select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
select pg_temp.ok((select count(*)=4 from lote_push),'el worker reclama el lote esperado');
select pg_temp.ok(crm.tomar_envios_push_tasa_fn(20)='[]'::jsonb,'un segundo worker no toma reservas vivas');
select pg_temp.ok((select bool_and(crm.materializar_envio_push_tasa_fn(id,reserva) is not null) from lote_push),'materializa solo con reserva vigente');
select pg_temp.ok(not crm.confirmar_envio_push_tasa_fn((select id from lote_push limit 1),gen_random_uuid(),'enviado',201),
  'una reserva ajena no confirma');
select crm.confirmar_envio_push_tasa_fn(id,reserva,'enviado',201) from lote_push;
select pg_temp.ok((select bool_and(estado='enviado') from crm.envios_push_tasa),'confirmación final registrada');
select pg_temp.ok(crm.tomar_envios_push_tasa_fn(20)='[]'::jsonb,'el cron no vuelve a enviar lo confirmado');

-- Resolver por la puerta real cancela un envío aún no entregado.
insert into ids_push values('resolver',pg_temp.nueva_solicitud());
select pg_temp.servicio();
truncate lote_push;
insert into lote_push select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
select crm.resolver_solicitud_tasa_fn((select id from ids_push where nombre='resolver'),'rechazar',null,'Prueba sintética')->>'estado';
select pg_temp.servicio();
select pg_temp.ok((select bool_and(crm.materializar_envio_push_tasa_fn(id,reserva) is null) from lote_push),'resolver antes de enviar impide el aviso');
select crm.tomar_envios_push_tasa_fn(20);
select pg_temp.ok((select bool_and(e.reserva=l.reserva) from crm.envios_push_tasa e join lote_push l on l.id=e.id),
  'otro worker conserva las reservas en curso aunque la solicitud se resuelva');
select crm.confirmar_envio_push_tasa_fn(id,reserva,'cancelado',null) from lote_push;
select pg_temp.ok((select bool_and(estado='cancelado') from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='resolver')),
  'el worker cancela los avisos de solicitudes resueltas');

-- Cierre de sesión y revocación del perfil se comprueban al entregar.
insert into ids_push values('revocacion',pg_temp.nueva_solicitud());
select pg_temp.servicio();
truncate lote_push;
insert into lote_push select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
update auth.sessions set not_after=now()-interval '1 second' where id='f3000000-0000-0000-0000-000000000002';
update public.perfiles set activo=false where id='f3000000-0000-0000-0000-000000000003';
select pg_temp.ok((select bool_and(crm.materializar_envio_push_tasa_fn(id,reserva) is null) from lote_push),'sesión vencida y perfil inactivo dejan de recibir');
select crm.tomar_envios_push_tasa_fn(20);
select crm.confirmar_envio_push_tasa_fn(id,reserva,'cancelado',null) from lote_push;
update auth.sessions set not_after=null where id='f3000000-0000-0000-0000-000000000002';
update public.perfiles set activo=true where id='f3000000-0000-0000-0000-000000000003';

-- Reintentos, reservas vencidas y 410.
insert into ids_push values('reintento',pg_temp.nueva_solicitud());
select pg_temp.servicio();
truncate lote_push;
insert into lote_push select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
select crm.confirmar_envio_push_tasa_fn(id,reserva,'reintentar',503) from lote_push;
select pg_temp.ok(crm.tomar_envios_push_tasa_fn(20)='[]'::jsonb,'respeta la espera antes del reintento');
update crm.envios_push_tasa set disponible_en=now()-interval '1 minute' where estado='pendiente';
truncate lote_push;
insert into lote_push select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
select pg_temp.ok((select count(*)=3 from lote_push),'un fallo temporal vuelve a intentarse');
select crm.confirmar_envio_push_tasa_fn(id,reserva,'invalido',410) from lote_push;
select pg_temp.ok(not exists(select 1 from crm.dispositivos_push_tasa where activo),'410 desactiva las suscripciones vencidas');

select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
select crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('B',87),repeat('a',22));
insert into ids_push values('revision',pg_temp.nueva_solicitud());
select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
select crm.registrar_push_tasa_fn('https://fcm.googleapis.com/fcm/send/solo-banco',repeat('E',87),repeat('a',22));
select pg_temp.servicio();
select pg_temp.ok(crm.tomar_envios_push_tasa_fn(20)='[]'::jsonb,'un cambio de claves invalida la cola de la suscripción anterior');

select pg_temp.actor('f3000000-0000-0000-0000-000000000002');
select pg_temp.ok(crm.preparar_prueba_push_tasa_fn((select id from ids_push where nombre='telefono'))->>'endpoint' is not null,
  'el usuario puede preparar una prueba propia');
do $$ begin
  begin perform crm.preparar_prueba_push_tasa_fn((select id from ids_push where nombre='telefono'));
    raise exception 'Faltó límite de pruebas'; exception when sqlstate 'P0429' then null; end;
end $$;
select pg_temp.ok(true,'prueba limitada a una por minuto');
select pg_temp.ok(not exists(select 1 from public.audit_log where tabla='crm.dispositivos_push_tasa'
  and (data_despues->>'endpoint' like 'https://%' or data_despues->>'p256dh'=repeat('B',87)
    or data_despues->>'auth'=repeat('a',22))), 'auditoría no filtra suscripciones ni claves');

-- Fallo real del auxiliar: la solicitud de negocio sobrevive y el cron recupera.
create function pg_temp.fallar_cola() returns trigger language plpgsql as $$
begin raise exception 'Fallo sintético de la cola'; end $$;
create trigger fallo_push_qa before insert on crm.envios_push_tasa for each row execute function pg_temp.fallar_cola();
insert into ids_push values('recuperacion',pg_temp.nueva_solicitud());
select pg_temp.ok(exists(select 1 from crm.solicitudes_tasa where id=(select id from ids_push where nombre='recuperacion')),
  'el fallo de notificación no impide solicitar la tasa');
select pg_temp.ok(not exists(select 1 from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='recuperacion')),
  'la inyección de fallo realmente impidió crear el aviso');
drop trigger fallo_push_qa on crm.envios_push_tasa;
select pg_temp.servicio();
update crm.dispositivos_push_tasa set habilitado_en=now()+interval '1 minute' where activo;
select private.reconciliar_push_tasa();
select pg_temp.ok(not exists(select 1 from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='recuperacion')),
  'activar después de una solicitud no envía ese aviso histórico');
update crm.dispositivos_push_tasa set habilitado_en=now() where activo;
select private.reconciliar_push_tasa();
select pg_temp.ok((select count(*)=1 from crm.envios_push_tasa where solicitud_id=(select id from ids_push where nombre='recuperacion')),
  'el cron recupera el aviso faltante sin enviar el historial a dispositivos nuevos');
truncate lote_push;
insert into lote_push select * from jsonb_to_recordset(crm.tomar_envios_push_tasa_fn(20)) as x(id uuid,reserva uuid);
update crm.envios_push_tasa set reservado_hasta=now()-interval '1 second' where id in(select id from lote_push);
select pg_temp.ok((select bool_and(not crm.confirmar_envio_push_tasa_fn(id,reserva,'enviado',201)) from lote_push),
  'una reserva vencida ya no puede confirmar');
select pg_temp.ok(jsonb_array_length(crm.tomar_envios_push_tasa_fn(20))>0,'un worker recupera reservas abandonadas');
update crm.envios_push_tasa set intentos=8,reservado_hasta=now()-interval '1 second' where estado='enviando';
select pg_temp.ok(crm.tomar_envios_push_tasa_fn(20)='[]'::jsonb,'ocho intentos agotan el envío');
select pg_temp.ok(not exists(select 1 from crm.envios_push_tasa where intentos=8 and estado<>'fallido'),
  'el envío agotado queda cerrado y no consume cron indefinidamente');

-- Contrato real cron -> firma -> verificador. El HTTP se sustituye dentro de
-- ESTA transacción de prueba y vuelve a su definición original con ROLLBACK.
create temp table http_push_qa(url text,cuerpo jsonb,cabeceras jsonb);
create or replace function net.http_post(url text,body jsonb default '{}'::jsonb,
  params jsonb default '{}'::jsonb,headers jsonb default '{"Content-Type":"application/json"}'::jsonb,
  timeout_milliseconds integer default 1000) returns bigint language sql as $$
  insert into pg_temp.http_push_qa values(url,body,headers); select 1::bigint;
$$;
select vault.create_secret('abcdefghijklmnopqrst','crm_push_proyecto');
select vault.create_secret('clave-publica-solo-del-banco-sintetico','cron_notif_secret');
insert into ids_push values('firma-cron',pg_temp.nueva_solicitud());
select pg_temp.servicio();
select private.despertar_push_tasa();
select pg_temp.ok((select count(*)=1 from http_push_qa),'el cron despierta al worker cuando hay trabajo');
select pg_temp.ok((select url='https://abcdefghijklmnopqrst.supabase.co/functions/v1/crm-notificaciones-tasa'
  and cuerpo='{"accion":"procesar"}'::jsonb from http_push_qa),'el cron solo llama al worker de tasa del proyecto configurado');
select pg_temp.ok((select not cabeceras ? 'x-cron-secret'
  and cabeceras::text not like '%clave-publica-solo-del-banco-sintetico%' from http_push_qa),
  'el secreto de Vault nunca se escribe en las cabeceras de pg_net');
select pg_temp.ok((select crm.verificar_cron_push_tasa_fn(cabeceras->>'x-cron-firma',(cabeceras->>'x-cron-instante')::bigint) from http_push_qa),
  'la firma emitida por el cron es aceptada por el verificador real');
select pg_temp.ok((select not crm.verificar_cron_push_tasa_fn(cabeceras->>'x-cron-firma',(cabeceras->>'x-cron-instante')::bigint-121)
  and not crm.verificar_cron_push_tasa_fn(cabeceras->>'x-cron-firma',(cabeceras->>'x-cron-instante')::bigint+31) from http_push_qa),
  'rechaza firmas vencidas o con fecha futura fuera de tolerancia');
select pg_temp.ok((select not crm.verificar_cron_push_tasa_fn(repeat('b',64),(cabeceras->>'x-cron-instante')::bigint)
  and not crm.verificar_cron_push_tasa_fn('clave-publica-solo-del-banco-sintetico',(cabeceras->>'x-cron-instante')::bigint) from http_push_qa),
  'rechaza una firma falsa y el secreto compartido usado directamente');
select pg_temp.ok((select not crm.verificar_cron_push_tasa_fn(encode(extensions.hmac(
  'otro-servicio:abcdefghijklmnopqrst:'||(cabeceras->>'x-cron-instante'),'clave-publica-solo-del-banco-sintetico','sha256'),'hex'),
  (cabeceras->>'x-cron-instante')::bigint) from http_push_qa),'la firma de otro servicio no autoriza este cron');
select pg_temp.ok((select not crm.verificar_cron_push_tasa_fn(encode(extensions.hmac(
  'crm-push-tasa:otroproyectodiferente:'||(cabeceras->>'x-cron-instante'),'clave-publica-solo-del-banco-sintetico','sha256'),'hex'),
  (cabeceras->>'x-cron-instante')::bigint) from http_push_qa),'la firma no se reutiliza entre proyectos');
select 'PASS: '||etiqueta from resultados_push;
select 'TOTAL_PASS='||count(*) from resultados_push;
rollback;
