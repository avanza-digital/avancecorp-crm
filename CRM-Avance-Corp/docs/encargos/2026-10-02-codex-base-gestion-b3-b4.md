ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea del texto transcrito), RIESGOS y test gaps, NEXT ACTIONS, CONFIDENCE.

# Encargo: Base para gestión del analista · B3 (puertas y núcleos) + B4 (trigger de enfriamiento) — LEVEL 3

## Contexto
Continuación del encargo revisado por ti el 02/10 (B1+B2: BLOCK por el P1 de semántica NULL, corregido y reensayado 25/25).
Desde entonces: B1b añadió `crm.leads.proxima_llamada_en` (sellada; la rellamada vive en el lead porque el CRM rechaza tareas
en leads cerrados), el CHECK del intento exige esa fecha en `volver_a_llamar`, y las constantes son (max_intentos 3,
dias_enfriamiento 30, dias_max_rellamada 10). Decisiones de Miguel: D1 reactivar → `contactado` en la misma operación;
D2 mismo dueño; D3 «agendó cita» reactiva sola; D4/D12 3 intentos sin cita ni rellamada → 30 días (gana la rellamada);
D6 etapa máxima deducida del historial; D7-bis agenda propia; D9 `reactivado_en`; D10 puerta y núcleo propios; D11 rellamada
máx. 10 días. Hechos del esquema: `crm.leads` da privilegios de TABLA a authenticated (por eso hay sellos por trigger);
`trg_00_actividades_resultado_solo_nucleo` (sellado por huella) reserva las claves `resultado`/`intento_n`… bajo
`crm.op_resultado_llamada`; `crm.reabrir_lead_fn` (sellada) reabre a `nuevo` con ciclo nuevo, SLA reiniciado y veto de persona;
el guard de tenencia permite el segundo UPDATE `nuevo → contactado` en la misma transacción; RLS del vendedor = solo sus leads.

Ambas migraciones ya pasaron por el `auditor-rls` del proyecto (hallazgos aplicados: sello de actividades de la base,
candados persona → lead antes del `for update` cuando habrá reactivación, replay leído tras el candado y solo del mismo actor,
resumen atribuido al dueño del lead, gate del trigger de B4 por GUC). Banco Docker con ACL de producción: `b3-puertas.sql`
44/44 y `b4-enfriamiento.sql` 16/16 bajo rol con impersonación (resultados transcritos abajo); `test-rls.mjs` con bloque por
la API (no ejecutado aún: la rama de Supabase con datos espera la contraseña de BD que la CLI enmascara).

## Qué revisar
1. Autorización y ámbito en las 4 puertas (DEFINER sin RLS); 2. idempotencia y concurrencia (replay por `id` + `respuesta`,
candados); 3. corrección de negocio: orden de la base, etapa máxima, consumo de la rellamada, D12, post-descanso; 4. el trigger
B4 y su gate; 5. riesgos para el frontend (códigos de error, replays, «agendó cita» todo-o-nada); 6. test gaps.

## Transcripción 1 · supabase/migrations/20261002231436_crm_base_gestion_puertas.sql
```sql
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
```

## Transcripción 2 · supabase/migrations/20261002233851_crm_base_gestion_enfriamiento.sql
```sql
-- 20261002233851_crm_base_gestion_enfriamiento.sql
--
-- Base para gestión del analista · B4 (trigger de enfriamiento). Plan B4 confirmado por Miguel el 02/10/2026 («vamos si»).
-- Decisiones: D4 (3 intentos sin cita → 30 días de descanso, por ciclo), D12 (gana la rellamada: el lead descansa solo
-- cuando el intento que agota el cupo termina sin cita y sin rellamada), D3 («agendó cita» reactiva: no cuenta para el
-- descanso). Vault: «Base para gestion del analista - F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- QUÉ. Trigger AFTER INSERT en `crm.actividades`, solo para `metadata.evento = 'intento_base'` (WHEN):
--   · si el intento trae rellamada (`proxima_llamada_en`) o es `agendo_reunion`, no hace nada (D12/D3);
--   · si el lead sigue descartado y vivo, cuenta los intentos del ciclo (desde `descartado_en`, incluido este) y, cuando
--     llegan a `max_intentos`, fija `enfriado_hasta = hoy Lima + dias_enfriamiento` bajo el sello de la base.
--   Mientras descansa, el lead no aparece en `obtener_base_gestion` y `registrar_intento_base` lo rechaza (22023);
--   pasado el plazo reaparece solo, con su historial; reactivarlo limpia el descanso (B3). Tras el descanso, un nuevo
--   intento sin rellamada ni cita vuelve a ponerlo a descansar (el cupo del ciclo ya está agotado).
--   Constantes en `private.base_gestion_constantes()` (3, 30, 10). Nombre con el prefijo del bloque AFTER (`zz_`).
--   El SLA al reactivar no necesita trigger: `reabrir_lead_fn` cambia de ciclo y `01_sla_global`/`02_sla_versionado`
--   reinician el reloj y abren el episodio (verificado en B3 y aquí con fechas simuladas).
--
--   Solo actúa dentro del núcleo (auditor-rls B4, P2): exige el GUC de transacción `crm.op_base_gestion = on`, que el
--   núcleo de B3 enciende al insertar el intento. Un escritor sin usuario (service_role sin JWT, backfill, restauración)
--   que inserte `intento_base` históricos NO pone leads a descansar con la fecha de hoy.
--
-- SECURITY DEFINER, por el mismo molde que el sello de B1 (INVOKER también valdría: el UPDATE lo haría igual el núcleo
--   DEFINER): `search_path` vacío, dueño postgres, sin EXECUTE para la API; no amplía ámbito (filtra `id = new.lead_id`,
--   y quien insertó el intento ya estaba autorizado sobre ese lead).
--
-- QUÉ NO CAMBIA. Ninguna función sellada; RLS intacta; sin columnas nuevas. Solo escribe cuando el núcleo de B3
--   inserta un intento (el sello de actividades impide forjarlos desde la API y el GUC acota el trigger al núcleo).
--   El postflight ensaya por la puerta real sobre el descartado MÁS ANTIGUO de un analista activo y lo deshace: toma un
--   candado breve sobre ese lead y, si otro lo tiene bloqueado, `lock_timeout` aborta la migración (fail-safe).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-enfriamiento.sql`: quita el trigger y su función. No toca datos
--   (los `enfriado_hasta` ya fijados quedan; Gerencia los puede limpiar por su puerta cuando exista).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)') is not null
    and (select count(*) from pg_proc p, unnest(p.proargnames) n where p.oid = to_regprocedure('private.base_gestion_constantes()')) = 3
    and exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'enfriado_hasta')
    and exists (select 1 from pg_trigger where tgrelid = 'crm.leads'::regclass and tgname = 'trg_leads_zz_sello_base_gestion' and tgenabled = 'O')
    and exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_00_actividades_base_gestion_solo_nucleo' and tgenabled = 'O')
    and to_regprocedure('private.trg_actividades_enfriamiento_base()') is null
    and not exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_zz_actividades_enfriamiento_base')
  ) is not true then
    raise exception 'PREFLIGHT: faltan B1/B1b/B3 tal como se auditaron, o B4 ya esta aplicada';
  end if;
