\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database()<>'citas_integracion_20260908' then raise exception 'Sólo banco local'; end if;
end $$;
insert into public.perfiles(id,nombre_completo,rol)
values('88000000-0000-4000-8000-000000000001','GERENCIA SINTÉTICA','comercial');
insert into crm.equipo(perfil_id,rol_crm) values('88000000-0000-4000-8000-000000000001','gerencia');
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,origen,creado_en)
select ('89000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'ESTADO '||n,'+51900000000',10000,
  case n when 3 then 'landing' when 4 then 'formulario' when 5 then 'telefono' else 'referido' end,'2026-07-01 15:00+00'
from generate_series(1,12) n;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,estado,cancelada_por,creado_en,activo)
select ('8a000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('89000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'reunion','ESTADO '||n,
  case n when 1 then now() when 2 then now()+interval '1 day' else '2026-08-10 15:00+00'::timestamptz end,
  case when n in(1,2) then 'pendiente' when n=3 then 'completada' when n=4 then 'no_show'
    when n in(5,6,7) then 'cancelada' else 'reprogramada' end,
  case n when 5 then 'asesor' when 7 then 'sistema' end,
  case when n=12 then now()+interval '1 day' else '2026-08-01 15:00+00'::timestamptz end,n<>10
from generate_series(1,12) n;
-- La cohorte de agosto incluye el seguimiento presente/futuro de las personas 1 y 2.
insert into crm.tareas(lead_id,tipo,titulo,vence_en,estado,creado_en)
select ('89000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'reunion','HISTORIA','2026-08-01 15:00+00','no_show','2026-07-31 15:00+00'
from generate_series(1,2) n;
update crm.leads set activo=false where id='89000000-0000-4000-8000-000000000011';
-- Estas tareas no deben ensanchar la lectura canónica del historial.
insert into crm.tareas(lead_id,tipo,titulo,vence_en,creado_en,activo)
values('89000000-0000-4000-8000-000000000003','llamada','ANTIGUA NO CITA','2020-01-01 15:00+00','2019-12-31 15:00+00',true),
  ('89000000-0000-4000-8000-000000000003','reunion','CITA INACTIVA','2019-01-01 15:00+00','2018-12-31 15:00+00',false);
insert into crm.lead_asignaciones(lead_id,analista_id,asignado_en,resultado,resultado_en,finalizado_en)
select ('89000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'88000000-0000-4000-8000-000000000001',
  '2026-07-01 15:00+00','convertido',
  case n when 6 then now()+interval '1 day' when 7 then '2026-08-09 15:00+00'::timestamptz
    when 8 then now() when 9 then null else '2026-08-20 15:00+00'::timestamptz end,
  '2026-08-20 15:00+00'
from generate_series(3,9) n;
insert into crm.cierres_externos(lead_id,anulado_en) values('89000000-0000-4000-8000-000000000004',now());
insert into crm.cierres_avance_anulados(lead_id) values('89000000-0000-4000-8000-000000000005');
-- Cohorte independiente: el cierre precede a la primera cita de TODO el historial.
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,creado_en)
values('89000000-0000-4000-8000-000000000013','CIERRE ANTERIOR A TODAS LAS CITAS','+51900000000',10000,'2026-05-01 15:00+00');
insert into crm.tareas(lead_id,tipo,titulo,vence_en,estado,creado_en)
values('89000000-0000-4000-8000-000000000013','reunion','POSTERIOR AL CIERRE','2026-05-20 15:00+00','completada','2026-05-19 15:00+00');
insert into crm.lead_asignaciones(lead_id,resultado,resultado_en)
values('89000000-0000-4000-8000-000000000013','convertido','2026-05-10 15:00+00');
set local role authenticated;
select set_config('request.jwt.claim.sub','88000000-0000-4000-8000-000000000001',true);
do $$ declare r jsonb; estados text[]; cierres boolean[]; begin
  r:=crm.citas_gerencia_consulta_fn('2026-08-01','2026-08-31');
  assert jsonb_array_length(r->'citas')=11,'Sólo citas activas, leads activos y registros existentes al corte';
  select array_agg(c->>'estado_comercial' order by c->>'id'),array_agg((c->>'cierre_posterior')::boolean order by c->>'id')
    into estados,cierres from jsonb_array_elements(r->'citas') c where c->>'id' like '8a000000%';
  assert estados=array['vencida','programada','realizada','no_show','cancelada','sistema','sistema','reprogramada','reprogramada'],
    'Estados vienen de las banderas canónicas, incluida igualdad exacta al corte';
  assert cierres=array[false,false,true,false,false,false,false,true,true],
    'Cierres vigentes de todos los canales, sin peso, anulaciones, futuro ni cierre anterior; coalesce y corte inclusivo';
  r:=crm.citas_gerencia_consulta_fn('2026-05-01','2026-05-31');
  assert jsonb_array_length(r->'citas')=1 and not (r->'citas'->0->>'cierre_posterior')::boolean,
    'Un cierre previo al primer vencimiento del historial no es cierre posterior';
end $$;
reset role;
-- El banco mínimo permite simular una futura ruptura del CHECK de producción.
-- El servidor debe rechazarla antes de enviar un JSON incompleto al navegador.
update crm.tareas set estado='por_clasificar' where lead_id='89000000-0000-4000-8000-000000000013';
set local role authenticated;
do $$ begin
  begin
    perform crm.citas_gerencia_consulta_fn('2026-05-01','2026-05-31');
    raise exception 'Aceptó un estado sin clasificación';
  exception when sqlstate '22023' then
    assert sqlerrm like 'Estado de reunión sin clasificación canónica:%','Debe diagnosticar la clasificación';
  end;
end $$;
reset role;
select 'CITAS_ESTADOS_Y_CIERRES_OK' as resultado;
rollback;
