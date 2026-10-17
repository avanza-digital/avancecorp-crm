-- Se ejecuta con fixture sintética y migraciones candidatas, dentro de rollback.
insert into crm.conversion_pesos(vigente_desde,peso_referido,peso_renovacion,tope_referidos_pct,nota)
values('2026-07-01',0.15,0.15,null,'Configuración sintética histórica'),
  ('2026-10-01',1,0,15,'Configuración sintética octubre');
insert into crm.metas_vendedor_detalle(meta_vendedor_id,categoria,moneda,capital_objetivo,contratos_objetivo)
select m.id,d.categoria,d.moneda,case when d.categoria='nuevo' and d.moneda='PEN' then 100000 else 0 end,0
from crm.metas_vendedor m cross join(values('nuevo','PEN'),('nuevo','USD'),('renovacion','PEN'),
  ('renovacion','USD'),('upgrade','PEN'),('upgrade','USD')) d(categoria,moneda);
create function pg_temp.evidencia(p_fecha date,p_tasa text) returns jsonb language sql as $$
  select jsonb_build_object('fecha_corte',p_fecha,'politica','sbs_punto_medio_7d_v1',
    'publicacion_confirmada',p_fecha,'fuente','BCRP · SBS PD04639PD/PD04640PD',
    'huella_respuestas',repeat('a',64),'pares',(select jsonb_agg(jsonb_build_object(
      'fecha',p_fecha-i,'compra',p_tasa,'venta',p_tasa) order by i desc) from generate_series(0,6) i));
$$;
create temp table cortes_prueba(nombre text primary key,id uuid);
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-02','3.4'));
select private.consolidar_tc_venta(jsonb_build_object('fecha_corte','2026-09-30',
  'politica','sbs_punto_medio_hasta7_legado_v1','publicacion_confirmada','2026-10-01',
  'fuente','BCRP · SBS PD04639PD/PD04640PD','huella_respuestas',repeat('b',64),
  'pares',jsonb_build_array(jsonb_build_object('fecha','2026-09-30','compra','3.5','venta','3.5'))));
-- @CITAS_SIN_CORTE@
select private.materializar_capital_valoraciones();
create temp table avance_corte as select crm.reconciliar_capital_valoraciones_fn() as datos;
insert into cortes_prueba select 'original',id from crm.capital_cortes_valorados where periodo='2026-10-01' order by revision desc limit 1;
select pg_temp.comprobar((select (datos->>'creadas')::integer=0 and (datos->>'cortes_publicados')::integer=1 from avance_corte),
  'una venta ya valorada informa avance al publicar su corte nuevo');
select pg_temp.comprobar((crm.reconciliar_capital_valoraciones_fn()->>'cortes_publicados')::integer=0,
  'reconciliar sin cambios no informa otro corte nuevo');
select pg_temp.comprobar((select id is not null from cortes_prueba where nombre='original'),
  'se publica un corte completo de las operaciones valoradas');
select pg_temp.comprobar((select count(*)=1 from crm.capital_cortes_valorados),
  'la publicación tiene una revisión inicial');
select pg_temp.comprobar(private.publicar_corte_capital('2026-10-01')=(select id from cortes_prueba where nombre='original'),
  'republicar sin cambios reutiliza la misma foto');
select pg_temp.comprobar((select sum((e->>'equivalente_pen')::numeric)=91400
  from crm.capital_cortes_valorados c,jsonb_array_elements(c.produccion) e where c.id=(select id from cortes_prueba where nombre='original')),
  'el corte suma por operación y conserva el legado sin duplicar desgloses');

-- Una corrección retroactiva sin su nueva cotización no invalida la foto publicada.
-- @CITAS_CON_CORTE@
set local session_replication_role=replica;
update public.contratos set fecha_cierre_comercial='2026-10-05',capital=20000,moneda='USD'
where id=pg_temp.contrato(1);
set local session_replication_role=origin;
select pg_temp.comprobar((select valoracion_id is null from private.capital_valoraciones_actuales(
  '2026-10-01 America/Lima','2026-11-01 America/Lima') where fuente_id=pg_temp.contrato(1)),
  'la valoración anterior no se presenta como vigente tras corregir fecha, monto y moneda');
