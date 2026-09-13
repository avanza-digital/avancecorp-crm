-- Se ejecuta después de crear pg_temp.citas_gerencia_consulta_original,
-- dentro de BEGIN/ROLLBACK. Esquema completo y todas las guardas activas.
set local statement_timeout='300s';
create temporary table citas_cohorte_muestra as
select n,gen_random_uuid() lead_id,p.id analista from generate_series(1,2500) n
cross join public.perfiles p where p.correo='vend1.crm@demo.avancecorp.pe';
-- Semilla de volumen interna con sello consistente al inicio de la transacción.
-- No se desactiva ninguna guarda; los permisos se contrastan además por HTTP.
select set_config('request.jwt.claim.sub','',true);
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por)
select lead_id,'CITAS COHORTE SINTETICA '||n,'+51986'||lpad(n::text,6,'0'),
  case n%3 when 0 then 'referido' when 1 then 'landing' else 'formulario' end,
  10000,'PEN',analista,analista from citas_cohorte_muestra;
create temporary table citas_cohorte_tareas as
select m.*,s,gen_random_uuid() tarea_id from citas_cohorte_muestra m cross join generate_series(1,4) s;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por,modalidad_reunion,ubicacion_reunion)
select tarea_id,lead_id,'reunion','CITAS COHORTE '||n||' / '||s,
  timestamptz '2026-05-01 15:00+00'+s*interval '1 day',analista,'presencial','Oficina de prueba' from citas_cohorte_tareas;
select set_config('request.jwt.claim.sub',(select analista::text from citas_cohorte_muestra limit 1),true);
do $$declare r record; salida jsonb; begin
  -- Cien trayectorias pasan por las mismas puertas que el analista: no_show,
  -- asistencia y cierre en cooperativa. Las otras citas conservan el historial.
  for r in select * from citas_cohorte_tareas where n<=100 and s in(1,2) order by n,s loop
    if r.s=1 then
      perform crm.cerrar_reunion(r.tarea_id,'no_show',null,null,'Banco sintético');
    else
      perform crm.cerrar_reunion(r.tarea_id,'completada','interesado',null,'Banco sintético');
    end if;
  end loop;
  for r in select * from citas_cohorte_muestra where n<=100 order by n loop
    salida:=crm.convertir_lead_externo(r.lead_id,'qorilazo',10000,'PEN','DNI',
      '94'||lpad(r.n::text,6,'0'),'CITAS COHORTE SINTETICA','CITAS-COHORTE-'||r.lead_id::text);
    assert (salida->>'ok')::boolean,'Cierre real de la muestra aceptado';
  end loop;
end $$;
select set_config('request.jwt.claim.sub',
  (select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $$ declare viejo jsonb; nuevo jsonb; ini timestamptz; ms_viejo numeric; ms_nuevo numeric; begin
  ini:=clock_timestamp();
  viejo:=pg_temp.citas_gerencia_consulta_original('2026-05-01','2026-05-31');
  ms_viejo:=extract(epoch from clock_timestamp()-ini)*1000;
  ini:=clock_timestamp();
  nuevo:=private.citas_gerencia_consulta('2026-05-01','2026-05-31');
  ms_nuevo:=extract(epoch from clock_timestamp()-ini)*1000;
  assert jsonb_array_length(nuevo->'citas')=10000,'La cohorte conserva las 10000 citas';
  assert (select count(distinct x->>'lead_id') from jsonb_array_elements(nuevo->'citas') x)=2500,'2500 leads distintos';
  assert (select count(distinct x->>'lead_id') from jsonb_array_elements(nuevo->'citas') x where (x->>'cierre_posterior')::boolean)=100,'100 leads con cierre posterior real';
  nuevo:=jsonb_set(nuevo,'{citas}',(select jsonb_agg(x-'estado_comercial' order by x->>'vence_en',x->>'id') from jsonb_array_elements(nuevo->'citas') x));
  assert viejo=nuevo,'La cohorte mixta conserva íntegramente el contrato anterior';
  raise notice 'PASS 2500 leads / 10000 citas / 100 cierres: anterior % ms, nuevo % ms',round(ms_viejo),round(ms_nuevo);
end $$;
