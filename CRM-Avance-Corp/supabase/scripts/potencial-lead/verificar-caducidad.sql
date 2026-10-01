-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20260930235917_crm_potencial_lead_caducidad.
-- Además calcula, SIN escribir, cuántas marcas bajaría la tarea si corriera hoy.
do $v$
declare
  v_job text; v_ultima text; v_privadas int; v_hoy date := (now() at time zone 'America/Lima')::date;
  v_bajarian int; v_vivas int; v_registro text;
begin
  select coalesce((select schedule || ' ' || command || ' ' || username || '@' || database || ' activo=' || active::text
                   from cron.job where jobname = 'crm-potencial-lead-caducidad'), '(sin job)') into v_job;
  select coalesce((select d.status || ' ' || to_char(d.start_time at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI') || ' Lima: ' || coalesce(left(d.return_message, 80), '')
                   from cron.job_run_details d join cron.job j on j.jobid = d.jobid
                   where j.jobname = 'crm-potencial-lead-caducidad' order by d.start_time desc limit 1), '(aún no corrió)') into v_ultima;
  select count(*) into v_privadas from pg_proc p, aclexplode(p.proacl) x
   where p.oid in ('private.potencial_caducar(date,timestamp with time zone,integer)'::regprocedure,
                   'private.potencial_nivel_tras(crm.nivel_potencial,integer)'::regprocedure,
                   'private.potencial_reloj(uuid,timestamp with time zone,timestamp with time zone)'::regprocedure,
                   'private.dias_lunes_a_sabado(date,date)'::regprocedure)
     and x.grantee <> 'postgres'::regrole;
  select count(*) filter (where p.nivel in ('estrella','tibio')),
         count(*) filter (where p.nivel in ('estrella','tibio')
                            and private.potencial_nivel_tras(p.nivel, private.dias_lunes_a_sabado(
                                  (private.potencial_reloj(p.lead_id, p.marcado_en, now()) at time zone 'America/Lima')::date, v_hoy)) < p.nivel)
    into v_vivas, v_bajarian
  from crm.lead_potencial p join crm.leads l on l.id = p.lead_id
  where l.activo is true and l.etapa not in ('convertido', 'descartado');
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20260930235917';
  raise exception 'VERIFICAR potencial_caducidad: job [%] (debe ser 10,40 10 * * * select private.potencial_caducar() postgres@postgres activo=true), última corrida [%], EXECUTE ajeno en funciones % (debe ser 0), marcas estrella/tibio vivas %, bajarían hoy (%) %, registro %',
    v_job, v_ultima, v_privadas, v_vivas, v_hoy, v_bajarian, v_registro;
end $v$;
