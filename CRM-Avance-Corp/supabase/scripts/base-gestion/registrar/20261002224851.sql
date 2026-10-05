-- REGISTRO en supabase_migrations.schema_migrations de 20261002224851_crm_base_gestion_proxima_llamada.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 f6cea9be895a9f34d6e428ff35957a70).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_proxima_llamada_registro'));
do $chk$
begin
  if (
    to_regclass('crm.idx_leads_base_rellamada') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261002224851 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261002224851' and (coalesce(name, '') <> 'crm_base_gestion_proxima_llamada' or statements is distinct from array[$mig$-- 20261002224851_crm_base_gestion_proxima_llamada.sql
--
-- Base para gestión del analista · B1b (esquema): la rellamada vive en el lead. Decisiones de Miguel del 02/10/2026:
-- D7-bis «agenda propia de la base» (aprobada: «Sí, así»), D11 «la rellamada puede agendarse como máximo 10 días
-- adelante», D12 «gana la rellamada: el lead descansa solo cuando el 3.º intento termina sin cita y sin rellamada».
-- Nota del vault: «Base para gestion del analista - F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- POR QUÉ. D7 (rellamada en `crm.tareas`) no es posible: `private.trg_tareas_before_insert` rechaza tareas nuevas en un
--   lead cerrado («El lead está cerrado: no admite tareas nuevas») y `trg_leads_zz_sync_tareas` cancela las pendientes al
--   descartar. El esquema separa tareas de descartados a propósito (cola diaria y SLA). La base lleva su propia agenda.
--
-- QUÉ.
--   1. `crm.leads.proxima_llamada_en timestamptz`: próxima rellamada acordada con el cliente desde la base. La escribe el
--      núcleo del intento (B3) cuando el resultado es `volver_a_llamar`; una nueva rellamada la sustituye; el siguiente
--      intento la consume; reactivar o vetar la limpia. Lectura por columna para la API; escritura solo bajo el sello.
--   2. El sello `trg_leads_zz_sello_base_gestion` cubre ahora las TRES columnas de la base (BEFORE INSERT OR UPDATE OF).
--      Mismo cuerpo y mismo GUC (`crm.op_base_gestion`); solo cambia la lista de columnas (función y trigger).
--   3. El CHECK `actividades_intento_base_forma` exige, cuando `resultado = 'volver_a_llamar'`, `proxima_llamada_en` en la
--      metadata con forma ISO-8601 con zona (antes exigía `tarea_id`, que ya no aplica). Se recrea `not valid` + `validate`.
--   4. `private.base_gestion_constantes()` gana `dias_max_rellamada = 10` (D11): la firma cambia (tres columnas), así que se
--      reemplaza con drop + create (nada depende de ella todavía). Sigue INVOKER, IMMUTABLE, sin EXECUTE para la API.
--   5. Índice parcial `idx_leads_base_rellamada (vendedor_id, proxima_llamada_en) where etapa = 'descartado' and
--      proxima_llamada_en is not null`: lo leen el bloque «Llamar hoy» y el contador del menú en cada carga; solo indexa los
--      descartados con rellamada (decenas de filas). Se confirma con EXPLAIN en la rama con datos.
--
-- QUÉ NO CAMBIA. Ningún dato (columna nueva NULL; el CHECK condiciona un evento que hoy no existe en ninguna fila).
--   RLS y policies intactas. Ninguna función sellada por huella se reemplaza. `reactivado_en` y `enfriado_hasta` igual.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-proxima-llamada.sql`: índice, CHECK de B1, constantes de B1 (dos
--   columnas), sello de B1 (dos columnas) y la columna. Aplicar ANTES que la reversa de B1. Solo se pierden rellamadas.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'reactivado_en')
    and exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'enfriado_hasta')
    and not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en')
    and to_regprocedure('private.base_gestion_constantes()') is not null
    and (select count(*) from pg_proc p, unnest(p.proargnames) n where p.oid = to_regprocedure('private.base_gestion_constantes()')) = 2
    and to_regprocedure('private.trg_leads_zz_sello_base_gestion()') is not null
    and exists (select 1 from pg_trigger where tgrelid = 'crm.leads'::regclass and tgname = 'trg_leads_zz_sello_base_gestion' and tgenabled = 'O')
    and exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated)
    and not exists (select 1 from pg_class where relname = 'idx_leads_base_rellamada' and relnamespace = 'crm'::regnamespace)
    and not exists (select 1 from crm.actividades where metadata->>'evento' = 'intento_base')
  ) is not true then
    raise exception 'PREFLIGHT: B1 (20261002054402) no esta aplicada tal como se audito, B1b ya esta aplicada, o ya hay intentos de la base registrados (revisar el CHECK antes de recrearlo)';
  end if;
end;
$preflight$;

-- ── 1. Columna ───────────────────────────────────────────────────────────────────────────────
alter table crm.leads add column proxima_llamada_en timestamptz;
comment on column crm.leads.proxima_llamada_en is
  'Base para gestión (B1b, D7-bis/D11): próxima rellamada acordada desde la base (máximo 10 días adelante; constantes en private.base_gestion_constantes). La escribe el núcleo del intento con resultado volver_a_llamar; una nueva la sustituye, el siguiente intento la consume, reactivar o vetar la limpia. NULL = sin rellamada. Es la agenda PROPIA de la base: no es una tarea ni entra en la cola diaria ni en el SLA.';

-- ── 2. Sello sobre las tres columnas ─────────────────────────────────────────────────────────
create or replace function private.trg_leads_zz_sello_base_gestion()
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
    if new.reactivado_en is not null or new.enfriado_hasta is not null or new.proxima_llamada_en is not null then
      raise exception 'reactivado_en, enfriado_hasta y proxima_llamada_en los escribe solo la base para gestion (su nucleo)'
        using errcode = '42501';
    end if;
  elsif new.reactivado_en is distinct from old.reactivado_en
     or new.enfriado_hasta is distinct from old.enfriado_hasta
     or new.proxima_llamada_en is distinct from old.proxima_llamada_en then
    raise exception 'reactivado_en, enfriado_hasta y proxima_llamada_en los escribe solo la base para gestion (su nucleo)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
alter function private.trg_leads_zz_sello_base_gestion() owner to postgres;
revoke all on function private.trg_leads_zz_sello_base_gestion() from public, anon, authenticated, service_role;
comment on function private.trg_leads_zz_sello_base_gestion() is
  'Base para gestión (B1/B1b): sello de reactivado_en, enfriado_hasta y proxima_llamada_en de crm.leads. Las acepta solo bajo el GUC de transacción crm.op_base_gestion=on (núcleos de B3/B4 y puertas de Gerencia) o sin usuario (migraciones). DEFINER por el mismo molde que trg_actividades_resultado_solo_nucleo; cerrado con search_path vacío, dueño postgres y sin EXECUTE para la API.';
drop trigger trg_leads_zz_sello_base_gestion on crm.leads;
create trigger trg_leads_zz_sello_base_gestion
  before insert or update of reactivado_en, enfriado_hasta, proxima_llamada_en on crm.leads
  for each row execute function private.trg_leads_zz_sello_base_gestion();

-- ── 3. CHECK del intento: volver_a_llamar exige la fecha (ISO-8601 con zona) ──────────────────
alter table crm.actividades drop constraint actividades_intento_base_forma;
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
         or coalesce(metadata->>'proxima_llamada_en', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?([+-][0-9]{2}:?[0-9]{2}|Z)$')
  )
) not valid;
alter table crm.actividades validate constraint actividades_intento_base_forma;
comment on constraint actividades_intento_base_forma on crm.actividades is
  'Base para gestión (B1/B1b): toda actividad con evento=intento_base trae resultado del MISMO catálogo cerrado de 7 valores de Gestión Diaria, intento_n y ciclo_n enteros >= 1, submotivo del catálogo si viene, y proxima_llamada_en (ISO-8601 con zona) cuando el resultado es volver_a_llamar. De forma, no de presencia: el núcleo construye la clave con to_jsonb(timestamptz) (nunca ::text) y castea a timestamptz antes de escribir crm.leads.proxima_llamada_en; la agenda se lee de crm.leads, no de la metadata.';

-- ── 4. Constantes: tres en un solo sitio ─────────────────────────────────────────────────────
drop function private.base_gestion_constantes();
create function private.base_gestion_constantes()
returns table (max_intentos integer, dias_enfriamiento integer, dias_max_rellamada integer)
language sql
immutable
security invoker
set search_path = ''
as $$
  select 3, 30, 10;
$$;
alter function private.base_gestion_constantes() owner to postgres;
revoke all on function private.base_gestion_constantes() from public, anon, authenticated, service_role;
comment on function private.base_gestion_constantes() is
  'Base para gestión (B1/B1b, D4/D11/D12): constantes de negocio en un solo sitio. max_intentos = intentos sin cita ni rellamada que agotan al lead en su ciclo (D12: una rellamada agendada gana al enfriamiento); dias_enfriamiento = días Lima que descansa fuera de la base; dias_max_rellamada = tope de días hacia adelante para agendar una rellamada. Las consumen los núcleos (DEFINER); cambiarlas es una migración.';

-- ── 5. Índice parcial de la agenda ───────────────────────────────────────────────────────────
create index idx_leads_base_rellamada on crm.leads (vendedor_id, proxima_llamada_en)
  where etapa = 'descartado' and proxima_llamada_en is not null;
comment on index crm.idx_leads_base_rellamada is
  'Base para gestión (B1b): agenda propia de la base («Llamar hoy» y contador del menú) por analista. Solo descartados con rellamada.';

-- ── 6. Permisos ──────────────────────────────────────────────────────────────────────────────
grant select (proxima_llamada_en) on crm.leads to authenticated, service_role;

do $postflight$
declare
  v_uid constant uuid := '0b0a5e00-0000-4000-8000-00000000b1b2';
  v_lead uuid;
  v_attnum smallint;
begin
  select attnum into v_attnum from pg_attribute where attrelid = 'crm.leads'::regclass and attname = 'proxima_llamada_en';
  if (
    (select data_type from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en') = 'timestamp with time zone'
    and has_column_privilege('authenticated', 'crm.leads', 'proxima_llamada_en', 'SELECT')
    and not has_column_privilege('anon', 'crm.leads', 'proxima_llamada_en', 'SELECT')
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta', 'proxima_llamada_en')) = 6
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta', 'proxima_llamada_en')
            and e.privilege_type = 'SELECT' and not e.is_grantable
            and e.grantee in ('authenticated'::regrole, 'service_role'::regrole)) = 6
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion'
                 and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4 and (t.tgtype & 16) = 16
                 and v_attnum = any(t.tgattr::smallint[]) and array_length(t.tgattr::smallint[], 1) = 3)
    and exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated)
    and (select (c.max_intentos, c.dias_enfriamiento, c.dias_max_rellamada) = (3, 30, 10) from private.base_gestion_constantes() c)
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.base_gestion_constantes()')
                 and not p.prosecdef and p.provolatile = 'i' and p.proowner = 'postgres'::regrole
                 and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.base_gestion_constantes()', 'EXECUTE')
    and not has_function_privilege('anon', 'private.base_gestion_constantes()', 'EXECUTE')
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()')
                 and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.trg_leads_zz_sello_base_gestion()', 'EXECUTE')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion'
                 and t.tgfoid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()'))
    and exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'idx_leads_base_rellamada' and i.indpred is not null and i.indisvalid)
  ) is not true then
    raise exception 'POSTFLIGHT: columna, ACL por columna, sello de tres columnas, CHECK, constantes o indice no quedaron como se esperaba';
  end if;
  select l.id into v_lead from crm.leads l where l.activo and l.etapa not in ('convertido', 'descartado') order by l.creado_en limit 1;
  if v_lead is not null then
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1"}');
      raise exception 'POSTFLIGHT: el CHECK acepto volver_a_llamar sin proxima_llamada_en' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1","proxima_llamada_en":"manana"}');
      raise exception 'POSTFLIGHT: el CHECK acepto una fecha sin forma ISO' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    -- Positivos (deshechos): la forma de to_jsonb(timestamptz) con offset y la canónica de JS/PostgREST con Z.
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1","proxima_llamada_en":"2026-10-03T15:00:00.123456-05:00"}');
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"2","ciclo_n":"1","proxima_llamada_en":"2026-10-03T20:00:00.000Z"}');
      raise exception 'DESHACER' using errcode = 'ZZ0B2';
    exception when sqlstate 'ZZ0B2' then null;
      when check_violation then raise exception 'POSTFLIGHT: el CHECK rechazo una fecha ISO valida (offset o Z)' using errcode = 'P0001';
    end;
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      update crm.leads set proxima_llamada_en = now() where id = v_lead;
      raise exception 'POSTFLIGHT: el sello dejo escribir proxima_llamada_en sin el GUC' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm not like '%base para gestion%' then
        raise exception 'POSTFLIGHT: otro 42501 se adelanto al sello: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
      update crm.leads set proxima_llamada_en = now() where id = v_lead;
      if not exists (select 1 from crm.leads where id = v_lead and proxima_llamada_en is not null) then
        raise exception 'POSTFLIGHT: con el GUC el sello no dejo escribir proxima_llamada_en' using errcode = 'P0001';
      end if;
      raise exception 'DESHACER' using errcode = 'ZZ0B1';
    exception when sqlstate 'ZZ0B1' then
      perform pg_catalog.set_config('crm.op_base_gestion', 'off', true);
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    if exists (select 1 from crm.leads where id = v_lead and proxima_llamada_en is not null) then
      raise exception 'POSTFLIGHT: el ensayo del sello no se deshizo';
    end if;
  else
    raise notice 'base_gestion_proxima_llamada: sin leads vivos en esta base; negativos NO RUN';
  end if;
  raise notice 'base_gestion_proxima_llamada OK: proxima_llamada_en sellada, CHECK con fecha ISO en volver_a_llamar, constantes 3/30/10, indice parcial';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261002224851 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261002224851', 'crm_base_gestion_proxima_llamada', array[$mig$-- 20261002224851_crm_base_gestion_proxima_llamada.sql
--
-- Base para gestión del analista · B1b (esquema): la rellamada vive en el lead. Decisiones de Miguel del 02/10/2026:
-- D7-bis «agenda propia de la base» (aprobada: «Sí, así»), D11 «la rellamada puede agendarse como máximo 10 días
-- adelante», D12 «gana la rellamada: el lead descansa solo cuando el 3.º intento termina sin cita y sin rellamada».
-- Nota del vault: «Base para gestion del analista - F0 y decisiones (2026-10-01)»; tablero FigJam zbgq3gjYGsaaMCo6e140bU.
--
-- POR QUÉ. D7 (rellamada en `crm.tareas`) no es posible: `private.trg_tareas_before_insert` rechaza tareas nuevas en un
--   lead cerrado («El lead está cerrado: no admite tareas nuevas») y `trg_leads_zz_sync_tareas` cancela las pendientes al
--   descartar. El esquema separa tareas de descartados a propósito (cola diaria y SLA). La base lleva su propia agenda.
--
-- QUÉ.
--   1. `crm.leads.proxima_llamada_en timestamptz`: próxima rellamada acordada con el cliente desde la base. La escribe el
--      núcleo del intento (B3) cuando el resultado es `volver_a_llamar`; una nueva rellamada la sustituye; el siguiente
--      intento la consume; reactivar o vetar la limpia. Lectura por columna para la API; escritura solo bajo el sello.
--   2. El sello `trg_leads_zz_sello_base_gestion` cubre ahora las TRES columnas de la base (BEFORE INSERT OR UPDATE OF).
--      Mismo cuerpo y mismo GUC (`crm.op_base_gestion`); solo cambia la lista de columnas (función y trigger).
--   3. El CHECK `actividades_intento_base_forma` exige, cuando `resultado = 'volver_a_llamar'`, `proxima_llamada_en` en la
--      metadata con forma ISO-8601 con zona (antes exigía `tarea_id`, que ya no aplica). Se recrea `not valid` + `validate`.
--   4. `private.base_gestion_constantes()` gana `dias_max_rellamada = 10` (D11): la firma cambia (tres columnas), así que se
--      reemplaza con drop + create (nada depende de ella todavía). Sigue INVOKER, IMMUTABLE, sin EXECUTE para la API.
--   5. Índice parcial `idx_leads_base_rellamada (vendedor_id, proxima_llamada_en) where etapa = 'descartado' and
--      proxima_llamada_en is not null`: lo leen el bloque «Llamar hoy» y el contador del menú en cada carga; solo indexa los
--      descartados con rellamada (decenas de filas). Se confirma con EXPLAIN en la rama con datos.
--
-- QUÉ NO CAMBIA. Ningún dato (columna nueva NULL; el CHECK condiciona un evento que hoy no existe en ninguna fila).
--   RLS y policies intactas. Ninguna función sellada por huella se reemplaza. `reactivado_en` y `enfriado_hasta` igual.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-proxima-llamada.sql`: índice, CHECK de B1, constantes de B1 (dos
--   columnas), sello de B1 (dos columnas) y la columna. Aplicar ANTES que la reversa de B1. Solo se pierden rellamadas.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'reactivado_en')
    and exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'enfriado_hasta')
    and not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en')
    and to_regprocedure('private.base_gestion_constantes()') is not null
    and (select count(*) from pg_proc p, unnest(p.proargnames) n where p.oid = to_regprocedure('private.base_gestion_constantes()')) = 2
    and to_regprocedure('private.trg_leads_zz_sello_base_gestion()') is not null
    and exists (select 1 from pg_trigger where tgrelid = 'crm.leads'::regclass and tgname = 'trg_leads_zz_sello_base_gestion' and tgenabled = 'O')
    and exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated)
    and not exists (select 1 from pg_class where relname = 'idx_leads_base_rellamada' and relnamespace = 'crm'::regnamespace)
    and not exists (select 1 from crm.actividades where metadata->>'evento' = 'intento_base')
  ) is not true then
    raise exception 'PREFLIGHT: B1 (20261002054402) no esta aplicada tal como se audito, B1b ya esta aplicada, o ya hay intentos de la base registrados (revisar el CHECK antes de recrearlo)';
  end if;
