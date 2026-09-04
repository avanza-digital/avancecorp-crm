import sys, pathlib, hashlib, re
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

# ── convertir_lead_externo: reserva viva de OTRO lead de la misma persona + inversiones con la bandera de F4 ──
cle_prev = viv('crm.convertir_lead_externo')
cle = rep(cle_prev, """  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
""", """  if v_flag then
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
""")
cle = rep(cle, """  if v_flag and v_inv is not null then
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)""",
"""  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'inversiones_escritura'), false) then
    insert into crm.inversiones (inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion, creado_por)""")

# ── marcar_efectos_conversion: lock de la identidad reservada ANTES de sellar (Codex E2 #6) ──
mec_prev = viv('crm.marcar_efectos_conversion')
mec = rep(mec_prev, """  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())""",
"""  -- F2.b (b4): si la reserva es por PERSONA, se bloquea la identidad antes de sellar
  -- (orden identidad -> reserva; la conversión coop lee las reservas bajo ese mismo lock).
  perform 1 from crm.inversionistas i
   where i.id = (select r.inversionista_id from crm.conversion_reservas r where r.lead_id = p_lead_id)
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
   for update;
  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())""")

# ── la sobrecarga nueva de reservar copia VERBATIM el ámbito y el upsert de la viva ──
rcl = viv('crm.reservar_conversion_lead')
i = rcl.index("  select *\n    into v_lead\n  from crm.leads"); j = rcl.index("  if v_lead.etapa in ('convertido', 'descartado') then")
ambito = rcl[i:j]
i = rcl.index("  insert into crm.conversion_reservas as r"); j = rcl.index("  return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'expira_en', v_expira);")
upsert = rcl[i:j]
upsert = rep(upsert, """  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,""", """  insert into crm.conversion_reservas as r
    (lead_id, reservado_por, expira_en, vence_absoluto_en, inversionista_id, hash_payload)
  values (p_lead_id, v_uid,
          v_ahora + v_ventana, v_ahora + v_tope, v_inv, v_hash)
  on conflict (lead_id) do update
     set reservado_por = excluded.reservado_por,
         reservado_en  = v_ahora,
         inversionista_id = v_inv,
         hash_payload  = v_hash,""")

