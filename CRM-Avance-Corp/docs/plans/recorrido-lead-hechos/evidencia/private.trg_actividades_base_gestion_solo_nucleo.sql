CREATE OR REPLACE FUNCTION private.trg_actividades_base_gestion_solo_nucleo()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_meta jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  if (select auth.uid()) is null then
    return new;  -- migraciones y jobs internos, como el trigger «solo núcleo» del resultado de llamada
  end if;
  if coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off') = 'on' then
    return new;
  end if;
  if v_meta ? 'respuesta' or v_meta->>'evento' in ('intento_base', 'reactivacion_base') or v_meta->>'via' = 'base_gestion' then
    raise exception 'Las actividades de la base para gestion solo las escribe su nucleo' using errcode = '42501';
  end if;
  return new;
end;
$function$