end;
$preflight$;

create function private.trg_actividades_enfriamiento_base()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_c record;
  v_lead crm.leads%rowtype;
  v_n integer;
  v_guc text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_hasta date;
begin
  -- Solo dentro del nucleo de la base (P2 del auditor): sin el GUC, un backfill sin usuario no enfria nada.
  if coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off') <> 'on' then
    return null;
  end if;
  -- D12 / D3: una rellamada agendada o una cita ganan al enfriamiento.
  if new.metadata->>'resultado' = 'agendo_reunion' or new.metadata ? 'proxima_llamada_en' then
    return null;
  end if;
  select * into v_lead from crm.leads where id = new.lead_id;  -- el nucleo ya lo tiene bajo for update en esta transaccion
  if v_lead.id is null or not v_lead.activo or v_lead.etapa <> 'descartado' then
    return null;
  end if;
  select * into v_c from private.base_gestion_constantes();
  select count(*) into v_n from crm.actividades a
   where a.lead_id = new.lead_id and a.metadata->>'evento' = 'intento_base'
     and a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);  -- incluye este intento (AFTER)
  if v_n < v_c.max_intentos then
    return null;
  end if;
  v_hasta := v_hoy + v_c.dias_enfriamiento;
  v_guc := coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off');
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.leads set enfriado_hasta = v_hasta
   where id = new.lead_id and (enfriado_hasta is null or enfriado_hasta < v_hasta);  -- defensivo: nunca acorta un descanso mayor
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc, true);
  return null;
end;
$$;
alter function private.trg_actividades_enfriamiento_base() owner to postgres;
revoke all on function private.trg_actividades_enfriamiento_base() from public, anon, authenticated, service_role;
comment on function private.trg_actividades_enfriamiento_base() is
  'Base para gestión (B4, D4/D12): al registrar un intento de la base sin rellamada ni cita, si el lead sigue descartado y los intentos del ciclo (desde descartado_en) llegan a max_intentos, fija enfriado_hasta = hoy Lima + dias_enfriamiento. Solo actúa bajo el GUC de transacción crm.op_base_gestion = on (el núcleo de B3); un escritor sin usuario que inserte intentos históricos no enfría. Constantes en private.base_gestion_constantes(). DEFINER por el molde del sello de B1 (INVOKER también valdría); search_path vacío, dueño postgres, sin EXECUTE para la API.';
create trigger trg_zz_actividades_enfriamiento_base
  after insert on crm.actividades
  for each row when (new.metadata->>'evento' = 'intento_base')
  execute function private.trg_actividades_enfriamiento_base();

