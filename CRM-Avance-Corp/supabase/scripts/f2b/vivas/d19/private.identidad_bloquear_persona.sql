CREATE OR REPLACE FUNCTION private.identidad_bloquear_persona(p_tipo text, p_documento text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_inv uuid;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  v_inv := private.inversionista_por_documento(p_tipo, p_documento);
  if v_inv is null then
    return;
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
end;
$function$
