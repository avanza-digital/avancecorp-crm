-- Adenda a la siembra: una GERENCIA activa. La pide 20260827090000
-- («POSTFLIGHT VACUO: sin gerencia activa no se puede probar la cadena»).
-- Esto NO es un parche: es el DATO que la prueba necesita, así que la
-- aserción se ejecuta de verdad en vez de neutralizarse.
-- Candados: gerencia NO admite supervisor, y su perfil Portal debe estar
-- activo (y no ser superadmin, que solo admite membresía de gerencia).
begin;
insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data
) values ('b0000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','banco.gerencia@avancecorp.test','',
   now(), now(), now(), '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb)
on conflict (id) do update set updated_at = now(), email_confirmed_at = now();

insert into public.perfiles (
  id, nombre_completo, rol, activo, tipo_documento,
  debe_cambiar_password, titular_distinto, titular_distinto_usd
) values ('b0000000-0000-4000-8000-000000000003','BANCO GERENCIA','admin',true,'DNI',false,false,false)
on conflict (id) do update set activo = true, rol = excluded.rol;

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values ('b0000000-0000-4000-8000-000000000003','gerencia',null,true)
on conflict (perfil_id) do update set rol_crm = 'gerencia', supervisor_id = null, activo = true;

do $ok$
declare v_n int;
begin
  select count(*) into v_n from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.activo and p.activo and e.rol_crm = 'gerencia';
  if v_n < 1 then raise exception 'siembra: sin gerencia activa'; end if;
end $ok$;
commit;
select 'SIEMBRA-GERENCIA-OK' as resultado,
       (select count(*) from crm.equipo where activo) as equipo_activo;
