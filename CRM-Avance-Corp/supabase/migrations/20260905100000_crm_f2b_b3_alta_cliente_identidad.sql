-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b3 — EL CLIENTE CREADO SIN LEAD ES UNA
-- PERSONA (§8.2 «vinculación del perfil»), con una SAGA reanudable entre Postgres y Auth
-- ============================================================================
--
-- QUE: `crear-cliente` e `importar-clientes` crean Auth + perfil sin identidad. Con la
-- bandera resolver_en_puertas ENCENDIDA, todo perfil `cliente` nuevo nace enlazado a su
-- identidad (`private.inversionista_resolver`, documento verificado) y con su responsable
-- de relación; `crear_contrato` podrá exigirlo (migración aparte, `public`, con OK de
-- Miguel) y `eliminar-cliente` pregunta antes de borrar nada.
--
-- COMO:
--   * SAGA ÚNICA (también la usa b4): el claim vive en crm.multiempresa_idempotencia con
--     clave 'auth_persona:<inversionista_id>' (NUNCA el documento), `version` como CAS,
--     token aleatorio hasheado (solo el edge lo ve), owner, lease de 10 min y estados
--     reclamado -> auth_creado -> perfil_creado -> enlazado. Reanudable en cada ventana
--     de caída; el edge marca el Auth con app_metadata.claim_id y solo lo reutiliza si
--     coincide.
--   * private.puede_alta_cliente(): reproduce EXACTAMENTE crear-cliente/autorizacion.mjs
--     (unión Portal admin/superadmin/analista/operaciones + miembro CRM con
--     puede_contratar; revocación CRM prevalece). No se reutiliza la frontera de contratos.
--   * crm.alta_cliente_identidad_fn(paso, payload): reclamar / registrar_auth / perfil_creado /
--     compensar_auth / enlazar. registrar_auth verifica EN SERVIDOR que el Auth exista y lleve
--     app_metadata.claim_id de este claim. Con bandera OFF: P0409 (superficie inerte).
--   * private.asegurar_identidad_perfil(perfil, fuente): documento -> identidad FOR UPDATE
--     -> perfil FOR SHARE (revalida) -> enlace -> responsable de relación (asesor activo,
--     bajo el interlock de jerarquía; si no, revision_responsable).
--   * crm.cliente_eliminable_fn (service_role): preflight de eliminar-cliente.
--   * crm.actualizar_cliente_gerencia: con bandera ON no cambia el documento de un perfil
--     enlazado (transformación anclada desde el texto vivo; guarda md5).
-- Orden total de locks: documento -> identidad -> perfil -> claim (fila de idempotencia).
-- Reversa: scripts/rollback-f2b-b3.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b3_alta_cliente_identidad'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regprocedure('private.idem_hash(jsonb)') is null
     or to_regclass('crm.multiempresa_idempotencia') is null then
    raise exception 'F2.b b3: falta E1 (b1/b2) o F1';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b b3: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='actualizar_cliente_gerencia';
  if v_h <> 'dc02fd3a57d55e033e2e05cff71996ff' and (select strpos(prosrc,'F2.b (b3)') from pg_proc where proname='actualizar_cliente_gerencia') = 0 then
    raise exception 'F2.b b3: crm.actualizar_cliente_gerencia no es el texto vivo esperado (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 1. La SAGA de Auth (privada)
-- ============================================================================
create or replace function private.saga_token_hash(p_token text)
returns text
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(p_token,''), 'utf8')), 'hex')
$$;
revoke all on function private.saga_token_hash(text) from public, anon, authenticated, service_role;

