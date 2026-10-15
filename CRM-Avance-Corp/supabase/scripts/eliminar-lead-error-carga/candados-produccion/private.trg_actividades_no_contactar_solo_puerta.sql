CREATE OR REPLACE FUNCTION private.trg_actividades_no_contactar_solo_puerta()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_exento boolean := false;
  v_veto boolean := false;
begin
  -- B6c: la nota del veto (metadata evento = no_contactar) es la fuente de la marca que la base para gestión muestra a
  -- Supervisión y Gerencia (cuándo, motivo, quién). Solo la escriben sus puertas, bajo la válvula de transacción
  -- crm.op_privilegiada = on (marcar_no_contactar, levantar_no_contactar y postventa_veto_fn), y no se cambia ni se borra.
  if (select auth.uid()) is null then
    v_exento := true;  -- sin usuario (migraciones, backfills, service_role sin sub), como los otros sellos de crm.actividades
  elsif coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    v_exento := true;  -- la válvula de las puertas del veto
  end if;
  if not v_exento then
    if tg_op <> 'DELETE' then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(new.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if tg_op <> 'INSERT' and not v_veto then
      v_veto := pg_catalog.lower(pg_catalog.btrim(coalesce(old.metadata->>'evento', ''), E' \t\r\n')) = 'no_contactar';
    end if;
    if v_veto then
      raise exception 'La nota de No contactar solo la escriben sus puertas (marcar, levantar o postventa); no se cambia ni se borra'
        using errcode = '42501';
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$
