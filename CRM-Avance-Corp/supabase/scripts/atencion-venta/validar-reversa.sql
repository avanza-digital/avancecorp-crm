\set ON_ERROR_STOP on
set search_path='';
do $$ declare n text; huella text; begin
 for n,huella in select x.* from (values
 ('crm','93bf592500f1285eebb68a417df90cea'),
 ('private','af46e93e22e923f3e539dffa6fe22eec')) x(esquema,md5) loop
 if (select md5(string_agg(md5(pg_catalog.pg_get_functiondef(p.oid)),',' order by p.oid::pg_catalog.regprocedure::text))
   from pg_catalog.pg_proc p join pg_catalog.pg_namespace s on s.oid=p.pronamespace
   where s.nspname=n and p.prokind='f') is distinct from huella then
   raise exception 'La reversa no coincide con el esquema inicial: %',n;
 end if;
 end loop;
 if not has_function_privilege('service_role','public.reasignar_analista_contrato(uuid,uuid,text)','EXECUTE')
    or not has_function_privilege('anon','public.proteger_campos_inmutables()','EXECUTE') then
   raise exception 'ACL anteriores no restauradas';
 end if;
 raise notice 'PASS: reversa recupera cuerpos CRM/private y permisos anteriores';
end $$;
