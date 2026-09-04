-- REGISTRO en supabase_migrations.schema_migrations del lote Contrato-F2 (8 versiones).

-- `db query --linked --file` NO registra: correr ESTE archivo DESPUÉS de aplicar las 8, en orden.

-- Un elemento por versión = el fichero entero (un solo mensaje, como se aplicó). Idempotente.

begin;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903190000', 'crm_fix_resolver_unique_violation', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA — Fix del resolver: relectura de carrera coherente
-- ============================================================================
--
-- QUE: `private.inversionista_resolver` tiene DOS caminos de lectura. La rama
-- normal exige identificador VIGENTE + VERIFICADO + identidad NO fusionada
-- (contrato §4.2). Pero el handler `unique_violation` (relectura tras perder la
-- carrera del indice unico) releia con SOLO `estado='vigente'`, sin `verificado`
-- ni el JOIN a `crm.inversionistas` — podia DEVOLVER una identidad que la rama
-- normal habria RECHAZADO (no verificada, o fusionada). Bug latente hallado por
-- Codex; no ha tenido efecto vivo porque el resolver aun no lo llama ninguna
-- puerta (F3 apagada), pero hay que corregirlo ANTES de encender F3.
--
-- COMO: CREATE OR REPLACE que copia LITERALMENTE el SELECT de la rama normal
-- (con JOIN + verificado + no-fusionado) tambien en el handler. Si no aparece
-- una ganadora valida, conserva el error higienizado (no reeleva la nativa, cuyo
-- DETAIL lleva el documento en claro). CREATE OR REPLACE conserva los grants/
-- revokes existentes (sin EXECUTE para la Data API). Reversa: reaplicar F1.
--
-- Requiere F1 (20260903160000).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_fix_resolver_uv'));

do $guard$
begin
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null then
    raise exception 'FIX resolver: falta F1 (private.inversionista_resolver)';
  end if;
end
$guard$;

create or replace function private.inversionista_resolver(
  p_tipo text,
  p_documento text,
  p_verificado boolean default false,
  p_fuente text default 'resolver'
) returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_norm text;
  v_id uuid;
begin
  if p_tipo is null or p_tipo not in ('DNI','CE','PASAPORTE') then
    raise exception using errcode = '22023', message = 'Tipo de documento invalido';
  end if;
  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'));
  -- Validacion POR TIPO alineada con crm.cierres_externos (20260812000259).
  if (p_tipo = 'DNI'       and v_norm !~ '^[0-9]{8}$')
     or (p_tipo = 'CE'        and v_norm !~ '^[0-9]{9,12}$')
     or (p_tipo = 'PASAPORTE' and v_norm !~ '^[A-Z0-9]{6,12}$') then
    raise exception using errcode = '22023', message = 'Documento invalido para el tipo';
  end if;

  -- Serializa la creacion del MISMO documento (otros documentos no contienden).
  -- Asume READ COMMITTED (el default de las puertas F3): bajo REPEATABLE READ un
  -- reintento tras el lock podria no ver al ganador (snapshot fijado antes).
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('inv_resolver:' || p_tipo || ':' || v_norm));

  -- Solo resuelve un identificador VIGENTE, VERIFICADO y de identidad NO fusionada
  -- (contrato §4.2): nunca devuelve una identidad perdedora.
  select i.inversionista_id into v_id
  from crm.inversionista_identificadores i
  join crm.inversionistas inv on inv.id = i.inversionista_id
  where i.tipo_documento = p_tipo
    and i.documento_normalizado = v_norm
    and i.estado = 'vigente'
    and i.verificado = true
    and inv.estado <> 'fusionado'
  limit 1;
  if v_id is not null then
    return v_id;
  end if;

  -- No crea identidad OPERATIVA sin documento verificado (contrato §4.3).
  if p_verificado is not true then
    raise exception using errcode = '22023',
      message = 'No se crea identidad con documento sin verificar';
  end if;
  insert into crm.inversionistas (estado) values ('activo') returning id into v_id;
  insert into crm.inversionista_identificadores
    (inversionista_id, tipo_documento, documento_normalizado, documento_original,
     estado, verificado, fuente)
  values (v_id, p_tipo, v_norm, p_documento, 'vigente', true, coalesce(p_fuente, 'resolver'));
  return v_id;

exception when unique_violation then
  -- FIX (Codex): la relectura de carrera debe exigir las MISMAS condiciones que
  -- la rama normal — VIGENTE + VERIFICADO + identidad NO fusionada — para no
  -- devolver una identidad que la rama normal habria rechazado.
  -- (Los inserts de esta subtransaccion se deshacen solos al entrar aqui.)
  select i.inversionista_id into v_id
  from crm.inversionista_identificadores i
  join crm.inversionistas inv on inv.id = i.inversionista_id
  where i.tipo_documento = p_tipo
    and i.documento_normalizado = v_norm
    and i.estado = 'vigente'
    and i.verificado = true
    and inv.estado <> 'fusionado'
  limit 1;
  if v_id is null then
    -- No reelevar la unique_violation nativa: su DETAIL lleva el documento en
    -- claro (Key (tipo_documento, documento_normalizado)=(...)). Mensaje higienizado.
    raise exception using errcode = '23505',
      message = 'No se pudo resolver la identidad (documento en conflicto)';
  end if;
  return v_id;
end
$fn$;

-- El resolver sigue SIN EXECUTE para la Data API (CREATE OR REPLACE conserva las
-- ACL; se reafirma por si acaso).
revoke all on function private.inversionista_resolver(text,text,boolean,text)
  from public, anon, authenticated, service_role;

do $post$
begin
  if has_function_privilege('authenticated','private.inversionista_resolver(text,text,boolean,text)','EXECUTE')
     or has_function_privilege('anon','private.inversionista_resolver(text,text,boolean,text)','EXECUTE')
     or has_function_privilege('service_role','private.inversionista_resolver(text,text,boolean,text)','EXECUTE') then
    raise exception 'POSTFLIGHT fix resolver: quedo ejecutable por la Data API';
  end if;
  raise notice 'FIX resolver OK: relectura de carrera exige verificado + no-fusionado.';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903205000', 'crm_f2_idempotencia_helpers', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Idempotencia de la conversión (§8.2, Codex #5)
