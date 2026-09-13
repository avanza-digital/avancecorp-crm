-- Esquema completo del banco. El runner crea previamente en pg_temp tres
-- oráculos a partir de las definiciones originales capturadas de producción.
-- Comparar conjuntos completos, incluidos importes y pesos de consumidores
-- antiguos; los oráculos no llaman a los nuevos helpers extraídos.
select set_config('request.jwt.claim.sub',
  (select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $$
declare ini timestamptz; fin timestamptz; corte timestamptz; ids uuid[]; global boolean;
  periodo date; m date; a jsonb; b jsonb; n integer:=0;
begin
  assert exists(select 1 from crm.tareas where estado='no_show'),'Se exige una muestra de inasistencias';
  assert exists(select 1 from crm.lead_asignaciones where resultado='convertido'),'Se exigen cierres reales del banco';
  ini:='2026-01-01 05:00+00'; fin:='2027-01-01 05:00+00';
  foreach corte in array array['2026-08-01 05:00+00'::timestamptz,now(),now()+interval '1 month'] loop
    select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into a
      from pg_temp.citas_episodios_original(ini,fin,corte) x;
    select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into b
      from private.citas_episodios(ini,fin,corte) x;
    assert a=b,'La firma original de citas conserva todos los hechos'; n:=n+1;
    for ids in select null::uuid[] union all select '{}'::uuid[] union all
      select array[id] from crm.leads where nombre_completo like 'CITAS BANCO%' limit 8 loop
      select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into a
        from pg_temp.citas_episodios_original(ini,fin,corte) x where ids is null or x.lead_id=any(ids);
      select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into b
        from private.citas_episodios(ini,fin,corte,ids) x;
      assert a=b,'El filtro de cohorte conserva exactamente NULL, vacío y subconjuntos'; n:=n+1;
    end loop;
  end loop;
  foreach global in array array[true,false] loop
    foreach periodo in array array[null::date,'2026-09-01'::date] loop
      for ids in select '{}'::uuid[] union all select array[id] from public.perfiles where correo='vend1.crm@demo.avancecorp.pe' loop
        select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into a
          from pg_temp.conversion_episodios_original(ini,fin,periodo,global,ids,0.15) x;
        select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into b
          from private.conversion_episodios(ini,fin,periodo,global,ids,0.15) x;
        assert a=b,'Todos los episodios, canales y pesos conservan su contrato'; n:=n+1;
        select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into a
          from pg_temp.conversion_episodios_original(ini,fin,periodo,global,ids,0.15) x where tipo='cierre';
        select coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]') into b
          from private.conversion_cierres(ini,fin,periodo,global,ids,0.15,null) x;
        assert a=b,'El helper de cierres es la extracción exacta del núcleo'; n:=n+1;
        assert not exists(select 1 from private.conversion_cierres(ini,fin,periodo,global,ids,0.15,'{}')),
          'Una cohorte vacía no trae cierres ajenos'; n:=n+1;
      end loop;
    end loop;
  end loop;
  foreach m in array array['2026-07-01'::date,'2026-08-01','2026-09-01','2026-10-01'] loop
    a:=pg_temp.citas_gerencia_consulta_original(m,(m+interval '1 month - 1 day')::date);
    b:=private.citas_gerencia_consulta(m,(m+interval '1 month - 1 day')::date);
    b:=jsonb_set(b,'{citas}',(select coalesce(jsonb_agg(x-'estado_comercial' order by x->>'vence_en',x->>'id'),'[]') from jsonb_array_elements(b->'citas') x));
    assert a=b,format('El contrato V2 conserva todos sus campos previos en %s',m); n:=n+1;
  end loop;
  raise notice 'PASS % comparaciones completas con los núcleos y lector anteriores',n;
end $$;
