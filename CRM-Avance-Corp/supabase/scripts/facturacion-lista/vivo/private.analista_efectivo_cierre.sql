CREATE OR REPLACE FUNCTION private.analista_efectivo_cierre(p_cierre_externo_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_analista uuid;
  v_responsable uuid;
begin
  select ce.vendedor_id, persona.responsable_relacion_id
    into v_analista, v_responsable
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  left join crm.inversionistas persona on persona.id = coalesce(ce.inversionista_id, l.inversionista_id)
  where ce.id = p_cierre_externo_id;
  if private.analista_dado_de_baja(v_analista) is not true then
    return v_analista;
  end if;
  return private.heredero_de_baja(v_analista, v_responsable);
end;
$function$
