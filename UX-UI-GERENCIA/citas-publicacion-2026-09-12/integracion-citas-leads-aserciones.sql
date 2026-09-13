
do $$ declare antes record; despues jsonb; begin
  select * into strict antes from integracion_citas_antes;
  assert private.assert_analitica_leads_citas()=antes.gate,'La tercera migración conserva el gate analítico';
  despues:=private.citas_gerencia_consulta((antes.payload#>>'{periodo,desde}')::date,(antes.payload#>>'{periodo,hasta}')::date);
  assert despues=antes.payload,'Citas conserva íntegramente su payload con la tercera migración';
  begin perform crm.leads_recibidos_analista_fn(current_date,current_date);raise exception 'Gerencia no debe leer el contador personal';
    exception when insufficient_privilege then null;end;
  raise notice 'PASS integración: mismo gate analítico y mismo detalle Citas; Gerencia denegada en contador personal';
end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.perfiles where correo='vend1.crm@demo.avancecorp.pe'),true);
do $$ declare r jsonb; hoy date:=(now() at time zone 'America/Lima')::date; begin
  r:=crm.leads_recibidos_analista_fn(date_trunc('month',hoy)::date,hoy);
  assert (r->>'version')::integer=1,'Contrato V1';
  assert jsonb_array_length(r->'dias')=extract(day from hoy),'Serie diaria completa';
  assert (r->>'total')::integer=(select coalesce(sum((d->>'total')::integer),0) from jsonb_array_elements(r->'dias') d),'Suma consistente';
  assert (r->>'aproximados')::integer<=(r->>'total')::integer,'Aproximados dentro del total';
  begin perform private.citas_gerencia_consulta(date_trunc('month',hoy)::date,(date_trunc('month',hoy)+interval '1 month - 1 day')::date);raise exception 'Analista no debe leer detalle global';
    exception when insufficient_privilege then null;end;
  assert not has_function_privilege('anon','crm.leads_recibidos_analista_fn(date,date)','execute'),'Anon denegado';
  assert not has_function_privilege('service_role','crm.leads_recibidos_analista_fn(date,date)','execute'),'Service role denegado';
  raise notice 'PASS integración: contador personal y serie coherentes; separación de acceso intacta';
end $$;
rollback;
do $$ begin
  assert to_regprocedure('crm.leads_recibidos_analista_fn(date,date)') is null,'La tercera candidata no persiste tras el ensayo';
  assert (select count(*) from supabase_migrations.schema_migrations)=277,'Historial de la rama intacto';
  raise notice 'PASS rollback de integración: sólo permanecen las dos candidatas de Citas verificadas';
end $$;
