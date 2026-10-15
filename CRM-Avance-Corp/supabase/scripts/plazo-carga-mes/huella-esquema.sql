-- Huella del esquema que toca 20261015000852_crm_plazo_carga_mes (SOLO LECTURA). Sirve para acreditar que la reversa deja
-- el esquema como estaba: se corre ANTES de la migración y DESPUÉS de reversa.sql, y las dos salidas tienen que ser iguales.
-- Por objeto: md5 de pg_get_functiondef (con search_path vacío) + dueño + ACL + comentario; CHECK, triggers y tablas.
set search_path = '';
select 'funciones crm+private' as pieza,
       pg_catalog.count(*)::text || ' | ' || pg_catalog.md5(pg_catalog.string_agg(
         pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) || p.proowner::regrole::text || coalesce(p.proacl::text, 'NULL')
           || coalesce(pg_catalog.obj_description(p.oid, 'pg_proc'), 'NULL') || p.provolatile::text,
         ',' order by p.oid::regprocedure::text)) as huella
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
 where n.nspname in ('crm', 'private') and p.prokind = 'f'
union all
select 'checks conversion_acreditaciones',
       pg_catalog.string_agg(c.conname || '=' || pg_catalog.pg_get_constraintdef(c.oid) || '#' || coalesce(pg_catalog.obj_description(c.oid, 'pg_constraint'), 'NULL'), ' ; ' order by c.conname)
  from pg_catalog.pg_constraint c where c.conrelid = 'crm.conversion_acreditaciones'::regclass
union all
select 'triggers del cierre',
       pg_catalog.string_agg(t.tgrelid::regclass::text || '.' || t.tgname || '=' || t.tgenabled::text || '#' || t.tgfoid::regprocedure::text, ' ; ' order by t.tgrelid::regclass::text, t.tgname)
  from pg_catalog.pg_trigger t
 where not t.tgisinternal and t.tgrelid in ('crm.periodos_cerrados'::regclass, 'crm.cierre_mes_vendedor'::regclass,
       'crm.inversion_ajustes_mes_cerrado'::regclass, 'crm.cierres_externos'::regclass, 'crm.conversion_acreditaciones'::regclass)
union all
select 'tablas crm', pg_catalog.count(*)::text || ' | ' || pg_catalog.md5(pg_catalog.string_agg(c.relname, ',' order by c.relname))
  from pg_catalog.pg_class c where c.relnamespace = 'crm'::regnamespace and c.relkind in ('r', 'p')
union all
select 'funciones con plazo', pg_catalog.string_agg(p.oid::regprocedure::text || '=' || p.provolatile::text, ' ; ' order by p.oid::regprocedure::text)
  from pg_catalog.pg_proc p
 where p.oid in ('private.conversion_plazo_hasta(date)'::regprocedure, 'private.cierre_mes_ventana_desde(date)'::regprocedure,
                 'private.conversion_decidir_plazo(date,timestamptz,timestamptz,timestamptz)'::regprocedure)
order by 1;
