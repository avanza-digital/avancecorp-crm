-- REGISTRO en supabase_migrations.schema_migrations de F2.b E1 (2 versiones: b1 y b2).
-- `db query --linked --file` NO registra: correr ESTE archivo DESPUÉS de aplicar las 2, en orden.
-- Un elemento por versión = el fichero entero (un solo mensaje, como se aplicó). Idempotente.
begin;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260904120000', 'crm_f2b_b1_alta_reconoce_persona', array[$m$-- ============================================================================
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
CREATE OR REPLACE FUNCTION private.verificar_disponibilidad_lead_impl(p_telefono text, p_dni text, p_excluir_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
      and idf.verificado = true
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
      and idf.verificado = true
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
$function$
;

-- ============================================================================
-- 6. Alta manual: documento ANTES de contactos
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.crear_lead_si_disponible(p_nombre_completo text, p_telefono text, p_origen text, p_monto_estimado numeric, p_moneda text, p_id uuid DEFAULT NULL::uuid, p_correo text DEFAULT NULL::text, p_dni text DEFAULT NULL::text, p_genero text DEFAULT NULL::text, p_fecha_nacimiento date DEFAULT NULL::date, p_distrito text DEFAULT NULL::text, p_etapa text DEFAULT 'nuevo'::text, p_categoria_interes text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_nota text DEFAULT NULL::text, p_telefono_alternativo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
  v_alt_bruto text := nullif(pg_catalog.btrim(p_telefono_alternativo), '');
  v_alt text;
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_correo text := nullif(pg_catalog.btrim(p_correo), '');
  v_genero text := nullif(pg_catalog.btrim(p_genero), '');
  v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
  v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
  v_nota text := nullif(pg_catalog.btrim(p_nota), '');
  v_vendedor uuid := p_vendedor_id;
  v_supervisor uuid;
  v_disponibilidad jsonb;
  v_existente crm.leads%rowtype;
  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_nombre is null then
    raise exception using errcode = '22023', message = 'El nombre es obligatorio';
  end if;
  if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;

  -- EL SEGUNDO NUMERO (opcion A). Admite celular, fijo peruano o cualquier pais,
  -- via la MISMA regla que el conector y el front. No participa del dedup: la
  -- identidad del lead sigue siendo `telefono`.
  if v_alt_bruto is not null then
    select c.e164 into v_alt from private.canonizar_contacto(v_alt_bruto) c;
    if v_alt is null then
      raise exception using
        errcode = '22023',
        message = 'Segundo telefono invalido: celular peruano, fijo peruano (014457890) o internacional con +codigo de pais';
    end if;
    -- Si repite al principal no aporta un canal nuevo: se guarda vacio en vez de
    -- enseñar el mismo numero dos veces en la ficha.
    if v_alt = v_telefono then
      v_alt := null;
    end if;
  end if;

  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
  end if;

  -- D8 (2026-08-11) · «landing y formulario se carga solo»: los canales
  -- automáticos (y los heredados) SOLO entran por el puente. Un alta manual que
  -- los declare está suplantando a la fuente — y con T10 vivo (el referido
  -- fuera del divisor), el origen mueve el porcentaje de alguien.
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro') then
    raise exception using
      errcode = '42501',
      message = 'Ese origen entra solo por el puente: el alta manual admite referido, oficina u otro';
  end if;

  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;

  if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
  end if;
  if p_monto_estimado is null
     or p_monto_estimado <= 0
     or p_monto_estimado > 9999999999.99
     or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
    raise exception using errcode = '22023', message = 'Capital estimado invalido';
  end if;
  if p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda invalida';
  end if;
  if v_genero is not null and v_genero not in ('F', 'M') then
    raise exception using errcode = '22023', message = 'Genero invalido';
  end if;
  if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception using errcode = '22023', message = 'Categoria de interes invalida';
  end if;
  if p_fecha_nacimiento is not null
     and (
       p_fecha_nacimiento < date '1900-01-01'
       or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
     ) then
    raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
  end if;

  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then
    if v_vendedor is not null and v_vendedor is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
    end if;
    v_vendedor := v_actor;
    v_supervisor := null;
  elsif v_vendedor is null and v_rol = 'supervisor' then
    v_supervisor := v_actor;
  else
    v_supervisor := null;
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  -- La identidad optimista funciona también como llave idempotente: si el
  -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
  -- antes de una mutación posterior confirma el alta anterior en vez de
  -- pintarla como un contacto ajeno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
  );
  -- F2.b (b1): orden total documento -> identidad -> contactos. Con la bandera
  -- apagada el helper no toma ningún lock (paridad exacta).
  perform private.identidad_bloquear_documento('DNI', v_dni);
  perform private.identidad_bloquear_persona('DNI', v_dni);
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- Un administrador puede desactivar la membresia mientras esta sesion
  -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
  -- los locks para que una sesion revocada no alcance a insertar al despertar.
  v_rol_actual := private.rol_crm(v_actor);
  if v_rol_actual is distinct from v_rol
     or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  select l.* into v_existente
  from crm.leads l
  where l.id = v_id;

  if found then
    if v_existente.creado_por is not distinct from v_actor
       and v_existente.nombre_completo is not distinct from v_nombre
       and v_existente.telefono is not distinct from v_telefono
       -- El segundo numero entra en la comparacion idempotente: sin esto, un
       -- reintento que SOLO cambia el alternativo se confirmaria como «ya
       -- creado» y el dato nuevo se perderia sin decir nada.
       and v_existente.telefono_alternativo is not distinct from v_alt
       and v_existente.correo is not distinct from v_correo
       and v_existente.dni is not distinct from v_dni
       and v_existente.genero is not distinct from v_genero
       and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
       and v_existente.distrito is not distinct from v_distrito
       and v_existente.origen is not distinct from p_origen
       and v_existente.etapa is not distinct from p_etapa
       and v_existente.monto_estimado is not distinct from p_monto_estimado
       and v_existente.moneda is not distinct from p_moneda
       and v_existente.categoria_interes is not distinct from v_categoria
       and v_existente.vendedor_id is not distinct from v_vendedor
       and v_existente.asignado_supervisor_id is not distinct from v_supervisor
       and v_existente.nota is not distinct from v_nota
       and v_existente.activo = true then
      return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
    end if;

    raise exception using
      errcode = '22023',
      message = 'El identificador de esta alta ya fue usado con datos distintos';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    return v_disponibilidad;
  end if;

  insert into crm.leads (
    id,
    nombre_completo,
    telefono,
    telefono_alternativo,
    correo,
    dni,
    genero,
    fecha_nacimiento,
    distrito,
    origen,
    etapa,
    monto_estimado,
    moneda,
    categoria_interes,
    vendedor_id,
    asignado_supervisor_id,
    nota,
    activo,
    creado_por,
    alta_manual
  ) values (
    v_id,
    v_nombre,
    v_telefono,
    v_alt,
    v_correo,
    v_dni,
    v_genero,
    p_fecha_nacimiento,
    v_distrito,
    p_origen,
    p_etapa,
    p_monto_estimado,
    p_moneda,
    v_categoria,
    v_vendedor,
    v_supervisor,
    v_nota,
    true,
    v_actor,
    true
  );

  return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
end;
$function$
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
$m$])
on conflict (version) do nothing;

insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260904130000', 'crm_f2b_b2_veto_persona_mutaciones', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b2 — EL VETO DE LA PERSONA BLOQUEA
-- REPARTO, TOMA, REAPERTURA Y SEGUIMIENTO (contrato §7.3, invariante #7)
-- ============================================================================
--
-- QUE: hasta hoy las MUTACIONES solo miraban crm.leads.no_contactar (el veto del
-- lead). Con la bandera resolver_en_puertas ENCENDIDA pasan a respetar también el
-- veto de la PERSONA: por crm.leads.inversionista_id -> identidad canónica, o por
-- documento exacto (identificador vigente y verificado) cuando el lead no está
-- enlazado. Además el veto cancela las tareas pendientes y bloquea el seguimiento
-- (actividades/tareas humanas) por el trigger de gestión que ya bloquea el lead.
--
-- COMO: helper único private.persona_vetada(lead) (+ forma set-based), STABLE y sin
-- lock; se consulta DESPUÉS del FOR UPDATE del lead en cada puerta (lectura: no
-- cambia el orden de locks). Cada función se TRANSFORMA desde su texto vivo
-- (pg_get_functiondef de producción, 04/09/2026) con reemplazos anclados.
--   * repartir_lead_implementacion, derivar_leads_equipo_fn, revertir_derivacion_equipo_fn,
--     deshacer_descarte_implementacion -> P0429; tomar_lead_libre -> veredicto no_contactar;
--     resumen_reparto_fn -> mismo criterio que la cola; trg_gestion_lead_serializada -> P0429
--     (exime la válvula op_privilegiada, bajo la que las RPC de veto dejan su nota);
--     marcar/levantar_no_contactar -> por PERSONA también cuando el lead está suelto (documento
--     exacto) + marcar cancela tareas pendientes (selladas 'sistema'); rescatar_descartes -> P0429.
--     El offboarding NO se toca (la reasignación del responsable de relación es la puerta de
--     Gerencia de b5: evita el ciclo identidad<->crm.equipo que señaló Codex).
-- TODO detrás de la bandera: APAGADA = persona_vetada() devuelve false y ninguna
-- puerta cambia de respuesta, SQLSTATE ni efectos (paridad exacta).
-- Reversa: scripts/rollback-f2b-b2.sql (texto previo byte a byte).

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_b2_veto_persona_mutaciones'));

do $guard$
begin
  if to_regprocedure('private.inversionista_por_documento(text,text)') is null
     or to_regprocedure('crm.marcar_no_contactar(uuid,text)') is null then
    raise exception 'F2.b b2: falta b1 (20260904120000) o el lote Contrato-F2';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b b2: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
end
$guard$;


-- Guarda del TEXTO VIVO (md5 de pg_get_functiondef en prod, 04/09/2026), o ya transformada
-- por este lote (marca 'F2.b (b2)' en prosrc) para reaplicar en banco.
do $vivo$
declare r record; v_h text; v_src text;
begin
  for r in select * from (values
    ('private.repartir_lead_implementacion','306e51ce145aae695f932b936199242e'),
    ('crm.derivar_leads_equipo_fn','9a4eae7eb21bbe0080139a0cf3686e3b'),
    ('crm.revertir_derivacion_equipo_fn','43699042a1b300a960a0696977f08b35'),
    ('crm.tomar_lead_libre','b0a3a3d185ff90504489fe9313023a13'),
    ('private.deshacer_descarte_implementacion','a386c107d7a7f04a9b369d5e152d8093'),
    ('crm.resumen_reparto_fn','51bdcdc6ed9849370a071d42e1a3600a'),
    ('private.leads_por_repartir_implementacion','6c6d2e57f7dd9a4c182e2513bab2c941'),
    ('private.trg_gestion_lead_serializada','03f171cc19acecb744b040bd7435a2a7'),
    ('crm.marcar_no_contactar','9807431e2b8511ea81395b037fe31c7a'),
    ('crm.levantar_no_contactar','6ec378121ea1736a0915be1d7e59213c'),
    ('crm.rescatar_descartes','7ecc2d7173578815d1d878ebfd7e11cb')
  ) as v(fn, h) loop
    select md5(pg_get_functiondef(p.oid)), p.prosrc into v_h, v_src
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
     where n.nspname || '.' || p.proname = r.fn;
    if v_h is null then
      raise exception 'F2.b b2: falta %', r.fn;
    end if;
    if v_h <> r.h and strpos(v_src, 'F2.b (b2)') = 0 then
      raise exception 'F2.b b2: % no es el texto vivo esperado (%)', r.fn, v_h;
    end if;
  end loop;
end
$vivo$;

-- ============================================================================
-- 1. Helpers del veto de la persona (privados, STABLE, sin lock)
-- ============================================================================
create or replace function private.leads_vetados_persona(p_lead_ids uuid[])
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select l.id
  from crm.leads l
  left join crm.inversionistas inv0 on inv0.id = l.inversionista_id
  left join crm.inversionistas inv  on inv.id  = coalesce(inv0.inversionista_canonico_id, inv0.id)
  where l.id = any (coalesce(p_lead_ids, array[]::uuid[]))
    and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
    and (
      l.no_contactar = true
      or coalesce(inv.no_contactar, false)
      or (l.inversionista_id is null
          and nullif(pg_catalog.btrim(coalesce(l.dni,'')), '') is not null
          and exists (
            select 1
            from crm.inversionista_identificadores idf
            join crm.inversionistas i on i.id = idf.inversionista_id
            where idf.tipo_documento = 'DNI'
              and idf.documento_normalizado = pg_catalog.upper(pg_catalog.regexp_replace(l.dni, '[^A-Za-z0-9]', '', 'g'))
              and idf.estado = 'vigente'
              and idf.verificado = true
              and i.estado <> 'fusionado'
              and i.no_contactar = true))
    )
$$;
revoke all on function private.leads_vetados_persona(uuid[]) from public, anon, authenticated, service_role;

create or replace function private.persona_vetada(p_lead_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from private.leads_vetados_persona(array[p_lead_id]))
$$;
revoke all on function private.persona_vetada(uuid) from public, anon, authenticated, service_role;

-- ============================================================================
-- 2. Reparto (implementación viva; el wrapper crm.repartir_lead no se toca)
-- ============================================================================
CREATE OR REPLACE FUNCTION private.repartir_lead_implementacion(p_lead uuid, p_supervisor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor      uuid := (select auth.uid());
  v_lead       crm.leads%rowtype;
  v_sup_nombre text;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads' using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios' using errcode = '22023';
  end if;

  select p.nombre_completo into v_sup_nombre
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_supervisor
    and e.rol_crm = 'supervisor' and e.activo = true and p.activo = true;
  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  for update;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;
  -- F2.b (b2): el veto es de la PERSONA (contrato §7.3). Lectura sin lock tras el
  -- FOR UPDATE del lead: no altera el orden de locks.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede repartir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  update crm.leads
     set asignado_supervisor_id = p_supervisor
   where id = p_lead and activo = true
     and vendedor_id is null and asignado_supervisor_id is null;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'repartido_en', statement_timestamp());
end;
$function$
;

-- ============================================================================
-- 3. Derivación entre equipos
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.derivar_leads_equipo_fn(p_lead_ids uuid[], p_asesor_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_total integer;
  v_distintos integer;
  v_destinos_solicitados integer;
  v_destinos_validos integer := 0;
  v_leads_encontrados integer := 0;
  v_indice integer;
  v_asesor record;
  v_lead record;
begin
  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede derivar leads de su equipo'
      using errcode = '42501';
  end if;

  -- Los cambios canónicos de jerarquía/offboarding toman esta misma clave en
  -- modo exclusivo antes de bloquear equipo y luego leads. Aquí basta modo
  -- compartido: varias derivaciones pueden convivir, pero ninguna se cruza
  -- con una baja/traslado y se evita el ciclo equipo → lead / lead → equipo.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  if p_lead_ids is null
     or pg_catalog.array_length(p_lead_ids, 1) is null
     or pg_catalog.array_ndims(p_lead_ids) <> 1
     or pg_catalog.array_lower(p_lead_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_lead_ids, 1) < 1
     or pg_catalog.array_length(p_lead_ids, 1) > 100
     or pg_catalog.array_position(p_lead_ids, null) is not null then
    raise exception 'Selecciona entre 1 y 100 leads válidos para derivar'
      using errcode = '22023';
  end if;

  if p_asesor_ids is null
     or pg_catalog.array_ndims(p_asesor_ids) <> 1
     or pg_catalog.array_lower(p_asesor_ids, 1) is distinct from 1
     or pg_catalog.array_length(p_asesor_ids, 1) is distinct from pg_catalog.array_length(p_lead_ids, 1)
     or pg_catalog.array_position(p_asesor_ids, null) is not null then
    raise exception 'Cada lead debe tener exactamente un asesor destino'
      using errcode = '22023';
  end if;

  v_total := pg_catalog.array_length(p_lead_ids, 1);
  select pg_catalog.count(*)::integer
    into v_distintos
  from (
    select distinct lead_id
    from pg_catalog.unnest(p_lead_ids) as entrada(lead_id)
  ) distintos;
  if v_distintos <> v_total then
    raise exception 'Un mismo lead no se puede derivar dos veces en el mismo guardado'
      using errcode = '22023';
  end if;

  select pg_catalog.count(*)::integer
    into v_destinos_solicitados
  from (
    select distinct asesor_id
    from pg_catalog.unnest(p_asesor_ids) as entrada(asesor_id)
  ) destinos;

  -- Bloqueo determinista: dos supervisores no pueden ganar una carrera sobre
  -- el mismo lead ni dejar un borrador parcialmente aplicado.
  for v_lead in
    select
      l.id,
      l.vendedor_id,
      l.asignado_supervisor_id,
      l.activo,
      l.etapa,
      l.no_contactar
    from crm.leads l
    where l.id = any(p_lead_ids)
    order by l.id
    for update
  loop
    v_leads_encontrados := v_leads_encontrados + 1;
    if v_lead.vendedor_id is not null
       or v_lead.asignado_supervisor_id is distinct from v_actor
       or v_lead.activo is not true
       or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
      raise exception 'El lead % ya no está disponible en tu bandeja', v_lead.id
        using errcode = 'P0001';
    end if;
    if v_lead.no_contactar is true then
      raise exception 'El lead % está marcado No Insista y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
    -- F2.b (b2): veto de la PERSONA (contrato §7.3).
    if private.persona_vetada(v_lead.id) then
      raise exception 'El lead % pertenece a una persona con la restricción «No insistir» y no se puede derivar', v_lead.id
        using errcode = 'P0429';
    end if;
  end loop;

  if v_leads_encontrados <> v_total then
    raise exception 'Uno de los leads seleccionados ya no existe'
      using errcode = 'P0001';
  end if;

  -- El precheck evita que un usuario sin rol use la RPC para bloquear filas
  -- ajenas. Esta segunda lectura sí bloquea y vuelve a validar al supervisor:
  -- Gerencia no puede desactivarlo mientras el guardado está en curso.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de derivar'
      using errcode = '42501';
  end if;

  -- Orden global de locks: leads → supervisor → asesores (igual que devolver).
  -- La pertenencia no es una foto optimista: bloqueamos, en orden
  -- determinista, tanto la membresía CRM como el perfil activo. Así Gerencia
  -- no puede mover/desactivar al asesor entre la validación y el UPDATE de los
  -- leads. El trigger de tenencia valida rol/activo, pero no supervisor_id.
  for v_asesor in
    select asesor_equipo.perfil_id
    from crm.equipo asesor_equipo
    join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
    where asesor_equipo.perfil_id = any(p_asesor_ids)
      and asesor_equipo.rol_crm = 'vendedor'
      and asesor_equipo.supervisor_id = v_actor
      and asesor_equipo.activo = true
      and asesor_perfil.activo = true
    order by asesor_equipo.perfil_id
    for no key update of asesor_equipo, asesor_perfil
  loop
    v_destinos_validos := v_destinos_validos + 1;
  end loop;

  if v_destinos_validos <> v_destinos_solicitados then
    raise exception 'Uno de los asesores destino ya no pertenece a tu equipo activo'
      using errcode = '42501';
  end if;

  for v_indice in 1..v_total loop
    update crm.leads
    set vendedor_id = p_asesor_ids[v_indice],
        asignado_supervisor_id = null
    where id = p_lead_ids[v_indice];
  end loop;

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'derivados', v_total,
    'lead_ids', pg_catalog.to_jsonb(p_lead_ids)
  );
end;
$function$
;

-- ============================================================================
-- 4. Reversión de derivación
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.revertir_derivacion_equipo_fn(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_hoy date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_inicio_hoy timestamptz := v_hoy::timestamp at time zone 'America/Lima';
  v_fin_hoy timestamptz := (v_hoy + 1)::timestamp at time zone 'America/Lima';
  v_lead crm.leads%rowtype;
  v_episodio crm.lead_asignaciones%rowtype;
  v_asesor_bloqueado uuid;
begin
  if p_lead_id is null then
    raise exception 'Indica el lead que deseas devolver'
      using errcode = '22023';
  end if;

  if v_actor is null or not exists (
    select 1
    from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm = 'supervisor'
      and actor_equipo.activo = true
      and actor_perfil.activo = true
  ) then
    raise exception 'Solo un supervisor activo puede devolver derivaciones de su equipo'
      using errcode = '42501';
  end if;

  -- Interlock compartido con la jerarquía: offboarding usa la misma clave en
  -- exclusivo antes de tocar equipo/leads. Debe ocurrir antes del row lock.
  perform pg_catalog.pg_advisory_xact_lock_shared(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select l.*
    into v_lead
  from crm.leads l
  where l.id = p_lead_id
  for update;
  if not found then
    raise exception 'El lead ya no está disponible'
      using errcode = 'P0001';
  end if;
  -- F2.b (b2): con la bandera encendida, ni el lead vetado ni el de una persona
  -- vetada se devuelven a la bandeja (coherente con reparto/derivación).
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se devuelve a la bandeja', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- Revalida bajo lock el rol que pasó el precheck. Esto impide completar la
  -- devolución si Gerencia desactivó al supervisor mientras esperaba el lead.
  perform 1
  from crm.equipo actor_equipo
  join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
  where actor_equipo.perfil_id = v_actor
    and actor_equipo.rol_crm = 'supervisor'
    and actor_equipo.activo = true
    and actor_perfil.activo = true
  for no key update of actor_equipo, actor_perfil;
  if not found then
    raise exception 'Tu acceso de supervisor cambió; recarga antes de devolver'
      using errcode = '42501';
  end if;

  -- Mismo orden que el guardado masivo: lead → supervisor → asesor. La
  -- membresía y los perfiles quedan estables hasta terminar la devolución.
  select asesor_equipo.perfil_id
    into v_asesor_bloqueado
  from crm.equipo asesor_equipo
  join public.perfiles asesor_perfil on asesor_perfil.id = asesor_equipo.perfil_id
  where asesor_equipo.perfil_id = v_lead.vendedor_id
    and asesor_equipo.rol_crm = 'vendedor'
    and asesor_equipo.supervisor_id = v_actor
    and asesor_equipo.activo = true
    and asesor_perfil.activo = true
  for no key update of asesor_equipo, asesor_perfil;

  if not found then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  select la.*
    into v_episodio
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id
    and la.analista_id = v_lead.vendedor_id
    and la.asignado_por = v_actor
    and la.supervisor_origen_id = v_actor
    and la.asignado_en >= v_inicio_hoy
    and la.asignado_en < v_fin_hoy
    and la.finalizado_en is null
  order by la.asignado_en desc
  limit 1
  for update of la;

  if not found
     or v_lead.activo is not true
     or v_lead.etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception 'Solo puedes devolver una derivación vigente de hoy hecha a un asesor de tu equipo'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from crm.actividades actividad
    where actividad.lead_id = p_lead_id
      and actividad.creado_por = v_episodio.analista_id
      and actividad.creado_en >= v_episodio.asignado_en
  ) or exists (
    select 1
    from crm.tareas tarea
    where tarea.lead_id = p_lead_id
      and tarea.creado_por = v_episodio.analista_id
      and tarea.creado_en >= v_episodio.asignado_en
  ) then
    raise exception 'No puedes devolver este lead porque el asesor ya registró gestión; su historial se conserva'
      using errcode = 'P0001';
  end if;

  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'on', true);
  update crm.leads
  set vendedor_id = null,
      asignado_supervisor_id = v_actor
  where id = p_lead_id;
  perform pg_catalog.set_config('crm.reversion_derivacion_equipo', 'off', true);

  return pg_catalog.jsonb_build_object(
    'version', 1,
    'lead_id', p_lead_id,
    'devuelto_a_bandeja', true
  );
end;
$function$
;

-- ============================================================================
-- 5. Toma de lead libre (precheck + 2 FOR UPDATE + 2 CAS)
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.tomar_lead_libre(p_telefono text, p_dni text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_tel text := private.normalizar_telefono(p_telefono);
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_lead crm.leads%rowtype;
  v_dias integer;
  v_disponible_desde timestamptz;
  v_quedo_libre_en timestamptz;
  v_ultima_conv timestamptz;
  v_propietario_anterior uuid;
  v_modo text;
  v_previo text;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- La toma directa es del VENDEDOR para sí mismo (spec §7). Supervisor y
  -- gerencia ya tienen su puerta con destino elegible: el reparto.
  if v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'La toma directa es solo para vendedores; supervisión asigna por el reparto';
  end if;

  if v_tel is null or v_tel !~ '^\+519[0-9]{8}$' then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object(
        'estado', 'error',
        'detalle', 'telefono_invalido'
      ));
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;

  -- Vetos de contacto ANTES de bloquear filas: baratos, y el veredicto que
  -- devuelven es el mismo que daría la verificación.
  if exists (
    select 1
    from crm.leads l
    where (l.no_contactar = true or private.persona_vetada(l.id))  -- F2.b (b2): veto de la persona
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      pg_catalog.jsonb_build_object('estado', 'no_contactar'));
  end if;

  if exists (
    select 1
    from public.perfiles per
    where per.rol = 'cliente'
      and per.activo = true
      and (
        private.normalizar_telefono(per.telefono) = v_tel
        or (v_dni is not null and per.dni = v_dni)
      )
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- El blanco, POR CONTACTO y el TELÉFONO manda (adenda 16/08-b del ledger):
  -- solo si el número no casa con nada se cae al DNI. FILA primero — el orden
  -- advisory→fila se abraza con «Deshacer descarte» (refutador del plan); las
  -- llaves advisory las toman los triggers del propio UPDATE, en el orden de
  -- los caminos vivos. ORDER BY determinista: la bolsa viva antes que los
  -- descartes, el descarte más reciente primero, id como desempate.
  select l.* into v_lead
  from crm.leads l
  where l.telefono = v_tel
    -- Codex R4: el veto DENTRO del predicado — EvalPlanQual lo re-evalúa
    -- sobre la versión nueva tras esperar la fila; el pre-chequeo solo no
    -- veía un no_contactar en vuelo.
    and l.no_contactar = false
    and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
    and (
      (l.activo = true
        and l.etapa not in ('convertido', 'descartado')
        and l.vendedor_id is null
        and l.asignado_supervisor_id is null)
      -- Espejo del impl: un descarte sin fecha es anomalía y no se toma.
      or (l.etapa = 'descartado' and l.descartado_en is not null)
    )
  order by (l.etapa = 'descartado'), l.descartado_en desc, l.id
  limit 1
  for update;

  if not found and v_dni is not null then
    select l.* into v_lead
    from crm.leads l
    where l.dni = v_dni
      and l.no_contactar = false
      and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
      and (
        (l.activo = true
          and l.etapa not in ('convertido', 'descartado')
          and l.vendedor_id is null
          and l.asignado_supervisor_id is null)
        -- Espejo EXACTO del brazo telefónico (auditor M1): sin este filtro un
        -- descarte-anomalía sin fecha entraba por el DNI saltándose
        -- enfriamiento y carencia.
        or (l.etapa = 'descartado' and l.descartado_en is not null)
      )
    order by (l.etapa = 'descartado'), l.descartado_en desc nulls last, l.id
    limit 1
    for update;
  end if;

  if not found then
    -- Nada tomable con ese contacto: el veredicto fresco explica qué pasa
    -- (tomado por otro, libre → alta nueva, etc.).
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- P-048: el permiso se re-consulta DESPUÉS del lock — una membresía
  -- revocada mientras esperaba la fila no alcanza a tomar al despertar. El
  -- FOR SHARE ancla la fila de equipo (Codex, carrera de offboarding): la
  -- desactivación la toma FOR UPDATE, así que o ella terminó (y aquí se ve
  -- inactivo) o espera a que esta toma termine (y su chequeo de dependencias
  -- verá el lead nuevo). Sin ciclo: la desactivación no bloquea crm.leads.
  perform 1
  from crm.equipo e
  where e.perfil_id = v_actor
  for share;
  if private.rol_crm(v_actor) is distinct from 'vendedor'
     or not private.es_destino_crm_activo(v_actor, array['vendedor']::text[]) then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  -- Si OTRO lead vivo del mismo contacto tiene DUEÑO, el contacto está tomado
  -- aunque nuestro blanco sea un descarte viejo: manda el veredicto fresco.
  -- El filtro de dueño es deliberado: una bolsa viva que casa solo por el OTRO
  -- dato no estorba (el teléfono manda) — sin él, el veredicto diría «en
  -- bolsa» y la toma rebotaría en bucle contra su propio blanco telefónico.
  if exists (
    select 1
    from crm.leads l
    where l.id <> v_lead.id
      and l.activo = true
      and l.etapa not in ('convertido', 'descartado')
      and (l.vendedor_id is not null or l.asignado_supervisor_id is not null)
      and (l.telefono = v_tel or (v_dni is not null and l.dni = v_dni))
  ) then
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  v_propietario_anterior := coalesce(v_lead.vendedor_id, v_lead.asignado_supervisor_id);
  v_ultima_conv := (
    select pg_catalog.max(a.creado_en)
    from crm.actividades a
    where a.lead_id = v_lead.id
      and a.tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada')
  );

  if v_lead.activo = true
     and v_lead.etapa not in ('convertido', 'descartado')
     and v_lead.vendedor_id is null
     and v_lead.asignado_supervisor_id is null then
    v_modo := 'bolsa';
    v_quedo_libre_en := null;
  elsif v_lead.etapa = 'descartado' then
    if v_lead.activo = false then
      -- Un soft-borrado no se revive por esta puerta (regla del plan).
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    select ep.dias into v_dias
    from crm.enfriamiento_politica ep
    where ep.motivo = v_lead.motivo_descarte;
    v_dias := coalesce(v_dias, 0);
    v_disponible_desde := v_lead.descartado_en
      + pg_catalog.make_interval(days => v_dias);
    if v_dias > 0 and v_disponible_desde > pg_catalog.now() then
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    if v_dias = 0
       and v_lead.descartado_en + pg_catalog.make_interval(hours => 24) > pg_catalog.now() then
      -- Carencia de Miguel: un descarte de 0 días espera 24 h para TOMARSE.
      return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
    end if;
    v_modo := 'reutilizable';
    v_quedo_libre_en := case
      when v_dias > 0 then v_disponible_desde
      else v_lead.descartado_en + pg_catalog.make_interval(hours => 24)
    end;
  else
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- La válvula, SOLO alrededor del UPDATE, y quien la enciende la apaga.
  v_previo := coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off');
  perform pg_catalog.set_config('crm.toma_directa', 'on', true);

  if v_modo = 'bolsa' then
    update crm.leads l
       set vendedor_id = v_actor
     where l.id = v_lead.id
       and l.activo = true
       and l.no_contactar = false
       and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
       and l.etapa not in ('convertido', 'descartado')
       and l.vendedor_id is null
       and l.asignado_supervisor_id is null;
  else
    begin
      update crm.leads l
         set etapa = 'nuevo',
             vendedor_id = v_actor,
             asignado_supervisor_id = null,
             motivo_descarte = null
       where l.id = v_lead.id
         and l.activo = true
         and l.no_contactar = false
         and not private.persona_vetada(l.id)  -- F2.b (b2): snapshot de la sentencia (no EvalPlanQual); el enlazado lo cubre la propagación de marcar
         and l.etapa = 'descartado';
    exception
      when unique_violation then
        -- Los índices de dedup (solo vivos) cazaron un vivo del mismo
        -- contacto: nadie roba, se responde la verdad fresca. El DNI del
        -- BLANCO entra en la consulta a propósito: el choque pudo venir por
        -- un dato que el vendedor no tecleó, y sin él el veredicto repetiría
        -- 'reutilizable' e invitaría a un bucle de reintentos.
        perform pg_catalog.set_config('crm.toma_directa', v_previo, true);
        return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
          private.verificar_disponibilidad_lead_impl(v_tel, coalesce(v_dni, v_lead.dni)));
    end;
  end if;

  perform pg_catalog.set_config('crm.toma_directa', v_previo, true);

  if not found then
    -- CAS en 0 filas: el estado cambió entre el veredicto y la escritura.
    return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
      private.verificar_disponibilidad_lead_impl(v_tel, v_dni));
  end if;

  -- Traza §9 (además de la cascada, que ya asentó 'reasignacion' + ledger):
  -- la nota rica del evento, firmada por quien tomó.
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en)
  values (
    v_lead.id,
    'nota',
    case v_modo
      when 'bolsa' then 'Lead tomado desde la bolsa tras verificación de disponibilidad'
      else 'Lead tomado después de liberación por enfriamiento vencido'
    end,
    pg_catalog.jsonb_build_object(
      'evento', 'toma_directa',
      'modo', v_modo,
      'propietario_anterior', v_propietario_anterior,
      'ultima_conversacion', v_ultima_conv,
      'quedo_libre_en', v_quedo_libre_en,
      'motivo', case v_modo when 'bolsa' then 'toma_de_bolsa' else 'enfriamiento_vencido' end
    ),
    v_actor,
    pg_catalog.statement_timestamp()
  );

  -- La fila FINAL (los BEFORE ya subieron ciclo y renacieron tenencia).
  select l.* into v_lead from crm.leads l where l.id = v_lead.id;

  return private.toma_asienta_y_devuelve(v_actor, p_telefono, v_tel, v_dni,
    pg_catalog.jsonb_build_object(
      'estado', 'tomado_ok',
      'lead_id', v_lead.id,
      'modo', v_modo,
      'etapa', v_lead.etapa,
      'ciclo_actual', v_lead.ciclo_actual,
      'tenencia_desde', v_lead.tenencia_desde
    ));
