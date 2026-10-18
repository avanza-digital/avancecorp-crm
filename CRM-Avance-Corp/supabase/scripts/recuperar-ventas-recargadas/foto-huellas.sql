-- SOLO LECTURA. Huellas (md5 de pg_get_functiondef con search_path vacío) de lo que la migración 20261018032400 cambia o llama.
begin read only;
set local search_path = '';
select string_agg(p.oid::regprocedure::text || ' ' || md5(pg_catalog.pg_get_functiondef(p.oid)), ' | ' order by p.oid::regprocedure::text) as huellas
from pg_catalog.pg_proc p
where p.oid in ('private.cierre_anulado(uuid)'::regprocedure, 'private.conversion_acreditar_fuente(uuid,text,uuid,text)'::regprocedure,
  'private.conversion_exclusion_fuente(text,uuid)'::regprocedure, 'private.conversion_plazo_hasta(date)'::regprocedure,
  'private.leads_before_update()'::regprocedure, 'private.materializar_capital_valoraciones_para(integer,text,uuid)'::regprocedure,
  'crm.cierres_estado_fn(uuid[])'::regprocedure, 'crm.altas_nuevas_por_analista_fn(integer)'::regprocedure,
  'crm.anular_cierre_avance(uuid,text)'::regprocedure);
rollback;
