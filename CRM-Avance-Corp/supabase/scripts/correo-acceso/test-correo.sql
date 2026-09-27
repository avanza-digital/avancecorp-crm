-- Oráculo real de Postgres, con rollback. El runner sólo admite el banco propio.
begin;
set local statement_timeout='60s';
create function pg_temp.exigir(ok boolean, caso text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'CORREO: %',caso; end if; raise notice 'PASS: %',caso; end $$;
create function pg_temp.rechaza(sentencia text, codigo text, caso text) returns void language plpgsql as $$
begin
  begin execute sentencia;
  exception when others then
    if sqlstate=codigo then raise notice 'PASS: %',caso; return; end if;
    raise exception '%: esperado %, recibido % (%)',caso,codigo,sqlstate,sqlerrm;
  end;
  raise exception 'CORREO aceptó: %',caso;
end $$;
create temporary table caso_correo(solicitud uuid, persona uuid, lead uuid, datos jsonb, reclamo jsonb, clave_correccion uuid, perfil uuid);
grant select on caso_correo to authenticated;
select set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000004',true);
do $$
declare l uuid:='c0000000-0000-4000-8000-000000000081'; p uuid; s uuid:=gen_random_uuid(); d jsonb; r jsonb;
begin
  update crm.leads set correo='original@example.invalid' where id=l;
  p:=(crm.preparar_persona_lead_inversion_fn(l,'DNI','79100001','PERSONA PRUEBA CORREO')->>'inversionista_id')::uuid;
  d:=jsonb_build_object('inversionista_id',p,'lead_id',l,'empresa','avance','contrato',jsonb_build_object('moneda','PEN'),
    'cronograma','[]'::jsonb,'cuenta','{}'::jsonb,'alta_portal',jsonb_build_object('correo','revision@example.invalid',
      'nombre_completo','PERSONA PRUEBA CORREO','nombres','PERSONA','apellidos','PRUEBA CORREO','telefono','999123456','domicilio','AVENIDA SINTETICA 123 LIMA'));
  r:=crm.preparar_inversion_fn(s,d);
  insert into caso_correo values(s,p,l,d,null,gen_random_uuid(),gen_random_uuid());
  perform pg_temp.exigir((select correo='revision@example.invalid' from crm.leads where id=l),'preparar acceso actualiza también la ficha');
end $$;
set local role authenticated;
update crm.leads set correo='  FICHA@example.invalid ' where id=(select lead from caso_correo);
reset role;
do $$
declare c caso_correo%rowtype; s crm.inversion_solicitudes%rowtype; r jsonb; d jsonb; g crm.multiempresa_idempotencia%rowtype;
  correcciones bigint; v integer;
begin
  select * into c from caso_correo;
  select * into s from crm.inversion_solicitudes where id=c.solicitud;
  perform pg_temp.exigir(s.datos#>>'{alta_portal,correo}'='ficha@example.invalid' and s.revision_datos=1,'edición RLS de ficha sincroniza correo y revisión sin claim');
  perform pg_temp.exigir((select count(*)=1 from crm.inversion_solicitud_correcciones where solicitud_id=s.id and corregido_por=s.creado_por),'edición de ficha auditada con actor real');
  r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
  update caso_correo set reclamo=r;
  select * into g from crm.multiempresa_idempotencia where clave='auth_persona:'||c.persona;
  v:=g.version;
  d:=jsonb_set(s.datos,'{alta_portal,correo}','"manual@example.invalid"');
  r:=crm.corregir_solicitud_inversion_fn(c.solicitud,c.clave_correccion,s.revision_datos,d,'Corregir correo antes del primer acceso');
  perform pg_temp.exigir((select correo='manual@example.invalid' from crm.leads where id=c.lead),'corrección manual sincroniza ficha');
  perform pg_temp.exigir((select auth_claim_id=(g.resultado->>'claim_id')::uuid and hash_payload=s.hash_payload from crm.inversion_solicitudes where id=s.id),'conserva claim y huella original de preparación');
  perform pg_temp.exigir((select version=v+1 and resultado->>'token_hash'=g.resultado->>'token_hash' from crm.multiempresa_idempotencia where clave=g.clave),'reserva activa corregible: conserva token e incrementa versión');
  perform pg_temp.exigir((select hash_payload=private.idem_hash(private.inversion_payload_acceso(c.persona,d->'alta_portal',s.responsable_esperado_id::text)) from crm.multiempresa_idempotencia where clave=g.clave),'huella corregida coincide con la que reclamará el acceso');
  -- s precede al reclamo: el responsable del hash está en el contexto actual.
  select count(*) into correcciones from crm.inversion_solicitud_correcciones where solicitud_id=s.id;
  r:=crm.corregir_solicitud_inversion_fn(c.solicitud,c.clave_correccion,s.revision_datos,d,'Corregir correo antes del primer acceso');
  perform pg_temp.exigir((r->>'reintento')::boolean and (select count(*)=correcciones from crm.inversion_solicitud_correcciones where solicitud_id=s.id),'respuesta perdida de corrección es idempotente');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,%s,%L::jsonb,%L)',s.id,gen_random_uuid(),s.revision_datos,d,'Otra corrección con versión antigua'),'PT409','versión antigua no pisa la corrección');
  update crm.leads set correo='ficha-con-reserva@example.invalid' where id=c.lead;
  perform pg_temp.exigir((select datos#>>'{alta_portal,correo}'='ficha-con-reserva@example.invalid' and revision_datos=3 from crm.inversion_solicitudes where id=s.id),'ficha también sincroniza una reserva activa');
  perform pg_temp.rechaza(format('insert into auth.users(id,aud,role,email,raw_app_meta_data) values(%L,%L,%L,%L,%L::jsonb)',
    gen_random_uuid(),'authenticated','authenticated','manual@example.invalid',jsonb_build_object('claim_id',g.resultado->>'claim_id')),
    'P0409','un intento Auth tardío no crea el correo anterior');
  perform pg_temp.exigir(not exists(select 1 from auth.users where raw_app_meta_data->>'claim_id'=g.resultado->>'claim_id'),'rechazo tardío no deja usuario huérfano');
  r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
  insert into auth.users(id,aud,role,email,raw_app_meta_data)
    values(c.perfil,'authenticated','authenticated','ficha-con-reserva@example.invalid',jsonb_build_object('claim_id',r->>'claim_id'));
  perform pg_temp.exigir((select resultado->>'auth_insertado_id'=c.perfil::text and version=(r->>'version')::int and resultado->>'estado'='reclamado' from crm.multiempresa_idempotencia where clave=g.clave),'Auth y marcador atómicos sin cambiar versión CAS');
  select * into s from crm.inversion_solicitudes where id=c.solicitud;
  d:=jsonb_set(s.datos,'{alta_portal,correo}','"no-reasignar@example.invalid"');
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,%s,%L::jsonb,%L)',s.id,gen_random_uuid(),s.revision_datos,d,'Corrección después de respuesta perdida de Auth'),'P0409','Auth existente con respuesta perdida no se reasigna');
  update crm.leads set correo=null where id=c.lead;
  perform pg_temp.exigir((select correo is null from crm.leads where id=c.lead) and (select email='ficha-con-reserva@example.invalid' from auth.users where id=c.perfil),'edición de contacto tras Auth no modifica credenciales ni bloquea la ficha');
  r:=crm.acceso_inversion_fn(c.solicitud,'registrar_auth',jsonb_build_object('token',repeat('a',48),'version',r->'version','auth_user_id',c.perfil));
  r:=crm.acceso_inversion_fn(c.solicitud,'crear_perfil',jsonb_build_object('token',repeat('a',48),'version',r->'version'));
  r:=crm.acceso_inversion_fn(c.solicitud,'enlazar',jsonb_build_object('token',repeat('a',48),'version',r->'version'));
  perform pg_temp.exigir(r->>'perfil_id'=c.perfil::text,'el contrato Edge anterior completa la saga corregida');
  perform pg_temp.exigir((select count(*)=1 from public.perfiles where id=c.perfil),'no duplica perfiles');
  perform pg_temp.exigir(not exists(select 1 from crm.inversiones where inversionista_id=c.persona),'corregir o crear acceso no confirma inversión');
  perform pg_temp.exigir((select etapa<>'convertido' from crm.leads where id=c.lead),'el lead espera la confirmación comercial');
  perform set_config('request.jwt.claim.sub','c0000000-0000-4000-8000-000000000006',true);
  perform pg_temp.rechaza(format('select crm.corregir_solicitud_inversion_fn(%L,%L,%s,%L::jsonb,%L)',s.id,gen_random_uuid(),s.revision_datos,d,'Actor fuera de la cartera de la persona'),'42501','corrección fuera de ámbito denegada');
end $$;
-- Un alta ajena a inversiones conserva su comportamiento.
insert into auth.users(id,aud,role,email,raw_app_meta_data) values(gen_random_uuid(),'authenticated','authenticated','sin-claim@example.invalid','{}');
select pg_temp.exigir(exists(select 1 from auth.users where email='sin-claim@example.invalid'),'signup ajeno sin claim permitido');
insert into auth.users(id,aud,role,email,raw_app_meta_data) values(gen_random_uuid(),'authenticated','authenticated','otro-flujo@example.invalid',jsonb_build_object('claim_id',gen_random_uuid()));
select pg_temp.exigir(exists(select 1 from auth.users where email='otro-flujo@example.invalid'),'claim ajeno a inversión permitido');
rollback;