end;
$function$
;

-- ============================================================================
-- 6. Deshacer descarte (implementación viva)
-- ============================================================================
CREATE OR REPLACE FUNCTION private.deshacer_descarte_implementacion(p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := (select auth.uid());
  v_ventana interval := interval '24 hours';
  v_lead    crm.leads%rowtype;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede deshacer un descarte'
      using errcode = '42501';
  end if;

  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa = 'descartado'
    and l.descartado_por = v_actor
    and l.descartado_en > (statement_timestamp() - v_ventana)
  for update;
  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
  -- F2.b (b2): gemela de rescatar_descartes: una persona vetada no se reabre.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
     where id = p_lead and activo = true and etapa = 'descartado'
       and vendedor_id is null and asignado_supervisor_id is null;
    if not found then
      raise exception 'El descarte ya no se puede deshacer (carrera)'
        using errcode = 'P0002';
    end if;
  exception
    when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir'
        using errcode = '22023';
  end;

  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'etapa', v_lead.etapa,
    'ciclo_actual', v_lead.ciclo_actual,
    'reabierto_por', v_actor,
    'reabierto_en', statement_timestamp());
end;
$function$
;

-- ============================================================================
-- 7. Resumen de reparto (mismo criterio que la cola)
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.resumen_reparto_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_ahora timestamptz := now();
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver el resumen de reparto'
      using errcode = '42501';
  end if;

  with cola as materialized (
    select l.origen, l.moneda, coalesce(l.monto_estimado, 0) as monto,
           l.creado_en, l.clasificacion_auto
    from crm.leads l
    where l.activo = true
      and l.vendedor_id is null
      and l.asignado_supervisor_id is null
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and l.no_contactar = false
      and not private.persona_vetada(l.id)  -- F2.b (b2): mismo criterio que la cola (leads_por_repartir)
  ),
  por_origen as (
    select coalesce(
             jsonb_agg(jsonb_build_object('origen', x.origen, 'n', x.n)
                       order by x.n desc, x.origen),
             '[]'::jsonb) as j
    from (select c.origen, count(*)::int as n from cola c group by c.origen) x
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'cola', jsonb_build_object(
      'total', count(*),
      'capital', jsonb_build_object(
        'pen', coalesce(sum(c.monto) filter (where c.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(c.monto) filter (where c.moneda = 'USD'), 0)
      ),
      -- Días ENTEROS del lead más viejo (espejo de diasEnCola: floor, nunca
      -- negativo). 0 con cola vacía — el front pinta el vacío.
      'espera_max_dias', coalesce(
        (select greatest(floor(extract(epoch from (v_ahora - min(c2.creado_en))) / 86400.0), 0)::int
         from cola c2), 0),
      'posible_credito', count(*) filter (where c.clasificacion_auto = 'posible_credito'),
      'por_origen', (select j from por_origen)
    )
  )
  into v_payload
  from cola c;

  return v_payload;
end;
$function$
;

-- ============================================================================
-- 7b. Cola de reparto (implementación viva de 250000): también por documento exacto
-- ============================================================================
CREATE OR REPLACE FUNCTION private.leads_por_repartir_implementacion()
 RETURNS TABLE(id uuid, nombre_completo text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, creado_en timestamp with time zone, clasificacion_auto text, comentario text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    and not private.persona_vetada(l.id)                     -- F2.b (b2): también por documento exacto (lead suelto)
  order by l.creado_en asc;                                  -- FIFO justo
end;
$function$
;

-- ============================================================================
-- 8. Seguimiento: trigger de gestión (actividades y tareas humanas)
-- ============================================================================
CREATE OR REPLACE FUNCTION private.trg_gestion_lead_serializada()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_autorizado boolean := false;
begin
  -- Los writers internos (auth.uid NULL) y los eventos de sistema ya tienen
  -- sus propios gates. No deben quedar atrapados al dispararse desde un UPDATE
  -- del lead que ya posee el lock.
  if v_actor is null
     or (
       tg_table_name = 'actividades'
       and new.tipo in ('cambio_etapa', 'reasignacion', 'conversion')
     ) then
    return new;
  end if;

  -- `crm.tareas` también admite tareas de perfil sin lead; no participan en
  -- una devolución y conservan su policy existente.
  if new.lead_id is null then
    return new;
  end if;

  -- `creado_en` no es inmutable durante INSERT en las tablas heredadas. Un
  -- asesor podría enviar una fecha anterior a la asignación y hacer invisible
  -- su gestión para el candado de devolución. Los inserts manuales reciben un
  -- sello del servidor; writers internos con auth.uid NULL conservan backfill.
  -- Se preservan antes los contratos heredados de NOT NULL/fecha finita: el
  -- sello no debe convertir un payload imposible en una escritura válida.
  if new.creado_en is null then
    raise exception 'La fecha de creación de la gestión es obligatoria'
      using errcode = '23502';
  end if;
  if not pg_catalog.isfinite(new.creado_en) then
    raise exception 'La fecha de creación de la gestión debe ser finita'
      using errcode = '23514';
  end if;

  if new.creado_por is distinct from v_actor then
    raise exception 'La gestión debe quedar atribuida al usuario autenticado'
      using errcode = '42501';
  end if;

  v_rol := private.rol_crm(v_actor);
  select true
    into v_autorizado
  from crm.leads lead
  where lead.id = new.lead_id
    and lead.activo = true
    and (
      v_rol = 'gerencia'
      or lead.vendedor_id = v_actor
      or (
        v_rol = 'supervisor'
        and (
          lead.vendedor_id in (
            select private.vendedor_ids_visibles(v_actor)
          )
          or (
            lead.vendedor_id is null
            and lead.asignado_supervisor_id in (
              select private.vendedor_ids_visibles(v_actor)
            )
          )
        )
      )
    )
  for update;

  if v_autorizado is distinct from true then
    raise exception 'El lead cambió de responsable; recarga antes de registrar la gestión'
      using errcode = '42501';
  end if;
  -- F2.b (b2): el veto de la PERSONA bloquea el SEGUIMIENTO (contrato §7.3): los tipos
  -- de CONTACTO y las tareas. Las notas administrativas (corrección/anulación de un
  -- cierre, fusión, reingreso) no son contacto y siguen entrando; la nota de las RPC
  -- de veto entra además bajo la válvula op_privilegiada.
  if not coalesce(pg_catalog.current_setting('crm.op_privilegiada', true) = 'on', false)
     and (tg_table_name = 'tareas'
          or new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
     and private.persona_vetada(new.lead_id) then
    raise exception '%: no se registra seguimiento', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;

  -- El sello se toma DESPUÉS del lock y de la revalidación. `statement_timestamp`
  -- conservaría la hora previa a una espera: si una derivación ganara durante
  -- esa espera, la gestión podría quedar fechada antes del episodio y el
  -- supervisor aún la vería como reversible. `clock_timestamp` registra el
  -- orden causal ya serializado por el lock.
  new.creado_en := pg_catalog.clock_timestamp();

  return new;
end;
$function$
;

-- ============================================================================
-- 9. Marcar no_contactar: nota bajo válvula + tareas pendientes canceladas
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.marcar_no_contactar(p_lead_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;

  -- F2.b (b2) [Codex E1 #2]: orden identidad -> TAREAS -> leads. crm.cerrar_tarea va
  -- tarea -> lead; cancelar las pendientes después de bloquear los leads formaría un ciclo.
  if v_flag then
    perform 1 from crm.tareas t
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv))
     order by t.id
     for update;
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
  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se marcaba; vuelve a intentarlo'
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
    -- F2.b (b2): el propio lead suelto también hereda el veto.
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  -- F2.b (b2): con la bandera encendida se cancelan las tareas PENDIENTES de todos
  -- los leads de la persona (selladas como sistema). Levantar el veto NO las revive.
  if v_flag then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv));
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  -- La nota se inserta BAJO la válvula: el trigger de gestión exime la válvula del veto (F2.b b2).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$
;

-- ============================================================================
-- 10. Levantar no_contactar: también por documento (lead suelto)
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
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
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se levantaba; vuelve a intentarlo'
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
    -- F2.b (b2): el propio lead suelto también.
    update crm.leads set no_contactar = false where id = p_lead_id and no_contactar = true;
    if found then v_n := v_n + 1; end if;
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
$function$
;

-- ============================================================================
-- 11. Rescate de descartes: veto de la persona también por documento
-- ============================================================================
CREATE OR REPLACE FUNCTION crm.rescatar_descartes(p_episodios uuid[], p_analistas_destino uuid[], p_evitar_asesor_origen boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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

  v_total_destinos := coalesce(pg_catalog.array_length(v_destinos_validos, 1), 0);  -- F2.b (b2): pg_catalog.coalesce no existe (bug desde 20/08)
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
    -- F2.b (b2): también por documento exacto (lead suelto de una persona vetada).
    if private.persona_vetada(v_fila.lead_id) then
      raise exception 'Uno de los leads pertenece a una persona con la restricción «No insistir» y no puede reactivarse'
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
$function$
;

-- ============================================================================
-- 11. Postflight
-- ============================================================================
do $post$
declare v_fn text; v_src text;
begin
  if to_regprocedure('private.persona_vetada(uuid)') is null
     or to_regprocedure('private.leads_vetados_persona(uuid[])') is null then
    raise exception 'POSTFLIGHT b2: faltan los helpers';
  end if;
  foreach v_fn in array array['private.repartir_lead_implementacion','crm.derivar_leads_equipo_fn','crm.revertir_derivacion_equipo_fn',
                              'crm.tomar_lead_libre','private.deshacer_descarte_implementacion','crm.resumen_reparto_fn',
                              'private.leads_por_repartir_implementacion','private.trg_gestion_lead_serializada'] loop
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname || '.' || p.proname = v_fn;
    if v_src is null or strpos(v_src, 'persona_vetada') = 0 then
      raise exception 'POSTFLIGHT b2: % no consulta persona_vetada', v_fn;
    end if;
  end loop;
  if (select strpos(prosrc, 'crm.cancela_sistema') from pg_proc where proname='marcar_no_contactar') = 0 then
    raise exception 'POSTFLIGHT b2: marcar_no_contactar no cancela tareas';
  end if;
  if (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc where proname='levantar_no_contactar') = 0
     or (select strpos(prosrc, 'identidad_bloquear_documento') from pg_proc where proname='marcar_no_contactar') = 0 then
    raise exception 'POSTFLIGHT b2: marcar/levantar no resuelven la persona por documento';
  end if;
  if (select strpos(prosrc, 'persona_vetada') from pg_proc where proname='rescatar_descartes') = 0 then
    raise exception 'POSTFLIGHT b2: rescatar_descartes no consulta persona_vetada';
  end if;
  if (select count(*) from regexp_matches((select prosrc from pg_proc where proname='tomar_lead_libre'), 'persona_vetada', 'g')) <> 5 then
    raise exception 'POSTFLIGHT b2: tomar_lead_libre debe consultar persona_vetada 5 veces';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
             where p.oid in ('private.persona_vetada(uuid)'::regprocedure, 'private.leads_vetados_persona(uuid[])'::regprocedure,
                             'private.repartir_lead_implementacion(uuid,uuid)'::regprocedure, 'private.deshacer_descarte_implementacion(uuid)'::regprocedure,
                             'private.leads_por_repartir_implementacion()'::regprocedure, 'private.trg_gestion_lead_serializada()'::regprocedure)
               and (a.grantee = 0 or a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)))
     or has_function_privilege('authenticated', 'private.persona_vetada(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.tomar_lead_libre(text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.tomar_lead_libre(text,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.derivar_leads_equipo_fn(uuid[],uuid[])', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.revertir_derivacion_equipo_fn(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.resumen_reparto_fn()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.marcar_no_contactar(uuid,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.levantar_no_contactar(uuid,text)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.rescatar_descartes(uuid[],uuid[],boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.repartir_lead_implementacion(uuid,uuid)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.deshacer_descarte_implementacion(uuid)', 'EXECUTE') then
    raise exception 'POSTFLIGHT b2: grants incorrectos (CREATE OR REPLACE conserva la ACL; verificar)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT b2: la bandera quedó encendida';
  end if;
  raise notice 'F2.b b2 OK: el veto de la persona bloquea reparto, derivación, reversión, toma, reapertura y seguimiento; marcar cancela tareas; marcar/levantar por persona en leads sueltos. Bandera APAGADA.';
end
$post$;

commit;
$m$])
on conflict (version) do nothing;

do $post$
begin
  if (select count(*) from supabase_migrations.schema_migrations where version in ('20260904120000','20260904130000')) <> 2 then
    raise exception 'REGISTRO F2.b E1: faltan versiones';
  end if;
  if to_regprocedure('private.persona_vetada(uuid)') is null or to_regprocedure('private.trg_leads_zz_enlaza_identidad()') is null then
    raise exception 'REGISTRO F2.b E1: se registra sin haber aplicado (faltan objetos)';
  end if;
end
$post$;
commit;

select version, name from supabase_migrations.schema_migrations where version in ('20260904120000','20260904130000') order by version;
