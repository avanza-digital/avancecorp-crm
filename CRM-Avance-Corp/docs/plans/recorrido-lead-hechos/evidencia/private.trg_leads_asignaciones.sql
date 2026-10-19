CREATE OR REPLACE FUNCTION private.trg_leads_asignaciones()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_evento_en timestamptz;
  v_actor uuid;
  v_movimiento text := 'sin_cambio';
  v_abierto crm.lead_asignaciones%rowtype;
  v_hay_abierto boolean := false;
  v_old_debe_tener boolean := false;
  v_new_debe_tener boolean;
  v_entra_terminal boolean := false;
  v_reabierto boolean := false;
  v_reactivado boolean := false;
  v_motivo_apertura text;
  v_motivo_cierre text;
  v_episodio_n integer;
  v_abiertos integer;
  v_analista_abierto uuid;
begin
  v_new_debe_tener := new.activo = true
    and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and new.vendedor_id is not null;

  if tg_op = 'INSERT' then
    v_evento_en := new.creado_en;
    v_actor := coalesce(auth.uid(), new.creado_por);

    if v_new_debe_tener then
      perform set_config('crm.ledger_writer', 'on', true);
      insert into crm.lead_asignaciones (
        lead_id,
        ciclo_n,
        episodio_n,
        analista_id,
        motivo_apertura,
        asignado_en,
        asignado_por,
        monto_estimado,
        moneda,
        origen,
        categoria_interes
      )
      values (
        new.id,
        new.ciclo_actual,
        1,
        new.vendedor_id,
        'ingreso',
        v_evento_en,
        v_actor,
        new.monto_estimado,
        new.moneda,
        new.origen,
        new.categoria_interes
      );
      perform set_config('crm.ledger_writer', 'off', true);
    end if;
  else
    v_evento_en := statement_timestamp();
    v_actor := auth.uid();
    v_movimiento := private.clasificar_movimiento_tenencia(
      old.vendedor_id,
      new.vendedor_id,
      old.asignado_supervisor_id,
      new.asignado_supervisor_id
    );
    v_old_debe_tener := old.activo = true
      and old.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and old.vendedor_id is not null;
    v_entra_terminal := old.etapa not in ('convertido', 'descartado')
      and new.etapa in ('convertido', 'descartado');
    v_reabierto := old.etapa = 'descartado' and new.etapa = 'nuevo';
    v_reactivado := old.activo = false and new.activo = true;

    select la.*
      into v_abierto
    from crm.lead_asignaciones la
    where la.lead_id = new.id
      and la.finalizado_en is null
    for update;
    v_hay_abierto := found;

    if v_old_debe_tener and not v_hay_abierto then
      raise exception 'Invariante rota: falta el episodio abierto del lead %', new.id;
    end if;
    if v_old_debe_tener and v_abierto.analista_id is distinct from old.vendedor_id then
      raise exception 'Invariante rota: el episodio abierto no coincide con el analista del lead %', new.id;
    end if;
    if not v_old_debe_tener and v_hay_abierto then
      raise exception 'Invariante rota: existe un episodio abierto fuera de tenencia operativa para %', new.id;
    end if;

    if v_hay_abierto
       and (
         new.vendedor_id is distinct from old.vendedor_id
         or not v_new_debe_tener
       ) then
      v_motivo_cierre := case
        when v_entra_terminal then new.etapa
        when old.activo = true and new.activo = false then 'desactivado'
        when v_movimiento = 'transferido' then 'transferido'
        when v_movimiento in ('parqueado', 'sin_asignar') then 'parqueado'
        else null
      end;

      if v_motivo_cierre is null then
        raise exception 'No se pudo clasificar el cierre del episodio del lead %', new.id;
      end if;

      perform set_config('crm.ledger_writer', 'on', true);
      update crm.lead_asignaciones
      set finalizado_en = v_evento_en,
          finalizado_por = v_actor,
          motivo_cierre = v_motivo_cierre,
          analista_destino_id = case
            when v_motivo_cierre = 'transferido' then new.vendedor_id
            else null
          end,
          supervisor_destino_id = case
            when v_motivo_cierre = 'parqueado' then new.asignado_supervisor_id
            else null
          end,
          resultado = case
            when v_motivo_cierre in ('convertido', 'descartado') then v_motivo_cierre
            else null
          end,
          resultado_en = case
            when v_motivo_cierre in ('convertido', 'descartado') then v_evento_en
            else null
          end,
          motivo_descarte_cierre = case
            when v_motivo_cierre = 'descartado' then new.motivo_descarte
            else null
          end
      where id = v_abierto.id;
      perform set_config('crm.ledger_writer', 'off', true);
      v_hay_abierto := false;
    end if;

    if v_new_debe_tener
       and (
         not v_old_debe_tener
         or new.vendedor_id is distinct from old.vendedor_id
       ) then
      v_motivo_apertura := case
        when v_reabierto then 'reabierto'
        when v_reactivado then 'reactivado'
        when v_movimiento = 'transferido' then 'reasignado'
        else 'asignado'
      end;

      select coalesce(max(la.episodio_n), 0) + 1
        into v_episodio_n
      from crm.lead_asignaciones la
      where la.lead_id = new.id
        and la.ciclo_n = new.ciclo_actual;

      perform set_config('crm.ledger_writer', 'on', true);
      insert into crm.lead_asignaciones (
        lead_id,
        ciclo_n,
        episodio_n,
        analista_id,
        motivo_apertura,
        asignado_en,
        asignado_por,
        supervisor_origen_id,
        monto_estimado,
        moneda,
        origen,
        categoria_interes
      )
      values (
        new.id,
        new.ciclo_actual,
        v_episodio_n,
        new.vendedor_id,
        v_motivo_apertura,
        v_evento_en,
        v_actor,
        old.asignado_supervisor_id,
        new.monto_estimado,
        new.moneda,
        new.origen,
        new.categoria_interes
      );
      perform set_config('crm.ledger_writer', 'off', true);
    end if;
  end if;

  select count(*), (array_agg(la.analista_id))[1]
    into v_abiertos, v_analista_abierto
  from crm.lead_asignaciones la
  where la.lead_id = new.id
    and la.finalizado_en is null;

  if v_new_debe_tener
     and (v_abiertos <> 1 or v_analista_abierto is distinct from new.vendedor_id) then
    raise exception 'Invariante rota: el lead % debe terminar con un episodio abierto', new.id;
  end if;
  if not v_new_debe_tener and v_abiertos <> 0 then
    raise exception 'Invariante rota: el lead % no debe terminar con episodio abierto', new.id;
  end if;

  return new;
end;
$function$
