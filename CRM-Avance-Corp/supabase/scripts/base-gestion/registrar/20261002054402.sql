-- REGISTRO en supabase_migrations.schema_migrations de 20261002054402_crm_base_gestion_esquema.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 5e8774f26101e2ea9f170f6dafe07e1d).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_esquema_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.base_gestion_constantes()') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261002054402 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261002054402' and (coalesce(name, '') <> 'crm_base_gestion_esquema' or statements is distinct from array[$mig$-- 20261002054402_crm_base_gestion_esquema.sql
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
$mig$])) then
    raise exception 'REGISTRO: la versión 20261002054402 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261002054402', 'crm_base_gestion_esquema', array[$mig$-- 20261002054402_crm_base_gestion_esquema.sql
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
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261002054402' and name = 'crm_base_gestion_esquema' and cardinality(statements) = 1
                   and md5(statements[1]) = '5e8774f26101e2ea9f170f6dafe07e1d') then
    raise exception 'REGISTRO: la fila 20261002054402 / crm_base_gestion_esquema no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261002054402 / crm_base_gestion_esquema (1 sentencia: el archivo entero)';
end $post$;
commit;