select pg_temp.comprobar(private.publicar_corte_capital('2026-10-01')=(select id from cortes_prueba where nombre='original'),
  'una corrección pendiente conserva la última foto completa sin retroceder el corte');
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-05','3.1'));
select private.materializar_capital_valoraciones();
insert into cortes_prueba values('corregido',private.publicar_corte_capital('2026-10-01'));
select pg_temp.comprobar((select id<>(select id from cortes_prueba where nombre='original') from cortes_prueba where nombre='corregido'),
  'resolver la corrección publica una nueva revisión del corte');
select pg_temp.comprobar((select (e->>'equivalente_pen')::numeric=62000 from crm.capital_cortes_valorados c,
  jsonb_array_elements(c.produccion) e where c.id=(select id from cortes_prueba where nombre='corregido')
  and (e->>'fuente_id')::uuid=pg_temp.contrato(1)),
  'la corrección usa su fecha comercial real y su tasa fija');

-- V2 conserva el endpoint anterior mientras la política esté desactivada.
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
select pg_temp.comprobar(crm.cumplimiento_metas_v2_fn('2026-10-01')=crm.cumplimiento_metas_fn('2026-10-01'),
  'el cliente compatible recibe exactamente v1 mientras no se activa');
update crm.capital_valoracion_politica set activa=true;
select pg_temp.comprobar((select bool_and((v->>'vendedor_id')::uuid=pg_temp.persona(2))
  from jsonb_array_elements(crm.cumplimiento_metas_v2_fn('2026-10-01')->'vendedores') v),
  'el vendedor solo recibe las filas autorizadas del ranking');
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{vendedores,0,capital_valorado,equivalente_pen}')::numeric=74000,
  'el vendedor lee el equivalente guardado de su producción');
select jsonb_build_object('tc_fixture','activo','payload',crm.cumplimiento_metas_v2_fn('2026-10-01'));
select jsonb_build_object('tc_fixture','detalle','payload',crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(2)));
select pg_temp.comprobar((crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(2))->>'total_pen')::numeric=74000,
  'el detalle por operación concilia con el mismo capital del ranking');
do $$ begin
  begin perform crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(3));
    raise exception 'Un vendedor leyó operaciones ajenas';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: el detalle no amplía la visibilidad del ranking';
end $$;
select pg_temp.comprobar(crm.cumplimiento_metas_v2_fn('2026-09-01')=crm.cumplimiento_metas_fn('2026-09-01'),
  'septiembre conserva exactamente la semántica anterior aunque octubre esté activo');
