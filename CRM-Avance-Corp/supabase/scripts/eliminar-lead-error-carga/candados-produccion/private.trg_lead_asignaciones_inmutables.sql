CREATE OR REPLACE FUNCTION private.trg_lead_asignaciones_inmutables()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'DELETE' then
    raise exception 'Los episodios de asignacion no se eliminan';
  end if;

  if coalesce(current_setting('crm.ledger_writer', true), 'off') <> 'on'
     or pg_trigger_depth() < 2 then
    raise exception 'El ledger solo se escribe desde el movimiento del lead';
  end if;

  if tg_op = 'INSERT' then
    return new;
  end if;

  if old.finalizado_en is not null then
    raise exception 'Un episodio cerrado es inmutable';
  end if;

  if old.id is distinct from new.id
     or old.lead_id is distinct from new.lead_id
     or old.ciclo_n is distinct from new.ciclo_n
     or old.episodio_n is distinct from new.episodio_n
     or old.analista_id is distinct from new.analista_id
     or old.motivo_apertura is distinct from new.motivo_apertura
     or old.asignado_en is distinct from new.asignado_en
     or old.asignado_por is distinct from new.asignado_por
     or old.supervisor_origen_id is distinct from new.supervisor_origen_id
     or old.monto_estimado is distinct from new.monto_estimado
     or old.moneda is distinct from new.moneda
     or old.origen is distinct from new.origen
     or old.categoria_interes is distinct from new.categoria_interes
     or old.aproximado is distinct from new.aproximado
     or old.creado_en is distinct from new.creado_en then
    raise exception 'La fotografia de un episodio es inmutable';
  end if;

  if new.finalizado_en is null or new.motivo_cierre is null then
    raise exception 'La unica actualizacion valida del ledger es su cierre completo';
  end if;

  return new;
end;
$function$
