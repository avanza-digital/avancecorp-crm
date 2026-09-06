CREATE OR REPLACE FUNCTION private.trg_leads_zz_reapertura_solo_rpc()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  if v_priv or not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  if ((old.etapa = 'descartado' and new.etapa is distinct from 'descartado') or (old.activo = false and new.activo = true))
     and coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, un descarte se reabre solo por sus puertas (tomar, rescatar o deshacer): juzgan a la persona y enlazan el lead'
      using errcode = 'P0409';
  end if;
  return new;
end;
$function$
