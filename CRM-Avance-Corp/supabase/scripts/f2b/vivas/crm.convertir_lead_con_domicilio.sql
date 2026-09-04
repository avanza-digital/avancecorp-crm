CREATE OR REPLACE FUNCTION crm.convertir_lead_con_domicilio(p_lead_id uuid, p_perfil_id uuid, p_domicilio text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_domicilio text;
  v_resultado jsonb;
  v_accion text := 'conservado';
begin
  -- Se valida ANTES de convertir: si falla, todavia no se ha escrito nada.
  v_domicilio := crm.normalizar_domicilio_legal(p_domicilio);

  v_resultado := crm.convertir_lead(p_lead_id, p_perfil_id);

  update public.perfiles
     set domicilio = v_domicilio
   where id = p_perfil_id
     and rol = 'cliente'
     and domicilio is null;
  if found then v_accion := 'completado'; end if;

  return v_resultado || jsonb_build_object('domicilio_accion', v_accion);
end;
$function$

