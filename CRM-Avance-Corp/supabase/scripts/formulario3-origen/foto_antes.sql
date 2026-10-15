-- Se ejecuta ANTES de A: el trigger vigente genera un desglose sin Formulario 3.
insert into crm.periodos_cerrados(periodo,ponderacion_referido,meta_revision,cobertura)
values('2026-08-01',0.15,1,'{"modelo_conversion":"llegadas_v2"}');
insert into crm.cierre_mes_vendedor(periodo,vendedor_id,nombre_completo,
  supervisor_id,supervisor_nombre,divisor,cierres_no_referidos,cierres_referidos,
  cierres_de_arrastre,numerador,conversion_pct,estado,referidos_recibidos,
  referidos_dados_de_alta,conversion_objetivo)
values('2026-08-01','f6000000-0000-0000-0000-000000000001','NOMBRE CONGELADO',
  'f6000000-0000-0000-0000-000000000003','SUPERVISOR CONGELADO',10,2,0,0,2,20,'cumple',0,0,10);
create temporary table _foto_f3_antigua as
select to_jsonb(f) fila from crm.cierre_mes_vendedor f where periodo='2026-08-01';
select pg_temp.exigir(not exists(select 1 from crm.cierre_mes_vendedor f,
  jsonb_array_elements(f.origenes_ranking->'filas') o where o->>'origen'='formulario_3'),
  'fixture sellada antigua no contiene origen F3');
