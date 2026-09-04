CREATE OR REPLACE FUNCTION private.idem_guardar(p_clave text, p_tipo text, p_hash text, p_resultado jsonb, p_por uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_n integer;
begin
  -- Atómico y CONFLICTIVO: la misma clave solo acepta el MISMO tipo+hash; el primer
  -- resultado gana (nunca se sobrescribe). Otra combinación = P0409 (Codex).
  insert into crm.multiempresa_idempotencia (clave, tipo, hash_payload, resultado, creado_por)
  values (p_clave, p_tipo, p_hash, p_resultado, p_por)
  on conflict (clave) do update
    set resultado = coalesce(crm.multiempresa_idempotencia.resultado, excluded.resultado)
    where crm.multiempresa_idempotencia.hash_payload = excluded.hash_payload
      and crm.multiempresa_idempotencia.tipo = excluded.tipo;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'La misma operacion llego con datos distintos; no se puede reintentar asi'
      using errcode = 'P0409';
  end if;
end;
$function$

