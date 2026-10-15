CREATE OR REPLACE FUNCTION private.potencial_evento_inmutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  raise exception 'El historial de potencial no se modifica ni se borra' using errcode = 'P0409';
end;
$function$
