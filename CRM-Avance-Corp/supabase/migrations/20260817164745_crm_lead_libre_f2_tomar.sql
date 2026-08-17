-- F2 del plan «Verificación y toma de lead libre» (nota del vault; spec §5.6,
-- §5.7, §9): la TOMA DIRECTA. Tres piezas:
--   1. El impl de disponibilidad parte el 'libre' genérico: un descartado con
--      enfriamiento VENCIDO pasa a ser 'reutilizable' (el alta ya lo bloquea
--      desde F1 — dejarlo en 'libre' duplicaba el contacto, §5.6). Dos
--      excepciones deliberadas: activo=false jamás es reutilizable (cae a
--      'libre' → alta nueva), y los motivos con 0 días de enfriamiento
--      (pide_credito, datos_invalidos) guardan una CARENCIA de 24 h SOLO para
--      tomar — decisión de Miguel 2026-08-16: protege el «Deshacer descarte
--      24h» del coordinador; durante la ventana el veredicto sigue siendo
--      'libre' y el alta manual no cambia.
--   2. crm.tomar_lead_libre(p_telefono, p_dni) — POR CONTACTO, jamás lead_id
--      (mata el TOCTOU y no filtra UUIDs). Protocolo gemelo del alta P-048 con
--      el ORDEN de candados de los caminos vivos: FILA (select … for update)
--      primero y advisory después — los toman los triggers del propio UPDATE;
--      invertirlo se abraza con «Deshacer descarte» (refutador del plan).
--      Bolsa: CAS «sin dueño y viva». Reutilizable: CAS «descartado y activo»
--      con etapa→'nuevo' y vendedor en el MISMO update (trg_leads_00_guard_
--      tenencia sube ciclo_actual solo; trg_leads_zzz_tenencia_desde hace
--      renacer la tenencia sola). 0 filas o carrera → veredicto FRESCO del
--      impl (el front lo presenta como «lo acaba de tomar otro», §5.7).
--   3. La válvula crm.toma_directa en trg_leads_bloquear_reasignacion: el veto
--      «un vendedor no puede reasignar» gana UNA excepción angosta — flag de
--      transacción encendido Y new.vendedor_id = auth.uid(). Cualquier otra
--      reasignación de un vendedor sigue vetada, con o sin flag. Patrón ya
--      pagado por crm.op_privilegiada y crm.cancela_sistema.
--
-- La toma es del VENDEDOR para sí mismo (spec §7: «acciones del vendedor
-- interesado»); supervisor y gerencia tienen su puerta propia (el reparto).
-- La cascada existente asienta sola: actividad 'reasignacion' clasificada
-- (trg_leads_reasignacion), episodio del ledger (trg_leads_asignaciones),
-- cambio de etapa auditado, tenencia y ciclo. La RPC añade la traza §9 como
-- actividad 'nota' con metadata rica (propietario anterior, última
-- conversación real, cuándo quedó libre, motivo).
--
-- Residuo conocido y DICHO (atribución corregida por Codex): el INSERT
-- HUMANO legacy queda CERRADO gratis — su trigger exige veredicto 'libre' y
-- 'reutilizable' ya no lo es. El bypass real es el escritor SIN sesión
-- (service-role: crm-importar-leads hace INSERT directo y el trigger lo deja
-- pasar por diseño) — un import sobre un descartado-vencido aún duplicaría el
-- contacto, igual que hoy; el puente conserva su propia semántica de dedup.
--
-- ⚠️ ORDEN DE DEPLOY: SERVIDOR primero. La clave nueva en la RESPUESTA del
-- verificar ('reutilizable') ya la tolera el front vivo desde el 28.º release
-- (variante looseObject puesta a propósito en F1), y la RPC nueva no tiene
-- consumidor hasta el release F2 del front. Las dos direcciones quedan en paz.

