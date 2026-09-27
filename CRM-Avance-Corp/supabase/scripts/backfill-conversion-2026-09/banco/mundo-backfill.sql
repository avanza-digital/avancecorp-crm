-- Mundo sintético para ensayar el backfill de conversión (setiembre 2026).
-- SOLO banco Docker local. Nombres «BANCO …», documentos y teléfonos ficticios.
-- Formas copiadas de producción:
--   A1  cliente nuevo, contrato de setiembre, SIN fila en crm.inversiones  (p. ej. 001360 Narrea)
--   A2  cliente nuevo, contrato de setiembre, CON crm.inversiones es_primera=false (p. ej. 001377)
--   B1  cliente con contrato de julio + contrato «nuevo» de setiembre       (p. ej. Canchan)
--   B2  cliente cuyo 1.er contrato es de setiembre + 2.º del mismo mes      (p. ej. Blas Medina)
begin;
set local session_replication_role = replica;  -- solo para la siembra: las filas entran con la forma de prod

-- La cuenta ADMIN como en producción: superadmin en el portal + gerencia en el CRM.
update public.perfiles set rol = 'superadmin', nombre_completo = 'BANCO ADMINISTRADOR'
 where id = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data)
select ('c0000000-0000-4000-8000-00000000000'||i)::uuid, '00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','banco.cliente'||i||'@avancecorp.test','', now(), now(), now(),
  '','','','','{"provider":"email"}'::jsonb,'{}'::jsonb
from generate_series(1,4) i;

insert into public.perfiles (id, nombre_completo, dni, telefono, rol, activo, tipo_documento,
  asesor_perfil_id, debe_cambiar_password, titular_distinto, titular_distinto_usd, creado_en)
values
 ('c0000000-0000-4000-8000-000000000001','BANCO CLIENTE A UNO','90000001','987000001','cliente',true,'DNI','b0000000-0000-4000-8000-000000000002',false,false,false,'2026-09-05 15:00Z'),
 ('c0000000-0000-4000-8000-000000000002','BANCO CLIENTE A DOS','90000002','987000002','cliente',true,'DNI','b0000000-0000-4000-8000-000000000002',false,false,false,'2026-09-10 15:00Z'),
 ('c0000000-0000-4000-8000-000000000003','BANCO CLIENTE B UNO','90000003','987000003','cliente',true,'DNI','b0000000-0000-4000-8000-000000000002',false,false,false,'2026-07-10 15:00Z'),
 ('c0000000-0000-4000-8000-000000000004','BANCO CLIENTE B DOS','90000004','987000004','cliente',true,'DNI','b0000000-0000-4000-8000-000000000002',false,false,false,'2026-09-09 15:00Z');

insert into crm.producto_versiones (id, producto_id, numero_version, estado, nombre, vigente_desde, publicada_en)
select 'd0000000-0000-4000-8000-000000000001', id, 1, 'publicada', 'BANCO PRODUCTO', '2026-01-01', now()
from crm.productos_inversion limit 1;
insert into crm.producto_condiciones (id, version_id, orden, categoria, moneda, plazo_meses, modalidad,
  tipo_interes, capital_minimo, capital_maximo, tasa_referencia, tasa_minima, tasa_maxima, activa)
values ('d0000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001',1,'nuevo','PEN',12,
  'semestral','simple',100,100000000,12,1,50,true);

insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad,
  tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria, fecha_cierre_comercial,
  fuente_cierre_comercial, analista_cierre_id, es_demo, creado_por, creado_en, producto_condicion_id)
values
 ('e0000000-0000-4000-8000-00000000000a','BANCO-A1','c0000000-0000-4000-8000-000000000001',22000,'PEN',12,'semestral','simple','2026-09-05','2027-03-05','activo','nuevo','2026-09-05','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-05 15:05Z','d0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-00000000000b','BANCO-A2','c0000000-0000-4000-8000-000000000002',30000,'PEN',12,'semestral','simple','2026-09-10','2027-03-10','activo','nuevo','2026-09-10','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-10 15:05Z','d0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-00000000000c','BANCO-B1-JUL','c0000000-0000-4000-8000-000000000003',12000,'PEN',12,'semestral','simple','2026-07-10','2027-01-10','activo','nuevo','2026-07-10','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-07-10 15:05Z','d0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-00000000000d','BANCO-B1-SEP','c0000000-0000-4000-8000-000000000003',25000,'USD',12,'semestral','simple','2026-09-12','2027-03-12','activo','nuevo','2026-09-12','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-12 15:05Z','d0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-00000000000e','BANCO-B2-1','c0000000-0000-4000-8000-000000000004',20000,'PEN',12,'semestral','simple','2026-09-09','2027-09-09','activo','nuevo','2026-09-09','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-10 15:05Z','d0000000-0000-4000-8000-000000000002'),
 ('e0000000-0000-4000-8000-00000000000f','BANCO-B2-2','c0000000-0000-4000-8000-000000000004',3100,'USD',12,'semestral','simple','2026-09-09','2027-09-09','activo','nuevo','2026-09-09','registro','b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-11 15:05Z','d0000000-0000-4000-8000-000000000002');
