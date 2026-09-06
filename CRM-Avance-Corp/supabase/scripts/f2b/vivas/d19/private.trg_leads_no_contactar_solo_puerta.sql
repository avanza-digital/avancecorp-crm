CREATE OR REPLACE FUNCTION private.trg_leads_no_contactar_solo_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;  -- bandera apagada: comportamiento de hoy
  end if;
  if new.no_contactar is distinct from old.no_contactar
     and coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') <> 'on' then
    raise exception 'No contactar se cambia solo por su puerta (marcar_no_contactar / levantar_no_contactar)'
      using errcode = '42501';
  end if;
  return new;
end;
$function$