-- ── 0. Guardas de fidelidad ──────────────────────────────────────────────────
-- Esta migración re-crea dos cuerpos COPIANDO su texto vigente + el cambio.
-- Si producción ya no es lo que se copió, se detiene ANTES de pisar nada.
do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'verificar_disponibilidad_lead_impl'
    and pg_get_function_identity_arguments(p.oid) = 'p_telefono text, p_dni text, p_excluir_lead_id uuid';
  if v_md5 is distinct from '0ace18e3b451c362e845e9c947010ca6' then
    raise exception 'impl canónico distinto del anclado (md5 %): re-anclar la migración antes de aplicar', coalesce(v_md5, 'AUSENTE');
  end if;

  select md5(p.prosrc) into v_md5
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private'
    and p.proname = 'trg_leads_bloquear_reasignacion';
  if v_md5 is distinct from '1ba780d9d3b7f4b846292237f0d78de9' then
    raise exception 'trg_leads_bloquear_reasignacion distinto del anclado (md5 %): re-anclar antes de aplicar', coalesce(v_md5, 'AUSENTE');
  end if;

  -- Dependencias cuya SEMÁNTICA se reutiliza sin copiarlas: deben existir.
  if to_regclass('crm.politica_abandono') is null
     or to_regclass('crm.verificaciones_lead') is null
     or to_regclass('crm.enfriamiento_politica') is null
     or to_regclass('crm.actividades') is null
     or to_regprocedure('private.es_destino_crm_activo(uuid, text[])') is null
     or to_regprocedure('private.verificar_disponibilidad_lead_impl(text, text)') is null then
    raise exception 'Faltan dependencias de F1/P-048: aplicar primero las migraciones previas';
  end if;

  -- La toma reviviente confía en que el UPDATE de etapa toma las llaves
  -- advisory vía trg_leads_00_disponibilidad_update: si alguien recorta sus
  -- columnas OF, este supuesto muere en silencio. Se verifica AQUÍ.
  if not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'crm' and c.relname = 'leads'
      and t.tgname = 'trg_leads_00_disponibilidad_update'
      and pg_get_triggerdef(t.oid) like '%etapa%'
  ) then
    raise exception 'trg_leads_00_disponibilidad_update ya no cubre etapa: la toma reviviente perdería sus llaves advisory';
  end if;
end $$;

-- ── 1. El impl parte 'libre' en 'libre' / 'reutilizable' ─────────────────────
-- Cuerpo VIGENTE copiado tal cual (guarda md5 arriba) + DOS cambios en la rama
-- del descartado: se seleccionan l.id y l.activo, y el descarte VENCIDO deja
-- de caer al 'libre' genérico. Todo lo demás, byte a byte igual.
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
    where l.id is distinct from p_excluir_lead_id
      and l.no_contactar = true
      and (l.telefono = v_tel or (p_dni is not null and l.dni = p_dni))
  ) then
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

comment on function private.verificar_disponibilidad_lead_impl(text, text, uuid) is
  'P-047 impl canónico. Desde F1 lead libre: tomado incluye ultima_conversacion_en (conversaciones reales; los intentos no cuentan). Desde F2: el descarte con enfriamiento vencido es reutilizable (§5.6) — activo=false cae a libre, y los motivos de 0 días guardan carencia de 24 h solo para tomar. p_excluir_lead_id permite al alta atómica no detectarse a sí misma.';

revoke all on function private.verificar_disponibilidad_lead_impl(text, text, uuid)
  from public, anon, authenticated, service_role;

-- ── 2. La válvula de la toma directa ─────────────────────────────────────────
-- Cuerpo vigente (guarda md5 arriba) + la excepción ANGOSTA: flag de
-- transacción crm.toma_directa encendido Y el destino es el propio actor.
-- La enciende SOLO crm.tomar_lead_libre, alrededor de su UPDATE, y quien la
-- enciende la apaga (patrón crm.cancela_sistema / crm.op_privilegiada).
create or replace function private.trg_leads_bloquear_reasignacion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.vendedor_id is distinct from old.vendedor_id
     and private.rol_crm((select auth.uid())) = 'vendedor'
     and not (
       coalesce(pg_catalog.current_setting('crm.toma_directa', true), 'off') = 'on'
       and new.vendedor_id = (select auth.uid())
     ) then
    raise exception 'Un vendedor no puede reasignar leads';
  end if;
  return new;
