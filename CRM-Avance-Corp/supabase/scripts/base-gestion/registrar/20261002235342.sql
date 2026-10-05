-- REGISTRO en supabase_migrations.schema_migrations de 20261002235342_crm_base_gestion_ventana_descanso.
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración. Idempotente; se niega si
-- los objetos no están, o si la versión ya está registrada con otro nombre u otro contenido.
-- Generado con banco/generar-registrador.py. statements = el archivo entero (md5 061389db23340abb33fa4c35cec400e7).
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_base_gestion_ventana_descanso_registro'));
do $chk$
begin
  if (
    to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)') is not null
  ) is not true then
    raise exception 'REGISTRO: la migración 20261002235342 no está aplicada; aplícala primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations
             where version = '20261002235342' and (coalesce(name, '') <> 'crm_base_gestion_ventana_descanso' or statements is distinct from array[$mig$-- 20261002235342_crm_base_gestion_ventana_descanso.sql
--
-- Base para gestión del analista · B4b: la ventana de intentos se reinicia tras cada descanso (D13).
-- Decisión de Miguel (02/10/2026, noche): «Tres intentos nuevos tras cada descanso». Hasta aquí el cupo de 3 era por
-- ciclo (desde `descartado_en`) y, vencido el descanso, UN intento más sin rellamada volvía a enfriar. Ahora los
-- intentos se cuentan desde el DESCARTE o desde el FIN DEL ÚLTIMO DESCANSO (el que sea posterior).
--
-- QUÉ. Un ayudante inmutable `private.base_gestion_intentos_desde(descartado_en, creado_en, enfriado_hasta, hoy)`:
--   greatest(coalesce(descartado_en, creado_en), inicio Lima del día `enfriado_hasta` si ese descanso ya venció). Lo usan,
--   por `create or replace` del texto de B3/B4 con una sustitución exacta cada una: `crm.obtener_base_gestion` (columna
--   `intentos` y `ultimo_resultado` de la ventana), `private.base_gestion_intento_core` (`intento_n`) y
--   `private.trg_actividades_enfriamiento_base` (cupo de `max_intentos`). El historial completo sigue en la ficha; lo
--   que se reinicia es el contador. Reactivar limpia `enfriado_hasta` (ventana desde el nuevo descarte si vuelve a caer).
--
-- QUÉ NO CAMBIA. Firmas, contratos (DEFINER/INVOKER, search_path, dueño, ACL), triggers, sellos, RLS. Ningún dato.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-ventana-descanso.sql`: reinstala los tres cuerpos de B3/B4 y quita el
--   ayudante. No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)') is null
    and (select p.prosrc like '%coalesce(l.descartado_en, l.creado_en) as desde%' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select p.prosrc like '%a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);%' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);  -- incluye este intento (AFTER)%' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
  ) is not true then
    raise exception 'PREFLIGHT: B3/B4 no tienen el texto esperado (ventana por ciclo) o B4b ya esta aplicada';
  end if;
end;
$preflight$;

create function private.base_gestion_intentos_desde(p_descartado_en timestamptz, p_creado_en timestamptz, p_enfriado_hasta date, p_hoy date)
returns timestamptz language sql immutable security invoker set search_path = '' as $$
  select greatest(coalesce(p_descartado_en, p_creado_en),
                  case when p_enfriado_hasta is not null and p_enfriado_hasta <= p_hoy
                       then (p_enfriado_hasta::timestamp at time zone 'America/Lima') end);
$$;
alter function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) owner to postgres;
revoke all on function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) from public, anon, authenticated, service_role;
comment on function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) is
  'Base para gestión (B4b, D13): inicio de la ventana de intentos de un lead descartado: el descarte vigente o, si ya venció un descanso, el inicio Lima del día en que terminó (el posterior de los dos). Tras cada descanso el analista vuelve a tener max_intentos.';

create or replace function crm.obtener_base_gestion(p_vendedor_id uuid default null)
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
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
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
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text, p_proxima timestamptz)
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
     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- D13
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
create or replace function private.trg_actividades_enfriamiento_base()
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
     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- incluye este intento (AFTER); D13
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
comment on function crm.obtener_base_gestion(uuid) is
  'Base para gestión (B3/B4b): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos y último resultado de la VENTANA vigente (desde el descarte o el fin del último descanso, D13), próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated.';
comment on function private.trg_actividades_enfriamiento_base() is
  'Base para gestión (B4/B4b, D4/D12/D13): al registrar un intento de la base sin rellamada ni cita, si el lead sigue descartado y los intentos de la ventana vigente (desde el descarte o el fin del último descanso) llegan a max_intentos, fija enfriado_hasta = hoy Lima + dias_enfriamiento. Solo actúa bajo crm.op_base_gestion = on. Constantes en private.base_gestion_constantes(). DEFINER por el molde del sello de B1; search_path vacío, dueño postgres, sin EXECUTE para la API.';

do $postflight$
begin
  if (
    (select p.prosrc like '%base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select p.prosrc like '%base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)')
                 and not p.prosecdef and p.provolatile = 'i' and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)', 'EXECUTE')
    -- contratos intactos
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)') and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and has_function_privilege('authenticated', 'crm.obtener_base_gestion(uuid)', 'EXECUTE') and not has_function_privilege('anon', 'crm.obtener_base_gestion(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.trg_actividades_enfriamiento_base()', 'EXECUTE')
    and exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_zz_actividades_enfriamiento_base' and tgenabled = 'O')
    -- la ventana: vencido el descanso, arranca al inicio Lima de ese dia; sin descanso, en el descarte
    and private.base_gestion_intentos_desde('2026-09-01 15:00-05'::timestamptz, '2026-08-01'::timestamptz, '2026-09-20'::date, '2026-10-02'::date) = ('2026-09-20'::timestamp at time zone 'America/Lima')
    and private.base_gestion_intentos_desde('2026-09-01 15:00-05'::timestamptz, '2026-08-01'::timestamptz, '2026-10-20'::date, '2026-10-02'::date) = '2026-09-01 15:00-05'::timestamptz
    and private.base_gestion_intentos_desde(null, '2026-08-01'::timestamptz, null, '2026-10-02'::date) = '2026-08-01'::timestamptz
  ) is not true then
    raise exception 'POSTFLIGHT: los tres cuerpos no usan la ventana D13, el ayudante no tiene su contrato o la ventana no calcula bien';
  end if;
  raise notice 'base_gestion_ventana_descanso OK: tras cada descanso, max_intentos nuevos (D13)';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])) then
    raise exception 'REGISTRO: la versión 20261002235342 ya está registrada con otro nombre o contenido';
  end if;
end $chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20261002235342', 'crm_base_gestion_ventana_descanso', array[$mig$-- 20261002235342_crm_base_gestion_ventana_descanso.sql
--
-- Base para gestión del analista · B4b: la ventana de intentos se reinicia tras cada descanso (D13).
-- Decisión de Miguel (02/10/2026, noche): «Tres intentos nuevos tras cada descanso». Hasta aquí el cupo de 3 era por
-- ciclo (desde `descartado_en`) y, vencido el descanso, UN intento más sin rellamada volvía a enfriar. Ahora los
-- intentos se cuentan desde el DESCARTE o desde el FIN DEL ÚLTIMO DESCANSO (el que sea posterior).
--
-- QUÉ. Un ayudante inmutable `private.base_gestion_intentos_desde(descartado_en, creado_en, enfriado_hasta, hoy)`:
--   greatest(coalesce(descartado_en, creado_en), inicio Lima del día `enfriado_hasta` si ese descanso ya venció). Lo usan,
--   por `create or replace` del texto de B3/B4 con una sustitución exacta cada una: `crm.obtener_base_gestion` (columna
--   `intentos` y `ultimo_resultado` de la ventana), `private.base_gestion_intento_core` (`intento_n`) y
--   `private.trg_actividades_enfriamiento_base` (cupo de `max_intentos`). El historial completo sigue en la ficha; lo
--   que se reinicia es el contador. Reactivar limpia `enfriado_hasta` (ventana desde el nuevo descarte si vuelve a caer).
--
-- QUÉ NO CAMBIA. Firmas, contratos (DEFINER/INVOKER, search_path, dueño, ACL), triggers, sellos, RLS. Ningún dato.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-ventana-descanso.sql`: reinstala los tres cuerpos de B3/B4 y quita el
--   ayudante. No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)') is null
    and (select p.prosrc like '%coalesce(l.descartado_en, l.creado_en) as desde%' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select p.prosrc like '%a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);%' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%a.creado_en >= coalesce(v_lead.descartado_en, v_lead.creado_en);  -- incluye este intento (AFTER)%' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
  ) is not true then
    raise exception 'PREFLIGHT: B3/B4 no tienen el texto esperado (ventana por ciclo) o B4b ya esta aplicada';
  end if;
end;
$preflight$;

create function private.base_gestion_intentos_desde(p_descartado_en timestamptz, p_creado_en timestamptz, p_enfriado_hasta date, p_hoy date)
returns timestamptz language sql immutable security invoker set search_path = '' as $$
  select greatest(coalesce(p_descartado_en, p_creado_en),
                  case when p_enfriado_hasta is not null and p_enfriado_hasta <= p_hoy
                       then (p_enfriado_hasta::timestamp at time zone 'America/Lima') end);
$$;
alter function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) owner to postgres;
revoke all on function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) from public, anon, authenticated, service_role;
comment on function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date) is
  'Base para gestión (B4b, D13): inicio de la ventana de intentos de un lead descartado: el descarte vigente o, si ya venció un descanso, el inicio Lima del día en que terminó (el posterior de los dos). Tras cada descanso el analista vuelve a tener max_intentos.';