set local role authenticated;
do $$ begin
  if (crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{vendedores,0,capital_valorado,equivalente_pen}')::numeric<>74000 then
    raise exception 'El rol authenticated no pudo leer su equivalente';
  end if;
  begin perform crm.activar_capital_valorado_fn('build-sintetico-20261016',repeat('0',32));
    raise exception 'authenticated activó la política';
  exception when insufficient_privilege then null; end;
  begin perform 1 from crm.capital_cortes_valorados; raise exception 'authenticated leyó el corte global';
  exception when insufficient_privilege then null; end;
  raise notice 'PASS: el rol SQL authenticated ejecuta solo su lectura autorizada';
end $$;
reset role;
do $$ begin
  begin perform crm.facturacion_diaria_v2_fn('2026-10-01'); raise exception 'Un vendedor abrió Facturación';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
select pg_temp.comprobar(jsonb_array_length(crm.facturacion_diaria_v2_fn('2026-10-01')->'filas')>0,
  'supervisión conserva su acceso a Facturación valorada');
select jsonb_build_object('tc_fixture','facturacion','payload',crm.facturacion_diaria_v2_fn('2026-10-01'));
create temp table lista_valorada_prueba as select crm.listar_operaciones_facturacion_v3_fn('2026-10-01','2026-10-31',
  p_cortes=>jsonb_build_object('2026-10-01',(select id from cortes_prueba where nombre='corregido'))) as datos;
select pg_temp.comprobar((select datos->>'version'='3' and jsonb_array_length(datos->'filas')>0 from lista_valorada_prueba),
  'el detalle de Facturación publica filas del corte solicitado');
select pg_temp.comprobar((select (select sum((t->>'equivalente_pen')::numeric) from jsonb_array_elements(datos->'totales_por_mes') t)
  =(select sum((f->>'capital_equivalente_pen')::numeric) from jsonb_array_elements(crm.facturacion_diaria_v2_fn('2026-10-01')->'filas') f)
  from lista_valorada_prueba),'malla y detalle de Facturación concilian el equivalente del mismo corte');
select pg_temp.comprobar((select exists(select 1 from jsonb_array_elements(datos->'filas') f where (f->>'equivalente_pen')::numeric=62000
  and (f->>'monto')::numeric=20000 and (f->>'tasa')::numeric=3.1) from lista_valorada_prueba),
  'el detalle sirve monto, tasa y equivalente persistidos');
select jsonb_build_object('tc_fixture','facturacion-lista','payload',(select datos from lista_valorada_prueba));
do $$ begin
  begin perform crm.listar_operaciones_facturacion_v3_fn('2026-10-01','2026-10-31',p_cortes=>'{}');
    raise exception 'El detalle inventó un corte';
  exception when sqlstate 'PT409' then null; end;
  raise notice 'PASS: el detalle no sustituye un corte faltante por el más reciente';
end $$;
savepoint rango_mixto;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id,creado_por)
select pg_temp.contrato(9),'ATR-TC-AGOSTO',cliente_id,3000,'USD',modalidad,'2026-08-02',
  fecha_vencimiento,categoria,producto_condicion_id,'2026-08-02',analista_cierre_id,creado_por
from public.contratos where id=pg_temp.contrato(7);
set local session_replication_role=origin;
create temp table lista_mixta_prueba as select crm.listar_operaciones_facturacion_v3_fn('2026-08-01','2026-10-31',
  p_cortes=>jsonb_build_object('2026-10-01',(select id from cortes_prueba where nombre='corregido'))) as datos;
select pg_temp.comprobar((select count(*)=3 and sum(case when t->>'mes'<'2026-10-01' then (t->>'monto')::numeric else 0 end)=10000
  and bool_and(case when t->>'mes'<'2026-10-01' then t->>'equivalente_pen' is null else t->>'equivalente_pen' is not null end)
  from lista_mixta_prueba,jsonb_array_elements(datos->'totales_por_mes') t where t->>'moneda'='USD'),
  'el rango agosto-octubre separa dos meses legados sin tasa inventada y octubre por operación');
select jsonb_build_object('tc_fixture','facturacion-lista-mixta','payload',(select datos from lista_mixta_prueba));
do $$ begin
  begin perform crm.listar_operaciones_facturacion_v2_fn('2026-08-01','2026-10-31'); raise exception 'Se amplió el rango v2';
  exception when invalid_parameter_value then null; end;
  begin perform crm.listar_operaciones_facturacion_v3_fn('2025-10-01','2026-10-31',p_cortes=>'{}'); raise exception 'Se admitió más de un año';
  exception when invalid_parameter_value then null; end;
  raise notice 'PASS: se conserva el límite anterior y el nuevo rango sigue acotado';
end $$;
rollback to savepoint rango_mixto;
select set_config('request.jwt.claim.sub',pg_temp.persona(4)::text,true);
create temp table lista_coordinacion_prueba as select crm.listar_operaciones_facturacion_v3_fn('2026-10-01','2026-10-31',
  p_cortes=>jsonb_build_object('2026-10-01',(select id from cortes_prueba where nombre='corregido'))) as datos;
