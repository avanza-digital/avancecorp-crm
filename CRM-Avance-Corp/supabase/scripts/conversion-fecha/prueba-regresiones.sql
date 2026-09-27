begin;
set local statement_timeout='30s';
set local lock_timeout='3s';
-- Histórico no vacío, preparado ANTES de instalar la candidata. Sólo fixture.
-- Restaurar un snapshot sintético de agosto exige esta excepción de siembra:
-- un episodio ya cerrado es inmutable en operación. Se restaura el guard
-- ANTES de instalar/ejercitar el producto; nada de esto entra en la migración.
alter table crm.lead_asignaciones disable trigger trg_lead_asignaciones_00_inmutables;
alter table crm.lead_asignaciones disable trigger trg_lead_asignaciones_00_sla_global_inmutable;
update crm.lead_asignaciones set asignado_en='2026-08-01 12:00-05',
 sla_global_iniciado_en='2026-08-01 12:00-05',resultado_en='2026-08-24 12:00-05',
 finalizado_en='2026-08-24 12:00-05'
where lead_id=(select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000005');
alter table crm.lead_asignaciones enable trigger trg_lead_asignaciones_00_inmutables;
alter table crm.lead_asignaciones enable trigger trg_lead_asignaciones_00_sla_global_inmutable;
create temp table agosto_antes as select * from private.conversion_cierres(
 '2026-08-01 00:00-05','2026-09-01 00:00-05','2026-08-01',true,'{}',0.15,null);
-- @MIGRACION@
create or replace function private.conversion_instante_servidor()
returns timestamptz language sql volatile security invoker set search_path=''
as $$ select '2026-09-26 22:00-05'::timestamptz $$;
create function pg_temp.exigir(p_ok boolean,p_motivo text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_motivo; end if; end $$;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000003',true);
select set_config('crm.op_privilegiada','on',true);
select pg_temp.exigir((select sum(aporte_numerador)>0 from agosto_antes),'historico agosto no vacio');
select pg_temp.exigir(not exists(
 (select * from agosto_antes except all select * from private.conversion_cierres(
  '2026-08-01 00:00-05','2026-09-01 00:00-05','2026-08-01',true,'{}',0.15,null))
 union all (select * from private.conversion_cierres(
  '2026-08-01 00:00-05','2026-09-01 00:00-05','2026-08-01',true,'{}',0.15,null) except all select * from agosto_antes)),
 'agosto conserva exactamente sus cierres anteriores');

-- Dos contratos distintos de la MISMA persona, no dos llamadas al evaluador.
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
 'id','e0000000-0000-4000-8000-00000000f002','numero_contrato','BANCO-CONVERSION-MAYO',
 'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
 'fecha_inicio','2026-05-21','creado_en','2026-05-22T17:00:00+00:00'))).*
from public.contratos c where id='e0000000-0000-4000-8000-00000000000f';
select crm.corregir_fecha_cierre_comercial('e0000000-0000-4000-8000-00000000f002',
 '2026-05-21','Fecha de la fuente sintetica antigua');
insert into public.contratos
select (jsonb_populate_record(null::public.contratos,to_jsonb(c)||jsonb_build_object(
 'id','e0000000-0000-4000-8000-00000000f003','numero_contrato','BANCO-CONVERSION-SEPTIEMBRE',
 'producto_condicion_id',null,'fecha_cierre_comercial',null,'fuente_cierre_comercial',null,
 'fecha_inicio','2026-09-17','creado_en','2026-09-21T17:00:00+00:00'))).*
from public.contratos c where id='e0000000-0000-4000-8000-00000000000f';
do $$ declare l uuid;
begin
 select id into l from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000004';
 perform private.conversion_acreditar_fuente(l,'contrato','e0000000-0000-4000-8000-00000000f002','Fuente antigua sin credito tardio');
 perform pg_temp.exigir((select estado='fuera_de_plazo' from crm.conversion_acreditaciones where lead_id=l),
  'mayo vinculado en septiembre no acredita');
 perform private.conversion_acreditar_fuente(l,'contrato','e0000000-0000-4000-8000-00000000000f','Operacion de cartera no es captacion');
 perform pg_temp.exigir((select estado='operacion_cartera' from crm.conversion_acreditaciones where lead_id=l),
  'continuidad de cartera no crea otra captacion');
 perform private.conversion_acreditar_fuente(l,'contrato','e0000000-0000-4000-8000-00000000f003','Seleccion expresa de fuente de septiembre');
 perform private.conversion_sincronizar_lead(l);
 perform pg_temp.exigir((select count(*)=1 and bool_and(fuente_id='e0000000-0000-4000-8000-00000000f003'
  and estado='acreditada' and periodo_comercial=date '2026-09-01') from crm.conversion_acreditaciones where lead_id=l),
  'solo septiembre seleccionado; sincronizar no vuelve a elegir mayo');
 perform pg_temp.exigir((select sum(aporte_numerador)=1 from private.conversion_cierres(
  '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,array[l])),
  'dos contratos producen una sola conversion de septiembre');
end $$;

-- Fusión canónica ya existente: dos leads no pueden fabricar dos captaciones.
update crm.inversionistas set estado='fusionado',fusionado_en=clock_timestamp(),
 inversionista_canonico_id=(select inversionista_id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000004')
where id=(select inversionista_id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000002');
do $$ begin
 begin
  perform private.conversion_acreditar_fuente(
   (select id from crm.leads where perfil_id='c0000000-0000-4000-8000-000000000002'),
   'contrato','e0000000-0000-4000-8000-00000000000b','Otra fuente de identidad ya acreditada');
  raise exception 'FAIL: doble captacion de identidad fusionada';
 exception when sqlstate 'P0409' then
  if sqlerrm<>'La identidad ya tiene una captacion acreditada' then raise; end if;
 end;
end $$;
-- Una fuente marcada demo después de acreditarse deja de sumar en mes abierto.
select public.marcar_contrato_demo('e0000000-0000-4000-8000-00000000f003',true,
 'Fuente sintetica marcada demo despues de la acreditacion');
select pg_temp.exigir(not exists(select 1 from private.conversion_cierres(
 '2026-09-01 00:00-05','2026-10-01 00:00-05','2026-09-01',true,'{}',0.15,null)),
 'demo no suma aunque exista el hecho historico acreditado');
select 'PASS: regresiones de seleccion exacta, agosto, identidad y demo' as resultado;
rollback;
