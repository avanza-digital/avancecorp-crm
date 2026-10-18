-- Comprobación de 20261017211313 (vista previa del mes del reemplazo) DESPUÉS de aplicarla. SOLO LECTURA de catálogo y censo;
-- termina SIEMPRE en ROLLBACK. Veredicto en una fila. Uso:
--   supabase db query --linked --file supabase/scripts/reemplazar-inversion-vista-previa/comprobar-tras-aplicar.sql
-- Ojo: tras esta migración, la comprobación de la Fase 1 (reemplazar-inversion/comprobar-tras-aplicar.sql) da NO APTA en
-- «huellas» a propósito: el núcleo cambió. Esta es la que vale desde aquí.
begin;
set local search_path = '';
with
huellas as (
  select
    md5(pg_catalog.pg_get_functiondef('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure)) = 'b6af7422802edc85ced40d6b9cc26e49'
    and md5(pg_catalog.pg_get_functiondef('private.reemplazo_dia_registro_venta(uuid)'::regprocedure)) = '3f78ec3e1114ba2c353246bab6cf4031'
    and md5(pg_catalog.pg_get_functiondef('private.reemplazo_fecha_comercial(uuid,date)'::regprocedure)) = 'eaaba0422ce0abde5bcecefcfc23f85e'
    and md5(pg_catalog.pg_get_functiondef('private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure)) = 'b92e6bbf1fe46c49b2482c0ad8eb3b3e'
    and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure)) = '093aec4bed9f3fdfab9b1958a0939947'
    -- Lo de la Fase 1 que esta migración no toca.
    and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)'::regprocedure)) = '755b35a2b92b4d46cf6e7294d6d77ea9'
    and md5(pg_catalog.pg_get_functiondef('crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)'::regprocedure)) = '3a055eeabb9a0b96981ff910c33354d5'
    and md5(pg_catalog.pg_get_functiondef('private.trg_contratos_observar_rentabilidad()'::regprocedure)) = '1606e0a61a83f80a7873d7fafe7c4faa' as ok
),
puerta as (
  select count(*) = 1 as ok from pg_catalog.pg_proc p
  where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure
    and p.prosecdef and p.proowner = 'postgres'::regrole and p.provolatile = 'v' and 'search_path=""' = any (p.proconfig)
    and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    and not exists (select 1 from pg_catalog.aclexplode(p.proacl) a where a.grantee = 0)
),
nucleo as (
  select count(*) = 0 as ok from pg_catalog.pg_proc p cross join unnest(array['anon','authenticated','service_role']) r(rol)
  where p.oid in ('private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure,
                  'private.reemplazo_dia_registro_venta(uuid)'::regprocedure,
                  'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure,
                  'private.contrato_tiene_cuotas_pagadas(uuid)'::regprocedure)
    and (pg_catalog.has_function_privilege(r.rol, p.oid, 'EXECUTE') or p.prosecdef)
),
censo as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c
  where position('reemplazar_inversion' in c.objeto) > 0 or position('reemplazo_' in c.objeto) > 0
     or position('contrato_tiene_cuotas_pagadas' in c.objeto) > 0
),
vigia as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c where not (c.declarada and c.huella_ok)
)
-- vigia_sin_pendientes es INFORMATIVO: puede haber pendientes ajenos de antes; lo propio lo juzga fuera_del_censo.
select case when h.ok and p.ok and n.ok and ce.ok then 'APTA' else 'NO APTA' end as veredicto,
  h.ok as huellas, p.ok as puerta, n.ok as nucleo_cerrado, ce.ok as fuera_del_censo, v.ok as vigia_sin_pendientes
from huellas h, puerta p, nucleo n, censo ce, vigia v;
rollback;