-- ============================================================================
--
-- QUE: F1 creó crm.multiempresa_idempotencia (clave, tipo, hash_payload, resultado)
-- pero nadie la usaba. Estos helpers la cablean: la MISMA clave + MISMO payload
-- devuelve el MISMO resultado; la misma clave con payload DISTINTO es conflicto.
-- Los usan las dos puertas de conversión (210000/220000): chequeo a la entrada,
-- guardado al éxito. Así «un reintento reutiliza lo que ya existe, no duplica»
-- (meta #4 de F3) queda formal, no solo por estado.
--
-- Privados (sin EXECUTE para la API): solo los llaman las puertas definer.
-- Requiere F1. Reversa: soltar las tres funciones (las puertas previas no las usan).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_idempotencia_helpers'));

do $guard$
begin
  if to_regclass('crm.multiempresa_idempotencia') is null then
    raise exception 'F2 idempotencia: falta F1 (crm.multiempresa_idempotencia)';
  end if;
end
$guard$;

-- Hash canónico del payload (jsonb::text canoniza el orden de claves).
create or replace function private.idem_hash(p_payload jsonb)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(p_payload::text, 'utf8')), 'hex')
$$;

-- Lee el resultado previo de una clave. NULL si no existe (o si la operación previa
-- no llegó a guardar resultado). Misma clave con OTRO hash = conflicto (P0409).
create or replace function private.idem_leer(p_clave text, p_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_res  jsonb;
  v_hash text;
begin
  select resultado, hash_payload into v_res, v_hash
  from crm.multiempresa_idempotencia
  where clave = p_clave;
  if not found then
    return null;
  end if;
  if v_hash <> p_hash then
    raise exception 'La misma operacion llego con datos distintos; no se puede reintentar asi'
      using errcode = 'P0409';
  end if;
  return v_res;
end;
$$;

-- Guarda el resultado. El PRIMER resultado gana (nunca se sobrescribe uno existente).
create or replace function private.idem_guardar(
  p_clave text, p_tipo text, p_hash text, p_resultado jsonb, p_por uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_n integer;
begin
  -- Atómico y CONFLICTIVO: la misma clave solo acepta el MISMO tipo+hash; el primer
  -- resultado gana (nunca se sobrescribe). Otra combinación = P0409 (Codex).
  insert into crm.multiempresa_idempotencia (clave, tipo, hash_payload, resultado, creado_por)
  values (p_clave, p_tipo, p_hash, p_resultado, p_por)
  on conflict (clave) do update
    set resultado = coalesce(crm.multiempresa_idempotencia.resultado, excluded.resultado)
    where crm.multiempresa_idempotencia.hash_payload = excluded.hash_payload
      and crm.multiempresa_idempotencia.tipo = excluded.tipo;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'La misma operacion llego con datos distintos; no se puede reintentar asi'
      using errcode = 'P0409';
  end if;
end;
$$;

-- Lectura de una bandera de rollout para el EDGE (crm-convertir-lead gatea su
-- cortocircuito idempotente con ella; la tabla no tiene grants API).
create or replace function crm.bandera_activa(p_nombre text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select activo from crm.multiempresa_flags where nombre = p_nombre), false)
$$;
revoke all on function crm.bandera_activa(text) from public, anon, service_role;
grant execute on function crm.bandera_activa(text) to authenticated;

revoke all on function private.idem_hash(jsonb) from public, anon, authenticated, service_role;
revoke all on function private.idem_leer(text, text) from public, anon, authenticated, service_role;
revoke all on function private.idem_guardar(text, text, text, jsonb, uuid) from public, anon, authenticated, service_role;

do $post$
begin
  if to_regprocedure('private.idem_hash(jsonb)') is null
     or to_regprocedure('private.idem_leer(text,text)') is null
     or to_regprocedure('private.idem_guardar(text,text,text,jsonb,uuid)') is null then
    raise exception 'POSTFLIGHT idempotencia: falta algún helper';
  end if;
  if has_function_privilege('authenticated','private.idem_leer(text,text)','EXECUTE') then
    raise exception 'POSTFLIGHT idempotencia: helper ejecutable por la API';
  end if;
  if to_regprocedure('crm.bandera_activa(text)') is null then raise exception 'POSTFLIGHT: falta crm.bandera_activa'; end if;
  raise notice 'F2 idempotencia OK: helpers privados listos para las puertas; bandera_activa para el edge.';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903210000', 'crm_f2_convertir_lead_identidad', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Puerta canónica: convertir_lead (Avance)
-- ============================================================================
--
-- QUE (contrato §8.2): la identidad se resuelve DENTRO de crm.convertir_lead.
-- El perfil se vincula a la identidad; el lead toma inversionista_id en el MISMO
-- UPDATE bajo la válvula (fuera de ahí el trigger #4 restauraría NULL). Esta
-- puerta REEMPLAZA lo que hacía el trigger trg_leads_reconocer_identidad (200000)
-- para Avance: reconoce identidad, abre el tramo de responsable-de-relación y
-- centraliza no_contactar. (El trigger se RETIRA en el cierre del lote, tras
-- reescribir también convertir_lead_externo — ver 2026090322xxxx.)
--
-- ORDEN DE LOCKS (Codex/auditor GO) — identidad ANTES del lead (comparte orden
-- con la fusión, mata el deadlock): [solo con bandera ON]
--   1. leer documento del perfil (sin lock)
--   2. advisory documental (dentro del resolver) + inversionistas FOR UPDATE
--   3. lead FOR UPDATE + revalidar
--   4. UPDATE bajo válvula (etapa, perfil_id, inversionista_id juntos)
--
-- DECISIONES (Miguel 03/09): UN SOLO LEAD TOTAL por persona (invariante #6) →
-- convertir un 2.º lead de la misma persona se RECHAZA (P0409); la nueva inversión
-- sobre el cliente existente es F5. Se CONSERVA UNIQUE(lead_id) (N inversiones=F5);
-- métrica por inversionista/mes = F3.
--
-- BANDERA resolver_en_puertas APAGADA = comportamiento IDÉNTICO a hoy: sin
-- identidad, sin idempotencia, «lead ya cerrado» en el reintento; la ÚNICA
-- diferencia observable es una clave ADITIVA inversionista_id=null en el JSON. Requiere F1, F2-backfill y el fix del resolver
-- (20260903190000) y los helpers de idempotencia (20260903205000). Reversa: script.

-- REBASE sobre P-058 (20260903215149, en prod el 03/09 por otra sesión): la
-- autorización de las puertas de conversión es `private.puede_gestionar_contratos_crm()`
-- (fuente única). Este cuerpo parte de ESA versión viva; con el `if` viejo la
-- habríamos revertido. Texto del predicado idéntico al que P-058 dejó instalado.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_convertir_lead'));

do $guard$
begin
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 convertir_lead: faltan F1/F2 (resolver o bandera)';
  end if;
end
$guard$;

create or replace function crm.convertir_lead(
  p_lead_id uuid,
  p_perfil_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
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
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (conversión previa a este lote) y mismo perfil: mismo hecho.
    if v_lead.perfil_id = p_perfil_id then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'perfil_id', p_perfil_id,
                                             'inversionista_id', v_lead.inversionista_id);
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
$$;

revoke all on function crm.convertir_lead(uuid, uuid)
  from public, anon, service_role;
grant execute on function crm.convertir_lead(uuid, uuid) to authenticated;

do $post$
begin
  if to_regprocedure('crm.convertir_lead(uuid,uuid)') is null then
    raise exception 'POSTFLIGHT F2 convertir_lead: la funcion no quedo creada';
  end if;
  raise notice 'F2 convertir_lead OK: resuelve identidad adentro (tras bandera); responsable y no_contactar replicados.';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903220000', 'crm_f2_convertir_lead_externo_identidad', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Puerta canónica: convertir_lead_externo (coop)
-- ============================================================================
--
-- QUE (contrato §8.3): la conversión cooperativa resuelve la identidad DENTRO de
-- su transacción; el cierre nace con lead_id E inversionista_id; se crea la
-- inversión (colgada de la identidad) y su titular principal; el lead toma
-- inversionista_id en el MISMO UPDATE bajo la válvula. NO crea Auth/perfil/correo.
-- Reemplaza, para coop, lo que hacía el trigger 200000 (que se retira en el cierre
-- del lote). Replica responsable-de-relación (vendedor) y no_contactar.
--
-- ORDEN DE LOCKS (Codex/auditor GO): advisory documental (dentro del resolver) +
-- inversionistas FOR UPDATE ANTES del lead FOR UPDATE; luego reserva (orden
-- lead->reserva conservado). identidad->lead->reserva, sin ciclo con la fusión.
--
-- DECISIONES (Miguel 03/09): UN SOLO LEAD TOTAL (invariante #6) → convertir un
-- 2.º lead de la misma persona se RECHAZA (P0409); se CONSERVA UNIQUE(lead_id)
-- (N inversiones = F5); métrica por inversionista/mes = F3.
--
-- BANDERA resolver_en_puertas APAGADA = comportamiento IDÉNTICO a hoy (v_inv NULL:
-- no toca inversionista_id de lead/cierre, no crea inversión/titular/responsable).
-- La carrera de reserva Avance↔coop y el anti-doble-depósito quedan VERBATIM.
-- Requiere F1, F2-backfill, el fix del resolver (20260903190000) y los helpers de
-- idempotencia (20260903205000).

-- REBASE sobre P-058 (20260903215149, en prod el 03/09 por otra sesión): la
-- autorización de las puertas de conversión es `private.puede_gestionar_contratos_crm()`
-- (fuente única). Este cuerpo parte de ESA versión viva; con el `if` viejo la
-- habríamos revertido. Texto del predicado idéntico al que P-058 dejó instalado.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_convertir_lead_externo'));

do $guard$
begin
  if to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 convertir_lead_externo: faltan F1/F2 (resolver o bandera)';
  end if;
end
$guard$;

create or replace function crm.convertir_lead_externo(
  p_lead_id uuid,
  p_cooperativa text,
  p_monto numeric,
  p_moneda text,
  p_documento_tipo text,
  p_documento text,
  p_nombre text,
  p_numero_transaccion text,
  p_referencia text default null,
  p_vence_en date default null,
  p_nota text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  if v_flag and v_inv is not null then
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
$$;

comment on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text) is
  'Cierra un lead como convertido en una cooperativa (Qorilazo/Prodelco): inserta la foto en crm.cierres_externos y mueve etapa bajo la valvula, SIN crear usuario de portal ni enviar correo. El episodio del ledger se cierra igual que en la conversion Avance, asi que la conversion mensual lo cuenta sin cambios de formula; la cuota lo suma via cumplimiento_metas_fn.';

revoke all on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text)
  from public, anon, service_role;
grant execute on function crm.convertir_lead_externo(uuid, text, numeric, text, text, text, text, text, text, date, text) to authenticated;

do $post$
begin
  if to_regprocedure('crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)') is null then
    raise exception 'POSTFLIGHT F2 convertir_lead_externo: la funcion no quedo creada';
  end if;
  raise notice 'F2 convertir_lead_externo OK: identidad adentro (tras bandera); cierre+inversion+titular; responsable/no_contactar replicados.';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903230000', 'crm_f2_cierre_lote_retira_trigger', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Cierre del lote: retirar el trigger 200000
-- ============================================================================
--
-- QUE: cierra el lote Contrato-F2. Las dos puertas (convertir_lead 210000 y
-- convertir_lead_externo 220000) YA reconocen la identidad ADENTRO, así que el
-- trigger-only trg_leads_reconocer_identidad (200000) sobra y se RETIRA (el
-- diseño lo ordena; el auditor lo marcó como bloqueante de lote).
--
-- BANDERA EN ESTADO EXPLÍCITO = APAGADA. F2 aterriza ADITIVA (sin cambio visible),
-- igual que F1 y el backfill: el reconocimiento en las puertas queda DORMIDO hasta
-- una ACTIVACIÓN deliberada —migración aparte— tras el ensayo en banco, el visto
-- de Miguel y (para «N inversiones por persona») la fase F5. Por eso aquí la
-- bandera se fuerza a false, neutralizando el encendido que hacía 200000, se
-- aplique o no ese archivo (los DROP y el UPDATE son idempotentes).
--
-- Requiere que las dos puertas F2 estén reescritas (210000, 220000). Reversa:
-- rollback-f2-puertas.sql (no recrea el trigger; las puertas ya lo sustituyen).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_cierre_lote'));

do $guard$
begin
  if to_regprocedure('crm.convertir_lead(uuid,uuid)') is null
     or to_regprocedure('crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text)') is null then
    raise exception 'F2 cierre: faltan las puertas reescritas (210000/220000)';
  end if;
  if not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 cierre: falta la bandera resolver_en_puertas (F1)';
  end if;
end
$guard$;

-- Retirar el trigger-only 200000 y su función (reemplazados por las puertas).
drop trigger if exists trg_leads_reconocer_identidad on crm.leads;
drop function if exists private.leads_reconocer_identidad_al_convertir();

-- Bandera APAGADA (aterrizaje aditivo). La activación es un paso deliberado aparte.
update crm.multiempresa_flags
   set activo = false, actualizado_en = now()
 where nombre = 'resolver_en_puertas' and activo = true;

do $post$
begin
  if exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where t.tgname = 'trg_leads_reconocer_identidad'
      and c.relname = 'leads' and c.relnamespace = 'crm'::regnamespace
      and not t.tgisinternal
  ) then
    raise exception 'POSTFLIGHT F2 cierre: el trigger trg_leads_reconocer_identidad no se retiró';
  end if;
  if to_regprocedure('private.leads_reconocer_identidad_al_convertir()') is not null then
    raise exception 'POSTFLIGHT F2 cierre: la función del trigger sigue viva';
  end if;
  if (select activo from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'POSTFLIGHT F2 cierre: la bandera quedó ENCENDIDA (F2 debe aterrizar apagada)';
  end if;
  raise notice 'F2 cierre OK: trigger retirado, puertas vigentes, bandera APAGADA (aditiva).';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903240000', 'crm_f2_no_contactar_por_persona', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — `no_contactar` por PERSONA (contrato §7.3)
-- ============================================================================
--
-- QUE: el veto «No contactar» se eleva al inversionista: bloquea a la PERSONA,
-- no solo un teléfono. Los leads vinculados lo HEREDAN. Levantarlo exige puerta
-- auditada de Gerencia con motivo. (Invariante #7 del contrato; meta #5 de F3.)
--
-- COMO (Codex #4 — evita el ciclo de locks con la fusión):
--   * Subida y bajada SOLO por RPC ORDENADA: identidad FOR UPDATE -> leads FOR
--     UPDATE (id asc). Nunca lead->identidad. Un trigger que propagara desde un
--     UPDATE directo iría lead->identidad y podría abrazarse con la fusión
--     (identidad->leads); por eso el trigger NO propaga: solo RECHAZA.
--   * Trigger de rechazo: un UPDATE directo de leads.no_contactar (authenticated
--     tiene GRANT por columna) se rechaza salvo bajo la válvula op_privilegiada,
--     que solo encienden las RPC. Monotonía garantizada: nadie baja el veto por
--     fuera de la puerta de Gerencia.
--   * Herencia al INSERT: un lead nuevo cuyo documento ya pertenece a una persona
--     vetada nace con no_contactar=true. Cierra el bypass de crm-importar-leads
--     (que inserta con service_role y no_contactar=false) en la capa de datos.
--   * Reparto, rescate y disponibilidad consultan el veto de la PERSONA con JOIN
--     directo a crm.inversionistas (migración 250000), sin helper por fila.
--
-- TODO detrás de la bandera resolver_en_puertas: APAGADA = los triggers no actúan
-- y las RPC actúan SOLO sobre el lead (como el UPDATE directo de hoy). Requiere F1.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_no_contactar_persona'));

do $guard$
begin
  if to_regclass('crm.inversionistas') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas') then
    raise exception 'F2 no_contactar: falta F1 (inversionistas o bandera)';
  end if;
end
$guard$;

-- (Sin helper por fila: las lecturas de 250000/260000 resuelven el veto de la
--  persona con JOIN directo a crm.inversionistas, set-based.)

-- ============================================================================
-- 2. RPC: MARCAR no contactar (cualquier rol CRM sobre un lead de su ámbito)
-- ============================================================================
create or replace function crm.marcar_no_contactar(
  p_lead_id uuid,
  p_motivo  text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (vendedor_id is null and asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;
  -- Revalidar tras esperar: si la identidad cambió (fusión/corrección), reintentar.
  if v_flag and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(no_contactar_en, pg_catalog.now()),
           no_contactar_por = coalesce(no_contactar_por, v_uid)
     where id = v_inv and no_contactar = false;
    -- Todos los leads de la persona heredan el veto (id asc = orden determinista).
    for v_lead in
      select * from crm.leads where inversionista_id = v_inv order by id for update
    loop
      if not v_lead.no_contactar then
        update crm.leads set no_contactar = true where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$$;
revoke all on function crm.marcar_no_contactar(uuid, text) from public, anon, service_role;
grant execute on function crm.marcar_no_contactar(uuid, text) to authenticated;

-- ============================================================================
-- 3. RPC: LEVANTAR no contactar (SOLO Gerencia, con motivo — puerta auditada)
-- ============================================================================
create or replace function crm.levantar_no_contactar(
  p_lead_id uuid,
  p_motivo  text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_uid is null or v_rol is distinct from 'gerencia' then
    raise exception 'Solo Gerencia puede levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_flag and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = false, no_contactar_en = null, no_contactar_por = null
     where id = v_inv and no_contactar = true;
    for v_lead in
      select * from crm.leads where inversionista_id = v_inv order by id for update
    loop
      if v_lead.no_contactar then
        update crm.leads set no_contactar = false where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
  else
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    get diagnostics v_n = row_count;
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota', 'Levantado No contactar por Gerencia',
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo)),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$$;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;

-- ============================================================================
-- 4. Trigger de RECHAZO: no_contactar solo cambia por la puerta (bajo válvula)
-- ============================================================================
create or replace function private.trg_leads_no_contactar_solo_puerta()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;  -- bandera apagada: comportamiento de hoy
  end if;
  if new.no_contactar is distinct from old.no_contactar
     and coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off') <> 'on' then
    raise exception 'No contactar se cambia solo por su puerta (marcar_no_contactar / levantar_no_contactar)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_no_contactar_solo_puerta() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_000_no_contactar_puerta on crm.leads;
create trigger trg_leads_000_no_contactar_puerta
  before update of no_contactar on crm.leads
  for each row execute function private.trg_leads_no_contactar_solo_puerta();

-- ============================================================================
-- 5. Trigger de HERENCIA al INSERT: un lead nuevo de una persona vetada nace vetado
-- ============================================================================
create or replace function private.trg_leads_hereda_veto_persona()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if new.no_contactar then
    return new;
  end if;
  -- Solo el documento exacto vincula (contrato #8). Lectura sin lock: no cambia
  -- el orden de locks (es un SELECT), no hay ciclo posible. Se NORMALIZA igual
  -- que el resolver (este trigger corre ANTES de que disponibilidad haga btrim).
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 digitos (lo exige el trigger de
  -- alta; contrato §18: CE/pasaporte se resuelven al convertir).
  if new.dni is not null then
    select i.no_contactar into v_veto
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni,''), '[^A-Za-z0-9]', '', 'g'))
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
    limit 1;
    if coalesce(v_veto, false) then
      new.no_contactar := true;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.trg_leads_hereda_veto_persona() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_000_hereda_veto on crm.leads;
create trigger trg_leads_000_hereda_veto
  before insert on crm.leads
  for each row execute function private.trg_leads_hereda_veto_persona();

-- ============================================================================
-- 6. Postflight
-- ============================================================================
do $post$
begin
  if to_regprocedure('crm.marcar_no_contactar(uuid,text)') is null
     or to_regprocedure('crm.levantar_no_contactar(uuid,text)') is null then
    raise exception 'POSTFLIGHT no_contactar: falta alguna función';
  end if;
  if not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where t.tgname='trg_leads_000_no_contactar_puerta' and c.relname='leads'
                   and c.relnamespace='crm'::regnamespace and not t.tgisinternal)
     or not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
                 where t.tgname='trg_leads_000_hereda_veto' and c.relname='leads'
                   and c.relnamespace='crm'::regnamespace and not t.tgisinternal) then
    raise exception 'POSTFLIGHT no_contactar: falta algún trigger';
  end if;
  if has_function_privilege('anon','crm.marcar_no_contactar(uuid,text)','EXECUTE')
     or has_function_privilege('anon','crm.levantar_no_contactar(uuid,text)','EXECUTE') then
    raise exception 'POSTFLIGHT no_contactar: grants abiertos de más';
  end if;
  raise notice 'F2 no_contactar OK: RPC ordenadas (identidad->leads), rechazo directo y herencia al insert (tras bandera).';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903250000', 'crm_f2_lecturas_veto_persona', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Las LECTURAS respetan el veto de la PERSONA
-- ============================================================================
--
-- QUE (contrato §7.3): no_contactar «bloquea toda oportunidad nueva y todo
-- seguimiento». Las tres rutas que hoy consultan SOLO leads.no_contactar pasan a
-- consultar también el veto de la identidad (crm.inversionistas.no_contactar):
--   * private.leads_por_repartir_implementacion  (la IMPLEMENTACIÓN del reparto;
--     el wrapper crm.leads_por_repartir de 20260807203740 NO se toca)
--   * crm.rescatar_descartes                      (rescate de descartes)
--   * private.verificar_disponibilidad_lead_impl  (disponibilidad / alta / toma)
-- El join sigue a la identidad CANÓNICA (si la del lead está fusionada). En
-- disponibilidad, además, el DOCUMENTO EXACTO (normalizado como el resolver) de
-- una persona vetada la bloquea aunque no exista lead con ese teléfono.
--
-- COMO: generado transformando el texto VIVO de cada función (reparto: cuerpo de
-- 20260723120000 renombrado a _implementacion en 20260807203740); lo demás
-- VERBATIM. CREATE OR REPLACE con firma idéntica conserva las ACL.
--
-- TODO tras la bandera resolver_en_puertas (v_flag): APAGADA = comportamiento
-- IDÉNTICO a hoy. Requiere F1 y 20260903240000.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_lecturas_veto_persona'));

do $guard$
begin
  if to_regclass('crm.inversionistas') is null
     or to_regprocedure('private.leads_por_repartir_implementacion()') is null
     or to_regprocedure('crm.leads_por_repartir()') is null
     or to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)') is null
     or to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)') is null then
    raise exception 'F2 lecturas: falta F1 o alguna de las funciones (incl. la implementación del reparto)';
  end if;
