CREATE OR REPLACE FUNCTION private.verificar_disponibilidad_lead_impl(p_telefono text, p_dni text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.verificar_disponibilidad_lead_impl(
    p_telefono,
    p_dni,
    null::uuid
  );
$function$

