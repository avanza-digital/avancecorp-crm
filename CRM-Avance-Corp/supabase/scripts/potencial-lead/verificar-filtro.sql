-- VERIFICACIÓN (solo lectura, termina SIEMPRE en raise) de 20261001212341_crm_cartera_filtro_potencial.
-- Se corre en producción después de aplicar y registrar. No escribe nada.
-- Permisos EFECTIVOS con has_function_privilege: una ACL nula significa «PUBLIC ejecuta».
do $v$
declare
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  f14_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayu constant text := 'private.cartera_potencial_fn()';
  v_firmas text; v_md5 text; v_md5_ayudante text; v_cartera text; v_ayudante text; v_forma text; v_acl_nula int; v_tabla text;
  v_declarada text; v_sello boolean; v_bandera boolean; v_marcas int; v_registro text;
begin
  -- Las huellas se miden como en la migración: sin search_path y sin comillas forzadas.
  perform set_config('search_path', '', true);
  perform set_config('quote_all_identifiers', 'off', true);
  select string_agg(p.oid::regprocedure::text, ' ## ' order by 1) into v_firmas
    from pg_proc p where p.proname = 'cartera_filtrada_fn' and p.pronamespace = 'crm'::regnamespace;
  if to_regprocedure(f14) is not null then
    v_md5 := md5(pg_get_functiondef(to_regprocedure(f14)));
    select string_agg(r.rol, ',' order by r.rol) into v_cartera
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol) where has_function_privilege(r.rol, f14, 'EXECUTE');
  end if;
  if to_regprocedure(ayu) is not null then
    select string_agg(r.rol, ',' order by r.rol) into v_ayudante
      from unnest(array['anon', 'authenticated', 'service_role']) r(rol) where has_function_privilege(r.rol, ayu, 'EXECUTE');
    select (case when p.prosecdef then 'DEFINER' else 'INVOKER' end) || '/' || p.provolatile::text || '/' || coalesce(array_to_string(p.proconfig, ','), '')
           || '/' || p.proowner::regrole::text
      into v_forma from pg_proc p where p.oid = to_regprocedure(ayu);
    v_md5_ayudante := md5(pg_get_functiondef(to_regprocedure(ayu)));
  end if;
  select count(*) into v_acl_nula from pg_proc p where p.oid in (to_regprocedure(f14), to_regprocedure(ayu)) and p.proacl is null;
  select string_agg(r.rol, ',' order by r.rol) into v_tabla
    from unnest(array['anon', 'authenticated']) r(rol)
   where has_table_privilege(r.rol, 'crm.lead_potencial', 'SELECT') or has_any_column_privilege(r.rol, 'crm.lead_potencial', 'SELECT');
  select (c.declarada and c.huella_ok)::text into v_declarada from private.contadores_crudos_leads_citas() c where c.objeto = f14_larga;
  select (s.sello = private.huella_exenciones_analitica_lc()) into v_sello from private.analitica_lc_sello s where s.id;
  select f.activo into v_bandera from crm.multiempresa_flags f where f.nombre = 'potencial_lead';
  select count(*) into v_marcas from crm.lead_potencial;
  select coalesce(max(name), '(sin registrar)') into v_registro
    from supabase_migrations.schema_migrations where version = '20261001212341';
  raise exception 'VERIFICAR filtro_potencial: firmas [%] (debe ser una, la de 14), md5 de la cartera % (debe ser 23a63cc3965472b9db85aa81cadffbeb), md5 del ayudante % (debe ser 73e993d618b203cdbe21e8127f7ea5b4), ejecutan la cartera [%] (debe ser authenticated), ejecutan el ayudante [%] (debe ser authenticated), forma del ayudante [%] (debe ser DEFINER/s/search_path=""/postgres), funciones con ACL nula % (debe ser 0), leen la tabla de marcas por la API [%] (debe ser ninguno), declaración analítica vigente % (debe ser true), sello vigente % (debe ser true), bandera %, marcas vivas %, registro %',
    coalesce(v_firmas, '(ninguna)'), coalesce(v_md5, '(no existe)'), coalesce(v_md5_ayudante, '(no existe)'), coalesce(v_cartera, '(ninguno)'), coalesce(v_ayudante, '(ninguno)'),
    coalesce(v_forma, '(no existe)'), v_acl_nula, coalesce(v_tabla, 'ninguno'), coalesce(v_declarada, '(sin declarar)'), coalesce(v_sello::text, '(sin sello)'),
    coalesce(v_bandera::text, '(no existe)'), v_marcas, v_registro;
end $v$;
