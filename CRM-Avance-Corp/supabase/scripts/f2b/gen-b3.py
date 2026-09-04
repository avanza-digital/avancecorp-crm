import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:70], s.count(old)); return s.replace(old, new)
prod = {}
for line in open(S/'huellas14-prod.txt', encoding='utf-8'):
    k, v = line.rsplit(' ', 1); prod[k.strip()] = v.strip()
def h(name):
    calc = hashlib.md5(open(S/'vivas'/f'{name}.sql','rb').read()[:-1]).hexdigest()
    assert prod[name] == calc, (name, prod[name], calc); return prod[name]

acg_prev = viv('crm.actualizar_cliente_gerencia')
acg = rep(acg_prev, """  select *
    into v_cliente
  from public.perfiles
  where id = p_cliente_id
    and rol = 'cliente'
  for update;
  if not found then
    raise exception 'Cliente no encontrado' using errcode = 'P0002';
  end if;
""", """  select *
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
     and ((p_patch ? 'dni' and p_patch->>'dni' is distinct from v_cliente.dni)
          or (p_patch ? 'tipo_documento' and p_patch->>'tipo_documento' is distinct from v_cliente.tipo_documento)) then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige por la corrección de documento (Gerencia)'
      using errcode = 'P0409';
  end if;
""")

mig = r"""-- ============================================================================
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
  if v_h <> '{{H_ACG}}' and (select strpos(prosrc,'F2.b (b3)') from pg_proc where proname='actualizar_cliente_gerencia') = 0 then
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
  -- En 'reclamado' aún no existe nada externo: un payload distinto (correo corregido, etc.)
  -- REEMPLAZA la huella en vez de varar a la persona (auditor b3 A2). Desde 'auth_creado' el
  -- Auth y el perfil ya llevan los datos: un payload distinto es otra intención → P0409.
  if v_est->>'estado' <> 'reclamado' and v_row.hash_payload <> v_hash then
    raise exception 'La misma persona llegó con datos distintos; no se puede reintentar así'
      using errcode = 'P0409';
  end if;
  v_est := v_est || pg_catalog.jsonb_build_object('token_hash', private.saga_token_hash(v_token), 'owner', v_uid,
    'tipo', p_tipo, 'lead_id', coalesce(p_lead_id, (v_est->>'lead_id')::uuid),
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now());
  update crm.multiempresa_idempotencia
     set resultado = v_est, version = version + 1,
         hash_payload = case when v_est->>'estado' = 'reclamado' then v_hash else hash_payload end,
         tipo = p_tipo
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
       or (v_prev = p_estado                                      -- repetición idempotente: NUNCA reescribe auth/perfil (auditor b3 A1)
           and coalesce(p_auth_user_id, (v_est->>'auth_user_id')::uuid) is not distinct from (v_est->>'auth_user_id')::uuid
           and coalesce(p_perfil_id, (v_est->>'perfil_id')::uuid) is not distinct from (v_est->>'perfil_id')::uuid)) then
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
  if p_estado = 'enlazado' and (v_est->>'auth_user_id') is not null
     and coalesce(p_perfil_id, (v_est->>'perfil_id')::uuid) is distinct from (v_est->>'auth_user_id')::uuid then
    raise exception 'Saga: el perfil enlazado debe ser el usuario de Auth de este claim' using errcode = 'P0409';
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
     or coalesce(v_acc->>'estado', '') not in ('miembro','global','administrador_roles','revocado','no_enrolado')
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
  v_doc  := nullif(pg_catalog.upper(pg_catalog.regexp_replace(coalesce(v_p.dni, ''), '[^A-Za-z0-9]', '', 'g')), '');
  if v_doc is null then
    raise exception 'El cliente no tiene documento: no se puede reconocer a la persona (identidad unificada)'
      using errcode = 'P0409';
  end if;
  -- jerarquía (compartida, como derivar) -> documento -> identidad -> perfil. La jerarquía va
  -- PRIMERO: el offboarding la toma exclusiva y luego actualiza perfiles (Codex E2 #9).
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  perform private.identidad_bloquear_documento(v_tipo, v_doc);
  v_inv := private.inversionista_resolver(v_tipo, v_doc, true, p_fuente);
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  perform 1 from public.perfiles p where p.id = p_perfil_id
     and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
     and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni, ''), '[^A-Za-z0-9]', '', 'g')) = v_doc
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
    -- Asesor releído bajo el perfil FOR SHARE (el offboarding no pudo cambiarlo: sostiene la jerarquía exclusiva).
    select p.asesor_perfil_id into v_asesor from public.perfiles p where p.id = p_perfil_id;
    if v_asesor is not null
       and exists (select 1 from crm.equipo e join public.perfiles pp on pp.id = e.perfil_id
                   where e.perfil_id = v_asesor and e.activo and pp.activo) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo, por)
      values (v_inv, v_asesor, p_fuente, (select auth.uid()));
      update crm.inversionistas set responsable_relacion_id = v_asesor where id = v_inv;
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
       where p.rol = 'cliente'
         and pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p.dni,''), '[^A-Za-z0-9]', '', 'g')) = v_doc
         and coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') = v_tipo
       limit 1;
      if v_perfil is not null then
        perform private.asegurar_identidad_perfil(v_perfil, 'alta_cliente');
      end if;
    end if;
    if v_perfil is not null then
      select p.activo into v_activo from public.perfiles p where p.id = v_perfil;
      -- Un vendedor (vía crm) solo sabe que existe y si está activo: sin ids (anti-pesca, auditor b3 M3).
      if coalesce(v_cap->>'via', '') = 'crm' and coalesce(v_cap->>'asesor_id', '') <> '' then
        return pg_catalog.jsonb_build_object('estado', 'ya_existia', 'activo', coalesce(v_activo, false), 'reanudar', false);
      end if;
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
    v_perfil := coalesce((v_loc.estado->>'perfil_id')::uuid, (v_loc.estado->>'auth_user_id')::uuid);
    if v_perfil is null then raise exception 'Saga: sin perfil que enlazar' using errcode = 'P0409'; end if;
    if (p_payload->>'perfil_id') is not null and (p_payload->>'perfil_id')::uuid is distinct from v_perfil then
      raise exception 'Saga: el perfil a enlazar es el del claim, no el del payload' using errcode = 'P0409';
    end if;
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
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if exists (select 1 from crm.inversionistas i where i.perfil_id = p_perfil_id and i.estado <> 'fusionado') then
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
{{ACG}}
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
""".replace("{{H_ACG}}", h('crm.actualizar_cliente_gerencia')).replace("{{ACG}}", acg)
(W/'migrations'/'20260905100000_crm_f2b_b3_alta_cliente_identidad.sql').write_text(mig, encoding='utf-8')

