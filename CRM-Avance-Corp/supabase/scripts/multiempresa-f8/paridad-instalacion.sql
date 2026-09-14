-- Inventario estructural F8; sin datos de negocio ni cuerpos de funciones en
-- la salida. Ejecutar igual en padre/rama. No excluye diferencias automáticamente.
-- Sin BEGIN: el ejecutor debe incluirlo en su transacción READ ONLY de captura.
with objetos as (
  -- Forzar text: el tipo name del catálogo truncaría las claves de las demás
  -- ramas UNION a 63 bytes, ocultando sobrecargas y columnas con nombres largos.
  select 'esquemas' as categoria,n.nspname::text as clave,
    jsonb_build_array(n.nspowner::regrole::text,n.nspacl::text,
      obj_description(n.oid,'pg_namespace')) as valor
  from pg_namespace n where n.nspname in ('public','crm','private')
  union all
  select 'relaciones',n.nspname||'.'||c.relname,
    jsonb_build_array(c.relkind,c.relowner::regrole::text,c.relacl::text,
      c.relrowsecurity,c.relforcerowsecurity,c.relreplident,c.relpersistence,
      c.reloptions,c.relispartition,
      case when c.relispartition then pg_get_expr(c.relpartbound,c.oid) end,
      case when c.relkind='p' then pg_get_partkeydef(c.oid) end,
      obj_description(c.oid,'pg_class'))
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','crm','private')
  union all
  select 'columnas',n.nspname||'.'||c.relname||'.'||a.attname,
    jsonb_build_array(a.attnum,format_type(a.atttypid,a.atttypmod),a.attnotnull,
      a.attidentity,a.attgenerated,a.attacl::text,
      pg_get_expr(d.adbin,d.adrelid),a.attcollation::regcollation::text,
      col_description(c.oid,a.attnum))
  from pg_attribute a join pg_class c on c.oid=a.attrelid
  join pg_namespace n on n.oid=c.relnamespace
  left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
  where n.nspname in ('public','crm','private') and a.attnum>0 and not a.attisdropped
  union all
  select 'funciones',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
    jsonb_build_array(pg_get_functiondef(p.oid),p.proowner::regrole::text,
      p.proacl::text,p.proconfig,obj_description(p.oid,'pg_proc'))
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('public','crm','private') and p.prokind in ('f','p')
  union all
  select 'triggers',n.nspname||'.'||c.relname||'.'||t.tgname,
    jsonb_build_array(pg_get_triggerdef(t.oid),t.tgenabled)
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  -- Incluye triggers de usuario sobre tablas administradas (p. ej. auth.users).
  where not t.tgisinternal
  union all
  select 'politicas',schemaname||'.'||tablename||'.'||policyname,
    jsonb_build_array(permissive,roles,cmd,qual,with_check)
  from pg_policies where schemaname in ('public','crm','private','auth','storage')
  union all
  select 'constraints',n.nspname||'.'||co.conname||':'||co.conrelid::regclass::text||':'||co.contypid::regtype::text,
    jsonb_build_array(pg_get_constraintdef(co.oid),co.convalidated,co.condeferrable,co.condeferred)
  from pg_constraint co join pg_namespace n on n.oid=co.connamespace
  where n.nspname in ('public','crm','private')
  union all
  select 'indices',n.nspname||'.'||c.relname,
    jsonb_build_array(pg_get_indexdef(i.indexrelid),i.indisvalid,i.indisready)
  from pg_index i join pg_class c on c.oid=i.indexrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','crm','private')
  union all
  select 'vistas',n.nspname||'.'||c.relname,
    jsonb_build_array(pg_get_viewdef(c.oid,true),c.reloptions,c.relowner::regrole::text)
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','crm','private') and c.relkind in ('v','m')
  union all
  select 'default_acl',a.defaclrole::regrole::text||':'||coalesce(n.nspname,'GLOBAL')||':'||a.defaclobjtype::text,
    to_jsonb(a.defaclacl::text)
  from pg_default_acl a left join pg_namespace n on n.oid=a.defaclnamespace
  where a.defaclnamespace=0 or n.nspname in ('public','crm','private')
  union all
  select 'tipos',n.nspname||'.'||t.typname,
    jsonb_build_array(t.typtype,t.typcategory,t.typowner::regrole::text,
      t.typacl::text,format_type(t.typbasetype,t.typtypmod),t.typnotnull,t.typdefault,
      t.typinput::regprocedure::text,t.typoutput::regprocedure::text,
      t.typcollation::regcollation::text,
      (select jsonb_agg(jsonb_build_array(e.enumsortorder,e.enumlabel) order by e.enumsortorder)
        from pg_enum e where e.enumtypid=t.oid))
  from pg_type t join pg_namespace n on n.oid=t.typnamespace
  where n.nspname in ('public','crm','private')
  union all
  select 'secuencias',n.nspname||'.'||c.relname,
    jsonb_build_array(format_type(s.seqtypid,null),s.seqstart,s.seqincrement,
      s.seqmax,s.seqmin,s.seqcache,s.seqcycle,
      (select jsonb_agg(jsonb_build_array(d.deptype,d.refobjid::regclass::text,a.attname)
        order by d.refobjid::regclass::text,a.attname,d.deptype)
        from pg_depend d left join pg_attribute a
          on a.attrelid=d.refobjid and a.attnum=d.refobjsubid
        where d.classid='pg_class'::regclass and d.objid=c.oid
          and d.refclassid='pg_class'::regclass and d.deptype in ('a','i')))
  from pg_sequence s join pg_class c on c.oid=s.seqrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in ('public','crm','private')
  union all
  select 'extensiones',e.extname,
    jsonb_build_array(e.extversion,n.nspname,e.extowner::regrole::text,e.extrelocatable)
  from pg_extension e join pg_namespace n on n.oid=e.extnamespace
  union all
  select 'publicaciones',p.pubname,
    jsonb_build_array(p.pubowner::regrole::text,p.puballtables,p.pubinsert,p.pubupdate,
      p.pubdelete,p.pubtruncate,p.pubviaroot,
      (select jsonb_agg(jsonb_build_array(t.schemaname,t.tablename,t.attnames,t.rowfilter)
        order by t.schemaname,t.tablename) from pg_publication_tables t where t.pubname=p.pubname),
      (select jsonb_agg(n.nspname order by n.nspname) from pg_publication_namespace pn
        join pg_namespace n on n.oid=pn.pnnspid where pn.pnpubid=p.oid))
  from pg_publication p
  union all
  select 'event_triggers',e.evtname,
    jsonb_build_array(e.evtevent,e.evtowner::regrole::text,e.evtfoid::regprocedure::text,
      e.evtenabled,e.evttags)
  from pg_event_trigger e
), categorias as (
  select unnest(array['esquemas','relaciones','columnas','funciones','triggers',
    'politicas','constraints','indices','vistas','default_acl','tipos','secuencias',
    'extensiones','publicaciones','event_triggers']) as categoria
), resumen as (
  select c.categoria,count(o.clave)::integer as n,
    md5(coalesce(string_agg(o.clave||':'||o.valor::text,E'\n' order by o.clave),'')) as md5
  from categorias c left join objetos o using(categoria) group by c.categoria
)
select jsonb_agg(r order by categoria) as paridad from resumen r;
