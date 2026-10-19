CREATE OR REPLACE FUNCTION private.trg_sla_nucleo_entrada_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_lead uuid;v_evento crm.actividades%rowtype;v_etapa crm.lead_sla_etapas%rowtype;
  v_regla crm.sla_politica_etapas_operacion%rowtype;v_hechos record;v_control crm.sla_operacion_control%rowtype;v_decision record;
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op in ('DELETE','TRUNCATE') then raise exception 'Los hechos SLA no se borran' using errcode='55000';end if;
  if current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
    raise exception 'Solo el nucleo escribe entradas SLA' using errcode='42501';end if;
  if tg_table_name='sla_operacion_control' then
    if tg_op<>'UPDATE' or current_setting('crm.sla_control_writer',true) is distinct from 'on' then
      raise exception 'El modo solo cambia por su comando' using errcode='55000';end if;
    if (old.primera_activacion_en is not null and
       (new.primera_activacion_en is distinct from old.primera_activacion_en
        or new.politica_adopcion_id is distinct from old.politica_adopcion_id))
      or new.revision<>old.revision+1 then
      raise exception 'Adopcion inmutable o revision invalida' using errcode='55000';end if;
    if new.politica_adopcion_id is not null and not private.sla_reglas_operacion_validas(
      (select jsonb_agg(to_jsonb(r)-'politica_id') from crm.sla_politica_etapas_operacion r where r.politica_id=new.politica_adopcion_id)) then
      raise exception 'La adopcion requiere cuatro reglas completas' using errcode='23514';end if;
  elsif tg_op='UPDATE' then
    raise exception 'Entrada SLA inmutable' using errcode='55000';
  elsif tg_table_name='sla_politica_etapas_operacion' then
    if current_setting('crm.sla_config_writer',true) is distinct from 'on'
      or exists(select 1 from crm.lead_sla_etapas e where e.politica_id=new.politica_id) then
      raise exception 'Reglas solo durante publicacion, nunca sobre episodios existentes' using errcode='55000';end if;
  elsif tg_table_name='tarea_sla_contexto' then
    if ((new.fuente='evento' and pg_trigger_depth()>=2
               and current_setting('crm.sla_contexto_writer',true)='evento')
         or (new.fuente='reconstruido' and current_setting('crm.sla_contexto_writer',true)='reconstruido')) is distinct from true then
      raise exception 'Contexto solo por captura o reconstruccion privada' using errcode='55000';end if;
    select lead_id into v_lead from crm.tareas where id=new.tarea_id;
    if v_lead is distinct from new.lead_id then
      raise exception 'Contexto ajeno a tarea' using errcode='23514';end if;
  elsif tg_table_name='lead_sla_etapa_ajustes' then
    if (pg_trigger_depth()<2 and current_setting('crm.sla_finalizando_gesto',true) is distinct from 'on')
      or current_setting('crm.sla_ajuste_writer',true) is distinct from 'on' then
      raise exception 'Ajuste solo desde evento de gestion' using errcode='55000';end if;
    select * into strict v_evento from crm.actividades where id=new.origen_actividad_id;
    select * into strict v_etapa from crm.lead_sla_etapas where id=new.etapa_sla_id;
    select * into strict v_regla from crm.sla_politica_etapas_operacion
      where politica_id=v_etapa.politica_id and etapa=v_etapa.etapa;
    select * into strict v_control from crm.sla_operacion_control where id;
    select * into strict v_hechos from private.sla_etapa_hechos(v_etapa.id,v_etapa.lead_id,v_etapa.ciclo_n,v_etapa.etapa);
    select * into strict v_decision from private.sla_evaluar_prorroga(v_etapa.etapa,v_evento.tipo,v_evento.creado_por,
      v_etapa.finalizado_en is null,v_control.modo,v_control.primera_activacion_en,v_evento.creado_en,
      v_etapa.limite_en+v_hechos.minutos*interval '1 minute',v_etapa.limite_en+v_regla.tope_extra_minutos*interval '1 minute',
      v_regla.prorroga_minutos,v_regla.prorroga_max,v_hechos.usadas,false);
    if v_evento.lead_id<>v_etapa.lead_id or v_evento.creado_por is distinct from new.creado_por
      or auth.uid() is distinct from new.creado_por or not v_decision.elegible
      or new.secuencia<>v_hechos.usadas+1 or new.minutos_reales<>v_decision.minutos_reales
      or new.limite_antes<>v_etapa.limite_en+v_hechos.minutos*interval '1 minute'
      or new.limite_despues<>v_decision.limite_despues then
      raise exception 'Ajuste fuera de causa, secuencia o presupuesto' using errcode='23514';end if;
  end if;
  return new;
end;
$function$
