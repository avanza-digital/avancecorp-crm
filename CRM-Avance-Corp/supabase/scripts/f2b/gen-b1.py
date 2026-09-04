import sys, re, pathlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')

def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:70], s.count(old))
    return s.replace(old, new)

# ── 1. impl 3-arg: verificado=true en las dos ramas + lead_id en ya_es_cliente ──
impl_prev = viv('private.verificar_disponibilidad_lead_impl.3')
impl = impl_prev
impl = rep(impl,
"""      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
      and i.no_contactar = true""",
"""      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and i.no_contactar = true""")
impl = rep(impl,
"""      and idf.estado = 'vigente'
      and i.estado <> 'fusionado'
      and li.id is distinct from p_excluir_lead_id""",
"""      and idf.estado = 'vigente'
      and idf.verificado = true
      and i.estado <> 'fusionado'
      and li.id is distinct from p_excluir_lead_id""")

# ── 2. crear_lead_si_disponible: documento ANTES de contactos ──
cl_prev = viv('crm.crear_lead_si_disponible')
cl = rep(cl_prev,
"""  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);""",
"""  -- F2.b (b1): orden total documento -> identidad -> contactos. Con la bandera
  -- apagada el helper no toma ningún lock (paridad exacta).
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);""")

hereda_prev = viv('private.trg_leads_hereda_veto_persona')

