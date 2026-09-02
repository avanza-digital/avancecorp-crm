-- SIEMBRA MINIMA del banco, intercalada ANTES de 20260812000259.
-- Esa migracion tiene un postflight con HAMBRE DE DATOS: exige un perfil real
-- ACTIVO en crm.equipo para la FK de vendedor_id («en branch el seed corre
-- antes», dice su propio comentario). Todo banco nuevo muere ahi POR DISEÑO.
--
-- La forma la dictan los candados, medidos contra el banco:
--  * `perfiles.id` es FK a `auth.users(id)` ⇒ el usuario va PRIMERO.
--  * `*_token` a '' y nunca NULL (login 500 si son NULL).
--  * cadena SUPERVISOR → VENDEDOR: `validar_supervisor_usuario_crm` rechaza
--    «un vendedor CRM activo requiere un Supervisor activo».
--  * `validar_equipo_usuario_crm` exige `perfiles.activo` true, y que el rol
--    Portal NO sea superadmin salvo gerencia ⇒ va como `analista`.
--  * upserts con DO UPDATE: una ronda fallida deja rastro que un DO NOTHING
--    respeta, y envenena la siguiente.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data
) values
  ('b0000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','banco.supervisor@avancecorp.test','',
   now(), now(), now(), '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb),
  ('b0000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','banco.vendedor@avancecorp.test','',
   now(), now(), now(), '', '', '', '', '{"provider":"email"}'::jsonb, '{}'::jsonb)
on conflict (id) do update set updated_at = now(), email_confirmed_at = now();

insert into public.perfiles (
  id, nombre_completo, rol, activo, tipo_documento,
  debe_cambiar_password, titular_distinto, titular_distinto_usd
) values
  ('b0000000-0000-4000-8000-000000000001','BANCO SUPERVISOR','analista',true,'DNI',false,false,false),
  ('b0000000-0000-4000-8000-000000000002','BANCO VENDEDOR','analista',true,'DNI',false,false,false)
on conflict (id) do update set activo = true, rol = excluded.rol;

-- El supervisor PRIMERO y sin jefe (solo el vendedor exige uno).
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values ('b0000000-0000-4000-8000-000000000001','supervisor',null,true)
on conflict (perfil_id) do update set rol_crm = 'supervisor', activo = true;

insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values ('b0000000-0000-4000-8000-000000000002','vendedor',
        'b0000000-0000-4000-8000-000000000001',true)
on conflict (perfil_id) do update
  set rol_crm = 'vendedor', supervisor_id = excluded.supervisor_id, activo = true;

do $ok$
declare v_n int;
begin
  select count(*) into v_n from crm.equipo e
   join public.perfiles p on p.id = e.perfil_id
   where e.activo and p.activo;
  if v_n < 2 then
    raise exception 'siembra: quedaron % membresias activas con perfil activo, esperaba 2', v_n;
  end if;
end $ok$;

commit;
select 'SIEMBRA-BANCO-OK' as resultado,
       (select count(*) from crm.equipo where activo) as equipo_activo;