end;
$preflight$;

-- ── 1. Columna ───────────────────────────────────────────────────────────────────────────────
alter table crm.leads add column proxima_llamada_en timestamptz;
comment on column crm.leads.proxima_llamada_en is
  'Base para gestión (B1b, D7-bis/D11): próxima rellamada acordada desde la base (máximo 10 días adelante; constantes en private.base_gestion_constantes). La escribe el núcleo del intento con resultado volver_a_llamar; una nueva la sustituye, el siguiente intento la consume, reactivar o vetar la limpia. NULL = sin rellamada. Es la agenda PROPIA de la base: no es una tarea ni entra en la cola diaria ni en el SLA.';

-- ── 2. Sello sobre las tres columnas ─────────────────────────────────────────────────────────
create or replace function private.trg_leads_zz_sello_base_gestion()
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
    if new.reactivado_en is not null or new.enfriado_hasta is not null or new.proxima_llamada_en is not null then
      raise exception 'reactivado_en, enfriado_hasta y proxima_llamada_en los escribe solo la base para gestion (su nucleo)'
        using errcode = '42501';
    end if;
  elsif new.reactivado_en is distinct from old.reactivado_en
     or new.enfriado_hasta is distinct from old.enfriado_hasta
     or new.proxima_llamada_en is distinct from old.proxima_llamada_en then
    raise exception 'reactivado_en, enfriado_hasta y proxima_llamada_en los escribe solo la base para gestion (su nucleo)'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
