set timezone='UTC';
set search_path=''; select jsonb_build_object('detalle',(select jsonb_agg(t) from (select 'funcion' as tipo,n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' as id,
 jsonb_build_object('def',md5(pg_get_functiondef(p.oid)),'body',md5(p.prosrc),'owner',p.proowner::regrole::text,'comment',md5(obj_description(p.oid,'pg_proc')),'config',p.proconfig,
 'acl',(select jsonb_agg(jsonb_build_array(a.grantee::regrole::text,a.privilege_type,a.is_grantable) order by a.grantee::regrole::text,a.privilege_type) from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a)) as valor
 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','crm')
 union all
 select 'restriccion',n.nspname||'.'||c.relname||'.'||co.conname,to_jsonb(pg_get_constraintdef(co.oid))
 from pg_constraint co join pg_class c on c.oid=co.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','crm')
 order by 1,2) t),'acl',(select jsonb_agg(t) from (with permisos as (
 select 'esquemas' as categoria,n.nspname||':'||n.nspowner::regrole::text||':'||a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable::text as linea
 from pg_namespace n cross join lateral aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a where n.nspname in ('public','crm','private')
 union all
 select 'tablas',n.nspname||'.'||c.relname||':'||c.relowner::regrole::text||':'||a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable::text
 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(coalesce(c.relacl,acldefault(case when c.relkind='S' then 's'::"char" else 'r'::"char" end,c.relowner))) a
 where n.nspname in ('public','crm','private') and c.relkind in ('r','p','v','m','S')
 union all
 select 'columnas',n.nspname||'.'||c.relname||'.'||att.attname||':'||a.grantee::regrole::text||':'||a.privilege_type||':'||a.is_grantable::text
 from pg_attribute att join pg_class c on c.oid=att.attrelid join pg_namespace n on n.oid=c.relnamespace cross join lateral aclexplode(att.attacl) a
 where n.nspname in ('public','crm','private') and not att.attisdropped
 union all
 select 'arrays_historial',version||':'||md5(to_jsonb(statements)::text) from supabase_migrations.schema_migrations
)
select categoria,count(*) as n,md5(string_agg(linea,E'\n' order by linea)) as huella from permisos group by categoria order by categoria) t)) as paridad;