mig = r"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b1 — EL ALTA RECONOCE A LA PERSONA
-- ============================================================================
--
-- QUE (invariantes #6, #7, #8 del contrato F0): con la bandera resolver_en_puertas
-- ENCENDIDA, todo INSERT en crm.leads y todo cambio de dni pasan por el documento
-- exacto (identificador VIGENTE y VERIFICADO de una identidad no fusionada) —
-- el cambio de dni solo puede RECHAZARSE (nunca enlaza ni bloquea, ver zz):
--   (a) persona vetada                       -> P0429 (no se abre oportunidad, §7.3)
--   (b) persona que ya tiene un lead (vivo,
--       convertido o descartado)             -> P0481 {estado:'ya_es_cliente', via:'identidad', lead_id}
--   (c) persona sin lead                     -> el lead nace ENLAZADO (inversionista_id + puente)
--   sin documento o sin coincidencia         -> NULL (captación, §4.3). NUNCA crea identidad.
-- Cierra el bypass de crm-importar-leads (inserta con service_role y el trigger de
-- disponibilidad lo deja pasar sin veredicto) y la edición de dni por PostgREST.
--
-- COMO (orden total de locks, uno para todas las puertas):
--   documento (advisory 'inv_resolver:tipo:norm', el mismo del resolver)
--   -> identidad FOR UPDATE (releer el veto tras esperar)
--   -> contactos (bloquear_contactos_lead)  <- SIEMPRE el último
--   * trg_leads_000_hereda_veto  (BEFORE INSERT): documento -> identidad FOR UPDATE ->
--     P0429 si vetada (ya NO copia el veto: la alta de una persona vetada se rechaza,
--     contrato §7.3).
--   * trg_leads_00_disponibilidad_* (sin cambios): toma contactos DESPUÉS (orden por nombre).
--   * trg_leads_zz_enlaza_identidad (BEFORE INSERT OR UPDATE OF dni): corre DESPUÉS de
--     trg_leads_protege_inversionista_id (orden alfabético, determinista) y por eso no
--     necesita válvula: en INSERT fija new.inversionista_id o levanta P0481; en UPDATE
--     NUNCA enlaza ni toma locks (la fila ya está bloqueada: sería lead->identidad):
--     RECHAZA (P0409) el cambio de DNI de un lead enlazado o hacia una persona
--     reconocida — eso es la corrección de documento de Gerencia (b5).
--   * trg_leads_zz_puente_identidad (AFTER INSERT OR UPDATE, comparando el valor: «UPDATE
--     OF columna» no ve lo que fija un BEFORE): el puente crm.inversionista_leads se
--     escribe cuando el lead YA existe (FK).
--   * crm.crear_lead_si_disponible: toma el documento antes de los contactos.
--   * Semántica única: solo vigente+verificado resuelve (contrato §4.2/#8). Se alinea
--     verificar_disponibilidad_lead_impl (260000) — en prod las 427 identidades son
--     vigente+verificado: ninguna cifra cambia.
--   * crm.registrar_reingreso_lead_fn (service_role): el cliente que vuelve por la hoja
--     queda como actividad 'nota' en SU lead (reingreso = señal de venta, §12).
--
-- TODO detrás de la bandera: APAGADA = idéntico a hoy (los helpers no toman locks,
-- los triggers devuelven new, el impl y el alta no cambian de veredicto).
-- Reversa: scripts/rollback-f2b-b1.sql (texto previo byte a byte).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b1_alta_reconoce_persona'));

do $guard$
begin
  if to_regclass('crm.inversionistas') is null
     or to_regclass('crm.inversionista_leads') is null
     or not exists (select 1 from crm.multiempresa_flags where nombre='resolver_en_puertas')
     or to_regprocedure('private.inversionista_resolver(text,text,boolean,text)') is null
     or to_regprocedure('private.verificar_disponibilidad_lead_impl(text,text,uuid)') is null
     or to_regprocedure('crm.marcar_no_contactar(uuid,text)') is null
     or to_regprocedure('crm.bandera_activa(text)') is null
     or to_regprocedure('private.trg_leads_hereda_veto_persona()') is null
     or to_regprocedure('crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)') is null then
    raise exception 'F2.b b1: falta F1 o el lote Contrato-F2 (190000-260000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b b1: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
end
$guard$;


-- Guarda del TEXTO VIVO (regla de la casa: una función viva no se reteclea): cada función
-- transformada debe ser la que se transformó (md5 de pg_get_functiondef en prod, 04/09/2026)
-- o estar ya transformada por este mismo lote (reaplicación en banco).
do $vivo$
declare v_h text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='trg_leads_hereda_veto_persona';
  if v_h <> '1a4483fc758555d861e211978035eaa3' and (select strpos(prosrc,'inversionista_por_documento') from pg_proc where proname='trg_leads_hereda_veto_persona') = 0 then
    raise exception 'F2.b b1: private.trg_leads_hereda_veto_persona no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid) = 'p_telefono text, p_dni text, p_excluir_lead_id uuid';
  if v_h <> '63e775094796e564ae04c088d0642bec' and (select strpos(prosrc,'idf.verificado = true') from pg_proc p where p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid) like '%uuid%') = 0 then
    raise exception 'F2.b b1: verificar_disponibilidad_lead_impl(3) no es el texto vivo esperado (%)', v_h;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='crear_lead_si_disponible';
  if v_h <> '9c86f9f748a375f75ee7731981c32d02' and (select strpos(prosrc,'identidad_bloquear_documento') from pg_proc where proname='crear_lead_si_disponible') = 0 then
    raise exception 'F2.b b1: crm.crear_lead_si_disponible no es el texto vivo esperado (%)', v_h;
  end if;
end
$vivo$;

-- ============================================================================
-- 1. Helpers de identidad (privados, sin EXECUTE para la API)
-- ============================================================================
-- Lock documental con la MISMA clave que private.inversionista_resolver. Con la
-- bandera apagada NO toma ningún lock: paridad exacta.
create or replace function private.identidad_bloquear_documento(p_tipo text, p_documento text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_norm text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'));
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  if v_norm = '' or p_tipo is null then
    return;
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('inv_resolver:' || p_tipo || ':' || v_norm));
end;
$$;
revoke all on function private.identidad_bloquear_documento(text, text) from public, anon, authenticated, service_role;

-- Lookup NO creador: devuelve la identidad CANÓNICA cuyo identificador vigente y
-- verificado coincide exactamente; NULL si no hay. (El resolver con p_verificado=false
-- lanza 22023, por eso el alta usa este lookup y nunca el resolver.)
create or replace function private.inversionista_por_documento(p_tipo text, p_documento text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(inv.inversionista_canonico_id, inv.id)
  from crm.inversionista_identificadores idf
  join crm.inversionistas inv on inv.id = idf.inversionista_id
  where idf.tipo_documento = p_tipo
    and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_documento,''), '[^A-Za-z0-9]', '', 'g'))
    and idf.estado = 'vigente'
    and idf.verificado = true
    and inv.estado <> 'fusionado'
  limit 1
