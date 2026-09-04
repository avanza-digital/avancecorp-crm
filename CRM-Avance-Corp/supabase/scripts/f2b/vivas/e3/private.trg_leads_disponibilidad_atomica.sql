CREATE OR REPLACE FUNCTION private.trg_leads_disponibilidad_atomica()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_disponibilidad jsonb;
  v_cambio_identidad boolean;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_descartado_por text;
begin
  if tg_op = 'UPDATE' then
    if new.telefono is distinct from old.telefono then
      new.telefono := private.normalizar_telefono(new.telefono);
      if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'Telefono invalido';
      end if;
    end if;

    if new.dni is distinct from old.dni then
      new.dni := nullif(pg_catalog.btrim(new.dni), '');
      if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
        raise exception using errcode = '22023', message = 'DNI invalido';
      end if;
    end if;

    v_cambio_identidad := new.telefono is distinct from old.telefono
      or new.dni is distinct from old.dni;

    perform private.bloquear_contactos_lead(
      array[old.telefono, new.telefono],
      array[old.dni, new.dni]
    );

    if not v_cambio_identidad or v_actor is null then
      return new;
    end if;

    v_rol := private.rol_crm(v_actor);
    if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
      raise exception using errcode = '42501', message = 'Acceso CRM revocado';
    end if;

    -- Excluir OLD al validar el destino es correcto para un lead operativo,
    -- pero no debe permitir «mover» un No contactar o un enfriamiento y dejar
    -- libre la identidad anterior. Ambos vetos propios congelan teléfono y DNI
    -- mientras sigan vigentes; levantarlos es una operación separada y auditable.
    if old.no_contactar = true then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = pg_catalog.jsonb_build_object('estado', 'no_contactar')::text;
    end if;

    if old.etapa = 'descartado'
       and old.descartado_en is not null
       and old.motivo_descarte is not null then
      select
        ep.dias,
        old.descartado_en + pg_catalog.make_interval(days => ep.dias),
        p.nombre_completo
      into v_dias, v_disponible_desde, v_descartado_por
      from crm.enfriamiento_politica ep
      left join public.perfiles p on p.id = old.descartado_por
      where ep.motivo = old.motivo_descarte;

      if coalesce(v_dias, 0) > 0
         and v_disponible_desde > pg_catalog.now() then
        raise exception using
          errcode = 'P0481',
          message = 'Contacto no disponible',
          detail = pg_catalog.jsonb_build_object(
            'estado', 'enfriamiento',
            'motivo_descarte', old.motivo_descarte,
            'disponible_desde', v_disponible_desde,
            'descartado_por', v_descartado_por
          )::text;
      end if;
    end if;

    v_disponibilidad := private.verificar_disponibilidad_lead_impl(
      new.telefono,
      new.dni,
      old.id
    );
    if v_disponibilidad ->> 'estado' is distinct from 'libre' then
      raise exception using
        errcode = 'P0481',
        message = 'Contacto no disponible',
        detail = v_disponibilidad::text;
    end if;
    return new;
  end if;

  new.telefono := private.normalizar_telefono(new.telefono);
  new.dni := nullif(pg_catalog.btrim(new.dni), '');

  if new.telefono is null or new.telefono !~ '^\+519[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'Telefono invalido';
  end if;
  if new.dni is not null and new.dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'DNI invalido';
  end if;

  perform private.bloquear_contactos_lead(array[new.telefono], array[new.dni]);

  -- Un escritor interno sin sesion humana se serializa, pero conserva su
  -- contrato especializado (por ejemplo crm-importar-leads con service_role).
  if v_actor is null then
    return new;
  end if;

  v_rol := private.rol_crm(v_actor);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La compatibilidad temporal es solo para el alta que ya hacía el bundle
  -- anterior. No abre una vía para fabricar leads terminales o inactivos.
  if new.activo is distinct from true
     or new.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead debe nacer activo y en etapa operativa';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(new.telefono, new.dni);
  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    raise exception using
      errcode = 'P0481',
      message = 'Contacto no disponible',
      detail = v_disponibilidad::text;
  end if;

  return new;
end;
$function$

