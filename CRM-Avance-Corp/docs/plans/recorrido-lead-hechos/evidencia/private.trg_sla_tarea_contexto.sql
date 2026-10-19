CREATE OR REPLACE FUNCTION private.trg_sla_tarea_contexto()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_lead crm.leads%rowtype;v_anterior text:=coalesce(current_setting('crm.sla_contexto_writer',true),'off');
begin
  if new.lead_id is null then return null;end if;
  -- Reutiliza el lock fuerte adquirido en BEFORE INSERT, incluso con auth NULL.
  select * into strict v_lead from crm.leads where id=new.lead_id for update;
  if not exists(select 1 from crm.lead_sla_ciclos where lead_id=new.lead_id and ciclo_n=v_lead.ciclo_actual) then
    raise exception 'Falta ciclo causal para tarea nueva' using errcode='23514';end if;
  perform set_config('crm.sla_contexto_writer','evento',true);
  insert into crm.tarea_sla_contexto(tarea_id,lead_id,ciclo_n,fuente)
    values(new.id,new.lead_id,v_lead.ciclo_actual,'evento');
  perform set_config('crm.sla_contexto_writer',v_anterior,true);
  return null;
end;
$function$
