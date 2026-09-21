-- Resultado de llamada: seleccionar no equivale a descartar (Miguel, 21/09/2026).
-- Nueva puerta v4; v3 y su nucleo permanecen BYTE A BYTE para clientes/recibos anteriores.
-- V4 compone los writers SLA existentes: actividad, cierre y agenda en una transaccion.
-- La copia versionada del nucleo preserva la semantica legacy sin banderas del cliente.
-- Sin tablas, policies ni datos historicos nuevos. Ningun objeto de public se altera.
-- Reversa: supabase/scripts/resultado-llamada-seguimiento/reversa.sql (conserva los datos).
-- Requiere aprobacion expresa antes de instalar en produccion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
do $preflight$
begin
  perform private.assert_gestion_diaria_resultado();
  if md5(pg_get_functiondef('private.assert_gestion_diaria_resultado()'::regprocedure)) <> '3b0e4ce94cde0ef975e9353aeced036c' then
    raise exception 'El gate F2 cambio: revisar su composicion antes de instalar v4';
  end if;
  if to_regprocedure('crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)') is not null then
    raise exception 'La v4 ya existe: no reinstalar sin verificar su estado';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION private.llamada_registrar_v4(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text, p_detalle text, p_siguiente jsonb, p_tarea_id uuid, p_descartar boolean, p_no_insista boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_tipo text;
  v_motivo text;
  v_descartar boolean := coalesce(p_descartar, false);
  v_no_insista boolean := coalesce(p_no_insista, false);
  v_sig_tipo text;
  v_vence timestamptz;
  v_vence_lima timestamp;
  v_previa jsonb;
  v_resp jsonb;
  v_actividad uuid;
  v_siguiente uuid;
  v_etapa_antes text;
  v_etapa_al_descartar text;
  v_descartado_en timestamptz;
  v_meta jsonb;
  v_n integer;
  v_intentos integer;
  v_tarea_tipo text;
  v_vendedor uuid;
  v_bloqueo jsonb;
  v_guc_previo text := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
begin
  -- ── 1. Validación PURA del input: antes de bloquear ni escribir nada ───────
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  if p_resultado is null or p_resultado not in (
    'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
    'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;

  -- Submotivo: obligatorio en estos resultados, haya seguimiento o descarte;
  -- prohibido en el resto. Elige el motivo REAL del catálogo existente.
  if p_resultado = 'no_interesado' then
    if p_submotivo is null or p_submotivo not in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir', 'otro') then
      raise exception 'Indica por que no le interesa (submotivo)' using errcode = '22023';
    end if;
    v_motivo := case p_submotivo when 'sin_fondos_ahora' then 'sin_fondos'
                                 when 'ya_invirtio_con_otro' then 'competencia'
                                 else 'sin_interes' end;
    -- El resultado no descarta: decide p_descartar (contrato v4).
  elsif p_resultado = 'pide_otro_producto' then
    if p_submotivo is null or p_submotivo not in ('prestamo', 'credito', 'otro') then
      raise exception 'Indica que producto pide (submotivo)' using errcode = '22023';
    end if;
    v_motivo := 'pide_credito';
    -- El resultado no descarta: decide p_descartar (contrato v4).
  elsif p_submotivo is not null then
    raise exception 'El submotivo solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  end if;

  -- Descarte por decisión del analista (decisión #6 de Miguel) o «no responde».
  if v_descartar and p_resultado in ('volver_a_llamar', 'agendo_reunion') then
    raise exception 'Este resultado no descarta al lead' using errcode = '22023';
  end if;
  if v_descartar and p_resultado in ('numero_errado', 'no_es_la_persona') then v_motivo := 'datos_invalidos'; end if;
  if v_descartar and p_resultado = 'no_contesto' then v_motivo := 'no_responde'; end if;
  if v_no_insista and p_resultado not in ('no_interesado', 'pide_otro_producto') then
    raise exception '"No insistir" solo acompana a "no le interesa" o "pide otro producto"' using errcode = '22023';
  end if;

  -- Tarea siguiente: obligatoria en volver_a_llamar (llamada) y agendo_reunion
  -- (reunion); opcional en no_contesto (llamada/whatsapp) y en numero errado /
  -- no es la persona (llamada al 2.º número o reintento); prohibida al descartar.
  if p_siguiente is not null and jsonb_typeof(p_siguiente) <> 'object' then
    raise exception 'La tarea siguiente debe ser un objeto' using errcode = '22023';
  end if;
  v_sig_tipo := p_siguiente->>'tipo';
  if p_siguiente is not null and (v_sig_tipo is null or v_sig_tipo not in ('llamada','whatsapp','reunion','tarea')) then
    raise exception 'Tipo de proxima accion invalido' using errcode = '22023';
  end if;
  if v_no_insista and p_siguiente is not null then
    raise exception 'No volver a contactar impide agendar una proxima accion' using errcode = '22023';
  end if;
  if v_descartar and p_siguiente is not null then
    raise exception 'Un lead descartado no recibe tarea siguiente' using errcode = '22023';
  end if;
  if p_resultado = 'volver_a_llamar' and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
    raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
  elsif p_resultado = 'agendo_reunion' and p_siguiente is not null and v_sig_tipo is distinct from 'reunion' then
    raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
  elsif p_resultado = 'no_contesto' and p_siguiente is not null and v_sig_tipo not in ('llamada', 'whatsapp') then
    raise exception 'Tras un "no contesto" el siguiente paso es una llamada o un WhatsApp' using errcode = '22023';
  elsif p_resultado in ('numero_errado', 'no_es_la_persona') and p_siguiente is not null and v_sig_tipo is distinct from 'llamada' then
    raise exception 'Tras un numero errado el siguiente paso es una llamada' using errcode = '22023';
  end if;
  if p_siguiente is not null then
    begin
      v_vence := (p_siguiente->>'vence_en')::timestamptz;
    exception when others then
      raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
    end;
    if v_vence is null or not pg_catalog.isfinite(v_vence) or v_vence >= timestamptz '2100-01-01Z' then
      raise exception 'Fecha de la tarea siguiente invalida' using errcode = '22023';
    end if;
  end if;

  -- ── 2. Ámbito y candados ANTES de delegar ──────────────────────────────────
  -- Mismo predicado y mismo texto que el writer (no se revela existencia). El
  -- orden es el de la casa: PERSONA (si habrá «No insistir», como hace
  -- crm.marcar_no_contactar) → LEAD → (recibo, tarea), el mismo que ya usan
  -- cerrar_tarea y el trigger serializado; etapa previa y evidencia se leen
  -- bajo el candado del lead.
  if private.sla_gestion_permitida(p_actor, p_lead_id) is distinct from true then
    raise exception 'Gestion no disponible en tu ambito' using errcode = '42501';
  end if;
  if v_no_insista then
    -- Identidad ANTES del lead, como crm.marcar_no_contactar (documento → persona).
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Registrar "No insistir" requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    v_bloqueo := private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select l.etapa, l.vendedor_id into v_etapa_antes, v_vendedor from crm.leads l where l.id = p_lead_id for update;
  -- Tras esperar por el lead, la identidad bloqueada debe seguir siendo la suya
  -- (D-13: documento/persona pudieron cambiar mientras se esperaba) → 40001.
  if v_bloqueo is not null and private.resolver_en_puertas_bajo_candado()
     and not private.lead_dentro_de_bloqueo(p_lead_id, v_bloqueo) then
    raise exception 'La persona del lead cambio mientras se registraba; vuelve a intentarlo' using errcode = '40001';
  end if;

  -- ── 3. ¿Replay? (recibo ya confirmado para este actor y operación) ─────────
  select r.respuesta into v_previa
  from crm.sla_operacion_recibos r
  where r.actor_id = p_actor and r.operacion_id = p_operacion_id;

  if v_previa is null then
    if p_siguiente is not null and v_vendedor is distinct from p_actor then
      raise exception 'Solo el analista dueno del lead puede agendar su proxima accion' using errcode = '42501';
    end if;
    if p_siguiente is not null and exists (select 1 from crm.leads l where l.id = p_lead_id and l.no_contactar) then
      raise exception 'No volver a contactar impide agendar una proxima accion' using errcode = '22023';
    end if;

    -- Lo TEMPORAL se exige solo a una operación nueva: un reintento tardío de
    -- una operación ya confirmada (respuesta perdida) debe recuperar su recibo,
    -- no morir con 22023 por una fecha que ya pasó (Codex, 19/09).
    if v_vence is not null then
      if v_vence <= pg_catalog.clock_timestamp() then
        raise exception 'La tarea siguiente debe ser futura' using errcode = '22023';
      end if;
      -- Ventana legal de contacto (Ley 29571): L–S 07:00–20:00 Lima para llamada y
      -- WhatsApp. Una cita la acuerda el cliente: solo se exige que sea futura.
      if v_sig_tipo in ('llamada', 'whatsapp') then
        v_vence_lima := v_vence at time zone 'America/Lima';
        if extract(isodow from v_vence_lima) = 7
           or v_vence_lima::time < time '07:00' or v_vence_lima::time >= time '20:00' then
          raise exception 'Solo se contacta de lunes a sabado entre 07:00 y 20:00 (Lima)' using errcode = '22023';
        end if;
      end if;
    end if;
    if v_etapa_antes in ('convertido', 'descartado') then
      raise exception 'El lead esta cerrado' using errcode = '22023';
    end if;
    -- La tarea siguiente se exige al DUEÑO del lead («volver a llamar crea la
    -- tarea sola»); un supervisor registra sin agendar: la agenda es del analista.
    if p_siguiente is null and v_vendedor = p_actor then
      if p_resultado = 'volver_a_llamar' then
        raise exception 'Indica cuando volver a llamar (tarea de llamada)' using errcode = '22023';
      elsif p_resultado = 'agendo_reunion' then
        raise exception 'Indica la fecha de la cita (tarea de reunion)' using errcode = '22023';
      end if;
    end if;
    if p_tarea_id is not null then
      -- Solo una tarea de LLAMADA pendiente de este lead: cerrar aquí una cita
      -- como «completada» la degradaría a sin_clasificar y saltaría la entrevista.
      select t.tipo into v_tarea_tipo from crm.tareas t
      where t.id = p_tarea_id and t.lead_id = p_lead_id and t.activo and t.estado = 'pendiente';
      if v_tarea_tipo is null then
        raise exception 'Tarea no encontrada, cerrada o de otro lead' using errcode = '22023';
      end if;
      if v_tarea_tipo <> 'llamada' then
        raise exception 'Solo una tarea de llamada se cierra con el resultado de una llamada' using errcode = '22023';
      end if;
    end if;
  end if;

  -- ── 4. Delegar SIEMPRE en el writer sellado (identidad del recibo, ámbito,
  --      actividad, tarea siguiente, episodio SLA) ─────────────────────────────
  if p_tarea_id is null then
    v_resp := crm.registrar_actividad_v2(p_operacion_id, p_lead_id, v_tipo, p_detalle, p_siguiente);
    v_actividad := p_operacion_id;
  else
    v_resp := crm.cerrar_tarea_v2(p_operacion_id, p_tarea_id, 'completada', v_tipo, p_detalle, p_siguiente, null, null);
    v_actividad := nullif(v_resp->>'actividad_id', '')::uuid;
    if v_actividad is null then
      raise exception 'El cierre de la tarea no dejo actividad de llamada' using errcode = '23514';
    end if;
  end if;
  if coalesce((v_resp->>'ok')::boolean, false) is not true
     or nullif(v_resp->>'lead_id', '')::uuid is distinct from p_lead_id then
    raise exception 'El servidor no confirmo la gestion' using errcode = '23514';
  end if;
  v_siguiente := nullif(v_resp->>'siguiente_id', '')::uuid;

  -- ── 5. Replay: sin escribir nada, el sobre se reconstruye desde la actividad ─
  if v_previa is not null then
    select a.metadata into v_meta from crm.actividades a where a.id = v_actividad;
    -- El recibo del writer no guarda resultado, submotivo, descarte ni «No
    -- insistir»: se comparan aquí con lo persistido (Codex, 19/09).
    if v_meta->>'evento' is distinct from 'resultado_llamada'
       or v_meta->>'resultado' is distinct from p_resultado
       or v_meta->>'submotivo' is distinct from p_submotivo
       or coalesce((v_meta->>'descartado')::boolean, false) is distinct from v_descartar
       or coalesce((v_meta->>'no_insista')::boolean, false) is distinct from v_no_insista then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_resp || pg_catalog.jsonb_build_object(
      'comando', 'registrar_llamada',
      'actividad_id', v_actividad,
      'siguiente_id', nullif(v_meta->>'siguiente_id', '')::uuid,
      'descartado', coalesce((v_meta->>'descartado')::boolean, false),
      'no_insista', coalesce((v_meta->>'no_insista')::boolean, false),
      'resultado', p_resultado,
      'intento_n', (v_meta->>'intento_n')::integer,
      'deshecho', (v_meta ? 'deshecho_en'),
      'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
      'replay', true);
  end if;

  -- ── 6. Primera vez: el resultado en la actividad ───────────────────────────
  -- intento_n = llamadas del lead en el ciclo actual, esta incluida (cardinality(array_agg), nunca la funcion de conteo: censo analitico).
  select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_n
  from crm.actividades a
  where a.lead_id = p_lead_id
    and a.tipo in ('llamada_realizada', 'llamada_no_contestada')
    and a.creado_en >= coalesce(private.inicio_ciclo_lead(p_lead_id), '-infinity'::timestamptz);

  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  update crm.actividades a
     set metadata = a.metadata || pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
       'evento', 'resultado_llamada',
       'resultado', p_resultado,
       'submotivo', p_submotivo,
       'intento_n', v_n,
       'etapa_anterior', v_etapa_antes,
       'siguiente_id', v_siguiente,
       'tarea_id', p_tarea_id,
       'descartado', v_descartar,
       'no_insista', v_no_insista))
   where a.id = v_actividad;
  if not found then
    raise exception 'La actividad de la llamada no existe' using errcode = '23514';
  end if;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);

  -- ── 7. Descarte en la misma operación (hacia el Centro de rescate) ─────────
  if v_descartar then
    if p_resultado = 'no_contesto' then
      -- «No responde» afirma un HECHO: espejo de INTENTOS_MIN_NO_RESPONDE (2) del
      -- front — intentos sin respuesta POSTERIORES a la última conversación,
      -- esta llamada incluida.
      select coalesce(pg_catalog.cardinality(pg_catalog.array_agg(a.id)), 0) into v_intentos
      from crm.actividades a
      where a.lead_id = p_lead_id
        and a.tipo in ('llamada_no_contestada', 'whatsapp_enviado')
        -- Un número errado no es «no responde»: no cuenta como intento sin respuesta.
        and coalesce(a.metadata->>'resultado', '') not in ('numero_errado', 'no_es_la_persona')
        and a.creado_en > coalesce((
          select pg_catalog.max(c.creado_en) from crm.actividades c
          where c.lead_id = p_lead_id
            and c.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')),
          '-infinity'::timestamptz);
      if v_intentos < 2 then
        raise exception '"No responde" exige al menos 2 intentos sin respuesta registrados' using errcode = '22023';
      end if;
    end if;
    select l.etapa into v_etapa_al_descartar from crm.leads l where l.id = p_lead_id;
    -- Las columnas EXACTAS que hoy toca el store (lib/store.tsx descartar):
    -- descartado_en/por los sella trg_leads_zz_sello_descarte; el ledger cierra
    -- el episodio que lee crm.rescate_descartes_mes; las tareas pendientes las
    -- cancela el sistema (trg_leads_sync_tareas).
    update crm.leads
       set etapa = 'descartado', motivo_descarte = v_motivo
     where id = p_lead_id and activo = true and etapa not in ('convertido', 'descartado');
    if not found then
      raise exception 'El lead cambio mientras se registraba; recarga la ficha' using errcode = 'P0409';
    end if;
    select l.descartado_en into v_descartado_en from crm.leads l where l.id = p_lead_id;
    perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
    update crm.actividades a
       set metadata = a.metadata || pg_catalog.jsonb_build_object(
         'etapa_al_descartar', v_etapa_al_descartar,
         'motivo_descarte', v_motivo,
         'descartado_en', v_descartado_en)
     where a.id = v_actividad;
    perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc_previo, true);
  end if;

  -- ── 8. «Pidió que no lo vuelvan a llamar» (Ley 29571): puerta existente ─────
  if v_no_insista then
    perform crm.marcar_no_contactar(p_lead_id, 'Pidio que no lo vuelvan a llamar (resultado de llamada)');
  end if;

  return v_resp || pg_catalog.jsonb_build_object(
    'comando', 'registrar_llamada',
    'actividad_id', v_actividad,
    'siguiente_id', v_siguiente,
    'descartado', v_descartar,
    'no_insista', v_no_insista,
    'resultado', p_resultado,
    'intento_n', v_n,
    'deshecho', false,
    'etapa', (select l.etapa from crm.leads l where l.id = p_lead_id),
    'replay', false);
