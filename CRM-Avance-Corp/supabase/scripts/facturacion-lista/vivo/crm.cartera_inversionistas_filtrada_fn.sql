CREATE OR REPLACE FUNCTION crm.cartera_inversionistas_filtrada_fn(p_pagina integer DEFAULT 1, p_tamano integer DEFAULT 25, p_texto text DEFAULT ''::text, p_empresa text DEFAULT NULL::text, p_responsable uuid DEFAULT NULL::uuid, p_sin_responsable boolean DEFAULT false, p_mes text DEFAULT NULL::text, p_moneda text DEFAULT NULL::text, p_estado text DEFAULT NULL::text, p_contacto text DEFAULT NULL::text, p_por_vencer boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.cartera_f5_listar(p_pagina,p_tamano,p_texto,p_empresa,p_responsable,
    p_sin_responsable,p_mes,p_moneda,p_estado,p_contacto,p_por_vencer);
$function$
