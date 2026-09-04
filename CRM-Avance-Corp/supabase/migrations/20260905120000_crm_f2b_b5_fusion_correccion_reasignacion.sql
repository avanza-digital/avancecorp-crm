-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b5 (E3) — FUSIÓN DE IDENTIDADES, CORRECCIÓN
-- DOCUMENTAL, ENLACE DE LEAD SUELTO Y REASIGNACIÓN DEL RESPONSABLE (solo Gerencia)
-- ============================================================================
--
-- QUE (contrato §4.4, §6, invariantes #6/#8/#9/#19): las puertas de Gerencia que hoy no existen.
--   * crm.fusion_previsualizar_fn(perdedora, canonica): foto + huella + bloqueos/advertencias (solo lectura).
--   * crm.fusionar_inversionistas_fn(perdedora, canonica, motivo, hash): matriz de colisiones completa
--     (perfil, veto OR con tareas, responsable, identificadores reemitidos, lead y puente, cierres,
--     inversiones y titulares, reservas, predecesoras aplanadas), libro append-only, perdedora NUNCA borrada.
--     Alcance acotado hasta F5: como máximo un lead y un perfil entre las dos.
--   * crm.corregir_documento_inversionista_fn(...): el vigente pasa a histórico, nuevo vigente verificado,
--     realinea perfil y lead SOLO si llevaban el documento reemplazado; motivo en crm.inversionista_correcciones.
--   * crm.enlazar_lead_inversionista_fn(lead, inversionista, motivo): la revisión humana de la clase E.
--   * crm.reasignar_responsable_relacion_fn(inversionista, nuevo, motivo): cierra/abre tramo; no mueve atribuciones.
-- Y cuatro funciones VIVAS transformadas SOLO en su rama ON (guarda md5 del texto de producción):
--   convertir_lead (revalida fusión tras el lock [E3-1]; persona del lead manda [E3-11]; proyección canónica
--   en reintentos [E3-12]), convertir_lead_externo ([E3-11]), saga_conversion_fn ('cerrar': documento antes de
--   identidad [E3-1]) y trg_leads_disponibilidad_atomica (excepción estrecha bajo válvula para la corrección [E3-6]).
-- Orden total de b5: jerarquía -> documentos -> identidades -> perfil -> cierres -> inversiones/titulares ->
-- tramos -> tareas -> lead -> reservas -> claims -> contactos (por trigger).
-- TODO detrás de la bandera; RPC nuevas inertes (P0409) con la bandera apagada.
-- Reversa: scripts/rollback-f2b-b5.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b5_fusion_correccion_reasignacion'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is null
     or to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is null
     or to_regprocedure('private.identidad_bloquear_documento(text,text)') is null
     or to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regclass('crm.inversionista_fusiones') is null then
    raise exception 'F2.b b5: falta E1 o E2 (20260904120000..20260905110000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false)
     or coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'), false) then
    raise exception 'F2.b b5: alguna bandera está ENCENDIDA; este lote aterriza apagado';
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_perfil_id uuid';
  if v_h <> '0327c4d75a515a292973fed3d2577cd0' and (select strpos(p.prosrc,'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='crm' and p.proname='convertir_lead' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_perfil_id uuid') = 0 then
    raise exception 'F2.b b5: crm.convertir_lead no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text';
  if v_h <> '190b75ebcd5ac0a5f7f43a59bda5295d' and (select strpos(p.prosrc,'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='crm' and p.proname='convertir_lead_externo' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text, p_vence_en date, p_nota text') = 0 then
    raise exception 'F2.b b5: crm.convertir_lead_externo no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='saga_conversion_fn' and pg_get_function_identity_arguments(p.oid) = 'p_paso text, p_payload jsonb';
  if v_h <> 'e1750c3d2def2d611b60fb5cf281f3c8' and (select strpos(p.prosrc,'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='crm' and p.proname='saga_conversion_fn' and pg_get_function_identity_arguments(p.oid) = 'p_paso text, p_payload jsonb') = 0 then
    raise exception 'F2.b b5: crm.saga_conversion_fn no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='trg_leads_disponibilidad_atomica' and pg_get_function_identity_arguments(p.oid) = '';
  if v_h <> '782e65d744ae497139f9cafd09a53778' and (select strpos(p.prosrc,'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
       where n.nspname='private' and p.proname='trg_leads_disponibilidad_atomica' and pg_get_function_identity_arguments(p.oid) = '') = 0 then
    raise exception 'F2.b b5: private.trg_leads_disponibilidad_atomica no es el texto vivo esperado (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 1. Funciones VIVAS transformadas (rama ON; OFF byte a byte)
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
;

CREATE OR REPLACE FUNCTION crm.convertir_lead_externo(p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text DEFAULT NULL::text, p_vence_en date DEFAULT NULL::date, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
  v_flag        boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_inv         uuid;
  v_lead_canon  uuid;
  v_clave       text;
  v_hash        text;
  v_prev        jsonb;
  v_res         jsonb;
begin
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- IDEMPOTENCIA (contrato §8.3, Codex #5): misma clave + mismo payload -> mismo
  -- resultado; misma clave con otro payload -> P0409. Se evalúa ANTES de validar
  -- para que un reintento idéntico ni siquiera toque el lead.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto.) El hash cubre
  -- TODO lo que se persiste (Codex), con el número de operación en MAYÚSCULAS como
  -- se compara y reclama.
  if v_flag then
    v_clave := 'conversion_coop:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object(
                 'lead', p_lead_id, 'coop', p_cooperativa, 'monto', p_monto, 'moneda', p_moneda,
                 'tipo', p_documento_tipo, 'doc', v_documento, 'trx', upper(v_transaccion),
                 'nombre', v_nombre, 'ref', v_referencia, 'vence', p_vence_en,
                 'nota', nullif(btrim(coalesce(p_nota,'')), '')));
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;

  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- En cooperativas solo se invierte en soles. Se valida en vez de forzar: un
  -- bundle viejo que mande USD merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto como si fueran soles.
  if p_moneda is distinct from 'PEN' then
    raise exception 'En cooperativas solo se registran inversiones en soles'
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Resolver ANTES del lock del lead (orden identidad->lead, comparte orden con
  -- la fusión y mata el deadlock). El documento ya se validó arriba. Con bandera
  -- APAGADA nada de esto corre (comportamiento idéntico a hoy).
  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b4): la PERSONA (no solo este lead) puede tener una conversión Avance en curso en OTRO
    -- lead: reserva viva o sellada con su inversionista_id. Lectura bajo el lock de la identidad
    -- (el sellado también lo toma desde b4): orden identidad -> lead -> reserva, sin cambios.
    if exists (select 1 from crm.conversion_reservas r
                where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                  and (r.efectos_iniciados_en is not null or r.expira_en > now())) then
      raise exception using
        errcode = 'P0409',
        message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
        hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
    end if;
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
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

  -- Reintento tras éxito: el lead ya se convirtió y su cierre lleva ESTE número de
  -- operación -> mismo resultado, sin efectos (idempotente).
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock (Codex): la clave guardada manda; payload distinto → P0409.
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (p.ej. conversión previa a este lote): mismo número de
    -- operación en su cierre = mismo hecho.
    select ce.id into v_cierre_id
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and upper(ce.numero_transaccion) = upper(v_transaccion)
    limit 1;
    if v_cierre_id is not null then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'cierre_id', v_cierre_id,
                                             'cooperativa', p_cooperativa);
      perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
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

  -- Un solo lead total (invariante #6, decisión Miguel 03/09): un 2.º lead de la
  -- misma persona no se convierte aquí; la nueva inversión sobre el cliente
  -- existente es F5. Mensaje de negocio en vez del choque con leads_inversionista_uidx.
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por, inversionista_id
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, p_vence_en, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid, v_inv
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  -- Inversión (colgada de la identidad) + titular principal (solo bandera).
  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura'), false) then
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)
    select v_inv, e.id, ce.id, 'vigente',
           least((ce.creado_en at time zone 'America/Lima')::date, (pg_catalog.now() at time zone 'America/Lima')::date),
           not exists (select 1 from crm.inversiones inv2 where inv2.inversionista_id = v_inv),
           ce.creado_por
    from crm.cierres_externos ce join crm.empresas e on e.clave = ce.cooperativa
    where ce.id = v_cierre_id and not exists (select 1 from crm.inversiones inv where inv.cierre_externo_id = ce.id);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol)
    select inv.id, v_inv, 'principal' from crm.inversiones inv
    where inv.cierre_externo_id = v_cierre_id
      and not exists (select 1 from crm.inversion_titulares it where it.inversion_id = inv.id and it.rol='principal');
  end if;

  -- El cierre del lead. inversionista_id viaja en el MISMO UPDATE bajo la válvula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Reconocimiento de identidad (reemplaza al trigger 200000 para coop).
  if v_flag and v_inv is not null then
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);
    -- Responsable de relación = vendedor del cierre (si activo y sin tramo abierto).
    if v_lead.vendedor_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_lead.vendedor_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_lead.vendedor_id, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_lead.vendedor_id
        where id = v_inv and responsable_relacion_id is null;
    end if;
    -- no_contactar del lead se centraliza en la persona.
    if v_lead.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  v_res := jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$
;

CREATE OR REPLACE FUNCTION crm.saga_conversion_fn(p_paso text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_claim uuid; v_loc record; v_res jsonb; v_perfil uuid; v_lead uuid; v_inv_conv uuid; v_tipo text; v_doc text;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;
  v_claim := (p_payload->>'claim_id')::uuid;
  if v_claim is null then raise exception 'Falta claim_id' using errcode = '22023'; end if;
  if (p_payload->>'version') is null then raise exception 'Falta version (CAS)' using errcode = '22023'; end if;

  if p_paso = 'registrar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'auth_creado', (p_payload->>'auth_user_id')::uuid, null, (p_payload->>'version')::integer);
  elsif p_paso = 'compensar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'reclamado', null, null, (p_payload->>'version')::integer);
  elsif p_paso = 'perfil_creado' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'perfil_creado', null, (p_payload->>'perfil_id')::uuid, (p_payload->>'version')::integer);
  elsif p_paso = 'cerrar' then
    -- CIERRE TRANSACCIONAL (Codex E2 #7): convertir y comprobar que la identidad convertida es la
    -- reservada, o revertir todo. Orden: (convertir_lead) documento -> identidad -> lead -> reserva -> claim.
    select * into v_loc from private.saga_auth_localizar(v_claim);
    if not found then raise exception 'Saga: claim inexistente' using errcode = 'P0002'; end if;
    if v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_payload->>'token') then
      raise exception 'Saga: token inválido' using errcode = '42501';
    end if;
    v_lead   := coalesce((p_payload->>'lead_id')::uuid, (v_loc.estado->>'lead_id')::uuid);
    v_perfil := coalesce((p_payload->>'perfil_id')::uuid, (v_loc.estado->>'perfil_id')::uuid, (v_loc.estado->>'auth_user_id')::uuid);
    if v_lead is null or v_perfil is null then
      raise exception 'Saga: faltan lead o perfil para cerrar' using errcode = 'P0409';
    end if;
    if (v_loc.estado->>'lead_id')::uuid is distinct from v_lead then
      raise exception 'Saga: el lead no es el reservado en este claim' using errcode = 'P0409';
    end if;
    -- El perfil de un claim con Auth es ese Auth: no se cierra con otro perfil (auditor b4 M1).
    if (v_loc.estado->>'auth_user_id') is not null and v_perfil is distinct from (v_loc.estado->>'auth_user_id')::uuid then
      raise exception 'Saga: el perfil no corresponde al usuario de Auth de este claim' using errcode = 'P0409';
    end if;
    -- F2.b (b5) [E3-1]: documento ANTES de identidad (la fusión toma documento -> identidad;
    -- convertir_lead resolverá este mismo documento, reentrante).
    select coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI'), p.dni into v_tipo, v_doc
      from public.perfiles p where p.id = v_perfil;
    if v_doc is null then
      raise exception 'Saga: el perfil del claim no existe o no tiene documento' using errcode = 'P0409';
    end if;
    perform private.identidad_bloquear_documento(v_tipo, v_doc);
    -- Veto revalidado también al cerrar (Codex E2 #11): con veto, la conversión no se consuma.
    perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
    if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
      raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
    end if;
    v_res := crm.convertir_lead_con_domicilio(v_lead, v_perfil, p_payload->>'domicilio');
    v_inv_conv := (v_res->>'inversionista_id')::uuid;
    if v_inv_conv is distinct from v_loc.inversionista_id then
      raise exception 'La persona convertida no es la persona reservada (el documento cambió): se revierte la conversión'
        using errcode = 'P0409';
    end if;
    return v_res || private.saga_auth_avanzar(v_claim, p_payload->>'token', 'enlazado', null, v_perfil, (p_payload->>'version')::integer);
  end if;
  raise exception 'Paso desconocido: %', p_paso using errcode = '22023';
end;
$function$
;

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
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
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

    -- F2.b (b5) [E3-6]: la corrección de documento de Gerencia (RPC definer bajo válvula)
    -- cambia SOLO el DNI de un lead que conserva su persona; los terceros (otra identidad,
    -- otro cliente del Portal, otro lead vivo) ya los comprobó la RPC bajo sus locks. Ningún
    -- otro escritor bajo válvula cambia el DNI; fuera de esta forma exacta nada cambia.
    if v_priv and new.dni is distinct from old.dni and new.telefono is not distinct from old.telefono
       and old.inversionista_id is not null and new.inversionista_id = old.inversionista_id then
      return new;
    end if;
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
;

-- ============================================================================
-- 2. Objetos nuevos: tabla de correcciones, helpers privados y las 5 puertas de Gerencia
-- ============================================================================
-- ---------------------------------------------------------------------------
-- 2.1 Tabla append-only de correcciones documentales (patrón F1: RLS, sin grants, auditada)
-- ---------------------------------------------------------------------------
create table if not exists crm.inversionista_correcciones (
  id uuid primary key default gen_random_uuid(),
  inversionista_id uuid not null references crm.inversionistas(id),
  identificador_anterior_id uuid references crm.inversionista_identificadores(id),
  identificador_nuevo_id uuid not null references crm.inversionista_identificadores(id),
  motivo text not null check (length(btrim(motivo)) between 3 and 500),
  perfil_realineado boolean not null default false,
  lead_realineado text not null default 'sin_lead' check (lead_realineado in ('dni','nulo','sin_cambio','sin_lead')),
  por uuid references public.perfiles(id),
  creado_en timestamptz not null default now() check (isfinite(creado_en))
);
comment on table crm.inversionista_correcciones is
  'F2.b b5: libro append-only de correcciones de documento (Gerencia). Guarda ids de identificadores y el motivo; NUNCA el documento en claro. RLS activa, sin grants a la Data API.';
create index if not exists inv_correcciones_inv_idx on crm.inversionista_correcciones (inversionista_id);
alter table crm.inversionista_correcciones enable row level security;
revoke all on crm.inversionista_correcciones from public, anon, authenticated, service_role;
drop policy if exists inversionista_correcciones_select_gerencia on crm.inversionista_correcciones;
create policy inversionista_correcciones_select_gerencia on crm.inversionista_correcciones
  for select to authenticated using (private.es_gerencia_crm_activa());
drop trigger if exists trg_audit_inversionista_correcciones on crm.inversionista_correcciones;
create trigger trg_audit_inversionista_correcciones
  after insert or update or delete on crm.inversionista_correcciones
  for each row execute function private.log_audit_crm();
create or replace function private.inversionista_correcciones_append_only() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'crm.inversionista_correcciones es append-only: % no permitido', tg_op using errcode = '0A000';
end $$;
revoke all on function private.inversionista_correcciones_append_only() from public, anon, authenticated, service_role;
drop trigger if exists trg_inversionista_correcciones_append_only on crm.inversionista_correcciones;
create trigger trg_inversionista_correcciones_append_only
  before update or delete on crm.inversionista_correcciones
  for each row execute function private.inversionista_correcciones_append_only();

-- ---------------------------------------------------------------------------
-- 2.2 Helpers privados (sin EXECUTE para la API)
-- ---------------------------------------------------------------------------
-- Raíz de la cadena de canónicas (máx. 16 saltos). NULL -> NULL; id sin fila -> el mismo id.
create or replace function private.inversionista_canonica(p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  with recursive c as (
    select i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i where i.id = p_id
    union all
    select i.id, i.inversionista_canonico_id, c.n + 1
    from c join crm.inversionistas i on i.id = c.inversionista_canonico_id
    where c.n < 16
  )
  select case when p_id is null then null
              else coalesce((select c.id from c where c.inversionista_canonico_id is null order by c.n desc limit 1), p_id) end
$$;
revoke all on function private.inversionista_canonica(uuid) from public, anon, authenticated, service_role;

-- Foto canónica y determinista de dos identidades, SIN documentos en claro (solo los 3 últimos
-- caracteres). La previsualización la devuelve; la fusión la recalcula bajo los locks y compara.
create or replace function private.fusion_estado_jsonb(p_a uuid, p_b uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object('v', 1, 'identidades', coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', i.id, 'estado', i.estado, 'perfil_id', i.perfil_id, 'responsable', i.responsable_relacion_id,
      'no_contactar', i.no_contactar, 'canonico', i.inversionista_canonico_id,
      'identificadores', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', d.id, 'tipo', d.tipo_documento, 'estado', d.estado, 'verificado', d.verificado,
          'fin', pg_catalog.right(d.documento_normalizado, 3)) order by d.id)
        from crm.inversionista_identificadores d where d.inversionista_id = i.id), '[]'::jsonb),
      'leads', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', l.id, 'etapa', l.etapa, 'activo', l.activo, 'no_contactar', l.no_contactar,
          'vendedor_id', l.vendedor_id, 'perfil_id', l.perfil_id) order by l.id)
        from crm.leads l where l.inversionista_id = i.id), '[]'::jsonb),
      'puente', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', il.id, 'lead_id', il.lead_id, 'rol', il.rol) order by il.id)
        from crm.inversionista_leads il where il.inversionista_id = i.id), '[]'::jsonb),
      'tramos', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', r.id, 'responsable_id', r.responsable_id) order by r.id)
        from crm.inversionista_responsables r where r.inversionista_id = i.id and r.hasta is null), '[]'::jsonb),
      'cierres', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', ce.id, 'lead_id', ce.lead_id, 'vigente', ce.anulado_en is null, 'inversionista_id', ce.inversionista_id) order by ce.id)
        from crm.cierres_externos ce
        where ce.inversionista_id = i.id or ce.lead_id in (select l.id from crm.leads l where l.inversionista_id = i.id)), '[]'::jsonb),
      'inversiones', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', inv.id, 'estado', inv.estado, 'empresa_id', inv.empresa_id) order by inv.id)
        from crm.inversiones inv where inv.inversionista_id = i.id), '[]'::jsonb),
      'titulares', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('id', t.id, 'inversion_id', t.inversion_id, 'rol', t.rol) order by t.id)
        from crm.inversion_titulares t where t.inversionista_id = i.id), '[]'::jsonb),
      'reservas', coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'lead_id', rv.lead_id, 'inversionista_id', rv.inversionista_id, 'expira', rv.expira_en, 'sellada', rv.efectos_iniciados_en is not null) order by rv.lead_id)
        from crm.conversion_reservas rv
        where rv.inversionista_id = i.id or rv.lead_id in (select l.id from crm.leads l where l.inversionista_id = i.id)), '[]'::jsonb),
      'claim', (select m.resultado->>'estado' from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || i.id::text),
      'predecesoras', coalesce((select pg_catalog.jsonb_agg(p.id order by p.id) from crm.inversionistas p where p.inversionista_canonico_id = i.id), '[]'::jsonb)
    ) order by i.id)
    from crm.inversionistas i where i.id in (p_a, p_b)), '[]'::jsonb))
