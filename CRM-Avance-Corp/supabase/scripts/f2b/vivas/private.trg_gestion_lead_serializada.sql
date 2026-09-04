CREATE OR REPLACE FUNCTION private.trg_gestion_lead_serializada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_autorizado boolean := false;
begin
  -- Los writers internos (auth.uid NULL) y los eventos de sistema ya tienen
  -- sus propios gates. No deben quedar atrapados al dispararse desde un UPDATE
  -- del lead que ya posee el lock.
  if v_actor is null
     or (
       tg_table_name = 'actividades'
       and new.tipo in ('cambio_etapa', 'reasignacion', 'conversion')
     ) then
    return new;
  end if;

  -- `crm.tareas` también admite tareas de perfil sin lead; no participan en
  -- una devolución y conservan su policy existente.
  if new.lead_id is null then
    return new;
  end if;

  -- `creado_en` no es inmutable durante INSERT en las tablas heredadas. Un
  -- asesor podría enviar una fecha anterior a la asignación y hacer invisible
  -- su gestión para el candado de devolución. Los inserts manuales reciben un
  -- sello del servidor; writers internos con auth.uid NULL conservan backfill.
  -- Se preservan antes los contratos heredados de NOT NULL/fecha finita: el
  -- sello no debe convertir un payload imposible en una escritura válida.
  if new.creado_en is null then
    raise exception 'La fecha de creación de la gestión es obligatoria'
      using errcode = '23502';
  end if;
  if not pg_catalog.isfinite(new.creado_en) then
    raise exception 'La fecha de creación de la gestión debe ser finita'
      using errcode = '23514';
  end if;

  if new.creado_por is distinct from v_actor then
    raise exception 'La gestión debe quedar atribuida al usuario autenticado'
      using errcode = '42501';
  end if;

  v_rol := private.rol_crm(v_actor);
  select true
    into v_autorizado
  from crm.leads lead
  where lead.id = new.lead_id
    and lead.activo = true
    and (
      v_rol = 'gerencia'
      or lead.vendedor_id = v_actor
      or (
        v_rol = 'supervisor'
        and (
          lead.vendedor_id in (
            select private.vendedor_ids_visibles(v_actor)
          )
          or (
            lead.vendedor_id is null
            and lead.asignado_supervisor_id in (
              select private.vendedor_ids_visibles(v_actor)
            )
          )
        )
      )
    )
  for update;

  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;

  -- El sello se toma DESPUÉS del lock y de la revalidación. `statement_timestamp`
  -- conservaría la hora previa a una espera: si una derivación ganara durante
  -- esa espera, la gestión podría quedar fechada antes del episodio y el
  -- supervisor aún la vería como reversible. `clock_timestamp` registra el
  -- orden causal ya serializado por el lock.
  new.creado_en := pg_catalog.clock_timestamp();

  return new;
end;
$function$

