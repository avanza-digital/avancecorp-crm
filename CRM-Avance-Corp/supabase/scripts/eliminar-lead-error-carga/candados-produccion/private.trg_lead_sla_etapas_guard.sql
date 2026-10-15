CREATE OR REPLACE FUNCTION private.trg_lead_sla_etapas_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Las etapas SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Las etapas SLA solo se escriben desde crm.leads' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.finalizado_en is not null or new.finalizado_en is null or new.motivo_cierre is null
    or old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.episodio_n is distinct from new.episodio_n
    or old.etapa is distinct from new.etapa or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en or old.limite_en is distinct from new.limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en then
    raise exception 'Solo se permite cerrar una etapa SLA abierta' using errcode='55000';
  end if;
  return new;
end;
$function$
