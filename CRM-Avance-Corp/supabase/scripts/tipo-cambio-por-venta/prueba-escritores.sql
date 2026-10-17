-- Se añade al banco transaccional después de las migraciones. Los escritores
-- se ejecutan con sus triggers/gates normales; solo la preparación es réplica.
savepoint escritores;
set local session_replication_role=replica;
insert into auth.users(id,aud,role,email) select pg_temp.persona(i),'authenticated','authenticated',
  'tc-escritor-'||i||'@example.test' from generate_series(1,7) i;
insert into public.perfiles(id,nombre_completo,rol) values(pg_temp.persona(6),'Gerencia sintética TC','admin');
update public.perfiles set nombres='GERENCIA',apellidos='SINTETICA TC',dni='48000006',telefono='999444006',domicilio='AVENIDA SINTETICA 6'
where id=pg_temp.persona(6);
insert into public.perfiles(id,nombre_completo,rol,nombres,apellidos,dni,telefono,correo,domicilio,asesor_perfil_id)
values(pg_temp.persona(7),'Cliente sintético TC','cliente','CLIENTE','SINTETICO TC','48000007','999444007',
  'tc-escritor-7@example.test','AVENIDA SINTETICA 7',pg_temp.persona(2));
insert into crm.equipo(perfil_id,rol_crm) values(pg_temp.persona(6),'gerencia');
insert into crm.empresas(id,clave,nombre_legal,nombre_visible,fuente_capital,monedas)
values(pg_temp.persona(70),'avance','Empresa sintética','Avance sintética','contratos',array['PEN','USD']),
  (pg_temp.persona(71),'prodelco','Cooperativa sintética','Prodelco sintética','cierres_externos',array['PEN','USD']);
insert into crm.inversionistas(id,perfil_id,responsable_relacion_id)
values(pg_temp.persona(60),pg_temp.persona(5),pg_temp.persona(2));
insert into crm.productos_inversion(id,codigo) values(pg_temp.persona(97),'TC-ESCRITOR');
insert into crm.producto_versiones(id,producto_id,numero_version,nombre,vigente_desde,estado,publicada_en)
values(pg_temp.persona(98),pg_temp.persona(97),1,'Producto sintético TC','2026-01-01','publicada',now());
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,
  capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
select pg_temp.persona(99),pg_temp.persona(98),1,categoria,moneda,13,modalidad,tipo_interes,100,100000000,tasa_anual,1,50
from public.contratos where id=pg_temp.contrato(8);
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,
  capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
select pg_temp.persona(96),pg_temp.persona(98),2,categoria,moneda,13,modalidad,tipo_interes,100,100000000,tasa_anual,1,50
from public.contratos where id=pg_temp.contrato(2);
update public.contratos set producto_condicion_id=pg_temp.persona(96) where id=pg_temp.contrato(2);
insert into crm.productos_inversion(id,codigo,estado,es_legacy,permite_altas_legacy,archivado_en)
values(pg_temp.persona(94),'HISTORICO-SIN-CATALOGO','archivado',true,true,now());
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,vendedor_id)
values(pg_temp.persona(41),'Lead sintético cooperativa','+51900000441','landing','convertido',9000,pg_temp.persona(3));
set local session_replication_role=origin;
select set_config('request.jwt.claim.sub',pg_temp.persona(6)::text,true);

select private.materializar_capital_valoraciones_para(1,'contrato',pg_temp.contrato(8));
select pg_temp.comprobar((select count(*)=1 and bool_and(fuente_id=pg_temp.contrato(8)) from crm.capital_valoraciones),
  'la materialización individual no valora otras ventas del mismo día');
select private.materializar_capital_valoraciones_para(1,'contrato',pg_temp.contrato(2));
select pg_temp.comprobar(exists(select 1 from crm.tipo_cambio_trabajos where fecha_corte='2026-10-02')
  and not exists(select 1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(2)),
  'sin tasa, el escritor conserva la venta y deja el trabajo pendiente sin inventar equivalente');
select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-10-02','politica','sbs_punto_medio_7d_v1',
  'publicacion_confirmada','2026-10-02','fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('a',64),
  'pares',(select jsonb_agg(jsonb_build_object('fecha',date '2026-10-02'-i,'compra','3.4','venta','3.4')) from generate_series(0,6) i)));
select private.inversion_vincular_fuente(pg_temp.persona(60),pg_temp.contrato(2),null,pg_temp.persona(6));
select pg_temp.comprobar((select equivalente_pen=6800 and tasa=3.4 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(2))
  and exists(select 1 from crm.inversiones where contrato_id=pg_temp.contrato(2)),
  'la vinculación real guarda inversión y valoración USD en la misma transacción');
select private.inversion_vincular_fuente(pg_temp.persona(60),pg_temp.contrato(2),null,pg_temp.persona(6));
select pg_temp.comprobar((select count(*)=1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(2)),
  'repetir la vinculación no crea otra revisión de valoración');
