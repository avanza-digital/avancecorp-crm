-- Huellas de identidad banco ↔ prod (correr IGUAL en los dos; deben coincidir línea a línea).
-- Funciones por pg_get_functiondef, triggers con su estado, políticas y permisos.
with c as materialized (select set_config('search_path', 'pg_catalog', true) x)
select 'funciones' as que, n.nspname as esquema, count(*)::text as n,
  md5(string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)) as huella
from c, pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('crm','private','public') and p.prokind in ('f','p')
group by n.nspname
union all
select 'acl_funciones', n.nspname, count(*)::text,
  md5(string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text,'') || '|' || pg_get_userbyid(p.proowner), ',' order by p.oid::regprocedure::text))
from c, pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('crm','private','public') and p.prokind in ('f','p')
group by n.nspname
union all
select 'triggers', n.nspname, count(*)::text,
  md5(string_agg(cl.oid::regclass::text || '.' || t.tgname || '=' || md5(pg_get_triggerdef(t.oid)) || '|' || t.tgenabled::text, ',' order by cl.oid::regclass::text, t.tgname))
from c, pg_trigger t join pg_class cl on cl.oid = t.tgrelid join pg_namespace n on n.oid = cl.relnamespace
where not t.tgisinternal and n.nspname in ('crm','private','public')
group by n.nspname
union all
select 'politicas', schemaname, count(*)::text,
  md5(string_agg(tablename || '.' || policyname || '=' || md5(coalesce(qual,'') || '|' || coalesce(with_check,'') || '|' || cmd || '|' || permissive::text || '|' || array_to_string(roles, ',')), ',' order by tablename, policyname))
from c, pg_policies where schemaname in ('crm','private','public')
group by schemaname
union all
select 'acl_tablas', n.nspname, count(*)::text,
  md5(string_agg(cl.relname || '=' || coalesce(cl.relacl::text,'') || '|' || cl.relrowsecurity::text || '|' || cl.relforcerowsecurity::text, ',' order by cl.relname))
from c, pg_class cl join pg_namespace n on n.oid = cl.relnamespace
where n.nspname in ('crm','private','public') and cl.relkind in ('r','p','v','m')
group by n.nspname
order by 1, 2;