$$;
revoke all on function private.inversionista_por_documento(text, text) from public, anon, authenticated, service_role;

-- Identidad FOR UPDATE por documento (el paso «identidad» del orden total) para las
-- puertas que no lo dan por un trigger. Reentrante con el FOR UPDATE del trigger 000.
create or replace function private.identidad_bloquear_persona(p_tipo text, p_documento text)
returns void
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare v_inv uuid;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return;
  end if;
  v_inv := private.inversionista_por_documento(p_tipo, p_documento);
  if v_inv is null then
    return;
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
end;
$$;
revoke all on function private.identidad_bloquear_persona(text, text) from public, anon, authenticated, service_role;

-- La bandera la leen también los edges que solo tienen service_role (importador).
-- Es un booleano sin PII.
grant execute on function crm.bandera_activa(text) to service_role;

-- ============================================================================
-- 2. Trigger 000: documento -> identidad FOR UPDATE -> veto (P0429)
-- ============================================================================
create or replace function private.trg_leads_hereda_veto_persona()
returns trigger
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_inv uuid;
  v_veto boolean;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  -- Solo DNI: crm.leads.dni es siempre DNI de 8 dígitos (contrato §18). Se
  -- normaliza igual que el resolver (este trigger corre ANTES del btrim de 00).
  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    return new;
  end if;
  -- Orden total: documento -> identidad -> (contactos los toma 00 después).
  perform private.identidad_bloquear_documento('DNI', new.dni);
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    return new;
  end if;
  -- Serializa contra marcar/levantar_no_contactar (identidad FOR UPDATE) y relee.
  select i.no_contactar into v_veto
  from crm.inversionistas i
  where i.id = v_inv
  for update;
  if coalesce(v_veto, false) then
    raise exception 'La persona tiene la restricción «No insistir»: no se abre una oportunidad nueva'
      using errcode = 'P0429',
            detail = pg_catalog.jsonb_build_object('estado', 'no_contactar', 'via', 'identidad')::text;
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
-- 3. Trigger zz: enlaza (o rechaza) DESPUÉS de trg_leads_protege_inversionista_id
-- ============================================================================
create or replace function private.trg_leads_zz_enlaza_identidad()
returns trigger
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
  v_inv uuid;
  v_otro record;
