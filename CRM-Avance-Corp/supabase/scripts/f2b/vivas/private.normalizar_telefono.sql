CREATE OR REPLACE FUNCTION private.normalizar_telefono(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p is null or btrim(p) = '' then p
    when length(regexp_replace(p, '[^0-9]', '', 'g')) = 9
      then '+51' || regexp_replace(p, '[^0-9]', '', 'g')
    when regexp_replace(p, '[^0-9]', '', 'g') ~ '^51[0-9]{9}$'
      then '+' || regexp_replace(p, '[^0-9]', '', 'g')
    else '+' || regexp_replace(p, '[^0-9]', '', 'g')
  end;
$function$

