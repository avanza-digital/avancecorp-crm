\set ON_ERROR_STOP on
begin isolation level read committed;
set local statement_timeout='90s';
\ir fixtures.sql

create temporary table resultados(nombre text primary key);
create function pg_temp.asegurar(ok boolean,nombre text) returns void language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %',nombre; end if;
  insert into pg_temp.resultados values(nombre);
end; $$;
grant all on pg_temp.resultados to authenticated;
create function pg_temp.estado(sql text) returns text language plpgsql as $$
begin
  execute sql;
  return '00000';
exception when others then return sqlstate;
end; $$;

select pg_temp.sesion(1);
set local role authenticated;
select pg_temp.asegurar((select count(*)=11 from crm.leads),'Coordinación ve leads de empresa por RLS');
select pg_temp.asegurar((select count(*)=1 from crm.actividades),'Coordinación consulta actividades');
select pg_temp.asegurar((select count(*)=1 from crm.tareas),'Coordinación consulta tareas de leads');
select pg_temp.asegurar(jsonb_array_length(crm.cartera_filtrada_fn()->'items')=11,'Listado global de Leads');
select pg_temp.asegurar(jsonb_array_length(crm.cartera_filtrada_fn(p_desde=>'2026-10-01',p_hasta=>'2026-10-15')->'items')=11,'Leads filtrados por recepción');
select pg_temp.asegurar((select count(*)=11 from crm.cartera_pagina_fn()),'Buscador global de Leads');
select pg_temp.asegurar(crm.documento_lead_fn(pg_temp.uid(4010))->>'lead_id'=pg_temp.uid(4010)::text,'Identidad visible en la ficha del lead');
select pg_temp.asegurar(pg_temp.estado('select crm.conversion_estado_lead_v1(pg_temp.uid(4010))')='00000','Conversión del lead consultable');
select pg_temp.asegurar(pg_temp.estado('select crm.potencial_leads_fn(array[pg_temp.uid(4010)])')='00000','Potencial del lead consultable');
select pg_temp.asegurar(pg_temp.estado('select crm.estado_sla_leads_v2_fn(array[pg_temp.uid(4010)])')='00000','Gestión del lead consultable');
select pg_temp.asegurar((select count(*)>=3 from crm.equipo_visible_fn()),'Filtros de equipo visibles');
select pg_temp.asegurar(crm.cartera_inversionistas_estado_fn() @> '{"habilitada":true,"escritura_habilitada":false}', 'Cartera habilitada para consulta');
select pg_temp.asegurar((crm.cartera_inversionistas_filtrada_fn()->>'total')::int=11,'Toda la cartera de clientes');
select pg_temp.asegurar(crm.inversionista_ficha_fn(pg_temp.uid(110))->'capacidades' @>
  '{"nueva_inversion":false,"documentos":false,"postventa":false,"cuentas_perfil_ids":[]}', 'Ficha sin escrituras ni banca');
select pg_temp.asegurar(pg_temp.estado('select crm.inversionista_gestion_fn(pg_temp.uid(110))')='42501','Gestión general denegada');
select pg_temp.asegurar(pg_temp.estado('select crm.inversionista_documento_fn(pg_temp.uid(110),pg_temp.uid(2010),pg_temp.uid(2010))')='42501','Documentos denegados');
select pg_temp.asegurar(pg_temp.estado('select crm.inversionista_cuentas_fn(pg_temp.uid(110),pg_temp.uid(10),''PEN'')')='42501','Banca denegada');
with escritos as (update crm.leads set nota='Intento fuera de permisos' where id=pg_temp.uid(4010) returning id)
select pg_temp.asegurar(not exists(select 1 from escritos),'Consulta no concede UPDATE de leads');
select pg_temp.asegurar(pg_temp.estado('insert into crm.actividades(lead_id,tipo,creado_por) values(pg_temp.uid(4010),''nota'',pg_temp.uid(1))')='42501','Consulta no concede actividades');
select pg_temp.asegurar(not has_table_privilege('authenticated','crm.correcciones_categoria_contrato','INSERT'), 'No se puede fabricar autorización');
select pg_temp.asegurar(not has_function_privilege('authenticated','private.fijar_categoria_contrato(uuid,text,text,text,uuid)','EXECUTE'), 'Núcleo sin ejecución directa');
select pg_temp.asegurar(not has_function_privilege('authenticated','private.operaciones_cartera_clasificadas()','EXECUTE'), 'Proyección interna sellada');
reset role;

