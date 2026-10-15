CREATE OR REPLACE FUNCTION private.trg_lead_sla_ciclos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op='DELETE' then raise exception 'Los ciclos SLA no se eliminan' using errcode='55000'; end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on' or pg_trigger_depth()<2 then
    raise exception 'Los ciclos SLA solo se escriben desde eventos CRM' using errcode='42501';
  end if;
  if tg_op='INSERT' then return new; end if;
  if old.id is distinct from new.id or old.lead_id is distinct from new.lead_id
    or old.ciclo_n is distinct from new.ciclo_n or old.politica_id is distinct from new.politica_id
    or old.iniciado_en is distinct from new.iniciado_en
    or old.primera_gestion_limite_en is distinct from new.primera_gestion_limite_en
    or old.primer_contacto_limite_en is distinct from new.primer_contacto_limite_en
    or old.aproximado is distinct from new.aproximado or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null and old.primer_contacto_en is distinct from new.primer_contacto_en) then
    raise exception 'Snapshot/eventos SLA inmutables' using errcode='55000';
  end if;
  return new;
end;
$function$
