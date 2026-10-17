-- Banco de dominio: esquema productivo real y hechos financieros sintéticos.
-- Las semillas omiten triggers/FK; las funciones, permisos y decimales son reales.
-- No acredita el flujo de alta, que tiene su propio gate de integración.
begin;
set local statement_timeout='60s';
do $$ begin
  if current_database()<>'tc_venta' then raise exception 'Solo se permite el banco tc_venta'; end if;
end $$;
create function pg_temp.comprobar(p_ok boolean,p_mensaje text) returns void
language plpgsql as $$ begin
  if p_ok is distinct from true then raise exception 'FAIL: %',p_mensaje; end if;
  raise notice 'PASS: %',p_mensaje;
end $$;
create function pg_temp.evidencia(p_fecha date,p_compra text,p_venta text) returns jsonb
language sql as $$
  select jsonb_build_object('fecha_corte',p_fecha,'politica','sbs_punto_medio_7d_v1',
    'publicacion_confirmada',p_fecha,'fuente','BCRP · SBS PD04639PD/PD04640PD',
    'huella_respuestas',repeat('a',64),'pares',
    (select jsonb_agg(jsonb_build_object('fecha',p_fecha-i,'compra',p_compra,'venta',p_venta) order by i desc)
    from generate_series(0,6) i));
$$;

set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial)
select ('e0000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'TC-SINTETICO-'||n,
  'e0000000-0000-4000-8000-000000000099'::uuid,monto,moneda,'mensual',fecha,fecha+365,'nuevo',
  'e0000000-0000-4000-8000-000000000098'::uuid,fecha
from (values(1,20000::numeric,'USD',date '2026-10-02'),
  (2,10000,'USD',date '2026-10-05'),(3,10000,'PEN',date '2026-10-02'),
  (4,5000,'USD',date '2026-09-02')) s(n,monto,moneda,fecha);
set local session_replication_role=origin;

select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select count(*)=1 from crm.capital_valoraciones),
  'sin BCRP solo se consolida PEN, no se inventa equivalencia USD');
select pg_temp.comprobar((select count(*)=2 from crm.tipo_cambio_trabajos),
  'las dos fechas USD quedan en cola persistente');
select pg_temp.comprobar((select count(*)=4 from public.contratos where numero_contrato like 'TC-SINTETICO-%'),
  'la falta de TC no borra ni rechaza las ventas');

create temp table reservas as select * from crm.tomar_fechas_tipo_cambio_fn(3);
select pg_temp.comprobar((select count(*)=2 from reservas),'se reclaman dos fechas con reserva');
select pg_temp.comprobar((select count(*)=0 from crm.tomar_fechas_tipo_cambio_fn(3)),
  'una reserva vigente no se reclama por otro worker');
do $$ begin
  begin
    perform crm.resolver_fecha_tipo_cambio_fn(date '2026-10-02',gen_random_uuid(),pg_temp.evidencia('2026-10-02','3.39','3.41'));
    raise exception 'Una reserva falsa fue aceptada';
  exception when sqlstate 'PT409' then null; end;
end $$;
select pg_temp.comprobar((select count(*)=0 from crm.tipo_cambio_diario),
  'una reserva falsa no puede fijar la tasa');

select crm.resolver_fecha_tipo_cambio_fn('2026-10-02',
  (select reserva from reservas where fecha_corte='2026-10-02'),pg_temp.evidencia('2026-10-02','3.39','3.41'));
select crm.resolver_fecha_tipo_cambio_fn('2026-10-05',
  (select reserva from reservas where fecha_corte='2026-10-05'),null,'publicacion_pendiente');
select pg_temp.comprobar((select intentos=1 and reserva is null and completado_en is null
  and proximo_intento_en>statement_timestamp() from crm.tipo_cambio_trabajos where fecha_corte='2026-10-05'),
  'el fallo deja reintento y libera la reserva');
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select equivalente_pen=68000 and tasa=3.4000 from crm.capital_valoraciones
  where fuente_id='e0000000-0000-4000-8000-000000000001'),
  'US$ 20 000 al 02/10 con TC 3,40 guardan S/ 68 000');

