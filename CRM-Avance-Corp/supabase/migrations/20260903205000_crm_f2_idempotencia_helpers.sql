-- ============================================================================
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