$$;
revoke all on function private.fusion_estado_jsonb(uuid, uuid) from public, anon, authenticated, service_role;

-- Bloqueos de una fusión (los mismos textos en la previsualización y bajo los locks de la fusión).
create or replace function private.fusion_bloqueos(p_perdedora uuid, p_canonica uuid)
returns text[]
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_b text[] := '{}'; v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_n integer;
begin
  if p_perdedora is null or p_canonica is null then
    return array['Faltan las dos identidades'];
  end if;
  if p_perdedora = p_canonica then
    return array['La perdedora y la canónica son la misma identidad'];
  end if;
  select * into v_p from crm.inversionistas where id = p_perdedora;
  if not found then return array['La identidad perdedora no existe']; end if;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if not found then return array['La identidad canónica no existe']; end if;
  if v_p.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_p.id)::text)::text);
  elsif v_p.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La perdedora no está activa (' || v_p.estado || '): revisión de Gerencia')::text);
  end if;
  if v_c.estado = 'fusionado' then
    v_b := pg_catalog.array_append(v_b, ('La canónica ya está fusionada: usa su canónica ' || private.inversionista_canonica(v_c.id)::text)::text);
  elsif v_c.estado <> 'activo' then
    v_b := pg_catalog.array_append(v_b, ('La canónica no está activa (' || v_c.estado || '): revisión de Gerencia')::text);
  end if;
  select count(*) into v_n from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica);
  if v_n > 1 then
    v_b := pg_catalog.array_append(v_b, 'Las dos identidades tienen lead: reconciliación de clase E hasta F5 (dos leads)'::text);
  end if;
  if v_p.perfil_id is not null and v_c.perfil_id is not null and v_p.perfil_id <> v_c.perfil_id then
    v_b := pg_catalog.array_append(v_b, 'Las dos identidades tienen perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)'::text);
  end if;
  if exists (select 1 from crm.multiempresa_idempotencia m
              where m.clave in ('auth_persona:' || p_perdedora::text, 'auth_persona:' || p_canonica::text)
                and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    v_b := pg_catalog.array_append(v_b, 'Hay un alta o conversión en curso (claim de Auth no terminal): termina o deja caducar'::text);
  end if;
  if exists (select 1 from crm.conversion_reservas r
              left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id in (p_perdedora, p_canonica) or l.inversionista_id in (p_perdedora, p_canonica))
                and (r.expira_en > pg_catalog.now()
                     or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    v_b := pg_catalog.array_append(v_b, 'Hay una reserva de conversión viva o sellada sin convertir: termina o deja caducar'::text);
  end if;
  return v_b;
end;
$$;
revoke all on function private.fusion_bloqueos(uuid, uuid) from public, anon, authenticated, service_role;

-- Advisory de TODOS los documentos vigentes de un conjunto de identidades, ordenados por texto
-- (misma clave que private.identidad_bloquear_documento; reentrante).
create or replace function private.identidad_bloquear_documentos_de(p_ids uuid[])
returns text[]
language plpgsql
security definer
set search_path = ''
as $$
declare v_docs text[]; v_k text;
begin
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d
        where d.inversionista_id = any(p_ids) and d.estado = 'vigente') s;
  if v_docs is not null then
    foreach v_k in array v_docs loop
      perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
    end loop;
  end if;
  return coalesce(v_docs, '{}');
end;
$$;
revoke all on function private.identidad_bloquear_documentos_de(uuid[]) from public, anon, authenticated, service_role;

-- Cancela las tareas pendientes de un lead como sistema (mismo sello que marcar_no_contactar, b2).
create or replace function private.cancelar_tareas_pendientes_lead(p_lead_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
  update crm.tareas t set estado = 'cancelada' where t.lead_id = p_lead_id and t.estado = 'pendiente';
  get diagnostics v_n = row_count;
  perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  return v_n;
end;
$$;
revoke all on function private.cancelar_tareas_pendientes_lead(uuid) from public, anon, authenticated, service_role;

-- El motivo de una puerta de Gerencia no puede llevar ninguno de los documentos implicados.
create or replace function private.motivo_sin_documento(p_motivo text, p_docs text[])
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare v_m text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_motivo, ''), '[^A-Za-z0-9]', '', 'g')); v_d text;
begin
  if p_motivo is null or length(pg_catalog.btrim(p_motivo)) not between 3 and 500 then
    raise exception 'El motivo debe tener entre 3 y 500 caracteres' using errcode = '22023';
  end if;
  foreach v_d in array coalesce(p_docs, '{}') loop
    if v_d is not null and length(v_d) >= 6 and pg_catalog.strpos(v_m, pg_catalog.upper(v_d)) > 0 then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end loop;
