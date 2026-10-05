-- REGISTRO en supabase_migrations.schema_migrations de 20261002233851_crm_base_gestion_enfriamiento.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 b5e78bc8f27a6725d929a98285b658e9).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_enfriamiento_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.trg_actividades_enfriamiento_base()') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261002233851 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261002233851' and (coalesce(name, '') <> 'crm_base_gestion_enfriamiento' or statements is distinct from array[$mig$-- 20261002233851_crm_base_gestion_enfriamiento.sql
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
$mig$])) then
    raise exception 'REGISTRO: la versión 20261002233851 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261002233851', 'crm_base_gestion_enfriamiento', array[$mig$-- 20261002233851_crm_base_gestion_enfriamiento.sql
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
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261002233851' and name = 'crm_base_gestion_enfriamiento' and cardinality(statements) = 1
                   and md5(statements[1]) = 'b5e78bc8f27a6725d929a98285b658e9') then
    raise exception 'REGISTRO: la fila 20261002233851 / crm_base_gestion_enfriamiento no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261002233851 / crm_base_gestion_enfriamiento (1 sentencia: el archivo entero)';
end $post$;
commit;
