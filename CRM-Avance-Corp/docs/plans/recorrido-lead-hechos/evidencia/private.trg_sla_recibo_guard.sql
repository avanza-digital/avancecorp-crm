CREATE OR REPLACE FUNCTION private.trg_sla_recibo_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'DELETE' then
    -- Única excepción: la vía oficial crm.eliminar_lead_error_carga, y solo para una fila ya copiada en
    -- crm.leads_eliminados en ESTA transacción (ver private.borrado_lead_error_autoriza).
    if private.borrado_lead_error_autoriza(tg_table_name, pg_catalog.to_jsonb(old)) then return old; end if;
  end if;
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'Los recibos de gestion no se borran' using errcode='55000';
  end if;
  if tg_op='UPDATE' and (old.respuesta is not null or new.respuesta is null
      or (to_jsonb(new)-'respuesta'-'confirmado_en') is distinct from
         (to_jsonb(old)-'respuesta'-'confirmado_en')) then
    raise exception 'El recibo solo puede confirmarse una vez' using errcode='55000';
  end if;
  return new;
end;
$function$
