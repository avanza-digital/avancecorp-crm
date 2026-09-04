-- Solo banco aislado: nunca ejecutar fixtures en producción.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() !~ '^crm_llegadas_' then
    raise exception 'Esta prueba requiere un banco crm_llegadas_* aislado';
  end if;
end $$;
truncate crm.leads, crm.lead_asignaciones, crm.operaciones_cartera,
  crm.equipo, public.perfiles, private.anulados_stub,
  crm.equipo_supervision, crm.periodos_cerrados, crm.cierre_mes_vendedor;

insert into public.perfiles(id,nombre_completo) values
 ('10000000-0000-4000-8000-000000000001','Ana'),
 ('10000000-0000-4000-8000-000000000002','Luis'),
 ('10000000-0000-4000-8000-000000000003','Supervisión'),
 ('10000000-0000-4000-8000-000000000004','Gerencia');
insert into crm.equipo(perfil_id,rol_crm,supervisor_id)
select id, case nombre_completo when 'Gerencia' then 'gerencia'
  when 'Supervisión' then 'supervisor' else 'vendedor' end,
  case when nombre_completo in ('Ana','Luis') then '10000000-0000-4000-8000-000000000003'::uuid end
from public.perfiles;
insert into crm.equipo_supervision values
 ('10000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001');

