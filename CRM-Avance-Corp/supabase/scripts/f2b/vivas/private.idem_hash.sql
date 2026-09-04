CREATE OR REPLACE FUNCTION private.idem_hash(p_payload jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_payload::text, 'utf8')), 'hex')
$function$

