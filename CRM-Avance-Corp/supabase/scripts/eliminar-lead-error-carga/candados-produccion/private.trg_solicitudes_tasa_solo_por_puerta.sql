CREATE OR REPLACE FUNCTION private.trg_solicitudes_tasa_solo_por_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Una solicitud de tasa no se borra: queda como historia' using errcode = 'P0409';
  end if;
  if coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off') <> 'on' then
    raise exception 'Una solicitud de tasa solo cambia por sus puertas (crm.*_tasa_fn)' using errcode = 'P0409';
  end if;
  new.actualizado_en := statement_timestamp();
  return new;
end;
$function$
