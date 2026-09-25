-- SOLO RAMA hhpjiygytwoayxymziqo. Identidades y cuentas enteramente ficticias.
-- Aplicar despues de la primera instalacion S1 para que la auditoria nueva
-- oculte numeros de cuenta y CCI incluso durante esta siembra de prueba.
begin;
set local lock_timeout = '10s';
select pg_catalog.set_config(
  'request.jwt.claim.sub', 'b0000000-0000-4000-8000-000000000003', true);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token,
  email_change_token_new, email_change, raw_app_meta_data, raw_user_meta_data
) values
  ('b0000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.vendedor2@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cliente1@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cliente2@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cliente3@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cliente4@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.testigo@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cci.distinto@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb),
  ('c0000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000',
   'authenticated','authenticated','p0xx.cci.conflicto@example.invalid','',
   now(),now(),now(),'','','','', '{"provider":"email"}'::jsonb,'{}'::jsonb)
on conflict (id) do nothing;

insert into public.perfiles
  (id,nombre_completo,correo,rol,tipo_documento,activo,creado_por)
values
  ('b0000000-0000-4000-8000-000000000004','P0XX VENDEDOR EXTERNO',
   'p0xx.vendedor2@example.invalid','analista','DNI',true,
   'b0000000-0000-4000-8000-000000000003')
on conflict (id) do update set activo=true,rol='analista';
insert into crm.equipo (perfil_id,rol_crm,supervisor_id,activo)
values ('b0000000-0000-4000-8000-000000000004','vendedor',
        'b0000000-0000-4000-8000-000000000001',true)
on conflict (perfil_id) do update
  set rol_crm='vendedor',supervisor_id=excluded.supervisor_id,activo=true;

insert into public.perfiles
  (id,nombre_completo,correo,rol,tipo_documento,dni,activo,
   asesor_perfil_id,creado_por,
   banco,tipo_cuenta,numero_cuenta,cci,
   banco_usd,tipo_cuenta_usd,numero_cuenta_usd,cci_usd)
values
  ('c0000000-0000-4000-8000-000000000001','P0XX CLIENTE PERFIL',
   'p0xx.cliente1@example.invalid','cliente','PASAPORTE','P0XX0001',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   'BCP','ahorros','TESTPEN0001','00000000000000000001',
   'BCP','corriente','TESTUSD0001','00000000000000000002'),
  ('c0000000-0000-4000-8000-000000000002','P0XX CLIENTE AMBIGUO',
   'p0xx.cliente2@example.invalid','cliente','PASAPORTE','P0XX0002',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   null,null,null,null,null,null,null,null),
  ('c0000000-0000-4000-8000-000000000003','P0XX CLIENTE INVALIDO',
   'p0xx.cliente3@example.invalid','cliente','PASAPORTE','P0XX0003',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   null,null,null,null,'BCP','ahorros','TESTINVALIDO',' '),
  ('c0000000-0000-4000-8000-000000000004','P0XX CLIENTE SIN CUENTA',
   'p0xx.cliente4@example.invalid','cliente','PASAPORTE','P0XX0004',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   null,null,null,null,null,null,null,null),
  ('c0000000-0000-4000-8000-000000000005','P0XX TESTIGO CRM',
   'p0xx.testigo@example.invalid','cliente','PASAPORTE','P0XX0005',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   null,null,null,null,null,null,null,null),
  ('c0000000-0000-4000-8000-000000000006','P0XX CCI DISTINTO',
   'p0xx.cci.distinto@example.invalid','cliente','PASAPORTE','P0XX0006',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   'BCP','ahorros','TESTPROFILE6','00000000000000000008',null,null,null,null),
  ('c0000000-0000-4000-8000-000000000007','P0XX CCI CONFLICTO',
   'p0xx.cci.conflicto@example.invalid','cliente','PASAPORTE','P0XX0007',true,
   'b0000000-0000-4000-8000-000000000002',
   'b0000000-0000-4000-8000-000000000003',
   'BCP','ahorros','TESTPROFILE7','00000000000000000010',null,null,null,null)
on conflict (id) do update set
  nombre_completo=excluded.nombre_completo,
  correo=excluded.correo,rol=excluded.rol,
  tipo_documento=excluded.tipo_documento,dni=excluded.dni,
  activo=excluded.activo,asesor_perfil_id=excluded.asesor_perfil_id,
  creado_por=excluded.creado_por,
  banco=excluded.banco,tipo_cuenta=excluded.tipo_cuenta,
  numero_cuenta=excluded.numero_cuenta,cci=excluded.cci,
  banco_usd=excluded.banco_usd,tipo_cuenta_usd=excluded.tipo_cuenta_usd,
  numero_cuenta_usd=excluded.numero_cuenta_usd,cci_usd=excluded.cci_usd;

insert into crm.cuentas_bancarias
  (id,cliente_id,moneda,banco,tipo_cuenta,numero_cuenta,cci,origen,creado_por)
values
  ('e0000000-0000-4000-8000-000000000001',
   'c0000000-0000-4000-8000-000000000002',
   'PEN','BCP','ahorros','TESTAMB0001','00000000000000000003','contrato',
   'b0000000-0000-4000-8000-000000000003'),
  ('e0000000-0000-4000-8000-000000000002',
   'c0000000-0000-4000-8000-000000000002',
   'PEN','BCP','ahorros','TESTAMB0002','00000000000000000004','contrato',
   'b0000000-0000-4000-8000-000000000003'),
  ('e0000000-0000-4000-8000-000000000003',
   'c0000000-0000-4000-8000-000000000005',
   'PEN','BCP','ahorros','TEST6087','00000000000000000006','contrato',
   'b0000000-0000-4000-8000-000000000003'),
  ('e0000000-0000-4000-8000-000000000004',
   'c0000000-0000-4000-8000-000000000005',
   'USD','BCP','ahorros','TEST9168','00000000000000000007','contrato',
   'b0000000-0000-4000-8000-000000000003'),
  ('e0000000-0000-4000-8000-000000000005',
   'c0000000-0000-4000-8000-000000000006',
   'PEN','BCP','ahorros','TESTCRM6','00000000000000000009','contrato',
   'b0000000-0000-4000-8000-000000000003'),
  ('e0000000-0000-4000-8000-000000000006',
   'c0000000-0000-4000-8000-000000000007',
   'PEN','BCP','ahorros','TESTCRM7','00000000000000000010','contrato',
   'b0000000-0000-4000-8000-000000000003')
on conflict (id) do nothing;

commit;
