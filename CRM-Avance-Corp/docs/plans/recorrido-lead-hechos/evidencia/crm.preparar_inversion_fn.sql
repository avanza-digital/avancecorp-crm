CREATE OR REPLACE FUNCTION crm.preparar_inversion_fn(p_clave uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: el flujo de Cartera y de conversión de siempre, sin llaves.
  return private.inversion_preparar_nucleo(p_clave, p_datos, 'cartera', null::uuid, null::text);
end;
$function$