-- Reclamar (o reanudar) el claim de una IDENTIDAD ya bloqueada por el llamador.
create or replace function private.saga_auth_reclamar(p_inv uuid, p_tipo text, p_payload jsonb, p_lead_id uuid default null, p_token text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_clave text := 'auth_persona:' || p_inv::text;
  v_hash  text := private.idem_hash(coalesce(p_payload, '{}'::jsonb));
  v_token text := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
  v_row   crm.multiempresa_idempotencia%rowtype;
  v_est   jsonb;
  v_claim uuid;
begin
  if p_inv is null or p_tipo not in ('alta_cliente','conversion') then
    raise exception 'Saga: identidad o tipo inválidos' using errcode = '22023';
  end if;
  select * into v_row from crm.multiempresa_idempotencia where clave = v_clave for update;
  if not found then
    v_claim := gen_random_uuid();
    v_est := pg_catalog.jsonb_build_object(
      'claim_id', v_claim, 'token_hash', private.saga_token_hash(v_token), 'tipo', p_tipo,
      'owner', v_uid, 'estado', 'reclamado', 'auth_user_id', null, 'perfil_id', null,
      'lead_id', p_lead_id, 'lease_hasta', pg_catalog.now() + interval '10 minutes',
      'creado_en', pg_catalog.now(), 'actualizado_en', pg_catalog.now());
    insert into crm.multiempresa_idempotencia (clave, tipo, hash_payload, resultado, creado_por)
    values (v_clave, p_tipo, v_hash, v_est, v_uid);
    return pg_catalog.jsonb_build_object('claim_id', v_claim, 'token', v_token, 'estado', 'reclamado',
      'version', 1, 'reanudar', false, 'inversionista_id', p_inv, 'auth_user_id', null, 'perfil_id', null);
  end if;
  v_est := v_row.resultado;
  if v_est->>'estado' = 'enlazado' then
    return pg_catalog.jsonb_build_object('claim_id', (v_est->>'claim_id')::uuid, 'token', null, 'estado', 'enlazado',
      'version', v_row.version, 'reanudar', true, 'inversionista_id', p_inv,
      'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid);
  end if;
  -- Reanudar SOLO con el token vigente (misma ejecución) o con el lease vencido. Compartir
  -- actor no basta: una segunda petición del mismo usuario no puede expulsar a la primera
  -- (Codex E2 #1). service_role (owner null) tampoco identifica un proceso.
  if (v_est->>'lease_hasta')::timestamptz > pg_catalog.now()
     and (p_token is null or v_est->>'token_hash' is distinct from private.saga_token_hash(p_token)) then
    raise exception 'Esta persona tiene un alta en curso; espera unos minutos'
      using errcode = 'P0409';
  end if;
  -- El payload canónico manda hasta completar la operación (Codex E2 #10).
  if v_row.hash_payload <> v_hash then
    raise exception 'La misma persona llegó con datos distintos; no se puede reintentar así'
      using errcode = 'P0409';
  end if;
  v_est := v_est || pg_catalog.jsonb_build_object('token_hash', private.saga_token_hash(v_token), 'owner', v_uid,
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now());
  update crm.multiempresa_idempotencia
     set resultado = v_est, version = version + 1
   where clave = v_clave;
  return pg_catalog.jsonb_build_object('claim_id', (v_est->>'claim_id')::uuid, 'token', v_token, 'estado', v_est->>'estado',
    'version', v_row.version + 1, 'reanudar', true, 'inversionista_id', p_inv,
    'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid);
end;
$$;
revoke all on function private.saga_auth_reclamar(uuid, text, jsonb, uuid, text) from public, anon, authenticated, service_role;

-- Localizar el claim por id (sin lock): devuelve clave e identidad.
create or replace function private.saga_auth_localizar(p_claim_id uuid)
returns table (clave text, inversionista_id uuid, estado jsonb, version integer)
language sql
stable
security definer
set search_path = ''
as $$
  select i.clave, pg_catalog.substr(i.clave, 14)::uuid, i.resultado, i.version
  from crm.multiempresa_idempotencia i
  where i.clave like 'auth\_persona:%'
    and i.resultado->>'claim_id' = p_claim_id::text
  limit 1
$$;
revoke all on function private.saga_auth_localizar(uuid) from public, anon, authenticated, service_role;

-- Avanzar el claim: token + CAS por version + transición válida.
create or replace function private.saga_auth_avanzar(p_claim_id uuid, p_token text, p_estado text,
                                                     p_auth_user_id uuid, p_perfil_id uuid, p_version integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loc record;
  v_row crm.multiempresa_idempotencia%rowtype;
  v_est jsonb;
  v_prev text;
begin
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found then
    raise exception 'Saga: claim inexistente' using errcode = 'P0002';
  end if;
  select * into v_row from crm.multiempresa_idempotencia where clave = v_loc.clave for update;
  v_est := v_row.resultado;
  if v_est->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'Saga: token inválido' using errcode = '42501';
  end if;
  if p_version is null then
    raise exception 'Saga: falta la versión del claim (CAS)' using errcode = '22023';
  end if;
  if v_row.version is distinct from p_version then
    raise exception 'Saga: el claim cambió (versión % ≠ %); vuelve a reclamar', v_row.version, p_version
      using errcode = '40001';
  end if;
  v_prev := v_est->>'estado';
  if not ((v_prev = 'reclamado' and p_estado = 'auth_creado' and p_auth_user_id is not null)
       or (v_prev = 'auth_creado' and p_estado = 'perfil_creado' and p_perfil_id is not null and p_perfil_id = (v_est->>'auth_user_id')::uuid)
       or (v_prev in ('auth_creado','perfil_creado') and p_estado = 'enlazado')
       or (v_prev = 'auth_creado' and p_estado = 'reclamado')   -- compensación: el Auth se borró tras fallar el perfil
       or (v_prev = p_estado)) then
    raise exception 'Saga: transición inválida % -> %', v_prev, p_estado using errcode = 'P0409';
  end if;
  -- Procedencia verificada EN SERVIDOR (Codex E2 #2): el Auth declarado debe existir y llevar la
  -- marca de ESTE claim en app_metadata; el perfil debe existir con id = auth_user_id.
  if p_estado = 'auth_creado' and v_prev = 'reclamado' then
    if not exists (select 1 from auth.users u where u.id = p_auth_user_id
                    and u.raw_app_meta_data->>'claim_id' = p_claim_id::text) then
      raise exception 'Saga: el usuario de Auth no existe o no lleva la marca de este claim' using errcode = 'P0409';
    end if;
  end if;
  if p_estado = 'perfil_creado' then
    if not exists (select 1 from public.perfiles p where p.id = p_perfil_id and p.rol = 'cliente') then
      raise exception 'Saga: el perfil declarado no existe' using errcode = 'P0409';
    end if;
  end if;
  if p_estado = 'reclamado' then
    if exists (select 1 from auth.users u where u.id = (v_est->>'auth_user_id')::uuid) then
      raise exception 'Saga: no se puede compensar: el usuario de Auth sigue existiendo' using errcode = 'P0409';
    end if;
    v_est := v_est - 'auth_user_id' || pg_catalog.jsonb_build_object('auth_user_id', null);
    p_auth_user_id := null;
  end if;
  v_est := v_est || pg_catalog.jsonb_build_object('estado', p_estado,
    'auth_user_id', case when p_estado = 'reclamado' then null else coalesce(p_auth_user_id, (v_est->>'auth_user_id')::uuid) end,
    'perfil_id', coalesce(p_perfil_id, (v_est->>'perfil_id')::uuid),
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now());
  update crm.multiempresa_idempotencia set resultado = v_est, version = version + 1 where clave = v_loc.clave;
  return pg_catalog.jsonb_build_object('claim_id', p_claim_id, 'estado', p_estado, 'version', v_row.version + 1,
    'inversionista_id', v_loc.inversionista_id, 'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid);
end;
$$;
revoke all on function private.saga_auth_avanzar(uuid, text, text, uuid, uuid, integer) from public, anon, authenticated, service_role;

-- ============================================================================
-- 2. Capacidad de ALTA DE CLIENTE = crear-cliente/autorizacion.mjs, al pie de la letra
-- ============================================================================
create or replace function private.puede_alta_cliente()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text; v_activo boolean; v_acc jsonb;
begin
  if v_uid is null then return pg_catalog.jsonb_build_object('ok', false); end if;
  select p.rol, p.activo into v_rol, v_activo from public.perfiles p where p.id = v_uid;
  if v_activo is distinct from true or v_rol is null then return pg_catalog.jsonb_build_object('ok', false); end if;
  v_acc := crm.mi_acceso_fn();
  if v_acc is null or pg_catalog.jsonb_typeof(v_acc) <> 'object'
     or (v_acc->>'perfil_id') is distinct from v_uid::text
     or (v_acc->>'estado') not in ('miembro','global','administrador_roles','revocado','no_enrolado')
     or pg_catalog.jsonb_typeof(v_acc->'puede_contratar') is distinct from 'boolean'
     or (v_acc->>'estado') = 'revocado' then
    return pg_catalog.jsonb_build_object('ok', false);
  end if;
  if v_rol in ('admin','superadmin','analista','operaciones') then
    return pg_catalog.jsonb_build_object('ok', true, 'via', 'portal',
      'asesor_id', case when v_rol = 'analista' then v_uid else null end);
  end if;
  if (v_acc->>'estado') = 'miembro' and (v_acc->'puede_contratar')::boolean
     and nullif(pg_catalog.btrim(coalesce(v_acc->>'rol_crm','')), '') is not null then
    return pg_catalog.jsonb_build_object('ok', true, 'via', 'crm',
      'asesor_id', case when v_acc->>'rol_crm' = 'vendedor' then v_uid else null end);
  end if;
  return pg_catalog.jsonb_build_object('ok', false);
end;
$$;
revoke all on function private.puede_alta_cliente() from public, anon, authenticated, service_role;

-- ============================================================================
-- 3. Asegurar la identidad de un perfil cliente (enlace + responsable de relación)
-- ============================================================================
create or replace function private.asegurar_identidad_perfil(p_perfil_id uuid, p_fuente text default 'alta_cliente')
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_p record; v_inv uuid; v_otro uuid; v_enlazado boolean := false;
  v_tramo boolean := false; v_revision boolean := false; v_asesor uuid; v_tipo text; v_doc text;
begin
  select p.tipo_documento, p.dni, p.rol, p.activo, p.asesor_perfil_id
    into v_p from public.perfiles p where p.id = p_perfil_id;
  if not found or v_p.rol <> 'cliente' then
    raise exception 'El perfil no es un cliente' using errcode = 'P0409';
  end if;
  v_tipo := coalesce(nullif(pg_catalog.btrim(v_p.tipo_documento), ''), 'DNI');
  v_doc  := nullif(pg_catalog.btrim(coalesce(v_p.dni, '')), '');
  if v_doc is null then
    raise exception 'El cliente no tiene documento: no se puede reconocer a la persona (identidad unificada)'
      using errcode = 'P0409';
  end if;
  -- documento -> identidad -> perfil (orden total)
  perform private.identidad_bloquear_documento(v_tipo, v_doc);
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, p_fuente);
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  perform 1 from public.perfiles p where p.id = p_perfil_id
     and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
     and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') = v_doc
   for share;
  if not found then
    raise exception 'El documento del cliente cambió mientras se enlazaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  select i.perfil_id into v_otro from crm.inversionistas i where i.id = v_inv;
  if v_otro is null then
    if exists (select 1 from crm.inversionistas i where i.perfil_id = p_perfil_id and i.estado <> 'fusionado' and i.id <> v_inv) then
      raise exception 'Este perfil ya pertenece a otra persona reconocida (fusión o corrección de Gerencia)' using errcode = 'P0409';
    end if;
    update crm.inversionistas set perfil_id = p_perfil_id where id = v_inv;
    v_enlazado := true;
  elsif v_otro <> p_perfil_id then
    raise exception 'La persona de este documento ya tiene otro perfil de cliente (revisión de Gerencia)' using errcode = 'P0409';
  end if;
  -- Responsable de relación (contrato §6): solo si no hay tramo abierto y el asesor está activo.
  if not exists (select 1 from crm.inversionista_responsables r where r.inversionista_id = v_inv and r.hasta is null) then
    v_asesor := v_p.asesor_perfil_id;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
    if v_asesor is not null
       and exists (select 1 from crm.equipo e join public.perfiles pp on pp.id = e.perfil_id
                   where e.perfil_id = v_asesor and e.activo and pp.activo) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo, por)
      values (v_inv, v_asesor, p_fuente, (select auth.uid()));
      update crm.inversionistas set responsable_relacion_id = v_asesor where id = v_inv and responsable_relacion_id is null;
      v_tramo := true;
    else
      v_revision := true;
    end if;
  end if;
  return pg_catalog.jsonb_build_object('inversionista_id', v_inv, 'enlazado_ahora', v_enlazado,
    'tramo_abierto', v_tramo, 'revision_responsable', v_revision);
end;
$$;
revoke all on function private.asegurar_identidad_perfil(uuid, text) from public, anon, authenticated, service_role;

-- ============================================================================
-- 4. La puerta del alta directa: crm.alta_cliente_identidad_fn(paso, payload)
-- ============================================================================
create or replace function crm.alta_cliente_identidad_fn(p_paso text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cap jsonb; v_tipo text; v_doc text; v_inv uuid; v_perfil uuid; v_activo boolean;
  v_claim uuid; v_loc record; v_r jsonb; v_hash_payload jsonb;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el alta con identidad no está activa' using errcode = 'P0409';
  end if;
  if v_uid is not null then
    v_cap := private.puede_alta_cliente();
    if coalesce((v_cap->>'ok')::boolean, false) is not true then
      raise exception 'No autorizado para crear clientes' using errcode = '42501';
    end if;
  end if;
  if p_payload is null or pg_catalog.jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Payload inválido' using errcode = '22023';
  end if;

  if p_paso = 'reclamar' then
    v_tipo := coalesce(nullif(pg_catalog.upper(pg_catalog.btrim(p_payload->>'tipo_documento')), ''), 'DNI');
    -- Misma normalización que el resolver (el lookup del perfil por documento la necesita igual).
    v_doc  := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_payload->>'documento', ''), '[^A-Za-z0-9]', '', 'g')), '');
    if v_doc is null then
      raise exception 'El documento es obligatorio para crear un cliente (identidad unificada)' using errcode = '22023';
    end if;
    perform private.identidad_bloquear_documento(v_tipo, v_doc);
    v_inv := private.inversionista_resolver(v_tipo, v_doc, true, 'alta_cliente');
    perform 1 from crm.inversionistas i where i.id = v_inv for update;
    -- Proyección canónica COMPLETA del alta (Codex E2 #10), sin documento (la identidad, uuid, ya lo aporta):
    v_hash_payload := pg_catalog.jsonb_build_object('v', 1, 'inv', v_inv,
      'correo', pg_catalog.lower(coalesce(p_payload->>'correo','')), 'nombre', coalesce(p_payload->>'nombre_completo',''),
      'apellidos', coalesce(p_payload->>'apellidos',''), 'nombres', coalesce(p_payload->>'nombres',''),
      'telefono', coalesce(p_payload->>'telefono',''), 'domicilio', coalesce(p_payload->'domicilio', 'null'::jsonb),
      'bancarios', coalesce(p_payload->'bancarios', 'null'::jsonb), 'asesor', coalesce(p_payload->>'asesor_id', ''));
    -- (El asesor DERIVADO del que llama no entra en la huella: otra sesión puede reanudar tras el lease.)
    -- 1) La SAGA manda antes que la existencia (Codex E2 #4): un enlace confirmado cuya respuesta se
    --    perdió se reanuda como 'enlazado' con su perfil_id, no como un rechazo.
    if exists (select 1 from crm.multiempresa_idempotencia i where i.clave = 'auth_persona:' || v_inv::text) then
      v_r := private.saga_auth_reclamar(v_inv, 'alta_cliente', v_hash_payload, null, p_payload->>'token');
      return v_r || pg_catalog.jsonb_build_object('asesor_id', coalesce(v_cap->>'asesor_id', p_payload->>'asesor_id'), 'via', coalesce(v_cap->>'via', 'service_role'));
    end if;
    -- 2) Persona ya cliente (identidad con perfil, o perfil suelto con el documento exacto creado con la
    --    bandera apagada, que se ENLAZA): resultado normal, NUNCA excepción (una excepción desharía el enlace).
    select i.perfil_id into v_perfil from crm.inversionistas i where i.id = v_inv;
    if v_perfil is null then
      select p.id into v_perfil from public.perfiles p
       where p.rol = 'cliente' and p.dni = v_doc and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
       limit 1;
      if v_perfil is not null then
        perform private.asegurar_identidad_perfil(v_perfil, 'alta_cliente');
      end if;
    end if;
    if v_perfil is not null then
      select p.activo into v_activo from public.perfiles p where p.id = v_perfil;
      return pg_catalog.jsonb_build_object('estado', 'ya_existia', 'perfil_id', v_perfil, 'activo', coalesce(v_activo, false),
        'inversionista_id', v_inv, 'reanudar', false);
    end if;
    -- 3) Claim nuevo.
    v_r := private.saga_auth_reclamar(v_inv, 'alta_cliente', v_hash_payload, null, p_payload->>'token');
    return v_r || pg_catalog.jsonb_build_object('asesor_id', coalesce(v_cap->>'asesor_id', p_payload->>'asesor_id'), 'via', coalesce(v_cap->>'via', 'service_role'));
  end if;

  v_claim := (p_payload->>'claim_id')::uuid;
  if v_claim is null then raise exception 'Falta claim_id' using errcode = '22023'; end if;

  if p_paso = 'registrar_auth' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'auth_creado', (p_payload->>'auth_user_id')::uuid, null, (p_payload->>'version')::integer);
  elsif p_paso = 'compensar_auth' then
    -- El edge borró el Auth (perfil rechazado por datos): el claim vuelve a 'reclamado'.
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'reclamado', null, null, (p_payload->>'version')::integer);
  elsif p_paso = 'perfil_creado' then
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'perfil_creado', null, (p_payload->>'perfil_id')::uuid, (p_payload->>'version')::integer);
  elsif p_paso = 'enlazar' then
    -- Sin lock del claim aquí: documento -> identidad -> perfil (asegurar) -> claim (avanzar).
    select * into v_loc from private.saga_auth_localizar(v_claim);
    if not found then raise exception 'Saga: claim inexistente' using errcode = 'P0002'; end if;
    if v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_payload->>'token') then
      raise exception 'Saga: token inválido' using errcode = '42501';
    end if;
    v_perfil := coalesce((p_payload->>'perfil_id')::uuid, (v_loc.estado->>'perfil_id')::uuid, (v_loc.estado->>'auth_user_id')::uuid);
    if v_perfil is null then raise exception 'Saga: sin perfil que enlazar' using errcode = 'P0409'; end if;
    v_r := private.asegurar_identidad_perfil(v_perfil, 'alta_cliente');
    if (v_r->>'inversionista_id')::uuid <> v_loc.inversionista_id then
      raise exception 'El perfil creado no corresponde a la persona reclamada' using errcode = 'P0409';
    end if;
    return private.saga_auth_avanzar(v_claim, p_payload->>'token', 'enlazado', null, v_perfil, (p_payload->>'version')::integer) || v_r;
  end if;
  raise exception 'Paso desconocido: %', p_paso using errcode = '22023';