select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-10-05','politica','sbs_punto_medio_7d_v1',
  'publicacion_confirmada','2026-10-05','fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('c',64),
  'pares',(select jsonb_agg(jsonb_build_object('fecha',date '2026-10-05'-i,'compra','3.1','venta','3.1')) from generate_series(0,6) i)));
set local role authenticated;
select crm.corregir_fecha_cierre_comercial(pg_temp.contrato(2),'2026-10-05','Corregir la fecha real de venta USD');
reset role;
select pg_temp.comprobar(exists(select 1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(2) and revision=2
  and equivalente_pen=6200 and tasa=3.1 and fecha_comercial='2026-10-05'),
  'la corrección real USD usa inmediatamente la tasa guardada de la fecha corregida');
set local role authenticated;
select crm.corregir_fecha_cierre_comercial(pg_temp.contrato(2),'2026-10-07','Fecha corregida sin cotización disponible');
reset role;
select pg_temp.comprobar((select count(*)=2 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(2))
  and exists(select 1 from crm.tipo_cambio_trabajos where fecha_corte='2026-10-07')
  and exists(select 1 from private.capital_valoraciones_actuales('2026-10-01 America/Lima','2026-11-01 America/Lima')
    where fuente_id=pg_temp.contrato(2) and valoracion_id is null),
  'la corrección sin TC confirma la venta y deja pendiente su nueva revisión, sin reutilizar la anterior');

set local role authenticated;
select crm.corregir_fecha_cierre_comercial(pg_temp.contrato(8),'2026-10-05','Corrección sintética del cierre comercial');
reset role;
select pg_temp.comprobar((select count(*)=2 and max(revision)=2 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(8))
  and exists(select 1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(8) and revision=2 and fecha_comercial='2026-10-05' and equivalente_pen=8000),
  'la RPC real de corrección agrega la revisión PEN con triggers y rol authenticated');
select pg_temp.comprobar(exists(select 1 from public.audit_log where tabla='contratos.fecha_cierre_comercial'
  and fila_id=pg_temp.contrato(8)::text and data_despues->>'motivo'='Corrección sintética del cierre comercial'),
  'la integración conserva el motivo y auditoría nativos de la corrección');
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
set local role authenticated;
do $$ begin
  begin perform crm.corregir_fecha_cierre_comercial(pg_temp.contrato(8),'2026-10-06','Intento no autorizado');
    raise exception 'Un vendedor corrigió la fecha';
  exception when insufficient_privilege then null; end;
  begin perform private.materializar_capital_valoraciones_para(1,'contrato',pg_temp.contrato(2));
    raise exception 'El navegador materializó directamente';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: la integración conserva la autorización de Gerencia y revoca la puerta interna';
end $$;
reset role;
select set_config('request.jwt.claim.sub',pg_temp.persona(6)::text,true);

-- La RPC de Gerencia conserva la identidad y ejecuta sus triggers existentes.
set local role authenticated;
select crm.corregir_cierre_externo(pg_temp.persona(31),9100,'USD','prodelco','ATR-TC-COOP-1',null,null,'Corrección sintética de monto');
reset role;
select pg_temp.comprobar((select equivalente_pen=30940 and monto=9100 from crm.capital_valoraciones where fuente_id=pg_temp.persona(31)),
  'la actualización real de cooperativa con tasa conocida materializa al escribir');
do $$ begin
  begin update crm.cierres_externos set fecha_imputacion='2026-10-04' where id=pg_temp.persona(31);
    raise exception 'Se reimputó sin una reapertura autorizada';
  exception when sqlstate 'P0409' then null; end;
end $$;
select pg_temp.comprobar((select count(*)=1 from crm.capital_valoraciones where fuente_id=pg_temp.persona(31)),
  'una reimputación no autorizada sigue rechazada y no crea una valoración');
select pg_temp.comprobar(not exists(select 1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(1)),
  'escribir otras fuentes no materializa una operación ajena del mismo día');

savepoint rendimiento_individual;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,
  categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id)
select md5('TC-RENDIMIENTO-'||n)::uuid,'TC-RENDIMIENTO-'||n,pg_temp.persona(5),1000,'PEN','mensual',
  date '2025-01-01',date '2026-02-01','nuevo',pg_temp.persona(99),date '2025-01-01',pg_temp.persona(2)
from generate_series(1,10000) n;
set local session_replication_role=origin;
do $$ declare v_inicio timestamptz:=clock_timestamp(); v_r jsonb; begin
  v_r:=private.materializar_capital_valoraciones_para(1,'contrato',pg_temp.contrato(8));
  if (v_r->>'creadas')::integer<>0 or exists(select 1 from crm.capital_valoraciones where fuente_id=md5('TC-RENDIMIENTO-1')::uuid) then
    raise exception 'La llamada individual incorporó ventas ajenas';
  end if;
  raise notice 'PASS: una operación conserva su resultado con 10 000 fuentes históricas adicionales';
  raise notice 'MEDICION: materialización individual con 10 000 fuentes extra: % ms',round(extract(epoch from clock_timestamp()-v_inicio)*1000,2);
end $$;
rollback to savepoint rendimiento_individual;