-- Intentos de acceso con el mismo JWT para cada rol (incluye perfiles/membresías inactivos).
do $$ declare n int; r text; begin
  foreach n in array array[4,5,6,8,9,10] loop
    perform pg_temp.sesion(n);
    set local role authenticated;
    r:=pg_temp.estado('select crm.corregir_categoria_contrato_fn(pg_temp.uid(2020),''renovacion'',''Categoría mal registrada'')');
    reset role;
    perform pg_temp.asegurar(r='42501','Corrección rechazada para actor '||n);
  end loop;
end; $$;
select pg_temp.sesion(1);
set local role authenticated;
select pg_temp.asegurar(pg_temp.estado('select crm.corregir_categoria_contrato_fn(pg_temp.uid(2010),''otra'',''Categoría mal registrada'')')='22023','Categoría inválida');
select pg_temp.asegurar(pg_temp.estado('select crm.corregir_categoria_contrato_fn(pg_temp.uid(2010),''renovacion'',''x'')')='22023','Motivo obligatorio');
reset role;

-- Paridad sin correcciones, incluso datos históricos desalineados o demo.
set local session_replication_role=replica;
update public.contratos set categoria=null where id=pg_temp.uid(2012);
update public.contratos set es_demo=true where id=pg_temp.uid(2014);
set local session_replication_role=origin;
select pg_temp.asegurar(not exists(select to_jsonb(o) from crm.operaciones_cartera o except
  select to_jsonb(p)-'categoria_corregida' from private.operaciones_cartera_clasificadas() p)
  and not exists(select to_jsonb(p)-'categoria_corregida' from private.operaciones_cartera_clasificadas() p except
  select to_jsonb(o) from crm.operaciones_cartera o),'Proyección idéntica sin correcciones, incluidos demo');
select pg_temp.asegurar((select count(*)=2 and bool_and(categoria='renovacion') from private.capital_episodios(
  '2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',true,'{}') where contrato_id=pg_temp.uid(2012)
  and medida in ('desglose_renovado','desglose_adicional')),'Desglose histórico sin corrección conserva su categoría');
set local session_replication_role=replica;
update public.contratos set categoria='renovacion' where id=pg_temp.uid(2012);
update public.contratos set es_demo=false where id=pg_temp.uid(2014);
set local session_replication_role=origin;

create temporary table dinero_antes as select id,capital,tasa_anual,moneda,fecha_inicio,fecha_vencimiento,analista_cierre_id from public.contratos;
create temporary table operaciones_antes as select * from crm.operaciones_cartera;
create temporary table relojes_antes as select id,confirmado_en,vinculado_en,acreditado_en,fecha_comercial,plazo_hasta from crm.conversion_acreditaciones;
create temporary table transiciones(n int,actor int,categoria text);
insert into transiciones values(10,1,'renovacion'),(11,2,'nuevo'),(12,3,'upgrade'),(13,7,'upgrade'),(14,1,'renovacion'),(15,2,'nuevo');
do $$ declare r record; j jsonb; begin
  for r in select * from pg_temp.transiciones order by n loop
    perform pg_temp.sesion(r.actor);
    set local role authenticated;
    j:=crm.corregir_categoria_contrato_fn(pg_temp.uid(2000+r.n),r.categoria,'El analista registró una categoría incorrecta');
    reset role;
    perform pg_temp.asegurar(j @> jsonb_build_object('ok',true,'cambio',true,'categoria',r.categoria),'Transición autorizada '||r.n);
  end loop;
end; $$;
set constraints all immediate;
set constraints all deferred;
select pg_temp.asegurar((select count(*)=6 from crm.correcciones_categoria_contrato),'Seis correcciones auditadas');
select pg_temp.asegurar(not exists(select * from operaciones_antes except select * from crm.operaciones_cartera)
  and not exists(select * from crm.operaciones_cartera except select * from operaciones_antes),'Registro financiero intacto');
select pg_temp.asegurar(not exists(select * from dinero_antes except
  select id,capital,tasa_anual,moneda,fecha_inicio,fecha_vencimiento,analista_cierre_id from public.contratos),'Capital, tasa, fechas y vendedor conservados');
select pg_temp.asegurar(not exists(select * from relojes_antes except
  select id,confirmado_en,vinculado_en,acreditado_en,fecha_comercial,plazo_hasta from crm.conversion_acreditaciones),'Relojes de conversión conservados');