end;
$function$;

revoke all on function private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean) from public, anon, authenticated, service_role;
comment on function private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean) is 'NUCLEO v4, privado: resultado y submotivo no implican descarte. Descarta solo con p_descartar; conserva agenda, recibo, ambito y candados del writer SLA. No insistir no admite siguiente. V3 conserva su nucleo legacy.';

CREATE OR REPLACE FUNCTION crm.registrar_llamada_v4(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_submotivo text DEFAULT NULL::text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb, p_tarea_id uuid DEFAULT NULL::uuid, p_descartar boolean DEFAULT false, p_no_insista boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
begin
  -- Mismos roles que el writer (sla_ejecutar_comando); el ámbito lo decide el núcleo.
  if v_uid is null or v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_operacion_id is null or p_lead_id is null or p_resultado is null then
    raise exception 'Operacion, lead y resultado son obligatorios' using errcode = '22023';
  end if;
  return private.llamada_registrar_v4(
    v_uid, p_operacion_id, p_lead_id, p_resultado, p_submotivo,
    nullif(pg_catalog.btrim(coalesce(p_detalle, '')), ''),
    p_siguiente, p_tarea_id, coalesce(p_descartar, false), coalesce(p_no_insista, false));
end;
$function$;

revoke all on function crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean) from public, anon, authenticated, service_role;
grant execute on function crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean) to authenticated;
comment on function crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean) is 'PUERTA v4: rol y actor del servidor, resultado tipificado y descarte explicito. Siguiente accion atomica con la llamada. Misma firma de v3 pero sin su descarte automatico; las peticiones v3 pendientes se confirman por v3. DEFINER para componer el nucleo privado, no para ampliar el ambito.';