-- Alta usada por el portal: contrato, cronograma, cuenta y reserva documental.
-- La fecha comercial la fija el escritor nativo, por eso se prepara su TC de hoy.
select private.consolidar_tc_venta(jsonb_build_object('fecha_corte',(statement_timestamp() at time zone 'America/Lima')::date,
  'politica','sbs_punto_medio_7d_v1','publicacion_confirmada',(statement_timestamp() at time zone 'America/Lima')::date,
  'fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('d',64),
  'pares',(select jsonb_agg(jsonb_build_object('fecha',(statement_timestamp() at time zone 'America/Lima')::date-i,
    'compra','3.4','venta','3.4')) from generate_series(0,6) i)));
create function pg_temp.alta_crm_tc() returns jsonb language plpgsql as $$
declare c jsonb; cuotas jsonb; cuenta jsonb; inicio date:='2026-10-02'; begin
  c:=jsonb_build_object('cliente_id',pg_temp.persona(7),'numero_contrato','2026-01-990001','categoria','nuevo',
    'capital',20000,'moneda','USD','tasa_anual',15,'modalidad','mensual','tipo_interes','simple',
    'fecha_inicio',inicio,'fecha_vencimiento',(inicio+interval '13 months')::date,
    'analista_cierre_id',pg_temp.persona(2),'clave_idempotencia',pg_temp.persona(90));
  select jsonb_agg(jsonb_build_object('numero_cuota',n,'fecha_programada',(inicio+make_interval(months=>n))::date,
    'monto_programado',250,'tipo','cuota') order by n) into cuotas from generate_series(1,13) n;
  cuotas:=cuotas||jsonb_build_array(jsonb_build_object('numero_cuota',14,'fecha_programada',(inicio+interval '13 months 7 days')::date,
    'monto_programado',20000,'tipo','retorno'));
  cuenta:=jsonb_build_object('tipo','nueva','banco','BANCO SINTETICO','tipo_cuenta','ahorros',
    'numero_cuenta','TC-USD-001','cci','99999999999999999991','titular_distinto',false);
  return crm.crear_contrato_con_cuenta_pdf_v2(c,cuotas,cuenta);
end $$;
create temp table conteos_antes_alta as select (select count(*) from public.contratos) contratos,
  (select count(*) from crm.capital_valoraciones) valoraciones,(select count(*) from crm.cuentas_bancarias) cuentas,
  (select count(*) from public.cronograma_pagos) cuotas;
set local role authenticated;
do $$ begin
  begin perform pg_temp.alta_crm_tc(); raise exception 'Se reservó PDF con analista sin datos legales';
  exception when check_violation then
    if sqlerrm<>'Faltan datos legales obligatorios del titular o del analista' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.comprobar((select contratos=(select count(*) from public.contratos)
  and valoraciones=(select count(*) from crm.capital_valoraciones) and cuentas=(select count(*) from crm.cuentas_bancarias)
  and cuotas=(select count(*) from public.cronograma_pagos) from conteos_antes_alta),
  'un rechazo documental posterior revierte contrato, cuotas, cuenta y valoración de la misma alta');
-- Completar los datos legales de la persona sintética, sin cambiar el gate PDF.
update public.perfiles set dni='48000002',telefono='999444002',correo='tc-escritor-2@example.test'
where id=pg_temp.persona(2);
set local role authenticated;
do $$ declare r jsonb; repetido jsonb; begin
  r:=pg_temp.alta_crm_tc();
  repetido:=pg_temp.alta_crm_tc();
  if r->>'id' is null or r->>'id' is distinct from repetido->>'id' or not (repetido->>'idempotente')::boolean then
    raise exception 'Falló la idempotencia nativa del alta contractual';
  end if;
end $$;
reset role;
set constraints all immediate;
select pg_temp.comprobar(exists(select 1 from public.contratos c join crm.capital_valoraciones v on v.fuente='contrato' and v.fuente_id=c.id
  join crm.contrato_cuentas_pago cp on cp.contrato_id=c.id where c.numero_contrato='2026-01-990001'
    and v.monto=20000 and v.tasa=3.4 and v.equivalente_pen=68000 and v.revision=1),
  'el alta real del portal confirma US$ 20 000, cuenta y valoración S/ 68 000 sin esperar al worker');

savepoint cola_extensa;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,fecha_vencimiento,
  categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id)
select md5('TC-COLA-'||n)::uuid,'TC-COLA-'||n,pg_temp.persona(5),1000,'USD','mensual',
  date '2026-10-08',date '2027-11-08','nuevo',pg_temp.persona(96),date '2026-10-08'+n%5,pg_temp.persona(2)
from generate_series(1,1000) n;
set local session_replication_role=origin;
select private.materializar_capital_valoraciones(1);
select pg_temp.comprobar(exists(select 1 from crm.capital_valoraciones where fuente_id=pg_temp.contrato(1))
  and (select count(*)=5 from crm.tipo_cambio_trabajos where fecha_corte between '2026-10-08' and '2026-10-12'),
  'mil ventas sin TC no impiden valorar PEN y se descubren todas sus fechas aun con lote de una operación');
rollback to savepoint cola_extensa;
rollback to savepoint escritores;
