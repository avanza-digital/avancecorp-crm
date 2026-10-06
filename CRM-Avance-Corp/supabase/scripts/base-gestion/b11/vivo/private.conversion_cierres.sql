CREATE OR REPLACE FUNCTION private.conversion_cierres(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric, p_leads uuid[])
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
select 'cierre'::text, la.analista_id, la.lead_id, null::uuid,
  l.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(la.lead_id), l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  coalesce(la.resultado_en, la.finalizado_en), 0,
  case when private.cierre_externo_anulado(la.lead_id) then 0
    when l.origen = 'referido' then
      case when p_periodo is not null then p_factor else
        private.peso_referido_conversion(date_trunc('month',
          coalesce(la.resultado_en, la.finalizado_en) at time zone 'America/Lima')::date) end
    when l.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.lead_asignaciones la
join crm.leads l on l.id = la.lead_id
where la.resultado = 'convertido'
  -- La política previa conserva agosto y todos los meses anteriores.
  and (not exists(select 1 from crm.conversion_politica where activada_en is not null)
    or coalesce(la.resultado_en, la.finalizado_en) < '2026-09-01 00:00:00 America/Lima'::timestamptz)
  and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
  and coalesce(la.resultado_en, la.finalizado_en) < p_fin
  and (p_global or la.analista_id = any(p_visibles))
  and (p_leads is null or la.lead_id in (select id from unnest(p_leads) seleccion(id)))
union all
select 'cierre'::text, ca.analista_id, ca.lead_id, null::uuid,
  ca.origen = 'referido', null::boolean, null::text,
  private.cierre_externo_anulado(ca.lead_id), ca.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, null::timestamptz,
  ca.fecha_comercial::timestamp at time zone 'America/Lima', 0,
  case when private.cierre_externo_anulado(ca.lead_id) then 0
    when ca.origen = 'referido' then
      case when p_periodo is not null then p_factor
        else private.peso_referido_conversion(ca.periodo_comercial) end
    when ca.origen in ('landing', 'formulario') then 1
    else 0 end
from crm.conversion_acreditaciones ca
join crm.leads l on l.id=ca.lead_id
where ca.estado='acreditada'
  and exists(select 1 from crm.conversion_politica where activada_en is not null)
  -- No reabrir agosto por la acreditación en septiembre de un contrato viejo.
  and ca.periodo_comercial >= date '2026-09-01'
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') >= p_ini
  and (ca.fecha_comercial::timestamp at time zone 'America/Lima') < p_fin
  and (p_global or ca.analista_id = any(p_visibles))
  and (p_leads is null or ca.lead_id in (select id from unnest(p_leads) seleccion(id)))
  -- Una fuente retirada no sigue fabricando cierres en un mes abierto.
  -- El hecho y su auditoría sobreviven; un mes sellado se sirve por su foto.
  and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible';
$function$