end;
$$;
revoke all on function private.motivo_sin_documento(text, text[]) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2.3 Previsualización de una fusión (Gerencia, solo lectura, sin locks)
-- ---------------------------------------------------------------------------
create or replace function crm.fusion_previsualizar_fn(p_perdedora uuid, p_canonica uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_lead crm.leads%rowtype;
  v_bloq text[]; v_adv text[] := '{}'; v_foto jsonb;
  v_tp crm.inversionista_responsables%rowtype; v_tc crm.inversionista_responsables%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia previsualiza una fusión' using errcode = '42501';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  select * into v_p from crm.inversionistas where id = p_perdedora;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if v_p.id is null or v_c.id is null or p_perdedora = p_canonica then
    return pg_catalog.jsonb_build_object('viable', false, 'bloqueos', pg_catalog.to_jsonb(v_bloq),
      'advertencias', '[]'::jsonb, 'hash', null, 'foto', null, 'impacto', null);
  end if;
  if exists (select 1 from crm.inversionista_identificadores a
             join crm.inversionista_identificadores b on b.tipo_documento = a.tipo_documento and b.documento_normalizado <> a.documento_normalizado
             where a.inversionista_id = p_perdedora and b.inversionista_id = p_canonica and a.estado = 'vigente' and b.estado = 'vigente') then
    v_adv := pg_catalog.array_append(v_adv, 'Las dos tienen un documento vigente del mismo tipo: una está mal; corrige el documento después de fusionar'::text);
  end if;
  if v_p.no_contactar <> v_c.no_contactar then
    v_adv := pg_catalog.array_append(v_adv, 'Vetos distintos: el resultado es «No contactar» y se cancelan las tareas pendientes del lead'::text);
  end if;
  select * into v_tp from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tc from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tp.responsable_id is not null and v_tc.responsable_id is not null and v_tp.responsable_id <> v_tc.responsable_id then
    v_adv := pg_catalog.array_append(v_adv, 'Responsables de relación distintos: gana el de la canónica; se cierra el tramo de la perdedora'::text);
  elsif v_tp.responsable_id is not null and v_tc.responsable_id is null then
    v_adv := pg_catalog.array_append(v_adv, 'La canónica hereda el responsable de relación de la perdedora'::text);
  end if;
  if exists (select 1 from crm.inversiones where inversionista_id = p_perdedora)
     or exists (select 1 from crm.cierres_externos where inversionista_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora tiene inversiones o cierres: se reapuntan a la canónica; el dinero y sus fotos no se tocan'::text);
  end if;
  if exists (select 1 from crm.inversionistas where inversionista_canonico_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora es canónica de otras identidades fusionadas: se aplanan a la nueva canónica'::text);
  end if;
  select * into v_lead from crm.leads where inversionista_id in (p_perdedora, p_canonica) order by id limit 1;
  if v_lead.id is not null and not v_lead.activo then
    v_adv := pg_catalog.array_append(v_adv, 'El lead está inactivo: no se deja nota de actividad (el libro de fusiones es el rastro)'::text);
  end if;
  v_adv := pg_catalog.array_append(v_adv, 'La conversión mensual sigue siendo por lead/cliente hasta Contrato-F3: la fusión no altera cifras ni meses sellados'::text);
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  return pg_catalog.jsonb_build_object(
    'viable', pg_catalog.cardinality(v_bloq) = 0,
    'bloqueos', pg_catalog.to_jsonb(v_bloq),
    'advertencias', pg_catalog.to_jsonb(v_adv),
    'hash', private.idem_hash(v_foto),
    'foto', v_foto,
    'impacto', pg_catalog.jsonb_build_object(
      'leads', (select count(*) from crm.leads where inversionista_id = p_perdedora),
      'puente', (select count(*) from crm.inversionista_leads where inversionista_id = p_perdedora),
      'identificadores', (select count(*) from crm.inversionista_identificadores where inversionista_id = p_perdedora and estado = 'vigente'),
      'tramos', (select count(*) from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null),
      'cierres', (select count(*) from crm.cierres_externos where inversionista_id = p_perdedora),
      'inversiones', (select count(*) from crm.inversiones where inversionista_id = p_perdedora),
      'titulares', (select count(*) from crm.inversion_titulares where inversionista_id = p_perdedora),
      'reservas', (select count(*) from crm.conversion_reservas where inversionista_id = p_perdedora),
      'predecesoras', (select count(*) from crm.inversionistas where inversionista_canonico_id = p_perdedora)));
end;
$$;
revoke all on function crm.fusion_previsualizar_fn(uuid, uuid) from public, anon, service_role;
grant execute on function crm.fusion_previsualizar_fn(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.4 Fusión (Gerencia): orden total, huella recalculada bajo locks, matriz completa, libro append-only
-- ---------------------------------------------------------------------------
create or replace function crm.fusionar_inversionistas_fn(p_perdedora uuid, p_canonica uuid, p_motivo text, p_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_row crm.inversionistas%rowtype;
  v_lead crm.leads%rowtype; v_docs text[]; v_docs2 text[]; v_bloq text[]; v_foto jsonb; v_ahora timestamptz;
  v_veto boolean; v_tramo_p crm.inversionista_responsables%rowtype; v_tramo_c crm.inversionista_responsables%rowtype;
  v_t crm.inversion_titulares%rowtype; v_t2 crm.inversion_titulares%rowtype; v_fusion_id uuid; v_impacto jsonb;
  v_n_leads integer; v_n_ident integer := 0; v_n_cierres integer := 0; v_n_inv integer := 0; v_n_tit integer := 0;
  v_n_tit_dup integer := 0; v_n_res integer := 0; v_n_pred integer := 0; v_n_tareas integer := 0; v_n_puente integer := 0;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia fusiona identidades' using errcode = '42501';
  end if;
  if p_perdedora is null or p_canonica is null or p_perdedora = p_canonica then
    raise exception 'Indica dos identidades distintas' using errcode = '22023';
  end if;
  if p_hash is null or p_hash !~ '^[a-f0-9]{64}$' then
    raise exception 'Falta la huella de la previsualización (p_hash)' using errcode = '22023';
  end if;

  -- 1. jerarquía compartida [E3-2] -> 2. documentos vigentes de ambas (leídos sin lock, ordenados)
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  v_docs := private.identidad_bloquear_documentos_de(array[p_perdedora, p_canonica]);
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(split_part(k, ':', 2)) from unnest(v_docs) k));
  -- 3. identidades FOR UPDATE por id ascendente, revalidando el conjunto de documentos
  for v_row in select * from crm.inversionistas where id in (p_perdedora, p_canonica) order by id for update loop
    if v_row.id = p_perdedora then v_p := v_row; else v_c := v_row; end if;
  end loop;
  if v_p.id is null or v_c.id is null then
    raise exception 'Alguna de las identidades no existe' using errcode = 'P0002';
  end if;
  select pg_catalog.array_agg(k order by k) into v_docs2
  from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
        from crm.inversionista_identificadores d where d.inversionista_id in (p_perdedora, p_canonica) and d.estado = 'vigente') s;
  if coalesce(v_docs2, '{}') is distinct from v_docs then
    raise exception 'Los documentos de la persona cambiaron mientras se esperaba; vuelve a previsualizar' using errcode = '40001';
  end if;
  -- 4. perfil FOR SHARE -> 5. cierres -> 6. inversiones/titulares -> 7. tramos -> 8. tareas -> 9. leads -> 10. reservas -> 11. claims
  perform 1 from public.perfiles p where p.id in (v_p.perfil_id, v_c.perfil_id) order by p.id for share;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id in (p_perdedora, p_canonica)
      or ce.lead_id in (select l.id from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica))
   order by ce.id for update;
  perform 1 from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica) order by i.id for update;
  perform 1 from crm.inversion_titulares t
   where t.inversionista_id in (p_perdedora, p_canonica)
      or t.inversion_id in (select i.id from crm.inversiones i where i.inversionista_id in (p_perdedora, p_canonica))
   order by t.id for update;
  perform 1 from crm.inversionista_responsables r where r.inversionista_id in (p_perdedora, p_canonica) and r.hasta is null order by r.id for update;
  perform 1 from crm.tareas t
   where t.estado = 'pendiente' and t.lead_id in (select l.id from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica))
   order by t.id for update;
  select count(*) into v_n_leads from (select l.id from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica) order by l.id for update) s;
  select * into v_lead from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica) order by l.id limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id in (p_perdedora, p_canonica)
      or r.lead_id in (select l.id from crm.leads l where l.inversionista_id in (p_perdedora, p_canonica))
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
  -- perdedora primero (sale del índice parcial de perfil); nunca se borra; conserva perfil/veto/responsable como historia
  update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = p_canonica, fusionado_en = v_ahora where id = p_perdedora;
  -- predecesoras aplanadas [E3-12]
  update crm.inversionistas set inversionista_canonico_id = p_canonica where inversionista_canonico_id = p_perdedora and id <> p_canonica;
  get diagnostics v_n_pred = row_count;
  -- perfil
  if v_c.perfil_id is null and v_p.perfil_id is not null then
    update crm.inversionistas set perfil_id = v_p.perfil_id where id = p_canonica;
  end if;
  -- veto OR en la canónica [E3-9]
  if v_veto and not v_c.no_contactar then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(v_p.no_contactar_en, v_ahora),
           no_contactar_por = coalesce(v_p.no_contactar_por, v_uid)
     where id = p_canonica;
  end if;
  -- responsable de relación
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
  -- identificadores: los vigentes de P -> histórico y REEMITIDOS en C (el resolver devuelve C directamente)
  update crm.inversionista_identificadores d set estado = 'historico', vigente_hasta = v_ahora
   where d.inversionista_id = p_perdedora and d.estado = 'vigente';
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
  select p_canonica, d.tipo_documento, d.documento_normalizado, d.documento_original, 'vigente', d.verificado, 'fusion', v_ahora, v_uid
  from crm.inversionista_identificadores d
  where d.inversionista_id = p_perdedora and d.estado = 'historico' and d.vigente_hasta = v_ahora
  order by d.id;
  get diagnostics v_n_ident = row_count;
  -- lead y puente (si el lead es de P); veto al lead y tareas (cualquiera que sea su lado)
  if v_lead.id is not null and v_lead.inversionista_id = p_perdedora then
    update crm.leads set inversionista_id = p_canonica where id = v_lead.id;
    update crm.inversionista_leads set inversionista_id = p_canonica where lead_id = v_lead.id and inversionista_id = p_perdedora;
    get diagnostics v_n_puente = row_count;
  end if;
  if v_lead.id is not null and v_veto and not v_lead.no_contactar then
    v_n_tareas := private.cancelar_tareas_pendientes_lead(v_lead.id);
    update crm.leads set no_contactar = true where id = v_lead.id;
  end if;
  -- cierres: los de P, y el del lead de P que aún no llevaba persona
  update crm.cierres_externos ce set inversionista_id = p_canonica
   where ce.inversionista_id = p_perdedora
      or (v_lead.id is not null and v_lead.inversionista_id = p_perdedora and ce.lead_id = v_lead.id and ce.inversionista_id is null);
  get diagnostics v_n_cierres = row_count;
  -- inversiones y titulares (principal único; duplicado exacto del par se elimina)
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
  -- reservas (ya no vivas ni pendientes: bloqueo del paso 12)
  update crm.conversion_reservas set inversionista_id = p_canonica where inversionista_id = p_perdedora;
  get diagnostics v_n_res = row_count;
  -- libro append-only (ids, nunca documentos)
  v_impacto := pg_catalog.jsonb_build_object('lead_id', v_lead.id, 'lead_reapuntado', v_lead.id is not null and v_lead.inversionista_id = p_perdedora,
    'puente', v_n_puente, 'identificadores_reemitidos', v_n_ident, 'tramo_cerrado', v_tramo_p.id, 'tramo_heredado', v_tramo_c.id is null and v_tramo_p.id is not null,
    'perfil_heredado', v_c.perfil_id is null and v_p.perfil_id is not null, 'veto', v_veto, 'tareas_canceladas', v_n_tareas,
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
$$;
revoke all on function crm.fusionar_inversionistas_fn(uuid, uuid, text, text) from public, anon, service_role;
grant execute on function crm.fusionar_inversionistas_fn(uuid, uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.5 Corrección de documento (Gerencia): el vigente pasa a histórico; nuevo vigente verificado;
--     realinea perfil y lead SOLO si llevaban el documento reemplazado; motivo en el libro de correcciones
-- ---------------------------------------------------------------------------
create or replace function crm.corregir_documento_inversionista_fn(
  p_inversionista uuid, p_tipo text, p_documento text, p_motivo text, p_identificador_anterior uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_tipo text := pg_catalog.upper(pg_catalog.btrim(coalesce(p_tipo, '')));
  v_norm text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento, ''), '[^A-Za-z0-9]', '', 'g'));
  v_inv crm.inversionistas%rowtype; v_old_id uuid; v_old_tipo text; v_old_norm text; v_n integer; v_otro uuid; v_ahora timestamptz;
  v_perfil_id uuid; v_perfil_dni text; v_perfil_tipo text; v_lead crm.leads%rowtype; v_new_id uuid; v_corr_id uuid;
  v_perfil_res text; v_lead_res text; v_k text; v_docs text[];
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia corrige el documento de una persona' using errcode = '42501';
  end if;
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
  if p_identificador_anterior is not null then
    select d.id, d.tipo_documento, d.documento_normalizado into v_old_id, v_old_tipo, v_old_norm
    from crm.inversionista_identificadores d
    where d.id = p_identificador_anterior and d.inversionista_id = p_inversionista and d.estado = 'vigente';
    if not found then
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
  perform private.motivo_sin_documento(p_motivo, array[v_norm, v_old_norm]);

  -- jerarquía [E3-2] -> advisories de viejo y nuevo, ordenados -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  select pg_catalog.array_agg(k order by k) into v_docs
  from (select distinct k from unnest(array[v_tipo || ':' || v_norm, v_old_tipo || ':' || v_old_norm]) k where k is not null) s;
  foreach v_k in array v_docs loop
    perform private.identidad_bloquear_documento(split_part(v_k, ':', 1), split_part(v_k, ':', 2));
  end loop;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se corregía (estado %); vuelve a intentarlo', v_inv.estado using errcode = '40001';
  end if;
  -- revalidar el que sale [E3-5]
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
  select d.inversionista_id into v_otro from crm.inversionista_identificadores d
  where d.tipo_documento = v_tipo and d.documento_normalizado = v_norm and d.estado = 'vigente';
  if v_otro = p_inversionista then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista);
  elsif v_otro is not null then
    raise exception 'El documento pertenece a otra persona reconocida: fusiona las identidades en vez de corregir' using errcode = 'P0409';
  end if;
  -- alta/conversión en curso [E3-7]: claim y reservas bajo lock
  perform 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text for update;
  if exists (select 1 from crm.multiempresa_idempotencia m where m.clave = 'auth_persona:' || p_inversionista::text
              and coalesce(m.resultado->>'estado', '') <> 'enlazado') then
    raise exception 'Hay un alta o conversión en curso para esta persona: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  -- perfil enlazado FOR UPDATE (escribe) -> cierre -> tareas -> lead -> reservas
  if v_inv.perfil_id is not null then
    select p.id, p.dni, p.tipo_documento into v_perfil_id, v_perfil_dni, v_perfil_tipo from public.perfiles p where p.id = v_inv.perfil_id for update;
  end if;
  perform 1 from crm.cierres_externos ce
   where ce.inversionista_id = p_inversionista or ce.lead_id in (select l.id from crm.leads l where l.inversionista_id = p_inversionista)
   order by ce.id for update;
  perform 1 from crm.tareas t where t.estado = 'pendiente'
     and t.lead_id in (select l.id from crm.leads l where l.inversionista_id = p_inversionista) order by t.id for update;
  select * into v_lead from crm.leads l where l.inversionista_id = p_inversionista order by l.id for update limit 1;
  perform 1 from crm.conversion_reservas r
   where r.inversionista_id = p_inversionista or (v_lead.id is not null and r.lead_id = v_lead.id) order by r.lead_id for update;
  if exists (select 1 from crm.conversion_reservas r left join crm.leads l on l.id = r.lead_id
              where (r.inversionista_id = p_inversionista or (v_lead.id is not null and r.lead_id = v_lead.id))
                and (r.expira_en > pg_catalog.now() or (r.efectos_iniciados_en is not null and coalesce(l.etapa, '') <> 'convertido'))) then
    raise exception 'Hay una reserva de conversión viva o sellada sin convertir: termina o deja caducar antes de corregir' using errcode = 'P0409';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  -- terceros, bajo los locks (la excepción del trigger de disponibilidad confía en esto) [E3-6]
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

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_old_id is not null then
    update crm.inversionista_identificadores set estado = 'historico', vigente_hasta = v_ahora where id = v_old_id;
  end if;
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original, estado, verificado, fuente, vigente_desde, creado_por)
  values (p_inversionista, v_tipo, v_norm, p_documento, 'vigente', true, 'correccion', v_ahora, v_uid)
  returning id into v_new_id;
  -- perfil: solo si llevaba el documento reemplazado
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
  -- lead: solo si llevaba el documento reemplazado (crm.leads solo representa DNI)
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
  insert into crm.inversionista_correcciones
    (inversionista_id, identificador_anterior_id, identificador_nuevo_id, motivo, perfil_realineado, lead_realineado, por)
  values (p_inversionista, v_old_id, v_new_id, p_motivo, v_perfil_res = 'actualizado', v_lead_res, v_uid)
  returning id into v_corr_id;
  if v_lead.id is not null and v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Documento corregido por Gerencia (' || v_tipo || ')',
            pg_catalog.jsonb_build_object('evento', 'correccion_documento', 'correccion_id', v_corr_id,
                                          'inversionista_id', p_inversionista, 'lead', v_lead_res),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'corregido', 'inversionista_id', p_inversionista,
    'correccion_id', v_corr_id, 'identificador_nuevo_id', v_new_id, 'identificador_anterior_id', v_old_id,
    'perfil', v_perfil_res, 'lead', v_lead_res);
