CREATE OR REPLACE FUNCTION private.trg_lead_asignacion_sla_hitos_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_asignado_en timestamptz;
  v_finalizado_en timestamptz;
begin
  if tg_op='DELETE' then
    raise exception 'Los hitos SLA de asignacion no se eliminan' using errcode='55000';
  end if;
  if coalesce(current_setting('crm.sla_writer',true),'off')<>'on'
    or pg_trigger_depth()<2 then
    raise exception 'Los hitos SLA solo se sellan desde eventos CRM' using errcode='42501';
  end if;
  select a.asignado_en,a.finalizado_en into v_asignado_en,v_finalizado_en
  from crm.lead_asignaciones a where a.id=new.lead_asignacion_id;
  if not found then raise exception 'Asignacion SLA inexistente' using errcode='23503'; end if;
  if tg_op='UPDATE' and (
    old.id is distinct from new.id
    or old.lead_asignacion_id is distinct from new.lead_asignacion_id
    or old.creado_en is distinct from new.creado_en
    or (old.primera_gestion_en is not null
      and old.primera_gestion_en is distinct from new.primera_gestion_en)
    or (old.primer_contacto_en is not null
      and old.primer_contacto_en is distinct from new.primer_contacto_en)
  ) then
    raise exception 'Los hitos SLA de asignacion son inmutables' using errcode='55000';
  end if;
  if (new.primera_gestion_en is not null and (
      new.primera_gestion_en<v_asignado_en
      or (v_finalizado_en is not null and new.primera_gestion_en>v_finalizado_en)
    )) or (new.primer_contacto_en is not null and (
      new.primera_gestion_en is null
      or new.primer_contacto_en<new.primera_gestion_en
      or (v_finalizado_en is not null and new.primer_contacto_en>v_finalizado_en)
    )) then
    raise exception 'Hito SLA fuera del episodio de asignacion' using errcode='23514';
  end if;
  return new;
end;
$function$
