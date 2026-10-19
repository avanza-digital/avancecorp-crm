CREATE OR REPLACE FUNCTION private.conversion_lead_con_inversion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.etapa='convertido' and old.etapa<>'convertido' then
    if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
      raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
    end if;
    if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
      where s.lead_origen_id=new.id and s.estado='confirmada'
        and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
      raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
    end if;
  end if;
  return new;
end $function$