begin
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.dni is not distinct from old.dni or v_priv then
      return new;
    end if;
    -- En UPDATE la fila del lead YA está bloqueada: aquí no se toma ningún lock de
    -- identidad (evitaría el orden documento->identidad->lead y podría abrazarse con
    -- marcar/levantar y la conversión). Se RECHAZA, no se enlaza: el documento de una
    -- persona enlazada, o un documento que resuelve a una persona reconocida, solo
    -- cambia por la corrección de Gerencia (bajo válvula, b5). Un DNI que no resuelve
    -- a nadie sigue editándose como hoy.
    if old.inversionista_id is not null
       or (nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is not null
           and private.inversionista_por_documento('DNI', new.dni) is not null) then
      raise exception 'El documento pertenece a una persona reconocida: solo Gerencia lo corrige (corrección de documento)'
        using errcode = 'P0409';
    end if;
    return new;
  elsif v_priv and new.inversionista_id is not null then
    -- Una RPC bajo válvula que ya trae el enlace (p. ej. una fusión futura) manda.
    return new;
  end if;

  if nullif(pg_catalog.btrim(coalesce(new.dni,'')), '') is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- El advisory documental ya lo tomó el trigger 000 en esta misma sentencia.
  v_inv := private.inversionista_por_documento('DNI', new.dni);
  if v_inv is null then
    new.inversionista_id := null;
    return new;
  end if;
  -- Un solo lead TOTAL por persona (invariante #6): vivos, convertidos y descartados.
  select l.id, coalesce(resp.nombre_completo, 'sin asesor asignado') as asesor
    into v_otro
  from crm.leads l
  join crm.inversionistas i on i.id = l.inversionista_id
  left join public.perfiles resp on resp.id = i.responsable_relacion_id
  where l.inversionista_id = v_inv
    and l.id is distinct from new.id
  limit 1;
  if found then
    raise exception 'Contacto no disponible'
      using errcode = 'P0481',
            detail = pg_catalog.jsonb_build_object(
              'estado', 'ya_es_cliente', 'asesor', v_otro.asesor, 'via', 'identidad', 'lead_id', v_otro.id)::text;
  end if;
  new.inversionista_id := v_inv;
  return new;
end;
$$;
revoke all on function private.trg_leads_zz_enlaza_identidad() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_zz_enlaza_identidad on crm.leads;
create trigger trg_leads_zz_enlaza_identidad
  before insert or update of dni on crm.leads
  for each row execute function private.trg_leads_zz_enlaza_identidad();

-- ============================================================================
-- 4. Trigger AFTER: el puente persona<->lead, cuando el lead ya existe (FK)
-- ============================================================================
create or replace function private.trg_leads_zz_puente_identidad()
returns trigger
language plpgsql
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_priv boolean := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- «UPDATE OF columna» mira la lista SET de la sentencia, no el valor: un BEFORE
  -- que fija inversionista_id no lo dispararía. Por eso AFTER INSERT OR UPDATE
  -- con comparación de valor.
  if tg_op = 'UPDATE' and new.inversionista_id is not distinct from old.inversionista_id then
    return null;
  end if;
  if new.inversionista_id is null then
    return null;
  end if;
  if not coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il where il.lead_id = new.id) then
    -- Reapuntes de puente (fusión) los gestiona su propia puerta bajo válvula.
    if v_priv then
      return null;
    end if;
    if exists (select 1 from crm.inversionista_leads il
               where il.lead_id = new.id and il.inversionista_id <> new.inversionista_id) then
      raise exception 'El puente persona<->lead no coincide con el enlace del lead' using errcode = 'P0409';
    end if;
    return null;
  end if;
  if exists (select 1 from crm.inversionista_leads il
             where il.inversionista_id = new.inversionista_id and il.rol = 'canonico' and il.lead_id <> new.id) then
    raise exception 'La persona ya tiene un lead canónico' using errcode = 'P0409';
  end if;
  insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
  values (new.inversionista_id, new.id, 'canonico');
  return null;
end;
$$;
revoke all on function private.trg_leads_zz_puente_identidad() from public, anon, authenticated, service_role;

drop trigger if exists trg_leads_zz_puente_identidad on crm.leads;
create trigger trg_leads_zz_puente_identidad
  after insert or update on crm.leads
  for each row execute function private.trg_leads_zz_puente_identidad();

-- ============================================================================
-- 5. Semántica única (vigente + verificado) en la disponibilidad + lead_id en el veredicto
-- ============================================================================
""" + impl + r"""
;

-- ============================================================================
-- 6. Alta manual: documento ANTES de contactos
-- ============================================================================
""" + cl + r"""
;

