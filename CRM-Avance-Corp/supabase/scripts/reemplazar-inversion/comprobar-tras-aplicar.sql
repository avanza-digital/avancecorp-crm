-- Comprobación de 20261017162053 (reemplazar inversión) DESPUÉS de aplicarla. SOLO LECTURA de catálogo y censo; termina
-- SIEMPRE en ROLLBACK. Veredicto en una fila. Uso:
--   supabase db query --linked --file supabase/scripts/reemplazar-inversion/comprobar-tras-aplicar.sql
-- Las huellas son md5(pg_get_functiondef) con search_path vacío (cambian con el search_path: por eso el `set local`).
begin;
set local search_path = '';
with
huellas as (
  select
    md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure)) = '1606e0a61a83f80a7873d7fafe7c4faa'
    and md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)) = '541ce30ffcc213adaebc036dda48a6a2'
    and md5(pg_catalog.pg_get_functiondef('private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure)) = '6071a4b804a177e3f0487e32d9859971'
    and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure)) = '755b35a2b92b4d46cf6e7294d6d77ea9'
    and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)) = '3a055eeabb9a0b96981ff910c33354d5'
    -- Lo que la migración llama y no cambia: tiene que seguir como en su preflight.
    and md5(pg_catalog.pg_get_functiondef('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure)) = 'c954f109757ccfa18692d0bff54f903c'
    and md5(pg_catalog.pg_get_functiondef('private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure)) = '872930922a1d477e27b23243cbfe691a'
    and md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) = 'df71c2b1e3cd44b97c3ad84e00637266' as ok
),
observador as (
  select count(*) = 1 as ok from pg_catalog.pg_proc p
  where p.oid = 'private.trg_contratos_observar_rentabilidad()'::regprocedure and p.prosecdef and p.provolatile = 'v'
    and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""', 'lock_timeout=2s']
    and p.proacl = '{postgres=X/postgres}'::aclitem[]
),
puertas as (
  select count(*) = 2 as ok from pg_catalog.pg_proc p
  where p.oid in ('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure,
                  'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)
    and p.prosecdef and p.proowner = 'postgres'::regrole and 'search_path=""' = any (p.proconfig)
    and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    and not exists (select 1 from pg_catalog.aclexplode(p.proacl) a where a.grantee = 0)
),
nucleo as (
  select count(*) = 0 as ok from pg_catalog.pg_proc p cross join unnest(array['anon','authenticated','service_role']) r(rol)
  where p.oid in ('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                  'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)'::regprocedure)
    and (pg_catalog.has_function_privilege(r.rol, p.oid, 'EXECUTE') or p.prosecdef)
),
copia as (
  select c.relrowsecurity and not exists (select 1 from pg_catalog.pg_policy x where x.polrelid = c.oid)
    and not pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT')
    and not pg_catalog.has_table_privilege('service_role', c.oid, 'SELECT')
    and exists (select 1 from pg_catalog.pg_attribute a where a.attrelid = c.oid and a.attname = 'reemplazada_por' and not a.attisdropped)
    and exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = c.oid and k.conname = 'inversiones_eliminadas_reemplazo_check')
    and (select count(*) from pg_catalog.pg_trigger t where t.tgrelid = c.oid and t.tgenabled = 'O'
         and t.tgname in ('trg_inversiones_eliminadas_inmutables', 'trg_inversiones_eliminadas_no_truncate', 'trg_audit_inversiones_eliminadas')) = 3 as ok
  from pg_catalog.pg_class c where c.oid = 'crm.inversiones_eliminadas'::regclass
),
censo as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c
  where c.objeto like '%reemplazar_inversion%' or c.objeto like '%inversion_reemplazada%'
),
vigia as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c where not (c.declarada and c.huella_ok)
)
-- vigia_sin_pendientes es INFORMATIVO: puede haber pendientes ajenos de antes; lo propio lo juzga fuera_del_censo.
select case when h.ok and o.ok and p.ok and n.ok and co.ok and ce.ok
            and private.inversion_eliminacion_dependencias_conocidas() then 'APTA' else 'NO APTA' end as veredicto,
  h.ok as huellas, o.ok as observador, p.ok as puertas, n.ok as nucleo_cerrado, co.ok as copia_privada, ce.ok as fuera_del_censo,
  v.ok as vigia_sin_pendientes,
  private.inversion_eliminacion_dependencias_conocidas() as dependencias_conocidas
from huellas h, observador o, puertas p, nucleo n, copia co, censo ce, vigia v;
rollback;