end;
$$;
revoke all on function crm.alta_cliente_identidad_fn(text, jsonb) from public, anon;
grant execute on function crm.alta_cliente_identidad_fn(text, jsonb) to authenticated, service_role;

-- ============================================================================
-- 5. Preflight de eliminar-cliente (service_role)
-- ============================================================================
create or replace function crm.cliente_eliminable_fn(p_perfil_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio consulta si un cliente es eliminable' using errcode = '42501';
  end if;
  -- Solo con la bandera encendida (paridad: hoy el edge decide por contratos y la FK).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from crm.inversionistas i where i.perfil_id = p_perfil_id and i.estado <> 'fusionado') then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'identidad',
      'mensaje', 'Este cliente está reconocido como persona (identidad unificada): desactívalo en vez de eliminarlo');
  end if;
  select count(*) into v_n from public.contratos c where c.cliente_id = p_perfil_id;
  if v_n > 0 then
    return pg_catalog.jsonb_build_object('eliminable', false, 'motivo', 'contratos', 'contratos', v_n,
      'mensaje', 'Este cliente tiene contratos: desactívalo en vez de eliminarlo');
  end if;
  return pg_catalog.jsonb_build_object('eliminable', true);
end;
$$;
revoke all on function crm.cliente_eliminable_fn(uuid) from public, anon, authenticated;
grant execute on function crm.cliente_eliminable_fn(uuid) to service_role;

