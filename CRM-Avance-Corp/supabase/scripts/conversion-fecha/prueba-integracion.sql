begin;
set local statement_timeout='40s';
set local lock_timeout='3s';
-- @MIGRACION@
-- @RELOJ_CIERRE@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select set_config('crm.op_privilegiada','on',true);

-- Cuota publicada sintética: probar el roster nominal, no sólo fuera_ranking.
-- Las tablas versionadas/auditadas conservan sus triggers; toda la siembra
-- pertenece al banco y se revierte al terminar.
with periodo as (
 insert into crm.meta_periodos(periodo,revision,revision_anterior_id,publicada_por)
 select '2026-09-01',coalesce(max(revision),0)+1,
  (select id from crm.meta_periodos where periodo='2026-09-01' order by revision desc limit 1),
  'b0000000-0000-4000-8000-000000000003' from crm.meta_periodos where periodo='2026-09-01'
 returning id
)
insert into crm.metas_vendedor(meta_periodo_id,vendedor_id,supervisor_id,conversion_objetivo)
select p.id,e.perfil_id,e.supervisor_id,10 from periodo p cross join crm.equipo e
where e.rol_crm='vendedor' and e.supervisor_id is not null;

-- El fixture heredado de Ranking tiene un catálogo que no coincide con sus
-- términos, por eso no sirve para probar correcciones. Crear una fuente nueva
-- y su snapshot legacy válido mediante los triggers reales, sin desactivarlos.
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
  'id','e0000000-0000-4000-8000-00000000f001','numero_contrato','BANCO-CONVERSION-FECHA-1',
  'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
  'creado_en','2026-09-25T17:00:00+00:00'))).*
from public.contratos c where id='e0000000-0000-4000-8000-00000000000a';

create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
create temp table capital_antes as select id,capital,moneda from public.contratos;
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000f001'
where perfil_id='c0000000-0000-4000-8000-000000000001';
update crm.leads set contrato_id='e0000000-0000-4000-8000-00000000000b'
where perfil_id='c0000000-0000-4000-8000-000000000002';
select pg_temp.exigir((select count(*) from crm.conversion_acreditaciones)=2,
 'vinculos explicitos alimentan credito automaticamente');

select crm.corregir_fecha_cierre_comercial('e0000000-0000-4000-8000-00000000f001',
 '2026-08-29','Correccion sintetica al mes anterior');
select pg_temp.exigir((select estado='fuera_de_plazo' and periodo_comercial=date '2026-08-01'
 from crm.conversion_acreditaciones where fuente_id='e0000000-0000-4000-8000-00000000f001'),
 'correccion de fecha reevalua sin credito retroactivo');
