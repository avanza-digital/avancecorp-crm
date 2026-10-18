-- Comprobación de 20261018032400 (recuperar ventas recargadas) DESPUÉS de aplicarla. SOLO LECTURA; termina SIEMPRE en
-- ROLLBACK. Veredicto en una fila. Uso:
--   supabase db query --linked --file supabase/scripts/recuperar-ventas-recargadas/comprobar-tras-aplicar.sql
-- Ojo: desde esta migración, las comprobaciones que fijan la huella vieja de private.cierre_anulado (df71c2b1…) dan
-- deriva a propósito (p. ej. las de eliminar-inversion y reemplazar-inversion): vale la de aquí.
begin read only;
set local search_path = '';
with
huellas as (
  select (select pg_catalog.string_agg(p.oid::regprocedure::text || '=' || md5(pg_catalog.pg_get_functiondef(p.oid)), ',' order by p.oid::regprocedure::text)
          from pg_catalog.pg_proc p
          where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'crm.cierres_estado_fn(uuid[])'::regprocedure,
                          'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure, 'crm.anular_cierre_avance(uuid,text)'::regprocedure))
         = 'crm.altas_nuevas_por_analista_fn(integer)=7136e6ea0786ae7ec166a7957f6e77d2,'
           'crm.anular_cierre_avance(uuid,text)=9625124158f7d2d04a2a59c4be405942,'
           'crm.cierres_estado_fn(uuid[])=965b778f15e64d3b5f41b257d6469ec8,'
           'private.cierre_anulado(uuid)=878d19fffc19bc39649a5105bd51b082' as ok
),
tabla as (
  select exists (select 1 from pg_catalog.pg_class c where c.oid = 'crm.conversion_ventas_recuperadas'::regclass
                 and c.relrowsecurity and c.relowner = 'postgres'::regrole)
     and not exists (select 1 from pg_catalog.pg_policy po where po.polrelid = 'crm.conversion_ventas_recuperadas'::regclass)
     and not pg_catalog.has_table_privilege('authenticated', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     and not pg_catalog.has_table_privilege('anon', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     and not pg_catalog.has_table_privilege('service_role', 'crm.conversion_ventas_recuperadas', 'select, insert, update, delete, truncate, references, trigger')
     -- Los cuatro triggers, habilitados y con su función.
     and (select count(*) from pg_catalog.pg_trigger t
          where t.tgrelid = 'crm.conversion_ventas_recuperadas'::regclass and not t.tgisinternal and t.tgenabled = 'O'
            and (t.tgname, t.tgfoid) in (
              ('trg_conversion_ventas_recuperadas_00_validar', 'private.validar_venta_recuperada()'::regprocedure::oid),
              ('trg_conversion_ventas_recuperadas_inmutables', 'private.proteger_venta_recuperada()'::regprocedure::oid),
              ('trg_conversion_ventas_recuperadas_no_truncate', 'private.proteger_venta_recuperada()'::regprocedure::oid),
              ('trg_audit_conversion_ventas_recuperadas', 'private.log_audit_crm()'::regprocedure::oid))) = 4
     and (select count(*) from crm.conversion_ventas_recuperadas) = 5 as ok
),
ventas as (
  -- Cada venta recuperada: acreditada al contrato vivo, el lead enlazado, ya no anulada y contando una vez en la conversión.
  select count(*) = 5 as ok
  from crm.conversion_ventas_recuperadas r
  join crm.conversion_acreditaciones ca on ca.id = r.acreditacion_id and ca.lead_id = r.lead_id
  join crm.leads l on l.id = r.lead_id
  where ca.fuente_tipo = 'contrato' and ca.fuente_id = r.contrato_vigente_id and ca.estado = 'acreditada'
    and l.contrato_id = r.contrato_vigente_id and not private.cierre_anulado(r.lead_id)
    and exists (select 1 from public.contratos c where c.id = r.contrato_vigente_id
                and c.fecha_cierre_comercial = r.fecha_comercial_despues and c.categoria = 'nuevo')
    -- Un cierre válido; con aporte, salvo un referido (el tope reparte su aporte individual: puede ser 0).
    and (select count(*) from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
         where x.tipo = 'cierre' and x.lead_id = r.lead_id and not x.anulado and (x.aporte_numerador > 0 or x.fue_referido)) = 1
),
otras as (
  -- Las anulaciones NO rehabilitadas siguen contando (la excepción es por fila, no general): de Avance y copias anuladas.
  select not exists (select 1 from crm.cierres_avance_anulados a
                     where not exists (select 1 from crm.conversion_ventas_recuperadas r where r.cierre_avance_anulado_id = a.id)
                       and not private.cierre_anulado(a.lead_id))
     and not exists (select 1 from crm.inversiones_eliminadas ie
                     where ie.conversion_anulada and ie.lead_id is not null
                       and not exists (select 1 from crm.conversion_ventas_recuperadas r where r.inversion_eliminada_id = ie.id)
                       and not private.cierre_anulado(ie.lead_id)) as ok
)
select case when h.ok and t.ok and v.ok and o.ok then 'APTA' else 'NO APTA' end as veredicto,
  h.ok as huellas, t.ok as tabla, v.ok as ventas_recuperadas, o.ok as otras_anulaciones_siguen
from huellas h, tabla t, ventas v, otras o;
rollback;
