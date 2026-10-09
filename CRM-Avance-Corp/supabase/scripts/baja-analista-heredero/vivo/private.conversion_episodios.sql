CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- Los meses COMPLETOS que toca la ventana: el tope de referidos es por analista y por mes de cierre, y su base son
  -- todos los cierres de leads asignados de ESE analista en ese mes, no solo los de un rango parcial. Como cada analista
  -- tiene su propia base, el ámbito (p_global/p_visibles) se aplica antes de calcular el tope sin cambiar su resultado.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- El índice único del ledger garantiza un cierre por lead. El cierre queda
  -- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
  -- siguen disponibles para consumidores operativos/capital, con aporte CERO.
  select c.*,
    -- El mes de CIERRE: el de la fecha comercial del cierre del lead.
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    -- Un cierre cuenta para la base del tope solo si NO está anulado y es el cierre de un lead que el sistema asigna
    -- (private.conversion_origen_base_tope: landing y formulario) y que no es un registro manual (alta_manual: regla
    -- cerrada, el registro manual queda fuera de la base, como queda fuera del divisor). Los referidos y la base cargada
    -- no entran en la base. Solo la BASE excluye el alta manual: su aporte al numerador sigue entero.
    (not c.anulado and private.conversion_origen_base_tope(c.origen) and not coalesce(lm.alta_manual, false)) as en_base,
    (c.fue_referido and not c.anulado) as es_referido,
    -- Desempate de dos cierres de la MISMA fecha comercial (es un día, sin hora): el que se acreditó antes cuenta antes.
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
  left join crm.leads lm on lm.id = c.lead_id
), con_tope as (
  select m.*,
    -- Un cierre sin analista (analista_id NULL) comparte UNA sola partición con los demás sin analista: un solo tope para todos.
    count(*) filter (where m.en_base) over (partition by m.analista_id, m.mes_cierre) as base_cierres,
    -- Los referidos de cada analista y mes, del más antiguo al más reciente: cuentan los primeros.
    row_number() over (partition by m.analista_id, m.mes_cierre, m.es_referido
                       order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido,
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

-- TOPE DE REFERIDOS (Miguel, 07/10/2026, desde octubre): por analista y mes de cierre, los referidos cuentan hasta el
-- tope % de sus cierres de leads asignados por el sistema (en_base; sin referidos, base cargada, registros manuales ni
-- operaciones; redondeado hacia arriba); los más recientes pasan a valer 0. Sin cierres asignados la base es 0 y todos sus referidos valen 0.
-- Sin tope vigente para el mes (agosto, septiembre) el aporte queda como siempre.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
         and t.orden_referido > ceil(t.base_cierres * t.tope_pct / 100.0)
       then 0::numeric else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa su propio peso; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
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
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
                           o.vendedor_id) = any(p_visibles));
end;
$function$
