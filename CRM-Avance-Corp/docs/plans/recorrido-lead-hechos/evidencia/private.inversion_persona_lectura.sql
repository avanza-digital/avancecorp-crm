CREATE OR REPLACE FUNCTION private.inversion_persona_lectura(p_persona uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: la regla vive en el núcleo _para; sin llaves, conducta idéntica a la anterior.
  return private.inversion_persona_lectura_para(p_persona, null::uuid, null::uuid);
end;
$function$