alter function private.trg_leads_zz_sello_base_gestion() owner to postgres;
revoke all on function private.trg_leads_zz_sello_base_gestion() from public, anon, authenticated, service_role;
comment on function private.trg_leads_zz_sello_base_gestion() is
  'Base para gestión (B1/B1b): sello de reactivado_en, enfriado_hasta y proxima_llamada_en de crm.leads. Las acepta solo bajo el GUC de transacción crm.op_base_gestion=on (núcleos de B3/B4 y puertas de Gerencia) o sin usuario (migraciones). DEFINER por el mismo molde que trg_actividades_resultado_solo_nucleo; cerrado con search_path vacío, dueño postgres y sin EXECUTE para la API.';
drop trigger trg_leads_zz_sello_base_gestion on crm.leads;
create trigger trg_leads_zz_sello_base_gestion
  before insert or update of reactivado_en, enfriado_hasta, proxima_llamada_en on crm.leads
  for each row execute function private.trg_leads_zz_sello_base_gestion();

-- ── 3. CHECK del intento: volver_a_llamar exige la fecha (ISO-8601 con zona) ──────────────────
alter table crm.actividades drop constraint actividades_intento_base_forma;
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
         or coalesce(metadata->>'proxima_llamada_en', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?([+-][0-9]{2}:?[0-9]{2}|Z)$')
  )
) not valid;
alter table crm.actividades validate constraint actividades_intento_base_forma;
comment on constraint actividades_intento_base_forma on crm.actividades is
  'Base para gestión (B1/B1b): toda actividad con evento=intento_base trae resultado del MISMO catálogo cerrado de 7 valores de Gestión Diaria, intento_n y ciclo_n enteros >= 1, submotivo del catálogo si viene, y proxima_llamada_en (ISO-8601 con zona) cuando el resultado es volver_a_llamar. De forma, no de presencia: el núcleo construye la clave con to_jsonb(timestamptz) (nunca ::text) y castea a timestamptz antes de escribir crm.leads.proxima_llamada_en; la agenda se lee de crm.leads, no de la metadata.';

