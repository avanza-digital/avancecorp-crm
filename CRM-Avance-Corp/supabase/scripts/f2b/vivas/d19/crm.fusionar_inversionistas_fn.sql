CREATE OR REPLACE FUNCTION crm.fusionar_inversionistas_fn(p_perdedora uuid, p_canonica uuid, p_motivo text, p_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_row crm.inversionistas%rowtype;
  v_lead crm.leads%rowtype; v_leads uuid[]; v_docs text[]; v_docs2 text[]; v_bloq text[]; v_foto jsonb; v_ahora timestamptz;
  v_veto boolean; v_tramo_p crm.inversionista_responsables%rowtype; v_tramo_c crm.inversionista_responsables%rowtype;
  v_t crm.inversion_titulares%rowtype; v_t2 crm.inversion_titulares%rowtype; v_fusion_id uuid; v_impacto jsonb;
  v_n_ident integer := 0; v_n_cierres integer := 0; v_n_inv integer := 0; v_n_tit integer := 0;
  v_perfiles_fusion uuid[] := '{}';        -- F2.b [D-18] (N6): perfiles cliente de las dos personas (tareas de cliente)
  v_n_tareas_cliente integer := 0;         -- F2.b [D-18] (N6)
  v_n_tit_dup integer := 0; v_n_res integer := 0; v_n_pred integer := 0; v_n_tareas integer := 0; v_n_puente integer := 0;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_perdedora is null or p_canonica is null or p_perdedora = p_canonica then
    raise exception 'Indica dos identidades distintas' using errcode = '22023';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Falta la huella de la previsualización (p_hash)' using errcode = '22023';
  end if;

  -- 1. jerarquía compartida [E3-2] y Gerencia REVALIDADA bajo ella -> 2. documentos vigentes de ambas (sin lock, ordenados)
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades (membresía revalidada)' using errcode = '42501';
  end if;
  v_docs := private.identidad_bloquear_documentos_de(array[p_perdedora, p_canonica]);
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica)));
  -- 3. identidades FOR UPDATE por id ascendente (P, C y las predecesoras de P: el aplanado no espera después de las reservas [E3-12])
  for v_row in select * from crm.inversionistas where id in (p_perdedora, p_canonica) order by id for update loop
    if v_row.id = p_perdedora then v_p := v_row; else v_c := v_row; end if;
  end loop;
  if v_p.id is null or v_c.id is null then
    raise exception 'Alguna de las identidades no existe' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.inversionista_canonico_id = p_perdedora and i.id not in (p_perdedora, p_canonica) order by i.id for update;
  select pg_catalog.array_agg(k order by k) into v_docs2
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica) and d.estado = 'vigente') s;
  if coalesce(v_docs2, '{}') is distinct from v_docs then
    raise exception 'Los documentos de la persona cambiaron mientras se esperaba; vuelve a previsualizar' using errcode = '40001';
  end if;
  -- 4. perfiles FOR SHARE (directos y de los leads [Codex B1]) -> 5. cierres -> 6. inversiones/titulares -> 7. tramos -> 8. tareas -> 9. leads (NOWAIT) -> 10. reservas -> 11. claims
  v_leads := coalesce((select pg_catalog.array_agg(x order by x) from private.leads_de_identidades(array[p_perdedora, p_canonica]) x), '{}');
  perform 1 from public.perfiles p
   where p.id in (v_p.perfil_id, v_c.perfil_id) or p.id in (select l.perfil_id from crm.leads l where l.id = any(v_leads))
   order by p.id for share;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id in (p_perdedora, p_canonica) or ce.lead_id = any(v_leads)
   order by ce.id for update;
  perform 1 from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica) order by i.id for update;
  perform 1 from crm.inversion_titulares t
   where t.inversionista_id in (p_perdedora, p_canonica)
      or t.inversion_id in (select i.id from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica))
   order by t.id for update;
  perform 1 from crm.inversionista_responsables r where r.inversionista_id in (p_perdedora, p_canonica) and r.hasta is null order by r.id for update;
  -- F2.b [D-18] (N6): también las tareas de CLIENTE de las dos personas (por su perfil), que hasta ahora quedaban
  -- vivas cuando la fusión heredaba el veto. Mismo criterio que D-3 y mismo orden (tareas → leads).
  v_perfiles_fusion := array(
    select x from (
      select v_p.perfil_id as x
      union select v_c.perfil_id
      -- Mismo criterio que D-3: el perfil cliente que lleva el documento exacto de la persona, aunque la identidad
      -- lo tenga en NULL (el backfill de F2 deja perfil_id NULL justo cuando otra identidad ya reclamó ese perfil,
      -- que es el caso típico de una fusión). Y el perfil del lead, que el FOR SHARE de arriba ya bloquea.
      union select p.id from public.perfiles p
             where p.rol = 'cliente'
               and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
               and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' ||
                    pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      union select l.perfil_id from crm.leads l where l.id = any(v_leads)
    ) s where s.x is not null order by 1);
  perform 1 from crm.tareas t
   where t.estado = 'pendiente'
     and (t.lead_id = any(v_leads) or (v_perfiles_fusion <> '{}' and t.perfil_id = any(v_perfiles_fusion)))
   order by t.id for update;
  perform private.bloquear_leads_nowait(v_leads);
  select * into v_lead from crm.leads l where l.id = any(v_leads) order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id in (p_perdedora, p_canonica) or r.lead_id = any(v_leads)
   order by r.lead_id for update;
  perform 1 from crm.multiempresa_idempotencia m
   where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text) order by m.clave for update;
  -- 12. huella y bloqueos bajo los locks [E3-4]
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  if private.idem_hash(v_foto) <> p_hash then
    raise exception 'La previsualización caducó (la foto cambió): vuelve a previsualizar' using errcode = 'P0409';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  if pg_catalog.cardinality(v_bloq) > 0 then
    raise exception 'Fusión no viable: %', pg_catalog.array_to_string(v_bloq, ' · ') using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  v_veto := v_p.no_contactar or v_c.no_contactar or coalesce(v_lead.no_contactar, false);

  -- 13. hechos bajo la válvula, en este orden
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = p_canonica, fusionado_en = v_ahora where id = p_perdedora;
  update crm.inversionistas set inversionista_canonico_id = p_canonica where inversionista_canonico_id = p_perdedora and id <> p_canonica;
  get diagnostics v_n_pred = row_count;
  if v_c.perfil_id is null and v_p.perfil_id is not null then
    update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_canonica;
  end if;
  if v_veto and not v_c.no_contactar then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(v_p.no_contactar_en, v_ahora),
           no_contactar_por = coalesce(v_p.no_contactar_por, v_uid)
     where id = p_canonica;
  end if;
  select * into v_tramo_p from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tramo_c from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tramo_p.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo_p.id;
    if v_tramo_c.id is null then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
      values (p_canonica, v_tramo_p.responsable_id, v_ahora, 'fusion', v_uid);
      update crm.inversionistas set responsable_relacion_id = v_tramo_p.responsable_id where id = p_canonica;
    end if;
  end if;
  update crm.inversionista_identificadores d set estado = 'historico', vigente_hasta = v_ahora
   where d.inversionista_id = p_perdedora and d.estado = 'vigente';
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
  select p_canonica, d.tipo_documento, d.documento_normalizado, d.documento_original, 'vigente', d.verificado, 'fusion', v_ahora, v_uid
  from crm.inversionista_identificadores d
  where d.inversionista_id = p_perdedora and d.estado = 'historico' and d.vigente_hasta = v_ahora
  order by d.id;
  get diagnostics v_n_ident = row_count;
  -- lead (enlace vivo) y TODO el puente de P (incluidos históricos del backfill)
  if v_lead.id is not null and v_lead.inversionista_id = p_perdedora then
    update crm.leads set inversionista_id = p_canonica where id = v_lead.id;
  end if;
  update crm.inversionista_leads set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_puente = row_count;
  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;
  -- F2.b [D-18] (N6): la fusión que hereda el veto cancela TAMBIÉN las tareas de cliente de las dos personas; si no,
  -- la ficha del cliente seguía con seguimientos pendientes de alguien a quien no se debe contactar. Se marca como
  -- cancelación del sistema (misma marca que usa D-3) para que el trigger de tareas no la trate como cierre humano.
  if v_veto and v_perfiles_fusion <> '{}' then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t set estado = 'cancelada'
     where t.estado = 'pendiente' and t.perfil_id = any(v_perfiles_fusion);
    get diagnostics v_n_tareas_cliente = row_count;
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;
  update crm.cierres_externos ce set inversionista_id = p_canonica
   where ce.inversionista_id = p_perdedora
      or (v_lead.id is not null and v_lead.inversionista_id = p_perdedora and ce.lead_id = v_lead.id and ce.inversionista_id is null);
  get diagnostics v_n_cierres = row_count;
  update crm.inversiones set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_inv = row_count;
  for v_t in select * from crm.inversion_titulares where inversionista_id = p_perdedora order by id loop
    v_t2 := null;
    select * into v_t2 from crm.inversion_titulares where inversion_id = v_t.inversion_id and inversionista_id = p_canonica;
    if v_t2.id is not null then
      delete from crm.inversion_titulares where id = v_t.id;
      if v_t.rol = 'principal' and v_t2.rol <> 'principal' then
        update crm.inversion_titulares set rol = 'principal' where id = v_t2.id;
      end if;
      v_n_tit_dup := v_n_tit_dup + 1;
    else
      update crm.inversion_titulares set inversionista_id = p_canonica where id = v_t.id;
      v_n_tit := v_n_tit + 1;
    end if;
  end loop;
  update crm.conversion_reservas set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_res = row_count;
  v_impacto := pg_catalog.jsonb_build_object('lead_id', v_lead.id, 'lead_reapuntado', v_lead.id is not null and v_lead.inversionista_id = p_perdedora,
    'puente', v_n_puente, 'identificadores_reemitidos', v_n_ident, 'tramo_cerrado', v_tramo_p.id, 'tramo_heredado', v_tramo_c.id is null and v_tramo_p.id is not null,
    'perfil_heredado', v_c.perfil_id is null and v_p.perfil_id is not null, 'veto', v_veto, 'tareas_canceladas', v_n_tareas, 'tareas_cliente_canceladas', v_n_tareas_cliente,
    'cierres', v_n_cierres, 'inversiones', v_n_inv, 'titulares', v_n_tit, 'titulares_duplicados_eliminados', v_n_tit_dup,
    'reservas', v_n_res, 'predecesoras_aplanadas', v_n_pred, 'hash', p_hash);
  insert into crm.inversionista_fusiones (canonico_id, fusionado_id, motivo, impacto, por)
  values (p_canonica, p_perdedora, p_motivo, v_impacto, v_uid) returning id into v_fusion_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Fusión de identidades (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'fusion', 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'fusion_id', v_fusion_id, 'canonico_id', p_canonica, 'fusionado_id', p_perdedora, 'impacto', v_impacto);
end;
$function$
