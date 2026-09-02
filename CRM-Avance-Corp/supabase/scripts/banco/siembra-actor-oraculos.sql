-- Adenda a la siembra: EL ACTOR QUE LOS ORACULOS SUPLANTAN.
--
-- Varias migraciones de la F4 llevan su oraculo de paridad dentro y suplantan
-- a un administrador REAL de produccion por su UUID literal
-- (`bf1c562e-ed08-4cc3-92a8-34f1fa3e9127`). En un banco ese perfil no existe,
-- asi que `public.es_admin()` devuelve false y el oraculo muere con
-- «No autorizado» — no por un fallo, sino porque le falta el actor.
--
-- Esto NO es un parche de banco: no se toca ni una asercion. Es el DATO que la
-- prueba necesita para ejecutarse de verdad. Se siembra el mismo UUID que usa
-- produccion, con rol de portal `admin` (que es lo que `es_admin()` exige) y
-- SIN membresia de CRM: el oraculo solo necesita que pase el gate del portal.
--
-- 🔴 Nombre deliberadamente reconocible: si alguna vez aparece en una pantalla,
--    debe cantar que es de banco y no un usuario real.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data
) values ('bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','banco.actor.oraculos@avancecorp.test','',
   now(), now(), now(), '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb)
on conflict (id) do update set updated_at = now(), email_confirmed_at = now();

insert into public.perfiles (
  id, nombre_completo, rol, activo, tipo_documento,
  debe_cambiar_password, titular_distinto, titular_distinto_usd
) values ('bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','BANCO ACTOR DE ORACULOS','admin',true,'DNI',false,false,false)
on conflict (id) do update set activo = true, rol = 'admin';

-- Y su asiento de CRM. Los oraculos de la F4.b lo suplantan contra puertas del
-- CRM (`crm.resumen_cartera_clientes_fn`), cuyo gate no mira el rol del portal
-- sino `private.rol_crm()`: sin membresia devuelve «No autorizado».
-- En produccion ese mismo UUID es admin en el portal Y gerencia en el CRM, que
-- es el PAR declarado del proyecto (gerencia real = admin en el portal), asi
-- que sembrar el par es ser fiel a produccion, no un atajo.
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values ('bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','gerencia',null,true)
on conflict (perfil_id) do update set rol_crm = 'gerencia', supervisor_id = null, activo = true;

do $ok$
begin
  -- Las comprobaciones se hacen CON EL ACTOR PUESTO: que exista la fila no
  -- prueba que el gate lo deje pasar, que es lo unico que le importa al oraculo.
  perform set_config('request.jwt.claims',
    json_build_object('sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','role','authenticated')::text, true);
  if not public.es_admin() then
    raise exception 'siembra: el actor de los oraculos NO pasa es_admin()';
  end if;
  if private.rol_crm('bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'::uuid) is distinct from 'gerencia' then
    raise exception 'siembra: el actor de los oraculos NO es gerencia en el CRM';
  end if;
  perform set_config('request.jwt.claims', '', true);
end $ok$;

commit;

select 'SIEMBRA-ACTOR-ORACULOS-OK' as resultado,
       (select count(*) from public.perfiles where activo and rol in ('admin','superadmin')) as admins_activos;