select pg_temp.comprobar((select bool_and(f->>'visible'='false' and f->>'nombre_visible'='true' and f ? 'cliente_nombre'
  and not (f ?| array['contrato_id','cliente_id','lead_id','cierre_externo_id','numero_contrato','telefono','correo','dni']))
  from lista_coordinacion_prueba,jsonb_array_elements(datos->'filas') f),
  'Coordinación conserva solo el nombre autorizado, sin identificadores ni contacto, también en el corte');
select jsonb_build_object('tc_fixture','facturacion-lista-coordinacion','payload',(select datos from lista_coordinacion_prueba));
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform crm.cumplimiento_metas_v2_fn('2026-10-01'); raise exception 'La consulta anónima fue aceptada';
  exception when insufficient_privilege then null; end;
end $$;
select pg_temp.comprobar(not has_table_privilege('authenticated','crm.capital_cortes_valorados','SELECT')
  and not has_table_privilege('service_role','crm.capital_mes_sellos','INSERT'),
  'no se pueden leer cortes globales ni forjar referencias de sello directamente');

-- La activación exige la huella del estado real y un bundle compatible.
select crm.suspender_capital_valorado_fn();
do $$ begin
  begin
    perform crm.activar_capital_valorado_fn('build-sintetico-20261016',repeat('0',32));
    raise exception 'Se activó con censo desactualizado';
  exception when sqlstate 'PT409' then null; end;
end $$;
select crm.activar_capital_valorado_fn('build-sintetico-20261016',crm.preflight_capital_valorado_fn()->>'huella');
select pg_temp.comprobar((select activa and bundle_compatible='build-sintetico-20261016'
  from crm.capital_valoracion_politica),'solo un censo completo y vigente permite activar la presentación');

savepoint ajustes_sin_origen;
set local session_replication_role=replica;
insert into crm.ajustes_mes_cerrado(vendedor_id,periodo_origen,lead_id,motivo,creado_por,numerador,
  pendiente_numerador,capital_usd,pendiente_usd)
values(pg_temp.persona(2),'2026-09-01',pg_temp.persona(21),'prueba_anulacion',pg_temp.persona(4),1,1,100,100);
set local session_replication_role=origin;
do $$ begin
  begin perform crm.preflight_capital_valorado_fn(); raise exception 'Se ignoró la deuda USD sin origen valorado';
  exception when sqlstate 'PT409' then null; end;
  raise notice 'PASS: una deuda monetaria sin origen resuelto bloquea activación y cierre';
end $$;
rollback to savepoint ajustes_sin_origen;
do $$ begin
  begin
    update crm.metas_vendedor_detalle set capital_objetivo=100 where moneda='USD' and categoria='nuevo';
    raise exception 'Se publicó meta USD con TC variable';
  exception when invalid_parameter_value then null; end;
  raise notice 'PASS: no se publica una meta USD sin fijar su equivalente';
end $$;

savepoint pendiente_visual;
set local session_replication_role=replica;
update public.contratos set fecha_cierre_comercial='2026-10-07' where id in(pg_temp.contrato(1),pg_temp.contrato(2));
set local session_replication_role=origin;
select crm.reconciliar_capital_valoraciones_fn();
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,cobertura,pendientes,cantidad}')::int=1,
  'la cobertura muestra solo la venta pendiente del analista autorizado');
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,personas,0,capital_valorado,equivalente_pen}')::numeric=74000
  and crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,cobertura,estado}'='pendiente',
  'personas, importes y metas conservan el último corte completo con estado pendiente visible');
