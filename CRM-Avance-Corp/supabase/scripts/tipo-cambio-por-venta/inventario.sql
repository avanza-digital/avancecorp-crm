-- Lectura acotada: sin nombres, contactos, cuentas, documentos ni credenciales.
begin read only;
with episodios as materialized (
  select e.* from private.capital_episodios(
    '2026-10-01 00:00 America/Lima'::timestamptz,
    '2026-11-01 00:00 America/Lima'::timestamptz,true,'{}'::uuid[]) e
  where e.medida='stock'
), hechos as (
  select case when e.contrato_id is not null then 'contrato' else 'cierre_externo' end as fuente,
    coalesce(e.contrato_id,e.cierre_externo_id) as fuente_id,
    case when e.contrato_id is not null then c.fecha_cierre_comercial else ce.fecha_comercial end as fecha_comercial,
    (e.fecha at time zone 'America/Lima')::date as fecha_imputacion,
    e.moneda,e.monto,e.categoria,e.analista_id,e.en_roster,e.anulado,
    exists(select 1 from crm.inversiones i where i.contrato_id=e.contrato_id
      or i.cierre_externo_id=e.cierre_externo_id) as tiene_inversion
  from episodios e
  left join public.contratos c on c.id=e.contrato_id
  left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
)
select jsonb_build_object(
  'capturado_en',statement_timestamp(),
  'proyecto','dctqcbznekcyxhjujuci',
  'periodo','2026-10-01',
  'operaciones',(select coalesce(jsonb_agg(to_jsonb(h) order by h.fecha_comercial,h.fuente,h.fuente_id),'[]') from hechos h),
  'metas',(select coalesce(jsonb_agg(jsonb_build_object('analista_id',mv.vendedor_id,
    'moneda',d.moneda,'objetivo',d.capital_objetivo,'categoria',d.categoria)),'[]')
    from crm.metas_vendedor_detalle d join crm.metas_vendedor mv on mv.id=d.meta_vendedor_id
    join crm.meta_periodos mp on mp.id=mv.meta_periodo_id
    where mp.periodo='2026-10-01' and mp.revision=(select max(revision) from crm.meta_periodos where periodo='2026-10-01')),
  'ajustes_usd',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'lead_id',a.lead_id,
    'periodo_origen',a.periodo_origen,'capital_usd',a.capital_usd,'pendiente_usd',a.pendiente_usd,
    'detalle',a.detalle,'pendiente_detalle',a.pendiente_detalle)),'[]')
    from crm.ajustes_mes_cerrado a where a.pendiente_usd>0),
  'cierres',(select coalesce(jsonb_agg(pc.periodo order by pc.periodo),'[]') from crm.periodos_cerrados pc),
  'huella_fotos',(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.periodo,f.vendedor_id)::text,'[]'))
    from crm.cierre_mes_vendedor f),
  'huella_funciones',(select md5(string_agg(p.oid::regprocedure::text||':'||md5(pg_get_functiondef(p.oid)),',' order by p.oid::regprocedure::text))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('crm','private') and p.prokind='f')
) as inventario;
rollback;