end
$guard$;

-- ── 1) Reparto (IMPLEMENTACIÓN; el wrapper crm.leads_por_repartir queda intacto) ─
create or replace function private.leads_por_repartir_implementacion()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text,
  creado_en timestamptz, clasificacion_auto text, comentario text
)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
        v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en,
         l.clasificacion_auto,
         -- Comentario REDACTADO (correo/celular/documento fuera) y acotado a
         -- 400 caracteres: Rosa necesita leer la pregunta, no los datos de
         -- contacto. Mantiene la premisa "sin PII de contacto" de C1.
         nullif(left(private.redactar_pii(l.nota), 400), '')
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                     -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                               -- Ley 29571: nunca listar 'No Insista'
    and (not v_flag or coalesce(inv.no_contactar, false) = false) -- el veto es de la PERSONA (contrato §7.3)
  order by l.creado_en asc;                                  -- FIFO justo
end;
$$;

-- ── 2) Rescate ──────────────────────────────────────────────────────────────
create or replace function crm.rescatar_descartes(
  p_episodios uuid[],
  p_analistas_destino uuid[],
  p_evitar_asesor_origen boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_destinos_validos uuid[];
  v_total_episodios integer;
  v_total_destinos integer;
  v_candidatos integer := 0;
  v_orden integer := 0;
  v_intento integer;
  v_destino uuid;
  v_fila record;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
begin
  if p_episodios is null
     or pg_catalog.array_length(p_episodios, 1) is null
     or pg_catalog.array_length(p_episodios, 1) = 0
     or pg_catalog.array_length(p_episodios, 1) > 100
     or pg_catalog.array_position(p_episodios, null) is not null then
    raise exception 'Selecciona entre 1 y 100 descartes válidos'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_episodios) as u(id)
  ) episodios_unicos) <> pg_catalog.array_length(p_episodios, 1) then
    raise exception 'Un descarte no se puede enviar dos veces en el mismo reparto'
      using errcode = '22023';
  end if;

  if p_analistas_destino is null
     or pg_catalog.array_length(p_analistas_destino, 1) is null
     or pg_catalog.array_length(p_analistas_destino, 1) = 0
     or pg_catalog.array_length(p_analistas_destino, 1) > 30
     or pg_catalog.array_position(p_analistas_destino, null) is not null then
    raise exception 'Selecciona al menos un asesor destino'
      using errcode = '22023';
  end if;

  if (select pg_catalog.count(*) from (
    select distinct id from pg_catalog.unnest(p_analistas_destino) as u(id)
  ) destinos_unicos) <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'No repitas un asesor destino'
      using errcode = '22023';
  end if;

  select e.rol_crm
    into v_rol
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = v_actor
    and e.activo = true
    and p.activo = true
    and e.rol_crm in ('supervisor', 'gerencia');

  if v_actor is null or v_rol is null then
    raise exception 'Solo supervisión puede rescatar descartes'
      using errcode = '42501';
  end if;

  select pg_catalog.array_agg(destino.id order by destino.orden)
    into v_destinos_validos
  from (
    select u.id, u.orden
    from pg_catalog.unnest(p_analistas_destino) with ordinality as u(id, orden)
    join crm.equipo e on e.perfil_id = u.id
    join public.perfiles p on p.id = e.perfil_id
    where e.activo = true
      and p.activo = true
      and e.rol_crm = 'vendedor'
      and (
        v_rol = 'gerencia'
        or e.perfil_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
  ) destino;

  v_total_destinos := pg_catalog.coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);
  if v_total_destinos <> pg_catalog.array_length(p_analistas_destino, 1) then
    raise exception 'Uno de los asesores destino no está activo o no pertenece a tu equipo'
      using errcode = '22023';
  end if;

  -- Se bloquean los leads antes de modificar alguno. Si una carrera ya los
  -- reabrió, toda la operación falla y no deja un reparto parcial.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id,
      (l.no_contactar or (v_flag and coalesce(inv.no_contactar, false))) as no_contactar  -- veto de la PERSONA
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and la.resultado_en is not null
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
      and la.motivo_descarte_cierre <> 'datos_invalidos'
      and (
        v_rol = 'gerencia'
        or la.analista_id in (
          select private.vendedor_ids_visibles(v_actor)
        )
      )
    order by la.resultado_en, la.id
    for update of l
  loop
    v_candidatos := v_candidatos + 1;
    if v_fila.no_contactar then
      raise exception 'Uno de los leads tiene la restricción «No insistir» y no puede reactivarse'
        using errcode = 'P0429';
    end if;
  end loop;

  v_total_episodios := pg_catalog.array_length(p_episodios, 1);
  if v_candidatos <> v_total_episodios then
    raise exception 'Uno de los descartes ya no está disponible para rescate'
      using errcode = 'P0002';
  end if;

  -- Una segunda pasada usa los mismos locks. La vuelta redonda conserva el
  -- orden seleccionado y, si se pidió, salta al asesor que lo descartó.
  for v_fila in
    select
      la.id as episodio_id,
      la.lead_id,
      la.analista_id as asesor_origen_id
    from crm.lead_asignaciones la
    join crm.leads l on l.id = la.lead_id
    where la.id = any(p_episodios)
      and la.resultado = 'descartado'
      and l.activo = true
      and l.etapa = 'descartado'
      and l.descartado_en is not distinct from la.resultado_en
    order by la.resultado_en, la.id
  loop
    v_destino := null;
    for v_intento in 0..(v_total_destinos - 1) loop
      v_destino := v_destinos_validos[((v_orden + v_intento) % v_total_destinos) + 1];
      exit when not p_evitar_asesor_origen or v_destino is distinct from v_fila.asesor_origen_id;
    end loop;

    if v_destino is null
       or (p_evitar_asesor_origen and v_destino = v_fila.asesor_origen_id) then
      raise exception 'No hay otro asesor destino para uno de los descartes seleccionados'
        using errcode = '22023';
    end if;

    update crm.leads
       set etapa = 'nuevo',
           motivo_descarte = null,
           vendedor_id = v_destino,
           asignado_supervisor_id = null
     where id = v_fila.lead_id;

    v_orden := v_orden + 1;
  end loop;

  return pg_catalog.jsonb_build_object(
    'rescatados', v_candidatos,
    'asesores_destino', v_total_destinos
  );
