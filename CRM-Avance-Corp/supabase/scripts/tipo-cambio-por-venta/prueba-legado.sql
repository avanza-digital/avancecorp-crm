begin;
set local statement_timeout='60s';
do $$ begin if current_database()<>'tc_venta' then raise exception 'Solo banco tc_venta'; end if; end $$;
create function pg_temp.comprobar(p_ok boolean,p_mensaje text) returns void language plpgsql as $$ begin
  if p_ok is distinct from true then raise exception 'FAIL: %',p_mensaje; end if;
  raise notice 'PASS: %',p_mensaje;
end $$;
create function pg_temp.evidencia(p_fecha date,p_valor text) returns jsonb language sql as $$
select jsonb_build_object('fecha_corte',p_fecha,'politica','sbs_punto_medio_7d_v1',
  'publicacion_confirmada',p_fecha,'fuente','BCRP · SBS PD04639PD/PD04640PD',
  'huella_respuestas',repeat('b',64),'pares',(select jsonb_agg(jsonb_build_object(
  'fecha',p_fecha-i,'compra',p_valor,'venta',p_valor)) from generate_series(0,6) i));
$$;
set local session_replication_role=replica;
insert into crm.cierres_externos(id,lead_id,cooperativa,monto,moneda,documento_tipo,documento,nombre_completo,
  numero_transaccion,vendedor_id,creado_por,creado_en,fecha_comercial,fecha_imputacion)
values('e3000000-0000-4000-8000-000000000001','e3000000-0000-4000-8000-000000000002','prodelco',20000,
  'USD','DNI','00000000','Cooperativa sintética legada','TC-LEGADO-1',
  'e3000000-0000-4000-8000-000000000003','e3000000-0000-4000-8000-000000000003',
  '2026-10-04 10:00 America/Lima','2026-09-15','2026-10-02');
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial)
values('e3000000-0000-4000-8000-000000000004','TC-LEGADO-CONTRATO',
  'e3000000-0000-4000-8000-000000000005',10000,'USD','mensual','2026-10-02','2027-10-02','nuevo',
  'e3000000-0000-4000-8000-000000000006','2026-10-02');
set local session_replication_role=origin;
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-02','3.4'));
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-05','3.1'));
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select politica='sbs_punto_medio_hasta7_legado_v1' from crm.tipo_cambio_trabajos
  where fecha_corte='2026-09-30'),'la venta legada solicita la tasa del cierre de septiembre, no la de octubre');
create temp table reserva as select * from crm.tomar_fechas_tipo_cambio_fn(3);
select crm.resolver_fecha_tipo_cambio_fn('2026-09-30',(select reserva from reserva where fecha_corte='2026-09-30'),
  jsonb_build_object('fecha_corte','2026-09-30','politica','sbs_punto_medio_hasta7_legado_v1',
    'publicacion_confirmada','2026-10-01','fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('c',64),
    'pares',jsonb_build_array(jsonb_build_object('fecha','2026-09-29','compra','3.4','venta',null),
      jsonb_build_object('fecha','2026-09-30','compra','3.4','venta','3.6'))));
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select fecha_comercial='2026-09-15' and fecha_tc='2026-09-30' and tasa=3.45
  and equivalente_pen=69000 and motivo='reconstruida_legada' from crm.capital_valoraciones
  where fuente_id='e3000000-0000-4000-8000-000000000001'),
  'se reconstruye el régimen legado y se completa la cobertura sin reescribir septiembre');

set local session_replication_role=replica;
update crm.cierres_externos set fecha_imputacion='2026-10-03' where id='e3000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select count(*)=1 from crm.capital_valoraciones
  where fuente_id='e3000000-0000-4000-8000-000000000001'),
  'reimputar conservando la fecha comercial no genera otra tasa o revisión monetaria');

set local session_replication_role=replica;
update crm.cierres_externos set fecha_comercial='2026-10-02' where id='e3000000-0000-4000-8000-000000000001';
update public.contratos set fecha_cierre_comercial='2026-10-05' where id='e3000000-0000-4000-8000-000000000004';
set local session_replication_role=origin;
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select revision=2 and equivalente_pen=68000 and fecha_tc='2026-10-02'
  from crm.capital_valoraciones where fuente_id='e3000000-0000-4000-8000-000000000001' order by revision desc limit 1),
  'corregir la fecha real de la cooperativa genera una revisión con la nueva política');
select pg_temp.comprobar((select revision=2 and equivalente_pen=31000 and fecha_tc='2026-10-05'
  from crm.capital_valoraciones where fuente_id='e3000000-0000-4000-8000-000000000004' order by revision desc limit 1),
  'corrección comercial dentro de octubre usa la tasa fija de la fecha corregida');

set local session_replication_role=replica;
update public.contratos set fecha_cierre_comercial='2026-09-15' where id='e3000000-0000-4000-8000-000000000004';
set local session_replication_role=origin;
select private.materializar_capital_valoraciones(1);
select pg_temp.comprobar((select count(*)=2 from crm.capital_valoraciones
  where fuente_id='e3000000-0000-4000-8000-000000000004'),
  'mover la venta fuera del régimen conserva la auditoría sin crear revisiones interminables');
select pg_temp.comprobar(not exists(select 1 from private.capital_episodios(
  '2026-10-01 00:00 America/Lima','2026-11-01 00:00 America/Lima',true,'{}'::uuid[])
  where contrato_id='e3000000-0000-4000-8000-000000000004'),
  'el núcleo retira de octubre la operación corregida a septiembre');
do $$ begin
  begin truncate crm.tipo_cambio_diario cascade; raise exception 'TRUNCATE indebidamente permitido';
  exception when insufficient_privilege then null; end;
end $$;
select pg_temp.comprobar((select count(*)=3 from crm.tipo_cambio_diario),
  'TRUNCATE tampoco puede borrar tasas ni el historial consolidado');
rollback;