rb = r"""-- ============================================================================
-- REVERSA de F2.b sub-lote b3 (20260905100000_crm_f2b_b3_alta_cliente_identidad)
-- ============================================================================
-- Suelta las RPC/helpers nuevos y restaura byte a byte crm.actualizar_cliente_gerencia
-- (verificado por md5 contra el vivo de producción). Conserva claims, enlaces y tramos
-- creados con la bandera encendida (hechos). Bandera APAGADA. Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b3_reversa'));
do $pre$
begin
  if to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is not null then
    raise exception 'REVERSA b3: b4 (20260905110000) sigue instalada y usa la saga de b3; revierte b4 primero';
  end if;
  if strpos(pg_get_functiondef('public.crear_contrato(jsonb,jsonb)'::regprocedure), 'asegurar_identidad_perfil') > 0 then
    raise exception 'REVERSA b3: public.crear_contrato llama a asegurar_identidad_perfil; revierte ese parche primero';
  end if;
end
$pre$;
update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = true;

drop function if exists crm.alta_cliente_identidad_fn(text, jsonb);
drop function if exists crm.cliente_eliminable_fn(uuid);
drop function if exists private.asegurar_identidad_perfil(uuid, text);
drop function if exists private.puede_alta_cliente();
drop function if exists private.saga_auth_avanzar(uuid, text, text, uuid, uuid, integer);
drop function if exists private.saga_auth_localizar(uuid);
drop function if exists private.saga_auth_reclamar(uuid, text, jsonb, uuid, text);
drop function if exists private.saga_token_hash(text);

""" + acg_prev + r"""
;

do $post$
begin
  if to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is not null
     or to_regprocedure('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)') is not null then
    raise exception 'REVERSA b3: quedó algo del lote';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='crm' and p.proname='actualizar_cliente_gerencia') <> '{{H_ACG}}' then
    raise exception 'REVERSA b3: actualizar_cliente_gerencia no volvió byte a byte al vivo de producción';
  end if;
  raise notice 'REVERSA F2.b b3 OK';
end
$post$;
commit;
""".replace('{{H_ACG}}', h('crm.actualizar_cliente_gerencia'))
(W/'scripts'/'rollback-f2b-b3.sql').write_text(rb, encoding='utf-8')
print('b3 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()))
