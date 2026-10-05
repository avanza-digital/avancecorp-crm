-- Huella del catálogo de Llamadas desde el celular: una línea por función (cuerpo, permisos, COMMENT), columna (tipo,
-- NOT NULL, default, COMMENT), restricción, índice, trigger y tabla (RLS, permisos, COMMENT, policies) de crm y
-- private cuyo nombre lleve «llamada» o «celular». El banco reducido la toma antes de la quinta y después de su
-- reversa: tienen que coincidir línea a línea (el orden de las columnas no cuenta; lo demás, todo).
-- Uso: psql -X -qAt -f supabase/tests/llamadas-celular/huella-catalogo.sql
with tablas as (
  select c.oid, c.oid::regclass::text as t
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm', 'private') and c.relkind = 'r' and c.relname ~ '(llamada|celular)'
), lineas as (
  select 'funcion ' || p.oid::regprocedure::text || ' def=' || md5(pg_catalog.replace(pg_catalog.pg_get_functiondef(p.oid), E'\r', ''))
         || ' acl=' || coalesce(p.proacl::text, '-')
         || ' com=' || md5(coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), '-')) as l
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('crm', 'private') and p.proname ~ '(llamada|celular)'
  union all
  select 'tabla ' || t.t || ' rls=' || c.relrowsecurity || ' acl=' || coalesce(c.relacl::text, '-')
         || ' com=' || md5(coalesce(pg_catalog.obj_description(t.oid, 'pg_class'), '-'))
         || ' policies=' || (select count(*) from pg_catalog.pg_policy p where p.polrelid = t.oid)
  from tablas t join pg_catalog.pg_class c on c.oid = t.oid
  union all
  select 'columna ' || t.t || '.' || a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod)
         || ' nn=' || a.attnotnull || ' def=' || coalesce(pg_catalog.pg_get_expr(d.adbin, d.adrelid), '-')
         || ' com=' || md5(coalesce(pg_catalog.col_description(t.oid, a.attnum), '-'))
  from tablas t
  join pg_catalog.pg_attribute a on a.attrelid = t.oid and a.attnum > 0 and not a.attisdropped
  left join pg_catalog.pg_attrdef d on d.adrelid = t.oid and d.adnum = a.attnum
  union all
  select 'restriccion ' || t.t || ' ' || c.conname || ' ' || pg_catalog.pg_get_constraintdef(c.oid)
         || ' com=' || md5(coalesce(pg_catalog.obj_description(c.oid, 'pg_constraint'), '-'))
  from tablas t join pg_catalog.pg_constraint c on c.conrelid = t.oid
  union all
  select 'indice ' || pg_catalog.pg_get_indexdef(i.indexrelid)
  from tablas t join pg_catalog.pg_index i on i.indrelid = t.oid
  union all
  select 'trigger ' || pg_catalog.pg_get_triggerdef(g.oid) || ' estado=' || g.tgenabled::text
  from tablas t join pg_catalog.pg_trigger g on g.tgrelid = t.oid and not g.tgisinternal
)
select l from lineas order by l;
