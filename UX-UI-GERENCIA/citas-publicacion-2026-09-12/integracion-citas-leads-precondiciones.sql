begin;
set local statement_timeout='120s';
do $$ begin assert to_regprocedure('crm.leads_recibidos_analista_fn(date,date)') is null,'El banco debe empezar sin la tercera candidata'; end $$;
select set_config('request.jwt.claim.sub',(select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
create temporary table integracion_citas_antes as
select private.assert_analitica_leads_citas() gate,
  private.citas_gerencia_consulta(date_trunc('month',now() at time zone 'America/Lima')::date,
    (date_trunc('month',now() at time zone 'America/Lima')+interval '1 month - 1 day')::date) payload;
