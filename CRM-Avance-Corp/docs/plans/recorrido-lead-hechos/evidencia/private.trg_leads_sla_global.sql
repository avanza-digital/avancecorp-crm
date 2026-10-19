CREATE OR REPLACE FUNCTION private.trg_leads_sla_global()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  if tg_op = 'INSERT' then
    if new.creado_en is null then
      raise exception 'No existe timestamp de ingreso para iniciar el SLA global';
    end if;
    new.sla_global_iniciado_en := new.creado_en;
    new.sla_global_aproximado := false;
    return new;
  end if;

  if new.ciclo_actual is distinct from old.ciclo_actual then
    if new.ciclo_actual <> old.ciclo_actual + 1 then
      raise exception 'Transicion de ciclo invalida para el SLA global';
    end if;
    new.sla_global_iniciado_en := statement_timestamp();
    new.sla_global_aproximado := false;
  else
    new.sla_global_iniciado_en := old.sla_global_iniciado_en;
    new.sla_global_aproximado := old.sla_global_aproximado;
  end if;

  return new;
end;
$function$