insert into crm.leads(id,creado_en,origen,alta_manual,vendedor_id,etapa)
select ('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  case n when 3 then '2026-08-15 12:00-05'::timestamptz
    when 10 then '2026-09-01 04:59:59+00'::timestamptz
    else '2026-09-01 12:00-05'::timestamptz end,
  case n when 2 then 'formulario' when 5 then 'referido' when 6 then 'oficina'
    when 7 then 'otro' else 'landing' end,
  n in (4,5,6,7),
  case when n=8 then null else '10000000-0000-4000-8000-000000000002'::uuid end,
  case when n in (2,4,5,6,7,9) then 'convertido' else 'nuevo' end
from generate_series(1,10) n;

insert into crm.lead_asignaciones(lead_id,analista_id,origen,asignado_en,resultado,resultado_en,episodio_n)
select l.id,'10000000-0000-4000-8000-000000000001',l.origen,
  l.creado_en, case when right(l.id::text,2)::int in (4,5,6,7,9) then 'convertido' end,
  case when right(l.id::text,2)::int in (4,5,6,7,9) then '2026-09-02 12:00-05'::timestamptz end,1
from crm.leads l where right(l.id::text,2)::int <> 8;
-- Ana → Luis; una nueva asignación NO es una llegada. Incluye un lead viejo.
insert into crm.lead_asignaciones(lead_id,analista_id,origen,asignado_en,resultado,resultado_en,episodio_n)
select l.id,'10000000-0000-4000-8000-000000000002',l.origen,
  '2026-09-02 12:00-05',case when right(l.id::text,2)::int=2 then 'convertido' end,
  case when right(l.id::text,2)::int=2 then '2026-09-03 12:00-05'::timestamptz end,2
from crm.leads l where right(l.id::text,2)::int in (1,2,3);
insert into private.anulados_stub values ('20000000-0000-4000-8000-000000000009');

insert into crm.operaciones_cartera(cliente_id,vendedor_id,tipo,fecha_operacion,periodo,moneda,elegible_conversion)
values
 ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','renovacion','2026-09-02','2026-09-01','PEN',true),
 ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','upgrade','2026-09-03','2026-09-01','PEN',true),
 ('30000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','upgrade','2026-09-03','2026-09-01','PEN',true),
 ('30000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000002','upgrade','2026-09-10','2026-09-01','PEN',true);

do $test$
declare r record; n numeric; d int; j jsonb;
begin
  select sum(aporte_divisor),sum(aporte_numerador) into d,n
  from private.conversion_episodios('2026-09-01 00:00-05','2026-09-04 00:00-05',null,true,null,.15);
  assert d=4 and n=3.30, format('Base/numerador esperados 4/3.30, llegaron %s/%s',d,n);
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-09-01 00:00-05','2026-09-04 00:00-05',false,array['10000000-0000-4000-8000-000000000001'::uuid],.15);
  assert r.divisor=3 and r.numerador=1.30, 'Ana conserva las llegadas y gana manual+referido+renovación';
  assert r.divisor_por_motivo='{"llegada":3}'::jsonb, 'El desglose no enumera asignaciones';
  select * into r from private.conversion_mensual_por_vendedor(
    '2026-09-01 00:00-05','2026-09-04 00:00-05',false,array['10000000-0000-4000-8000-000000000002'::uuid],.15);
  assert r.divisor=0 and r.numerador=2 and r.conversion_pct is null, 'Luis gana el cierre y upgrade, no la llegada de Ana';
  select sum(divisor),sum(numerador) into d,n from private.conversion_mensual_por_vendedor(
    '2026-09-01 00:00-05','2026-09-04 00:00-05',true,null,.15);
  assert d=4 and n=3.30, 'Agregación debe sumar aportes, incluyendo sin analista';
  select sum(aporte_numerador) into n from private.conversion_episodios(
    '2026-09-03 00:00-05','2026-09-04 00:00-05',null,true,null,.15) where tipo='operacion';
  assert n=1, 'Recortar el rango no vuelve elegible la segunda operación de un cliente';
  select sum(aporte_numerador) into n from private.conversion_episodios(
    '2026-09-01 00:00-05','2026-09-04 00:00-05','2026-09-01',true,null,.25) where tipo='operacion';
  assert n=1.25, 'Renovación consume el mismo parámetro de peso, no un 0.15 duplicado';

  -- Cambiar estado/dueño y agregar rescates no modifica las llegadas.
  update crm.leads set activo=false,etapa='descartado',vendedor_id=null where id='20000000-0000-4000-8000-000000000001';
  insert into crm.lead_asignaciones(lead_id,analista_id,origen,asignado_en,episodio_n)
  values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','landing','2026-09-03 14:00-05',3);
  select sum(divisor) into d from private.conversion_mensual_por_vendedor(
    '2026-09-01 00:00-05','2026-09-04 00:00-05',true,null,.15);
  assert d=4, 'Descartar, ocultar o rescatar no altera la base empresarial';

  perform set_config('test.uid','10000000-0000-4000-8000-000000000004',true);
  j:=private.metricas_conversiones_implementacion('2026-09-01','2026-09-03',null);
  assert j#>>'{nucleo,base}'='llegada_unica', 'Contrato de fuente incorrecto';
  assert (j#>>'{nucleo,divisor}')::int=4 and (j#>>'{nucleo,numerador}')::numeric=3.30, 'Resumen/Conversiones no cuadra';
  assert (j#>>'{nucleo,llegadas}')::int=6 and (j#>>'{nucleo,altas_manuales}')::int=1, 'Desglose de llegadas incorrecto';
  assert (j#>>'{cohorte,leads}')::int=6, 'Cosecha solo contiene llegadas admitidas, incluido descartado';
  assert (j#>>'{sondas,paridad_nucleo}')::numeric=0, 'Paridad del rango parcial debe verificarse';
  j:=private.metricas_distribucion_leads_v3_core('2026-09-01','2026-09-03','2026-09-04 12:00-05');
  assert (j#>>'{resumen,conversion,nucleo_divisor}')::int=4, 'Distribución excluyó sin analista';
  assert (j#>>'{resumen,conversion,nucleo_numerador}')::numeric=3.30, 'Distribución no ponderó cartera';
  assert (j#>>'{sondas,paridad_nucleo}')::numeric=0, 'Distribución no verifica rangos parciales';
  j:=crm.metricas_conversiones_equipo_fn('2026-09-01','2026-09-03');
  select e.value into j from jsonb_array_elements(j->'responsables') e
  where e.value->>'vendedor_id'='10000000-0000-4000-8000-000000000001';
  assert (j->>'nucleo_divisor')::int=3 and (j->>'nucleo_numerador')::numeric=1.30, 'Ranking diverge del núcleo';
  assert (j->>'leads')::int=5, 'Cosecha de Ana debe conservar su primera atribución';

  j:=crm.conversion_mensual_fn('2026-09-01');
  assert j#>>'{fuentes,divisor}'='crm.leads.creado_en', 'Mensual sigue declarando asignaciones';
  assert (j#>>'{ponderacion,renovacion}')::numeric=.15, 'Mensual no declara el peso de renovación';
  assert (j#>>'{total,divisor}')::int=4 and (j#>>'{total,numerador}')::numeric=4.30, 'Mensual no suma sin analista o no pondera cartera';
  assert (j#>>'{total,cartera,conversiones_clientes}')::int=3, 'El conteo bruto de cartera no debe volverse ponderado';
  assert (j#>>'{total,cartera,conversiones_renovacion}')::int=1, 'Renovación conserva un conteo entero';

  -- Una foto anterior conserva su fuente y peso, sin reescribir históricos.
  insert into crm.periodos_cerrados(periodo,automatico,ponderacion_referido,meta_revision,cobertura)
  values ('2026-08-01',false,.15,1,'{"medible":true,"fuera_ranking":[]}');
  j:=crm.conversion_mensual_fn('2026-08-01');
  assert j#>>'{fuentes,divisor}'='crm.lead_asignaciones.asignado_en', 'Foto legacy fue reetiquetada';
  assert (j#>>'{ponderacion,renovacion}')::numeric=1, 'Foto legacy cambió su peso';
  update crm.periodos_cerrados set cobertura = cobertura || jsonb_build_object(
    'modelo_conversion','llegadas_v2','conversion_sin_analista',jsonb_build_object(
      'divisor',1,'divisor_aproximado',0,'divisor_por_motivo',jsonb_build_object('llegada',1),
      'cierres_no_referidos',0,'cierres_referidos',0,'cierres_de_arrastre',0,'referidos_recibidos',0,'numerador',0))
  where periodo='2026-08-01';
  j:=crm.conversion_mensual_fn('2026-08-01');
  assert j#>>'{fuentes,divisor}'='crm.leads.creado_en', 'Foto nueva pierde su fuente';
  assert (j#>>'{total,divisor}')::int=1, 'Foto nueva pierde las llegadas sin analista';

  -- El perímetro público se mantiene. Un vendedor no puede pedir el reporte global.
  perform set_config('test.uid','10000000-0000-4000-8000-000000000001',true);
  begin
    perform private.metricas_conversiones_implementacion('2026-09-01','2026-09-03',null);
    raise exception 'Fallo: acceso global permitido a vendedor';
  exception when insufficient_privilege then null; end;
  perform set_config('test.uid','',true);
  begin
    perform crm.metricas_conversiones_equipo_fn('2026-09-01','2026-09-03');
    raise exception 'Fallo: acceso sin sesión';
  exception when insufficient_privilege then null; end;
  raise notice 'OK: llegadas únicas, primera atribución, pesos, fechas, reingresos, paridad y gates';
end;
$test$;
rollback;
