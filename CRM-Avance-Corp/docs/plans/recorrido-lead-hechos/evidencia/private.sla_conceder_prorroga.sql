CREATE OR REPLACE FUNCTION private.sla_conceder_prorroga(p_actividad_id uuid, p_episodio_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_evento crm.actividades%rowtype;v_lead crm.leads%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_control crm.sla_operacion_control%rowtype;
  v_hechos record;v_decision record;v_id uuid;v_previo text:=coalesce(current_setting('crm.sla_ajuste_writer',true),'off');
begin
  if pg_trigger_depth()<1 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on' then
    raise exception 'La prorroga requiere un evento de gestion' using errcode='55000';end if;
  if auth.uid() is null then return null;end if;
  select * into strict v_evento from crm.actividades where id=p_actividad_id;
  if v_evento.creado_por is distinct from auth.uid() then return null;end if;
  select * into strict v_lead from crm.leads where id=v_evento.lead_id for update;
  if not v_lead.activo or private.persona_vetada(v_lead.id) then return null;end if;
  select * into v_etapa from crm.lead_sla_etapas where id=p_episodio_id and lead_id=v_lead.id
    and ciclo_n=v_lead.ciclo_actual and etapa=v_lead.etapa and finalizado_en is null for update;
  if not found then return null;end if;
  select * into v_regla from crm.sla_politica_etapas_operacion
    where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
  if not found then return null;end if;
  select id into v_id from crm.lead_sla_etapa_ajustes where etapa_sla_id=p_episodio_id and origen_actividad_id=p_actividad_id;
  if found then return v_id;end if;
  select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_lead.id,v_lead.ciclo_actual,v_etapa.etapa);
  -- Barrera de apagado: ultima dependencia de bloqueo; conservada hasta commit.
  select * into strict v_control from crm.sla_operacion_control where id for share;
  select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
    true,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
    v_etapa.limite_en+v_hechos.minutos*interval '1 minute',
    v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
    v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
  if not v_decision.elegible then return null;end if;
  perform set_config('crm.sla_ajuste_writer','on',true);
  insert into crm.lead_sla_etapa_ajustes(etapa_sla_id,origen_actividad_id,secuencia,minutos_reales,
    limite_antes,limite_despues,creado_por)
  values(v_etapa.id,v_evento.id,v_hechos.usadas+1,v_decision.minutos_reales,
    v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_decision.limite_despues,v_evento.creado_por)
  returning id into v_id;
  perform set_config('crm.sla_ajuste_writer',v_previo,true);
  return v_id;
end;
$function$