end;
$$;
revoke all on function crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) from public, anon, service_role;
grant execute on function crm.corregir_documento_inversionista_fn(uuid, text, text, text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.6 Enlace de un lead suelto a una persona reconocida (Gerencia): la revisión humana de la clase E
-- ---------------------------------------------------------------------------
create or replace function crm.enlazar_lead_inversionista_fn(p_lead_id uuid, p_inversionista uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv crm.inversionistas%rowtype; v_lead0 crm.leads%rowtype; v_lead crm.leads%rowtype; v_cierre crm.cierres_externos%rowtype;
  v_perfil_inv uuid; v_ahora timestamptz; v_veto boolean; v_n_tareas integer := 0;
  v_perfil_completado boolean := false; v_cierre_completado boolean := false;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia enlaza un lead a una persona' using errcode = '42501';
  end if;
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
  perform private.motivo_sin_documento(p_motivo, array[v_lead0.dni]);

  -- jerarquía -> documento del lead -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  perform private.identidad_bloquear_documento('DNI', v_lead0.dni);
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if v_inv.estado <> 'activo' then
    raise exception 'La persona cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if not exists (select 1 from crm.inversionista_identificadores d
                 where d.inversionista_id = p_inversionista and d.tipo_documento = 'DNI'
                   and d.documento_normalizado = v_lead0.dni and d.estado = 'vigente' and d.verificado = true) then
    if private.inversionista_por_documento('DNI', v_lead0.dni) is not null then
      raise exception 'El DNI del lead pertenece a otra persona reconocida: fusiona o corrige primero' using errcode = 'P0409';
    end if;
    raise exception 'El DNI del lead no es un documento vigente y verificado de esta persona: corrige el documento primero' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.leads l where l.inversionista_id = p_inversionista) then
    raise exception 'La persona ya tiene su lead (activo o no): reconciliación de clase E hasta F5' using errcode = 'P0409';
  end if;
  -- unión de enlaces del lead [E3-10]: perfil (FOR SHARE) -> cierre -> puente -> tareas -> lead -> reservas -> claim
  if v_lead0.perfil_id is not null then
    perform 1 from public.perfiles p where p.id = v_lead0.perfil_id for share;
    select i.id into v_perfil_inv from crm.inversionistas i where i.perfil_id = v_lead0.perfil_id and i.estado <> 'fusionado' limit 1;
    if v_perfil_inv is not null and v_perfil_inv <> p_inversionista then
      raise exception 'El perfil de cliente del lead pertenece a otra persona reconocida: reconciliación (fusión/corrección)' using errcode = 'P0409';
    end if;
    if v_perfil_inv is null and v_inv.perfil_id is not null and v_inv.perfil_id <> v_lead0.perfil_id then
      raise exception 'La persona ya tiene otro perfil de cliente: reconciliación de clase E hasta F5 (dos perfiles)' using errcode = 'P0409';
    end if;
  end if;
  select * into v_cierre from crm.cierres_externos ce where ce.lead_id = p_lead_id for update;
  if v_cierre.id is not null and v_cierre.inversionista_id is not null and v_cierre.inversionista_id <> p_inversionista then
    raise exception 'El cierre del lead pertenece a otra persona reconocida: reconciliación' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id and il.inversionista_id <> p_inversionista) then
    raise exception 'El puente del lead apunta a otra persona: reconciliación' using errcode = 'P0409';
  end if;
  perform 1 from crm.tareas t where t.estado = 'pendiente' and t.lead_id = p_lead_id order by t.id for update;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if v_lead.inversionista_id is not null or v_lead.perfil_id is distinct from v_lead0.perfil_id or v_lead.dni is distinct from v_lead0.dni then
    raise exception 'El lead cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if exists (select 1 from crm.conversion_reservas r where r.lead_id = p_lead_id and r.inversionista_id is not null
              and r.inversionista_id <> p_inversionista and (r.expira_en > pg_catalog.now() or r.efectos_iniciados_en is not null)) then
    raise exception 'El lead tiene una reserva de conversión de otra persona' using errcode = 'P0409';
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
  if v_lead.activo then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (p_lead_id, 'nota', 'Lead enlazado a una persona reconocida (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'enlace_identidad', 'inversionista_id', p_inversionista,
                                          'motivo', pg_catalog.left(p_motivo, 500), 'veto', v_veto),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', p_inversionista,
    'perfil_completado', v_perfil_completado, 'cierre_completado', v_cierre_completado, 'veto', v_veto, 'tareas_canceladas', v_n_tareas);
