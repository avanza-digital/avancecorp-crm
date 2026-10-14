-- Miguel 14/10/2026: el capital adicional de una renovación aporta como upgrade.
-- Primera operación elegible por cliente/mes; renovación pura y referido sin cambios.
-- Solo reemplaza el núcleo privado. No escribe pesos, operaciones ni fotos.
-- Rechaza la aplicación si octubre o un mes posterior ya está cerrado.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
set local search_path = '';
select pg_catalog.pg_advisory_xact_lock(
  pg_catalog.hashtext('crm.periodos_cerrados')::bigint
);
lock table crm.periodos_cerrados in share mode;
lock table crm.conversion_pesos in share mode;

do $preflight$
begin
  if exists (
    select 1 from crm.periodos_cerrados where periodo >= date '2026-10-01'
  ) then
    raise exception 'ADICIONAL RENOVACION: octubre o posterior ya está cerrado'
      using errcode = 'P0409';
  end if;
  if not exists (
    select 1 from crm.conversion_pesos
    where vigente_desde = date '2026-10-01'
      and peso_renovacion = 0 and peso_referido = 1 and tope_referidos_pct = 15
  ) or exists (
    select 1 from crm.conversion_pesos
    where vigente_desde > date '2026-10-01'
  ) then
    raise exception 'ADICIONAL RENOVACION: pesos distintos de los revisados'
      using errcode = 'P0409';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(
      'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')
      and pg_catalog.md5(p.prosrc) = 'ed15fbd034c636e4897c7600002ee8cf'
      and p.proowner = 'postgres'::regrole
      and p.proacl::text = '{postgres=X/postgres}'
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'ADICIONAL RENOVACION: núcleo o permisos distintos de los revisados'
      using errcode = 'P0409';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- El límite se calcula por analista y mes completo de cierre.
  -- Un rango parcial selecciona después los aportes que caen en sus fechas.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- La base es el total de cierres referidos válidos del analista y mes.
  select c.*,
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    (c.fue_referido and not c.anulado) as es_referido,
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id=c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
), con_tope as (
  select m.*,
    count(*) filter (where m.es_referido) over
      (partition by m.analista_id,m.mes_cierre) as total_referidos,
    -- Se conserva el orden vigente: fecha comercial, acreditación y UUID.
    -- Cada cierre conserva su aporte previo; el último admitido puede ser parcial.
    coalesce(sum(m.aporte_numerador) filter (where m.es_referido) over (
      partition by m.analista_id,m.mes_cierre,m.es_referido
      order by m.fecha_numerador,m.registrado_en,m.lead_id
      rows between unbounded preceding and 1 preceding),0) as aporte_anterior_referidos,
    private.tope_referidos_conversion(m.mes_cierre) as tope_pct
  from marcados m
)
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- Límite agregado exacto: total de cierres referidos válidos × porcentaje.
-- Se calcula sobre el mes completo antes de recortar el rango consultado.
-- Sin redondeo entero: 4 referidos con límite 15 % admiten un máximo de 0,60.
-- Los meses sin tope conservan su ponderación histórica.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
       then least(t.aporte_numerador,
         greatest(0::numeric,
           t.total_referidos * t.tope_pct / 100.0 - t.aporte_anterior_referidos))
       else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Desde octubre, el adicional de renovación cuenta como upgrade.
-- Solo cambia la categoría del aporte: el registro y el capital no se alteran.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.categoria_conversion, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.categoria_conversion = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.categoria_conversion = 'upgrade' then 1 else 0 end
from (
  select o0.*,
    case when o0.tipo = 'renovacion'
      and o0.periodo >= date '2026-10-01'
      and o0.capital_adicional > 0
      then 'upgrade' else o0.tipo end as categoria_conversion,
    row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) = any(p_visibles));
end;
$function$;

-- CREATE OR REPLACE conserva propietario, ACL y firma.
do $postflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = pg_catalog.to_regprocedure(
      'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')
      and p.proowner = 'postgres'::regrole
      and p.proacl::text = '{postgres=X/postgres}'
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig = array['search_path=""']
  ) then
    raise exception 'ADICIONAL RENOVACION: cambió el contrato de seguridad';
  end if;
end;
$postflight$;
commit;