-- ── 4. Constantes: tres en un solo sitio ─────────────────────────────────────────────────────
drop function private.base_gestion_constantes();
create function private.base_gestion_constantes()
returns table (max_intentos integer, dias_enfriamiento integer, dias_max_rellamada integer)
language sql
immutable
security invoker
set search_path = ''
as $$
  select 3, 30, 10;
$$;
alter function private.base_gestion_constantes() owner to postgres;
revoke all on function private.base_gestion_constantes() from public, anon, authenticated, service_role;
comment on function private.base_gestion_constantes() is
  'Base para gestión (B1/B1b, D4/D11/D12): constantes de negocio en un solo sitio. max_intentos = intentos sin cita ni rellamada que agotan al lead en su ciclo (D12: una rellamada agendada gana al enfriamiento); dias_enfriamiento = días Lima que descansa fuera de la base; dias_max_rellamada = tope de días hacia adelante para agendar una rellamada. Las consumen los núcleos (DEFINER); cambiarlas es una migración.';

-- ── 5. Índice parcial de la agenda ───────────────────────────────────────────────────────────
create index idx_leads_base_rellamada on crm.leads (vendedor_id, proxima_llamada_en)
  where etapa = 'descartado' and proxima_llamada_en is not null;
comment on index crm.idx_leads_base_rellamada is
  'Base para gestión (B1b): agenda propia de la base («Llamar hoy» y contador del menú) por analista. Solo descartados con rellamada.';