mig = r"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b4 — LA CONVERSIÓN AVANCE RESERVA POR LA
-- PERSONA Y NO DEJA HUÉRFANOS (saga de Auth compartida con b3)
-- ============================================================================
--
-- QUE: hoy la reserva de conversión es por LEAD; dos leads distintos de la misma persona
-- podían cerrarse a la vez por Avance y por cooperativa, y una caída tras crear el Auth
-- dejaba perfil huérfano y lead incerrable. Con la bandera ENCENDIDA:
--   * crm.reservar_conversion_lead(lead, tipo, documento, payload): resuelve la identidad
--     ANTES de Auth, revalida (sin veto, sin OTRO lead, sin reserva viva de otro lead de la
--     persona), reserva con inversionista_id (nunca el documento) y abre/reanuda el claim.
--     Es el preflight: revalida DESPUÉS de esperar el advisory. La de 1 argumento sigue
--     (bandera apagada = idéntico a hoy, con P-058).
--   * crm.marcar_efectos_conversion: bloquea la identidad reservada antes de sellar (Codex #6)
--     + sobrecarga con claim/token que verifica la ejecución.
--   * crm.saga_conversion_fn(paso, payload): registrar_auth / compensar_auth / perfil_creado /
--     cerrar. `cerrar` es TRANSACCIONAL (Codex #7): convierte (convertir_lead_con_domicilio),
--     comprueba que la identidad convertida es la reservada y avanza el claim; si no, revierte.
--   * crm.retomar_conversion_gerencia_fn(lead): pasado el tope, solo Gerencia retoma una
--     reserva sellada (claim en reclamado / auth_creado / perfil_creado, Codex #5).
--   * crm.convertir_lead_externo: rechaza si la persona tiene una conversión Avance en curso en
--     OTRO lead; los hechos de inversión (crm.inversiones) pasan a la bandera de F4
--     `inversiones_escritura` (Codex v2 #17).
-- Orden total: documento -> identidad -> perfil -> lead -> reserva -> claim.
-- TODO detrás de la bandera; RPC nuevas inertes con la bandera apagada.
-- Reversa: scripts/rollback-f2b-b4.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b4_conversion_por_persona'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.saga_auth_reclamar(uuid,text,jsonb,uuid,text)') is null
     or to_regprocedure('crm.alta_cliente_identidad_fn(text,jsonb)') is null then
    raise exception 'F2.b b4: falta b3 (20260905100000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false)
     or coalesce((select activo from crm.multiempresa_flags where nombre='inversiones_escritura'), false) then
    raise exception 'F2.b b4: alguna bandera está ENCENDIDA; este lote aterriza apagado';
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='convertir_lead_externo';
  if v_h <> '{{H_CLE}}' and (select strpos(prosrc,'F2.b (b4)') from pg_proc where proname='convertir_lead_externo') = 0 then
    raise exception 'F2.b b4: crm.convertir_lead_externo no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid';
  if v_h <> '{{H_MEC}}' and (select strpos(prosrc,'F2.b (b4)') from pg_proc p where proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid') = 0 then
    raise exception 'F2.b b4: crm.marcar_efectos_conversion no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid';
  if v_h <> '{{H_RCL}}' then
    raise exception 'F2.b b4: crm.reservar_conversion_lead(uuid) no es el texto vivo esperado (%): la sobrecalga copia su ámbito y su upsert', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 1. Columnas ADITIVAS de la reserva (sin documento)
-- ============================================================================
alter table crm.conversion_reservas
  add column if not exists inversionista_id uuid references crm.inversionistas(id),
  add column if not exists claim_id uuid,
  add column if not exists hash_payload text;
create index if not exists conversion_reservas_inv_idx on crm.conversion_reservas (inversionista_id) where inversionista_id is not null;
comment on column crm.conversion_reservas.inversionista_id is 'F2.b b4: la PERSONA reservada (identidad, nunca documento). Solo con resolver_en_puertas.';
comment on column crm.conversion_reservas.claim_id is 'F2.b b4: claim de la saga de Auth (crm.multiempresa_idempotencia).';
comment on column crm.conversion_reservas.hash_payload is 'F2.b b4: huella canónica del alta (sin documento).';

-- ============================================================================
-- 2. Sobrecarga: reservar por PERSONA (bandera ON). Ámbito y upsert copiados de la viva.
-- ============================================================================
create or replace function crm.reservar_conversion_lead(p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
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
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
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
{{AMBITO}}
  -- El documento tecleado debe ser el de la persona de ESTE lead (misma regla que convertir_lead, adelantada a antes de Auth).
  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
  if v_tipo = 'DNI' and v_lead.dni is not null and v_lead.dni <> v_doc then
    raise exception 'El documento no coincide con el del lead' using errcode = 'P0409';
  end if;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
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

{{UPSERT}}
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
$$;
revoke all on function crm.reservar_conversion_lead(uuid, text, text, jsonb) from public, anon, service_role;
grant execute on function crm.reservar_conversion_lead(uuid, text, text, jsonb) to authenticated;

-- ============================================================================
-- 3. Sellar: identidad ANTES de la reserva (transformación de la viva) + sobrecarga con token
-- ============================================================================
{{MEC}}
;

create or replace function crm.marcar_efectos_conversion(p_lead_id uuid, p_claim_id uuid, p_token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_loc record;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
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
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  return crm.marcar_efectos_conversion(p_lead_id);
end;
$$;
revoke all on function crm.marcar_efectos_conversion(uuid, uuid, text) from public, anon, service_role;
grant execute on function crm.marcar_efectos_conversion(uuid, uuid, text) to authenticated;

-- ============================================================================
-- 4. La saga de la conversión: registrar_auth / compensar_auth / perfil_creado / cerrar (transaccional)
-- ============================================================================
create or replace function crm.saga_conversion_fn(p_paso text, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_claim uuid; v_loc record; v_res jsonb; v_perfil uuid; v_lead uuid; v_inv_conv uuid;
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
$$;
revoke all on function crm.saga_conversion_fn(text, jsonb) from public, anon, service_role;
grant execute on function crm.saga_conversion_fn(text, jsonb) to authenticated;

-- ============================================================================
-- 5. Gerencia retoma una reserva sellada pasado el tope (claim en cualquier estado no terminal)
-- ============================================================================
create or replace function crm.retomar_conversion_gerencia_fn(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_uid uuid := (select auth.uid()); v_inv uuid; v_r crm.conversion_reservas%rowtype; v_est jsonb; v_token text; v_clave text;
begin
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia retoma una conversión' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select r.inversionista_id into v_inv from crm.conversion_reservas r where r.lead_id = p_lead_id;
  if v_inv is null then
    raise exception 'Este lead no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_r from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if v_r.efectos_iniciados_en is null then
    raise exception 'La reserva no está sellada: basta con volver a reservar' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is null or v_est->>'estado' = 'enlazado' then
    raise exception 'No hay una conversión a medias que retomar' using errcode = 'P0409';
  end if;
  if (v_est->>'lead_id')::uuid is distinct from p_lead_id or v_r.claim_id is distinct from (v_est->>'claim_id')::uuid then
    raise exception 'La reserva y el claim de esta persona no corresponden a este lead' using errcode = 'P0409';
  end if;
  -- Nunca expulsa a una ejecución viva: solo pasado el tope de la reserva o con el lease del claim vencido (Codex E2 #10).
  if v_r.vence_absoluto_en > pg_catalog.now() and (v_est->>'lease_hasta')::timestamptz > pg_catalog.now() then
    raise exception 'La conversión sigue viva (reserva y claim vigentes): no hay nada que retomar todavía' using errcode = 'P0409';
  end if;
  v_token := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
  v_est := v_est || pg_catalog.jsonb_build_object('token_hash', private.saga_token_hash(v_token), 'owner', v_uid,
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now(), 'retomado_por_gerencia', true);
  update crm.multiempresa_idempotencia set resultado = v_est, version = version + 1 where clave = v_clave;
  update crm.conversion_reservas r
     set reservado_por = v_uid, reservado_en = pg_catalog.now(),
         expira_en = pg_catalog.now() + interval '5 minutes', vence_absoluto_en = pg_catalog.now() + interval '30 minutes'
   where r.lead_id = p_lead_id;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', v_inv,
    'claim_id', (v_est->>'claim_id')::uuid, 'token', v_token, 'estado', v_est->>'estado',
    'version', (select i.version from crm.multiempresa_idempotencia i where i.clave = v_clave),
    'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid, 'reanudar', true);
end;
$$;
revoke all on function crm.retomar_conversion_gerencia_fn(uuid) from public, anon, service_role;
grant execute on function crm.retomar_conversion_gerencia_fn(uuid) to authenticated;

-- ============================================================================
-- 5b. Ayudantes de los edges (service_role): Auth por correo con su marca; eliminar cliente en UNA transacción
-- ============================================================================
-- El edge no puede buscar en auth.users por PostgREST. Devuelve solo id y la marca del claim.
create or replace function crm.auth_usuario_por_correo_fn(p_correo text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case when not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    then pg_catalog.jsonb_build_object('id', null, 'apagada', true)
    else coalesce((
    select pg_catalog.jsonb_build_object('id', u.id, 'claim_id', u.raw_app_meta_data->>'claim_id',
                                         'tiene_perfil', exists (select 1 from public.perfiles p where p.id = u.id))
    from auth.users u
    where pg_catalog.lower(u.email) = pg_catalog.lower(pg_catalog.btrim(p_correo))
    limit 1), pg_catalog.jsonb_build_object('id', null)) end
$$;
revoke all on function crm.auth_usuario_por_correo_fn(text) from public, anon, authenticated;
grant execute on function crm.auth_usuario_por_correo_fn(text) to service_role;

-- eliminar-cliente (Codex E2 #8): comprobar y borrar en la MISMA transacción (comunicados + perfil);
-- el Auth lo borra el edge después. Con la bandera apagada: mismas reglas que hoy (contratos y FK).
create or replace function crm.eliminar_cliente_fn(p_perfil_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare v_pre jsonb; v_nombre text; v_n integer;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el servicio elimina clientes' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el edge usa su ruta de siempre' using errcode = 'P0409';
  end if;
  select p.nombre_completo into v_nombre from public.perfiles p where p.id = p_perfil_id and p.rol = 'cliente' for update;
  if not found then
    raise exception 'El cliente no existe o ya fue eliminado' using errcode = 'P0002';
  end if;
  v_pre := crm.cliente_eliminable_fn(p_perfil_id);
  if coalesce((v_pre->>'eliminable')::boolean, false) is not true then
    raise exception '%', coalesce(v_pre->>'mensaje', 'El cliente no se puede eliminar')
      using errcode = 'P0409', detail = v_pre::text;
  end if;
  -- Un perfil de una saga aún sin enlazar tampoco se borra por aquí.
  if exists (select 1 from crm.multiempresa_idempotencia i
                 where i.clave like 'auth\_persona:%' and i.resultado->>'perfil_id' = p_perfil_id::text
                   and i.resultado->>'estado' <> 'enlazado') then
    raise exception 'Este cliente tiene un alta en curso (identidad unificada): espera a que termine' using errcode = 'P0409';
  end if;
  delete from public.novedades n where n.destinatario_id = p_perfil_id;
  get diagnostics v_n = row_count;
  delete from public.perfiles p where p.id = p_perfil_id;
  return pg_catalog.jsonb_build_object('ok', true, 'nombre', v_nombre, 'comunicados_borrados', v_n);
end;
$$;
revoke all on function crm.eliminar_cliente_fn(uuid) from public, anon, authenticated;
grant execute on function crm.eliminar_cliente_fn(uuid) to service_role;

-- ============================================================================
-- 6. Conversión cooperativa: reserva viva de OTRO lead de la persona + inversiones con la bandera de F4
-- ============================================================================
{{CLE}}
;

-- ============================================================================
-- 7. Postflight
-- ============================================================================
do $post$
begin
  if to_regprocedure('crm.reservar_conversion_lead(uuid,text,text,jsonb)') is null
     or to_regprocedure('crm.reservar_conversion_lead(uuid)') is null
     or to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)') is null
     or to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is null
     or to_regprocedure('crm.retomar_conversion_gerencia_fn(uuid)') is null
     or to_regprocedure('crm.auth_usuario_por_correo_fn(text)') is null
     or to_regprocedure('crm.eliminar_cliente_fn(uuid)') is null then
    raise exception 'POSTFLIGHT b4: falta alguna función';
  end if;
  if (select count(*) from information_schema.columns where table_schema='crm' and table_name='conversion_reservas'
       and column_name in ('inversionista_id','claim_id','hash_payload')) <> 3 then
    raise exception 'POSTFLIGHT b4: faltan columnas en conversion_reservas';
  end if;
  if (select strpos(prosrc, 'F2.b (b4)') from pg_proc where proname='convertir_lead_externo') = 0
     or (select strpos(prosrc, 'inversiones_escritura') from pg_proc where proname='convertir_lead_externo') = 0
     or (select strpos(prosrc, 'F2.b (b4)') from pg_proc p where proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid') = 0 then
    raise exception 'POSTFLIGHT b4: transformaciones ausentes';
  end if;
  if has_function_privilege('anon', 'crm.saga_conversion_fn(text,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.saga_conversion_fn(text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.saga_conversion_fn(text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.reservar_conversion_lead(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.retomar_conversion_gerencia_fn(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.auth_usuario_por_correo_fn(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.eliminar_cliente_fn(uuid)', 'EXECUTE')
     or not has_function_privilege('service_role', 'crm.eliminar_cliente_fn(uuid)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                where p.oid in ('crm.saga_conversion_fn(text,jsonb)'::regprocedure, 'crm.reservar_conversion_lead(uuid,text,text,jsonb)'::regprocedure,
                                'crm.retomar_conversion_gerencia_fn(uuid)'::regprocedure, 'crm.marcar_efectos_conversion(uuid,uuid,text)'::regprocedure)
                  and a.grantee = 0) then
    raise exception 'POSTFLIGHT b4: grants incorrectos';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b4: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b4 OK: reserva por persona, sellado con identidad y token, saga de conversión con cierre transaccional, retoma de Gerencia, coop rechaza Avance en curso, inversiones con inversiones_escritura. Bandera APAGADA.';
end
$post$;

commit;
""".replace("{{H_CLE}}", h('crm.convertir_lead_externo')).replace("{{H_MEC}}", h('crm.marcar_efectos_conversion')).replace("{{H_RCL}}", h('crm.reservar_conversion_lead')).replace("{{AMBITO}}", ambito).replace("{{UPSERT}}", upsert).replace("{{MEC}}", mec).replace("{{CLE}}", cle)
(W/'migrations'/'20260905110000_crm_f2b_b4_conversion_por_persona.sql').write_text(mig, encoding='utf-8')

rb = r"""-- ============================================================================
-- REVERSA de F2.b sub-lote b4 (20260905110000_crm_f2b_b4_conversion_por_persona)
-- ============================================================================
-- Suelta las RPC nuevas, restaura byte a byte convertir_lead_externo y marcar_efectos_conversion
-- (md5 contra el vivo de producción) y retira las columnas aditivas de la reserva. Conserva
-- claims/enlaces (hechos). Banderas APAGADAS. Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b4_reversa'));
update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre in ('resolver_en_puertas','inversiones_escritura') and activo = true;

drop function if exists crm.saga_conversion_fn(text, jsonb);
drop function if exists crm.retomar_conversion_gerencia_fn(uuid);
drop function if exists crm.auth_usuario_por_correo_fn(text);
drop function if exists crm.eliminar_cliente_fn(uuid);
drop function if exists crm.marcar_efectos_conversion(uuid, uuid, text);
drop function if exists crm.reservar_conversion_lead(uuid, text, text, jsonb);

""" + cle_prev + r"""
;

""" + mec_prev + r"""
;

do $vuelo$
declare v_n integer;
begin
  select count(*) into v_n from crm.conversion_reservas r
   where r.claim_id is not null and r.efectos_iniciados_en is not null and r.vence_absoluto_en > now();
  if v_n > 0 then
    raise exception 'REVERSA b4: hay % conversiones por persona en vuelo (selladas y vigentes); espera a que terminen o caduquen', v_n;
  end if;
end
$vuelo$;
drop index if exists crm.conversion_reservas_inv_idx;
alter table crm.conversion_reservas
  drop column if exists hash_payload,
  drop column if exists claim_id,
  drop column if exists inversionista_id;

do $post$
begin
  if to_regprocedure('crm.saga_conversion_fn(text,jsonb)') is not null
     or to_regprocedure('crm.reservar_conversion_lead(uuid,text,text,jsonb)') is not null
     or to_regprocedure('crm.marcar_efectos_conversion(uuid,uuid,text)') is not null
     or to_regprocedure('crm.retomar_conversion_gerencia_fn(uuid)') is not null
     or to_regprocedure('crm.auth_usuario_por_correo_fn(text)') is not null
     or to_regprocedure('crm.eliminar_cliente_fn(uuid)') is not null
     or exists (select 1 from information_schema.columns where table_schema='crm' and table_name='conversion_reservas'
                and column_name in ('inversionista_id','claim_id','hash_payload')) then
    raise exception 'REVERSA b4: quedó algo del lote';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='convertir_lead_externo') <> '{{H_CLE}}'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='marcar_efectos_conversion' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid') <> '{{H_MEC}}' then
    raise exception 'REVERSA b4: alguna función no volvió byte a byte al vivo de producción';
  end if;
  raise notice 'REVERSA F2.b b4 OK';
end
$post$;
commit;
""".replace("{{H_CLE}}", h('crm.convertir_lead_externo')).replace("{{H_MEC}}", h('crm.marcar_efectos_conversion'))
(W/'scripts'/'rollback-f2b-b4.sql').write_text(rb, encoding='utf-8')
print('b4 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()))
