-- 20261002231436_crm_base_gestion_puertas.sql
--
-- Base para gestión del analista · B3 (puertas y núcleos). Plan B3 confirmado por Miguel el 02/10/2026 («siii»).
-- Decisiones: D1 (reactivar → `contactado` en la misma operación), D2 (mismo dueño), D3 (Reactivar explícito; «agendó
-- cita» reactiva sola), D4/D12 (3 intentos sin cita ni rellamada → enfriamiento: lo pone el trigger de B4), D6 (etapa
-- máxima deducida del historial), D7-bis/D11 (rellamada en el lead, máximo 10 días), D9 (`reactivado_en` + actividad),
-- D10 (puerta y núcleo propios; no se toca `registrar_llamada_v4`). Vault: «Base para gestion del analista - F0 y
-- decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- QUÉ (capa 3 → capa 2, sin tablas nuevas):
--   · `crm.obtener_base_gestion(p_vendedor_id uuid default null)` — LECTURA por rol: analista → sus leads; Supervisión →
--     su subárbol (y bandeja); Gerencia → toda la operación. Solo descartados vivos, sin «no contactar» y sin descanso
--     vigente. Por lead: intentos del ciclo (desde `descartado_en`), último resultado, próxima rellamada, etapa máxima
--     alcanzada en el ciclo (historial `cambio_etapa`), días desde el descarte, quién gestiona. Orden: rellamada vencida o
--     de hoy → etapa máxima (desc) → días desde el descarte (asc); sin fecha o sin etapa, al final sin error.
--   · `crm.registrar_intento_base(p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima_llamada)` → núcleo
--     `private.base_gestion_intento_core`: los 7 resultados de Gestión Diaria; «volver a llamar» exige fecha futura y a
--     lo sumo `dias_max_rellamada` días; los demás no llevan fecha. Escribe la actividad (`evento = intento_base`) bajo
--     los DOS GUC (`crm.op_resultado_llamada` por las claves reservadas y `crm.op_base_gestion` por el sello) y fija o
--     limpia `proxima_llamada_en`. «agendó cita» reactiva en la misma transacción. Idempotente: la actividad lleva
--     `id = p_operacion_id` y guarda su respuesta; un reintento devuelve lo mismo con `replay = true`.
--   · `crm.reactivar_lead_base(p_operacion_id, p_lead_id, p_nota)` → núcleo `private.base_gestion_reactivar_core`:
--     compone sobre `crm.reabrir_lead_fn` (sellada, se LLAMA, no se toca: reabre a `nuevo`, ciclo nuevo, SLA reiniciado)
--     y en la MISMA transacción avanza a `contactado` (el guard de tenencia lo permite: ya `old.etapa = nuevo`), sella
--     `reactivado_en`, limpia rellamada y descanso, y deja la línea en el historial. Idempotente igual.
--   · `crm.base_gestion_resumen()` — Supervisión y Gerencia: por analista, leads en base, rellamadas de hoy, intentos de
--     hoy y reactivaciones del mes (lo que pide F4).
--   · Ayudantes `private.base_gestion_rol`, `private.base_gestion_lead_visible` (espejo de `leads_select`, con `activo`
--     y `is not true` ante NULL), `private.base_gestion_etapa_rango` (INVOKER: solo los llaman funciones DEFINER).
--   · Sello de actividades `trg_00_actividades_base_gestion_solo_nucleo` (auditor-rls B3, P1): los eventos
--     `intento_base`/`reactivacion_base`, la clave `respuesta` y `via = base_gestion` solo se escriben bajo
--     `crm.op_base_gestion = on` (o sin usuario). Sin él, un analista forjaba por la API una «reactivación» que
--     inflaba el resumen de Supervisión o un replay falso de «agendó cita». Molde del sello de B1.
--   · Candados (auditor-rls B3, P2): cuando habrá reactivación, persona ANTES que lead (READ COMMITTED, candado
--     compartido de la bandera, `private.bloquear_personas_de_leads`), como `llamada_registrar`; `reabrir_lead_fn`
--     vuelve a tomar los mismos candados dentro de la transacción. La idempotencia se lee DESPUÉS del `for update`
--     del lead (dos clics concurrentes → el segundo espera y recibe replay) y solo entre operaciones del mismo actor.
--   · Resumen: `intentos_hoy` y `reactivaciones_mes` se atribuyen al DUEÑO del lead (un intento de Supervisión sobre
--     un lead del analista cuenta para el analista): la fila es del analista, no de quien marcó.
--   · 23505 «Esta operacion ya corresponde a otro contenido» comparte SQLSTATE con el índice de contacto vivo que
--     puede saltar al reabrir («agendó cita»): el front distingue por el texto.
--
-- SECURITY DEFINER, justificación: las puertas leen `crm.leads` y `crm.actividades` de todo un ámbito y escriben bajo
--   sellos que la RLS/los triggers cierran al cliente; el ámbito se verifica EXPLÍCITAMENTE con el mismo espejo de la
--   policy `leads_select` (`private.vendedor_ids_visibles`, que exige `auth.uid()`). `search_path` vacío, dueño postgres,
--   EXECUTE solo `authenticated` en las puertas; núcleos y ayudantes sin EXECUTE para la API.
--
-- QUÉ NO CAMBIA. Ninguna función sellada por huella se reemplaza (`reabrir_lead_fn`, `llamada_registrar`,
--   `trg_actividades_resultado_solo_nucleo`…). RLS y policies intactas. Fechas de negocio en America/Lima.
--   El enfriamiento (D4/D12) lo pone el trigger de B4; aquí solo se respeta (un lead en descanso no admite intentos).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-puertas.sql`: quita las 4 puertas, los 2 núcleos, los 3 ayudantes y el
--   sello de actividades.
--   No toca datos (los intentos y reactivaciones ya registrados quedan en el historial).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select count(*) from information_schema.columns where table_schema = 'crm' and table_name = 'leads'
       and column_name in ('reactivado_en', 'enfriado_hasta', 'proxima_llamada_en')) = 3
    and (select count(*) from pg_proc p, unnest(p.proargnames) n where p.oid = to_regprocedure('private.base_gestion_constantes()')) = 3
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.reabrir_lead_fn(uuid)') and p.prosecdef)
    and to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and to_regprocedure('private.rol_crm(uuid)') is not null
    and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)')) = '05df49be43869cd8e5f75330fa592a84'
    and exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated
                 and pg_get_constraintdef(oid) like '%proxima_llamada_en%')
    and to_regprocedure('crm.obtener_base_gestion(uuid)') is null
    and to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamptz)') is null
    and to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)') is null
    and to_regprocedure('crm.base_gestion_resumen()') is null
    and to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)') is null
    and to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)') is null
  ) is not true then
    raise exception 'PREFLIGHT: faltan B1/B1b/B2 tal como se auditaron, o alguna puerta de B3 ya existe';
  end if;
end;
$preflight$;

-- ── Ayudantes ─────────────────────────────────────────────────────────────────────────────────
create function private.base_gestion_etapa_rango(p_etapa text)
returns integer language sql immutable security invoker set search_path = '' as $$
  select case p_etapa when 'nuevo' then 1 when 'contactado' then 2 when 'reunion_agendada' then 3
                      when 'propuesta_enviada' then 4 when 'convertido' then 5 else 0 end;
$$;
alter function private.base_gestion_etapa_rango(text) owner to postgres;
revoke all on function private.base_gestion_etapa_rango(text) from public, anon, authenticated, service_role;
comment on function private.base_gestion_etapa_rango(text) is
  'Base para gestión (B3, D6): orden de las etapas del pipeline para calcular la etapa máxima alcanzada (0 = desconocida, va al final).';

create function private.base_gestion_rol(p_uid uuid)
returns text language plpgsql stable security invoker set search_path = '' as $$
declare v_rol text;
begin
  if p_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  v_rol := private.rol_crm(p_uid);
  if v_rol is null or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception 'La base para gestion es para analistas, Supervision y Gerencia' using errcode = '42501';
  end if;
  return v_rol;
end;
$$;
alter function private.base_gestion_rol(uuid) owner to postgres;
revoke all on function private.base_gestion_rol(uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_rol(uuid) is
  'Base para gestión (B3): rol del actor (vendedor | supervisor | gerencia) o 42501. NULL (baja, coordinación, directorio) rechaza.';

create function private.base_gestion_lead_visible(p_uid uuid, p_rol text, p_vendedor_id uuid, p_asignado_supervisor_id uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  -- Espejo de la policy leads_select (sin lector global). `is true`: un NULL nunca autoriza.
  select (p_rol = 'gerencia'
          or p_vendedor_id in (select private.vendedor_ids_visibles(p_uid))
          or (p_vendedor_id is null and p_asignado_supervisor_id in (select private.vendedor_ids_visibles(p_uid)))) is true;
$$;
alter function private.base_gestion_lead_visible(uuid, text, uuid, uuid) owner to postgres;
revoke all on function private.base_gestion_lead_visible(uuid, text, uuid, uuid) from public, anon, authenticated, service_role;
comment on function private.base_gestion_lead_visible(uuid, text, uuid, uuid) is
  'Base para gestión (B3): ámbito del actor sobre un lead, espejo de leads_select (vendedor → el suyo; Supervisión → subárbol y bandeja; Gerencia → todo). NULL = false.';

-- ── Sello de actividades de la base (P1 del auditor-rls B3) ───────────────────────────────────
create function private.trg_actividades_base_gestion_solo_nucleo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_meta jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  if (select auth.uid()) is null then
    return new;  -- migraciones y jobs internos, como el trigger «solo núcleo» del resultado de llamada
  end if;
  if coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off') = 'on' then
    return new;
  end if;
  if v_meta ? 'respuesta' or v_meta->>'evento' in ('intento_base', 'reactivacion_base') or v_meta->>'via' = 'base_gestion' then
    raise exception 'Las actividades de la base para gestion solo las escribe su nucleo' using errcode = '42501';
  end if;
  return new;
end;
$$;
alter function private.trg_actividades_base_gestion_solo_nucleo() owner to postgres;
revoke all on function private.trg_actividades_base_gestion_solo_nucleo() from public, anon, authenticated, service_role;
comment on function private.trg_actividades_base_gestion_solo_nucleo() is
  'Base para gestión (B3): reserva en crm.actividades los eventos intento_base y reactivacion_base, la clave respuesta y via = base_gestion para el núcleo (GUC de transacción crm.op_base_gestion = on) o sesiones sin usuario. Evita forjar reactivaciones (indicador del supervisor) o replays falsos desde la API. Mismo molde que trg_actividades_resultado_solo_nucleo.';
create trigger trg_00_actividades_base_gestion_solo_nucleo
  before insert or update of metadata on crm.actividades
  for each row execute function private.trg_actividades_base_gestion_solo_nucleo();

-- ── Lectura: la base ──────────────────────────────────────────────────────────────────────────
create function crm.obtener_base_gestion(p_vendedor_id uuid default null)
returns table (
  lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text,
  monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamptz, dias_desde_descarte integer,
  etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamptz,
  proxima_llamada_en timestamptz, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer,
  vendedor_id uuid, gestiona text)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_rol := private.base_gestion_rol(v_uid);
  if p_vendedor_id is not null then
    if v_rol = 'vendedor' and p_vendedor_id <> v_uid then
      raise exception 'Un analista solo consulta su propia base' using errcode = '42501';
    end if;
    if v_rol = 'supervisor' and p_vendedor_id not in (select private.vendedor_ids_visibles(v_uid)) then
      raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
    end if;
  end if;
  return query
  with base as (
    select l.id, l.nombre_completo, l.telefono, l.distrito, l.origen, l.categoria_interes, l.monto_estimado, l.moneda,
           l.motivo_descarte, l.descartado_en, l.proxima_llamada_en, l.enfriado_hasta, l.ciclo_actual, l.vendedor_id,
           coalesce(l.descartado_en, l.creado_en) as desde
    from crm.leads l
    where l.activo and l.etapa = 'descartado' and not l.no_contactar
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
  ),
  intentos as (
    select a.lead_id, count(*)::integer as n,
           (array_agg(a.metadata->>'resultado' order by a.creado_en desc, a.id desc))[1] as ultimo,
           max(a.creado_en) as ultimo_en
    from crm.actividades a join base b on b.id = a.lead_id
    where a.metadata->>'evento' = 'intento_base' and a.creado_en >= b.desde
    group by a.lead_id
  ),
  ciclo as (
    -- El ciclo vigente empieza en la ultima reapertura (cambio_etapa descartado → nuevo) o, si nunca hubo, al inicio.
    -- Se acota con el propio historial (misma fuente y mismo reloj que los cambios de etapa): robusto frente a
    -- transacciones multi-sentencia, donde now() del log y statement_timestamp() del ledger difieren.
    select b.id as lead_id,
           coalesce((select max(a.creado_en) from crm.actividades a
                      where a.lead_id = b.id and a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado'),
                    '-infinity'::timestamptz) as desde
    from base b
  ),
  etapas as (
    select a.lead_id,
           max(greatest(private.base_gestion_etapa_rango(a.metadata->>'etapa_anterior'),
                        private.base_gestion_etapa_rango(case when a.metadata->>'etapa_nueva' <> 'descartado' then a.metadata->>'etapa_nueva' end))) as rango
    from crm.actividades a join ciclo c on c.lead_id = a.lead_id
    where a.tipo = 'cambio_etapa' and a.creado_en >= c.desde
    group by a.lead_id
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  order by (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           b.proxima_llamada_en asc nulls last,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos días desde el descarte primero
           b.id;
end;
$$;
alter function crm.obtener_base_gestion(uuid) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid) to authenticated;
comment on function crm.obtener_base_gestion(uuid) is
  'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated.';

-- ── Núcleo: reactivar (D1, D2, D9) ────────────────────────────────────────────────────────────
create function private.base_gestion_reactivar_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_nota text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_guc text;
  v_resp jsonb;
  v_reabrir jsonb;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- Candados de la casa: persona ANTES que lead (como llamada_registrar y marcar_no_contactar); reabrir_lead_fn los
  -- vuelve a tomar dentro de la misma transaccion sin esperar.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'Reactivar requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead: dos clics concurrentes → el segundo espera y recibe el replay.
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'evento' is distinct from 'reactivacion_base' then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead ya no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  -- 1. Reabrir por la puerta sellada (→ nuevo, ciclo nuevo, SLA reiniciado, veto de persona verificado).
  v_reabrir := crm.reabrir_lead_fn(p_lead_id);
  -- 2. En la misma transaccion, a «contactado» (D1): el guard de tenencia lo permite porque ya old.etapa = nuevo.
  update crm.leads set etapa = 'contactado' where id = p_lead_id and activo and etapa = 'nuevo';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'No se pudo avanzar el lead reabierto a contactado' using errcode = 'P0001';
  end if;
  -- 3. Sello de la base: marca de reactivacion, sin rellamada ni descanso.
  v_guc := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.leads set reactivado_en = now(), proxima_llamada_en = null, enfriado_hasta = null where id = p_lead_id;
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  select * into v_lead from crm.leads where id = p_lead_id;
  v_resp := jsonb_build_object('ok', true, 'evento', 'reactivacion_base', 'lead_id', p_lead_id, 'etapa', v_lead.etapa,
                               'reactivado_en', v_lead.reactivado_en, 'ciclo_n', v_lead.ciclo_actual,
                               'reabierto_por', v_reabrir->>'reabierto_por', 'replay', false);
  -- 4. Historial (D9): la linea de la reactivacion, con la respuesta para la idempotencia, bajo el sello de actividades.
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, 'nota', coalesce(nullif(pg_catalog.btrim(p_nota), ''), 'Reactivado desde la base para gestión'),
          jsonb_build_object('evento', 'reactivacion_base', 'via', 'base_gestion', 'etapa', 'contactado',
                             'ciclo_n', v_lead.ciclo_actual, 'respuesta', v_resp),
          p_actor);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  return v_resp;
end;
$$;
alter function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) owner to postgres;
revoke all on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) from public, anon, authenticated, service_role;
comment on function private.base_gestion_reactivar_core(uuid, uuid, uuid, text) is
  'Base para gestión (B3, D1/D2/D9): reabre por crm.reabrir_lead_fn (sellada; → nuevo, ciclo nuevo, SLA reiniciado, veto verificado), avanza a contactado en la misma transacción, sella reactivado_en y limpia rellamada y descanso; deja la actividad reactivacion_base con la respuesta (idempotencia por id = operación). Solo la llama la puerta crm.reactivar_lead_base.';

-- ── Núcleo: registrar intento (D3, D4/D12, D7-bis, D10, D11) ─────────────────────────────────
create function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text, p_proxima timestamptz)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_rol text;
  v_c record;
  v_lead crm.leads%rowtype;
  v_prev jsonb;
  v_n integer;
  v_tipo text;
  v_guc1 text;
  v_guc2 text;
  v_meta jsonb;
  v_resp jsonb;
  v_react jsonb;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if p_actor is null or p_operacion_id is null or p_lead_id is null then
    raise exception 'Operacion, lead y actor son obligatorios' using errcode = '22023';
  end if;
  v_rol := private.base_gestion_rol(p_actor);
  if p_resultado is null or p_resultado not in ('no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                                                'numero_errado', 'no_es_la_persona', 'pide_otro_producto') then
    raise exception 'Resultado de llamada invalido' using errcode = '22023';
  end if;
  select * into v_c from private.base_gestion_constantes();
  if p_resultado = 'volver_a_llamar' then
    if p_proxima is null then
      raise exception 'Indica cuando volver a llamar' using errcode = '22023';
    end if;
    if p_proxima <= now() then
      raise exception 'La rellamada debe ser futura' using errcode = '22023';
    end if;
    if p_proxima > now() + make_interval(days => v_c.dias_max_rellamada) then
      raise exception 'La rellamada se agenda como maximo % dias adelante', v_c.dias_max_rellamada using errcode = '22023';
    end if;
  elsif p_proxima is not null then
    raise exception 'Solo "volver a llamar" lleva fecha de rellamada' using errcode = '22023';
  end if;
  if length(coalesce(p_nota, '')) > 2000 then
    raise exception 'La nota supera los 2000 caracteres' using errcode = '22023';
  end if;
  -- «agendó cita» reactivara: candados de persona ANTES del lead (protocolo de la casa).
  if p_resultado = 'agendo_reunion' then
    if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
      raise exception 'Agendar cita desde la base requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
    end if;
    perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
    perform private.bloquear_personas_de_leads(array[p_lead_id], null);
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  -- Idempotencia DESPUES del candado del lead y solo entre operaciones del mismo actor.
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'resultado' is distinct from p_resultado
       or v_prev->>'evento' is distinct from 'intento_base' then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  if v_lead.id is null or not v_lead.activo
     or not private.base_gestion_lead_visible(p_actor, v_rol, v_lead.vendedor_id, v_lead.asignado_supervisor_id) then
    raise exception 'Lead no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  if v_lead.etapa <> 'descartado' then
    raise exception 'El lead no esta en la base (no esta descartado)' using errcode = '22023';
  end if;
  if v_lead.no_contactar then
    raise exception 'No insistir: el lead esta marcado No contactar' using errcode = 'P0429';
  end if;
  if v_lead.enfriado_hasta is not null and v_lead.enfriado_hasta > v_hoy then
    raise exception 'El lead esta en descanso hasta el %', to_char(v_lead.enfriado_hasta, 'DD/MM/YYYY') using errcode = '22023';
  end if;
  select count(*)::integer + 1 into v_n from crm.actividades a
   where a.lead_id = p_lead_id and a.metadata->>'evento' = 'intento_base'
     and a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);
  v_tipo := case when p_resultado in ('no_contesto', 'numero_errado', 'no_es_la_persona')
                 then 'llamada_no_contestada' else 'llamada_realizada' end;
  v_meta := jsonb_strip_nulls(jsonb_build_object(
    'evento', 'intento_base', 'via', 'base_gestion', 'resultado', p_resultado, 'intento_n', v_n,
    'ciclo_n', v_lead.ciclo_actual, 'proxima_llamada_en', p_proxima));  -- to_jsonb(timestamptz): ISO con zona, nunca ::text
  v_guc1 := coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off');
  v_guc2 := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  insert into crm.actividades (id, lead_id, tipo, detalle, metadata, creado_por)
  values (p_operacion_id, p_lead_id, v_tipo, nullif(pg_catalog.btrim(p_nota), ''), v_meta, p_actor);
  update crm.leads set proxima_llamada_en = case when p_resultado = 'volver_a_llamar' then p_proxima else null end
   where id = p_lead_id
     and proxima_llamada_en is distinct from case when p_resultado = 'volver_a_llamar' then p_proxima else null end;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  -- «agendó cita» reactiva en la misma transaccion (D3); la cita se agenda despues por el flujo normal del lead vivo.
  if p_resultado = 'agendo_reunion' then
    v_react := private.base_gestion_reactivar_core(p_actor, md5(p_operacion_id::text || ':reactivar')::uuid, p_lead_id,
                                                   'Agendó cita desde la base para gestión');
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;  -- tras el trigger de enfriamiento (B4) y la reactivacion
  v_resp := jsonb_build_object('ok', true, 'evento', 'intento_base', 'lead_id', p_lead_id, 'actividad_id', p_operacion_id,
                               'resultado', p_resultado, 'intento_n', v_n, 'ciclo_n', v_meta->>'ciclo_n',
                               'proxima_llamada_en', v_lead.proxima_llamada_en, 'enfriado_hasta', v_lead.enfriado_hasta,
                               'reactivado', v_react is not null, 'etapa', v_lead.etapa, 'replay', false);
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('respuesta', v_resp) where id = p_operacion_id;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  return v_resp;
end;
$$;
alter function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) owner to postgres;
revoke all on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) from public, anon, authenticated, service_role;
comment on function private.base_gestion_intento_core(uuid, uuid, uuid, text, text, timestamptz) is
  'Base para gestión (B3, D3/D7-bis/D10/D11): registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción. Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Solo la llama la puerta crm.registrar_intento_base.';

-- ── Puertas de escritura ──────────────────────────────────────────────────────────────────────
create function crm.registrar_intento_base(p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text default null, p_proxima_llamada timestamptz default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_intento_core(v_uid, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima_llamada);
end;
$$;
alter function crm.registrar_intento_base(uuid, uuid, text, text, timestamptz) owner to postgres;
revoke all on function crm.registrar_intento_base(uuid, uuid, text, text, timestamptz) from public, anon, authenticated, service_role;
grant execute on function crm.registrar_intento_base(uuid, uuid, text, text, timestamptz) to authenticated;
comment on function crm.registrar_intento_base(uuid, uuid, text, text, timestamptz) is
  'PUERTA (B3): registra un intento de la base para gestión. Actor = auth.uid(); rol y ámbito se resuelven en el servidor. p_operacion_id es la clave de idempotencia (el doble clic devuelve la misma respuesta con replay = true). volver_a_llamar exige p_proxima_llamada (futura, ≤ 10 días). DEFINER para componer el núcleo privado, no para ampliar el ámbito.';

create function crm.reactivar_lead_base(p_operacion_id uuid, p_lead_id uuid, p_nota text default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then raise exception 'No autorizado' using errcode = '42501'; end if;
  return private.base_gestion_reactivar_core(v_uid, p_operacion_id, p_lead_id, p_nota);
end;
$$;
alter function crm.reactivar_lead_base(uuid, uuid, text) owner to postgres;
revoke all on function crm.reactivar_lead_base(uuid, uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.reactivar_lead_base(uuid, uuid, text) to authenticated;
comment on function crm.reactivar_lead_base(uuid, uuid, text) is
  'PUERTA (B3, D1/D2/D9): reactiva un lead descartado de la base al pipeline en contactado, mismo dueño, con reactivado_en y la línea en el historial. Idempotente por p_operacion_id. DEFINER para componer crm.reabrir_lead_fn y el núcleo privado, no para ampliar el ámbito.';

-- ── Lectura: resumen para Supervisión y Gerencia (F4) ─────────────────────────────────────────
create function crm.base_gestion_resumen()
returns table (vendedor_id uuid, nombre text, en_base integer, rellamadas_hoy integer, intentos_hoy integer, reactivaciones_mes integer)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  v_rol := private.base_gestion_rol(v_uid);
  if v_rol <> 'supervisor' and v_rol <> 'gerencia' then
    raise exception 'Solo Supervision y Gerencia ven el resumen de la base' using errcode = '42501';
  end if;
  return query
  select e.perfil_id, p.nombre_completo,
         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)),
         (select count(*)::integer from crm.leads l where l.vendedor_id = e.perfil_id and l.activo and l.etapa = 'descartado'
            and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy)
            and l.proxima_llamada_en is not null and (l.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),
         -- Atribucion por DUEÑO del lead: lo que Supervision o Gerencia registran sobre un lead del analista cuenta para el analista.
         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'intento_base'
             and (a.creado_en at time zone 'America/Lima')::date = v_hoy),
         (select count(*)::integer from crm.actividades a join crm.leads l on l.id = a.lead_id
           where l.vendedor_id = e.perfil_id and a.metadata->>'evento' = 'reactivacion_base'
             and date_trunc('month', a.creado_en at time zone 'America/Lima') = date_trunc('month', v_hoy::timestamp))
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'vendedor' and e.activo and p.activo
    and (v_rol = 'gerencia' or e.perfil_id in (select private.vendedor_ids_visibles(v_uid)))
  order by p.nombre_completo;
end;
$$;
alter function crm.base_gestion_resumen() owner to postgres;
revoke all on function crm.base_gestion_resumen() from public, anon, authenticated, service_role;
grant execute on function crm.base_gestion_resumen() to authenticated;
comment on function crm.base_gestion_resumen() is
  'Base para gestión (B3, para F4): por analista activo del ámbito (Supervisión → subárbol; Gerencia → todos), leads en base, rellamadas vencidas o de hoy, intentos de hoy y reactivaciones del mes (Lima), atribuidos al DUEÑO del lead (lo que Supervisión registra sobre un lead del analista cuenta para el analista). Analistas y otros roles: 42501. DEFINER con ámbito explícito, search_path vacío, EXECUTE solo authenticated.';

do $postflight$
declare
  v_puertas text[] := array['crm.obtener_base_gestion(uuid)', 'crm.registrar_intento_base(uuid,uuid,text,text,timestamptz)',
                            'crm.reactivar_lead_base(uuid,uuid,text)', 'crm.base_gestion_resumen()'];
  v_privadas text[] := array['private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)',
                             'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'private.base_gestion_rol(uuid)',
                             'private.base_gestion_lead_visible(uuid,text,uuid,uuid)', 'private.base_gestion_etapa_rango(text)',
                             'private.trg_actividades_base_gestion_solo_nucleo()'];
  f text;
  v_vend uuid; v_coord uuid; v_lead uuid; v_n integer;
begin
  -- 1. Puertas: DEFINER, postgres, search_path vacío, EXECUTE exactamente authenticated (ni anon, ni service_role, ni PUBLIC).
  foreach f in array v_puertas loop
    if (
      exists (select 1 from pg_proc p where p.oid = to_regprocedure(f) and p.prosecdef and p.proowner = 'postgres'::regrole
               and p.proconfig = array['search_path=""']::text[])
      and has_function_privilege('authenticated', f, 'EXECUTE')
      and not has_function_privilege('anon', f, 'EXECUTE')
      and not has_function_privilege('service_role', f, 'EXECUTE')
      and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(f)
                       and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                            or (a.grantee = 'authenticated'::regrole and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
    ) is not true then
      raise exception 'POSTFLIGHT: la puerta % no quedo DEFINER/postgres/search_path vacio/EXECUTE solo authenticated', f;
    end if;
  end loop;
  -- 2. Núcleos y ayudantes: sin EXECUTE para la API; postgres dueño; search_path vacío.
  foreach f in array v_privadas loop
    if (
      exists (select 1 from pg_proc p where p.oid = to_regprocedure(f) and p.proowner = 'postgres'::regrole
               and p.proconfig = array['search_path=""']::text[])
      and not has_function_privilege('authenticated', f, 'EXECUTE')
      and not has_function_privilege('anon', f, 'EXECUTE')
      and not has_function_privilege('service_role', f, 'EXECUTE')
    ) is not true then
      raise exception 'POSTFLIGHT: % quedo expuesta a la API o sin su contrato', f;
    end if;
  end loop;
  -- 2b. Sello de actividades: BEFORE INSERT OR UPDATE OF metadata, habilitado, DEFINER.
  if (
    exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_base_gestion_solo_nucleo'
             and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4 and (t.tgtype & 16) = 16
             and t.tgfoid = to_regprocedure('private.trg_actividades_base_gestion_solo_nucleo()'))
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_base_gestion_solo_nucleo()') and p.prosecdef)
  ) is not true then
    raise exception 'POSTFLIGHT: el sello de actividades de la base no quedo BEFORE INSERT/UPDATE OF metadata habilitado';
  end if;
  -- 3. Negativos sin escribir: validaciones que fallan ANTES de tocar datos.
  select e.perfil_id into v_vend from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'vendedor' and e.activo and p.activo order by e.perfil_id limit 1;
  select e.perfil_id into v_coord from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'coordinador' and e.activo and p.activo order by e.perfil_id limit 1;
  if v_vend is not null then
    perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
    begin
      perform crm.registrar_intento_base(gen_random_uuid(), gen_random_uuid(), 'interesado');
      raise exception 'POSTFLIGHT: acepto un resultado fuera del catalogo' using errcode = 'P0001';
    exception when invalid_parameter_value then null;
    end;
    begin
      perform crm.registrar_intento_base(gen_random_uuid(), gen_random_uuid(), 'volver_a_llamar', null, now() + interval '11 days');
      raise exception 'POSTFLIGHT: acepto una rellamada a mas de 10 dias' using errcode = 'P0001';
    exception when invalid_parameter_value then
      if sqlerrm not like '%maximo 10 dias%' then raise exception 'POSTFLIGHT: rechazo por otro motivo: %', sqlerrm using errcode = 'P0001'; end if;
    end;
    begin
      perform crm.registrar_intento_base(gen_random_uuid(), gen_random_uuid(), 'no_contesto', null, now() + interval '1 day');
      raise exception 'POSTFLIGHT: acepto fecha en un resultado distinto de volver_a_llamar' using errcode = 'P0001';
    exception when invalid_parameter_value then null;
    end;
    begin
      perform crm.reactivar_lead_base(gen_random_uuid(), gen_random_uuid());
      raise exception 'POSTFLIGHT: reactivo un lead inexistente' using errcode = 'P0001';
    exception when no_data_found then null;
    end;
    -- Forja por la API: una «reactivación» o una «respuesta» sin el GUC muere en el sello (antes del insert).
    select l.id into v_lead from crm.leads l where l.activo order by l.creado_en limit 1;
    if v_lead is not null then
      begin
        insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
        values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"reactivacion_base"}', v_vend);
        raise exception 'POSTFLIGHT: el sello dejo forjar una reactivacion' using errcode = 'P0001';
      exception when insufficient_privilege then
        if sqlerrm not like '%base para gestion%' then raise exception 'POSTFLIGHT: otro 42501 se adelanto al sello: %', sqlerrm using errcode = 'P0001'; end if;
      end;
      begin
        insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
        values (v_lead, 'nota', 'POSTFLIGHT', '{"respuesta":{"ok":true}}', v_vend);
        raise exception 'POSTFLIGHT: el sello dejo forjar una respuesta' using errcode = 'P0001';
      exception when insufficient_privilege then null;
      end;
    end if;
    -- El analista solo ve lo suyo.
    select count(*) into v_n from crm.obtener_base_gestion() b where b.vendedor_id is distinct from v_vend;
    if v_n <> 0 then raise exception 'POSTFLIGHT: obtener_base_gestion devolvio % leads ajenos a un analista', v_n; end if;
    begin
      perform crm.base_gestion_resumen();
      raise exception 'POSTFLIGHT: un analista leyo el resumen de Supervision' using errcode = 'P0001';
    exception when insufficient_privilege then null;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  else
    raise notice 'base_gestion_puertas: sin analista activo en esta base; negativos del analista NO RUN';
  end if;
  if v_coord is not null then
    perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_coord, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_coord::text, true);
    begin
      perform crm.obtener_base_gestion();
      raise exception 'POSTFLIGHT: coordinacion leyo la base' using errcode = 'P0001';
    exception when insufficient_privilege then null;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;
  begin
    perform crm.obtener_base_gestion();
    raise exception 'POSTFLIGHT: la base acepto una llamada sin sesion' using errcode = 'P0001';
  exception when insufficient_privilege then null;
  end;
  raise notice 'base_gestion_puertas OK: 4 puertas (EXECUTE solo authenticated), 2 nucleos, 3 ayudantes y el sello de actividades cerrados; ambito por rol y forja verificados sin escribir';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