select pg_temp.exigir(not exists(select 1 from private.conversion_cierres(
 '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null) c
 where c.lead_id=(select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001')),
 'tardio no se traslada a septiembre');
select pg_temp.exigir(private.registrar_ajuste_si_mes_cerrado(
 (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'Nunca se abono ese credito','b0000000-0000-4000-8000-000000000003') is null,
 'tardio no fabrica deuda');

select crm.corregir_fecha_cierre_comercial('e0000000-0000-4000-8000-00000000f001',
 '2026-09-05','Restaurar fecha comercial correcta del banco');
select pg_temp.exigir((select estado='acreditada' from crm.conversion_acreditaciones
 where fuente_id='e0000000-0000-4000-8000-00000000f001'),'fecha corregida valida en septiembre');
select pg_temp.exigir((crm.alarma_conversion_fn()->>'cuadra')::boolean,
 'paridad de los cinco caminos con la acreditacion comercial');
do $$ declare metas jsonb:=crm.cumplimiento_metas_fn('2026-09-01');
  oficial jsonb:=crm.conversion_mensual_fn('2026-09-01'); r record;
begin
  perform pg_temp.exigir(jsonb_array_length(metas->'vendedores')>0,'roster nominal de Metas no vacio');
  -- Probar también los responsables sin cuota que la puerta separa del roster.
  metas:=metas||jsonb_build_object('comparables',coalesce(metas->'vendedores','[]'::jsonb)||
    coalesce((select jsonb_agg(jsonb_build_object('vendedor_id',x->'persona_id',
      'numerador',x#>'{conversion,numerador}')) from jsonb_array_elements(metas->'fuera_ranking') e(x)
      where x->'conversion'<>'null'::jsonb),'[]'::jsonb));
  perform pg_temp.exigir(jsonb_array_length(metas->'comparables')>0,'Metas tiene analistas no vacios');
  for r in select m.x as meta,o.x as mensual
    from jsonb_array_elements(metas->'comparables') m(x)
    left join jsonb_array_elements(oficial->'responsables') o(x)
      on o.x->>'vendedor_id'=m.x->>'vendedor_id'
  loop
    perform pg_temp.exigir(r.mensual is not null and
      (r.meta->>'numerador')::numeric=(r.mensual->>'numerador')::numeric,
      'Metas y oficial mantienen numerador por analista');
  end loop;
  perform pg_temp.exigir((select sum(cierres)=2 from private.ranking_conversion_origen_mes(
    '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',0.15)),
    'Ranking por origen recibe solo los dos cierres acreditados');
end $$;

-- Corregir solamente el día, después del plazo y antes del sello, conserva
-- el vínculo ya acreditado. Cron apagado no hace caducar un crédito válido.
create temp table vinculo_antes_correccion as select vinculado_en from crm.conversion_acreditaciones
 where fuente_id='e0000000-0000-4000-8000-00000000f001';
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-10-12 10:00-05'::timestamptz $$;
select crm.corregir_fecha_cierre_comercial('e0000000-0000-4000-8000-00000000f001',
 '2026-09-08','Correccion del dia sin cambiar el mes ya acreditado');
select pg_temp.exigir((select estado='acreditada' and vinculado_en=(select vinculado_en from vinculo_antes_correccion)
 from crm.conversion_acreditaciones where fuente_id='e0000000-0000-4000-8000-00000000f001'),
 'correccion del mismo mes despues del plazo no quita credito valido');

-- Foto no vacía real, construida por el cierre bajo reloj de banco.
-- Modela registro administrativo en octubre con crédito comercial septiembre.
-- El campo legado no debe escoger el mes de la deuda. No altera el episodio.
update crm.leads set convertido_en='2026-10-01 12:00-05'
where perfil_id='c0000000-0000-4000-8000-000000000001';
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-10-11 09:20-05'::timestamptz $$;
select crm.cerrar_periodo('2026-08-01');
select crm.cerrar_periodo('2026-09-01');
create temp table foto_antes as select * from crm.cierre_mes_vendedor;
select pg_temp.exigir(exists(select 1 from foto_antes where periodo='2026-09-01' and numerador>0),
 'sello con credito no vacio');
select pg_temp.exigir((select incluida_en_sello from crm.conversion_acreditaciones
 where fuente_id='e0000000-0000-4000-8000-00000000f001'),'pertenencia al sello preservada por fuente');

-- El origen operativo del lead puede editarse sin reescribir la foto ni
-- bloquear la edición: el crédito y la deuda conservan el origen congelado.
update crm.leads set origen='landing' where perfil_id='c0000000-0000-4000-8000-000000000001';
select pg_temp.exigir((select origen='referido' from crm.conversion_acreditaciones
 where fuente_id='e0000000-0000-4000-8000-00000000f001'),'origen del credito sellado no cambia');

select crm.anular_cierre_avance(
 (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'Anulacion sintetica despues del sello');
select pg_temp.exigir(exists(select 1 from crm.ajustes_mes_cerrado a
 join crm.conversion_acreditaciones ca on ca.lead_id=a.lead_id
 where ca.fuente_id='e0000000-0000-4000-8000-00000000f001'
 and a.periodo_origen='2026-09-01' and a.numerador>0 and a.capital_pen=0 and a.capital_usd=0),
 'anulacion posterior genera solo deuda de conversion del mes comercial');
select pg_temp.exigir(private.registrar_ajuste_si_mes_cerrado(
 (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001'),
 'Reintento no duplica la deuda','b0000000-0000-4000-8000-000000000003') is null,
 'deuda posterior idempotente');
do $$ declare deuda numeric; actor uuid; cobro record;
begin
 select a.pendiente_numerador,a.vendedor_id into strict deuda,actor from crm.ajustes_mes_cerrado a
 where a.lead_id=(select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000001');
 perform pg_temp.exigir((select ajuste_pendiente=deuda from private.conversion_neta_por_vendedor(
  '2026-10-01',true,'{}') where analista_id=actor),'mes siguiente recibe la deuda una sola vez');
 select * into cobro from private.saldar_ajustes(actor,1,0,0);
 perform pg_temp.exigir(cobro.aplicado_numerador=deuda and cobro.aplicado_pen=0 and cobro.aplicado_usd=0,
  'saldo cobra solo el credito de conversion sin tocar capital');
 select * into cobro from private.saldar_ajustes(actor,1,0,0);
 perform pg_temp.exigir(cobro.aplicado_numerador=0,'saldo repetido no cobra dos veces');
end $$;
select pg_temp.exigir(not exists(
 (select * from foto_antes except all select * from crm.cierre_mes_vendedor)
 union all (select * from crm.cierre_mes_vendedor except all select * from foto_antes)),
 'anulacion no reescribe fotos selladas');
-- La alarma de mes ABIERTO compara bruto vivo - deuda; no es un oráculo para
-- una foto sellada (el bruto vivo ya excluye la anulación). Comparar las
-- puertas publicadas contra la foto conservada, no forzar que esa foto cambie.
do $$ declare mensual jsonb; rango jsonb; distribucion jsonb; esperado numeric;
  hasta date:=least((now() at time zone 'America/Lima')::date,date '2026-09-30');
begin
  mensual:=crm.conversion_mensual_fn('2026-09-01');
  rango:=crm.metricas_conversiones_fn('2026-09-01',hasta,null);
  distribucion:=crm.metricas_distribucion_leads_v3_fn('2026-09-01',hasta);
  select sum(numerador) into esperado from foto_antes where periodo='2026-09-01';
  perform pg_temp.exigir((mensual#>>'{total,numerador}')::numeric=esperado
    and (rango#>>'{nucleo,numerador}')::numeric=esperado
    and (distribucion#>>'{resumen,conversion,nucleo_numerador}')::numeric=esperado,
    'consumidores sellados conservan la misma foto sin descontar deuda retroactiva');
end $$;

do $$ begin
  begin
    perform crm.corregir_fecha_cierre_comercial('e0000000-0000-4000-8000-00000000000b',
      '2026-08-28','Intento de mover mes sellado');
    raise exception 'FAIL: correccion de mes sellado aceptada';
  exception when sqlstate 'P0409' then
    if sqlerrm<>'No se puede reescribir un mes comercial sellado' then raise; end if;
  end;
end $$;
select pg_temp.exigir(not exists(select * from capital_antes except all
 select id,capital,moneda from public.contratos),'capital y monedas permanecen intactos');
select 'PASS: integracion de enlace, correccion, cierre y anulacion' as resultado;
rollback;