-- ============================================================================
-- 6. Corrección de documento de un cliente enlazado: solo por la puerta de Gerencia (b5)
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.actualizar_cliente_gerencia(p_cliente_id uuid, p_patch jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cliente public.perfiles%rowtype;
begin
  if private.rol_crm((select auth.uid())) <> 'gerencia' then
    raise exception 'Solo Gerencia puede corregir clientes fuera de cartera'
      using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'Los datos del cliente son invalidos'
      using errcode = '22023';
  end if;
  if (
    p_patch - array[
      'nombre_completo', 'nombres', 'apellidos', 'tipo_documento',
      'dni', 'telefono',
      'banco', 'tipo_cuenta', 'numero_cuenta', 'cci',
      'titular_distinto', 'beneficiario_nombre', 'beneficiario_dni',
      'banco_usd', 'tipo_cuenta_usd', 'numero_cuenta_usd', 'cci_usd',
      'titular_distinto_usd', 'beneficiario_nombre_usd',
      'beneficiario_dni_usd', 'actualizado_en'
    ]::text[]
  ) <> '{}'::jsonb then
    raise exception 'El formulario intento modificar campos no permitidos'
      using errcode = '22023';
  end if;

  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
  -- F2.b (b3): el documento de un cliente ENLAZADO a una identidad solo cambia por la
  -- corrección de documento de Gerencia (b5), que realinea identificador, perfil y lead.
  if (p_patch ? 'dni' or p_patch ? 'tipo_documento')
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from crm.inversionistas i where i.perfil_id = p_cliente_id and i.estado <> 'fusionado')
     and (coalesce(p_patch->>'dni', v_cliente.dni) is distinct from v_cliente.dni
          or coalesce(p_patch->>'tipo_documento', v_cliente.tipo_documento) is distinct from v_cliente.tipo_documento) then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige por la corrección de documento (Gerencia)'
      using errcode = 'P0409';
  end if;

  update public.perfiles
     set nombre_completo = case
           when p_patch ? 'nombre_completo'
             then p_patch->>'nombre_completo'
           else nombre_completo
         end,
         nombres = case
           when p_patch ? 'nombres' then p_patch->>'nombres'
           else nombres
         end,
         apellidos = case
           when p_patch ? 'apellidos' then p_patch->>'apellidos'
           else apellidos
         end,
         tipo_documento = case
           when p_patch ? 'tipo_documento'
             then p_patch->>'tipo_documento'
           else tipo_documento
         end,
         dni = case
           when p_patch ? 'dni' then p_patch->>'dni'
           else dni
         end,
         telefono = case
           when p_patch ? 'telefono' then p_patch->>'telefono'
           else telefono
         end,
         banco = case
           when p_patch ? 'banco' then p_patch->>'banco'
           else banco
         end,
         tipo_cuenta = case
           when p_patch ? 'tipo_cuenta' then p_patch->>'tipo_cuenta'
           else tipo_cuenta
         end,
         numero_cuenta = case
           when p_patch ? 'numero_cuenta'
             then p_patch->>'numero_cuenta'
           else numero_cuenta
         end,
         cci = case
           when p_patch ? 'cci' then p_patch->>'cci'
           else cci
         end,
         titular_distinto = case
           when p_patch ? 'titular_distinto'
             then (p_patch->>'titular_distinto')::boolean
           else titular_distinto
         end,
         beneficiario_nombre = case
           when p_patch ? 'beneficiario_nombre'
             then p_patch->>'beneficiario_nombre'
           else beneficiario_nombre
         end,
         beneficiario_dni = case
           when p_patch ? 'beneficiario_dni'
             then p_patch->>'beneficiario_dni'
           else beneficiario_dni
         end,
         banco_usd = case
           when p_patch ? 'banco_usd' then p_patch->>'banco_usd'
           else banco_usd
         end,
         tipo_cuenta_usd = case
           when p_patch ? 'tipo_cuenta_usd'
             then p_patch->>'tipo_cuenta_usd'
           else tipo_cuenta_usd
         end,
         numero_cuenta_usd = case
           when p_patch ? 'numero_cuenta_usd'
             then p_patch->>'numero_cuenta_usd'
           else numero_cuenta_usd
         end,
         cci_usd = case
           when p_patch ? 'cci_usd' then p_patch->>'cci_usd'
           else cci_usd
         end,
         titular_distinto_usd = case
           when p_patch ? 'titular_distinto_usd'
             then (p_patch->>'titular_distinto_usd')::boolean
           else titular_distinto_usd
         end,
         beneficiario_nombre_usd = case
           when p_patch ? 'beneficiario_nombre_usd'
             then p_patch->>'beneficiario_nombre_usd'
           else beneficiario_nombre_usd
         end,
         beneficiario_dni_usd = case
           when p_patch ? 'beneficiario_dni_usd'
             then p_patch->>'beneficiario_dni_usd'
           else beneficiario_dni_usd
         end,
         actualizado_en = now()
   where id = p_cliente_id;

  return true;