select pg_temp.asegurar((select count(*)=2 and bool_and(categoria='upgrade') from private.capital_episodios(
  '2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',true,'{}') where contrato_id=pg_temp.uid(2012)
  and medida in ('desglose_renovado','desglose_adicional')),'Desglose corregido reclasificado sin cambiar importes');

do $$ declare r record; v_cierres int; v_ops int; v_aporte numeric; v_categoria text; begin
  for r in select * from pg_temp.transiciones loop
    select count(*) filter(where e.tipo='cierre'),count(*) filter(where e.tipo='operacion'),coalesce(sum(aporte_numerador),0)
      into v_cierres,v_ops,v_aporte
    from private.conversion_episodios('2026-10-01 00:00:00-05','2026-11-01 00:00:00-05','2026-10-01',true,'{}',0.15) e
    where (e.tipo='cierre' and e.lead_id=pg_temp.uid(4000+r.n)) or
      (e.tipo='operacion' and e.operacion_id in
        (select o.id from private.operaciones_cartera_clasificadas() o where o.contrato_nuevo_id=pg_temp.uid(2000+r.n)));
    perform pg_temp.asegurar(v_cierres+v_ops=1,'Sin doble conteo '||r.n);
    perform pg_temp.asegurar(v_cierres=case when r.categoria='nuevo' then 1 else 0 end
      and v_aporte=case when r.categoria='renovacion' then 0 else 1 end,'Conversión correcta '||r.n);
    select f.categoria into v_categoria from private.ranking_capital_origen_filas(
      '2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',null) f where f.operacion_id=pg_temp.uid(2000+r.n);
    perform pg_temp.asegurar(v_categoria=r.categoria,'Ranking reclasificado '||r.n);
  end loop;
end; $$;
select pg_temp.asegurar((select sum(monto)=22000 from private.capital_episodios(
  '2026-10-01 00:00:00-05','2026-11-01 00:00:00-05',true,'{}') where medida='stock'),'Capital total sin duplicación');
select pg_temp.sesion(1);
set local role authenticated;
select pg_temp.asegurar(crm.corregir_categoria_contrato_fn(pg_temp.uid(2010),'renovacion','Reintento sin cambios')->>'cambio'='false','Reintento idempotente');
reset role;
select pg_temp.asegurar((select count(*)=6 from crm.correcciones_categoria_contrato),'Reintento no duplica auditoría');
select pg_temp.asegurar(pg_temp.estado('update crm.correcciones_categoria_contrato set motivo=''Intento de reemplazo''')='42501','Historial inmutable');
select pg_temp.asegurar(pg_temp.estado('update public.contratos set categoria=''renovacion'' where id=pg_temp.uid(2020)')='23514','UPDATE directo no elude la puerta');

-- Los históricos sin clasificación pueden corregirse y la auditoría conserva el NULL.
set local session_replication_role=replica;
update public.contratos set categoria=null where id=pg_temp.uid(2016);
set local session_replication_role=origin;
set local role authenticated;
select pg_temp.asegurar(crm.corregir_categoria_contrato_fn(pg_temp.uid(2016),'renovacion','Corregir histórico sin categoría')->>'cambio'='true','Categoría histórica vacía corregible');
reset role;
select pg_temp.asegurar(exists(select 1 from crm.correcciones_categoria_contrato where contrato_id=pg_temp.uid(2016)
  and categoria_anterior is null and categoria_nueva='renovacion'),'Auditoría conserva categoría anterior vacía');

-- Reclasificar a Nuevo no vuelve a abrir el plazo original.
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2017),'renovacion','Preparar captación con plazo vencido');
set local session_replication_role=replica;
update crm.conversion_acreditaciones set confirmado_en='2026-11-15',vinculado_en='2026-11-15',acreditado_en='2026-11-15'
where fuente_id=pg_temp.uid(2017);
set local session_replication_role=origin;
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2017),'nuevo','Restituir clasificación correcta');
select pg_temp.asegurar((select estado='fuera_de_plazo' and confirmado_en='2026-11-15'::timestamptz
  from crm.conversion_acreditaciones where fuente_id=pg_temp.uid(2017)),'La corrección respeta el plazo vencido');

-- El primer mes conserva la exclusión de Upgrade y no crea un nuevo cierre.
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2020),'upgrade','Corregir upgrade del primer mes');
select pg_temp.asegurar((select not elegible_conversion from private.operaciones_cartera_clasificadas()
  where contrato_nuevo_id=pg_temp.uid(2020)),'Upgrade del primer mes no suma conversión');

