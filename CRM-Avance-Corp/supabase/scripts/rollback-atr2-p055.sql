-- MARCHA ATRAS de P-055 ATR-2 (capital por cadena de upgrade).
-- Repone el cuerpo ORIGINAL del nucleo de capital (literal de maquina del
-- prosrc vivo del 30/08). El resolutor NO se toca: es de ATR-1.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- 0) PREFLIGHT: solo se pisa el estado ATR-2. Si un hotfix posterior movio el
--    nucleo, esto ABORTA — regenerar el rollback, jamas pisar a ciegas.
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from '90f1d8c2342becb94cc3d3e023227078' then
    raise exception 'rollback ATR-2: capital_episodios NO esta en el estado ATR-2 (huella %) — regenerar el rollback', v_h;
  end if;
  -- P1-4 de Codex: un ALTER FUNCTION (security/volatility/search_path) conserva
  -- prosrc — los atributos tambien se pinnean antes de pisar.
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig::text = '{"search_path=\"\""}') then
    raise exception 'rollback ATR-2: los ATRIBUTOS del nucleo no son los del estado ATR-2 — regenerar el rollback';
  end if;
end $$;

CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    c.analista_cierre_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = c.analista_cierre_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    o.vendedor_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = o.vendedor_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or o.vendedor_id = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$function$
;

do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from '872f5ad4362f66a18f4a3806453f78a0' then
    raise exception 'rollback ATR-2: el nucleo no volvio al byte (huella %)', v_h;
  end if;
  if (select p.proacl::text from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'rollback ATR-2: proacl del nucleo no es el original';
  end if;
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig::text = '{"search_path=\"\""}') then
    raise exception 'rollback ATR-2: los ATRIBUTOS del nucleo no volvieron (definer/stable/search_path vacio)';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