end;
$function$
;

-- ============================================================================
-- 7. Postflight
-- ============================================================================
do $post$
begin
  if to_regprocedure('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)') is null
     or to_regprocedure('private.saga_auth_avanzar(uuid,text,text,uuid,uuid,integer)') is null
     or to_regprocedure('private.saga_auth_localizar(uuid)') is null
     or to_regprocedure('private.puede_alta_cliente()') is null
     or to_regprocedure('private.asegurar_identidad_perfil(uuid,text)') is null
     or to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is null
     or to_regprocedure('crm.cliente_eliminable_fn(uuid)') is null then
    raise exception 'POSTFLIGHT b3: falta alguna función';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.oid in ('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)'::regprocedure,
                             'private.saga_auth_avanzar(uuid,text,text,uuid,uuid,integer)'::regprocedure,
                             'private.saga_auth_localizar(uuid)'::regprocedure,
                             'private.saga_token_hash(text)'::regprocedure,
                             'private.puede_alta_cliente()'::regprocedure,
                             'private.asegurar_identidad_perfil(uuid,text)'::regprocedure)
               and (a.grantee = 0 or a.grantee in ('anon'::regrole,'authenticated'::regrole,'service_role'::regrole)))
     or has_function_privilege('anon', 'crm.alta_cliente_identidad_fn(text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.alta_cliente_identidad_fn(text,jsonb)', 'EXECUTE')
     or not has_function_privilege('service_role', 'crm.alta_cliente_identidad_fn(text,jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.cliente_eliminable_fn(uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'crm.cliente_eliminable_fn(uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.actualizar_cliente_gerencia(uuid,jsonb)', 'EXECUTE')  -- interna: solo el dueño (como hoy)
     or not has_function_privilege('authenticated', 'crm.actualizar_cliente_gerencia_con_domicilio(uuid,jsonb)', 'EXECUTE') then
    raise exception 'POSTFLIGHT b3: grants incorrectos';
  end if;
  if (select strpos(prosrc, 'F2.b (b3)') from pg_proc where proname='actualizar_cliente_gerencia') = 0 then
    raise exception 'POSTFLIGHT b3: actualizar_cliente_gerencia sin transformar';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b3: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b3 OK: saga de Auth por identidad, capacidad de alta, alta con identidad, asegurar identidad del perfil, preflight de eliminación, documento del cliente enlazado protegido. Bandera APAGADA.';
end
$post$;

commit;
