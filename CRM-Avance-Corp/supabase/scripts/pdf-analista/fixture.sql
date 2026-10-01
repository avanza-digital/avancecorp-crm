-- Solo sobre el banco sintético; el ejecutor exige su nombre y marcador.
begin;
update public.perfiles set dni='99000001', correo='creador@example.test', telefono='999111222',
  domicilio='Av. Pruebas 123, Lima', nombre_completo='CREADOR DE PRUEBA'
where id='b0000000-0000-4000-8000-000000000002';
update public.perfiles set dni='99000002', correo='asignada@example.test', telefono='999333444',
  domicilio='Av. Pruebas 123, Lima', nombre_completo='ANALISTA ASIGNADA'
where id='b0000000-0000-4000-8000-000000000001';
-- Simula una corrección administrativa confirmada por Auth, sin apagar triggers.
insert into crm.correcciones_correo_acceso(id,cliente_id,por,correo_anterior,correo_nuevo,motivo)
values ('f0000000-0000-4000-8000-000000000099','c0000000-0000-4000-8000-000000000001',
 'b0000000-0000-4000-8000-000000000003','anterior@example.test','cliente@example.test','Fixture PDF aislado');
update auth.users set email='cliente@example.test', raw_app_meta_data=coalesce(raw_app_meta_data,'{}'::jsonb)
 || jsonb_build_object('correccion_correo_acceso_id','f0000000-0000-4000-8000-000000000099')
where id='c0000000-0000-4000-8000-000000000001';
select set_config('crm.correccion_correo_acceso_id','f0000000-0000-4000-8000-000000000099',true);
update public.perfiles set correo='cliente@example.test', domicilio='Av. Pruebas 123, Lima'
where id='c0000000-0000-4000-8000-000000000001';
insert into public.contratos select (jsonb_populate_record(null::public.contratos,
 (to_jsonb(c)-'fecha_cierre_comercial'-'fuente_cierre_comercial')||jsonb_build_object('id','e0000000-0000-4000-8000-000000000099',
 'numero_contrato','2026-01-009991','producto_condicion_id',null))).*
from public.contratos c where id='e0000000-0000-4000-8000-00000000000a';
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select public.reasignar_analista_contrato('e0000000-0000-4000-8000-000000000099',
 'b0000000-0000-4000-8000-000000000001','Ensayo aislado: creador distinto de la analista asignada');
select set_config('request.jwt.claim.sub','',true);
insert into public.cronograma_pagos(contrato_id,numero_cuota,fecha_programada,monto_programado,tipo)
select id,1,fecha_vencimiento,capital*0.06,'cuota' from public.contratos
where id='e0000000-0000-4000-8000-000000000099'
union all select id,2,fecha_vencimiento,capital,'retorno' from public.contratos
where id='e0000000-0000-4000-8000-000000000099';
insert into crm.cuentas_bancarias(id,cliente_id,moneda,banco,tipo_cuenta,numero_cuenta,cci,origen)
values ('f0000000-0000-4000-8000-000000000001','c0000000-0000-4000-8000-000000000001',
 'PEN','BCP','ahorros','19100000000000','00219100000000000000','contrato');
insert into crm.contrato_cuentas_pago(contrato_id,cuenta_bancaria_id)
values ('e0000000-0000-4000-8000-000000000099','f0000000-0000-4000-8000-000000000001');