end;
$$;

-- ── 3) Disponibilidad ───────────────────────────────────────────────────────
create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text,
  p_excluir_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  -- documento normalizado IGUAL que el resolver (documento_normalizado es mayúsculas+alfanumérico)
  v_dni_norm text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_dni,''), '[^A-Za-z0-9]', '', 'g')), '');
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where l.id is distinct from p_excluir_lead_id
      and (l.no_contactar = true or (v_flag and coalesce(inv.no_contactar, false)))
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  )
  -- El veto es de la PERSONA (contrato §7.3): también si el documento EXACTO
  -- pertenece a una identidad vetada, aunque no tenga lead con ese teléfono.
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (el trigger de alta lo
  -- exige; contrato §18: CE/pasaporte se resuelven al convertir).
  or (v_flag and v_dni_norm is not null and exists (
    select 1
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
      and i.no_contactar = true
  )) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  select
    l.id,
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde,
      -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
      -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
      -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
      -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
      -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
      'ultima_conversacion_en', (
        select pg_catalog.max(a.creado_en)
        from crm.actividades a
        where a.lead_id = v_lead.id
          and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
      )
    );
  end if;

  select
    l.id,
    l.activo,
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;

    -- ── F2: el descarte VENCIDO se parte (spec §5.6) ─────────────────────────
    -- Un enfriamiento vencido ya NO cae al 'libre' genérico: el contacto es
    -- REUTILIZABLE y su puerta es crm.tomar_lead_libre (el alta lo bloquea
    -- desde F1 — crear duplicaría). Dos excepciones deliberadas del plan:
    --   · activo=false jamás es reutilizable: un soft-borrado no se revive
    --     por esta puerta — cae a 'libre' y el alta crea de cero.
    --   · motivos con 0 días (pide_credito, datos_invalidos): CARENCIA de
    --     24 h SOLO para tomar (Miguel 2026-08-16 — protege el «Deshacer
    --     descarte 24h» del coordinador). Durante la ventana el veredicto
    --     sigue 'libre': el alta manual conserva su comportamiento de hoy.
    if v_lead.activo = true then
      if v_dias = 0
         and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
        return pg_catalog.jsonb_build_object('estado', 'libre');
      end if;
      v_quedo_libre_en := case
        when v_dias > 0 then v_disponible_desde
        else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
      end;
      return pg_catalog.jsonb_build_object(
        'estado', 'reutilizable',
        'motivo_descarte', v_lead.motivo_descarte,
        'descartado_en', v_lead.descartado_en,
        'quedo_libre_en', v_quedo_libre_en,
        'descartado_por', v_lead.descartado_por_nombre,
        'ultima_conversacion_en', (
          select pg_catalog.max(a.creado_en)
          from crm.actividades a
          where a.lead_id = v_lead.id
            and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
        )
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

do $post$
begin
  if to_regprocedure('private.leads_por_repartir_implementacion()') is null
     or to_regprocedure('crm.rescatar_descartes(uuid[],uuid[],boolean)') is null
     or to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)') is null then
    raise exception 'POSTFLIGHT F2 lecturas: alguna función no quedó';
  end if;
  -- el wrapper del reparto sigue devolviendo sus 10 columnas
  if (select count(*) from information_schema.parameters where specific_schema='crm'
        and specific_name like 'leads_por_repartir%' and parameter_mode='OUT') <> 10 then
    raise exception 'POSTFLIGHT F2 lecturas: el wrapper crm.leads_por_repartir cambió de forma';
  end if;
  raise notice 'F2 lecturas OK: reparto (impl), rescate y disponibilidad respetan el veto de la persona canónica (tras bandera).';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260903260000', 'crm_f2_disponibilidad_un_lead_total', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 — Disponibilidad: UN SOLO LEAD TOTAL por persona
