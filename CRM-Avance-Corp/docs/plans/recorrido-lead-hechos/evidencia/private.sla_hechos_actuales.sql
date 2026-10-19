CREATE OR REPLACE FUNCTION private.sla_hechos_actuales(p_lead_ids uuid[], p_global boolean, p_visibles uuid[])
 RETURNS TABLE(lead_id uuid, etapa_actual text, vendedor_id uuid, supervisor_id uuid, creado_en timestamp with time zone, ciclo_n integer, ciclo_inicio timestamp with time zone, asignacion_id uuid, asignacion_inicio timestamp with time zone, etapa_sla_id uuid, etapa_inicio timestamp with time zone, limite_original timestamp with time zone, politica_etapa_id uuid, base jsonb, activo boolean, asignacion_coherente boolean, etapa_coherente boolean, nombre_completo text, analista_nombre text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select l.id, l.etapa, l.vendedor_id, l.asignado_supervisor_id, l.creado_en,
    l.ciclo_actual, c.iniciado_en, a.id, a.asignado_en, e.id, e.iniciado_en,
    e.limite_en, e.politica_id,
    case when c.id is null or pc.id is null then null else jsonb_build_object(
      'lead_id',l.id,
      'ciclo_politica_id',c.politica_id,'ciclo_politica_version',pc.version,
      'primera_gestion_limite_en',c.primera_gestion_limite_en,'primera_gestion_en',c.primera_gestion_en,
      'primer_contacto_limite_en',c.primer_contacto_limite_en,'primer_contacto_en',c.primer_contacto_en,
      'ciclo_aproximado',c.aproximado,
      'asignacion_id',a.id,'asignacion_politica_id',a.sla_politica_asignacion_id,'asignacion_politica_version',pa.version,
      'asignacion_primera_gestion_limite_en',a.primera_gestion_limite_en,'asignacion_primera_gestion_en',ah.primera_gestion_en,
      'asignacion_primer_contacto_limite_en',a.primer_contacto_limite_en,'asignacion_primer_contacto_en',ah.primer_contacto_en,
      'etapa_politica_id',e.politica_id,'etapa_politica_version',pe.version,'etapa',e.etapa,
      'etapa_iniciada_en',e.iniciado_en,'etapa_limite_en',e.limite_en,'etapa_objetivo_minutos',re.maximo_minutos,
      'etapa_aproximada',e.aproximado
    ) end,l.activo,
    a.ciclo_n=l.ciclo_actual and a.analista_id is not distinct from l.vendedor_id,
    e.etapa=l.etapa,l.nombre_completo,dueno.nombre_completo
  from crm.leads l
  left join public.perfiles dueno on dueno.id=l.vendedor_id
  left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  left join crm.sla_politicas pc on pc.id=c.politica_id
  left join lateral (
    select la.* from crm.lead_asignaciones la
    where la.lead_id=l.id and la.finalizado_en is null
    order by la.episodio_n desc limit 1
  ) a on true
  left join crm.sla_politicas pa on pa.id=a.sla_politica_asignacion_id
  left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id=a.id
  left join crm.lead_sla_etapas e on e.lead_id=l.id and e.ciclo_n=l.ciclo_actual and e.finalizado_en is null
  left join crm.sla_politicas pe on pe.id=e.politica_id
  left join crm.sla_politica_etapas re on re.politica_id=e.politica_id and re.etapa=e.etapa
  where (l.activo is true or p_lead_ids is not null)
    and (p_lead_ids is null or l.id=any(p_lead_ids))
    and (p_global is true or l.vendedor_id=any(p_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id=any(p_visibles)))
  order by l.id;
$function$
