CREATE OR REPLACE FUNCTION crm.fijar_dni_lead_fn(p_lead_id uuid, p_dni text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_lead crm.leads%rowtype; v_inv uuid; v_v jsonb; v_previo text; v_k text; v_claves text[] := '{}';
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
begin
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'Acceso CRM revocado' using errcode = '42501';
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception 'El DNI debe tener exactamente 8 digitos' using errcode = '22023';
  end if;
  -- Ámbito ANTES de cualquier candado (auditor v4 M1): un lead ajeno o inexistente muere aquí sin sondear a nadie.
  if not exists (select 1 from crm.leads l
                  where l.id = p_lead_id and l.activo = true
                    and (v_rol = 'gerencia'
                         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_flag then
    -- Candados del documento ANTERIOR y del nuevo, en orden de texto (Codex v4.1): una toma o reapertura en vuelo que
    -- bloqueó el documento anterior termina antes de que este cambio lo deje obsoleto; y quien llegue después ve el nuevo.
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    for v_k in select k from (select l.dni as k from crm.leads l where l.id = p_lead_id and l.dni is not null
                              union select v_dni where v_dni is not null) s order by k loop
      perform private.identidad_bloquear_documento('DNI', v_k);
      v_claves := v_claves || v_k;
    end loop;
    if v_dni is not null then
      v_inv := private.inversionista_por_documento('DNI', v_dni);
      if v_inv is not null then
        perform 1 from crm.inversionistas i where i.id = v_inv for share;
      end if;
    end if;
  end if;
  select * into v_lead
  from crm.leads l
  where l.id = p_lead_id and l.activo = true
    and (v_rol = 'gerencia'
         or l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
         or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.dni is not distinct from v_dni then
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'sin_cambios', true);
  end if;
  if v_flag then
    -- Codex v4.3 [1]: si la bandera se apagó en medio, los candados de documento fueron no-ops: no se escribe con una lista vacía.
    if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
      raise exception 'La identidad unificada se apagó durante la operación; vuelve a intentarlo' using errcode = '40001';
    end if;
    -- El documento anterior ACTUAL debe ser uno de los bloqueados (Codex v4.2: otra llamada pudo cambiarlo mientras se esperaba).
    if v_lead.dni is not null and not (v_lead.dni = any(v_claves)) then
      raise exception 'El documento de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    if v_lead.inversionista_id is not null or exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id) then
      raise exception 'El documento de un lead ya reconocido solo lo corrige Gerencia (corrección de documento)' using errcode = 'P0409';
    end if;
    if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))) then
      raise exception 'Este lead tiene una conversión en curso: no se cambia su documento' using errcode = 'P0409';
    end if;
    if v_inv is not null then
      v_v := private.juicio_persona(v_inv, p_lead_id);
      if v_v is not null then
        if v_v->>'estado' = 'no_contactar' then
          raise exception 'La persona de ese documento tiene la restricción «No insistir»' using errcode = 'P0429';
        end if;
        raise exception 'La persona de ese documento ya es cliente o ya tiene su lead: no se puede asignar a este'
          using errcode = 'P0409', detail = v_v::text;
      end if;
    end if;
  end if;
  v_previo := coalesce(pg_catalog.current_setting('crm.dni_por_puerta', true), 'off');
  perform pg_catalog.set_config('crm.dni_por_puerta', 'on', true);
  update crm.leads set dni = v_dni where id = p_lead_id;
  perform pg_catalog.set_config('crm.dni_por_puerta', v_previo, true);
  if v_flag and v_inv is not null then
    perform private.enlazar_lead_reabierto(p_lead_id, v_inv);
  end if;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'dni', v_dni,
    'inversionista_id', case when v_flag then v_inv end, 'enlazado', v_flag and v_inv is not null);
end;
$function$