select jsonb_build_object('tc_fixture','pendiente','payload',crm.cumplimiento_metas_v2_fn('2026-10-01'));
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
select pg_temp.comprobar((crm.facturacion_diaria_v2_fn('2026-10-01')#>>'{cobertura,pendientes,cantidad}')::int=2,
  'Facturación muestra las dos ventas pendientes del equipo sin inventar equivalentes');
-- @CITAS_PENDIENTE@
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(crm.listar_operaciones_facturacion_v3_fn('2026-10-01','2026-10-31',
  p_cortes=>jsonb_build_object('2026-10-01',(select id from cortes_prueba where nombre='corregido')))->'filas') f
  where (f->>'equivalente_pen')::numeric=62000 and f->>'fecha_comercial'='2026-10-05'),
  'el detalle de un corte abierto conserva la fecha y valoración anteriores ante una corrección pendiente');
rollback to savepoint pendiente_visual;
select set_config('request.jwt.claim.sub','',true);

-- Reloj simulado SOLO dentro de este rollback. No existe un override público.
do $reloj$
declare v_src text;
begin
  select pg_get_functiondef('crm.cerrar_periodo(date)'::regprocedure) into v_src;
  execute replace(v_src,'now()',E'timestamptz ''2026-11-12 12:00 America/Lima''');
  select pg_get_functiondef('crm.ciclo_cierre_mes()'::regprocedure) into v_src;
  execute replace(v_src,'now()',E'timestamptz ''2026-11-12 12:00 America/Lima''');
  select pg_get_functiondef('private.publicar_corte_capital(date)'::regprocedure) into v_src;
  execute replace(v_src,E'(statement_timestamp() at time zone ''America/Lima'')::date',E'date ''2026-11-12''');
  select pg_get_functiondef('private.capital_estado_corte(date,uuid,jsonb)'::regprocedure) into v_src;
  execute replace(v_src,'statement_timestamp()',E'timestamptz ''2026-11-12 12:00 America/Lima''');
end $reloj$;

-- @REEVALUACION_CIERRE@

savepoint cierre_legado;
select crm.suspender_capital_valorado_fn();
select crm.cerrar_periodo('2026-10-01');
select pg_temp.comprobar(exists(select 1 from crm.periodos_cerrados)
  and not exists(select 1 from crm.capital_mes_sellos),
  'desactivado, el cierre anterior funciona sin añadir un sello de valoración');
do $$ begin
  begin
    perform crm.activar_capital_valorado_fn('build-sintetico-20261016',crm.preflight_capital_valorado_fn()->>'huella');
    raise exception 'Se activó sobre un mes sellado con la regla anterior';
  exception when sqlstate 'PT409' then null; end;
end $$;
rollback to savepoint cierre_legado;

set local session_replication_role=replica;
update public.contratos set fecha_cierre_comercial='2026-10-06' where id=pg_temp.contrato(1);
set local session_replication_role=origin;
update cron.job set active=true where jobid=3;
create temp table ciclo_fallido as select crm.reevaluar_cierre_capital_fn()->'resultado' as resultado;
select pg_temp.comprobar((select resultado->>'ok'='false' and resultado#>>'{fallo,sqlstate}'='PT409'
  from ciclo_fallido),'el ciclo identifica falta de valoración y mantiene el siguiente intento');
select pg_temp.comprobar(not exists(select 1 from crm.periodos_cerrados)
  and not exists(select 1 from crm.cierre_mes_vendedor) and not exists(select 1 from crm.capital_mes_sellos),
  'sin cobertura no se sella ningún componente del mes');
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
select pg_temp.comprobar(crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,cobertura,estado}'='atascado',
  'pasadas 24 horas del plazo el estado indica atascado sin forzar un cierre');
select set_config('request.jwt.claim.sub','',true);

select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-06','3.4'));
savepoint atraso_cierre;
set local session_replication_role=replica;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,modalidad,fecha_inicio,
  fecha_vencimiento,categoria,producto_condicion_id,fecha_cierre_comercial,analista_cierre_id)
