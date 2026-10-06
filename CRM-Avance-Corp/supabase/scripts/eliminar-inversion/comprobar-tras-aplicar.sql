-- Comprobación de 20261005200945 (eliminar inversión) DESPUÉS de aplicarla. SOLO LECTURA de catálogo y censo; termina SIEMPRE
-- en ROLLBACK. Veredicto en una fila. Uso: supabase db query --linked --file supabase/scripts/eliminar-inversion/comprobar-tras-aplicar.sql
begin;
set local search_path = '';
with
huellas as (
  select
    md5(pg_catalog.pg_get_functiondef('private.trg_cierres_externos_inmutables()'::regprocedure)) = '34fd3c383e636353038acca2b42e0535'
    and md5(pg_catalog.pg_get_functiondef('private.trg_depositos_reclamados_append_only()'::regprocedure)) = '0d7eb68419c9c31bd42552b5d08d45a4'
    and md5(pg_catalog.pg_get_functiondef('private.f4_fuente_inmutable()'::regprocedure)) = '808b1ac3481ee180f5060bd4e0bc6fa1'
    and md5(pg_catalog.pg_get_functiondef('private.cierre_anulado(uuid)'::regprocedure)) = 'df71c2b1e3cd44b97c3ad84e00637266'
    and md5(pg_catalog.pg_get_functiondef('private.conversion_bloquear_retiro_trg()'::regprocedure)) = '823bf82cc20e4e4ca95381e4ce683ea1'
    and md5(pg_catalog.pg_get_functiondef('private.leads_before_update()'::regprocedure)) = '4ae909f2d56ca650b5595b505e6aa51d'
    and md5(pg_catalog.pg_get_functiondef('crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure)) = 'c954f109757ccfa18692d0bff54f903c' as ok
),
puerta as (
  select count(*) = 1 as ok from pg_catalog.pg_proc p
  where p.oid = 'crm.eliminar_inversion_fn(uuid,text)'::regprocedure and p.prosecdef
    and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
    and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
),
nucleo as (
  select count(*) = 0 as ok from pg_catalog.pg_proc p cross join unnest(array['anon','authenticated','service_role']) r(rol)
  where p.pronamespace = 'private'::regnamespace
    and p.proname in ('inversion_eliminacion_autoriza', 'eliminar_inversion_cooperativa', 'registrar_inversion_eliminada_avance',
      'eliminar_inversion_contexto', 'eliminar_inversion_roles', 'inversion_motivo_no_eliminable', 'conversion_coordinar_retiro_fuente',
      'inversion_eliminacion_dependencias_conocidas', 'proteger_inversion_eliminada', 'motivo_normalizado')
    and pg_catalog.has_function_privilege(r.rol, p.oid, 'EXECUTE')
),
copia as (
  select c.relrowsecurity and not exists (select 1 from pg_catalog.pg_policy x where x.polrelid = c.oid)
    and not pg_catalog.has_table_privilege('authenticated', c.oid, 'SELECT')
    and not pg_catalog.has_table_privilege('service_role', c.oid, 'SELECT') as ok
  from pg_catalog.pg_class c where c.oid = 'crm.inversiones_eliminadas'::regclass
),
candados as (
  select count(*) = 6 as ok from pg_catalog.pg_trigger t
  where t.tgenabled = 'O' and (
    (t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_cierres_externos_00_inmutables')
    or (t.tgrelid = 'crm.depositos_reclamados'::regclass and t.tgname = 'trg_depositos_reclamados_00_append_only')
    or (t.tgrelid = 'crm.inversion_eventos'::regclass and t.tgname = 'trg_inversion_eventos_inmutables')
    or (t.tgrelid = 'crm.inversiones_eliminadas'::regclass
        and t.tgname in ('trg_inversiones_eliminadas_inmutables', 'trg_inversiones_eliminadas_no_truncate', 'trg_audit_inversiones_eliminadas')))
),
censo as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c
  where c.objeto like '%eliminar_inversion%' or c.objeto like '%conversion_coordinar_retiro_fuente%'
     or c.objeto like '%inversion_eliminacion%' or c.objeto like '%inversion_motivo_no_eliminable%'
),
vigia as (
  select count(*) = 0 as ok from private.contadores_crudos_leads_citas() c where not (c.declarada and c.huella_ok)
)
-- vigia_sin_pendientes es INFORMATIVO: puede haber pendientes ajenos de antes; lo propio lo juzga fuera_del_censo.
select case when h.ok and p.ok and n.ok and co.ok and ca.ok and ce.ok then 'APTA' else 'NO APTA' end as veredicto,
  h.ok as huellas, p.ok as puerta, n.ok as nucleo_cerrado, co.ok as copia_privada, ca.ok as candados, ce.ok as fuera_del_censo,
  v.ok as vigia_sin_pendientes,
  private.inversion_eliminacion_dependencias_conocidas() as dependencias_conocidas
from huellas h, puerta p, nucleo n, copia co, candados ca, censo ce, vigia v;
rollback;
