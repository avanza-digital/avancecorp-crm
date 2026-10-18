-- Comprobación de 20261018053228 (Reemplazar inversión, cooperativas) DESPUÉS de aplicarla. SOLO LECTURA; termina SIEMPRE en
-- ROLLBACK. Veredicto en una fila. Uso:
--   supabase db query --linked --file supabase/scripts/reemplazar-inversion-cooperativa/comprobar-tras-aplicar.sql
begin read only;
set local search_path = '';
with
bucket as (
  select (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
          from pg_catalog.pg_proc p
          where p.oid in ('private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure))
         = 'private.f4_comprobante_autorizado(text)=cdecad21e77c38d023ba156efd8faa74,'
           'private.f4_comprobante_visible(text)=d5e74abf371a35c677d42da9abb2ff82' as ok
),
funciones as (
  select to_regprocedure('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)') is not null
     and to_regprocedure('crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)') is not null
     and to_regprocedure('private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)') is not null
     and to_regprocedure('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)') is not null
     and to_regprocedure('private.f4_comprobante_reemplazo_autorizado(text)') is not null as ok
),
permisos as (
  select not exists (select 1 from pg_catalog.pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where p.oid in ('private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)'::regprocedure,
                                     'private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)'::regprocedure)
                       and pg_catalog.has_function_privilege(r.rol, p.oid, 'execute'))
     and (select count(*) from pg_catalog.pg_proc p
          where p.oid in ('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)'::regprocedure,
                          'crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)'::regprocedure,
                          'private.f4_comprobante_reemplazo_autorizado(text)'::regprocedure,
                          'private.f4_comprobante_autorizado(text)'::regprocedure, 'private.f4_comprobante_visible(text)'::regprocedure)
            and p.prosecdef and p.proowner = 'postgres'::regrole and 'search_path=""' = any (p.proconfig)
            and pg_catalog.has_function_privilege('authenticated', p.oid, 'execute')
            and not pg_catalog.has_function_privilege('anon', p.oid, 'execute')
            and not pg_catalog.has_function_privilege('service_role', p.oid, 'execute')) = 5 as ok
)
select case when b.ok and f.ok and p.ok then 'APTA' else 'NO APTA' end as veredicto,
  b.ok as bucket, f.ok as funciones, p.ok as permisos,
  (select count(*) from crm.inversiones_eliminadas e where e.fuente_tipo = 'cierre_externo' and e.reemplazada_por is not null) as reemplazos_hechos
from bucket b, funciones f, permisos p;
rollback;
