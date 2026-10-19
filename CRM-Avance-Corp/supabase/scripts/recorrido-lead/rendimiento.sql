-- Banco local desechable. 4.000 leads, 60.000 actividades y 4.000 citas.
-- Fixture sintético con triggers normales; no cambia políticas ni funciones.
begin;
set local statement_timeout='10min';
create temporary table recorrido_carga as select n,md5('recorrido-lead-'||n)::uuid id,
  md5('recorrido-cita-'||n)::uuid tarea,md5('recorrido-entrevista-'||n)::uuid entrevista from generate_series(1,4000) n;
create temporary table recorrido_tiempos(tamano integer,ms numeric,filas integer);
grant select on recorrido_carga to authenticated;
grant select,insert on recorrido_tiempos to authenticated;
insert into crm.leads(id,nombre_completo,telefono,origen,vendedor_id,monto_estimado,moneda,creado_por)
select id,'BANCO CARGA RECORRIDO '||n,'986'||lpad(n::text,6,'0'),'landing',
  'b0000000-0000-4000-8000-000000000002',1000,'PEN','b0000000-0000-4000-8000-000000000002' from recorrido_carga;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
select tarea,id,'reunion','Cita de carga',clock_timestamp()-interval '1 minute','presencial','Oficina de prueba',
  'b0000000-0000-4000-8000-000000000002' from recorrido_carga;
insert into crm.actividades(lead_id,tipo,detalle,creado_por)
select c.id,case when g%2=0 then 'llamada_no_contestada' else 'whatsapp_enviado' end,'Gestion sintetica '||g,
  'b0000000-0000-4000-8000-000000000002' from recorrido_carga c cross join generate_series(1,14) g;
insert into crm.actividades(id,lead_id,tipo,metadata,creado_por)
select entrevista,id,'reunion_realizada',jsonb_build_object('tarea_id',tarea,'resultado_reunion','interesado'),
  'b0000000-0000-4000-8000-000000000002' from recorrido_carga;
select set_config('crm.op_tarea','on',true);
update crm.tareas t set estado='completada',resultado_actividad_id=c.entrevista,resultado_reunion='interesado'
  from recorrido_carga c where t.id=c.tarea;
select set_config('crm.op_tarea','off',true);
analyze crm.leads;
analyze crm.actividades;
analyze crm.tareas;
analyze crm.lead_sla_ciclos;
analyze crm.actividad_ciclo_contexto;
analyze crm.tarea_sla_contexto;
set local role authenticated;
select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
do $$
declare v_ids uuid[];v_inicio timestamptz;v_res jsonb;v_tamano integer;v_i integer;v_offset integer;
begin
  foreach v_tamano in array array[50,100] loop
    for v_i in 0..40 loop
      v_offset:=(v_i*v_tamano)%3900;
      select array_agg(id order by n) into v_ids from recorrido_carga where n>v_offset and n<=v_offset+v_tamano;
      v_inicio:=clock_timestamp();
      v_res:=crm.recorrido_leads_fn(v_ids);
      if jsonb_array_length(v_res->'filas')<>v_tamano or exists(
        select 1 from jsonb_array_elements(v_res->'filas') f where (f->>'habilita_conversion')::boolean is not true) then
        raise exception 'La carga no evalua todas las citas validas';end if;
      -- La primera ejecución se registra aparte como calentamiento.
      if v_i>0 then insert into recorrido_tiempos values(v_tamano,extract(epoch from clock_timestamp()-v_inicio)*1000,v_tamano);end if;
    end loop;
  end loop;
end $$;
reset role;
select jsonb_build_object('tamano',tamano,'muestras',count(*),'p50_ms',round(percentile_cont(.50) within group(order by ms)::numeric,2),
  'p95_ms',round(percentile_cont(.95) within group(order by ms)::numeric,2),'max_ms',round(max(ms),2))
from recorrido_tiempos group by tamano order by tamano;
do $$ begin
  if exists(select 1 from recorrido_tiempos group by tamano having percentile_cont(.95) within group(order by ms)>=300) then
    raise exception 'FAIL: p95 excede 300 ms';end if;
  raise notice 'PASS: evaluacion por lotes sobre 4000 leads / 60000 actividades / 4000 citas, p95 < 300 ms';
end $$;
rollback;