select ('fe000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'ATRASO-TC-'||n,
  pg_temp.persona(5),1000,'PEN','mensual',date '2026-10-10',date '2027-10-10',
  'nuevo',pg_temp.persona(99),date '2026-10-10',pg_temp.persona(2)
from generate_series(1,600) n;
set local session_replication_role=origin;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()#>>'{resultado,fallo,sqlstate}'='PT409'
  and not exists(select 1 from crm.periodos_cerrados)
  and not exists(select 1 from crm.capital_valoraciones where fuente_id::text like 'fe000000-%'),
  'un atraso de 600 ventas PEN conocidas se difiere sin materializarlo bajo bloqueos del cierre');
rollback to savepoint atraso_cierre;
select pg_temp.comprobar(crm.reevaluar_cierre_capital_fn()#>>'{resultado,fallo,sqlstate}'='PT409'
  and not exists(select 1 from crm.periodos_cerrados),
  'una tasa conocida no materializa el atraso bajo bloqueos del cierre: espera al worker');
select crm.reconciliar_capital_valoraciones_fn(500);
create temp table ciclo_completo as select crm.reevaluar_cierre_capital_fn()->'resultado' as resultado;
select pg_temp.comprobar((select resultado->>'ok'='true' and (resultado->>'cerrados')::int=1
  from ciclo_completo),'al resolver la cotización el mismo ciclo sella el mes completo');
select pg_temp.comprobar((crm.reevaluar_cierre_capital_fn()#>>'{resultado,cerrados}')::integer=0
  and (select active from cron.job where jobid=3),
  'repetir la reevaluación conserva el sello y la programación sin cerrar otra vez');
select pg_temp.comprobar((select count(*)=1 from crm.capital_mes_sellos s
  join crm.capital_cortes_valorados c on c.id=s.corte_id where c.corte='2026-10-31'),
  'el sello conserva una referencia inmutable al corte completo de octubre');
select pg_temp.comprobar((select (e->>'equivalente_pen')::numeric=68000 from crm.capital_mes_sellos s
  join crm.capital_cortes_valorados c on c.id=s.corte_id,jsonb_array_elements(c.produccion) e
  where (e->>'fuente_id')::uuid=pg_temp.contrato(1)),
  'el cierre real guarda US$ 20 000 a 3,40 como S/ 68 000');
select private.consolidar_tc_venta(pg_temp.evidencia('2026-10-06','3.1'));
select crm.suspender_capital_valorado_fn();
select set_config('request.jwt.claim.sub',pg_temp.persona(2)::text,true);
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{vendedores,0,capital_valorado,equivalente_pen}')::numeric=80000,
  'cambio de cotización y reversa de presentación conservan los importes sellados');
select pg_temp.comprobar((crm.cumplimiento_metas_v2_fn('2026-10-01')#>>'{capital_valoracion,sellado}')::boolean,
  'un mes sellado sigue usando su versión aun con la presentación suspendida');
-- @CITAS_SELLADO@
select pg_temp.comprobar((select sum((e->>'equivalente_pen')::numeric)=80000
  from jsonb_array_elements(crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(2))->'operaciones') e),
  'el detalle sellado conserva los equivalentes individuales y concilia al céntimo');
do $$ begin
  begin perform crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(2),
    (select id from cortes_prueba where nombre='corregido'));
    raise exception 'Se sustituyó el detalle de un mes sellado con un corte viejo';
  exception when sqlstate 'PT409' then null; end;
  raise notice 'PASS: un mes sellado rechaza un corte anterior aunque pertenezca al mismo analista';
end $$;
select jsonb_build_object('tc_fixture','sellado','payload',crm.cumplimiento_metas_v2_fn('2026-10-01'));
select jsonb_build_object('tc_fixture','detalle-sellado','payload',crm.capital_operaciones_valoradas_fn('2026-10-01',pg_temp.persona(2)));
select pg_temp.comprobar(not has_function_privilege('authenticated','crm.activar_capital_valorado_fn(text,text)','EXECUTE')
  and not has_function_privilege('authenticated','crm.suspender_capital_valorado_fn()','EXECUTE'),
  'ningún usuario del navegador activa ni revierte la política');
rollback;
