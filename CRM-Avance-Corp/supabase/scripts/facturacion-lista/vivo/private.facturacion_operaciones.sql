CREATE OR REPLACE FUNCTION private.facturacion_operaciones(p_desde timestamp with time zone, p_hasta timestamp with time zone)
 RETURNS TABLE(operacion_id uuid, dia date, fecha timestamp with time zone, tipo text, moneda text, monto numeric, analista_id uuid, supervisor_id uuid, contrato_id uuid, cierre_externo_id uuid, cliente_id uuid, lead_id uuid, registrado_por uuid, categoria text, estado text, anulado boolean, fecha_vencimiento date)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with episodios as (
    select (e.fecha at time zone 'America/Lima')::date as dia, e.*
    from private.capital_episodios(p_desde, p_hasta, true, '{}'::uuid[]) e
    where e.medida = 'stock'
  ),
  eventos as (
    select
      ue.objetivo_id as analista_id,
      (ue.creado_en at time zone 'America/Lima')::date as dia_cambio,
      (ue.detalle->>'supervisor_anterior')::uuid as antes,
      (ue.detalle->>'supervisor_nuevo')::uuid as despues,
      -- `ue.id` desempata: sin él, dos eventos en el mismo instante numerarían
      -- de forma no determinista y los tramos podrían solaparse.
      row_number() over (partition by ue.objetivo_id order by ue.creado_en, ue.id) as n
    from crm.usuario_eventos ue
    where ue.accion = 'jerarquia_actualizada'
  ),
  tramos as (
    -- Antes del primer cambio registrado.
    select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
    from eventos e
    where e.n = 1
    union all
    -- Entre un cambio y el siguiente (o hasta hoy, si fue el último). El día del
    -- cambio cuenta ya para el supervisor NUEVO; con dos cambios el mismo día, el
    -- tramo intermedio queda vacío y manda el último.
    select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
    from eventos e
    left join eventos sig
      on sig.analista_id = e.analista_id and sig.n = e.n + 1
  )
  select
    coalesce(ep.contrato_id, ep.cierre_externo_id) as operacion_id,
    ep.dia, ep.fecha, ep.tipo, ep.moneda, ep.monto, ep.analista_id,
  -- LOS DOS CAMINOS AL EQUIPO DE HOY, y son deliberados: no hay tramo (nunca se
  -- registró un cambio) o el tramo dice NULL («no constaba jerarquía entonces»).
  -- Ver la nota de la cabecera de 20260910230000: en un informe de dinero «no
  -- consta» no deja el importe sin dueño.
    coalesce(t.supervisor_id, eq.supervisor_id) as supervisor_id,
    ep.contrato_id, ep.cierre_externo_id, ep.cliente_id, ep.lead_id,
    ep.registrado_por, ep.categoria, ep.estado, ep.anulado, ep.fecha_vencimiento
  from episodios ep
  -- Los tramos de un analista son disjuntos y cubren toda la línea temporal, así
  -- que este join casa como mucho una fila. `crm.equipo.perfil_id` es PK.
  left join tramos t
    on t.analista_id = ep.analista_id
   and ep.dia >= t.desde
   and ep.dia <  t.hasta
  left join crm.equipo eq on eq.perfil_id = ep.analista_id;
$function$