do $postflight$
declare
  f constant text := 'private.trg_actividades_enfriamiento_base()';
  v_lead uuid; v_vend uuid; v_hasta date; v_c record; v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  if (
    exists (select 1 from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_zz_actividades_enfriamiento_base'
             and t.tgenabled = 'O' and (t.tgtype & 2) = 0 and (t.tgtype & 4) = 4 and t.tgqual is not null
             and t.tgfoid = to_regprocedure(f))
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure(f) and p.prosecdef and p.proowner = 'postgres'::regrole
                 and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', f, 'EXECUTE')
    and not has_function_privilege('anon', f, 'EXECUTE')
    and not has_function_privilege('service_role', f, 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: el trigger de enfriamiento no quedo AFTER INSERT con WHEN, habilitado y con su contrato';
  end if;
  -- Ensayo deshecho: tres intentos sin rellamada sobre un descartado vivo de un analista activo → descansa 30 dias.
  select l.id, l.vendedor_id into v_lead, v_vend
    from crm.leads l join crm.equipo e on e.perfil_id = l.vendedor_id join public.perfiles p on p.id = l.vendedor_id
   where l.activo and l.etapa = 'descartado' and not l.no_contactar and l.enfriado_hasta is null
     and e.rol_crm = 'vendedor' and e.activo and p.activo
     and not exists (select 1 from crm.actividades a where a.lead_id = l.id and a.metadata->>'evento' = 'intento_base')
   order by l.descartado_en asc nulls last limit 1;  -- el mas antiguo: menos choque con trabajo en curso
  if v_lead is null then
    raise notice 'base_gestion_enfriamiento: sin descartado vivo de un analista activo; ensayo NO RUN (se prueba en el banco)';
  else
    -- P2: tres intento_base insertados SIN usuario y SIN el GUC (como un backfill) no enfrian nada (deshecho).
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      select v_lead, 'llamada_no_contestada', 'postflight backfill',
             jsonb_build_object('evento', 'intento_base', 'resultado', 'no_contesto', 'intento_n', g, 'ciclo_n', 1)
        from generate_series(1, 3) g;
      if (select enfriado_hasta from crm.leads where id = v_lead) is not null then
        raise exception 'POSTFLIGHT: un backfill sin GUC puso a descansar al lead' using errcode = 'P0001';
      end if;
      raise exception 'DESHACER' using errcode = 'ZZ0B4';
    exception when sqlstate 'ZZ0B4' then null;
    end;
    select * into v_c from private.base_gestion_constantes();
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform crm.registrar_intento_base(gen_random_uuid(), v_lead, 'no_contesto', 'postflight 1');
      perform crm.registrar_intento_base(gen_random_uuid(), v_lead, 'volver_a_llamar', 'postflight 2', now() + interval '1 hour');
      if (select enfriado_hasta from crm.leads where id = v_lead) is not null then
        raise exception 'POSTFLIGHT: enfrio antes del tercer intento' using errcode = 'P0001';
      end if;
      perform crm.registrar_intento_base(gen_random_uuid(), v_lead, 'no_contesto', 'postflight 3');
      select enfriado_hasta into v_hasta from crm.leads where id = v_lead;
      if v_hasta is distinct from v_hoy + v_c.dias_enfriamiento then
        raise exception 'POSTFLIGHT: el tercer intento sin rellamada no puso a descansar % dias (quedo %)', v_c.dias_enfriamiento, v_hasta using errcode = 'P0001';
      end if;
      if exists (select 1 from crm.obtener_base_gestion() b where b.lead_id = v_lead) then
        raise exception 'POSTFLIGHT: el lead en descanso sigue en la base' using errcode = 'P0001';
      end if;
      raise exception 'DESHACER' using errcode = 'ZZ0B4';
    exception when sqlstate 'ZZ0B4' then
      perform pg_catalog.set_config('request.jwt.claims', '', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
    end;
    if exists (select 1 from crm.actividades a where a.lead_id = v_lead and a.detalle like 'postflight %')
       or (select enfriado_hasta from crm.leads where id = v_lead) is not null then
      raise exception 'POSTFLIGHT: el ensayo del enfriamiento no se deshizo';
    end if;
  end if;
  raise notice 'base_gestion_enfriamiento OK: trigger AFTER INSERT (WHEN intento_base) cerrado; 3 intentos sin rellamada → descanso de % dias (ensayo deshecho)', (select dias_enfriamiento from private.base_gestion_constantes());
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

## Transcripción 3 · resultados del banco (02/10, noche)
```
PASS A: base = sus 4 descartados sin veto (LA, LX1, LX2, LX3) · esperado 4/0 · obtenido 4/0
PASS A: intento 1 no_contesto en LA · esperado ok n=1 sin fecha · obtenido ok n=1 sin fecha
PASS A: la actividad es llamada_no_contestada con evento intento_base · esperado ok · obtenido ok
PASS A: doble clic (misma operación) → replay, sin duplicar · esperado replay 1 actividad · obtenido replay 1 actividad
PASS A: misma operación con otro contenido → 23505 · esperado 23505 · obtenido 23505
PASS A: intento 2 volver_a_llamar (+1 min) fija la rellamada · esperado ok n=2 con fecha · obtenido ok n=2 con fecha
PASS A: el lead lleva proxima_llamada_en y la metadata la trae en ISO · esperado ok · obtenido ok
PASS A: volver_a_llamar a 11 días → 22023 · esperado 22023 · obtenido 22023
PASS A: volver_a_llamar sin fecha → 22023 · esperado 22023 · obtenido 22023
PASS A: no_contesto con fecha → 22023 · esperado 22023 · obtenido 22023
PASS A: resultado inválido → 22023 · esperado 22023 · obtenido 22023
PASS A: intento en LB (de B) → P0002 · esperado P0002 · obtenido P0002
PASS A: intento en LA_VETO (no contactar) → P0429 · esperado P0429 · obtenido P0429
PASS A: intento en lead inexistente → P0002 · esperado P0002 · obtenido P0002
PASS A: orden = LA (rellamada hoy) → LX2 (contactado) → LX1/LX3 (nuevo) · esperado ok · obtenido ok
PASS A: LA trae intentos=2, ultimo=volver_a_llamar, rellamada_hoy, etapa_maxima nuevo; LX2 etapa_maxima contactado · esperado ok · obtenido ok
PASS A: intento 3 no_interesado consume la rellamada y (B4) pone a LA a descansar 30 días · esperado ok n=3 sin fecha descansa · obtenido ok n=3 sin fecha descansa
PASS A: reactivar LX1 → contactado, reactivado_en, ciclo 2 · esperado ok · obtenido ok
PASS A: LX1 vivo en contactado, mismo dueño, sin rellamada ni descanso, con la línea en el historial · esperado ok · obtenido ok
PASS A: doble clic en Reactivar → replay · esperado replay · obtenido replay
PASS A: reactivar un lead que ya no está en la base → 22023 · esperado 22023 · obtenido 22023
PASS A: LX1 ya no aparece en la base (ni LA, que descansa) · esperado 2 · obtenido 2
PASS A: intento sobre LA en descanso → 22023 · esperado 22023 · obtenido 22023
PASS A: agendó cita en LX3 → reactiva en la misma operación · esperado ok reactivado contactado · obtenido ok reactivado contactado
PASS A: LX3 tiene la actividad del intento y la de reactivación · esperado 2 · obtenido 2
PASS SLA: LX1 reinició su reloj global al reactivar · esperado ok · obtenido ok
PASS SLA: LX1 tiene episodio abierto en contactado (ciclo 2) · esperado ok · obtenido ok
PASS A: LX1 descartado otra vez vuelve a la base con intentos=0 y ciclo 2 · esperado ok · obtenido ok
PASS A: resumen de Supervisión → 42501 · esperado 42501 · obtenido 42501
PASS A: forja una «reactivación» por INSERT directo → 42501 (sello) · esperado 42501 · obtenido 42501
PASS A: forja una «respuesta» por INSERT directo → 42501 (sello) · esperado 42501 · obtenido 42501
PASS A: forja un «intento_base» por INSERT directo → 42501 · esperado 42501 · obtenido 42501
PASS B: base = solo LB · esperado ok · obtenido ok
PASS B: intento en LA → P0002 · esperado P0002 · obtenido P0002
PASS S1: base = equipo 1 (LB, LX1, LX2; LA descansa) sin LC · esperado ok · obtenido ok
PASS S1: filtro por analista A → solo A · esperado ok · obtenido ok
PASS S1: filtro por analista C (otro equipo) → P0002 · esperado P0002 · obtenido P0002
PASS S1: registra intento en LB (su equipo) · esperado ok · obtenido ok
PASS S1: resumen = A y B con cifras · esperado ok · obtenido ok
PASS S2: base = solo LC · esperado ok · obtenido ok
PASS S2: intento en LA → P0002 · esperado P0002 · obtenido P0002
PASS G: base = todos los descartados sin veto ni descanso (4: LA descansa) · esperado 4 · obtenido 4
PASS G: registra intento en LC · esperado ok · obtenido ok
PASS G: resumen incluye a C con el intento de Gerencia atribuido a C · esperado ok · obtenido ok
TOTAL: 44 PASS · 0 FAIL

PASS A: intento 1 no enfría · esperado null · obtenido null
PASS A: intento 2 no enfría · esperado null · obtenido null
PASS A: intento 3 sin rellamada → enfriado_hasta = hoy + 30 · esperado ok · obtenido ok
PASS A: LA ya no está en la base · esperado 0 · obtenido 0
PASS A: intento sobre LA en descanso → 22023 · esperado 22023 · obtenido 22023
PASS A: pasados los 30 días LA reaparece con su historial (3 intentos) · esperado ok · obtenido ok
PASS A: un 4.º intento con rellamada NO vuelve a enfriar (gana la rellamada) · esperado ok · obtenido ok
PASS A: el 5.º intento sin rellamada vuelve a enfriar 30 días · esperado ok · obtenido ok
PASS B: 3.º intento = volver_a_llamar → no enfría (D12) · esperado null · obtenido null
PASS B: LB sigue en la base con la rellamada · esperado ok · obtenido ok
PASS B: 4.º intento sin rellamada → enfría · esperado ok · obtenido ok
PASS C: 3.º intento = agendó cita → reactiva y no enfría · esperado ok · obtenido ok
PASS C: LC en descanso no está en la base · esperado 0 · obtenido 0
PASS C: reactivar LC en descanso → contactado (ciclo 3) · esperado ok · obtenido ok
PASS C: la reactivación limpió el descanso y reinició el SLA · esperado ok · obtenido ok
PASS Backfill: 3 intento_base sin usuario ni GUC no ponen a descansar · esperado null · obtenido null
TOTAL: 16 PASS · 0 FAIL
```

## Transcripción 4 · bloques B3/B4 de supabase/scripts/test-rls.mjs (por la API, aún NOT RUN)
```js
// ── Base para gestión · B3 (20261002231436): las puertas por la API ──────────────────────────
// Roles que no entran (42501), validaciones que fallan sin escribir (22023/P0002), y el camino bueno con un lead
// transitorio de vend1: descartarlo por el camino del front, verlo en su base (y que vend3 no lo vea), registrar un
// intento, doble clic → replay, agendar rellamada (+2 min: aparece primera), reactivar → contactado con ciclo 2,
// doble clic → replay, reactivar un lead ya vivo → 22023. El lead se retira con soft-delete al final.
async function testBaseGestionB3(sessions, seed) {
  console.log('\n— Base para gestión B3: puertas obtener / registrar intento / reactivar / resumen —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_BASE_GESTION === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  let aplicada;
  try {
    aplicada = contarFueraDeBanda('base gestión B3: puertas aplicadas',
      `select (to_regprocedure('crm.obtener_base_gestion(uuid)') is not null and to_regprocedure('crm.registrar_intento_base(uuid,uuid,text,text,timestamptz)') is not null and to_regprocedure('crm.reactivar_lead_base(uuid,uuid,text)') is not null and to_regprocedure('crm.base_gestion_resumen()') is not null)::int`);
  } catch (error) {
    saltar(`⚠ Base para gestión B3 SALTADO: sin vía fuera de banda (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ 20261002231436 (base gestión B3) NO desplegada en esta base: bloque SALTADO (no probado)');
    return;
  }
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`base gestión B3: ${etiqueta}`, sql);
  const vend1Id = seed.profileIdByKey.vend1;
  const ana = seed.leadByName.get(LEAD_BY_KEY.ana.name)?.id;  // lead de otro equipo
  const vend1 = sessions.vend1.client.schema('crm');
  const anon = createClient(SUPABASE_URL, ANON_KEY, clientOptions('crm-rls-anon-base-gestion'));
  const DENEGADO = /permission denied|denegado/i;
  const AMBITO = /fuera de tu [aá]mbito/i;
  // Roles.
  await expectExpectedFailure('B3 anon → obtener_base_gestion 42501 (sin EXECUTE)', anon.schema('crm').rpc('obtener_base_gestion'), ['42501'], DENEGADO);
  for (const clave of ['coordinador', 'directorio', 'clientBank', 'vendInactive']) {
    await expectExpectedFailure(`B3 ${clave} → obtener_base_gestion 42501`, sessions[clave].client.schema('crm').rpc('obtener_base_gestion'), ['42501'], /analistas, Supervision y Gerencia|No autorizado|permission denied|denegado/i);
  }
  for (const fn of ['obtener_base_gestion', 'base_gestion_resumen']) {
    await expectExpectedFailure(`B3 service_role → ${fn} 42501 (sin EXECUTE)`, admin.schema('crm').rpc(fn), ['42501'], DENEGADO);
  }
  await expectExpectedFailure('B3 service_role → registrar_intento_base 42501 (sin EXECUTE)', admin.schema('crm').rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID(), p_resultado: 'no_contesto' }), ['42501'], DENEGADO);
  await expectExpectedFailure('B3 service_role → reactivar_lead_base 42501 (sin EXECUTE)', admin.schema('crm').rpc('reactivar_lead_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID() }), ['42501'], DENEGADO);
  await expectExpectedFailure('B3 vendInactive → registrar_intento_base 42501', sessions.vendInactive.client.schema('crm').rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID(), p_resultado: 'no_contesto' }), ['42501'], /analistas, Supervision y Gerencia|No autorizado/i);
  await expectExpectedFailure('B3 vend1 pide la base de vend3 → 42501', vend1.rpc('obtener_base_gestion', { p_vendedor_id: seed.profileIdByKey.vend3 }), ['42501'], /su propia base/i);
  await expectExpectedFailure('B3 sup1 pide la base de vend3 (otro equipo) → P0002', sessions.sup1.client.schema('crm').rpc('obtener_base_gestion', { p_vendedor_id: seed.profileIdByKey.vend3 }), ['P0002'], AMBITO);
  await positive('B3 sup1 pide la base de vend1 (su analista)', sessions.sup1.client.schema('crm').rpc('obtener_base_gestion', { p_vendedor_id: vend1Id }));
  await expectExpectedFailure('B3 vend1 → base_gestion_resumen 42501', vend1.rpc('base_gestion_resumen'), ['42501'], /Supervision y Gerencia/i);
  check(cuenta('acl puertas', `select count(*) from unnest(array['crm.obtener_base_gestion(uuid)','crm.registrar_intento_base(uuid,uuid,text,text,timestamptz)','crm.reactivar_lead_base(uuid,uuid,text)','crm.base_gestion_resumen()']) f(firma) where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE') or not has_function_privilege('authenticated', f.firma, 'EXECUTE') or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0)`) === 0,
    'B3 las cuatro puertas exponen EXECUTE exactamente a authenticated (ni anon, ni service_role, ni PUBLIC)');
  check(cuenta('acl privadas', `select count(*) from unnest(array['private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)','private.base_gestion_reactivar_core(uuid,uuid,uuid,text)','private.base_gestion_rol(uuid)','private.base_gestion_lead_visible(uuid,text,uuid,uuid)','private.base_gestion_etapa_rango(text)','private.trg_actividades_base_gestion_solo_nucleo()']) f(firma) where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('authenticated', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')`) === 0,
    'B3 núcleos, ayudantes y sello sin EXECUTE para la API');
  check(cuenta('sello actividades', `select count(*) from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_00_actividades_base_gestion_solo_nucleo' and t.tgenabled = 'O' and (t.tgtype & 2) = 2`) === 1,
    'B3 el sello de actividades de la base está BEFORE y habilitado');
  await positive('B3 sup1 lee el resumen de su equipo', sessions.sup1.client.schema('crm').rpc('base_gestion_resumen'));
  await positive('B3 gerencia lee el resumen de la operación', sessions.gerencia.client.schema('crm').rpc('base_gestion_resumen'));
  // Validaciones que fallan ANTES de escribir.
  await expectExpectedFailure('B3 vend1 resultado fuera del catálogo → 22023', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID(), p_resultado: 'interesado' }), ['22023'], /invalido/i);
  await expectExpectedFailure('B3 vend1 rellamada a 11 días → 22023', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID(), p_resultado: 'volver_a_llamar', p_proxima_llamada: new Date(Date.now() + 11 * 86400000).toISOString() }), ['22023'], /maximo 10 dias/i);
  await expectExpectedFailure('B3 vend1 no_contesto con fecha → 22023', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID(), p_resultado: 'no_contesto', p_proxima_llamada: new Date(Date.now() + 86400000).toISOString() }), ['22023'], /volver a llamar/i);
  await expectExpectedFailure('B3 vend1 intento en lead de otro equipo (ana) → P0002', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: ana, p_resultado: 'no_contesto' }), ['P0002'], AMBITO);
  await expectExpectedFailure('B3 vend1 reactivar lead inexistente → P0002', vend1.rpc('reactivar_lead_base', { p_operacion_id: randomUUID(), p_lead_id: randomUUID() }), ['P0002'], AMBITO);
  // Camino bueno con un lead transitorio de vend1 (nace nuevo; lo descarta su analista por el camino del front).
  const L = randomUUID();
  try {
    await requireAdmin('B3: sembrar un lead nuevo de vend1', admin.schema('crm').from('leads').insert({
      activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'oficina', monto_estimado: 5000,
      id: L, nombre_completo: 'B3 BASE GESTION TRANSIENT', telefono: TEL_IDENTIDAD(61), creado_por: vend1Id, vendedor_id: vend1Id,
    }));
    await requireAdmin('B3: vend1 descarta el suyo', vend1.from('leads').update({ etapa: 'descartado', motivo_descarte: 'no_responde' }).eq('id', L));
    const base1 = await positive('B3 vend1 obtiene su base', vend1.rpc('obtener_base_gestion'));
    assertions += 1;
    if (Array.isArray(base1?.data) && base1.data.some((r) => r.lead_id === L && r.intentos === 0 && r.etapa_maxima === 'nuevo') && base1.data.every((r) => r.vendedor_id === vend1Id)) console.log('  ✓ B3 la base de vend1 trae su descartado (0 intentos, etapa máxima nuevo) y solo los suyos');
    else fail(`B3: la base de vend1 no trae su descartado o trae ajenos (${JSON.stringify(base1?.data?.slice(0, 2))})`);
    await expectExpectedFailure('B3 vend1 forja una «reactivación» por INSERT → 42501 (sello)', vend1.from('actividades').insert({ creado_por: vend1Id, detalle: 'B3 FORJA TRANSIENT', lead_id: L, tipo: 'nota', metadata: { evento: 'reactivacion_base' } }).select('id'), ['42501'], /solo las escribe su nucleo/i);
    await expectExpectedFailure('B3 vend1 forja una «respuesta» por INSERT → 42501 (sello)', vend1.from('actividades').insert({ creado_por: vend1Id, detalle: 'B3 FORJA TRANSIENT', lead_id: L, tipo: 'nota', metadata: { respuesta: { ok: true, evento: 'reactivacion_base', lead_id: L } } }).select('id'), ['42501'], /solo las escribe su nucleo/i);
    const baseS2 = await positive('B3 sup2 obtiene su base', sessions.sup2.client.schema('crm').rpc('obtener_base_gestion'));
    assertions += 1;
    if (Array.isArray(baseS2?.data) && !baseS2.data.some((r) => r.lead_id === L)) console.log('  ✓ B3 sup2 (otro equipo) no ve el descartado de vend1'); else fail('B3: sup2 ve un lead del equipo de sup1');
    const baseS1 = await positive('B3 sup1 obtiene la base de su equipo', sessions.sup1.client.schema('crm').rpc('obtener_base_gestion'));
    assertions += 1;
    if (Array.isArray(baseS1?.data) && baseS1.data.some((r) => r.lead_id === L && r.gestiona)) console.log('  ✓ B3 sup1 ve el descartado de su analista con quién lo gestiona'); else fail('B3: sup1 no ve el descartado de vend1');
    const base3 = await positive('B3 vend3 obtiene su base', sessions.vend3.client.schema('crm').rpc('obtener_base_gestion'));
    assertions += 1;
    if (Array.isArray(base3?.data) && !base3.data.some((r) => r.lead_id === L)) console.log('  ✓ B3 vend3 no ve el descartado de vend1');
    else fail('B3: vend3 ve un lead de vend1');
    const op1 = randomUUID();
    const i1 = await positive('B3 vend1 registra no_contesto', vend1.rpc('registrar_intento_base', { p_operacion_id: op1, p_lead_id: L, p_resultado: 'no_contesto', p_nota: 'sin respuesta' }));
    assertions += 1;
    if (i1?.data?.ok === true && i1.data.intento_n === 1 && i1.data.replay === false && i1.data.proxima_llamada_en == null) console.log('  ✓ B3 intento 1 registrado');
    else fail(`B3: intento 1 inesperado ${JSON.stringify(i1?.data)}`);
    const i1b = await positive('B3 doble clic (misma operación)', vend1.rpc('registrar_intento_base', { p_operacion_id: op1, p_lead_id: L, p_resultado: 'no_contesto', p_nota: 'sin respuesta' }));
    assertions += 1;
    if (i1b?.data?.replay === true && i1b.data.intento_n === 1 && cuenta('intentos de L', `select count(*) from crm.actividades where lead_id = '${L}' and metadata->>'evento' = 'intento_base'`) === 1) console.log('  ✓ B3 el doble clic devuelve replay sin duplicar');
    else fail(`B3: el doble clic no fue replay ${JSON.stringify(i1b?.data)}`);
    await expectExpectedFailure('B3 misma operación con otro contenido → 23505', vend1.rpc('registrar_intento_base', { p_operacion_id: op1, p_lead_id: L, p_resultado: 'no_interesado' }), ['23505'], /otro contenido/i);
    const i2 = await positive('B3 vend1 registra volver_a_llamar (+2 min)', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L, p_resultado: 'volver_a_llamar', p_proxima_llamada: new Date(Date.now() + 120000).toISOString() }));
    assertions += 1;
    if (i2?.data?.intento_n === 2 && i2.data.proxima_llamada_en) console.log('  ✓ B3 intento 2 fija la rellamada');
    else fail(`B3: intento 2 inesperado ${JSON.stringify(i2?.data)}`);
    const base2 = await positive('B3 la base trae la rellamada primero', vend1.rpc('obtener_base_gestion'));
    assertions += 1;
    const fila = Array.isArray(base2?.data) ? base2.data.find((r) => r.lead_id === L) : null;
    if (fila && fila.intentos === 2 && fila.ultimo_resultado === 'volver_a_llamar' && fila.rellamada_hoy === true && base2.data[0]?.lead_id === L) console.log('  ✓ B3 la rellamada de hoy va primera con intentos=2');
    else fail(`B3: la base no refleja la rellamada ${JSON.stringify(fila)}`);
    // B4 (20261002233851): el 3.º intento sin rellamada ni cita pone al lead a descansar 30 días y lo saca de la base.
    const b4 = cuenta('B4 aplicada', `select count(*) from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_zz_actividades_enfriamiento_base' and tgenabled = 'O'`) === 1;
    if (b4) {
      const i3 = await positive('B4 vend1 registra el 3.º intento sin rellamada', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L, p_resultado: 'no_contesto' }));
      assertions += 1;
      if (i3?.data?.intento_n === 3 && typeof i3.data.enfriado_hasta === 'string') console.log(`  ✓ B4 el 3.º intento pone al lead a descansar hasta ${i3.data.enfriado_hasta}`);
      else fail(`B4: el 3.º intento no puso a descansar ${JSON.stringify(i3?.data)}`);
      check(cuenta('descanso de 30 días', `select count(*) from crm.leads where id = '${L}' and enfriado_hasta = ((now() at time zone 'America/Lima')::date + (select dias_enfriamiento from private.base_gestion_constantes()))`) === 1,
        'B4 enfriado_hasta = hoy Lima + dias_enfriamiento');
      const baseFria = await positive('B4 la base ya no lista el lead en descanso', vend1.rpc('obtener_base_gestion'));
      assertions += 1;
      if (Array.isArray(baseFria?.data) && !baseFria.data.some((r) => r.lead_id === L)) console.log('  ✓ B4 el lead en descanso no está en la base'); else fail('B4: el lead en descanso sigue en la base');
      await expectExpectedFailure('B4 intento sobre un lead en descanso → 22023', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L, p_resultado: 'no_contesto' }), ['22023'], /descanso/i);
      check(cuenta('contrato del trigger B4', `select count(*) from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()') and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[] and not has_function_privilege('anon', p.oid, 'EXECUTE') and not has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('service_role', p.oid, 'EXECUTE')`) === 1
          && cuenta('trigger B4 AFTER INSERT con WHEN', `select count(*) from pg_trigger t where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_zz_actividades_enfriamiento_base' and t.tgenabled = 'O' and (t.tgtype & 2) = 0 and (t.tgtype & 4) = 4 and t.tgqual is not null`) === 1,
        'B4 el trigger de enfriamiento es AFTER INSERT con WHEN, DEFINER de postgres, search_path vacío y sin EXECUTE para la API');
    } else {
      console.log('  (B4 20261002233851 no está en esta base: se saltan sus casos)');
      if (process.env.CRM_RLS_EXIGE_BASE_GESTION === '1') fail('B4 no desplegada');
    }
    await expectExpectedFailure('B3 vend3 reactiva el lead de vend1 → P0002', sessions.vend3.client.schema('crm').rpc('reactivar_lead_base', { p_operacion_id: randomUUID(), p_lead_id: L }), ['P0002'], AMBITO);
    const op3 = randomUUID();
    const r1 = await positive('B3 vend1 reactiva', vend1.rpc('reactivar_lead_base', { p_operacion_id: op3, p_lead_id: L, p_nota: 'volvió a interesarse' }));
    assertions += 1;
    if (r1?.data?.etapa === 'contactado' && r1.data.reactivado_en && r1.data.ciclo_n === 2 && r1.data.replay === false) console.log('  ✓ B3 reactivado a contactado, ciclo 2');
    else fail(`B3: reactivación inesperada ${JSON.stringify(r1?.data)}`);
    const r1b = await positive('B3 doble clic en Reactivar', vend1.rpc('reactivar_lead_base', { p_operacion_id: op3, p_lead_id: L, p_nota: 'volvió a interesarse' }));
    assertions += 1;
    if (r1b?.data?.replay === true) console.log('  ✓ B3 el doble clic en Reactivar devuelve replay'); else fail('B3: el doble clic en Reactivar no fue replay');
    check(cuenta('foto tras reactivar', `select count(*) from crm.leads l where l.id = '${L}' and l.etapa = 'contactado' and l.vendedor_id = '${vend1Id}' and l.reactivado_en is not null and l.proxima_llamada_en is null and l.enfriado_hasta is null and l.ciclo_actual = 2`) === 1,
      'B3 la foto: contactado, mismo dueño, reactivado_en, sin rellamada ni descanso, ciclo 2');
    check(cuenta('historial', `select count(*) from crm.actividades where lead_id = '${L}' and ((metadata->>'evento' = 'reactivacion_base' and detalle = 'volvió a interesarse') or (tipo = 'cambio_etapa' and metadata->>'etapa_nueva' = 'contactado'))`) === 2,
      'B3 el historial trae la línea de reactivación y el cambio a contactado');
    await expectExpectedFailure('B3 vend1 reactiva un lead ya vivo → 22023', vend1.rpc('reactivar_lead_base', { p_operacion_id: randomUUID(), p_lead_id: L }), ['22023'], /no esta en la base/i);
    const base4 = await positive('B3 el lead reactivado ya no está en la base', vend1.rpc('obtener_base_gestion'));
    assertions += 1;
    if (Array.isArray(base4?.data) && !base4.data.some((r) => r.lead_id === L)) console.log('  ✓ B3 el lead reactivado salió de la base'); else fail('B3: el lead reactivado sigue en la base');
  } finally {
    await requireAdmin('B3: retirar el lead transitorio (soft-delete)', admin.schema('crm').from('leads').update({ activo: false }).eq('id', L));
  }
  // «Agendó cita» por la API: reactiva en la misma operación (D3) con un segundo lead transitorio.
  const L2 = randomUUID();
  try {
    await requireAdmin('B3: sembrar un segundo lead nuevo de vend1', admin.schema('crm').from('leads').insert({
      activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'oficina', monto_estimado: 5000,
      id: L2, nombre_completo: 'B3 BASE GESTION CITA TRANSIENT', telefono: TEL_IDENTIDAD(62), creado_por: vend1Id, vendedor_id: vend1Id,
    }));
    await requireAdmin('B3: vend1 descarta el segundo', vend1.from('leads').update({ etapa: 'descartado', motivo_descarte: 'sin_fondos' }).eq('id', L2));
    const c1 = await positive('B3 vend1 registra agendo_reunion', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L2, p_resultado: 'agendo_reunion', p_nota: 'reunión el viernes' }));
    assertions += 1;
    if (c1?.data?.reactivado === true && c1.data.etapa === 'contactado' && c1.data.intento_n === 1) console.log('  ✓ B3 «agendó cita» reactiva en la misma operación');
    else fail(`B3: agendó cita no reactivó ${JSON.stringify(c1?.data)}`);
    check(cuenta('cita: foto', `select count(*) from crm.leads l where l.id = '${L2}' and l.etapa = 'contactado' and l.reactivado_en is not null and l.ciclo_actual = 2`) === 1
        && cuenta('cita: historial', `select count(*) from crm.actividades where lead_id = '${L2}' and metadata->>'evento' in ('intento_base', 'reactivacion_base')`) === 2,
      'B3 tras «agendó cita»: contactado, ciclo 2, intento + reactivación en el historial');
  } finally {
    await requireAdmin('B3: retirar el segundo lead transitorio (soft-delete)', admin.schema('crm').from('leads').update({ activo: false }).eq('id', L2));
  }
  // B4 · D12 por la API: el 3.º intento CON rellamada no enfría; el 4.º sin rellamada sí.
  if (cuenta('B4 aplicada (D12)', `select count(*) from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_zz_actividades_enfriamiento_base' and tgenabled = 'O'`) === 1) {
    const L3 = randomUUID();
    try {
      await requireAdmin('B4: sembrar un tercer lead nuevo de vend1', admin.schema('crm').from('leads').insert({
        activo: true, asignado_supervisor_id: null, etapa: 'nuevo', moneda: 'PEN', no_contactar: false, origen: 'oficina', monto_estimado: 5000,
        id: L3, nombre_completo: 'B4 D12 TRANSIENT', telefono: TEL_IDENTIDAD(63), creado_por: vend1Id, vendedor_id: vend1Id,
      }));
      await requireAdmin('B4: vend1 descarta el tercero', vend1.from('leads').update({ etapa: 'descartado', motivo_descarte: 'no_responde' }).eq('id', L3));
      await positive('B4 D12 intento 1', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L3, p_resultado: 'no_contesto' }));
      await positive('B4 D12 intento 2', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L3, p_resultado: 'numero_errado' }));
      const d3 = await positive('B4 D12 intento 3 = volver_a_llamar (+1 día)', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L3, p_resultado: 'volver_a_llamar', p_proxima_llamada: new Date(Date.now() + 86400000).toISOString() }));
      assertions += 1;
      if (d3?.data?.intento_n === 3 && d3.data.enfriado_hasta == null) console.log('  ✓ B4 D12: el 3.º intento con rellamada no enfría'); else fail(`B4 D12: el 3.º con rellamada enfrió ${JSON.stringify(d3?.data)}`);
      const baseD12 = await positive('B4 D12 sigue en la base con su rellamada', vend1.rpc('obtener_base_gestion'));
      assertions += 1;
      if (Array.isArray(baseD12?.data) && baseD12.data.some((r) => r.lead_id === L3 && r.proxima_llamada_en)) console.log('  ✓ B4 D12: sigue en la base con la rellamada'); else fail('B4 D12: el lead con rellamada desapareció de la base');
      const d4 = await positive('B4 D12 intento 4 sin rellamada', vend1.rpc('registrar_intento_base', { p_operacion_id: randomUUID(), p_lead_id: L3, p_resultado: 'no_contesto' }));
      assertions += 1;
      if (d4?.data?.intento_n === 4 && typeof d4.data.enfriado_hasta === 'string') console.log('  ✓ B4 D12: el 4.º intento sin rellamada pone a descansar'); else fail(`B4 D12: el 4.º no enfrió ${JSON.stringify(d4?.data)}`);
    } finally {
      await requireAdmin('B4: retirar el tercer lead transitorio (soft-delete)', admin.schema('crm').from('leads').update({ activo: false }).eq('id', L3));
    }
  }
}

```

## Pregunta de negocio abierta (auditor-rls B4, P3)
Tras vencer los 30 días de descanso, el cupo del ciclo sigue agotado: UN intento más sin rellamada ni cita vuelve a enfriar
30 días (así está implementado y probado). La alternativa es «3 intentos nuevos tras cada descanso» (contar desde
`greatest(descartado_en, fin del último descanso)`). ¿Ves un riesgo de negocio o técnico en una u otra? (Miguel decide.)

## Protocolo global (adjunto)
```
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
```

## Protocolo del proyecto (adjunto, .ai/REVIEW_PROTOCOL.md)
```
# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
```
