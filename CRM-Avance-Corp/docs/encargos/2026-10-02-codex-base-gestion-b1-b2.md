ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato: VERDICT (PASS/BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia
(archivo:línea del texto transcrito), RIESGOS y test gaps, NEXT ACTIONS, CONFIDENCE.

# Encargo: Base para gestión del analista · B1 (esquema) + B2 (permisos) — LEVEL 3 (datos, permisos, migraciones)

## Contexto de negocio (decisiones de Miguel, 02/10/2026)
El CRM (Supabase/Postgres, esquema `crm` expuesto por PostgREST, núcleos en `private`) tiene un «Centro de rescate»
donde supervisor y gerencia ven los leads descartados. Se construye una «base para gestión» para el ANALISTA
(rol `vendedor`): ve sus propios leads descartados, registra intentos de llamada (7 resultados cerrados ya
existentes: no_contesto, volver_a_llamar, agendo_reunion, no_interesado, numero_errado, no_es_la_persona,
pide_otro_producto), agenda rellamadas y reactiva leads. Decisiones: D1 reactivar lleva a `contactado`
(reabrir a `nuevo` + avanzar en la misma transacción); D2 mismo dueño; D3 botón Reactivar explícito (no hay
resultado «interesado»); D4 3 intentos sin cita/reactivación → 30 días de enfriamiento, por ciclo; D5 el
supervisor también puede quitar «no contactar» (su equipo, con motivo); D6 etapa máxima deducida del historial;
D7 rellamada en `crm.tareas`; D8 columna `enfriado_hasta` + trigger; D9 `reactivado_en` + actividad (`origen` es
inmutable); D10 puerta y núcleo propios para el intento.

## Hechos del esquema relevantes (verificados en migraciones)
- `crm.leads` concede a `authenticated` privilegios de TABLA (`authenticated=rw`, `service_role=arwd`): un grant por
  columna no protege una columna nueva; por eso B1 añade un SELLO por trigger.
- `information_schema.column_privileges` expande el grant de tabla a cada columna (auditor-rls B1, P1): el
  postflight usa `pg_attribute.attacl`.
- `crm.actividades.metadata` lleva el resultado de llamada; el CHECK `actividades_resultado_llamada_forma`
  (evento `resultado_llamada`) y el trigger BEFORE `trg_00_actividades_resultado_solo_nucleo` (reserva las claves
  resultado, submotivo, intento_n… salvo con el GUC de transacción `crm.op_resultado_llamada='on'`, y exime a
  sesiones con `auth.uid()` null) están SELLADOS por huella en `private.assert_gestion_diaria_resultado()`, igual
  que `crm.reabrir_lead_fn`, `crm.marcar_no_contactar`, `private.llamada_registrar`, `trg_leads_cambio_etapa`,
  `trg_leads_zz_sello_descarte`, `trg_leads_sync_tareas`. Ninguna se reemplaza en B1/B2.
- `crm.levantar_no_contactar(uuid,text)` NO está en ningún `private.assert_*` (solo anclas puntuales ya corridas).
- RLS vigente para `vendedor`: `leads_select/update` por `private.vendedor_ids_visibles(auth.uid())` (vendedor → solo
  él; supervisor → subárbol; gerencia → todos), `actividades_insert` exige `creado_por = auth.uid()` y lead propio,
  `tareas_*` solo propias (update solo `vence_en`, `confirmada_en`). Gate restrictivo `crm_actor_activo_gate`.
- Trigger `private.trg_tareas_before_insert`: «El lead está cerrado: no admite tareas nuevas» si etapa ∈
  (convertido, descartado). CONSECUENCIA (hallazgo 02/10): la rellamada de la base NO puede ser una tarea tal como
  está (choca con D7). Se pedirá decisión a Miguel; ver la pregunta final.

## Qué revisar
1. Migración B1 (esquema): columnas `reactivado_en`/`enfriado_hasta`, sello, CHECK `actividades_intento_base_forma`,
   constantes. 2. Migración B2 (permisos): `levantar_no_contactar` abierta a Supervisión con ámbito por persona.
3. Las pruebas: banco Docker (postflights, `test.sql`, `b2-rls.sql` 20/20), casos nuevos en `test-rls.mjs`.
4. Diseño para B3 ante el hallazgo de las tareas (opinión acotada, sin implementar).

## Transcripción 1 · supabase/migrations/20261002054402_crm_base_gestion_esquema.sql
```sql
-- 20261002054402_crm_base_gestion_esquema.sql
--
-- Base para gestión del analista · B1 (esquema). Encargo P-0XX «Base de gestión para analistas con
-- seguimiento y reactivación de leads» (Miguel, 01/10/2026). Plan B1 confirmado por Miguel el
-- 02/10/2026 («sii») tras las decisiones D1–D10 del mismo día. Nota del vault:
-- «Base para gestion del analista - F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- QUÉ. Solo terreno; ninguna puerta ni núcleo de negocio todavía (eso es B3/B4):
--   1. `crm.leads.reactivado_en timestamptz` (D9): cuándo el analista reactivó el lead desde la base.
--      El origen comercial (`origen`) NO se toca: es inmutable y lo mide el Ranking.
--   2. `crm.leads.enfriado_hasta date` (D8): fecha Lima hasta la que el lead descansa fuera de la base
--      tras agotar los intentos. La escribirá el trigger de B4; Gerencia podrá ajustarla por su puerta.
--   3. CHECK `actividades_intento_base_forma` en `crm.actividades`: toda actividad con
--      `metadata.evento = 'intento_base'` trae `resultado` del MISMO catálogo cerrado de 7 valores de
--      Gestión Diaria (D3/D10: no se crea un enum nuevo), `intento_n` y `ciclo_n` enteros ≥ 1, submotivo
--      del catálogo si viene, y si `resultado = 'volver_a_llamar'` exige `tarea_id` (uuid de la rellamada
--      en `crm.tareas`, D7). Así «volver a llamar exige fecha» se cumple sin columna nueva.
--   4. `private.base_gestion_constantes()`: las dos constantes de negocio en UN solo sitio (D4):
--      `max_intentos = 3`, `dias_enfriamiento = 30`. Cambiarlas es una migración, no un dato.
--   5. Sello `trg_leads_zz_sello_base_gestion`: las dos columnas nuevas solo las escribe el núcleo
--      (GUC de transacción `crm.op_base_gestion = 'on'`) o una sesión sin usuario (migraciones, jobs).
--      Hace falta porque `crm.leads` concede a `authenticated` privilegios de TABLA (20260723120000:120-128),
--      que cubren las columnas futuras: un grant por columna no protege; el sello sí. Mismo molde que
--      `trg_leads_000_no_contactar_puerta` y `trg_00_actividades_resultado_solo_nucleo`.
--
-- QUÉ SE REUTILIZA Y NO SE CREA (el encargo pedía crearlo): el resultado de llamada (metadata + CHECK
--   vigente + trigger «solo núcleo»), la rellamada (`crm.tareas.vence_en`), «no contactar» y su motivo
--   (columna `no_contactar` + actividad `evento = no_contactar`), `lead_asignaciones.motivo_apertura =
--   'reactivado'`. Índices: ninguno nuevo; `(dueño, estado)` lo cubre `idx_leads_vendedor` y la agenda
--   `tareas_pendientes_keyset_idx`. Se comprueba con EXPLAIN en el banco (scripts/base-gestion/test.sql).
--
-- QUÉ NO CAMBIA. Ningún dato existente. Las columnas nacen NULL. El CHECK condiciona un evento que hoy no
--   existe en ninguna fila (`not valid` + `validate`, como el CHECK vigente). Ninguna función sellada por
--   huella se reemplaza (solo se comprueba que siguen ahí). RLS y policies de `leads`/`actividades` intactas.
--
-- GRANTS. Lectura por columna a `authenticated` y `service_role`, por convención y registro (20260919211105:
--   un revoke de tabla ARRASTRA las ACL por columna; el grant por columna documenta qué reponer, no es una
--   red). Sin INSERT/UPDATE por columna: escribe el núcleo (DEFINER, dueño postgres) y lo vigila el sello.
--   Exención del sello: una sesión sin usuario (`auth.uid()` null: migraciones, jobs, service_role sin JWT)
--   escribe sin GUC, igual que el trigger «solo núcleo» de actividades (20260920005000:216-221).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-esquema.sql`: quita trigger, función del sello, CHECK,
--   función de constantes y las dos columnas. Solo se pierden los valores de las dos columnas nuevas.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  -- Guardas en positivo con `is not true`: un NULL también rechaza.
  -- 1. Nada de lo que crea existe ya (ni con otro nombre parecido).
  if (
    not exists (select 1 from information_schema.columns
                 where table_schema = 'crm' and table_name = 'leads'
                   and column_name in ('reactivado_en', 'enfriado_hasta', 'reabierto_en', 'etapa_maxima'))
    and not exists (select 1 from pg_constraint
                     where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma')
    and to_regprocedure('private.base_gestion_constantes()') is null
    and to_regprocedure('private.trg_leads_zz_sello_base_gestion()') is null
    and not exists (select 1 from pg_trigger where tgrelid = 'crm.leads'::regclass
                     and tgname = 'trg_leads_zz_sello_base_gestion')
  ) is not true then
    raise exception 'PREFLIGHT: alguna pieza de base_gestion ya existe; esta migracion no se reaplica';
  end if;
  -- 2. Las piezas que reutiliza siguen vivas: el catálogo cerrado de 7 resultados (CHECK validado) y el
  --    trigger «solo núcleo» de actividades (habilitado, BEFORE). La lista de valores de abajo se copia
  --    de ese CHECK: si cambió, hay que revisar las dos a la vez.
  if (
    exists (select 1 from pg_constraint c
             where c.conrelid = 'crm.actividades'::regclass
               and c.conname = 'actividades_resultado_llamada_forma' and c.convalidated
               and (select bool_and(pg_get_constraintdef(c.oid) like '%''' || v || '''::text%')
                      from unnest(array['no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
                                        'numero_errado', 'no_es_la_persona', 'pide_otro_producto']) v))
    and exists (select 1 from pg_trigger t
                 where t.tgrelid = 'crm.actividades'::regclass
                   and t.tgname = 'trg_00_actividades_resultado_solo_nucleo'
                   and t.tgenabled = 'O' and (t.tgtype & 2) = 2)
    and exists (select 1 from information_schema.columns
                 where table_schema = 'crm' and table_name = 'leads' and column_name = 'descartado_en')
    and exists (select 1 from information_schema.columns
                 where table_schema = 'crm' and table_name = 'tareas' and column_name = 'vence_en')
  ) is not true then
    raise exception 'PREFLIGHT: el catalogo de resultados, el trigger solo-nucleo, descartado_en o tareas.vence_en no estan como se auditaron';
  end if;
end;
$preflight$;

-- ── 1. Tablas: dos columnas en crm.leads ──────────────────────────────────────────────────────
alter table crm.leads
  add column reactivado_en timestamptz,
  add column enfriado_hasta date;

comment on column crm.leads.reactivado_en is
  'Base para gestión (B1, D9): cuándo el analista reactivó este lead descartado desde su base. Lo sella el núcleo de reactivación; NULL si nunca. No sustituye a `origen` (inmutable, canal de llegada).';
comment on column crm.leads.enfriado_hasta is
  'Base para gestión (B1, D8): fecha Lima hasta la que el lead descansa fuera de la base del analista tras agotar los intentos (constantes en private.base_gestion_constantes). La escribe el trigger de enfriamiento; Gerencia la ajusta solo por su puerta. NULL = sin enfriamiento.';

-- ── 2. Restricciones: forma del intento de la base en crm.actividades ─────────────────────────
alter table crm.actividades add constraint actividades_intento_base_forma check (
  coalesce(metadata->>'evento', '') <> 'intento_base'
  or (
    coalesce(metadata->>'resultado', '') in (
      'no_contesto', 'volver_a_llamar', 'agendo_reunion', 'no_interesado',
      'numero_errado', 'no_es_la_persona', 'pide_otro_producto')
    and coalesce(metadata->>'intento_n', '') ~ '^[1-9][0-9]{0,5}$'
    and coalesce(metadata->>'ciclo_n', '') ~ '^[1-9][0-9]{0,5}$'
    and (metadata->>'submotivo' is null or metadata->>'submotivo' in (
      'sin_fondos_ahora', 'ya_invirtio_con_otro', 'desconfianza', 'no_le_interesa_invertir',
      'prestamo', 'credito', 'otro'))
    and (coalesce(metadata->>'resultado', '') <> 'volver_a_llamar'
         or coalesce(metadata->>'tarea_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  )
) not valid;
alter table crm.actividades validate constraint actividades_intento_base_forma;
comment on constraint actividades_intento_base_forma on crm.actividades is
  'Base para gestión (B1): toda actividad con evento=intento_base trae resultado del MISMO catálogo cerrado de 7 valores de Gestión Diaria, intento_n y ciclo_n enteros >= 1, submotivo del catálogo si viene, y tarea_id (uuid de la rellamada en crm.tareas) cuando el resultado es volver_a_llamar. De forma, no de presencia.';

-- ── 3. Núcleo: constantes de negocio en un solo sitio ─────────────────────────────────────────
create function private.base_gestion_constantes()
returns table (max_intentos integer, dias_enfriamiento integer)
language sql
immutable
security invoker
set search_path = ''
as $$
  select 3, 30;
$$;
alter function private.base_gestion_constantes() owner to postgres;
revoke all on function private.base_gestion_constantes() from public, anon, authenticated, service_role;
comment on function private.base_gestion_constantes() is
  'Base para gestión (B1, D4): constantes de negocio en un solo sitio. max_intentos = intentos sin cita ni reactivación que agotan al lead en su ciclo; dias_enfriamiento = días Lima que descansa fuera de la base. Las consumen los núcleos (DEFINER); cambiarlas es una migración.';

-- ── 4. Sello: las columnas nuevas solo las escribe el núcleo ─────────────────────────────────
create function private.trg_leads_zz_sello_base_gestion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return new;  -- migraciones y jobs internos, como el trigger «solo núcleo» de actividades
  end if;
  if coalesce(pg_catalog.current_setting('crm.op_base_gestion', true), 'off') = 'on' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.reactivado_en is not null or new.enfriado_hasta is not null then
      raise exception 'reactivado_en y enfriado_hasta los escribe solo la base para gestion (su nucleo)'
        using errcode = '42501';
    end if;
  elsif new.reactivado_en is distinct from old.reactivado_en
     or new.enfriado_hasta is distinct from old.enfriado_hasta then
    raise exception 'reactivado_en y enfriado_hasta los escribe solo la base para gestion (su nucleo)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
alter function private.trg_leads_zz_sello_base_gestion() owner to postgres;
revoke all on function private.trg_leads_zz_sello_base_gestion() from public, anon, authenticated, service_role;
comment on function private.trg_leads_zz_sello_base_gestion() is
  'Base para gestión (B1): sello de las columnas reactivado_en y enfriado_hasta de crm.leads. Las acepta solo bajo el GUC de transacción crm.op_base_gestion=on (núcleos de B3/B4 y puerta de Gerencia) o sin usuario (migraciones). DEFINER por el mismo molde que trg_actividades_resultado_solo_nucleo y trg_leads_no_contactar_solo_puerta (INVOKER también valdría): cerrado con search_path vacío, dueño postgres y sin EXECUTE para la API; no lee tablas, no amplía ámbito.';

create trigger trg_leads_zz_sello_base_gestion
  before insert or update of reactivado_en, enfriado_hasta on crm.leads
  for each row execute function private.trg_leads_zz_sello_base_gestion();

-- ── 5. Permisos ──────────────────────────────────────────────────────────────────────────────
grant select (reactivado_en, enfriado_hasta) on crm.leads to authenticated, service_role;

do $postflight$
declare
  v_uid constant uuid := '0b0a5e00-0000-4000-8000-00000000b1b1';
  v_lead uuid;
begin
  -- 1. Columnas: tipo exacto, NULL admitido, con comentario; lectura por columna para authenticated,
  --    sin INSERT/UPDATE por columna para nadie de la API.
  if (
    (select data_type from information_schema.columns where table_schema = 'crm' and table_name = 'leads'
       and column_name = 'reactivado_en') = 'timestamp with time zone'
    and (select data_type from information_schema.columns where table_schema = 'crm' and table_name = 'leads'
       and column_name = 'enfriado_hasta') = 'date'
    and (select bool_and(is_nullable = 'YES') from information_schema.columns
          where table_schema = 'crm' and table_name = 'leads' and column_name in ('reactivado_en', 'enfriado_hasta'))
    and (select count(*) from pg_description d join pg_attribute a on a.attrelid = d.objoid and a.attnum = d.objsubid
          where d.objoid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta')) = 2
    and has_column_privilege('authenticated', 'crm.leads', 'reactivado_en', 'SELECT')
    and has_column_privilege('authenticated', 'crm.leads', 'enfriado_hasta', 'SELECT')
    and not has_column_privilege('anon', 'crm.leads', 'reactivado_en', 'SELECT')
    and not has_column_privilege('anon', 'crm.leads', 'enfriado_hasta', 'SELECT')
    -- ACL POR COLUMNA (pg_attribute.attacl), como 20260919211105: exactamente SELECT para authenticated y
    -- service_role en cada columna y nada más. (information_schema.column_privileges expande el grant de
    -- TABLA a cada columna y daría falso rojo en producción; auditor-rls B1, P1.)
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta')) = 4
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta')
            and e.privilege_type = 'SELECT' and not e.is_grantable
            and e.grantee in ('authenticated'::regrole, 'service_role'::regrole)) = 4
  ) is not true then
    raise exception 'POSTFLIGHT: columnas, comentarios o ACL por columna no quedaron como se esperaba';
  end if;
  -- 2. CHECK validado y función de constantes con su contrato (INVOKER, IMMUTABLE, postgres, sin EXECUTE
  --    para la API) y sus valores.
  if (
    exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass
             and conname = 'actividades_intento_base_forma' and convalidated)
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.base_gestion_constantes()')
                 and not p.prosecdef and p.provolatile = 'i' and p.proowner = 'postgres'::regrole
                 and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.base_gestion_constantes()', 'EXECUTE')
    and not has_function_privilege('anon', 'private.base_gestion_constantes()', 'EXECUTE')
    and (select (c.max_intentos, c.dias_enfriamiento) = (3, 30) from private.base_gestion_constantes() c)
  ) is not true then
    raise exception 'POSTFLIGHT: CHECK no validado o constantes sin el contrato/valores esperados';
  end if;
  -- 3. Sello: trigger BEFORE INSERT OR UPDATE, habilitado, sobre las dos columnas; función DEFINER, postgres,
  --    search_path vacío, sin EXECUTE para la API.
  if (
    exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass
             and t.tgname = 'trg_leads_zz_sello_base_gestion' and t.tgenabled = 'O'
             and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4 and (t.tgtype & 16) = 16
             and t.tgfoid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()'))
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()')
                 and p.prosecdef and p.proowner = 'postgres'::regrole
                 and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.trg_leads_zz_sello_base_gestion()', 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: el sello de base_gestion no quedo BEFORE INSERT/UPDATE habilitado con su contrato';
  end if;
  -- 4. Negativos del CHECK (cada uno en su sub-bloque: el error esperado deshace el intento).
  select l.id into v_lead from crm.leads l
   where l.activo and l.etapa not in ('convertido', 'descartado') order by l.creado_en limit 1;
  if v_lead is not null then
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"interesado","intento_n":"1","ciclo_n":"1"}');
      raise exception 'POSTFLIGHT: el CHECK acepto un resultado fuera del catalogo' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1"}');
      raise exception 'POSTFLIGHT: el CHECK acepto volver_a_llamar sin tarea_id' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"no_contesto","ciclo_n":"1"}');
      raise exception 'POSTFLIGHT: el CHECK acepto un intento sin intento_n' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","intento_n":"1","ciclo_n":"1","tarea_id":"11111111-2222-4333-8444-555555555555"}');
      raise exception 'POSTFLIGHT: el CHECK acepto un intento SIN resultado (trampa NULL)' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    -- 5. Sello: con usuario y sin el GUC, 42501; con el GUC, pasa (y se deshace).
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      update crm.leads set enfriado_hasta = current_date where id = v_lead;
      raise exception 'POSTFLIGHT: el sello dejo escribir enfriado_hasta sin el GUC' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm not like '%base para gestion%' then
        raise exception 'POSTFLIGHT: otro 42501 se adelanto al sello: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
      update crm.leads set enfriado_hasta = current_date, reactivado_en = now() where id = v_lead;
      if not exists (select 1 from crm.leads where id = v_lead and enfriado_hasta = current_date and reactivado_en is not null) then
        raise exception 'POSTFLIGHT: con el GUC el sello no dejo escribir' using errcode = 'P0001';
      end if;
      raise exception 'DESHACER' using errcode = 'ZZ0B1';
    exception when sqlstate 'ZZ0B1' then
      perform pg_catalog.set_config('crm.op_base_gestion', 'off', true);
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    if exists (select 1 from crm.leads where id = v_lead and (enfriado_hasta is not null or reactivado_en is not null)) then
      raise exception 'POSTFLIGHT: el ensayo del sello no se deshizo';
    end if;
  else
    raise notice 'base_gestion_esquema: sin leads en esta base; negativos del CHECK y del sello NO RUN';
  end if;
  raise notice 'base_gestion_esquema OK: reactivado_en y enfriado_hasta (solo lectura por API, sello activo), CHECK intento_base validado, constantes 3/30';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

## Transcripción 2 · supabase/migrations/20261002061500_crm_base_gestion_no_contactar_supervisor.sql
```sql
-- 20261002061500_crm_base_gestion_no_contactar_supervisor.sql
--
-- Base para gestión del analista · B2 (permisos). Decisión D5 de Miguel (02/10/2026): «quitar No contactar» pasa de
-- «solo Gerencia» a «Gerencia o Supervisión dentro de su ámbito». Plan B2 confirmado por Miguel el 02/10 («vamos si»),
-- incluida la regla «todos los leads de la persona en su equipo». Nota del vault: «Base para gestion del analista -
-- F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- QUÉ. `crm.levantar_no_contactar(uuid, text)` (texto vivo 20260906160000, md5 prosrc 3840a73f…) gana tres cosas y
--   nada más, por sustituciones exactas sobre el texto vivo (no se reteclea):
--   1. Gate: `v_rol in ('supervisor','gerencia')` (con `v_rol is null` rechazando). Analistas, coordinación y directorio: 42501.
--   2. Ámbito de Supervisión: ANTES de resolver la identidad o tomar candados, el lead pedido debe estar en su ámbito
--      (espejo de la policy `leads_select` sin la rama de gerencia) → si no, P0002 «no encontrado o fuera de tu ámbito»
--      (no revela si existe). Bajo candado se revalida y, además, TODOS los leads de la persona que se van a tocar
--      (`v_leads`: enlace ∪ puente ∪ sueltos ∪ el propio) deben estar en su equipo; si alguno es de otro equipo →
--      42501 «La persona tiene leads fuera de tu equipo: pídelo a Gerencia». La Ley 29571 trata el veto por persona:
--      Supervisión no puede levantar un veto que alcanza leads que no gestiona.
--   3. Historial: la actividad dice «por Gerencia» o «por Supervisión» y lleva `rol` en la metadata.
--   La resolución de identidad, los candados (documentos → persona → leads), las 40001 y la escritura bajo
--   `crm.op_privilegiada` quedan byte a byte como estaban. El motivo sigue siendo obligatorio.
--
-- QUÉ NO CAMBIA. `crm.marcar_no_contactar` (sellada por huella en assert_gestion_diaria_resultado) no se toca. La
--   función NO está fijada por ningún `private.assert_*` (solo anclas puntuales en 20260904130000 y 20260906200000,
--   que ya corrieron). ACL: se reafirma EXECUTE solo para `authenticated` (dueño postgres). RLS y policies intactas.
--   Para el analista no cambia nada: la RLS vigente ya limita lectura y escritura a sus propios leads, actividades y
--   tareas (B2 lo demuestra con `supabase/scripts/base-gestion/b2-rls.sql`, sin migración).
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-no-contactar-supervisor.sql`: reinstala el texto vivo byte a byte
--   (md5 3840a73f…), reafirma la ACL y el comentario. No toca datos (los levantamientos hechos por Supervisión quedan
--   en el historial con su `rol`).
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    to_regprocedure('crm.levantar_no_contactar(uuid,text)') is not null
    and (select count(*) from pg_proc where proname = 'levantar_no_contactar' and pronamespace = 'crm'::regnamespace) = 1
    and (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)')) = '3840a73fc3a1db8f27ea921fad1bd65a'
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.levantar_no_contactar(uuid,text)')
                 and p.prosecdef and p.proconfig = array['search_path=""']::text[])
    and to_regprocedure('private.vendedor_ids_visibles(uuid)') is not null
    and to_regprocedure('private.rol_crm(uuid)') is not null
  ) is not true then
    raise exception 'PREFLIGHT: crm.levantar_no_contactar no es el texto vivo auditado (3840a73f…), tiene otra firma o faltan sus ayudantes';
  end if;
end;
$preflight$;

create or replace function crm.levantar_no_contactar(p_lead_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean;
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
  v_puente boolean := false;  -- F2.b [D-3]: la persona se resolvió por el PUENTE (lead histórico sin DNI ni enlace)
  v_leads  uuid[];            -- F2.b [D-3]: enlace vivo ∪ puente ∪ sueltos con su documento, más el propio lead
  v_docs   text[];            -- F2.b [D-3]: documentos vigentes de la persona, bloqueados ANTES que ella (tipo:documento)
  v_perfiles uuid[] := array[]::uuid[];  -- F2.b [D-3]: perfiles cliente de la persona (enlazado o con su documento): tareas de cliente
begin
  -- B2 · Base para gestión (D5, Miguel 02/10/2026): Gerencia o Supervisión. Supervisión solo dentro de su ámbito y
  -- solo si TODA la persona (sus leads) cae en su equipo; si no, lo pide a Gerencia. `v_rol is null` también rechaza.
  if v_uid is null or v_rol is null or v_rol not in ('supervisor', 'gerencia') then
    raise exception 'Solo Gerencia o Supervisión pueden levantar No contactar' using errcode = '42501';
  end if;
  if p_motivo is null or pg_catalog.btrim(p_motivo) = '' then
    raise exception 'Levantar No contactar exige un motivo' using errcode = '22023';
  end if;
  -- Ámbito ANTES de resolver la identidad o tomar candados (el espejo de la policy leads_select, sin la rama de gerencia).
  if v_rol = 'supervisor' and not exists (
       select 1 from crm.leads l
        where l.id = p_lead_id
          and (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
               or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);

  -- ORDEN: identidad PRIMERO, luego leads.
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b [D-3] (Codex #7): un lead que solo está en el PUENTE (histórico sin DNI ni enlace vivo) también es de su
    -- persona: se resuelve por el puente (canónica) antes de intentar el documento. El puente solo cambia bajo el lock
    -- de la persona (fusión), que se toma más abajo y se revalida tras bloquear el lead.
    select private.inversionista_canonica(il.inversionista_id) into v_inv
    from crm.inversionista_leads il
    where il.lead_id = p_lead_id
    order by (il.rol = 'canonico') desc, il.inversionista_id
    limit 1;
    v_puente := v_inv is not null;
  end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    -- F2.b [D-3] (auditor M1): DOCUMENTO → PERSONA, el orden del nacimiento (b1), la puerta del DNI (D-13) y la fusión (b5):
    -- se bloquean los documentos vigentes de la persona (en orden de texto) ANTES de bloquearla, y se releen después;
    -- así la puerta del DNI (que solo bloquea documentos y a la persona NUEVA) no puede llevarse un suelto a otra persona
    -- mientras el veto se propaga. Si el juego de documentos cambió mientras se esperaba → 40001.
    v_docs := private.identidad_bloquear_documentos_de(array[v_inv]);
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- La relectura es una LECTURA PURA (Codex N3): no vuelve a tomar candados con la persona ya bloqueada (documento → persona).
    if (select coalesce(pg_catalog.array_agg(s.k order by s.k), '{}'::text[])
          from (select distinct d.tipo_documento || ':' || d.documento_normalizado as k
                  from crm.inversionista_identificadores d
                 where d.inversionista_id = v_inv and d.estado = 'vigente') s) is distinct from v_docs then
      raise exception 'Los documentos de la persona cambiaron mientras se marcaba; vuelve a intentarlo'
        using errcode = '40001';
    end if;
    -- F2.b [D-3] (Codex #12): el motivo no lleva NINGÚN documento de la persona (vigentes ni históricos; la regla documental
    -- de las puertas de b5, sin imponer aquí su largo mínimo: el motivo de marcar es opcional).
    if p_motivo is not null and exists (
         select 1 from crm.inversionista_identificadores d
          where d.inversionista_id = v_inv
            and pg_catalog.length(d.documento_normalizado) >= 6
            and pg_catalog.strpos(pg_catalog.upper(pg_catalog.regexp_replace(p_motivo, '[^A-Za-z0-9]', '', 'g')), d.documento_normalizado) > 0) then
      raise exception 'El motivo no debe contener el número de documento' using errcode = '22023';
    end if;
  end if;
  -- F2.b [D-3]: bajo los locks de documentos y persona, «sus leads» = enlace vivo ∪ puente ∪ sueltos con su documento
  -- verificado (private.leads_de_persona_veto) más el propio lead; y sus perfiles cliente (el enlazado a la identidad o
  -- el que lleva su documento exacto, como persona_vetada_perfil) para las tareas de cliente. Estable hasta el commit.
  if v_inv is not null then
    v_leads := array(select x from private.leads_de_persona_veto(v_inv) x union select p_lead_id order by 1);
    v_perfiles := array(
      select i.perfil_id from crm.inversionistas i where i.id = v_inv and i.perfil_id is not null
      union
      select p.id from public.perfiles p
       where p.rol = 'cliente'
         and nullif(pg_catalog.btrim(coalesce(p.dni, '')), '') is not null
         and (coalesce(nullif(pg_catalog.btrim(p.tipo_documento), ''), 'DNI') || ':' || pg_catalog.upper(pg_catalog.regexp_replace(p.dni, '[^A-Za-z0-9]', '', 'g'))) = any(v_docs)
      order by 1);
  else
    v_leads := array[p_lead_id];
  end if;
  -- F2.b [D-3] (Codex #1): tareas → leads es el orden de b2 y de cerrar_tarea; derivar y repartir van al revés (lead →
  -- tareas por el trigger de sincronización). Como la fusión (b5, E3-9): los leads se toman SIN esperar; si otra sesión
  -- tiene uno, 40001 y el front reintenta. Solo con la bandera (con OFF no hay tareas bloqueadas: el propio lead se toma como hoy).
  if v_flag then
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id for update;
  if not found then
    raise exception 'Lead no encontrado' using errcode = 'P0002';
  end if;
  -- B2 (D5): bajo candado, el ámbito se revalida y se exige para TODOS los leads de la persona que se van a tocar.
  if v_rol = 'supervisor' then
    if not (v_lead.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
            or (v_lead.vendedor_id is null and v_lead.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))) then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode = 'P0002';
    end if;
    if exists (select 1 from crm.leads l
                where l.id = any(v_leads)
                  and not (l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
                           or (l.vendedor_id is null and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid))))) then
      raise exception 'La persona tiene leads fuera de tu equipo: pídelo a Gerencia' using errcode = '42501';
    end if;
  end if;
  if v_flag and not v_suelto and not v_puente and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se levantaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_puente
     and (v_lead.inversionista_id is not null
          or not exists (select 1 from crm.inversionista_leads il
                         where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) = v_inv)) then
    raise exception 'El puente del lead cambió mientras se levantaba; vuelve a intentarlo'
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
      select * from crm.leads where id = any(v_leads) order by id for update  -- F2.b [D-3]: enlace ∪ puente ∪ sueltos
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
  values (p_lead_id, 'nota', 'Levantado No contactar por ' || case when v_rol = 'gerencia' then 'Gerencia' else 'Supervisión' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'levantar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', pg_catalog.btrim(p_motivo), 'rol', v_rol),
          v_uid);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$;
alter function crm.levantar_no_contactar(uuid, text) owner to postgres;
revoke all on function crm.levantar_no_contactar(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.levantar_no_contactar(uuid, text) to authenticated;
comment on function crm.levantar_no_contactar(uuid, text) is
  'Levanta No contactar (Ley 29571) de la persona del lead y de todos sus leads. Gerencia en toda la operación; Supervisión (B2, D5 02/10/2026) solo si el lead y TODOS los leads de la persona están en su equipo (si no, 42501: pídelo a Gerencia). Motivo obligatorio; queda en el historial con el rol. DEFINER: compone la identidad y escribe bajo crm.op_privilegiada; search_path vacío, dueño postgres, EXECUTE solo authenticated.';

do $postflight$
declare
  f constant text := 'crm.levantar_no_contactar(uuid,text)';
  v_src text;
  v_vend uuid;
  v_sup uuid;
  v_lead uuid;
begin
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure(f);
  -- 1. Cuerpo ENSAYADO (md5 medido en el banco), contrato intacto, ACL exacta.
  if (
    md5(v_src) = '2467b5068fc814ce42f18596d740ebcb'
    and v_src like '%Solo Gerencia o Supervisión pueden levantar No contactar%'
    and v_src like '%pídelo a Gerencia%'
    and v_src like '%''rol'', v_rol%'
    and (select count(*) from pg_proc where proname = 'levantar_no_contactar' and pronamespace = 'crm'::regnamespace) = 1
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure(f) and p.prosecdef
                 and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and has_function_privilege('authenticated', f, 'EXECUTE')
    and not has_function_privilege('anon', f, 'EXECUTE')
    and not has_function_privilege('service_role', f, 'EXECUTE')
    and not exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = to_regprocedure(f)
                     and (a.grantee not in ('postgres'::regrole, 'authenticated'::regrole)
                          or (a.grantee = 'authenticated'::regrole and (a.is_grantable or a.privilege_type <> 'EXECUTE'))))
  ) is not true then
    raise exception 'POSTFLIGHT: levantar_no_contactar no quedo con el cuerpo ensayado, el contrato DEFINER/postgres/search_path vacio o la ACL exacta';
  end if;
  -- 2. Negativos sin escribir (cada uno falla ANTES de tocar datos; se deshacen igual por sub-bloque).
  select e.perfil_id into v_vend from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'vendedor' and e.activo and p.activo order by e.perfil_id limit 1;
  select l.id into v_lead from crm.leads l where l.activo order by l.creado_en limit 1;
  if v_vend is not null and v_lead is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform crm.levantar_no_contactar(v_lead, 'postflight');
      raise exception 'POSTFLIGHT: un analista pudo llamar a levantar_no_contactar' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm not like 'Solo Gerencia o Supervisi%' then
        raise exception 'POSTFLIGHT: el analista fue rechazado por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
    end;
  else
    raise notice 'base_gestion B2: sin analista o lead activo en esta base; negativo del analista NO RUN';
  end if;
  -- Supervisión fuera de ámbito: un supervisor y un lead cuyo vendedor NO está en su subárbol (si existe el par).
  select e.perfil_id into v_sup from crm.equipo e join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'supervisor' and e.activo and p.activo order by e.perfil_id limit 1;
  if v_sup is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
      select l.id into v_lead from crm.leads l
       where l.activo and l.vendedor_id is not null
         and l.vendedor_id not in (select private.vendedor_ids_visibles(v_sup))
       order by l.creado_en limit 1;
      if v_lead is null then
        perform pg_catalog.set_config('request.jwt.claims', '', true);
        perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
        raise notice 'base_gestion B2: el primer supervisor ve todos los leads de esta base; negativo fuera de ambito NO RUN';
      else
        perform crm.levantar_no_contactar(v_lead, 'postflight');
        raise exception 'POSTFLIGHT: Supervision levanto fuera de su ambito' using errcode = 'P0001';
      end if;
    exception when no_data_found then
      if sqlerrm not like '%fuera de tu %mbito%' then
        raise exception 'POSTFLIGHT: Supervision fuera de ambito fue rechazada por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
      perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
    end;
  end if;
  raise notice 'base_gestion_no_contactar_supervisor OK: gate Gerencia|Supervision, ambito por persona, historial con rol, ACL exacta';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

## Transcripción 3 · supabase/scripts/base-gestion/b2-rls.sql (pruebas de permisos en banco; resultado 20/20 PASS)
```sql
-- B2 · Pruebas de permisos en el banco, bajo rol `authenticated` con impersonación (ambas formas del claim).
-- Toda la corrida va en UNA transacción que termina en ROLLBACK: no deja rastro. Una línea por caso: PASS/FAIL.
-- Nunca llamar bajo `set role` a una función sin EXECUTE para authenticated (cuelga PG 17.6).
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
-- Actores y leads de fixtures-b2.sql
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid as a, 'b0000000-0000-4000-8000-000000000012'::uuid as b,
  'b0000000-0000-4000-8000-000000000013'::uuid as c, 'b0000000-0000-4000-8000-000000000001'::uuid as s1,
  'b0000000-0000-4000-8000-000000000011'::uuid as s2, 'b0000000-0000-4000-8000-000000000003'::uuid as g,
  'b0000000-0000-4000-8000-0000000000a1'::uuid as la, 'b0000000-0000-4000-8000-0000000000b1'::uuid as lb,
  'b0000000-0000-4000-8000-0000000000c1'::uuid as lc, 'b0000000-0000-4000-8000-0000000000a2'::uuid as la_veto,
  'b0000000-0000-4000-8000-0000000000d1'::uuid as ld;
grant select on f to authenticated;

-- ───────── Analista A ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'A lee su descartado LA', '1', count(*)::text from crm.leads, f where id = f.la;
insert into r(caso, esperado, obtenido) select 'A NO lee LB (mismo equipo) ni LC (otro equipo)', '0', count(*)::text from crm.leads, f where id in (f.lb, f.lc);
insert into r(caso, esperado, obtenido) select 'A ve enfriado_hasta/reactivado_en de LA (NULL,NULL)', 'ok', case when count(*) = 1 then 'ok' else 'sin fila' end from (select enfriado_hasta, reactivado_en from crm.leads, f where id = f.la) q;
do $$ declare n int; begin update crm.leads set nota = 'B2 nota A' where id = (select la from f); get diagnostics n = row_count; insert into r(caso,esperado,obtenido) values ('A edita nota en LA', '1', n::text); end $$;
do $$ declare n int; begin update crm.leads set nota = 'B2 intruso' where id = (select lb from f); get diagnostics n = row_count; insert into r(caso,esperado,obtenido) values ('A NO edita LB (0 filas)', '0', n::text); end $$;
do $$ begin insert into crm.actividades (lead_id, tipo, detalle, creado_por) select la, 'nota', 'B2 nota A', a from f; insert into r(caso,esperado,obtenido) values ('A registra actividad en LA', 'ok', 'ok'); exception when others then insert into r(caso,esperado,obtenido) values ('A registra actividad en LA', 'ok', sqlstate); end $$;
do $$ begin insert into crm.actividades (lead_id, tipo, detalle, creado_por) select lb, 'nota', 'B2 intruso', a from f; insert into r(caso,esperado,obtenido) values ('A NO registra actividad en LB', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO registra actividad en LB', '42501', sqlstate); end $$;
insert into r(caso, esperado, obtenido) select 'A lee la actividad de LA, no la de LB', '1/0', (select count(*) from crm.actividades, f where lead_id = f.la and detalle = 'B2 nota A')::text || '/' || (select count(*) from crm.actividades, f where lead_id = f.lb)::text;
do $$ begin update crm.leads set enfriado_hasta = current_date where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO escribe enfriado_hasta (sello)', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO escribe enfriado_hasta (sello)', '42501', sqlstate); end $$;
do $$ begin update crm.leads set vendedor_id = (select b from f) where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO reasigna LA', 'error', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO reasigna LA', 'error', 'error ' || sqlstate); end $$;
do $$ begin update crm.leads set etapa = 'nuevo', motivo_descarte = null where id = (select la from f); insert into r(caso,esperado,obtenido) values ('A NO reabre LA por UPDATE (solo por puerta)', 'P0409', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO reabre LA por UPDATE (solo por puerta)', 'P0409', sqlstate); end $$;
do $$ begin perform crm.levantar_no_contactar((select la_veto from f), 'intento'); insert into r(caso,esperado,obtenido) values ('A NO levanta no_contactar', '42501', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('A NO levanta no_contactar', '42501', sqlstate); end $$;
reset role;
-- ───────── Analista B (mismo equipo que A) ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'B NO lee LA (mismo supervisor no basta)', '0', count(*)::text from crm.leads, f where id = f.la;
insert into r(caso, esperado, obtenido) select 'B lee su LB', '1', count(*)::text from crm.leads, f where id = f.lb;
reset role;
-- ───────── Supervisor 1 (equipo de A y B) ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
insert into r(caso, esperado, obtenido) select 'S1 lee LA y LB, no LC', '2/0', (select count(*) from crm.leads, f where id in (f.la, f.lb))::text || '/' || (select count(*) from crm.leads, f where id = f.lc)::text;
do $$ begin perform crm.levantar_no_contactar((select lc from f), 'fuera'); insert into r(caso,esperado,obtenido) values ('S1 NO levanta en LC (otro equipo)', 'P0002', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('S1 NO levanta en LC (otro equipo)', 'P0002', sqlstate); end $$;
do $$ declare j jsonb; begin j := crm.levantar_no_contactar((select la_veto from f), 'cliente pidió volver'); insert into r(caso,esperado,obtenido) values ('S1 levanta LA_VETO (persona con LD en equipo 2 por mismo DNI)', 'ok o 42501', 'ok leads=' || (j->>'leads_afectados')); exception when others then insert into r(caso,esperado,obtenido) values ('S1 levanta LA_VETO (persona con LD en equipo 2 por mismo DNI)', 'ok o 42501', sqlstate || ' ' || left(sqlerrm, 60)); end $$;
reset role;
-- ───────── Supervisor 2 (equipo de C) ─────────
select pg_temp.sesion((select s2 from f)); set local role authenticated;
do $$ begin perform crm.levantar_no_contactar((select la_veto from f), 'ajeno'); insert into r(caso,esperado,obtenido) values ('S2 NO levanta LA_VETO (de A, equipo 1)', 'P0002', 'paso'); exception when others then insert into r(caso,esperado,obtenido) values ('S2 NO levanta LA_VETO (de A, equipo 1)', 'P0002', sqlstate); end $$;
reset role;
-- ───────── Gerencia ─────────
select pg_temp.sesion((select g from f)); set local role authenticated;
do $$ declare j jsonb; begin j := crm.levantar_no_contactar((select ld from f), 'gerencia levanta'); insert into r(caso,esperado,obtenido) values ('G levanta LD', 'ok', 'ok leads=' || (j->>'leads_afectados')); exception when others then insert into r(caso,esperado,obtenido) values ('G levanta LD', 'ok', sqlstate || ' ' || left(sqlerrm, 60)); end $$;
insert into r(caso, esperado, obtenido) select 'historial dice por Gerencia con rol', 'ok', case when exists (select 1 from crm.actividades, f where lead_id = f.ld and detalle = 'Levantado No contactar por Gerencia' and metadata->>'rol' = 'gerencia') then 'ok' else 'falta' end;
reset role;
-- ───────── Resultado ─────────
update r set ok = case when esperado = 'ok o 42501' then obtenido like 'ok%' or obtenido like '42501%'
                       when esperado = 'error' then obtenido like 'error%'
                       when esperado = 'ok' then obtenido like 'ok%'
                       else obtenido = esperado end;
select format('%s %s · esperado %s · obtenido %s', case when ok then 'PASS' else 'FAIL' end, caso, esperado, obtenido) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where not ok)) from r;
rollback;
```

Resultado de b2-rls.sql en el banco (ACL del banco copiada del stack local = producción): 20 PASS · 0 FAIL. Nota: el
caso «S1 levanta LA_VETO (persona con LD en equipo 2 por mismo DNI)» devolvió `ok leads=1`: dos leads sueltos con el
mismo DNI NO forman persona sin `inversionista`, así que la regla «todos los leads de la persona en su equipo» solo
se ejercitó trivialmente (v_leads = [p_lead_id]). Falta un fixture con persona enlazada (B3 o rama).

## Transcripción 4 · casos añadidos a supabase/scripts/test-rls.mjs
```js
// ── Base para gestión del analista · B1 (20261002054402): columnas selladas y CHECK del intento ──
// Qué prueba: (1) nadie escribe reactivado_en / enfriado_hasta por PATCH, ni el dueño ni su supervisor ni
// gerencia (sello 42501); (2) un PATCH no-op con el mismo valor NULL pasa, para que los parches parciales del
// drawer no se rompan; (3) las dos columnas viajan por la API (la falla silenciosa conocida de los grants por
// columna); (4) un INSERT de actividad con evento intento_base desde la API muere en el trigger «solo núcleo»
// si trae claves reservadas (42501) y en el CHECK si no trae resultado (23514); (5) fuera de banda, el
// contrato del sello y de las constantes y la ACL por columna (pg_attribute.attacl, no column_privileges).
// Salto RUIDOSO si la migración no está en esta base; con CRM_RLS_EXIGE_BASE_GESTION=1 es un FALLO.
async function testBaseGestionB1(sessions, seed) {
  console.log('\n— Base para gestión B1: reactivado_en / enfriado_hasta selladas y CHECK intento_base —');
  const saltar = (msg) => {
    if (process.env.CRM_RLS_EXIGE_BASE_GESTION === '1') fail(msg);
    else console.log(`  ${msg}`);
  };
  let aplicada;
  try {
    aplicada = contarFueraDeBanda('base gestión: esquema aplicado',
      `select (to_regprocedure('private.base_gestion_constantes()') is not null and exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'enfriado_hasta'))::int`);
  } catch (error) {
    saltar(`⚠ Base para gestión B1 SALTADO: sin vía fuera de banda (${error?.message ?? String(error)})`);
    return;
  }
  if (aplicada !== 1) {
    saltar('⚠ 20261002054402 (base gestión B1) NO desplegada en esta base: bloque SALTADO (no probado)');
    return;
  }
  const idDe = (clave) => seed.leadByName.get(LEAD_BY_KEY[clave].name)?.id;
  const SELLO = /base para gestion/i;
  const hoy = new Date().toISOString().slice(0, 10);
  const patch = (cliente, clave, cambios) => cliente.schema('crm').from('leads').update(cambios).eq('id', idDe(clave)).select('id');
  // (1) Sello: 42501 para dueño, supervisor del subárbol y gerencia, en las dos columnas.
  await expectExpectedFailure('B1 vend1 PATCH enfriado_hasta en su lead (juan) → 42501', patch(sessions.vend1.client, 'juan', { enfriado_hasta: hoy }), ['42501'], SELLO);
  await expectExpectedFailure('B1 vend1 PATCH reactivado_en en su lead (juan) → 42501', patch(sessions.vend1.client, 'juan', { reactivado_en: new Date().toISOString() }), ['42501'], SELLO);
  await expectExpectedFailure('B1 sup1 PATCH enfriado_hasta en lead de su subárbol (carlos) → 42501', patch(sessions.sup1.client, 'carlos', { enfriado_hasta: hoy }), ['42501'], SELLO);
  await expectExpectedFailure('B1 gerencia PATCH enfriado_hasta (juan) → 42501', patch(sessions.gerencia.client, 'juan', { enfriado_hasta: hoy }), ['42501'], SELLO);
  // (2) No-op: mismo valor NULL → pasa (los parches parciales del drawer siguen funcionando).
  await positive('B1 vend1 PATCH enfriado_hasta: null sobre NULL → 200 (no-op)', patch(sessions.vend1.client, 'juan', { enfriado_hasta: null }));
  // (3) Las columnas viajan por la API.
  const sel = await positive('B1 vend1 SELECT id, enfriado_hasta, reactivado_en (juan)',
    sessions.vend1.client.schema('crm').from('leads').select('id, enfriado_hasta, reactivado_en').eq('id', idDe('juan')).single());
  assertions += 1;
  if (sel?.data && 'enfriado_hasta' in sel.data && 'reactivado_en' in sel.data) console.log('  ✓ B1 enfriado_hasta y reactivado_en viajan por la API');
  else fail('B1: la API no devolvió enfriado_hasta / reactivado_en (grant por columna ausente)');
  // (4) El intento de la base no se forja desde la API.
  const actividad = (metadata) => sessions.vend1.client.schema('crm').from('actividades').insert({
    creado_por: sessions.vend1.user.id, detalle: 'B1 TRANSIENT', lead_id: idDe('juan'), tipo: 'nota', metadata,
  }).select('id');
  await expectExpectedFailure('B1 vend1 INSERT actividad intento_base con resultado → 42501 (claves del núcleo)',
    actividad({ evento: 'intento_base', resultado: 'no_contesto', intento_n: 1, ciclo_n: 1 }), ['42501'], /solo lo escribe/i);
  await expectExpectedFailure('B1 vend1 INSERT actividad intento_base sin resultado → 23514 (CHECK)',
    actividad({ evento: 'intento_base', ciclo_n: 1 }), ['23514'], /actividades_intento_base_forma/i);
  // (5) Fuera de banda: contrato del sello, constantes y ACL por columna.
  const cuenta = (etiqueta, sql) => contarFueraDeBanda(`base gestión: ${etiqueta}`, sql);
  check(cuenta('sello definer', `select count(*) from pg_proc p where p.oid = 'private.trg_leads_zz_sello_base_gestion()'::regprocedure and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]`) === 1,
    'B1 el sello es DEFINER de postgres con search_path vacío');
  check(cuenta('sin execute API', `select count(*) from unnest(array['anon','authenticated','service_role']) r(rol) where has_function_privilege(r.rol, 'private.trg_leads_zz_sello_base_gestion()', 'EXECUTE') or has_function_privilege(r.rol, 'private.base_gestion_constantes()', 'EXECUTE')`) === 0,
    'B1 sello y constantes sin EXECUTE para la API');
  check(cuenta('trigger', `select count(*) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion' and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4 and (t.tgtype & 16) = 16`) === 1,
    'B1 trigger del sello BEFORE INSERT OR UPDATE, habilitado');
  check(cuenta('anon', `select (has_column_privilege('anon', 'crm.leads', 'enfriado_hasta', 'SELECT') or has_column_privilege('anon', 'crm.leads', 'reactivado_en', 'SELECT'))::int`) === 0,
    'B1 anon no lee las columnas nuevas');
  check(cuenta('acl por columna', `select count(*) from pg_attribute a, aclexplode(a.attacl) e where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta') and e.privilege_type in ('INSERT', 'UPDATE') and e.grantee in ('anon'::regrole, 'authenticated'::regrole)`) === 0,
    'B1 sin INSERT/UPDATE por columna para la API (pg_attribute.attacl)');
  check(cuenta('constantes', `select (c.max_intentos = 3 and c.dias_enfriamiento = 30)::int from private.base_gestion_constantes() c`) === 1,
    'B1 constantes de negocio 3 intentos / 30 días');
  check(cuenta('check validado', `select count(*) from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated`) === 1,
    'B1 CHECK actividades_intento_base_forma validado');
}

    // B2 · Base para gestión (20261002061500, D5): Supervisión levanta dentro de su equipo; fuera, P0002; otros roles 42501.
    await positive('#5 B2 re-marcar para probar Supervisión',
      sessions.vend1.client.schema('crm').rpc('marcar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'supervision' }));
    await expectExpectedFailure('#5 B2 sup2 (otro equipo) no levanta → P0002 (no revela el lead)',
      sessions.sup2.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'ajeno' }), ['P0002'], /fuera de tu [aá]mbito/i);
    await expectExpectedFailure('#5 B2 coordinador no levanta → 42501',
      sessions.coordinador.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'coordina' }), ['42501'], /Gerencia o Supervisi/i);
    await expectExpectedFailure('#5 B2 sup1 sin motivo → 22023',
      sessions.sup1.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: ' ' }), ['22023'], /motivo/i);
    await positive('#5 B2 sup1 (su equipo) levanta CON motivo',
      sessions.sup1.client.schema('crm').rpc('levantar_no_contactar', { p_lead_id: IDS_IDENTIDAD.veto, p_motivo: 'cliente pidió volver (supervisión)' }));
    if (cuenta('veto levantado por supervisión', `select count(*) from crm.inversionistas where id in ${idsPorDoc(DOCS_IDENTIDAD.veto)} and not no_contactar`) !== 1) fail('#5 B2: supervisión no pudo levantar el veto de su equipo');
    if (cuenta('historial por Supervisión', `select count(*) from crm.actividades where lead_id = '${IDS_IDENTIDAD.veto}' and detalle = 'Levantado No contactar por Supervisión' and metadata->>'rol' = 'supervisor'`) !== 1) fail('#5 B2: el historial no dice «por Supervisión» con rol');
```

## Transcripción 5 · auditor-rls sobre B1 (ya aplicado)
P1 aceptado: el postflight usaba `information_schema.column_privileges` (expande el grant de tabla) → ahora
`pg_attribute.attacl` (4 entradas SELECT exactas). P2 aceptado: el CHECK pasaba un `intento_base` SIN `resultado`
(trampa NULL) → `coalesce` + negativo nuevo. P2 aceptado: matriz `test-rls.mjs` sin casos → bloque
`testBaseGestionB1`. P3 aplicados (SQLERRM filtrado, SQLSTATE propio `ZZ0B1`, lead vivo para el ensayo, textos).
Verificación tras los cambios: aplicar + postflight PASS, `test` 12/12, `reversa-y-reaplicar` PASS, typecheck,
check:scripts y test:rls:preflight PASS. Pendiente: rama de Supabase → `test-rls.mjs` real → advisors → merge.

## Pregunta de diseño para B3 (opinión acotada)
La rellamada («volver a llamar») iba a ser una tarea `llamada` en `crm.tareas` (D7), pero el trigger
`trg_tareas_before_insert` prohíbe tareas nuevas en leads cerrados, y `trg_leads_zz_sync_tareas` cancela las
pendientes al descartar: el esquema separa tareas de descartados a propósito (cola diaria y SLA). Opciones:
(a) tocar `trg_tareas_before_insert` para admitir `llamada` en descartados bajo un GUC de la base (las rellamadas
entrarían en la cola diaria y en el motor SLA; el trigger es del núcleo SLA operativo);
(b) la rellamada vive en el lead: columna sellada `crm.leads.proxima_llamada_en timestamptz` (la escribe el núcleo
del intento, se limpia al reactivar/no contactar) + la misma fecha en la metadata del intento; el CHECK pasa a
exigir `proxima_llamada_en` (no `tarea_id`) en `volver_a_llamar`; «Llamar hoy» ordena por esa columna. Sin tocar
SLA ni cola. Recomendación del PRIMARY: (b). ¿Ves un riesgo que no esté dicho?

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
