CREATE OR REPLACE FUNCTION private.identidad_bloquear_documento(p_tipo text, p_documento text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_norm text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  if v_norm = '' or p_tipo is null then
    return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('inv_resolver:' || p_tipo || ':' || v_norm));
end;
$function$