create or replace function crm.obtener_base_gestion(p_vendedor_id uuid default null)
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
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
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
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text, p_proxima timestamptz)
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
     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- D13
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
create or replace function private.trg_actividades_enfriamiento_base()
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
     and a.creado_en >= private.base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy);  -- incluye este intento (AFTER); D13
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
comment on function crm.obtener_base_gestion(uuid) is
  'Base para gestión (B3/B4b): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos y último resultado de la VENTANA vigente (desde el descarte o el fin del último descanso, D13), próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated.';
comment on function private.trg_actividades_enfriamiento_base() is
  'Base para gestión (B4/B4b, D4/D12/D13): al registrar un intento de la base sin rellamada ni cita, si el lead sigue descartado y los intentos de la ventana vigente (desde el descarte o el fin del último descanso) llegan a max_intentos, fija enfriado_hasta = hoy Lima + dias_enfriamiento. Solo actúa bajo crm.op_base_gestion = on. Constantes en private.base_gestion_constantes(). DEFINER por el molde del sello de B1; search_path vacío, dueño postgres, sin EXECUTE para la API.';

do $postflight$
begin
  if (
    (select p.prosrc like '%base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select p.prosrc like '%base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)%' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)')
                 and not p.prosecdef and p.provolatile = 'i' and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and not has_function_privilege('authenticated', 'private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)', 'EXECUTE')
    -- contratos intactos
    and exists (select 1 from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)') and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[])
    and has_function_privilege('authenticated', 'crm.obtener_base_gestion(uuid)', 'EXECUTE') and not has_function_privilege('anon', 'crm.obtener_base_gestion(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.trg_actividades_enfriamiento_base()', 'EXECUTE')
    and exists (select 1 from pg_trigger where tgrelid = 'crm.actividades'::regclass and tgname = 'trg_zz_actividades_enfriamiento_base' and tgenabled = 'O')
    -- la ventana: vencido el descanso, arranca al inicio Lima de ese dia; sin descanso, en el descarte
    and private.base_gestion_intentos_desde('2026-09-01 15:00-05'::timestamptz, '2026-08-01'::timestamptz, '2026-09-20'::date, '2026-10-02'::date) = ('2026-09-20'::timestamp at time zone 'America/Lima')
    and private.base_gestion_intentos_desde('2026-09-01 15:00-05'::timestamptz, '2026-08-01'::timestamptz, '2026-10-20'::date, '2026-10-02'::date) = '2026-09-01 15:00-05'::timestamptz
    and private.base_gestion_intentos_desde(null, '2026-08-01'::timestamptz, null, '2026-10-02'::date) = '2026-08-01'::timestamptz
  ) is not true then
    raise exception 'POSTFLIGHT: los tres cuerpos no usan la ventana D13, el ayudante no tiene su contrato o la ventana no calcula bien';
  end if;
  raise notice 'base_gestion_ventana_descanso OK: tras cada descanso, max_intentos nuevos (D13)';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
$mig$])
on conflict (version) do nothing;
do $post$
begin
  if not exists (select 1 from supabase_migrations.schema_migrations
                 where version = '20261002235342' and name = 'crm_base_gestion_ventana_descanso' and cardinality(statements) = 1
                   and md5(statements[1]) = '061389db23340abb33fa4c35cec400e7') then
    raise exception 'REGISTRO: la fila 20261002235342 / crm_base_gestion_ventana_descanso no quedó como se esperaba';
  end if;
  raise notice 'REGISTRO: 20261002235342 / crm_base_gestion_ventana_descanso (1 sentencia: el archivo entero)';
end $post$;
commit;