create function private.assert_gestion_diaria_resultado_v4()
returns text language plpgsql security invoker set search_path = ''
as $function$
declare v_firma text; v_md5 text; v_id oid;
begin
  for v_firma, v_md5 in select * from (values
    ('private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'd6c4407c92e7f38c055653b4a4ead538'),
    ('crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'cbd0a3da63397507c2312d0cf15c0b8c')
  ) as sellos(firma, md5) loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or md5(pg_get_functiondef(v_id)) is distinct from v_md5 then
      raise exception 'Resultado v4: cuerpo ausente o alterado: %', v_firma;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = v_id and p.prosecdef
      and p.proowner = 'postgres'::regrole::oid and p.provolatile = 'v'
      and p.proconfig @> array['search_path=""']) then
      raise exception 'Resultado v4: forma de funcion alterada: %', v_firma;
    end if;
    if exists (select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_id and a.grantee <> 'postgres'::regrole::oid
        and not (v_firma = 'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)' and a.grantee = 'authenticated'::regrole::oid and a.privilege_type = 'EXECUTE' and not a.is_grantable)) then
      raise exception 'Resultado v4: privilegios excesivos: %', v_firma;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'EXECUTE') then
    raise exception 'Resultado v4: falta acceso de authenticated';
  end if;
  return 'OK: resultado v4 — descarte explicito, seguimiento atomico y acceso sellado';