-- ── 6. Permisos ──────────────────────────────────────────────────────────────────────────────
grant select (proxima_llamada_en) on crm.leads to authenticated, service_role;

do $postflight$
declare
  v_uid constant uuid := '0b0a5e00-0000-4000-8000-00000000b1b2';
  v_lead uuid;
  v_attnum smallint;
begin
  select attnum into v_attnum from pg_attribute where attrelid = 'crm.leads'::regclass and attname = 'proxima_llamada_en';
  if (
    (select data_type from information_schema.columns where table_schema = 'crm' and table_name = 'leads' and column_name = 'proxima_llamada_en') = 'timestamp with time zone'
    and has_column_privilege('authenticated', 'crm.leads', 'proxima_llamada_en', 'SELECT')
    and not has_column_privilege('anon', 'crm.leads', 'proxima_llamada_en', 'SELECT')
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta', 'proxima_llamada_en')) = 6
    and (select count(*) from pg_attribute a, aclexplode(a.attacl) e
          where a.attrelid = 'crm.leads'::regclass and a.attname in ('reactivado_en', 'enfriado_hasta', 'proxima_llamada_en')
            and e.privilege_type = 'SELECT' and not e.is_grantable
            and e.grantee in ('authenticated'::regrole, 'service_role'::regrole)) = 6
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion'
                 and t.tgenabled = 'O' and (t.tgtype & 2) = 2 and (t.tgtype & 4) = 4 and (t.tgtype & 16) = 16
                 and v_attnum = any(t.tgattr::smallint[]) and array_length(t.tgattr::smallint[], 1) = 3)
    and exists (select 1 from pg_constraint where conrelid = 'crm.actividades'::regclass and conname = 'actividades_intento_base_forma' and convalidated)
    and (select (c.max_intentos, c.dias_enfriamiento, c.dias_max_rellamada) = (3, 30, 10) from private.base_gestion_constantes() c)
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.base_gestion_constantes()')
                 and not p.prosecdef and p.provolatile = 'i' and p.proowner = 'postgres'::regrole
                 and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.base_gestion_constantes()', 'EXECUTE')
    and not has_function_privilege('anon', 'private.base_gestion_constantes()', 'EXECUTE')
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()')
                 and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.trg_leads_zz_sello_base_gestion()', 'EXECUTE')
    and exists (select 1 from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_leads_zz_sello_base_gestion'
                 and t.tgfoid = to_regprocedure('private.trg_leads_zz_sello_base_gestion()'))
    and exists (select 1 from pg_index i join pg_class c on c.oid = i.indexrelid where c.relname = 'idx_leads_base_rellamada' and i.indpred is not null and i.indisvalid)
  ) is not true then
    raise exception 'POSTFLIGHT: columna, ACL por columna, sello de tres columnas, CHECK, constantes o indice no quedaron como se esperaba';
  end if;
  select l.id into v_lead from crm.leads l where l.activo and l.etapa not in ('convertido', 'descartado') order by l.creado_en limit 1;
  if v_lead is not null then
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1"}');
      raise exception 'POSTFLIGHT: el CHECK acepto volver_a_llamar sin proxima_llamada_en' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1","proxima_llamada_en":"manana"}');
      raise exception 'POSTFLIGHT: el CHECK acepto una fecha sin forma ISO' using errcode = 'P0001';
    exception when check_violation then null;
    end;
    -- Positivos (deshechos): la forma de to_jsonb(timestamptz) con offset y la canónica de JS/PostgREST con Z.
    begin
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"1","ciclo_n":"1","proxima_llamada_en":"2026-10-03T15:00:00.123456-05:00"}');
      insert into crm.actividades (lead_id, tipo, detalle, metadata)
      values (v_lead, 'nota', 'POSTFLIGHT', '{"evento":"intento_base","resultado":"volver_a_llamar","intento_n":"2","ciclo_n":"1","proxima_llamada_en":"2026-10-03T20:00:00.000Z"}');
      raise exception 'DESHACER' using errcode = 'ZZ0B2';
    exception when sqlstate 'ZZ0B2' then null;
      when check_violation then raise exception 'POSTFLIGHT: el CHECK rechazo una fecha ISO valida (offset o Z)' using errcode = 'P0001';
    end;
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      update crm.leads set proxima_llamada_en = now() where id = v_lead;
      raise exception 'POSTFLIGHT: el sello dejo escribir proxima_llamada_en sin el GUC' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm not like '%base para gestion%' then
        raise exception 'POSTFLIGHT: otro 42501 se adelanto al sello: %', sqlerrm using errcode = 'P0001';
      end if;
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    begin
      perform pg_catalog.set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
      update crm.leads set proxima_llamada_en = now() where id = v_lead;
      if not exists (select 1 from crm.leads where id = v_lead and proxima_llamada_en is not null) then
        raise exception 'POSTFLIGHT: con el GUC el sello no dejo escribir proxima_llamada_en' using errcode = 'P0001';
      end if;
      raise exception 'DESHACER' using errcode = 'ZZ0B1';
    exception when sqlstate 'ZZ0B1' then
      perform pg_catalog.set_config('crm.op_base_gestion', 'off', true);
      perform pg_catalog.set_config('request.jwt.claims', '', true);
    end;
    if exists (select 1 from crm.leads where id = v_lead and proxima_llamada_en is not null) then
      raise exception 'POSTFLIGHT: el ensayo del sello no se deshizo';
    end if;
  else
    raise notice 'base_gestion_proxima_llamada: sin leads vivos en esta base; negativos NO RUN';
  end if;
  raise notice 'base_gestion_proxima_llamada OK: proxima_llamada_en sellada, CHECK con fecha ISO en volver_a_llamar, constantes 3/30/10, indice parcial';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261002224851' and name = 'crm_base_gestion_proxima_llamada' and cardinality(statements) = 1
                   and md5(statements[1]) = 'f6cea9be895a9f34d6e428ff35957a70') then
    raise exception 'REGISTRO: la fila 20261002224851 / crm_base_gestion_proxima_llamada no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261002224851 / crm_base_gestion_proxima_llamada (1 sentencia: el archivo entero)';
end $post$;
commit;
