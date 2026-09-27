-- Paridad de permisos banco ↔ prod. Restaurar el volcado en el stack local deja el banco MÁS
-- permisivo que producción (los privilegios por defecto del stack dan EXECUTE/ALL a anon y
-- authenticated en public) y con ACL implícitos donde prod los tiene explícitos.
--
-- 1) Correr ESTAS consultas en PRODUCCIÓN (solo lectura): devuelven el SQL a aplicar.
-- 2) Aplicar su salida en el banco dentro de un begin/commit, más el bloque fijo del final.
-- 3) Verificar con acreditar.sql y acreditar-acl-public.sql: mismas huellas en los dos lados.

-- (a) Funciones de public: dejar exactamente los EXECUTE de prod.
with c as materialized (select set_config('search_path', 'pg_catalog', true) x),
f as (
  select p.oid, p.oid::regprocedure::text as sig, p.proacl
  from c, pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind in ('f','p')
)
select string_agg(
  'revoke all on function ' || f.sig || ' from public, anon, authenticated, service_role;' ||
  coalesce((select string_agg(' grant execute on function ' || f.sig || ' to ' ||
      case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end || ';', '' order by a.grantee)
    from aclexplode(f.proacl) a
    where a.privilege_type = 'EXECUTE' and a.grantee <> (select proowner from pg_proc where oid = f.oid)), ''),
  E'\n' order by f.sig) as sql_funciones
from f;

-- (b) Tablas de crm/private con ACL explícito solo del dueño en prod: materializarlo igual.
with c as materialized (select set_config('search_path', 'pg_catalog', true) x)
select string_agg('revoke all on table ' || cl.oid::regclass::text || ' from public;', ' ' order by cl.oid::regclass::text)
from c, pg_class cl join pg_namespace n on n.oid = cl.relnamespace
where n.nspname in ('crm','private') and cl.relkind in ('r','p','v','m')
  and regexp_replace(cl.relacl::text, '/[^,}]+', '', 'g') = '{postgres=arwdDxtm}';

-- (c) Bloque fijo (medido el 23/09; revisar si cambia):
--   revoke truncate, references, trigger, maintain on all tables in schema public from anon, authenticated;
--   grant execute on function private.gestion_diaria_avisos(timestamptz),
--     private.gestion_diaria_avisos_con_contexto(timestamptz) to postgres;
