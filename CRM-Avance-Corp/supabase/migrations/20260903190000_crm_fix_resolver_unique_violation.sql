-- ============================================================================
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
