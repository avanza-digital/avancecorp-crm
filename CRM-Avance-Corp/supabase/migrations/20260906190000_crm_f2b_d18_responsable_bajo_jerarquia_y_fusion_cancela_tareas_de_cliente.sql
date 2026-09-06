-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b [D-18] — LAS DOS DEUDAS DEL BLOQUE 2, ANTES DEL ENCENDIDO
-- ============================================================================
--
-- (a) LA CONVERSIÓN NO LE DA UN RESPONSABLE QUE SE ESTÁ YENDO (Codex #3 del bloque 2). `crm.convertir_lead` abre el
--     tramo de responsable de relación con el asesor del perfil «si está activo», y leía `crm.equipo.activo` sin
--     candado. La baja de un analista (`crm.fijar_membresia_activa_fn`, D-2) toma el interlock EXCLUSIVO de jerarquía
--     `crm.equipo.usuarios_jerarquia`, cierra sus tramos y los abre al reemplazo; una conversión en vuelo podía
--     abrirle uno nuevo justo después y dejar a esa persona con un responsable que ya no trabaja. Ahora la conversión
--     toma el interlock COMPARTIDO al ENTRAR (antes de cualquier candado de negocio: jerarquía → documento → persona
--     → lead, el mismo orden que el offboarding, así que no hay ciclo) y comprueba `activo` con la fila FOR SHARE.
--
-- (b) LA FUSIÓN CANCELA TAMBIÉN LAS TAREAS DE CLIENTE (N6). Cuando la fusión hereda el veto «No insistir», cancelaba
--     los seguimientos del LEAD pero dejaba vivas las tareas de la FICHA DE CLIENTE de esas personas: quedaban
--     recordatorios para llamar a alguien a quien no se debe contactar. Ahora se bloquean y se cancelan también
--     (mismo criterio y misma marca de «cancelación del sistema» que D-3), y la respuesta informa cuántas.
--
-- Ambas transformaciones son ANCLADAS al texto vivo de producción (vivas/d18/, huellas-d18-prod.txt) y no cambian
-- nada más. Con la bandera apagada, (a) es un candado que nadie disputa y (b) no dispara (no hay veto de persona).
-- Reversa byte a byte: scripts/rollback-f2b-d18.sql. Registro: scripts/registrar-f2b-d18.sql.
-- Ensayo: scripts/oraculo-f2b-d18.sh.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d18_deudas_bloque2'));

do $guard$
begin
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.convertir_lead(uuid,uuid)')), '') not in ('c8ebebbef7ba675702b91d4f10bb4d6a', '4b013634a8d8aa6b205dfc37fe1b6da1') then
    raise exception 'F2.b D-18: crm.convertir_lead(uuid,uuid) no es ni el texto vivo de producción (c8ebebbe…) ni el de D-18';
  end if;
  if coalesce((select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)')), '') not in ('eaa39f1552cdea5821311c544d90e3b0', 'd3d1a56fcf0d8c7479be27ce13990b17') then
    raise exception 'F2.b D-18: crm.fusionar_inversionistas_fn(uuid,uuid,text,text) no es ni el texto vivo de producción (eaa39f15…) ni el de D-18';
  end if;
  if to_regprocedure('private.cancelar_tareas_pendientes_lead(uuid)') is null then
    raise exception 'F2.b D-18: falta private.cancelar_tareas_pendientes_lead(uuid)';
  end if;
  -- La guarda se lee bajo el MISMO candado compartido que usan las puertas (auditor D-17 #5): esta migración corre como
  -- `postgres`, así que el drenaje del script de encendido no la ve; sin el candado, un encendido confirmado entre esta
  -- lectura y el CREATE OR REPLACE dejaría aterrizar el lote con la bandera ya encendida.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  if not exists (select 1 from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas') then
    raise exception 'F2.b D-18: no existe la bandera resolver_en_puertas (¿F1 aplicada?)';
  end if;
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'F2.b D-18: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.convertir_lead(uuid,uuid) — el responsable, bajo el interlock de jerarquía
-- ============================================================================
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
  -- F2.b [D-18] (Codex #3 del bloque 2): el tramo de responsable se abre con el asesor del perfil «si está activo»,
  -- y eso se leía sin candado: una baja de analista en vuelo (crm.fijar_membresia_activa_fn, que toma el interlock
  -- EXCLUSIVO de jerarquía) podía cerrarle sus tramos mientras esta conversión le abría uno nuevo. Se toma el
  -- interlock COMPARTIDO al ENTRAR —antes de cualquier candado de negocio, el mismo orden que el offboarding:
  -- jerarquía → documento → persona → lead, así que no hay ciclo— y más abajo se revalida `activo` bajo él.
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));

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
$function$;

-- ============================================================================
-- 2. crm.fusionar_inversionistas_fn(uuid,uuid,text,text) — la fusión cancela también las tareas de cliente
-- ============================================================================
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
  v_perfiles_fusion := array(select p.id from public.perfiles p
                              where p.id in (v_p.perfil_id, v_c.perfil_id) and p.id is not null);
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
$function$;

do $post$
begin
  if not exists (select 1 from pg_proc p where p.oid = 'crm.convertir_lead(uuid,uuid)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = '4b013634a8d8aa6b205dfc37fe1b6da1') then
    raise exception 'POSTFLIGHT D-18: crm.convertir_lead(uuid,uuid) no quedó como la genera gen-d18.py';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""'] and p.proowner = 'postgres'::regrole and md5(p.prosrc) = 'd3d1a56fcf0d8c7479be27ce13990b17') then
    raise exception 'POSTFLIGHT D-18: crm.fusionar_inversionistas_fn(uuid,uuid,text,text) no quedó como la genera gen-d18.py';
  end if;
  if exists (select 1 from unnest(array['crm.convertir_lead(uuid,uuid)','crm.fusionar_inversionistas_fn(uuid,uuid,text,text)']) f(firma)
             where not has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE'))
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('crm.convertir_lead(uuid,uuid)'::regprocedure, 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-18: los grants no son «solo authenticated»';
  end if;
  raise notice 'F2.b D-18 OK: la conversión respeta la baja del analista y la fusión cancela las tareas de cliente.';
end
$post$;
commit;
