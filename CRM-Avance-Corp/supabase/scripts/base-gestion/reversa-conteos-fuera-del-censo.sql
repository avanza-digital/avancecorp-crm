-- REVERSA de 20261003162300_crm_base_gestion_conteos_fuera_del_censo (B3c): reinstala los cuatro cuerpos vivos del 03/10 (vuelven al censo analítico) y borra las
-- dos ayudantes. Revertir ANTES B5 si está aplicada (su preflight lo exige). No toca datos.
begin;
set local lock_timeout = '10s';
set local search_path = '';
set local quote_all_identifiers = off;
do $pre$
begin
  if (
    (select md5(p.prosrc) = '74ed9b893bd45f446189feb05cadc839' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = 'db8ba2b4df43c84438f216924f20e73d' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select md5(p.prosrc) = 'b60555d169891e2edb96b38e31754654' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
  ) is not true then
    raise exception 'REVERSA: los cuerpos vivos no son los de B3c (¿B5 sigue aplicada o hubo otro cambio?)';
  end if;
end;
$pre$;
create or replace function private.base_gestion_intento_core(p_actor uuid, p_operacion_id uuid, p_lead_id uuid, p_resultado text, p_nota text, p_proxima timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
create or replace function private.trg_actividades_enfriamiento_base()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
create or replace function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;
create or replace function crm.base_gestion_resumen()
 RETURNS TABLE(vendedor_id uuid, nombre text, en_base integer, rellamadas_hoy integer, intentos_hoy integer, reactivaciones_mes integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

comment on function private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz) is 'Base para gestión (B3, D3/D7-bis/D10/D11): registra un intento sobre un lead descartado del ámbito del actor (7 resultados; volver_a_llamar exige fecha futura ≤ dias_max_rellamada; descanso vigente y No contactar rechazan), escribe la actividad intento_base bajo los dos GUC, fija o limpia proxima_llamada_en y, con agendo_reunion, reactiva en la misma transacción. Idempotente por id = operación (guarda la respuesta). El enfriamiento lo pone el trigger de B4. Solo la llama la puerta crm.registrar_intento_base.';
comment on function private.trg_actividades_enfriamiento_base() is 'Base para gestión (B4/B4b, D4/D12/D13): al registrar un intento de la base sin rellamada ni cita, si el lead sigue descartado y los intentos de la ventana vigente (desde el descarte o el fin del último descanso) llegan a max_intentos, fija enfriado_hasta = hoy Lima + dias_enfriamiento. Solo actúa bajo crm.op_base_gestion = on. Constantes en private.base_gestion_constantes(). DEFINER por el molde del sello de B1; search_path vacío, dueño postgres, sin EXECUTE para la API.';
comment on function crm.obtener_base_gestion(uuid) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente, con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated.';
comment on function crm.base_gestion_resumen() is 'Base para gestión (B3, para F4): por analista activo del ámbito (Supervisión → subárbol; Gerencia → todos), leads en base, rellamadas vencidas o de hoy, intentos de hoy y reactivaciones del mes (Lima), atribuidos al DUEÑO del lead (lo que Supervisión registra sobre un lead del analista cuenta para el analista). Analistas y otros roles: 42501. DEFINER con ámbito explícito, search_path vacío, EXECUTE solo authenticated.';
drop function private.base_gestion_intentos_ciclo(uuid[], timestamptz[]);
drop function private.base_gestion_leads_de(uuid);
do $post$
begin
  if (
    (select md5(p.prosrc) = '65de1a6aaaf88c48cc22df74d8bd3a8a' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select md5(p.prosrc) = '58f71178330836139f4c505450ee462a' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and (select md5(p.prosrc) = '83813e4502f378951b50e91168e4480f' from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'))
    and (select md5(p.prosrc) = '7b63174495ad8347805d38b2cec82158' from pg_proc p where p.oid = to_regprocedure('private.trg_actividades_enfriamiento_base()'))
  ) is not true then
    raise exception 'REVERSA: los cuerpos restaurados no son los vivos del 03/10';
  end if;
end;
$post$;
notify pgrst, 'reload schema';
commit;
