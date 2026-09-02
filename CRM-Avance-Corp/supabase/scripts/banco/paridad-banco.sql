-- ---------------------------------------------------------------------------
-- PARIDAD BANCO ↔ PRODUCCION
--
-- Se corre IGUAL en los dos lados y se comparan las huellas linea a linea.
-- Cada fila es una CATEGORIA de objeto: si la huella coincide, esa categoria
-- es identica al ultimo byte; si no, hay que bajar al detalle.
--
-- Solo mira ESTRUCTURA (nunca datos): el banco tiene semilla propia y sus
-- filas no son comparables. Se excluye lo que la plataforma crea por su
-- cuenta y lo que es intrinsecamente local (OIDs, `supabase_migrations`).
-- ---------------------------------------------------------------------------
with
esquemas as (select unnest(array['crm','public','private']) as n),

-- 1. Tablas y sus columnas (tipo, nulabilidad y default)
cols as (
  select c.table_schema||'.'||c.table_name||'.'||c.column_name||' :: '||
         c.data_type||' null='||c.is_nullable||' def='||coalesce(c.column_default,'-') as linea
  from information_schema.columns c
  join esquemas e on e.n = c.table_schema
),

-- 2. Funciones: cuerpo completo, dueño, comentario y permisos efectivos
fns as (
  select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '||
         md5(pg_get_functiondef(p.oid))||' owner='||p.proowner::regrole::text||
         ' com='||coalesce(md5(obj_description(p.oid,'pg_proc')),'-')||
         ' acl='||coalesce((select string_agg(a.grantee::regrole::text||':'||a.privilege_type, ','
                              order by a.grantee::regrole::text, a.privilege_type)
                            from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a),'-') as linea
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  join esquemas e on e.n = n.nspname
),

-- 3. Disparadores: la definicion ENTERA (el WHEN y el UPDATE OF viven ahi)
trgs as (
  select n.nspname||'.'||c.relname||'.'||t.tgname||' '||md5(pg_get_triggerdef(t.oid)) as linea
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  join esquemas e on e.n = n.nspname
  where not t.tgisinternal
),

-- 4. Politicas de RLS
pols as (
  select schemaname||'.'||tablename||'.'||policyname||' '||cmd||' roles='||roles::text||
         ' using='||coalesce(md5(qual),'-')||' check='||coalesce(md5(with_check),'-') as linea
  from pg_policies join esquemas e on e.n = schemaname
),

-- 5. RLS encendida o apagada por tabla
rls as (
  select n.nspname||'.'||c.relname||' rls='||c.relrowsecurity::text||
         ' forzada='||c.relforcerowsecurity::text as linea
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join esquemas e on e.n = n.nspname
  where c.relkind in ('r','p')
),

-- 6. Indices
idx as (
  select schemaname||'.'||tablename||'.'||indexname||' '||md5(indexdef) as linea
  from pg_indexes join esquemas e on e.n = schemaname
),

-- 7. Restricciones (CHECK, FK, UNIQUE, PK)
cons as (
  select n.nspname||'.'||rel.relname||'.'||con.conname||' '||md5(pg_get_constraintdef(con.oid)) as linea
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace n on n.oid = rel.relnamespace
  join esquemas e on e.n = n.nspname
),

-- 8. El REGISTRO de migraciones: mismo conjunto y mismo texto
regs as (
  select version||' '||name||' '||md5(array_to_string(statements, E';\n')) as linea
  from supabase_migrations.schema_migrations
),

-- 9. Vistas y vistas materializadas
vis as (
  select n.nspname||'.'||c.relname||' '||md5(pg_get_viewdef(c.oid, true)) as linea
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join esquemas e on e.n = n.nspname
  where c.relkind in ('v','m')
),

todo as (
  select '1. columnas'    as categoria, linea from cols
  union all select '2. funciones',      linea from fns
  union all select '3. disparadores',   linea from trgs
  union all select '4. politicas RLS',  linea from pols
  union all select '5. RLS por tabla',  linea from rls
  union all select '6. indices',        linea from idx
  union all select '7. restricciones',  linea from cons
  union all select '8. registro',       linea from regs
  union all select '9. vistas',         linea from vis
)
select categoria,
       count(*) as n,
       md5(string_agg(linea, E'\n' order by linea)) as huella
from todo
group by categoria
order by categoria;
