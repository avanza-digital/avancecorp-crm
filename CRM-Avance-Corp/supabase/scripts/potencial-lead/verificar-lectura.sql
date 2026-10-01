-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20261001151704_crm_potencial_lead_lectura.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
-- Permisos EFECTIVOS con has_function_privilege (Codex f3a r1): una ACL nula significa «PUBLIC
-- ejecuta», y contar filas de aclexplode la daría por buena.
do $v$
declare
  v_puerta pg_catalog.regprocedure := 'crm.potencial_leads_fn(uuid[])'::pg_catalog.regprocedure;
  v_privadas pg_catalog.regprocedure[] := array[
    'private.potencial_lectura(uuid,uuid[],date,timestamp with time zone,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_baja(crm.nivel_potencial,date,date)'::pg_catalog.regprocedure,
    'private.potencial_proxima_corrida(timestamp with time zone)'::pg_catalog.regprocedure
  ];
  v_ejecutan text; v_ajenos int; v_acl_nula int; v_forma text; v_bandera boolean; v_marcas int; v_registro text; v_job text;
begin
  select string_agg(r.rol, ',' order by r.rol) into v_ejecutan
    from unnest(array['anon', 'authenticated', 'service_role']) r(rol)
   where has_function_privilege(r.rol, v_puerta, 'EXECUTE');
  select count(*) into v_ajenos
    from unnest(v_privadas) f(fn), unnest(array['anon', 'authenticated', 'service_role']) r(rol)
   where has_function_privilege(r.rol, f.fn, 'EXECUTE');
  select count(*) into v_acl_nula from pg_proc p where (p.oid = v_puerta or p.oid = any (v_privadas)) and p.proacl is null;
  select (case when p.prosecdef then 'DEFINER' else 'INVOKER' end) || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ','), '')
    into v_forma from pg_proc p where p.oid = v_puerta;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select count(*) into v_marcas from crm.lead_potencial;
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20261001151704';
  if to_regclass('cron.job') is not null then
    select coalesce((select schedule || ' activo=' || active::text from cron.job where jobname = 'crm-potencial-lead-caducidad'), '(sin job)') into v_job;
  else
    v_job := '(sin pg_cron)';
  end if;
  raise exception 'VERIFICAR potencial_lectura: ejecutan la puerta [%] (debe ser authenticated), EXECUTE de la API en los 3 ayudantes % (debe ser 0), funciones con ACL nula % (debe ser 0), forma [%] (debe ser DEFINER/s/search_path=""), job [%] (debe ser 10,40 10 * * * activo=true), bandera %, marcas %, registro %',
    coalesce(v_ejecutan, '(ninguno)'), v_ajenos, v_acl_nula, coalesce(v_forma, '(no existe)'), v_job, coalesce(v_bandera::text, '(no existe)'), v_marcas, v_registro;
end $v$;
