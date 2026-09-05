CREATE OR REPLACE FUNCTION crm.convertir_lead(p_lead_id uuid, p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text := private.rol_crm((select auth.uid()));
  v_lead       crm.leads%rowtype;
  v_dni_perfil text;
  v_tipo_perfil text;
  v_asesor     uuid;
  v_flag       boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_inv        uuid;
  v_lead_canon uuid;
  v_clave      text;
  v_hash       text;
  v_prev       jsonb;
  v_res        jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- IDEMPOTENCIA (contrato §8.2, Codex #5): misma clave + mismo payload -> mismo
  -- resultado, sin efectos. Misma clave con otro payload -> P0409.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto, sin idempotencia.)
  if v_flag then
    v_clave := 'conversion:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object('lead', p_lead_id, 'perfil', p_perfil_id));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Con bandera ON el documento del perfil se lee ANTES del lead para tomar la
  -- identidad primero (orden identidad->lead). Con bandera OFF nada de esto corre
  -- y el perfil se lee DESPUÉS del lock del lead (idéntico a hoy, ver más abajo).
  if v_flag then
    select dni, tipo_documento, asesor_perfil_id
      into v_dni_perfil, v_tipo_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
    -- fail-closed (contrato §4.3): sin documento válido no se confirma identidad.
    if v_dni_perfil is null or pg_catalog.btrim(v_dni_perfil) = '' or v_tipo_perfil is null then
      raise exception 'No se puede convertir sin documento valido del cliente'
        using errcode = '22023';
    end if;
    -- Reusar la identidad del perfil si ya existe (una corrección de documento no
    -- parte a la persona); seguir la canónica si esa identidad está fusionada.
    select coalesce(inv.inversionista_canonico_id, inv.id)
      into v_inv
    from crm.inversionistas inv
    where inv.perfil_id = p_perfil_id
    order by (inv.estado <> 'fusionado') desc, inv.creado_en asc
    limit 1;
    -- Si el perfil aún no tiene identidad, EL PUNTO ÚNICO la resuelve/crea
    -- (advisory documental interno + índice único arbitran la carrera).
    if v_inv is null then
      v_inv := private.inversionista_resolver(v_tipo_perfil, v_dni_perfil, true, 'conversion');
    end if;
    -- Serializar por IDENTIDAD, no solo por documento: dos documentos vigentes de
    -- la misma persona convergen en esta fila y aquí se ordenan (Codex #3).
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b5) [Cx-15, E3-1]: una fusión pudo ganar mientras se esperaba este lock: la
    -- perdedora ya no convierte. Sin advisory documental AQUÍ a propósito: tomarlo después
    -- de la identidad invertiría el orden documento -> identidad que sigue la fusión.
    if exists (select 1 from crm.inversionistas i where i.id = v_inv and i.estado = 'fusionado') then
      raise exception 'La persona fue fusionada mientras se convertía; vuelve a intentarlo'
        using errcode = '40001';
    end if;
  end if;

  -- ── LEAD: ámbito + lock, y revalidación tras esperar ─────────────────────
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito (el lead ya se convirtió a ESTE perfil): mismo resultado,
  -- sin efectos. Si la clave no se alcanzó a guardar (caída), se guarda ahora.
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock, INCONDICIONALMENTE (Codex): si otro ya guardó la clave,
    -- se devuelve ESE resultado; si el payload difiere (p.ej. otro perfil para el
    -- mismo lead), idem_leer lanza P0409 aquí, ya serializado — no «lead ya cerrado».
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      -- F2.b (b5) [E3-12]: el resultado guardado se conserva; la identidad se proyecta por su canónica.
      return v_prev || pg_catalog.jsonb_build_object('reintento', true,
        'inversionista_id', private.inversionista_canonica((v_prev->>'inversionista_id')::uuid));
    end if;
    -- Sin clave guardada (conversión previa a este lote) y mismo perfil: mismo hecho.
    if v_lead.perfil_id = p_perfil_id then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', private.inversionista_canonica(v_lead.inversionista_id));
      perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Con bandera OFF: leer el perfil AHORA (tras el lock del lead), IDÉNTICO a la
  -- versión previa (misma precedencia de errores).
  if not v_flag then
    select dni, asesor_perfil_id
      into v_dni_perfil, v_asesor
    from public.perfiles
    where id = p_perfil_id
      and rol = 'cliente'
      and activo = true;
    if not found then
      raise exception 'El cliente destino no existe o no esta activo';
    end if;
  end if;

  if v_lead.dni is not null
     and v_dni_perfil is not null
     and v_lead.dni <> v_dni_perfil then
    raise exception 'El documento del cliente no coincide con el del lead';
  end if;

  if v_rol <> 'gerencia'
     and (
       v_asesor is null
       or v_asesor not in (
         select private.vendedor_ids_visibles((select auth.uid()))
       )
     )
     and not (
       v_lead.dni is not null
       and v_dni_perfil is not null
       and v_lead.dni = v_dni_perfil
     ) then
    raise exception 'Ese cliente no pertenece a tu cartera';
  end if;

  -- Invariante #6 (un solo lead total): si la identidad YA tiene otro lead, esta
  -- persona no puede abrir un segundo. Mensaje de negocio en vez del choque crudo
  -- con leads_inversionista_uidx. (Una nueva inversión sobre el cliente existente
  -- es F5, no una nueva conversión — decisión de Miguel 03/09.)
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon
    from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id
    limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- ── EL CIERRE: etapa + perfil + inversionista_id EN EL MISMO UPDATE ──────
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         perfil_id = p_perfil_id,
         convertido_en = pg_catalog.now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- ── Reconocimiento de identidad (reemplaza al trigger 200000, solo bandera) ─
  if v_flag and v_inv is not null then
    -- Vincular perfil<->identidad y registrar el lead canónico.
    update crm.inversionistas set perfil_id = p_perfil_id
      where id = v_inv and perfil_id is null;
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);

    -- Responsable de relación (asesor del perfil), si está activo y la persona no
    -- tiene tramo abierto. (Lo hacía el trigger 200000:125-131.)
    if v_asesor is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir
                        where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_asesor, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_asesor
        where id = v_inv and responsable_relacion_id is null;
    end if;

    -- no_contactar del lead se centraliza en la persona. (Trigger 200000:134-137.)
    if v_lead.no_contactar then
      update crm.inversionistas
        set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;

    -- El contrato/inversión Avance lo crea su propia puerta (crear_contrato), no
    -- esta función: aquí solo se reconoce la persona (contrato §8.2).
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido a cliente',
    pg_catalog.jsonb_build_object('perfil_id', p_perfil_id),
    v_uid
  );

  v_res := pg_catalog.jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'perfil_id', p_perfil_id,
    'inversionista_id', v_inv
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_avance', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$
