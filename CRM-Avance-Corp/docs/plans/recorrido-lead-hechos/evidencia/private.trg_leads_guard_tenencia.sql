CREATE OR REPLACE FUNCTION private.trg_leads_guard_tenencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_rol_actor text;
  v_entra_terminal boolean;
begin
  if new.vendedor_id is not null and new.asignado_supervisor_id is not null then
    raise exception 'Un lead no puede tener analista y bandeja al mismo tiempo';
  end if;

  -- Solo un miembro plenamente activo puede recibir responsabilidad nueva.
  if new.vendedor_id is not null
     and (
       tg_op = 'INSERT'
       or new.vendedor_id is distinct from old.vendedor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.vendedor_id,
       array['vendedor', 'supervisor']::text[]
     ) then
    raise exception 'El analista destino no existe, no esta activo o no puede recibir leads';
  end if;

  -- Una bandeja pertenece exclusivamente a un supervisor plenamente activo.
  if new.asignado_supervisor_id is not null
     and (
       tg_op = 'INSERT'
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
       or (old.activo = false and new.activo = true)
       or (
         old.etapa in ('convertido', 'descartado')
         and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
       )
     )
     and not private.es_destino_crm_activo(
       new.asignado_supervisor_id,
       array['supervisor']::text[]
     ) then
    raise exception 'La bandeja destino no pertenece a un supervisor activo';
  end if;

  -- Un usuario CRM no gerencial no puede liberar un lead a la cola global.
  if new.vendedor_id is null
     and new.asignado_supervisor_id is null
     and (
       tg_op = 'INSERT'
       or old.vendedor_id is not null
       or old.asignado_supervisor_id is not null
     )
     and auth.uid() is not null then
    v_rol_actor := private.rol_crm(auth.uid());
    if v_rol_actor is distinct from 'gerencia' then
      raise exception 'Solo Gerencia puede dejar un lead en la cola global';
    end if;
  end if;

  if tg_op = 'INSERT' then
    new.creado_en := statement_timestamp();
    new.actualizado_en := new.creado_en;
    new.ciclo_actual := 1;
    return new;
  end if;

  new.ciclo_actual := old.ciclo_actual;

  if old.etapa = 'convertido' and new.etapa is distinct from old.etapa then
    raise exception 'Un lead convertido no se puede reabrir';
  end if;

  if old.etapa = 'descartado' and new.etapa is distinct from old.etapa then
    if new.etapa <> 'nuevo' then
      raise exception 'Un lead descartado solo se puede reabrir en etapa nuevo';
    end if;
    new.ciclo_actual := old.ciclo_actual + 1;
  end if;

  v_entra_terminal := old.etapa not in ('convertido', 'descartado')
    and new.etapa in ('convertido', 'descartado');

  if v_entra_terminal
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Asigna al responsable antes de cerrar el lead';
  end if;

  if v_entra_terminal and old.activo = false then
    raise exception 'Reactiva el lead antes de cerrarlo';
  end if;

  if v_entra_terminal and old.activo = true and new.activo = false then
    raise exception 'Cierra o desactiva el lead en operaciones separadas';
  end if;

  if old.etapa <> 'convertido' and new.etapa = 'convertido'
     and old.vendedor_id is null then
    raise exception 'Asigna un analista antes de convertir el lead';
  end if;

  if old.activo = true and new.activo = false
     and (
       new.vendedor_id is distinct from old.vendedor_id
       or new.asignado_supervisor_id is distinct from old.asignado_supervisor_id
     ) then
    raise exception 'Reasigna o desactiva el lead en operaciones separadas';
  end if;

  return new;
end;
$function$