-- ============================================================================
--
-- QUE (contrato invariante #6 / meta #3): al verificar disponibilidad por documento,
-- si ese DNI exacto (normalizado como el resolver) ya pertenece a una identidad
-- que TIENE lead —Avance o cooperativa, aunque no tenga perfil de portal— la
-- persona ya es cliente / ya tiene su lead y NO se crea otro. Hoy una persona
-- convertida en cooperativa (sin perfil) caía a 'libre'. Cubre el ALTA HUMANA y
-- las RPC de disponibilidad/toma (verificar_disponibilidad_lead, tomar_lead_libre,
-- crear_lead_si_disponible). NO cubre al importador sin sesión (sale del trigger
-- antes de verificar; su veto lo hereda trg_leads_000_hereda_veto de 240000).
--
-- Base: la versión de 20260903250000 + este bloque; lo demás VERBATIM. CREATE OR
-- REPLACE con firma idéntica conserva las ACL. Gateado por resolver_en_puertas:
-- APAGADA = idéntico a hoy. Requiere F1 y 250000.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2_disponibilidad_un_lead'));

do $guard$
begin
  if to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)') is null
     or to_regclass('crm.inversionista_identificadores') is null then
    raise exception 'F2 disponibilidad: falta F1 o la función';
  end if;
end
$guard$;

