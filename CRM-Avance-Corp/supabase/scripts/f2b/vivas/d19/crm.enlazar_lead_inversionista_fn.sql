CREATE OR REPLACE FUNCTION crm.enlazar_lead_inversionista_fn(p_lead_id uuid, p_inversionista uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_lead0 crm.leads%rowtype; v_lead crm.leads%rowtype; v_cierre crm.cierres_externos%rowtype;
  v_perfil_inv uuid; v_perfil_dni text; v_perfil_tipo text; v_ahora timestamptz; v_veto boolean; v_n_tareas integer := 0;
  v_perfil_completado boolean := false; v_cierre_completado boolean := false; v_op_id uuid;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: enlaza a su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_lead0 from crm.leads where id = p_lead_id;
  if not found then
    raise exception 'El lead no existe' using errcode = 'P0002';
  end if;
  if v_lead0.inversionista_id is not null then
    raise exception 'El lead ya está enlazado a una persona' using errcode = 'P0409';
  end if;
  if v_lead0.dni is null then
    raise exception 'El lead no tiene DNI: solo el documento exacto enlaza (corrige el DNI del lead primero)' using errcode = 'P0409';
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_lead0.dni] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía + Gerencia revalidada -> documento del lead -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona (membresía revalidada)' using errcode = '42501';
  end if;
  perform private.identidad_bloquear_documento('DNI', v_lead0.dni);
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if not private.documento_es_de_identidad(p_inversionista, 'DNI', v_lead0.dni) then
    if private.inversionista_por_documento('DNI', v_lead0.dni) is not null then
      raise exception 'El DNI del lead pertenece a otra persona reconocida: fusiona o corrige primero' using errcode = 'P0409';
    end if;
    raise exception 'El DNI del lead no es un documento vigente y verificado de esta persona: corrige el documento primero' using errcode = 'P0409';
  end if;
  if exists (select 1 from private.leads_de_identidades(array[p_inversionista]) x where x <> p_lead_id) then
    raise exception 'La persona ya tiene su lead (enlace vivo o puente, activo o no): reconciliación de clase E hasta F5' using errcode = 'P0409';
  end if;
  -- unión de enlaces del lead [E3-10]: perfil (FOR SHARE, por DOCUMENTO) -> cierre (por DOCUMENTO) -> puente -> tareas -> lead -> reservas -> claim
  if v_lead0.perfil_id is not null then
    select p.dni, p.tipo_documento into v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_lead0.perfil_id for share;
    select i.id into v_perfil_inv from crm.inversionistas i where i.perfil_id = v_lead0.perfil_id and i.estado <> 'fusionado' limit 1;
    if v_perfil_inv is not null and v_perfil_inv <> p_inversionista then
      raise exception 'El perfil de cliente del lead pertenece a otra persona reconocida: reconciliación (fusión/corrección)' using errcode = 'P0409';
    end if;
    if v_perfil_inv is null then
      if v_inv.perfil_id is not null and v_inv.perfil_id <> v_lead0.perfil_id then
        raise exception 'La persona ya tiene otro perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)' using errcode = 'P0409';
      end if;
      if not private.documento_es_de_identidad(p_inversionista, v_perfil_tipo, v_perfil_dni) then
        raise exception 'El documento del perfil de cliente del lead no es de esta persona: corrige el documento primero' using errcode = 'P0409';
      end if;
    end if;
  end if;
  select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id for update;
  if v_cierre.id is not null then
    if v_cierre.inversionista_id is not null and v_cierre.inversionista_id <> p_inversionista then
      raise exception 'El cierre del lead pertenece a otra persona reconocida: reconciliación' using errcode = 'P0409';
    end if;
    if v_cierre.inversionista_id is null and not private.documento_es_de_identidad(p_inversionista, v_cierre.documento_tipo, v_cierre.documento) then
      raise exception 'El documento del cierre del lead no es de esta persona: reconciliación documental primero' using errcode = 'P0409';
    end if;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and il.inversionista_id <> p_inversionista) then
    raise exception 'El puente del lead apunta a otra persona: reconciliación' using errcode = 'P0409';
  end if;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = p_lead_id order by t.id for update;
  perform private.bloquear_leads_nowait(array[p_lead_id]);
  select * into v_lead from crm.leads where id = p_lead_id;
  if v_lead.inversionista_id is not null or v_lead.perfil_id is distinct from v_lead0.perfil_id or v_lead.dni is distinct from v_lead0.dni then
    raise exception 'El lead cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id
              and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and v_lead.etapa <> 'convertido'))
              and (r.inversionista_id is null or r.inversionista_id <> p_inversionista)) then
    raise exception 'El lead tiene una reserva de conversión viva o sellada (de otra persona o sin persona): termina o deja caducar' using errcode = 'P0409';
  end if;
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de enlazar' using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_inv.no_contactar or v_lead.no_contactar;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set inversionista_id = p_inversionista where id = p_lead_id;   -- el trigger zz escribe el puente canónico si no existe
  if v_lead0.perfil_id is not null and v_inv.perfil_id is null then
    update crm.inversionistas set perfil_id = v_lead0.perfil_id where id = p_inversionista;
    v_perfil_completado := true;
  end if;
  if v_cierre.id is not null and v_cierre.inversionista_id is null then
    update crm.cierres_externos set inversionista_id = p_inversionista where id = v_cierre.id;
    v_cierre_completado := true;
  end if;
  if v_veto and not v_inv.no_contactar then
    update crm.inversionistas set no_contactar = true, no_contactar_en = v_ahora, no_contactar_por = v_uid where id = p_inversionista;
  end if;
  if v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(p_lead_id);
    update crm.leads set no_contactar = true where id = p_lead_id;
  end if;
  insert into crm.inversionista_operaciones (tipo, inversionista_id, lead_id, motivo, detalle, por)
  values ('enlace', p_inversionista, p_lead_id, p_motivo,
          pg_catalog.jsonb_build_object('perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado,
                                        'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'lead_activo', v_lead.activo), v_uid)
  returning id into v_op_id;
  if v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Lead enlazado a una persona reconocida (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'operacion_id', v_op_id, 'inversionista_id', p_inversionista, 'veto', v_veto),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', p_inversionista, 'operacion_id', v_op_id,
    'perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado, 'veto', v_veto, 'tareas_canceladas', v_n_tareas);
end;
$function$
