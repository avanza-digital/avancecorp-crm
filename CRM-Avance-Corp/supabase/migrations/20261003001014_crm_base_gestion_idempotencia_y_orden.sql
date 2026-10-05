-- 20261003001014_crm_base_gestion_idempotencia_y_orden.sql
--
-- Base para gestión del analista · B3b: enmiendas de la revisión de Codex (LEVEL 3, 02/10/2026 noche, BLOCK) sobre
-- B3/B4. Regla del CRM: una migración commiteada no se edita; se enmienda con otra. Vault: «Base para gestion del
-- analista - F0 y decisiones (2026-10-01)»; informe en `BASE PARA GESTION/revisiones/2026-10-02-codex-b3-b4.md`.
--
-- QUÉ (por `create or replace` del texto vigente de B4b con sustituciones exactas; firmas y contratos iguales):
--   · `private.base_gestion_intento_core` — (#1) el replay se resuelve ANTES de las validaciones temporales: el reintento
--     de una rellamada ya vencida devuelve su respuesta en vez de 22023; (#2) la identidad de la operación incluye la
--     fecha de rellamada y la nota (`solicitud_proxima`, `nota_md5` en la respuesta): mismo id con otra fecha → 23505;
--     (#3) la reactivación hija de «agendó cita» usa un uuid NUEVO (no derivable del padre) y se rechaza si viniera
--     como replay o sin dejar el lead en contactado.
--   · `crm.obtener_base_gestion` — (#4) orden del contrato: rellamada vencida/hoy → etapa máxima → días desde el
--     descarte; la hora de la rellamada solo desempata; (#5) «último resultado» desempata por `intento_n`; (#6) el
--     descarte del ciclo anterior que comparta instante con la reapertura queda fuera de la etapa máxima.
--   Rechazado con evidencia: el cupo tras el descanso ya lo decidió Miguel (D13, B4b).
--   Riesgo operativo anotado (no corregible aquí): el postflight de B4 ensaya por la puerta sobre un lead real; si otra
--   sesión tiene ese lead y va a insertar una actividad, puede haber un deadlock que Postgres resuelve abortando a una
--   de las dos (40P01). Aplicar B4 en producción fuera de horario de gestión.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-idempotencia-y-orden.sql` (reinstala los cuerpos de B4b). No toca datos.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select p.prosrc like '%base_gestion_intentos_desde(v_lead.descartado_en, v_lead.creado_en, v_lead.enfriado_hasta, v_hoy)%'
        and p.prosrc like '%md5(p_operacion_id::text || '':reactivar'')::uuid%' and p.prosrc not like '%solicitud_proxima%'
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy)%'
            and p.prosrc like '%b.proxima_llamada_en asc nulls last,
           coalesce(e.rango, 0) desc,%'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
  ) is not true then
    raise exception 'PREFLIGHT: B4b no tiene el texto esperado o B3b ya esta aplicada';
  end if;
end;
$preflight$;

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
           (array_agg(a.metadata->>'resultado' order by a.creado_en desc, (a.metadata->>'intento_n')::integer desc, a.id desc))[1] as ultimo,  -- Codex B3 #5: desempate por intento_n
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
      -- Codex B3 #6: el descarte del ciclo anterior puede compartir instante con la reapertura (misma transaccion): fuera.
      and not (a.creado_en = c.desde and a.metadata->>'etapa_nueva' = 'descartado')
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
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4).
  order by (b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
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
  -- Validaciones de FORMA (valen igual para una operacion nueva y para su reintento).
  if p_resultado = 'volver_a_llamar' and p_proxima is null then
    raise exception 'Indica cuando volver a llamar' using errcode = '22023';
  elsif p_resultado <> 'volver_a_llamar' and p_proxima is not null then
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
  -- Idempotencia DESPUES del candado del lead, solo entre operaciones del mismo actor y ANTES de las validaciones
  -- temporales (Codex B3 #1: el reintento de una rellamada ya vencida debe seguir devolviendo su respuesta). La identidad
  -- de la operacion incluye lead, resultado, fecha de rellamada y nota (Codex B3 #2).
  select a.metadata->'respuesta' into v_prev from crm.actividades a where a.id = p_operacion_id and a.creado_por = p_actor;
  if found then
    if v_prev is null or (v_prev->>'lead_id')::uuid is distinct from p_lead_id or v_prev->>'resultado' is distinct from p_resultado
       or v_prev->>'evento' is distinct from 'intento_base'
       or (v_prev->>'solicitud_proxima')::timestamptz is distinct from p_proxima
       or v_prev->>'nota_md5' is distinct from md5(coalesce(pg_catalog.btrim(p_nota), '')) then
      raise exception 'Esta operacion ya corresponde a otro contenido' using errcode = '23505';
    end if;
    return v_prev || jsonb_build_object('replay', true);
  end if;
  -- Validaciones TEMPORALES: solo para una operacion nueva.
  if p_resultado = 'volver_a_llamar' then
    if p_proxima <= now() then
      raise exception 'La rellamada debe ser futura' using errcode = '22023';
    end if;
    if p_proxima > now() + make_interval(days => v_c.dias_max_rellamada) then
      raise exception 'La rellamada se agenda como maximo % dias adelante', v_c.dias_max_rellamada using errcode = '22023';
    end if;
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
    -- Codex B3 #3: la operacion hija lleva un uuid NUEVO (no derivable del padre) y no puede ser un replay ajeno; la
    -- idempotencia del conjunto la da la operacion padre.
    v_react := private.base_gestion_reactivar_core(p_actor, gen_random_uuid(), p_lead_id, 'Agendó cita desde la base para gestión');
    if coalesce((v_react->>'replay')::boolean, false) or v_react->>'etapa' is distinct from 'contactado' then
      raise exception 'La reactivacion de "agendo cita" no se completo' using errcode = 'P0001';
    end if;
  end if;
  select * into v_lead from crm.leads where id = p_lead_id;  -- tras el trigger de enfriamiento (B4) y la reactivacion
  v_resp := jsonb_build_object('ok', true, 'evento', 'intento_base', 'lead_id', p_lead_id, 'actividad_id', p_operacion_id,
                               'resultado', p_resultado, 'intento_n', v_n, 'ciclo_n', v_meta->>'ciclo_n',
                               'proxima_llamada_en', v_lead.proxima_llamada_en, 'enfriado_hasta', v_lead.enfriado_hasta,
                               'reactivado', v_react is not null, 'etapa', v_lead.etapa, 'replay', false,
                               'solicitud_proxima', p_proxima, 'nota_md5', md5(coalesce(pg_catalog.btrim(p_nota), '')));
  perform pg_catalog.set_config('crm.op_resultado_llamada', 'on', true);
  perform pg_catalog.set_config('crm.op_base_gestion', 'on', true);
  update crm.actividades set metadata = metadata || jsonb_build_object('respuesta', v_resp) where id = p_operacion_id;
  perform pg_catalog.set_config('crm.op_resultado_llamada', v_guc1, true);
  perform pg_catalog.set_config('crm.op_base_gestion', v_guc2, true);
  return v_resp;
end;
$$;

do $postflight$
begin
  if (
    (select p.prosrc like '%solicitud_proxima%' and p.prosrc like '%nota_md5%' and p.prosrc like '%gen_random_uuid(), p_lead_id%'
        and p.prosrc not like '%:reactivar%' and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
       from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select p.prosrc like '%coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone ''America/Lima'')::date desc nulls last%'
            and p.prosrc like '%(a.metadata->>''intento_n'')::integer desc%' and p.prosrc like '%etapa_nueva'' = ''descartado'')%'
            and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and has_function_privilege('authenticated', 'crm.obtener_base_gestion(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'crm.obtener_base_gestion(uuid)', 'EXECUTE')
    and not has_function_privilege('authenticated', 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)', 'EXECUTE')
  ) is not true then
    raise exception 'POSTFLIGHT: los cuerpos no llevan las enmiendas de Codex o perdieron su contrato';
  end if;
  raise notice 'base_gestion_idempotencia_y_orden OK: replay antes de lo temporal, identidad con fecha y nota, hija con uuid nuevo, orden del contrato, desempates';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