create or replace function private.verificar_disponibilidad_lead_impl(
  p_telefono text,
  p_dni text,
  p_excluir_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tel text := private.normalizar_telefono(p_telefono);
  v_lead record;
  v_perfil record;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  -- documento normalizado IGUAL que el resolver (documento_normalizado es mayúsculas+alfanumérico)
  v_dni_norm text := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_dni,''), '[^A-Za-z0-9]', '', 'g')), '');
  v_asesor_identidad text;
begin
  if v_tel is null or pg_catalog.length(v_tel) = 0 then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  if exists (
    select 1
    from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
    left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)  -- sigue a la canónica si está fusionada
    where l.id is distinct from p_excluir_lead_id
      and (l.no_contactar = true or (v_flag and coalesce(inv.no_contactar, false)))
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  )
  -- El veto es de la PERSONA (contrato §7.3): también si el documento EXACTO
  -- pertenece a una identidad vetada, aunque no tenga lead con ese teléfono.
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (el trigger de alta lo
  -- exige; contrato §18: CE/pasaporte se resuelven al convertir).
  or (v_flag and v_dni_norm is not null and exists (
    select 1
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
      and i.no_contactar = true
  )) then
    return pg_catalog.jsonb_build_object('estado', 'no_contactar');
  end if;

  select per.id, asesor.nombre_completo as asesor_nombre
  into v_perfil
  from public.perfiles per
  left join public.perfiles asesor on asesor.id = per.asesor_perfil_id
  where per.rol = 'cliente'
    and per.activo = true
    and (
      private.normalizar_telefono(per.telefono) = v_tel
      or (p_dni is not null and per.dni = p_dni)
    )
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'estado', 'ya_es_cliente',
      'asesor', coalesce(v_perfil.asesor_nombre, 'sin asesor asignado')
    );
  end if;

  -- Un solo lead TOTAL por persona (contrato #6, meta #3): si el DOCUMENTO exacto
  -- ya pertenece a una identidad que TIENE lead (Avance o cooperativa — aunque no
  -- tenga perfil de portal), esa persona ya es cliente / ya tiene su lead: no se
  -- crea otro. Solo el documento vincula (contrato #8). Gateado por bandera.
  if v_flag and v_dni_norm is not null then
    select coalesce(resp.nombre_completo, 'sin asesor asignado')
      into v_asesor_identidad
    from crm.inversionista_identificadores idf
    join crm.inversionistas i on i.id = idf.inversionista_id
    -- Sin filtro li.activo: DELIBERADO. leads_inversionista_uidx es único por
    -- inversionista_id SIN filtro de activo, así que un lead soft-borrado que
    -- conserve el puntero seguiría bloqueando la conversión del nuevo; mejor
    -- bloquear aquí, en el alta, con mensaje claro, que reventar al convertir.
    join crm.leads li on li.inversionista_id = i.id
    left join public.perfiles resp on resp.id = i.responsable_relacion_id
    where idf.tipo_documento = 'DNI'
      and idf.documento_normalizado = v_dni_norm
      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
      and li.id is distinct from p_excluir_lead_id
    limit 1;
    if found then
      return pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'asesor', v_asesor_identidad, 'via', 'identidad');
    end if;
  end if;

  select
    l.id,
    l.tenencia_desde,
    l.vendedor_id,
    l.asignado_supervisor_id,
    coalesce(pv.nombre_completo, ps.nombre_completo) as tenedor
  into v_lead
  from crm.leads l
  left join public.perfiles pv on pv.id = l.vendedor_id
  left join public.perfiles ps on ps.id = l.asignado_supervisor_id
  where l.id is distinct from p_excluir_lead_id
    and l.activo = true
    and l.etapa not in ('convertido', 'descartado')
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  limit 1;

  if found then
    if v_lead.vendedor_id is null and v_lead.asignado_supervisor_id is null then
      return pg_catalog.jsonb_build_object('estado', 'en_bolsa');
    end if;
    return pg_catalog.jsonb_build_object(
      'estado', 'tomado',
      'vendedor', v_lead.tenedor,
      'tenencia_desde', v_lead.tenencia_desde,
      -- La última CONVERSACIÓN real: «¿el cliente RESPONDIÓ?» — espejo de
      -- TIPOS_CONVERSACION (tipos.ts) y del WHEN de
      -- trg_zz_actividades_avance_etapa. Los intentos (llamada_no_contestada,
      -- whatsapp_enviado) NO cuentan: decisión dura de Miguel, 2026-08-16.
      -- NULL si jamás hubo conversación — la tarjeta no pinta la línea.
      'ultima_conversacion_en', (
        select pg_catalog.max(a.creado_en)
        from crm.actividades a
        where a.lead_id = v_lead.id
          and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
      )
    );
  end if;

  select
    l.id,
    l.activo,
    l.motivo_descarte,
    l.descartado_en,
    pd.nombre_completo as descartado_por_nombre
  into v_lead
  from crm.leads l
  left join public.perfiles pd on pd.id = l.descartado_por
  where l.id is distinct from p_excluir_lead_id
    and l.etapa = 'descartado'
    and l.descartado_en is not null
    and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  order by l.descartado_en desc
  limit 1;

  if found then
    select ep.dias
    into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;

    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);

    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return pg_catalog.jsonb_build_object(
        'estado', 'enfriamiento',
        'motivo_descarte', v_lead.motivo_descarte,
        'disponible_desde', v_disponible_desde,
        'descartado_por', v_lead.descartado_por_nombre
      );
    end if;

    -- ── F2: el descarte VENCIDO se parte (spec §5.6) ─────────────────────────
    -- Un enfriamiento vencido ya NO cae al 'libre' genérico: el contacto es
    -- REUTILIZABLE y su puerta es crm.tomar_lead_libre (el alta lo bloquea
    -- desde F1 — crear duplicaría). Dos excepciones deliberadas del plan:
    --   · activo=false jamás es reutilizable: un soft-borrado no se revive
    --     por esta puerta — cae a 'libre' y el alta crea de cero.
    --   · motivos con 0 días (pide_credito, datos_invalidos): CARENCIA de
    --     24 h SOLO para tomar (Miguel 2026-08-16 — protege el «Deshacer
    --     descarte 24h» del coordinador). Durante la ventana el veredicto
    --     sigue 'libre': el alta manual conserva su comportamiento de hoy.
    if v_lead.activo = true then
      if v_dias = 0
         and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
        return pg_catalog.jsonb_build_object('estado', 'libre');
      end if;
      v_quedo_libre_en := case
        when v_dias > 0 then v_disponible_desde
        else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
      end;
      return pg_catalog.jsonb_build_object(
        'estado', 'reutilizable',
        'motivo_descarte', v_lead.motivo_descarte,
        'descartado_en', v_lead.descartado_en,
        'quedo_libre_en', v_quedo_libre_en,
        'descartado_por', v_lead.descartado_por_nombre,
        'ultima_conversacion_en', (
          select pg_catalog.max(a.creado_en)
          from crm.actividades a
          where a.lead_id = v_lead.id
            and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
        )
      );
    end if;
  end if;

  return pg_catalog.jsonb_build_object('estado', 'libre');
end;
$$;

-- ACL: CREATE OR REPLACE con firma idéntica las conserva; se reafirma por si un
-- futuro drop+create las perdiera (patrón de la versión viva).
revoke all on function private.verificar_disponibilidad_lead_impl(text, text, uuid)
  from public, anon, authenticated, service_role;

do $post$
begin
  if to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)') is null then
    raise exception 'POSTFLIGHT F2 disponibilidad: la función no quedó';
  end if;
  raise notice 'F2 disponibilidad OK: un solo lead total por persona (tras bandera).';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

commit;

select version, name from supabase_migrations.schema_migrations where version in ('20260903190000','20260903205000','20260903210000','20260903220000','20260903230000','20260903240000','20260903250000','20260903260000') order by version;
