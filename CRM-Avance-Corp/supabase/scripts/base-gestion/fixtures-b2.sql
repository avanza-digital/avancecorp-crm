-- Fixtures B2 del banco «base_gestion_20261002» (idempotentes). Actores y leads SINTÉTICOS (b0000000-…).
-- Equipo 1: supervisor 0001 → analistas A (0002, ya existe) y B (0012). Equipo 2: supervisor 0011 → analista C (0013).
-- Leads descartados LA/LB/LC (uno por analista) con una rellamada pendiente; LA_VETO (A) con no_contactar;
-- LD (C, equipo 2) comparte DNI con LA_VETO para probar «persona con leads en dos equipos».
begin;
set local search_path = '';
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data) values
  ('b0000000-0000-4000-8000-000000000011','00000000-0000-0000-0000-000000000000','authenticated','authenticated','banco.supervisor2@avancecorp.test','',now(),now(),now(),'','','','','{"provider":"email"}','{}'),
  ('b0000000-0000-4000-8000-000000000012','00000000-0000-0000-0000-000000000000','authenticated','authenticated','banco.vendedor.b@avancecorp.test','',now(),now(),now(),'','','','','{"provider":"email"}','{}'),
  ('b0000000-0000-4000-8000-000000000013','00000000-0000-0000-0000-000000000000','authenticated','authenticated','banco.vendedor.c@avancecorp.test','',now(),now(),now(),'','','','','{"provider":"email"}','{}')
on conflict (id) do update set updated_at = now();
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd) values
  ('b0000000-0000-4000-8000-000000000011','BANCO SUPERVISOR 2','analista',true,'DNI',false,false,false),
  ('b0000000-0000-4000-8000-000000000012','BANCO VENDEDOR B','analista',true,'DNI',false,false,false),
  ('b0000000-0000-4000-8000-000000000013','BANCO VENDEDOR C','analista',true,'DNI',false,false,false)
on conflict (id) do update set activo = true;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values ('b0000000-0000-4000-8000-000000000011','supervisor',null,true)
on conflict (perfil_id) do update set rol_crm='supervisor', activo=true;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  ('b0000000-0000-4000-8000-000000000012','vendedor','b0000000-0000-4000-8000-000000000001',true),
  ('b0000000-0000-4000-8000-000000000013','vendedor','b0000000-0000-4000-8000-000000000011',true)
on conflict (perfil_id) do update set rol_crm='vendedor', supervisor_id=excluded.supervisor_id, activo=true;

-- Leads: nacen en «nuevo» y se descartan después (los triggers exigen el camino normal).
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values
  ('b0000000-0000-4000-8000-0000000000a1','BANCO B2 LEAD A DESCARTADO','988770101','70000101','otro','nuevo','b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002',true),
  ('b0000000-0000-4000-8000-0000000000b1','BANCO B2 LEAD B DESCARTADO','988770102','70000102','otro','nuevo','b0000000-0000-4000-8000-000000000012',1000,'PEN','b0000000-0000-4000-8000-000000000012',true),
  ('b0000000-0000-4000-8000-0000000000c1','BANCO B2 LEAD C DESCARTADO','988770103','70000103','otro','nuevo','b0000000-0000-4000-8000-000000000013',1000,'PEN','b0000000-0000-4000-8000-000000000013',true),
  ('b0000000-0000-4000-8000-0000000000a2','BANCO B2 LEAD A VETO','988770104','70000104','otro','nuevo','b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002',true)
on conflict (id) do nothing;
update crm.leads set etapa='descartado', motivo_descarte='no_responde'
 where id in ('b0000000-0000-4000-8000-0000000000a1','b0000000-0000-4000-8000-0000000000b1','b0000000-0000-4000-8000-0000000000c1',
              'b0000000-0000-4000-8000-0000000000a2') and etapa='nuevo';
-- LD comparte DNI con LA_VETO: solo puede nacer cuando LA_VETO ya está descartado (índice único de DNI vivo).
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values
  ('b0000000-0000-4000-8000-0000000000d1','BANCO B2 LEAD D MISMA PERSONA EQUIPO 2','988770105','70000104','otro','nuevo','b0000000-0000-4000-8000-000000000013',1000,'PEN','b0000000-0000-4000-8000-000000000013',true)
on conflict (id) do nothing;
update crm.leads set etapa='descartado', motivo_descarte='no_responde' where id = 'b0000000-0000-4000-8000-0000000000d1' and etapa='nuevo';
-- (Sin rellamadas: el CRM no admite tareas nuevas en un lead cerrado — trg_tareas_before_insert. Pendiente D7-bis.)
-- Veto en LA_VETO y LD (misma persona por DNI), por la vía privilegiada del propio esquema.
select set_config('crm.op_privilegiada','on',true);
update crm.leads set no_contactar = true where id in ('b0000000-0000-4000-8000-0000000000a2','b0000000-0000-4000-8000-0000000000d1') and not no_contactar;
select set_config('crm.op_privilegiada','off',true);
do $$ begin
  if (select count(*) from crm.leads where id::text like 'b0000000-0000-4000-8000-0000000000%' and etapa='descartado') <> 5 then raise exception 'fixtures B2: no quedaron 5 descartados'; end if;
  if (select count(*) from crm.leads where id in ('b0000000-0000-4000-8000-0000000000a2','b0000000-0000-4000-8000-0000000000d1') and no_contactar) <> 2 then raise exception 'fixtures B2: el veto no quedó'; end if;
  raise notice 'fixtures B2 OK: 3 actores nuevos, 5 descartados, 2 vetados';
end $$;
commit;
