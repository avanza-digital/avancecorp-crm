-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b sub-lote b1 — EL ALTA RECONOCE A LA PERSONA
-- ============================================================================
--
-- QUE (invariantes #6, #7, #8 del contrato F0): con la bandera resolver_en_puertas
-- ENCENDIDA, todo INSERT en crm.leads y todo cambio de dni pasan por el documento
-- exacto (identificador VIGENTE y VERIFICADO de una identidad no fusionada):
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
--   * trg_leads_000_hereda_veto  (BEFORE INSERT OR UPDATE OF dni): documento -> identidad
--     FOR UPDATE -> P0429 si vetada (ya NO copia el veto: la alta de una persona vetada
--     se rechaza, contrato §7.3).
--   * trg_leads_00_disponibilidad_* (sin cambios): toma contactos DESPUÉS (orden por nombre).
--   * trg_leads_zz_enlaza_identidad (BEFORE INSERT OR UPDATE OF dni): corre DESPUÉS de
--     trg_leads_protege_inversionista_id (orden alfabético, determinista) y por eso no
--     necesita válvula: fija new.inversionista_id o levanta P0481/P0409.
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
  if tg_op = 'UPDATE' and new.dni is not distinct from old.dni then
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
  before insert or update of dni on crm.leads
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
    if new.dni is not distinct from old.dni then
      return new;
    end if;
    -- El documento de una persona ENLAZADA solo cambia por la corrección de
    -- Gerencia (bajo válvula). PostgREST y service_role no pueden desalinearlo.
    if old.inversionista_id is not null and not v_priv then
      raise exception 'El documento de un lead enlazado a una persona solo se corrige por Gerencia (corrección de documento)'
        using errcode = 'P0409';
    end if;
    if v_priv then
      return new;
    end if;
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
  if v_def is null or v_def not like '%BEFORE INSERT OR UPDATE OF dni ON crm.leads%' then
    raise exception 'POSTFLIGHT b1: trg_leads_000_hereda_veto no es BEFORE INSERT OR UPDATE OF dni (%)', v_def;
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