-- Una identidad ya acreditada no bloquea corregir la clasificación ni gana otro crédito.
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2018),'renovacion','Categoría incorrecta antes de conciliar identidad');
set local session_replication_role=replica;
update crm.conversion_acreditaciones set inversionista_id=pg_temp.uid(118) where fuente_id=pg_temp.uid(2019);
set local session_replication_role=origin;
select crm.corregir_categoria_contrato_fn(pg_temp.uid(2018),'nuevo','Corregir clasificación conservando identidad única');
select pg_temp.asegurar((select categoria='nuevo' from public.contratos where id=pg_temp.uid(2018))
  and (select estado='operacion_cartera' from crm.conversion_acreditaciones where fuente_id=pg_temp.uid(2018)),
  'Identidad acreditada permite corregir sin otra captación');

-- Un producto catalogado y luego archivado conserva sus condiciones originales.
set local session_replication_role=replica;
insert into crm.productos_inversion(id,codigo) values(pg_temp.uid(8018),'PRUEBA-CATEGORIA');
insert into crm.producto_versiones(id,producto_id,numero_version,estado,nombre,vigente_desde,publicada_en)
values(pg_temp.uid(8118),pg_temp.uid(8018),1,'publicada','Producto sintético',current_date-100,now());
insert into crm.producto_condiciones(id,version_id,orden,categoria,moneda,plazo_meses,modalidad,tipo_interes,
capital_minimo,capital_maximo,tasa_referencia,tasa_minima,tasa_maxima)
values(pg_temp.uid(8218),pg_temp.uid(8118),1,'nuevo','PEN',12,'mensual','simple',1000,5000,15,15,15);
set local session_replication_role=origin;
insert into public.contratos(id,numero_contrato,cliente_id,capital,moneda,tasa_anual,modalidad,
fecha_inicio,fecha_vencimiento,categoria,analista_cierre_id,creado_por,creado_en,producto_condicion_id)
values(pg_temp.uid(9018),'PRUEBA-CATALOGADO',pg_temp.uid(18),1000,'PEN',15,'mensual',
'2026-10-05','2027-10-05','nuevo',pg_temp.uid(4),pg_temp.uid(4),'2026-10-05 12:00:00-05',pg_temp.uid(8218));
update crm.productos_inversion set estado='archivado',archivado_en=now(),revision=revision+1 where id=pg_temp.uid(8018);
set local role authenticated;
select pg_temp.asegurar(crm.corregir_categoria_contrato_fn(pg_temp.uid(9018),'renovacion','Corregir categoría con producto archivado')->>'cambio'='true','Producto archivado admite corrección');
reset role;
select pg_temp.asegurar((select producto_condicion_id=pg_temp.uid(8218) and capital=1000 and tasa_anual=15
  from public.contratos where id=pg_temp.uid(9018)),'Snapshot de producto archivado conservado');
select pg_temp.asegurar(pg_temp.estado('update public.contratos set tasa_anual=16 where id=pg_temp.uid(9018)')='23514','La excepción no permite cambiar condiciones económicas');
set constraints all immediate;
set constraints all deferred;

-- Sello: la corrección no puede reescribir fotografías mensuales.
insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura) values('2026-10-01',0.15,1,'{}');
select pg_temp.sesion(1);
set local role authenticated;
select pg_temp.asegurar(pg_temp.estado('select crm.corregir_categoria_contrato_fn(pg_temp.uid(2020),''renovacion'',''Corrección después del sello'')')='P0409','Mes sellado protegido');
reset role;

-- Revocación efectiva sin renovar JWT.
set local session_replication_role=replica;
update crm.equipo set activo=false where perfil_id=pg_temp.uid(1);
set local session_replication_role=origin;
set local role authenticated;
select pg_temp.asegurar(not exists(select 1 from crm.leads),'Baja CRM corta lectura');
select pg_temp.asegurar(pg_temp.estado('select crm.cartera_inversionistas_estado_fn()')='42501','Baja CRM corta cartera');
select pg_temp.asegurar(pg_temp.estado('select crm.corregir_categoria_contrato_fn(pg_temp.uid(2020),''renovacion'',''Corrección después de baja'')')='42501','Baja CRM corta corrección');
reset role;
select 'PASS: '||count(*)||' comprobaciones de permisos, correcciones, conversión, ranking y auditoría' from resultados;
rollback;