end;
$$;
revoke all on function crm.enlazar_lead_inversionista_fn(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.enlazar_lead_inversionista_fn(uuid, uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2.7 Reasignación del responsable de relación (Gerencia): cierra/abre tramo; no mueve atribuciones (§6)
-- ---------------------------------------------------------------------------
create or replace function crm.reasignar_responsable_relacion_fn(p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode = '42501';
  end if;
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  if not exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                 where e.perfil_id = p_nuevo_responsable and e.activo and p.activo
                   and e.rol_crm in ('vendedor', 'supervisor', 'gerencia')) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial' using errcode = '22023';
  end if;
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Responsable de relación reasignado (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable);
end;
$$;
revoke all on function crm.reasignar_responsable_relacion_fn(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.reasignar_responsable_relacion_fn(uuid, uuid, text) to authenticated;


do $post$
begin
  if to_regprocedure('private.inversionista_canonica(uuid)') is null
     or to_regprocedure('private.fusion_estado_jsonb(uuid,uuid)') is null
     or to_regprocedure('private.fusion_bloqueos(uuid,uuid)') is null
     or to_regprocedure('private.identidad_bloquear_documentos_de(uuid[])') is null
     or to_regprocedure('private.cancelar_tareas_pendientes_lead(uuid)') is null
     or to_regprocedure('private.motivo_sin_documento(text,text[])') is null
     or to_regprocedure('crm.fusion_previsualizar_fn(uuid,uuid)') is null
     or to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is null
     or to_regprocedure('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)') is null
     or to_regprocedure('crm.enlazar_lead_inversionista_fn(uuid,uuid,text)') is null
     or to_regprocedure('crm.reasignar_responsable_relacion_fn(uuid,uuid,text)') is null
     or to_regprocedure('private.inversionista_correcciones_append_only()') is null then
    raise exception 'POSTFLIGHT b5: falta alguna función nueva';
  end if;

  if (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='saga_conversion_fn') = 0
     or (select strpos(p.prosrc, 'F2.b (b5)') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_disponibilidad_atomica') = 0 then
    raise exception 'POSTFLIGHT b5: transformaciones ausentes';
  end if;
  if has_function_privilege('anon', 'private.inversionista_canonica(uuid)', 'EXECUTE') or has_function_privilege('service_role', 'private.inversionista_canonica(uuid)', 'EXECUTE') or has_function_privilege('authenticated', 'private.inversionista_canonica(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.fusion_estado_jsonb(uuid,uuid)', 'EXECUTE') or has_function_privilege('service_role', 'private.fusion_estado_jsonb(uuid,uuid)', 'EXECUTE') or has_function_privilege('authenticated', 'private.fusion_estado_jsonb(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.fusion_bloqueos(uuid,uuid)', 'EXECUTE') or has_function_privilege('service_role', 'private.fusion_bloqueos(uuid,uuid)', 'EXECUTE') or has_function_privilege('authenticated', 'private.fusion_bloqueos(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.identidad_bloquear_documentos_de(uuid[])', 'EXECUTE') or has_function_privilege('service_role', 'private.identidad_bloquear_documentos_de(uuid[])', 'EXECUTE') or has_function_privilege('authenticated', 'private.identidad_bloquear_documentos_de(uuid[])', 'EXECUTE')
     or has_function_privilege('anon', 'private.cancelar_tareas_pendientes_lead(uuid)', 'EXECUTE') or has_function_privilege('service_role', 'private.cancelar_tareas_pendientes_lead(uuid)', 'EXECUTE') or has_function_privilege('authenticated', 'private.cancelar_tareas_pendientes_lead(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'private.motivo_sin_documento(text,text[])', 'EXECUTE') or has_function_privilege('service_role', 'private.motivo_sin_documento(text,text[])', 'EXECUTE') or has_function_privilege('authenticated', 'private.motivo_sin_documento(text,text[])', 'EXECUTE')
     or has_function_privilege('anon', 'crm.fusion_previsualizar_fn(uuid,uuid)', 'EXECUTE') or has_function_privilege('service_role', 'crm.fusion_previsualizar_fn(uuid,uuid)', 'EXECUTE') or not has_function_privilege('authenticated', 'crm.fusion_previsualizar_fn(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)', 'EXECUTE') or has_function_privilege('service_role', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)', 'EXECUTE') or not has_function_privilege('authenticated', 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', 'EXECUTE') or has_function_privilege('service_role', 'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', 'EXECUTE') or not has_function_privilege('authenticated', 'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', 'EXECUTE') or has_function_privilege('service_role', 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', 'EXECUTE') or not has_function_privilege('authenticated', 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', 'EXECUTE') or has_function_privilege('service_role', 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', 'EXECUTE') or not has_function_privilege('authenticated', 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid in ('private.inversionista_canonica(uuid)'::regprocedure, 'private.fusion_estado_jsonb(uuid,uuid)'::regprocedure, 'private.fusion_bloqueos(uuid,uuid)'::regprocedure, 'private.identidad_bloquear_documentos_de(uuid[])'::regprocedure, 'private.cancelar_tareas_pendientes_lead(uuid)'::regprocedure, 'private.motivo_sin_documento(text,text[])'::regprocedure, 'crm.fusion_previsualizar_fn(uuid,uuid)'::regprocedure, 'crm.fusionar_inversionistas_fn(uuid,uuid,text,text)'::regprocedure, 'crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)'::regprocedure, 'crm.enlazar_lead_inversionista_fn(uuid,uuid,text)'::regprocedure, 'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'::regprocedure) and a.grantee = 0) then
    raise exception 'POSTFLIGHT b5: grants incorrectos';
  end if;

  if to_regclass('crm.inversionista_correcciones') is null
     or not (select relrowsecurity from pg_class where oid = 'crm.inversionista_correcciones'::regclass)
     or has_table_privilege('authenticated', 'crm.inversionista_correcciones', 'SELECT')
     or has_table_privilege('service_role', 'crm.inversionista_correcciones', 'SELECT') then
    raise exception 'POSTFLIGHT b5: tabla de correcciones sin RLS o con grants';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b5: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b5 OK: fusión, corrección documental, enlace de lead suelto y reasignación (Gerencia); 4 vivas transformadas en su rama ON. Bandera APAGADA.';
end
$post$;
commit;
