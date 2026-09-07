-- Censo real F6.a (cuerpo contrastado con produccion). No suplanta assert_analitica.
create table private.analitica_leads_citas_exenciones(objeto text primary key,huella text);
create or replace function private.contadores_crudos_leads_citas()
returns table (tipo text, objeto text, declarada boolean, huella_ok boolean)
language sql
stable
security definer
set search_path to ''
as $function$
  with fn as (
    -- TODOS los esquemas de usuario (fail-closed: lo del sistema se excluye por
    -- lista, no al reves - un esquema nuevo entra al censo solo); el cuerpo
    -- viene de prosrc O de pg_get_functiondef (funciones con prosqlbody);
    -- la exclusion de los nucleos y de las piezas del trinquete es por
    -- IDENTIDAD exacta, no por nombre (un overload malicioso no se cuela).
    select 'funcion'::text as tipo,
           p.oid::regprocedure::text as objeto,
           regexp_replace(regexp_replace(
             lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
             '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g') as cuerpo
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where p.prokind in ('f','p')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
       and p.oid not in (
             coalesce(to_regprocedure('private.citas_episodios(timestamptz,timestamptz,timestamptz)')::oid, 0),
             coalesce(to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')::oid, 0),
             coalesce(to_regprocedure('private.contadores_crudos_leads_citas()')::oid, 0),
             coalesce(to_regprocedure('private.assert_analitica_leads_citas()')::oid, 0))
  ),
  vw as (
    select 'vista'::text,
           c.relnamespace::regnamespace::text || '.' || c.relname,
           lower(pg_get_viewdef(c.oid))
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind in ('v','m')
       and n.nspname not in ('pg_catalog','information_schema','pg_toast',
                             'auth','storage','vault','realtime','extensions',
                             'graphql','graphql_public','pgbouncer','net',
                             'supabase_functions','supabase_migrations','cron','pgsodium')
       and n.nspname not like 'pg\_%'
  ),
  todo as (select * from fn union all select * from vw),
  crudos as (
    -- Insensible a mayusculas (el cuerpo va en lower), tolera espacio tras el
    -- punto (un comentario borrado deja hueco: `crm. leads`), y caza tambien
    -- `sum(` ademas de `count(`. El SQL dinamico que nombre leads/tareas se
    -- censa entero: si su conteo no es demostrable, se declara.
    select t.tipo, t.objeto, md5(t.cuerpo) as huella
      from todo t
     where (t.cuerpo ~ '\mcrm\.\s*leads\M'
            or t.cuerpo ~ '\mreunion'
            or (t.cuerpo ~ '\mcrm\.\s*tareas\M' and t.cuerpo ~ '\mexecute\M'))
       and (t.cuerpo ~ '\mcount\s*\(' or t.cuerpo ~ '\msum\s*\(\s*1\s*\)')
  )
  select cr.tipo,
         cr.objeto,
         (e.objeto is not null) as declarada,
         (e.objeto is not null and e.huella = cr.huella) as huella_ok
    from crudos cr
    left join private.analitica_leads_citas_exenciones e on e.objeto = cr.objeto
   order by 3, 4, 1, 2;
$function$;