end;
$$;

revoke all on function private.trg_leads_bloquear_reasignacion()
  from public, anon, authenticated, service_role;

-- ── 3. crm.tomar_lead_libre — la toma directa, atómica y por contacto ────────

-- El asiento anti-pesca de la TOMA (auditor A1 de esta migración): sin él,
-- quien pesque identidades usaría exactamente el endpoint sin log y el control
-- de F1 quedaría vivo solo para los honestos. TODA llamada a la RPC de tomar
-- deja fila — también la exitosa y el teléfono inválido — con el mismo recorte
-- que el wrapper F1. Devuelve el veredicto tal cual para poder envolver cada
-- return sin duplicar lógica.
create function private.toma_asienta_y_devuelve(
  p_actor uuid,
  p_telefono_tecleado text,
  p_telefono_norm text,
  p_dni text,
  p_veredicto jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  insert into crm.verificaciones_lead (verificado_por, telefono_consultado, dni_consultado, veredicto)
  values (
    p_actor,
    pg_catalog.left(coalesce(p_telefono_norm, p_telefono_tecleado, ''), 32),
    pg_catalog.left(p_dni, 16),
    p_veredicto ->> 'estado'
  );
  return p_veredicto;
end;
$$;

comment on function private.toma_asienta_y_devuelve(uuid, text, text, text, jsonb) is
  'Asiento anti-pesca de crm.tomar_lead_libre: toda llamada deja rastro (quién, qué identidad, veredicto — tomado_ok incluido). Interno: solo lo llama la RPC de tomar.';

revoke all on function private.toma_asienta_y_devuelve(uuid, text, text, text, jsonb)
  from public, anon, authenticated, service_role;

-- El comment de F1 decía «lo escribe SOLO la RPC» en singular: ya son dos.
comment on table crm.verificaciones_lead is
  'Registro anti-pesca de la verificación por contacto (F1) y de la TOMA directa (F2): cada llamada a crm.verificar_disponibilidad_lead o a crm.tomar_lead_libre deja quién consultó qué identidad y el veredicto (en la toma, también tomado_ok). Lo escriben SOLO esas RPCs (security definer); por policy lo lee gerencia — y, como TODA tabla crm.* auditada, su rastro en public.audit_log es legible por admin/superadmin del portal (vía preexistente; la bandeja del portal filtra tabla IN (perfiles, contratos) y NO lo muestra — verificado en prod 2026-08-16, md5 bandeja_actividad ff1bd19f…). Los prechecks internos del alta atómica llaman al impl directo y no dejan fila.';

create function crm.tomar_lead_libre(
  p_telefono text,
  p_dni text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
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
    where l.no_contactar = true
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
$$;

comment on function crm.tomar_lead_libre(text, text) is
  'F2 lead libre (spec §5.6/§5.7/§9): toma directa POR CONTACTO — el teléfono manda, el DNI solo entra sin coincidencia telefónica. Fila for update + CAS + re-verificación dentro; las llaves advisory las toman los triggers del UPDATE (orden de los caminos vivos). Bolsa: asigna al actor. Descartado con enfriamiento vencido: revive en nuevo (ciclo+1, tenencia renace) respetando la carencia de 24 h de los motivos de 0 días. Perdedor de la carrera: veredicto fresco, jamás robo. Solo vendedores, para sí mismos.';

revoke all on function crm.tomar_lead_libre(text, text)
  from public, anon, service_role;
grant execute on function crm.tomar_lead_libre(text, text) to authenticated;