-- ============================================================================
-- 7. Reingreso: el cliente que vuelve por la hoja queda en SU lead (service_role)
-- ============================================================================
create or replace function crm.registrar_reingreso_lead_fn(p_lead_id uuid, p_origen text, p_datos jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_datos jsonb;
begin
  if (select auth.uid()) is not null then
    raise exception 'Solo el importador (service_role) registra reingresos' using errcode = '42501';
  end if;
  -- Paridad apagada: superficie inerte mientras la identidad no esté activa (Codex E1).
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada: el reingreso no se registra' using errcode = 'P0409';
  end if;
  if p_lead_id is null or not exists (select 1 from crm.leads l where l.id = p_lead_id) then
    raise exception 'Lead inexistente' using errcode = 'P0002';
  end if;
  if p_origen is null or pg_catalog.length(pg_catalog.btrim(p_origen)) not between 1 and 40 then
    raise exception 'Origen inválido' using errcode = '22023';
  end if;
  -- Sin documento en claro en la actividad: solo datos comerciales del formulario.
  v_datos := (
    select coalesce(pg_catalog.jsonb_object_agg(e.key, e.value), '{}'::jsonb)
    from pg_catalog.jsonb_each(coalesce(p_datos, '{}'::jsonb)) e
    where e.key in ('nombre','telefono','telefono_alternativo','correo','capital','moneda','canal','distrito','interes','nota','fila')
  );
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (
    p_lead_id, 'nota',
    'Reingreso por ' || pg_catalog.btrim(p_origen) || ': la persona volvió a dejar sus datos',
    pg_catalog.jsonb_build_object('evento', 'reingreso', 'origen', pg_catalog.btrim(p_origen), 'datos', v_datos),
    null)
  returning id into v_id;
  return pg_catalog.jsonb_build_object('ok', true, 'actividad_id', v_id);
end;
$$;
revoke all on function crm.registrar_reingreso_lead_fn(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function crm.registrar_reingreso_lead_fn(uuid, text, jsonb) to service_role;

-- ============================================================================
-- 8. Postflight
-- ============================================================================
do $post$
declare
  v_def text;
begin
  if to_regprocedure('private.identidad_bloquear_documento(text,text)') is null
     or to_regprocedure('private.identidad_bloquear_persona(text,text)') is null
     or to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is null
     or to_regprocedure('private.trg_leads_zz_puente_identidad()') is null
     or to_regprocedure('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)') is null then
    raise exception 'POSTFLIGHT b1: falta alguna función';
  end if;
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where t.tgname='trg_leads_000_hereda_veto' and c.relname='leads' and c.relnamespace='crm'::regnamespace;
  if v_def is null or v_def not like '%BEFORE INSERT ON crm.leads%' or v_def like '%UPDATE%' then
    raise exception 'POSTFLIGHT b1: trg_leads_000_hereda_veto no es BEFORE INSERT (%)', v_def;
  end if;
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where t.tgname='trg_leads_zz_enlaza_identidad' and c.relname='leads' and c.relnamespace='crm'::regnamespace;
  if v_def is null or v_def not like '%BEFORE INSERT OR UPDATE OF dni ON crm.leads%' then
    raise exception 'POSTFLIGHT b1: trg_leads_zz_enlaza_identidad mal definido (%)', v_def;
  end if;
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where t.tgname='trg_leads_zz_puente_identidad' and c.relname='leads' and c.relnamespace='crm'::regnamespace;
  if v_def is null or v_def not like '%AFTER INSERT OR UPDATE ON crm.leads%' then
    raise exception 'POSTFLIGHT b1: trg_leads_zz_puente_identidad mal definido (%)', v_def;
  end if;
  -- El orden por nombre es la garantía: protege < zz_enlaza (mismo timing BEFORE).
  if 'trg_leads_protege_inversionista_id' collate "C" >= 'trg_leads_zz_enlaza_identidad' collate "C"
     or 'trg_leads_000_hereda_veto' collate "C" >= 'trg_leads_00_disponibilidad_insert' collate "C" then
    raise exception 'POSTFLIGHT b1: el orden alfabético de triggers no garantiza protege antes de zz';
  end if;
  if (select strpos(prosrc, 'idf.verificado = true') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl'
        and pg_get_function_identity_arguments(p.oid) = 'p_telefono text, p_dni text, p_excluir_lead_id uuid') = 0 then
    raise exception 'POSTFLIGHT b1: el impl de disponibilidad no exige verificado';
  end if;
  if (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='crm' and p.proname='crear_lead_si_disponible') = 0 then
    raise exception 'POSTFLIGHT b1: crear_lead_si_disponible no toma el documento';
  end if;
  -- CREATE OR REPLACE conserva la ACL; se comprueba igual (y PUBLIC = grantee 0, que
  -- has_function_privilege enmascara).
  if not has_function_privilege('authenticated', 'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text,text)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                where p.oid in ('private.verificar_disponibilidad_lead_impl(text,text,uuid)'::regprocedure,
                                'private.inversionista_por_documento(text,text)'::regprocedure,
                                'private.identidad_bloquear_documento(text,text)'::regprocedure,
                                'private.identidad_bloquear_persona(text,text)'::regprocedure,
                                'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)'::regprocedure)
                  and a.grantee = 0) then
    raise exception 'POSTFLIGHT b1: ACL inesperada (crear_lead sin authenticated o PUBLIC con EXECUTE)';
  end if;
  if not has_function_privilege('service_role', 'crm.bandera_activa(text)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'crm.registrar_reingreso_lead_fn(uuid,text,jsonb)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.inversionista_por_documento(text,text)', 'EXECUTE') then
    raise exception 'POSTFLIGHT b1: grants incorrectos';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b1: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b1 OK: el alta reconoce a la persona (documento->identidad->contactos; zz tras protege; puente en AFTER). Bandera APAGADA.';
end
$post$;

commit;
"""
(W/'migrations'/'20260904120000_crm_f2b_b1_alta_reconoce_persona.sql').write_text(mig, encoding='utf-8')

rb = r"""-- ============================================================================
-- REVERSA de F2.b sub-lote b1 (20260904120000_crm_f2b_b1_alta_reconoce_persona)
-- ============================================================================
-- Restaura byte a byte (pg_get_functiondef de producción, 04/09/2026) las tres
-- funciones transformadas y suelta triggers/helpers/RPC nuevos. Conserva los
-- enlaces (inversionista_id, puentes, actividades de reingreso) creados con la
-- bandera encendida: son hechos. Deja la bandera APAGADA. Repetible dos veces.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b1_reversa'));
do $pre$
begin
  if to_regprocedure('private.persona_vetada(uuid)') is not null then
    raise exception 'REVERSA b1: b2 (20260904130000) sigue instalada y usa los helpers de b1; revierte b2 primero';
  end if;
end
$pre$;

update crm.multiempresa_flags set activo = false, actualizado_en = now()
  where nombre = 'resolver_en_puertas' and activo = true;

drop trigger if exists trg_leads_zz_puente_identidad on crm.leads;
drop trigger if exists trg_leads_zz_enlaza_identidad on crm.leads;
drop function if exists private.trg_leads_zz_puente_identidad();
drop function if exists private.trg_leads_zz_enlaza_identidad();
drop function if exists crm.registrar_reingreso_lead_fn(uuid, text, jsonb);
revoke execute on function crm.bandera_activa(text) from service_role;

-- 000: versión de 20260903240000 (solo copia el veto; BEFORE INSERT).
""" + hereda_prev + r"""
;
drop trigger if exists trg_leads_000_hereda_veto on crm.leads;
create trigger trg_leads_000_hereda_veto
  before insert on crm.leads
  for each row execute function private.trg_leads_hereda_veto_persona();

-- Disponibilidad: versión de 20260903260000.
""" + impl_prev + r"""
;

-- Alta manual: versión de 20260826182500 + parche 20260901185600.
""" + cl_prev + r"""
;

drop function if exists private.identidad_bloquear_documento(text, text);
drop function if exists private.identidad_bloquear_persona(text, text);
drop function if exists private.inversionista_por_documento(text, text);

do $post$
declare v_def text;
begin
  if to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is not null
     or to_regprocedure('private.identidad_bloquear_documento(text,text)') is not null
     or to_regprocedure('crm.registrar_reingreso_lead_fn(uuid,text,jsonb)') is not null then
    raise exception 'REVERSA b1: quedó algo del lote';
  end if;
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where t.tgname='trg_leads_000_hereda_veto' and c.relname='leads' and c.relnamespace='crm'::regnamespace;
  if v_def is null or v_def not like '%BEFORE INSERT ON crm.leads%' or v_def like '%UPDATE%' then
    raise exception 'REVERSA b1: trg_leads_000_hereda_veto no volvió a BEFORE INSERT (%)', v_def;
  end if;
  if (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='crm' and p.proname='crear_lead_si_disponible') <> 0 then
    raise exception 'REVERSA b1: crear_lead_si_disponible sigue transformada';
  end if;
  -- El texto restaurado debe ser el VIVO de producción (md5 de pg_get_functiondef, 04/09/2026).
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='trg_leads_hereda_veto_persona') <> '1a4483fc758555d861e211978035eaa3'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='crear_lead_si_disponible') <> '9c86f9f748a375f75ee7731981c32d02'
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='verificar_disponibilidad_lead_impl' and pg_get_function_identity_arguments(p.oid) = 'p_telefono text, p_dni text, p_excluir_lead_id uuid') <> '63e775094796e564ae04c088d0642bec' then
    raise exception 'REVERSA b1: el texto restaurado no coincide byte a byte con el vivo de producción';
  end if;
  raise notice 'REVERSA F2.b b1 OK';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-b1.sql').write_text(rb, encoding='utf-8')
print('migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), 'líneas')
