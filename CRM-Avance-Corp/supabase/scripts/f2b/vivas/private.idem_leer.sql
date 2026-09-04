CREATE OR REPLACE FUNCTION private.idem_leer(p_clave text, p_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_res  jsonb;
  v_hash text;
begin
  select resultado, hash_payload into v_res, v_hash
  from crm.multiempresa_idempotencia
  where clave = p_clave;
  if not found then
    return null;
  end if;
  if v_hash <> p_hash then
    raise exception 'La misma operacion llego con datos distintos; no se puede reintentar asi'
      using errcode = 'P0409';
  end if;
  return v_res;
end;
$function$

