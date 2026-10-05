-- Reversa de 20261002235342_crm_base_gestion_ventana_descanso.sql (B4b, D13): reinstala los cuerpos de B3/B4 (ventana por ciclo) y quita el ayudante.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;
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
drop function private.base_gestion_intentos_desde(timestamptz, timestamptz, date, date);
do $post$
begin
  if to_regprocedure('private.base_gestion_intentos_desde(timestamptz,timestamptz,date,date)') is not null
     or exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('crm','private') and p.prosrc like '%base_gestion_intentos_desde%') then
    raise exception 'REVERSA B4b: quedo el ayudante o alguna referencia';
  end if;
  raise notice 'reversa base_gestion_ventana_descanso OK';
end;
$post$;
notify pgrst, 'reload schema';
commit;