commit;

-- Identidades con la función real (como en prod: todos los clientes tienen persona).
select private.asegurar_identidad_perfil(('c0000000-0000-4000-8000-00000000000'||i)::uuid, 'alta_cliente')
from generate_series(1,4) i;

-- A2: fila de crm.inversiones que el trigger F4 creó en prod (es_primera=false).
select private.inversion_vincular_fuente(
  (select id from crm.inversionistas where perfil_id='c0000000-0000-4000-8000-000000000002'),
  'e0000000-0000-4000-8000-00000000000b', null, 'b0000000-0000-4000-8000-000000000002', false);

-- Leads de fondo: dos llegadas de formulario de la analista (para que el divisor no sea cero).
insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, activo, alta_manual)
values ('BANCO LEAD FONDO UNO','987100001','formulario','nuevo','b0000000-0000-4000-8000-000000000002',10000,true,false),
       ('BANCO LEAD FONDO DOS','987100002','formulario','nuevo','b0000000-0000-4000-8000-000000000002',10000,true,false);

select 'MUNDO OK' r, (select count(*) from crm.inversionistas where perfil_id::text like 'c0000000%') personas,
  (select count(*) from crm.inversiones) inversiones, (select count(*) from crm.leads) leads,
  (select count(*) from public.contratos) contratos;

-- ===== A3 (23/09): forma de 001377 / 001396 / 001416 =====
-- Cliente nuevo, contrato de setiembre hecho por el FORMULARIO de solicitud sin lead: su inversión
-- (es_primera=false) ya tiene una solicitud CONFIRMADA sin lead_origen_id y sin revisiones.
begin;
set local session_replication_role = replica;
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
  created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change,
  raw_app_meta_data, raw_user_meta_data)
values ('c0000000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','banco.cliente5@avancecorp.test','', now(), now(), now(),
  '','','','','{"provider":"email"}'::jsonb,'{}'::jsonb);
insert into public.perfiles (id, nombre_completo, dni, telefono, rol, activo, tipo_documento,
  asesor_perfil_id, debe_cambiar_password, titular_distinto, titular_distinto_usd, creado_en)
values ('c0000000-0000-4000-8000-000000000005','BANCO CLIENTE A TRES','90000005','987000005','cliente',true,'DNI',
  'b0000000-0000-4000-8000-000000000002',false,false,false,'2026-09-14 15:00Z');
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad,
  tipo_interes, fecha_inicio, fecha_vencimiento, estado, categoria, fecha_cierre_comercial,
  fuente_cierre_comercial, analista_cierre_id, es_demo, creado_por, creado_en, producto_condicion_id)
values ('e0000000-0000-4000-8000-000000000010','BANCO-A3','c0000000-0000-4000-8000-000000000005',18000,'PEN',12,
  'semestral','simple','2026-09-14','2027-03-14','activo','nuevo','2026-09-14','registro',
  'b0000000-0000-4000-8000-000000000002',false,'b0000000-0000-4000-8000-000000000002','2026-09-14 15:05Z',
  'd0000000-0000-4000-8000-000000000002');
commit;
select private.asegurar_identidad_perfil('c0000000-0000-4000-8000-000000000005', 'alta_cliente');
select private.inversion_vincular_fuente(
  (select id from crm.inversionistas where perfil_id='c0000000-0000-4000-8000-000000000005'),
  'e0000000-0000-4000-8000-000000000010', null, 'b0000000-0000-4000-8000-000000000002', false);
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id,
  hash_payload, datos, revision_datos, estado, inversion_id, resultado, creado_por, confirmado_por)
select 'f0000000-0000-4000-8000-0000000000a3', i.id, e.id, 'b0000000-0000-4000-8000-000000000002',
  encode(sha256(convert_to('banco-a3', 'UTF8')), 'hex'),
  jsonb_build_object('contrato', jsonb_build_object('capital', 18000, 'moneda', 'PEN'), 'cronograma', '[]'::jsonb,
    'cuenta', '{}'::jsonb, 'empresa', 'avance', 'inversionista_id', i.id),
  0, 'confirmada', iv.id,
  jsonb_build_object('ok', true, 'empresa', 'avance', 'fuente', 'contrato', 'inversion_id', iv.id,
    'inversionista_id', i.id, 'lead_id', null, 'revision_datos', 0,
    'solicitud_id', 'f0000000-0000-4000-8000-0000000000a3'),
  'b0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000002'
from crm.inversionistas i, crm.empresas e, crm.inversiones iv
where i.perfil_id = 'c0000000-0000-4000-8000-000000000005' and e.clave = 'avance'
  and iv.contrato_id = 'e0000000-0000-4000-8000-000000000010';
select 'A3 OK' r, (select count(*) from crm.inversion_solicitudes where id = 'f0000000-0000-4000-8000-0000000000a3') solicitud,
  (select es_primera_conversion from crm.inversiones where contrato_id = 'e0000000-0000-4000-8000-000000000010') es_primera;
