CREATE OR REPLACE FUNCTION crm.corregir_documento_inversionista_fn(p_inversionista uuid, p_tipo text, p_documento text, p_motivo text, p_identificador_anterior uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_tipo text; v_norm text;
  v_inv crm.inversionistas%rowtype; v_old_id uuid; v_old_tipo text; v_old_norm text; v_n integer; v_otro uuid; v_ahora timestamptz;
  v_perfil_id uuid; v_perfil_dni text; v_perfil_tipo text; v_lead crm.leads%rowtype; v_new_id uuid; v_op_id uuid;
  v_perfil_res text; v_lead_res text; v_k text; v_docs text[]; v_reusa boolean := false;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  v_tipo := pg_catalog.upper(pg_catalog.btrim(coalesce(p_tipo, '')));
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido' using errcode = '22023';
  end if;
  if (v_tipo = 'DNI' and v_norm !~ '^[0-9]{8}$')
     or (v_tipo = 'CE' and v_norm !~ '^[0-9]{9,12}$')
     or (v_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: corrige en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  -- El identificador que sale, leído SIN lock (solo para calcular los advisories); se revalida bajo la identidad [E3-5].
  -- La unicidad «único de su tipo» solo se exige cuando NO se indica cuál sale [E3-15].
  if p_identificador_anterior is not null then
    select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
    from crm.inversionista_identificadores d
    where d.id = p_identificador_anterior and d.inversionista_id = p_inversionista and d.estado = 'vigente';
    if v_old_id is null then
      raise exception 'El identificador anterior no es un documento vigente de esta persona' using errcode = 'P0409';
    end if;
  else
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n > 1 then
      raise exception 'La persona tiene varios documentos vigentes de tipo %: indica cuál sustituir (p_identificador_anterior)', v_tipo using errcode = '22023';
    elsif v_n = 1 then
      select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
      from crm.inversionista_identificadores d
      where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    end if;
  end if;
  if v_old_tipo = v_tipo and v_old_norm = v_norm then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
  end if;
  perform private.motivo_sin_documento(p_motivo, array[v_norm, v_old_norm] || coalesce((select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista), '{}'));

  -- jerarquía [E3-2] + Gerencia revalidada -> advisories de viejo y nuevo, ordenados -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona (membresía revalidada)' using errcode = '42501';
  end if;
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct k from unnest(array[v_tipo || ':' || v_norm, v_old_tipo || ':' || v_old_norm]) k where k is not null) s;
  foreach v_k in array v_docs loop
    perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
  end loop;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se corregía (estado %); vuelve a intentarlo', v_inv.estado using errcode = '40001';
  end if;
  if v_old_id is not null then
    if not exists (select 1 from crm.inversionista_identificadores d where d.id = v_old_id and d.inversionista_id = p_inversionista
                     and d.estado = 'vigente' and d.tipo_documento = v_old_tipo and d.documento_normalizado = v_old_norm) then
      raise exception 'El documento de la persona cambió mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  if p_identificador_anterior is null then
    select count(*) into v_n from crm.inversionista_identificadores d
    where d.inversionista_id = p_inversionista and d.tipo_documento = v_tipo and d.estado = 'vigente';
    if v_n <> (case when v_old_id is null then 0 else 1 end) then
      raise exception 'Los documentos de la persona cambiaron mientras se corregía; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  -- el nuevo, ¿ya es vigente de alguien?
  select d.inversionista_id, d.id into v_otro, v_new_id from crm.inversionista_identificadores d
  where d.tipo_documento = v_tipo and d.documento_normalizado = v_norm and d.estado = 'vigente';
  if v_otro is not null and v_otro <> p_inversionista then
    raise exception 'El documento pertenece a otra persona reconocida: fusiona las identidades en vez de corregir' using errcode = 'P0409';
  end if;
  if v_otro = p_inversionista then
    if v_old_id is null then
      return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
    end if;
    v_reusa := true;   -- [E3-15] el destino ya es un vigente propio (p. ej. tras una fusión): sale el anterior y se reutiliza
  else
    v_new_id := null;
  end if;
  -- alta/conversión en curso [E3-7]: claim y reservas (por persona O por lead) bajo lock
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- perfil enlazado FOR UPDATE (escribe) -> cierres -> tareas -> lead (NOWAIT) -> reservas -> contactos -> terceros
  if v_inv.perfil_id is not null then
    select p.id, p.dni, p.tipo_documento into v_perfil_id, v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_inv.perfil_id for update;
  end if;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id = p_inversionista or ce.lead_id in (select private.leads_de_identidades(array[p_inversionista]))
   order by ce.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente'
     and t.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by t.id for update;
  perform private.bloquear_leads_nowait(coalesce((select pg_catalog.array_agg(x) from private.leads_de_identidades(array[p_inversionista]) x), '{}'));
  select * into v_lead from crm.leads l where l.inversionista_id = p_inversionista order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])) order by r.lead_id for update;
  if exists (select 1 from crm.conversion_reservas r left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id = p_inversionista or r.lead_id in (select private.leads_de_identidades(array[p_inversionista])))
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    raise exception 'Hay una reserva de conversión viva o sellada sin convertir (por persona o por lead): termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- contactos (último recurso del orden) ANTES de mirar a terceros [E3-6]: el trigger los retoma reentrante
  if v_lead.id is not null then
    perform private.bloquear_contactos_lead(array[v_lead.telefono], array[v_lead.dni, case when v_tipo = 'DNI' then v_norm end]);
  else
    perform private.bloquear_contactos_lead(array[]::text[], array[case when v_tipo = 'DNI' then v_norm end]);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  if exists (select 1 from public.perfiles pp
              where pp.rol = 'cliente'
                and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(pp.dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_norm
                and coalesce(nullif(pg_catalog.btrim(pp.tipo_documento), ''), 'DNI') = v_tipo
                and pp.id is distinct from v_inv.perfil_id) then
    raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id
                                  and l.activo = true and l.etapa not in ('convertido', 'descartado')) then
    raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and exists (select 1 from crm.leads l where l.dni = v_norm and l.id is distinct from v_lead.id and l.inversionista_id is not null
                                  and l.inversionista_id <> p_inversionista) then
    raise exception 'Otro lead enlazado a otra persona lleva ese DNI: fusiona o corrige ese lead primero' using errcode = 'P0409';
  end if;
  -- [auditor M2] lo que la excepción del trigger deja de comprobar: OTRO lead con ese DNI vetado o en enfriamiento congela el
  -- documento (el veto de la PROPIA persona no cuenta: corregir su documento es justamente lo que Gerencia está haciendo).
  if v_tipo = 'DNI' and exists (
       select 1 from crm.leads l
       left join crm.enfriamiento_politica ep on ep.motivo = l.motivo_descarte
       where l.dni = v_norm and l.id is distinct from v_lead.id
         and (l.inversionista_id is null or l.inversionista_id <> p_inversionista)
         and (l.no_contactar
              or (l.etapa = 'descartado' and l.descartado_en is not null and coalesce(ep.dias, 0) > 0
                  and l.descartado_en + pg_catalog.make_interval(days => ep.dias) > pg_catalog.now()))) then
    raise exception 'Ese DNI está congelado por un veto o un enfriamiento vigente en otro lead: revisión de Gerencia' using errcode = 'P0409';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  perform pg_catalog.set_config('crm.correccion_documento', 'on', true);   -- [auditor M1] la excepción del trigger la exige
  if v_old_id is not null then
    update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = v_ahora where id = v_old_id;
  end if;
  if not v_reusa then
    insert into crm.inversionista_identificadores
      (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
    values (p_inversionista, v_tipo, v_norm, p_documento, 'vigente', true, 'correccion', v_ahora, v_uid)
    returning id into v_new_id;
  else
    -- [Codex B3] el destino reutilizado queda VERIFICADO con la misma política de la corrección
    update crm.inversionista_identificadores set verificado = true, fuente = coalesce(fuente, 'correccion') where id = v_new_id and verificado = false;
  end if;
  v_perfil_res := case when v_inv.perfil_id is null then 'ninguno' else 'sin_cambio' end;
  if v_perfil_id is not null and v_old_id is not null
     and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_perfil_dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_old_norm
     and coalesce(nullif(pg_catalog.btrim(v_perfil_tipo), ''), 'DNI') = v_old_tipo then
    begin
      update public.perfiles set dni = v_norm, tipo_documento = v_tipo where id = v_perfil_id;
    exception when unique_violation then
      raise exception 'Otro cliente del Portal lleva ese documento: revisión o fusión de Gerencia' using errcode = 'P0409';
    end;
    v_perfil_res := 'actualizado';
  end if;
  v_lead_res := case when v_lead.id is null then 'sin_lead' else 'sin_cambio' end;
  if v_lead.id is not null and v_old_id is not null and v_old_tipo = 'DNI' and v_lead.dni = v_old_norm then
    if v_tipo = 'DNI' then
      begin
        update crm.leads set dni = v_norm where id = v_lead.id;
      exception when unique_violation then
        raise exception 'Otro lead vivo lleva ese DNI: fusiona o descarta ese lead primero' using errcode = 'P0409';
      end;
      v_lead_res := 'dni';
    else
      update crm.leads set dni = null where id = v_lead.id;
      v_lead_res := 'nulo';
    end if;
  end if;
  insert into crm.inversionista_operaciones
    (tipo, inversionista_id, lead_id, identificador_anterior_id, identificador_nuevo_id, motivo, detalle, por)
  values ('correccion', p_inversionista, v_lead.id, v_old_id, v_new_id, p_motivo,
          pg_catalog.jsonb_build_object('tipo_documento', v_tipo, 'perfil', v_perfil_res, 'lead', v_lead_res, 'reutilizado', v_reusa), v_uid)
  returning id into v_op_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Documento corregido por Gerencia (' || v_tipo || ')',
            pg_catalog.jsonb_build_object('evento', 'correccion_documento', 'operacion_id', v_op_id,
                                          'inversionista_id', p_inversionista, 'lead', v_lead_res),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.correccion_documento', 'off', true);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'corregido', 'inversionista_id', p_inversionista,
    'operacion_id', v_op_id, 'identificador_nuevo_id', v_new_id, 'identificador_anterior_id', v_old_id,
    'reutilizado', v_reusa, 'perfil', v_perfil_res, 'lead', v_lead_res);
end;
$function$