end;
$function$;
revoke all on function private.assert_gestion_diaria_resultado_v4() from public, anon, authenticated, service_role;
comment on function private.assert_gestion_diaria_resultado_v4() is 'Gate de la v4: cuerpos, owner, search_path, volatilidad y ACL. Se ejecuta desde el gate F2, sin sustituir sus controles historicos.';

-- Ampliar F2 conserva TODOS sus sellos y alcanza tambien paraguas F3/F4 futuros.
CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_resultado()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_firma text;
  v_md5 text;
  v_id oid;
begin
  perform private.assert_gestion_diaria_resultado_v4();
  -- 1. Puertas: DEFINER, volátiles, search_path vacío, owner postgres, EXECUTE
  --    exactamente para authenticated.
  foreach v_firma in array array[
    'crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'crm.deshacer_resultado_llamada(uuid)'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.provolatile = 'v'
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Contrato del resultado de llamada alterado (debe ser DEFINER, volatile, search_path vacio): %', v_firma;
    end if;
    if not has_function_privilege('authenticated', v_id, 'EXECUTE')
       or exists (
         select 1 from pg_proc p
         cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
         where p.oid = v_id
           and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
       ) then
      raise exception 'ACL del resultado de llamada alterada: %', v_firma;
    end if;
  end loop;

  -- 2. Núcleo y función del trigger: DEFINER, search_path vacío, owner postgres,
  --    SIN EXECUTE para nadie salvo postgres.
  foreach v_firma in array array[
    'private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',
    'private.trg_actividades_resultado_solo_nucleo()'
  ] loop
    v_id := to_regprocedure(v_firma);
    if v_id is null or not exists (
      select 1 from pg_proc p
      where p.oid = v_id and p.prosecdef
        and p.proowner = 'postgres'::regrole::oid
        and p.proconfig @> array['search_path=""']
    ) then
      raise exception 'Nucleo del resultado de llamada alterado (debe ser DEFINER, search_path vacio): %', v_firma;
    end if;
    if exists (
      select 1 from pg_proc p
      cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
      where p.oid = v_id and a.grantee <> 'postgres'::regrole::oid
    ) then
      raise exception 'El nucleo del resultado de llamada tiene EXECUTE fuera de postgres: %', v_firma;
    end if;
  end loop;

  -- 3. El CHECK de forma, VALIDADO y con el catálogo completo.
  if not exists (
    select 1 from pg_constraint c
    where c.conrelid = 'crm.actividades'::regclass
      and c.conname = 'actividades_resultado_llamada_forma'
      and c.contype = 'c' and c.convalidated
      and strpos(pg_get_constraintdef(c.oid), 'no_contesto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'volver_a_llamar') > 0
      and strpos(pg_get_constraintdef(c.oid), 'agendo_reunion') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_interesado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'numero_errado') > 0
      and strpos(pg_get_constraintdef(c.oid), 'no_es_la_persona') > 0
      and strpos(pg_get_constraintdef(c.oid), 'pide_otro_producto') > 0
      and strpos(pg_get_constraintdef(c.oid), 'submotivo') > 0
      -- La DEFINICIÓN COMPLETA, sellada: un octavo valor conservaría todos los
      -- LIKE de arriba y pasaría (Codex, 19/09). Huella medida en el banco.
      and md5(pg_get_constraintdef(c.oid)) = 'ec46b200b9181592b0f48af06009c4c7'
  ) then
    raise exception 'Falta o cambio el CHECK actividades_resultado_llamada_forma (o no esta validado)';
  end if;

  -- 4. El trigger que veta la falsificación: presente, habilitado, BEFORE
  --    INSERT OR UPDATE OF metadata, con su función.
  if not exists (
    select 1 from pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_00_actividades_resultado_solo_nucleo'
      and t.tgenabled in ('O', 'A')
      and t.tgfoid = to_regprocedure('private.trg_actividades_resultado_solo_nucleo()')
      and pg_get_triggerdef(t.oid) like '%BEFORE INSERT OR UPDATE OF metadata ON crm.actividades FOR EACH ROW%'
  ) then
    raise exception 'Falta, esta deshabilitado o cambio el trigger trg_00_actividades_resultado_solo_nucleo';
  end if;

  -- 5. Los CUERPOS, sellados: los propios (medidos en el banco, dos pasadas) y
  --    los de TODO lo que la v3 compone (texto vivo de producción el 19/09/2026).
  --    Un `create or replace` sobre cualquiera exige re-sellar aquí a conciencia.
  for v_firma, v_md5 in select * from (values
    ('private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'fec6bfd18b0ca26623f84b55daddef64'),
    ('crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)',        '92d2dcfb4cc03c158a42292980226ba2'),
    ('crm.deshacer_resultado_llamada(uuid)',                                                  '5869117e03ac55d699d248244a71bb31'),
    ('private.trg_actividades_resultado_solo_nucleo()',                                       '19952736370f64026f747c19b54ab38e'),
    ('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)',                       '805b3489aeab94371328f28229f23fe5'),
    ('crm.registrar_actividad_v2(uuid,uuid,text,text,jsonb)',                                 '52a44ac20288a9283801a28047efba18'),
    ('crm.cerrar_tarea_v2(uuid,uuid,text,text,text,jsonb,text,text)',                         'f5147d689ec8a213ec9320dad322de4b'),
    ('crm.cerrar_tarea(uuid,text,text,text,jsonb,text,text)',                                 '5396719dc3133e3e658c59c9f63b3530'),
    ('private.sla_ejecutar_comando(uuid,text,uuid,jsonb)',                                    '9f8f1100df419f8d7d70bf4d845adc0d'),
    ('crm.reabrir_lead_fn(uuid)',                                                             '9cdac9e10f2efde549bbcbdf810b95d3'),
    ('crm.marcar_no_contactar(uuid,text)',                                                    '697e0c59f73377b30e7f13340686061c'),
    ('private.trg_gestion_lead_serializada()',                                                '7af0e66b8a4849566e43b514245e1b86'),
    ('private.trg_leads_sync_tareas()',                                                       '6874c23294da0027f25475b4e1fc49d7'),
    ('private.trg_sla_recibo_guard()',                                                        '903e9260918bc7e100bde650d46c1ee4'),
    ('private.trg_leads_cambio_etapa()',                                                      '5e457384188efa3f32cf728d4bc3b2a9'),
    ('private.trg_leads_zz_sello_descarte()',                                                 '150d7ae56bb2094733f7620a1362c29e')
  ) as m(firma, md5) loop
    if to_regprocedure(v_firma) is null
       or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
      raise exception 'El cuerpo de % cambio: re-sellar el resultado de llamada de Gestion Diaria (md5 %)',
        v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
    end if;
  end loop;

  -- 6. El núcleo del historial sigue INVOKER, estable, search_path vacío, con
  --    EXECUTE para authenticated, y entrega metadata.
  v_id := to_regprocedure('private.actividades_de_lead_core(uuid,integer,timestamptz,uuid)');
  if not exists (
    select 1 from pg_proc p
    where p.oid = v_id and not p.prosecdef and p.proowner = 'postgres'::regrole::oid
      and p.provolatile = 's' and p.proconfig @> array['search_path=""']
      and strpos(p.prosrc, 'jsonb_each(pg.metadata) as m(clave, valor)') > 0
  ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
    raise exception 'private.actividades_de_lead_core perdio su forma, su EXECUTE o la metadata del item';
  end if;

  -- 7. Los writers v2 y su mundo, por el gate que ya los sella.
  perform private.assert_sla_comandos();

  return 'OK: resultado de llamada — puertas DEFINER selladas (EXECUTE solo authenticated), nucleo y trigger solo postgres, CHECK de forma validado, trigger anti-falsificacion habilitado, cuerpos propios y compuestos con su md5, historial por lead con metadata';
end;
$function$;

select private.assert_gestion_diaria();
notify pgrst, 'reload schema';
commit;
