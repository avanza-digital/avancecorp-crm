with piezas as (
  select 'funciones' clase,n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' clave,
    jsonb_build_array(pg_get_functiondef(p.oid),r.rolname,(select array_agg(x::text order by x::text) from unnest(p.proacl) x))::text contenido
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_roles r on r.oid=p.proowner
  where n.nspname in ('crm','private','public') and p.prokind='f'
    and not exists(select 1 from pg_depend d where d.classid='pg_proc'::regclass and d.objid=p.oid and d.deptype='e')
  union all
  select 'columnas',table_schema||'.'||table_name||'.'||column_name,
    jsonb_build_array(data_type,udt_schema,udt_name,is_nullable,column_default,character_maximum_length,numeric_precision,numeric_scale)::text
  from information_schema.columns where table_schema in ('crm','private','public')
  union all
  select 'tablas_rls',n.nspname||'.'||c.relname,jsonb_build_array(c.relkind,c.relrowsecurity,c.relforcerowsecurity,r.rolname,(select array_agg(x::text order by x::text) from unnest(coalesce(c.relacl,acldefault('r',c.relowner))) x))::text
  from pg_class c join pg_namespace n on n.oid=c.relnamespace join pg_roles r on r.oid=c.relowner
  where n.nspname in ('crm','private','public') and c.relkind in ('r','p','v')
  union all
  select 'policies',schemaname||'.'||tablename||'.'||policyname,
    jsonb_build_array(permissive,roles,cmd,qual,with_check)::text
  from pg_policies where schemaname in ('crm','private','public','storage')
  union all
  select 'triggers',n.nspname||'.'||c.relname||'.'||t.tgname,pg_get_triggerdef(t.oid)||':'||t.tgenabled::text
  from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('crm','private','public','auth') and not t.tgisinternal
  union all
  select 'indices',schemaname||'.'||indexname,indexdef
  from pg_indexes where schemaname in ('crm','private','public')
  union all
  select 'grants_columnas',table_schema||'.'||table_name||'.'||column_name||'.'||grantee||'.'||privilege_type,
    jsonb_build_array(grantor,is_grantable)::text
  from information_schema.column_privileges where table_schema in ('crm','private','public')
)
select jsonb_agg(to_jsonb(r) order by clase) from (
  select clase,count(*) piezas,md5(string_agg(clave||':'||contenido,E'\n' order by clave)) huella
  from piezas group by clase
) r;