select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-02','3.09','3.11'));
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-05','3.09','3.11'));
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select tasa=3.4000 from crm.tipo_cambio_diario where fecha_corte='2026-10-02'),
  'reconsultar el mismo corte con 3,10 conserva la tasa consolidada 3,40');
select pg_temp.comprobar((select sum(equivalente_pen)=109000 from crm.capital_valoraciones),
  '20 mil USD a 3,40 + 10 mil USD a 3,10 + 10 mil PEN suman S/ 109 000');
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select count(*)=3 from crm.capital_valoraciones),
  'reconciliar varias veces no duplica valoraciones');
select pg_temp.comprobar(not exists(select 1 from crm.capital_valoraciones
  where fuente_id='e0000000-0000-4000-8000-000000000004'),
  'la venta de septiembre conserva su régimen anterior');

-- Cambio financiero autorizado ya ocurrido: se simula solo el postestado.
set local session_replication_role=replica;
update public.contratos set capital=20010 where id='e0000000-0000-4000-8000-000000000001';
set local session_replication_role=origin;
select private.materializar_capital_valoraciones();
select pg_temp.comprobar((select equivalente_pen=68034 and revision=2 and anterior_id is not null
  and motivo='correccion' from crm.capital_valoraciones
  where fuente_id='e0000000-0000-4000-8000-000000000001' order by revision desc limit 1),
  'una corrección de monto agrega revisión sin cambiar la tasa de origen');
select pg_temp.comprobar((select equivalente_pen=68000 from crm.capital_valoraciones
  where fuente_id='e0000000-0000-4000-8000-000000000001' and revision=1),
  'la revisión previa permanece auditable');

do $$ begin
  begin
    update crm.tipo_cambio_diario set tasa=3.1 where fecha_corte='2026-10-02';
    raise exception 'Se pudo reemplazar una tasa consolidada';
  exception when insufficient_privilege then null; end;
  begin
    delete from crm.capital_valoraciones;
    raise exception 'Se pudo borrar la valoración original';
  exception when insufficient_privilege then null; end;
  begin
    perform private.consolidar_tc_venta(jsonb_set(pg_temp.evidencia('2026-10-06','3.4','3.4'),'{pares,0,venta}','null'));
    raise exception 'Se consolidó un par incompleto';
  exception when invalid_parameter_value then null; end;
end $$;
select pg_temp.comprobar((select count(*)=2 from crm.tipo_cambio_diario),
  'los rechazos preservan tasas y evidencia originales');

select pg_temp.comprobar(not has_function_privilege('authenticated','crm.reconciliar_capital_valoraciones_fn(integer)','EXECUTE')
  and not has_function_privilege('anon','crm.resolver_fecha_tipo_cambio_fn(date,uuid,jsonb,text)','EXECUTE')
  and not has_function_privilege('authenticated','private.consolidar_tc_venta(jsonb)','EXECUTE'),
  'usuarios y anónimos no pueden fijar tasas o materializar por detrás');
select pg_temp.comprobar(has_function_privilege('service_role','crm.reconciliar_capital_valoraciones_fn(integer)','EXECUTE')
  and not has_table_privilege('service_role','crm.tipo_cambio_diario','INSERT'),
  'el servicio usa escritores acotados y no INSERT directo');
select pg_temp.comprobar((select bool_and(relrowsecurity) from pg_class where oid in(
  'crm.capital_valoraciones'::regclass,'crm.tipo_cambio_diario'::regclass,
  'crm.tipo_cambio_trabajos'::regclass,'crm.capital_valoracion_politica'::regclass)),
  'las cuatro tablas tienen RLS desde su creación');
select pg_temp.comprobar((select not activa from crm.capital_valoracion_politica),
  'la instalación no activa la nueva regla en producción');

rollback;
