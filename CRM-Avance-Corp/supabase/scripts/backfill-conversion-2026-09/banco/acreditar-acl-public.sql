-- Permisos de las funciones de public, sin depender del orden de las entradas del ACL.
-- En el banco, restaurar un volcado deja public MÁS permisivo que prod (privilegios por defecto del
-- stack local): hay que regenerar desde prod los revoke/grant y aplicarlos (ver LEEME §5).
with c as materialized (select set_config('search_path', 'pg_catalog', true) x)
select count(*), md5(string_agg(sig || '=' || acl, ',' order by sig)) from (
  select p.oid::regprocedure::text sig,
    coalesce((select string_agg(case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end || ':' || a.privilege_type, ';' order by case when a.grantee = 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end, a.privilege_type)
              from aclexplode(p.proacl) a), 'NULL') acl
  from c, pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f','p')) z;
