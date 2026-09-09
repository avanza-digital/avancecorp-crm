-- Reversa SOLO antes del primer uso. Con solicitudes previas se conserva historial y se corrige hacia delante.
begin;
set local lock_timeout='5s';
lock table crm.solicitudes_tasa,crm.conversion_reservas in access exclusive mode;
do $$ begin
 if exists(select 1 from crm.solicitudes_tasa where lead_id is not null)
   or exists(select 1 from crm.conversion_reservas where condiciones_tasa is not null) then
   raise exception 'La funcionalidad ya tiene datos. No se permite borrar su historial ni las reservas.';
 end if;
end $$;

CREATE OR REPLACE FUNCTION crm.convertir_lead(p_lead_id uuid, p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text := private.rol_crm((select auth.uid()));
  v_lead       crm.leads%rowtype;
  v_dni_perfil text;
  v_tipo_perfil text;
  v_asesor     uuid;
  v_flag       boolean := private.resolver_en_puertas_bajo_candado();
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
  -- F2.b [D-18] (Codex #3 del bloque 2): el tramo de responsable se abre con el asesor del perfil «si está activo»,
  -- y eso se leía sin candado: una baja de analista en vuelo (crm.fijar_membresia_activa_fn, que toma el interlock
  -- EXCLUSIVO de jerarquía) podía cerrarle sus tramos mientras esta conversión le abría uno nuevo. Se toma el
  -- interlock COMPARTIDO al ENTRAR —antes de cualquier candado de negocio, el mismo orden que el offboarding:
  -- jerarquía → documento → persona → lead, así que no hay ciclo— y más abajo se revalida `activo` bajo él.
  -- Solo con la bandera ENCENDIDA: es el único caso en que se abre el tramo de responsable (más abajo, bajo
  -- `if v_flag and v_inv is not null`). Apagada, tomarlo haría esperar a TODA conversión detrás de cualquier
  -- titular del exclusivo (offboarding, RPC de jerarquía, alta de vendedor) sin ganar nada (auditor D-18 #2).
  if v_flag then
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
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
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento de un perfil
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cliente: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #2): una reserva viva o sellada de ESTE lead pertenece a UNA persona (b4): no se convierte para otra
  -- por la puerta directa; el cierre de la saga trae la misma persona y pasa.
  if v_flag and exists (select 1 from crm.conversion_reservas r
                         where r.lead_id = p_lead_id and r.inversionista_id is not null
                           and r.inversionista_id is distinct from v_inv
                           and (r.efectos_iniciados_en is not null or r.expira_en > pg_catalog.now())) then
    raise exception 'Este lead está reservado para otra persona: espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex v3 B4): una conversión Avance en curso en OTRO lead de la misma persona (reserva viva o sellada)
  -- también rechaza la puerta directa, como ya hace convertir_lead_externo; el cierre de la saga trae su propio lead y pasa.
  if v_flag and v_inv is not null and private.persona_en_conversion(v_inv, p_lead_id) then
    raise exception 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead' using errcode = 'P0409';
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
       -- F2.b [D-18]: bajo el interlock compartido de jerarquía tomado al entrar, y con la fila del equipo FOR SHARE:
       -- si el analista se está dando de baja, o esta conversión espera a que termine, o la baja espera a ésta.
       and exists (select 1 from crm.equipo e where e.perfil_id = v_asesor and e.activo for share of e)
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
;
CREATE OR REPLACE FUNCTION crm.historial_decisiones_tasa_gerencia_fn(p_periodo_dias integer DEFAULT 30, p_decision text DEFAULT NULL::text, p_busqueda text DEFAULT NULL::text, p_limite integer DEFAULT 10, p_cursor_resuelta_en timestamp with time zone DEFAULT NULL::timestamp with time zone, p_cursor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_limite integer := least(greatest(coalesce(p_limite, 10), 1), 25);
  v_periodo integer := coalesce(p_periodo_dias, 30);
  v_busqueda text := nullif(left(btrim(coalesce(p_busqueda, '')), 100), '');
begin
  if v_uid is null or private.rol_crm(v_uid) is distinct from 'gerencia' then raise exception 'Solo Gerencia consulta su historial de decisiones de tasa' using errcode = '42501'; end if;
  if v_periodo not in (0, 7, 30, 90) then raise exception 'Período inválido' using errcode = '22023'; end if;
  if p_decision is not null and p_decision not in ('aprobada', 'aprobada_con_tope', 'rechazada') then raise exception 'Decisión inválida' using errcode = '22023'; end if;
  if (p_cursor_resuelta_en is null) <> (p_cursor_id is null) then raise exception 'Cursor incompleto' using errcode = '22023'; end if;

  return (
    with resueltas as (
      select s.*,
        case when s.tasa_maxima_autorizada is null then 'rechazada' when s.tasa_maxima_autorizada = s.tasa_solicitada then 'aprobada' else 'aprobada_con_tope' end as decision_gerencia,
        case when s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista') and s.vence_en < statement_timestamp() then 'vencida' else s.estado end as estado_actual,
        coalesce(cl.nombre_completo, 'Cliente') as cliente_nombre, coalesce(so.nombre_completo, 'Sin nombre') as solicitante_nombre,
        coalesce(re.nombre_completo, 'Gerencia') as resolutor_nombre, c.numero_contrato as contrato_numero, p.version as politica_version
      from crm.solicitudes_tasa s
      left join public.perfiles cl on cl.id = s.cliente_id
      left join public.perfiles so on so.id = s.solicitada_por
      left join public.perfiles re on re.id = s.resuelta_por
      left join public.contratos c on c.id = s.contrato_id
      left join crm.politica_rentabilidad p on p.id = s.politica_id
      where s.resuelta_por = v_uid and s.resuelta_en is not null
    ), filtradas as (
      select r.* from resueltas r
      where (v_periodo = 0 or r.resuelta_en >= statement_timestamp() - make_interval(days => v_periodo))
        and (p_decision is null or r.decision_gerencia = p_decision)
        and (v_busqueda is null or r.cliente_nombre ilike '%' || v_busqueda || '%' or r.solicitante_nombre ilike '%' || v_busqueda || '%')
    ), pagina_mas_uno as (
      select f.* from filtradas f where p_cursor_resuelta_en is null or (f.resuelta_en, f.id) < (p_cursor_resuelta_en, p_cursor_id)
      order by f.resuelta_en desc, f.id desc limit v_limite + 1
    ), pagina as (
      select p.* from pagina_mas_uno p order by p.resuelta_en desc, p.id desc limit v_limite
    )
    select jsonb_build_object(
      'version', 1, 'total', (select count(*) from filtradas),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'decision', x.decision_gerencia, 'estado_actual', x.estado_actual, 'categoria', x.categoria,
        'cliente_nombre', x.cliente_nombre, 'contrato_origen_numero', x.contrato_origen_numero, 'contrato_numero', x.contrato_numero,
        'capital', x.capital, 'moneda', x.moneda, 'modalidad', x.modalidad, 'tipo_interes', x.tipo_interes,
        'fecha_inicio', x.fecha_inicio, 'fecha_vencimiento', x.fecha_vencimiento, 'tasa_base', x.tasa_base, 'regla_base', x.regla_base,
        'tasa_solicitada', x.tasa_solicitada, 'tasa_maxima_autorizada', x.tasa_maxima_autorizada, 'motivo', x.motivo,
        'motivo_resolucion', x.motivo_resolucion, 'solicitante_nombre', x.solicitante_nombre, 'solicitada_en', x.solicitada_en,
        'vence_en', x.vence_en, 'resolutor_nombre', x.resolutor_nombre, 'resuelta_en', x.resuelta_en,
        'respondida_por_analista_en', x.respondida_por_analista_en, 'consumida_en', x.consumida_en, 'politica_version', x.politica_version
      ) order by x.resuelta_en desc, x.id desc) from pagina x), '[]'::jsonb),
      'siguiente_cursor', case when (select count(*) from pagina_mas_uno) > v_limite then
        (select jsonb_build_object('resuelta_en', x.resuelta_en, 'id', x.id) from pagina x order by x.resuelta_en asc, x.id asc limit 1)
      else null end
    )
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid, p_claim_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_loc record; v_previo_d5 text; v_res_d5 jsonb;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  -- F2.b [D-5] (Codex v4 #3, auditor v4 #2): READ COMMITTED y el candado COMPARTIDO de la bandera AL ENTRAR, antes de tomar
  -- documentos y filas: así el sellado nunca retiene candados de negocio mientras espera por un cambio de bandera, y el
  -- compartido que la firma de un argumento vuelve a tomar al delegar es reentrante (misma transacción).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token)
     or (v_loc.estado->>'lead_id')::uuid is distinct from p_lead_id then
    raise exception 'Saga: claim o token inválidos para este lead' using errcode = '42501';
  end if;
  -- La reserva de este lead debe ser de este claim y de su identidad (Codex E2 #5).
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead no corresponde a este claim' using errcode = 'P0409';
  end if;
  -- F2.b [D-13]: los documentos vigentes de la persona ANTES de su lock (orden documento -> persona, el de la reserva, la toma
  -- y la fusión): una toma/reapertura por ese documento en vuelo termina antes o después de este sellado, nunca en medio.
  perform private.identidad_bloquear_documentos_de(array[v_loc.inversionista_id]);
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona del claim pudo fusionarse: reintentar (la fusión exige claims terminales).
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.estado = 'fusionado') then
    raise exception 'La persona de este claim fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (Codex #4, auditor v3 M1): el lead FOR SHARE tras la persona y ANTES de la reserva (orden persona -> lead ->
  -- reserva, el mismo de la reserva por persona, la conversión coop y la fusión: sin arista nueva).
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- F2.b [D-13] (Codex #5): la pareja (lead, claim, persona) se revalida bajo el lock de la RESERVA: tras esperar, otra reserva
  -- del mismo lead para otra persona no se sella con este claim.
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead cambió mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex v3 B3): el token se relee tras los locks: una reanudación de la reserva mientras se esperaba rota el
  -- token del mismo claim, y esa ejecución vieja no debe autorizar efectos.
  perform 1 from crm.multiempresa_idempotencia m where m.clave = v_loc.clave for share;   -- orden reserva -> claim (b4)
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'El claim cambió (token rotado) mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex #4): el lead debe seguir vivo y sin otra persona (una conversión directa para otra persona, o un
  -- descarte, mientras la reserva esperaba, no se sella).
  if not exists (select 1 from crm.leads l where l.id = p_lead_id and l.activo
                  and l.etapa not in ('convertido', 'descartado')
                  and (l.inversionista_id is null or private.inversionista_canonica(l.inversionista_id) = v_loc.inversionista_id)
                  and (l.dni is null or private.inversionista_por_documento('DNI', l.dni) = v_loc.inversionista_id)) then   -- Codex v3 B2
    raise exception 'El lead ya no está disponible para esta conversión (convertido, descartado, con otro documento o de otra persona): no se sella'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1/#3): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno, contando
  -- enlace, puente y sueltos vivos con su documento: un lead de esta persona nacido, reabierto o tomado mientras la reserva
  -- esperaba (o ya vencida) no deja cuentas de portal huérfanas; Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_personas(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-5]: la firma de un argumento queda cerrada con la identidad encendida salvo para ESTE paso (b4 M3): aquí ya se
  -- validaron claim, token, veto, pareja y «un solo lead». La marca es transaccional y se restaura al salir.
  v_previo_d5 := coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off');
  perform pg_catalog.set_config('crm.sellado_por_persona', 'on', true);
  v_res_d5 := crm.marcar_efectos_conversion(p_lead_id);
  perform pg_catalog.set_config('crm.sellado_por_persona', v_previo_d5, true);
  return v_res_d5;
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_ok  boolean;
  v_inv0 uuid; v_inv1 uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance sella POR PERSONA (claim + token,
  -- crm.marcar_efectos_conversion(lead, claim, token), que valida y luego DELEGA aquí bajo la marca crm.sellado_por_persona).
  -- Esta firma de UN argumento —el sellado sin claim ni token— queda SOLO para la bandera apagada y para ese paso: una
  -- llamada directa con la bandera encendida se cierra, para que ningún cliente viejo del edge selle una conversión que la
  -- saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then   -- Codex v4 #2
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));   -- Codex v3 #3: serializa con el cambio de bandera (reentrante desde el sellado por persona)
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and coalesce(pg_catalog.current_setting('crm.sellado_por_persona', true), 'off') <> 'on' then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = 'crm.marcar_efectos_conversion(p_lead_id, p_claim_id, p_token)';
  end if;

  -- El tope absoluto también manda AQUÍ: si ya pasó, esta reserva no vale para
  -- sellar nada, y la edge muere antes de crear la cuenta.
  -- F2.b (b4): si la reserva es por PERSONA, se bloquea la identidad antes de sellar
  -- (orden identidad -> reserva; la conversión coop lee las reservas bajo ese mismo lock).
  select r.inversionista_id into v_inv0 from crm.conversion_reservas r where r.lead_id = p_lead_id;
  perform 1 from crm.inversionistas i
   where i.id = v_inv0
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
   for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona reservada pudo fusionarse (la reserva ya apunta a la canónica): reintentar.
  if v_inv0 is not null and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    select r.inversionista_id into v_inv1 from crm.conversion_reservas r where r.lead_id = p_lead_id;
    if v_inv1 is distinct from v_inv0 or exists (select 1 from crm.inversionistas i where i.id = v_inv0 and i.estado = 'fusionado') then
      raise exception 'La persona de esta reserva fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())
   where r.lead_id = p_lead_id
     and r.reservado_por = v_uid
     and r.vence_absoluto_en > now()
     and (r.expira_en > now() or r.efectos_iniciados_en is not null)
  returning true into v_ok;

  if not coalesce(v_ok, false) then
    raise exception using
      errcode = 'P0409',
      message = 'La reserva de esta conversion ya no esta viva',
      hint    = 'Vuelve a empezar la conversion desde la ficha del lead.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id);
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  v_tope     interval := interval '30 minutes';
  v_tipo     text := coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_tipo_documento)), ''), 'DNI');
  v_doc      text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g')), '');
  v_inv      uuid; v_veto boolean; v_otro uuid; v_perfil uuid; v_perfil_activo boolean;
  v_hash     text; v_hash_payload jsonb; v_saga jsonb; v_claim uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  if not private.resolver_en_puertas_bajo_candado() then
    raise exception 'Identidad unificada apagada: usa la reserva por lead' using errcode = 'P0409';
  end if;
  if v_doc is null then
    raise exception 'El documento es obligatorio para reservar la conversión' using errcode = '22023';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;

  -- documento -> identidad -> lead (ámbito, VERBATIM de la viva) -> revalidaciones de la persona.
  -- El ámbito va ANTES de cualquier lectura sobre la persona: un vendedor no puede sondear
  -- documentos ajenos con un lead que no es suyo (auditor b4 A1).
  perform private.identidad_bloquear_documento(v_tipo, v_doc);
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'reserva_conversion');
  select i.no_contactar, i.perfil_id into v_veto, v_perfil from crm.inversionistas i where i.id = v_inv for update;
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


  -- El documento tecleado debe ser el de la persona de ESTE lead (misma regla que convertir_lead, adelantada a antes de Auth).
  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
  -- F2.b [D-10] (Codex #2): el PUENTE de ESTE lead también manda. Un lead que solo está en el puente (sin enlace vivo
  -- ni DNI) pertenece a la persona de su puente; con un documento que resuelve a otra persona no se reserva
  -- (la Gerencia lo corrige o fusiona), igual que ya exige crm.enlazar_lead_inversionista_fn (b5). Por la canónica.
  if exists (select 1 from crm.inversionista_leads il
              where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and v_lead.dni is not null and v_lead.dni <> v_doc then
    raise exception 'El documento no coincide con el del lead' using errcode = 'P0409';
  end if;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
  -- F2.b [D-10] (Codex B2): si no hay OTRO enlace vivo, «un solo lead» cuenta también el PUENTE (crm.inversionista_leads,
  -- históricos del backfill sin enlace vivo), como ya hacen las dos conversiones desde b5; el propio lead no cuenta.
  -- Espejo de b5 (auditor D-10 M1): el enlace vivo se comprueba PRIMERO (el detalle señala el lead canónico cuando existe)
  -- y un lead ya cerrado conserva las respuestas de hoy (enlazado / «ya esta cerrado», más abajo). Mismo error y mismo
  -- detalle que hoy (el front no cambia).
  if v_otro is null and v_lead.etapa not in ('convertido', 'descartado') then
    -- F2.b [D-13] (Codex #1): también los SUELTOS vivos con un documento vigente de la persona (private.leads_de_personas).
    select x into v_otro from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id order by x limit 1;
  end if;
  if v_otro is not null then
    raise exception 'Esta persona ya tiene su lead: la nueva inversión sobre un cliente existente no es una conversión'
      using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_otro)::text;
  end if;
  if v_perfil is null then
    -- Perfil cliente con ese documento creado antes de la identidad: se reutiliza (dedup de hoy, por identidad).
    select p.id into v_perfil from public.perfiles p
     where p.rol = 'cliente' and p.dni = v_doc and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
     limit 1;
  end if;
  if v_perfil is not null then
    select p.activo into v_perfil_activo from public.perfiles p where p.id = v_perfil;
    if v_perfil_activo is distinct from true then
      raise exception 'Ese cliente existe pero está inactivo en el portal' using errcode = 'P0409';
    end if;
  end if;

  -- Conversión ya consumada cuya respuesta se perdió (Codex E2 #4): la saga manda.
  if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null and v_lead.inversionista_id = v_inv
     and exists (select 1 from crm.multiempresa_idempotencia i where i.clave = 'auth_persona:' || v_inv::text
                 and i.resultado->>'estado' <> 'enlazado' and i.resultado->>'tipo' = 'conversion'
                 and (i.resultado->>'lead_id')::uuid = p_lead_id
                 and coalesce((i.resultado->>'auth_user_id')::uuid, v_lead.perfil_id) = v_lead.perfil_id) then
    update crm.multiempresa_idempotencia
       set resultado = resultado || pg_catalog.jsonb_build_object('estado', 'enlazado', 'perfil_id', v_lead.perfil_id, 'actualizado_en', pg_catalog.now()),
           version = version + 1
     where clave = 'auth_persona:' || v_inv::text;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    if v_lead.etapa = 'convertido' and v_lead.perfil_id is not null then
      return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'estado', 'enlazado', 'reanudar', true,
        'inversionista_id', v_inv, 'perfil_id', v_lead.perfil_id, 'ya_existia', true);
    end if;
    raise exception 'El lead ya esta cerrado';
  end if;
  -- Reserva viva o sellada de OTRO lead de la misma persona (Avance en curso en otro lead).
  if exists (select 1 from crm.conversion_reservas r
              where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception using errcode = 'P0409',
      message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
      hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
  end if;

  -- Una reserva viva o sellada de este lead pertenece a UNA persona: no se cambia de identidad
  -- sin compensar (Codex E2 #5).
  if exists (select 1 from crm.conversion_reservas r
              where r.lead_id = p_lead_id and r.inversionista_id is not null and r.inversionista_id <> v_inv
                and (r.efectos_iniciados_en is not null or r.expira_en > v_ahora)) then
    raise exception 'Este lead ya está reservado para otra persona; espera a que caduque o pide a Gerencia que lo retome'
      using errcode = 'P0409';
  end if;
  -- Huella canónica SIN documento (Codex E2 #10).
  v_hash_payload := pg_catalog.jsonb_build_object('v', 1, 'inv', v_inv,
    'correo', pg_catalog.lower(coalesce(p_payload->>'correo','')), 'nombre', coalesce(p_payload->>'nombre_completo',''),
    'apellidos', coalesce(p_payload->>'apellidos',''), 'nombres', coalesce(p_payload->>'nombres',''),
    'telefono', coalesce(p_payload->>'telefono',''), 'domicilio', coalesce(p_payload->'domicilio', 'null'::jsonb),
    'bancarios', coalesce(p_payload->'bancarios', 'null'::jsonb));
  v_hash := private.idem_hash(v_hash_payload);

  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en, inversionista_id, hash_payload)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope, v_inv, v_hash)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         inversionista_id = v_inv,
         hash_payload  = v_hash,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;


  -- Persona YA cliente del portal (identidad enlazada o perfil con el documento exacto): sin Auth y
  -- sin saga; el edge convierte con convertir_lead_con_domicilio como hoy (auditor b4 A2).
  if v_perfil is not null then
    update crm.conversion_reservas r set claim_id = null where r.lead_id = p_lead_id;
    return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
      'inversionista_id', v_inv, 'perfil_id', v_perfil, 'ya_existia', true, 'estado', 'ya_existia', 'reanudar', false);
  end if;
  -- Claim de la saga (o reanudación con token / lease vencido).
  v_saga := private.saga_auth_reclamar(v_inv, 'conversion', v_hash_payload, p_lead_id, p_payload->>'token');
  v_claim := (v_saga->>'claim_id')::uuid;
  update crm.conversion_reservas r set claim_id = v_claim where r.lead_id = p_lead_id;

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira,
    'inversionista_id', v_inv, 'perfil_id', (v_saga->>'perfil_id')::uuid, 'ya_existia', false)
    || (v_saga - 'inversionista_id' - 'perfil_id');
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.reservar_conversion_lead(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_lead     crm.leads%rowtype;
  v_expira   timestamptz;
  v_ahora    timestamptz := now();
  v_ventana  interval := interval '5 minutes';
  -- Tope absoluto: más allá de esto, ni el propio dueño renueva. Holgado para
  -- cualquier conversión real (que tarda segundos) y corto para un secuestro.
  v_tope     interval := interval '30 minutes';
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-5] (b4 M3, Codex #8): con la identidad unificada ENCENDIDA la conversión Avance reserva y sella POR PERSONA
  -- (sobrecargas de b4: reserva con documento + datos, sellado con claim + token, saga de Auth vigilada). Esta firma de UN
  -- argumento —la reserva por lead, sin persona— queda SOLO para la bandera apagada: encendida, se cierra, para que ningún cliente
  -- viejo del edge abra una conversión que la saga no vigila (la cuenta de portal huérfana que b4 vino a impedir).
  -- Codex v3 #3: la guarda se serializa con el CAMBIO de la bandera (candado compartido por bandera; el UPDATE de
  -- crm.multiempresa_flags toma el exclusivo en su trigger): una llamada que entró apagada termina apagada, y una que entre
  -- después del encendido lo ve. Sin esto, una llamada que esperaba por el lead podía escribir sin persona ya encendida.
  -- Codex v4 #2: READ COMMITTED SIEMPRE antes de leer la bandera (una foto REPEATABLE READ anterior al encendido seguiría
  -- viendo la bandera vieja aunque tome el candado). PostgREST nunca usa otro aislamiento.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La conversión requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Con la identidad unificada encendida, la conversión a cliente va por persona (documento y datos): actualiza el CRM y vuelve a intentarlo'
      using errcode = 'P0409', hint = 'crm.reservar_conversion_lead(p_lead_id, p_tipo_documento, p_documento, p_payload)';
  end if;

  -- El FOR UPDATE serializa contra el cierre externo DENTRO de esta
  -- transacción: si el externo va ganando, aquí se espera y luego se ve el lead
  -- ya convertido → la edge se entera ANTES de crear nada.
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

  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;

  -- Alias explícito `r`: en el WHERE del DO UPDATE hay que nombrar la fila que
  -- YA existe, y `crm.conversion_reservas.expira_en` ahí se lee peor de lo que
  -- se ejecuta. Si el WHERE no se cumple no se actualiza nada y el RETURNING no
  -- devuelve fila: eso es la señal de «hay una conversión en vuelo».
  --
  -- Se puede tomar/renovar SOLO si la anterior está caducada, o si es del mismo
  -- actor Y no ha pasado su tope absoluto. Las dos condiciones exigen además
  -- que NADIE haya iniciado efectos: una vez creada la cuenta de Auth, esa
  -- reserva es definitiva y ni su propio dueño la reinicia.
  -- Quién puede tomar o retomar la reserva:
  --   · nadie, si hay efectos iniciados y la reserva es DE OTRO (esa conversión
  --     ya creó una cuenta: solo su dueño puede terminarla);
  --   · SU DUEÑO, siempre que no se haya pasado el tope absoluto — incluso con
  --     efectos ya iniciados. Esto es lo que hace posible el REINTENTO: si la
  --     conversión Avance falla en el último paso, la pantalla dice «reintenta»
  --     y ese reintento tiene que poder entrar. Sin esta rama, un fallo de red
  --     en la última llamada dejaba el lead trabado PARA SIEMPRE.
  --   · cualquiera, si la reserva caducó y nunca hubo efectos.
  -- `efectos_iniciados_en` NO se limpia al retomar: el cierre en cooperativa
  -- sigue vetado, que es la garantía que importa.
  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         -- El tope absoluto MANDA sobre la ventana: sin este `least`, renovar a
         -- los 29 minutos daba 5 más y el tope no era un tope.
         expira_en     = least(excluded.expira_en,
                               case when r.reservado_por = v_uid
                                    then r.vence_absoluto_en
                                    else excluded.vence_absoluto_en end),
         vence_absoluto_en = case
           -- Retomar la propia reserva NO reinicia el tope.
           when r.reservado_por = v_uid then r.vence_absoluto_en
           else excluded.vence_absoluto_en
         end
   where (r.reservado_por = v_uid and r.vence_absoluto_en > v_ahora)
      or (r.efectos_iniciados_en is null and r.expira_en <= v_ahora)
  returning r.expira_en into v_expira;

  if v_expira is null then
    -- Distinguir los motivos importa: uno se resuelve esperando y el otro no.
    if exists (select 1 from crm.conversion_reservas r2
               where r2.lead_id = p_lead_id and r2.efectos_iniciados_en is not null) then
      raise exception using
        errcode = 'P0409',
        message = 'Este lead ya tiene una conversion a cliente de Avance empezada por otra persona',
        hint    = 'Ya existe una cuenta de portal a su nombre: quien la empezo tiene que terminarla.';
    end if;
    raise exception using
      errcode = 'P0409',
      message = 'Otra persona esta convirtiendo este lead en este momento',
      hint    = 'Espera unos minutos y vuelve a intentarlo.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira);
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.solicitar_tasa_fn(p_solicitud jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_cliente uuid; v_cat text; v_origen uuid; v_pc uuid; v_ctr uuid;
  v_capital numeric; v_moneda text; v_mod text; v_ti text; v_fi date; v_fv date;
  v_tasa numeric; v_motivo text;
  v_res jsonb; v_base numeric; v_tope numeric; v_dias integer; v_pol_id uuid;
  v_huella text; v_viva record; v_fila crm.solicitudes_tasa;
  v_previo text := coalesce(current_setting('crm.solicitud_tasa_por_puerta', true), 'off');
begin
  -- La AUTORIDAD se pregunta antes de mirar el JSON (auditor n2): un no autorizado muere en el 42501 uniforme sin
  -- distinguir «formato inválido»; el cliente (activo, rol cliente) se comprueba justo después de leerlo.
  if v_uid is null or not private.puede_registrar_ventas() then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if p_solicitud is null or jsonb_typeof(p_solicitud) <> 'object' then
    raise exception 'Faltan los datos de la solicitud' using errcode = '22023';
  end if;
  begin
    v_cliente := (p_solicitud ->> 'cliente_id')::uuid;
    v_cat     := p_solicitud ->> 'categoria';
    v_origen  := (p_solicitud ->> 'contrato_origen_id')::uuid;
    v_pc      := (p_solicitud ->> 'producto_condicion_id')::uuid;
    v_capital := (p_solicitud ->> 'capital')::numeric;
    v_moneda  := p_solicitud ->> 'moneda';
    v_mod     := p_solicitud ->> 'modalidad';
    v_ti      := p_solicitud ->> 'tipo_interes';
    v_fi      := (p_solicitud ->> 'fecha_inicio')::date;
    v_fv      := (p_solicitud ->> 'fecha_vencimiento')::date;
    v_tasa    := round((p_solicitud ->> 'tasa_solicitada')::numeric, 2);   -- misma escala que contratos.tasa_anual (auditor m5)
    v_motivo  := btrim(p_solicitud ->> 'motivo');
    -- R4: contexto de CORRECCIÓN. El contrato que se está corrigiendo se pasa al núcleo como p_contrato_nuevo_id, para
    -- que un origen «ya renovado POR ESE contrato» siga siendo su origen válido. Sin esto no se puede ni PEDIR
    -- autorización para corregir la tasa de una renovación: el núcleo la rechaza por origen cerrado (Codex R4 #3).
    v_ctr     := (p_solicitud ->> 'contrato_id')::uuid;
  exception when others then
    raise exception 'Datos de la solicitud inválidos' using errcode = '22023';
  end;
  if not private.puede_operar_tasa_cliente(v_cliente) then
    raise exception 'Cliente no encontrado o fuera de tu cartera' using errcode = '42501';
  end if;
  if v_capital is null or v_capital < 100 or v_capital > 100000000 then
    raise exception 'El capital debe estar entre 100 y 100,000,000' using errcode = '22023';
  end if;
  if v_moneda is null or v_moneda not in ('PEN', 'USD') then
    raise exception 'Moneda inválida' using errcode = '22023';
  end if;
  if v_mod is null or v_mod not in ('mensual', 'trimestral', 'semestral', 'anual')
     or v_ti is null or v_ti not in ('simple', 'compuesto') then
    raise exception 'Modalidad o tipo de interés inválidos' using errcode = '22023';
  end if;
  if v_fi is null or v_fv is null or v_fv <= v_fi then
    raise exception 'El plazo del contrato es inválido' using errcode = '22023';
  end if;
  if v_motivo is null or length(v_motivo) < 5 or length(v_motivo) > 500 then
    raise exception 'Escribe el motivo comercial (entre 5 y 500 caracteres)' using errcode = '22023';
  end if;
  if v_tasa is null or v_tasa <= 0 then
    raise exception 'La tasa solicitada es inválida' using errcode = '22023';
  end if;

  perform private.vencer_solicitudes_tasa();
  -- EL NÚCLEO decide la base y la regla; esta puerta no calcula tasa.
  v_res := private.resolver_tasa(v_cliente, v_cat, v_origen, statement_timestamp(), v_ctr);
  v_base := (v_res ->> 'tasa_base')::numeric;
  v_tope := (v_res #>> '{politica,tope_tecnico}')::numeric;
  v_dias := (v_res #>> '{politica,vigencia_solicitud_dias}')::integer;
  v_pol_id := (v_res #>> '{politica,id}')::uuid;
  if v_tasa <= v_base then
    raise exception 'La excepción debe ser superior a la tasa base de % %%', rtrim(rtrim(to_char(v_base, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;
  if v_tasa > v_tope then
    raise exception 'La tasa solicitada supera el tope técnico de % %%', rtrim(rtrim(to_char(v_tope, 'FM999990.99'), '0'), '.') using errcode = '22023';
  end if;

  perform private.rentabilidad_bloquear_operacion(v_cliente, v_cat, v_origen);
  v_huella := private.huella_solicitud_tasa(v_cliente, v_cat, v_origen, v_pc, v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv);
  perform pg_advisory_xact_lock(hashtext('crm.solicitudes_tasa'), hashtext(v_huella));
  select s.id, s.estado, s.solicitada_por into v_viva from crm.solicitudes_tasa s
   where s.huella = v_huella
     and s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
   limit 1;
  if v_viva.id is not null then
    raise exception 'Ya hay una solicitud viva para este contrato (estado «%»)', v_viva.estado
      using errcode = 'P0409',
            detail = jsonb_build_object('solicitud_id', v_viva.id, 'estado', v_viva.estado, 'solicitada_por', v_viva.solicitada_por,
                                        'propia', v_viva.solicitada_por = v_uid)::text;
  end if;

  perform set_config('crm.solicitud_tasa_por_puerta', 'on', true);
  insert into crm.solicitudes_tasa (
    politica_id, cliente_id, categoria, contrato_origen_id, contrato_origen_numero, producto_condicion_id,
    capital, moneda, modalidad, tipo_interes, fecha_inicio, fecha_vencimiento, huella,
    tasa_base, regla_base, contratos_previos, prioridad_bandeja, tasa_solicitada, motivo,
    estado, solicitada_por, solicitada_en, vence_en
  ) values (
    v_pol_id, v_cliente, v_cat, v_origen, v_res #>> '{contrato_origen,numero_contrato}', v_pc,
    v_capital, v_moneda, v_mod, v_ti, v_fi, v_fv, v_huella,
    v_base, v_res ->> 'regla', (v_res ->> 'contratos_previos')::integer, (v_res ->> 'prioridad_bandeja')::boolean, v_tasa, v_motivo,
    'pendiente', v_uid, statement_timestamp(), statement_timestamp() + make_interval(days => v_dias)
  ) returning * into v_fila;
  perform set_config('crm.solicitud_tasa_por_puerta', v_previo, true);
  return to_jsonb(v_fila) || jsonb_build_object('ok', true, 'resolucion', v_res);
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.solicitudes_tasa_fn(p_estados text[] DEFAULT NULL::text[], p_limite integer DEFAULT 200, p_solo_mias boolean DEFAULT false, p_cliente_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm(v_uid);
  v_lector   boolean := private.es_lector_global();
  v_gerencia boolean := coalesce(v_rol = 'gerencia', false);
  v_visibles uuid[];
  v_limite   integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_ahora    timestamptz := statement_timestamp();
  v_payload  jsonb;
begin
  if v_uid is null or not (private.puede_registrar_ventas() or v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_estados is not null and exists (select 1 from unnest(p_estados) e where e not in
       ('pendiente', 'aprobada', 'aprobada_con_tope', 'rechazada', 'aceptada_por_analista', 'declinada_por_analista', 'consumida', 'vencida')) then
    raise exception 'Estado desconocido en el filtro' using errcode = '22023';
  end if;
  v_visibles := case when v_gerencia or v_lector then '{}'::uuid[] else array(select private.vendedor_ids_visibles(v_uid)) end;

  with efectivas as (
    select s.*,
           case when s.estado in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista') and s.vence_en < v_ahora
                then 'vencida' else s.estado end as estado_efectivo
    from crm.solicitudes_tasa s
    where (v_gerencia or v_lector or s.solicitada_por = v_uid or s.solicitada_por = any(v_visibles))
      and (not coalesce(p_solo_mias, false) or s.solicitada_por = v_uid)
      and (p_cliente_id is null or s.cliente_id = p_cliente_id)
  ), acotadas as (
    -- Las TERMINALES (rechazada, declinada, consumida, vencida) solo de los últimos 7 días: esta RPC alimenta la bandeja,
    -- el formulario y el aviso (el histórico completo de un cliente vive en historial_tasa_cliente_fn). Así 200 rechazos
    -- viejos no pueden tapar una autorización viva (Codex R3 ronda 3). El front usa el mismo corte (DIAS_RECHAZO_VISIBLE).
    select s.*,
           (s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')) as viva,
           coalesce(s.resuelta_en, s.respondida_por_analista_en, s.consumida_en, s.vence_en, s.solicitada_en) as cerrada_en
    from efectivas s
    where s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')
       or coalesce(s.resuelta_en, s.respondida_por_analista_en, s.consumida_en, s.vence_en, s.solicitada_en) >= v_ahora - interval '7 days'
  ), visibles as (
    -- El filtro por estado es sobre el estado EFECTIVO (Codex R3 #9): una pendiente ya vencida no es «pendiente»
    -- y no ocupa el límite. Las VIVAS van siempre antes del límite; entre vivas, pendientes y prioritarias (D1) primero
    -- y la más antigua antes (FIFO de la bandeja); las terminales, la más reciente antes.
    select s.*
    from acotadas s
    where (p_estados is null or s.estado_efectivo = any(p_estados))
    order by s.viva desc, (s.estado_efectivo = 'pendiente') desc, s.prioridad_bandeja desc,
             case when s.viva then s.solicitada_en end asc, s.cerrada_en desc
    limit v_limite
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'estado', s.estado,
    'estado_efectivo', s.estado_efectivo,
    'vigente', (s.estado_efectivo in ('pendiente', 'aprobada', 'aprobada_con_tope', 'aceptada_por_analista')),
    'categoria', s.categoria, 'cliente_id', s.cliente_id,
    -- El nombre del cliente solo con ámbito sobre su ficha (Codex R3 #4): quien pidió, Gerencia, Directorio o quien
    -- puede consultar la ficha; el resto del subárbol ve la solicitud sin el nombre.
    'cliente_nombre', case when v_gerencia or v_lector or s.solicitada_por = v_uid or private.puede_consultar_cliente_ficha(s.cliente_id)
                           then coalesce(cl.nombre_completo, 'Cliente') else 'Cliente de tu equipo' end,
    'contrato_origen_id', s.contrato_origen_id, 'contrato_origen_numero', s.contrato_origen_numero,
    'producto_condicion_id', s.producto_condicion_id,
    'capital', s.capital, 'moneda', s.moneda, 'modalidad', s.modalidad, 'tipo_interes', s.tipo_interes,
    'fecha_inicio', s.fecha_inicio, 'fecha_vencimiento', s.fecha_vencimiento,
    'tasa_base', s.tasa_base, 'regla_base', s.regla_base, 'tasa_solicitada', s.tasa_solicitada,
    'tasa_maxima_autorizada', s.tasa_maxima_autorizada,
    'motivo', s.motivo, 'motivo_resolucion', s.motivo_resolucion, 'motivo_analista', s.motivo_analista,
    'prioridad_bandeja', s.prioridad_bandeja, 'contratos_previos', s.contratos_previos,
    'solicitada_por', s.solicitada_por, 'solicitante_nombre', coalesce(so.nombre_completo, 'Sin nombre'),
    'solicitada_en', s.solicitada_en, 'vence_en', s.vence_en,
    'resuelta_por', s.resuelta_por, 'resolutor_nombre', re.nombre_completo, 'resuelta_en', s.resuelta_en,
    'respondida_por_analista_en', s.respondida_por_analista_en, 'consumida_en', s.consumida_en, 'contrato_id', s.contrato_id,
    'politica_id', s.politica_id,
    'es_mia', (s.solicitada_por = v_uid),
    -- D3: Gerencia resuelve las de OTROS, pendientes y vigentes.
    'puede_resolver', (v_gerencia and s.solicitada_por <> v_uid and s.estado_efectivo = 'pendiente'),
    -- Quien pidió responde a un tope vigente.
    'puede_responder', (s.solicitada_por = v_uid and s.estado_efectivo = 'aprobada_con_tope')
  ) order by s.viva desc, (s.estado_efectivo = 'pendiente') desc, s.prioridad_bandeja desc, case when s.viva then s.solicitada_en end asc, s.cerrada_en desc), '[]'::jsonb)
  into v_payload
  from visibles s
  left join public.perfiles cl on cl.id = s.cliente_id
  left join public.perfiles so on so.id = s.solicitada_por
  left join public.perfiles re on re.id = s.resuelta_por;
  return v_payload;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.resolver_tasa(p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_instante timestamp with time zone, p_contrato_nuevo_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_pol      crm.politica_rentabilidad;
  v_cli      record;
  v_origen   public.contratos%rowtype;
  v_previos  integer;
  v_activos  integer;
  v_base     numeric;
  v_regla    text;
begin
  if p_cliente_id is null then
    raise exception 'El cliente es obligatorio' using errcode = '22023';
  end if;
  if p_categoria is null or p_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception 'Selecciona la categoría del contrato (nuevo, renovacion o upgrade)' using errcode = '22023';
  end if;
  v_pol := private.politica_rentabilidad_vigente(p_instante);
  if v_pol.id is null then
    raise exception 'No hay política de rentabilidad vigente' using errcode = 'P0002';
  end if;
  select p.id, p.activo, p.asesor_perfil_id into v_cli
  from public.perfiles p where p.id = p_cliente_id and p.rol = 'cliente';
  if v_cli.id is null then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  if v_cli.activo is not true then
    raise exception 'El cliente está inactivo' using errcode = 'P0409';
  end if;
  -- «Previos» = los contratos del cliente sin contar el que se está observando (al commit, el nuevo ya existe).
  select count(*), count(*) filter (where c.estado = 'activo')
    into v_previos, v_activos
  from public.contratos c
  where c.cliente_id = p_cliente_id and not c.es_demo and c.id is distinct from p_contrato_nuevo_id;

  if p_categoria = 'nuevo' then
    if p_contrato_origen_id is not null then
      raise exception 'Una primera inversión no lleva contrato origen' using errcode = '22023';
    end if;
    v_base := v_pol.tasa_base_nueva;
    v_regla := 'primera_inversion';
  else
    if p_contrato_origen_id is null then
      raise exception 'Selecciona el contrato que se % (contrato origen)', case when p_categoria = 'renovacion' then 'renueva' else 'amplía' end
        using errcode = '22023';
    end if;
    select * into v_origen from public.contratos c where c.id = p_contrato_origen_id;
    if v_origen.id is null then
      raise exception 'El contrato origen no existe' using errcode = 'P0002';
    end if;
    if v_origen.cliente_id is distinct from p_cliente_id then
      raise exception 'El contrato origen pertenece a otro cliente' using errcode = 'P0409';
    end if;
    if p_categoria = 'renovacion' then
      -- Mismo criterio que public.crear_contrato: se renueva un contrato activo o vencido que aún no fue renovado…
      -- …salvo que ya haya quedado renovado POR ESTE contrato (observación al commit): sigue siendo su origen.
      -- IS NOT TRUE (no «NOT»): con renovado_a_id NULL la segunda alternativa es NULL y un «NOT NULL» dejaría pasar un
      -- origen retirado (Codex R2 #3). La segunda alternativa exige además estado 'renovado'.
      if (
           (v_origen.estado in ('activo', 'vencido') and v_origen.renovado_a_id is null)
        or (p_contrato_nuevo_id is not null and v_origen.estado = 'renovado' and v_origen.renovado_a_id = p_contrato_nuevo_id)
      ) is not true then
        raise exception 'El contrato origen ya fue cerrado o renovado (estado «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_renovacion';
    else
      -- D2: el upgrade amplía un contrato ACTIVO concreto que el analista selecciona.
      if v_origen.estado <> 'activo' or v_origen.renovado_a_id is not null then
        raise exception 'El upgrade solo amplía un contrato activo (este está «%»)', v_origen.estado using errcode = 'P0409';
      end if;
      v_regla := 'heredada_upgrade';
    end if;
    v_base := v_origen.tasa_anual;
  end if;

  return jsonb_build_object(
    'tasa_base', v_base,
    'regla', v_regla,
    'categoria', p_categoria,
    'cliente_id', p_cliente_id,
    'contrato_origen', case when v_origen.id is null then null else jsonb_build_object(
        'id', v_origen.id, 'numero_contrato', v_origen.numero_contrato, 'tasa_anual', v_origen.tasa_anual,
        'estado', v_origen.estado, 'moneda', v_origen.moneda, 'capital', v_origen.capital,
        'fecha_vencimiento', v_origen.fecha_vencimiento) end,
    'contratos_previos', v_previos,
    'contratos_activos', v_activos,
    'prioridad_bandeja', (p_categoria = 'nuevo' and v_previos > 0),
    'politica', jsonb_build_object('id', v_pol.id, 'version', v_pol.version, 'modo', v_pol.modo,
        'tasa_base_nueva', v_pol.tasa_base_nueva, 'tope_tecnico', v_pol.tope_tecnico,
        'vigencia_solicitud_dias', v_pol.vigencia_solicitud_dias),
    'resuelto_en', coalesce(p_instante, statement_timestamp())
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION private.resolver_tasa(p_cliente_id uuid, p_categoria text, p_contrato_origen_id uuid, p_instante timestamp with time zone DEFAULT statement_timestamp())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.resolver_tasa(p_cliente_id, p_categoria, p_contrato_origen_id, p_instante, null::uuid)
$function$
;

drop policy solicitudes_tasa_select on crm.solicitudes_tasa;
create policy solicitudes_tasa_select on crm.solicitudes_tasa for select to authenticated using (((solicitada_por = ( SELECT auth.uid() AS uid)) OR ( SELECT private.es_lector_global() AS es_lector_global) OR (( SELECT private.rol_crm(( SELECT auth.uid() AS uid)) AS rol_crm) = 'gerencia'::text) OR (solicitada_por IN ( SELECT private.vendedor_ids_visibles(( SELECT auth.uid() AS uid)) AS vendedor_ids_visibles))));
drop function crm.resolver_tasa_lead_fn(uuid,text,uuid);
drop function crm.solicitudes_tasa_lead_fn(uuid,text[],integer);
drop function crm.reservar_conversion_lead_tasa_fn(uuid,jsonb);
drop function private.puede_ver_tasa_lead(uuid);
drop function private.cliente_tasa_lead(uuid);
drop function private.exigir_operar_tasa_lead(uuid);
drop function private.exigir_sin_conversion_tasa(uuid,uuid);
drop function private.huella_intencion_tasa(uuid,jsonb);
drop function private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean);
drop function private.enlazar_tasa_lead(uuid,uuid);
drop function private.solicitudes_tasa_impl(text[],integer,boolean,uuid,uuid);
alter table crm.solicitudes_tasa drop constraint solicitudes_tasa_sujeto;
alter table crm.solicitudes_tasa alter column cliente_id set not null;
alter table crm.solicitudes_tasa drop column lead_id,drop column huella_preconversion,drop column documento_lead;
alter table crm.conversion_reservas drop column condiciones_tasa;
notify pgrst,'reload schema';
commit;
