-- Fuente viva 2026-09-06, md5(pg_get_functiondef)=11808483d300a97fb6ff8b3be2dab1fa
CREATE OR REPLACE FUNCTION crm.estado_sla_leads_fn()
 RETURNS TABLE(lead_id uuid, ciclo_politica_id uuid, ciclo_politica_version integer, primera_gestion_limite_en timestamp with time zone, primera_gestion_en timestamp with time zone, primer_contacto_limite_en timestamp with time zone, primer_contacto_en timestamp with time zone, ciclo_aproximado boolean, asignacion_id uuid, asignacion_politica_id uuid, asignacion_politica_version integer, asignacion_primera_gestion_limite_en timestamp with time zone, asignacion_primera_gestion_en timestamp with time zone, asignacion_primer_contacto_limite_en timestamp with time zone, asignacion_primer_contacto_en timestamp with time zone, etapa_politica_id uuid, etapa_politica_version integer, etapa text, etapa_iniciada_en timestamp with time zone, etapa_limite_en timestamp with time zone, etapa_objetivo_minutos integer, etapa_aproximada boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector_global boolean;
  v_visibles uuid[];
begin
  v_rol := private.rol_crm(v_uid);
  v_lector_global := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector_global) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  return query
  select
    l.id,
    c.politica_id,
    pc.version,
    c.primera_gestion_limite_en,
    c.primera_gestion_en,
    c.primer_contacto_limite_en,
    c.primer_contacto_en,
    c.aproximado,
    a.id,
    a.sla_politica_asignacion_id,
    pa.version,
    a.primera_gestion_limite_en,
    ah.primera_gestion_en,
    a.primer_contacto_limite_en,
    ah.primer_contacto_en,
    e.politica_id,
    pe.version,
    e.etapa,
    e.iniciado_en,
    e.limite_en,
    re.maximo_minutos,
    e.aproximado
  from crm.leads l
  join crm.lead_sla_ciclos c
    on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  join crm.sla_politicas pc on pc.id=c.politica_id
  left join lateral (
    select la.*
    from crm.lead_asignaciones la
    where la.lead_id=l.id and la.finalizado_en is null
    order by la.episodio_n desc
    limit 1
  ) a on true
  left join crm.sla_politicas pa on pa.id=a.sla_politica_asignacion_id
  left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id=a.id
  left join crm.lead_sla_etapas e
    on e.lead_id=l.id and e.ciclo_n=l.ciclo_actual and e.finalizado_en is null
  left join crm.sla_politicas pe on pe.id=e.politica_id
  left join crm.sla_politica_etapas re
    on re.politica_id=e.politica_id and re.etapa=e.etapa
  where l.activo is true
    and (
      l.vendedor_id = any(v_visibles)
      or (
        l.vendedor_id is null
        and l.asignado_supervisor_id = any(v_visibles)
      )
      or v_rol='gerencia'
      or v_lector_global
    )
  order by l.id;
end;
$function$
;
