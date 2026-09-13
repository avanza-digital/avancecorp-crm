\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database()<>'citas_integracion_20260908' then raise exception 'Sólo banco local'; end if;
end $$;
insert into public.perfiles(id,nombre_completo,rol) values('90000000-0000-4000-8000-000000000001','GERENCIA VOLUMEN','comercial');
insert into crm.equipo(perfil_id,rol_crm) values('90000000-0000-4000-8000-000000000001','gerencia');
insert into crm.leads(id,nombre_completo,telefono,monto_estimado,origen,creado_en)
select ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'VOLUMEN '||n,'+51900000000',10000,
  case when n%3=0 then 'referido' when n%3=1 then 'landing' else 'telefono' end,
  '2021-01-01 15:00+00'::timestamptz+(n%1500)*interval '1 day' from generate_series(1,20000) n;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,estado,creado_en)
select l.id,'90000000-0000-4000-8000-000000000001','reunion','HISTÓRICA',
  l.creado_en+n*interval '1 day','completada',l.creado_en from crm.leads l cross join generate_series(1,3) n;
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,estado,creado_en)
select ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'90000000-0000-4000-8000-000000000001',
  'reunion','COHORTE ACTUAL','2026-09-01 15:00+00','no_show','2026-08-31 15:00+00' from generate_series(1,40) n;
insert into crm.lead_asignaciones(lead_id,analista_id,asignado_en,resultado,resultado_en)
select l.id,'90000000-0000-4000-8000-000000000001',l.creado_en,'convertido',l.creado_en+interval '5 days' from crm.leads l;
insert into crm.operaciones_cartera(id,cliente_id,vendedor_id,tipo,periodo,fecha_operacion,creado_en,elegible_conversion,moneda)
select gen_random_uuid(),('92000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  '90000000-0000-4000-8000-000000000001','upgrade',
  date_trunc('month',date '2021-01-01'+n%1500)::date,date '2021-01-01'+n%1500,
  '2021-01-01 15:00+00'::timestamptz+n*interval '1 day',true,'PEN' from generate_series(1,3000) n;
analyze crm.leads;
analyze crm.tareas;
analyze crm.lead_asignaciones;
analyze crm.operaciones_cartera;
create temporary table mediciones_citas(caso text,plan jsonb) on commit drop;
grant select,insert on mediciones_citas to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-4000-8000-000000000001',true);
do $$ declare r jsonb; p jsonb; n integer; begin
  r:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  assert jsonb_array_length(r->'citas')=160,'40 personas y todo su historial, sin las otras 19.960';
  for n in 1..3 loop
    execute 'explain(analyze,buffers,format json) select crm.citas_gerencia_consulta_fn(''2026-09-01'',''2026-09-30'')' into p;
    insert into pg_temp.mediciones_citas values('lector_nuevo_'||n,p);
    execute 'explain(analyze,buffers,format json) select private.citas_gerencia_anterior_prueba(''2026-09-01'',''2026-09-30'')' into p;
    insert into pg_temp.mediciones_citas values('lector_anterior_'||n,p);
  end loop;
end $$;
reset role;
do $$ declare p jsonb; ambito boolean; periodo date; consulta text; begin
  execute 'explain(analyze,buffers,format json) select count(*) from private.citas_episodios(''2021-01-01'',''2027-01-01'',now())' into p;
  insert into pg_temp.mediciones_citas values('nucleo_citas_historial',p);
  execute 'explain(analyze,buffers,format json) select count(*) from private.conversion_episodios(''2021-01-01'',now(),''2026-09-01'',true,''{}'',1)' into p;
  insert into pg_temp.mediciones_citas values('nucleo_conversion_global',p);
  for ambito in select unnest(array[true,false]) loop
    foreach periodo in array array[null::date,date '2026-09-01'] loop
      consulta:=format('(''2021-01-01'',now(),%L,%L,''{90000000-0000-4000-8000-000000000001}'',0.37)',periodo,ambito);
      execute 'explain(analyze,buffers,format json) select count(*) from private.conversion_episodios'||consulta into p;
      insert into pg_temp.mediciones_citas values('conversion_nueva_'||ambito||'_'||coalesce(periodo::text,'null'),p);
      execute 'explain(analyze,buffers,format json) select count(*) from private.conversion_episodios_anterior_prueba'||consulta into p;
      insert into pg_temp.mediciones_citas values('conversion_anterior_'||ambito||'_'||coalesce(periodo::text,'null'),p);
    end loop;
  end loop;
  execute 'explain(analyze,buffers,format json) select count(*) from private.citas_episodios_anterior_prueba(''2021-01-01'',''2027-01-01'',now())' into p;
  insert into pg_temp.mediciones_citas values('nucleo_citas_historial_anterior',p);
end $$;
-- Techo real: 2.500 leads x (3 históricas + 1 del mes), con cierres y reagendas.
insert into crm.tareas(lead_id,vendedor_id,tipo,titulo,vence_en,estado,creado_en)
select ('91000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'90000000-0000-4000-8000-000000000001',
  'reunion','COHORTE AMPLIA','2026-09-01 15:00+00','no_show','2026-08-31 15:00+00' from generate_series(41,2500) n;
with primeras as (select distinct on(lead_id) lead_id,id,vence_en from crm.tareas order by lead_id,vence_en,id)
update crm.tareas t set reagendada_de=p.id from primeras p
where t.lead_id=p.lead_id and t.vence_en>p.vence_en and t.lead_id<='91000000-0000-4000-8000-000000002500';
set local role authenticated;
do $$ declare r jsonb; p jsonb; begin
  r:=crm.citas_gerencia_consulta_fn('2026-09-01','2026-09-30');
  assert jsonb_array_length(r->'citas')=10000,'Techo completo con 2.500 leads, cierres y reagendas';
  execute 'explain(analyze,buffers,format json) select crm.citas_gerencia_consulta_fn(''2026-09-01'',''2026-09-30'')' into p;
  insert into pg_temp.mediciones_citas values('techo_10000_nuevo',p);
  execute 'explain(analyze,buffers,format json) select private.citas_gerencia_anterior_prueba(''2026-09-01'',''2026-09-30'')' into p;
  insert into pg_temp.mediciones_citas values('techo_10000_anterior',p);
end $$;
reset role;
select jsonb_build_object('banco','Base: 20000 leads, 60040 tareas, 20000 asignaciones, 3000 operaciones y 5 años. Techo: se añaden 2460 tareas, resultando 10000 citas para 2500 leads de la cohorte. Auth/pesos/atribución simulados',
  'mediciones',(select jsonb_agg(to_jsonb(m) order by caso) from pg_temp.mediciones_citas m));
select 'CITAS_VOLUMEN_CON_PARIDAD_OK' as resultado;
rollback;
