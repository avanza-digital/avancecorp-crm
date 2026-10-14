-- SOLO preparación de atencion_http en el contenedor propio; NO es migración.
\set ON_ERROR_STOP on
do $$ begin
 if current_database()<>'atencion_http' then raise exception 'Solo base HTTP local';end if;
end $$;
alter database atencion_http owner to postgres;
alter schema crm owner to postgres;
alter schema private owner to postgres;
do $$ declare r record;begin
 if current_database()<>'atencion_http' then raise exception 'Solo base HTTP local';end if;
 for r in select p.oid::regprocedure identidad from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname in ('public','crm','private') and p.prokind='f' loop
 execute format('alter function %s owner to postgres',r.identidad);end loop;
 for r in select c.oid::regclass identidad from pg_class c join pg_namespace n on n.oid=c.relnamespace
 where n.nspname in ('public','crm','private') and c.relkind in ('r','p','v','m') loop
 execute format('alter %s %s owner to postgres',case when (select relkind from pg_class where oid=r.identidad)='S' then 'sequence' else 'table' end,r.identidad);end loop;
end $$;
-- Cuerpo exacto auth.uid() de producción, 13/10/2026. La imagen antigua solo
-- leía request.jwt.claim.sub; PostgREST 14 envía request.jwt.claims.
create or replace function auth.uid() returns uuid language sql stable as $$
 select coalesce(nullif(current_setting('request.jwt.claim.sub',true),''),
 (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub'))::uuid;
$$;
grant all on auth.users to postgres;
alter role authenticator password 'solo-banco-atencion';
grant usage on schema crm to authenticator;
