CREATE OR REPLACE FUNCTION crm.altas_nuevas_por_analista_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, analista_id uuid, analista_nombre text, altas bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with gate as (
    -- fail-closed: sin rol CRM ni lector global, el reporte sale VACIO.
    select coalesce(
      (select auth.uid()) is not null
      and (
        private.rol_crm((select auth.uid())) in ('vendedor','supervisor','gerencia')
        or private.es_lector_global()
      ), false) as ok
  ),
  ambito as (
    select
      (coalesce(private.es_lector_global(), false)
       or private.rol_crm((select auth.uid())) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid()))) as ids
  ),
  anulados as (
    -- Contratos cuyo cierre fue anulado, por el mapeo CANONICO (no reinventado).
    -- Rama 2 (cierres_externos = cooperativa): las coop NO viven en public.contratos,
    -- asi que el mapeo devuelve contratos Avance solo si el MISMO lead ligo un 'nuevo'
    -- Avance al mismo acreditado; hoy 0 impacto (unica coop anulada -> 0 'nuevo').
    select x as contrato_id
    from crm.cierres_avance_anulados ca
    cross join lateral private.contratos_afectados_por_anulacion(ca.lead_id) x
    union
    select x
    from crm.cierres_externos ce
    cross join lateral private.contratos_afectados_por_anulacion(ce.lead_id) x
    where ce.anulado_en is not null and ce.es_cierre_inicial
  ),
  base as (
    -- 🔴 fecha_cierre_comercial ES `date` (el dia comercial de Lima). NUNCA
    --    `at time zone` sobre un date: en un servidor UTC el dia 1 se cae al mes
    --    anterior (footgun del proyecto). Se bucketea y se acota en espacio de FECHA,
    --    igual que private.capital_episodios.
    select
      (date_trunc('month', c.fecha_cierre_comercial))::date as mes,
      coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) as analista_id
    from public.contratos c
    where c.categoria = 'nuevo'
      and not c.es_demo
      and c.fecha_cierre_comercial is not null
      and not exists (select 1 from anulados an where an.contrato_id = c.id)
      and c.fecha_cierre_comercial >=
        (date_trunc('month', now() at time zone 'America/Lima')
          - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date
  )
  select
    b.mes,
    b.analista_id,
    coalesce(pf.nombre_completo, 'Sin analista') as analista_nombre,
    count(*)::bigint as altas
  from gate g
  cross join ambito a
  join base b on g.ok
  left join public.perfiles pf on pf.id = b.analista_id
  where a.es_global or b.analista_id = any(a.ids)
  group by b.mes, b.analista_id, coalesce(pf.nombre_completo, 'Sin analista')
  order by b.mes desc, altas desc;
$function$
