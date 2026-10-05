-- 20261004045038_crm_base_gestion_ver_vetados.sql
--
-- Base para gestión del analista · B6b (F4, vista del supervisor). Decisiones de Miguel (03/10/2026, `BASE PARA GESTION/
-- F4-SUPERVISOR.md`): (1) los leads «No contactar» se ven en la lista de la base con el interruptor «Ver no contactar»,
-- SOLO Supervisión y Gerencia (opción a); (3) «Intentos de hoy» y «Reactivaciones del mes» del panel por analista se
-- abren (todo número se abre); (4) los vetados se ven completos: marca + cuándo + motivo + quién, también los que están
-- en descanso; un analista que los pida → 42501.
--
-- QUÉ:
--   · `crm.obtener_base_gestion(uuid)` → `crm.obtener_base_gestion(uuid, boolean)`: drop + create con el texto VIVO de B5
--     (20261003162400, md5 b2629fba…) y estas sustituciones, nada más:
--       - parámetro nuevo `p_incluir_vetados boolean default false` (null = false). Con true y un rol que no sea
--         Supervisión o Gerencia → 42501 (antes de mirar p_vendedor_id);
--       - filtro del veto `not l.no_contactar` → `(not l.no_contactar or v_vetados)`; el del descanso deja pasar SOLO a
--         los vetados cuando v_vetados (un no vetado en descanso sigue fuera);
--       - `rellamada_hoy` = false para un vetado (nunca va a «Llamar hoy») y los vetados van al FINAL del orden;
--       - cuatro columnas nuevas AL FINAL: no_contactar, no_contactar_en, no_contactar_motivo, no_contactar_por. Salen de
--         la nota del EVENTO VIGENTE del veto (metadata evento = no_contactar), solo si ese evento es un «marcar» (también
--         el de postventa, con el motivo en el detalle «No contactar: …») y su lead es visible para quien llama; si no, NULL.
--         Evento vigente (Codex r2 + auditor-rls r2, 04/10): marcar_no_contactar, levantar_no_contactar y postventa_veto_fn
--         cambian `no_contactar` en TODOS los leads de la persona pero escriben la nota solo en el lead desde el que se
--         opera (postventa, en todos). Por eso, si el lead tiene persona y la persona está vetada, el evento vigente es la
--         ÚLTIMA nota del veto entre TODOS los leads de esa persona — el mismo conjunto que actualizan esas puertas:
--         private.leads_de_persona_veto(persona) ∪ el propio lead (20260910150039:904 y 20261002061500:152; postventa
--         20260910150039:477) —, por creado_en desc, id desc. Si no hay persona o la persona no está vetada (veto solo del
--         lead, p. ej. con la bandera resolver_en_puertas apagada), la última nota del propio lead. La persona se resuelve
--         EXACTAMENTE como marcar/levantar: enlace leads.inversionista_id; si no, puente crm.inversionista_leads (canónica,
--         rol canónico primero); si no, private.inversionista_por_documento('DNI', dni) (20260910150039:855-872,
--         20261002061500:103-120). Sin anclas por hora: el orden lo da el sello del servidor (trg_01_gestion_lead_serializada
--         fija creado_en := clock_timestamp() en toda nota con usuario, también la de postventa). La regla anterior por hora
--         (nota ≥ inversionistas.no_contactar_en, con holgura para postventa) no distinguía periodos de veto: Codex r2 dio
--         dos contraejemplos (postventa → levantar → re-vetar en < 60 s; y marcar → levantar → marcar en UNA transacción,
--         donde no_contactar_en vuelve a valer el now() de la transacción).
--         Si el lead del evento vigente no es visible para quien llama (private.base_gestion_lead_visible, y activo), NULL:
--         no se expone el motivo ni el autor escrito en un lead de otro equipo.
--         Residuo: dos notas con el MISMO clock_timestamp (prácticamente imposible) se desempatan por id. Un lead vetado
--         enlazado a una persona NO vetada (veto solo del lead) muestra su propia nota (con la regla por hora salía NULL).
--     Con p_incluir_vetados = false el resultado es IDÉNTICO al de B5 (mismas filas, mismo orden; las columnas nuevas en
--     false/NULL): el postflight lo acredita con los datos de la base, como Gerencia, contra una foto tomada en esta
--     misma transacción antes del drop.
--   · NUEVA `crm.base_gestion_resumen_detalle(uuid, text)`: las filas detrás de «Intentos de hoy» y «Reactivaciones del
--     mes» de un analista. Mismo rol que `crm.base_gestion_resumen` (analista → 42501), mismo ámbito (el analista tiene
--     que ser una fila de ESE resumen: se le pregunta a él, sin copiar su predicado; si no → P0002) y los MISMOS
--     predicados de las dos cifras (atribución al dueño actual vía `private.base_gestion_leads_de`, día y mes de Lima):
--     filas del detalle = cifra del resumen. `sigue_en_base` = el lead está hoy en `crm.obtener_base_gestion` del
--     analista (una sola definición de la base). Un lead retirado (activo = false) cuenta igual que en la cifra, pero
--     sin nombre ni nota: la policy leads_select no deja leerlo.
--   Ninguna de las dos usa contadores: fuera del censo analítico (foto antes/después en el postflight).
--   `crm.base_gestion_resumen` NO se toca (sigue llamando a la lista sin parámetros: no cuenta vetados).
--   ⚠️ Desde aquí la lista tiene DOS envoltorios DEFINER en la base: el resumen y la detalle. El preflight «único
--   envoltorio» de esta migración ya NO vale para las siguientes: si cambian leads_select o el gate de actor, re-auditar
--   las dos (memoria «espejo de leads_select»).
--   La policy actividades_insert deja insertar desde la API una nota con evento = no_contactar / accion = marcar (quien
--   escribe en el lead podría «firmar» el motivo que se muestra, con él como autor): se cierra en B6c (decisión de Miguel
--   04/10); esta migración no lo toca.
--   CONSISTENCIA (Codex r1, P2): la transacción va en REPEATABLE READ, primera sentencia tras el begin: la foto previa, el
--   postflight y el bucle resumen/detalle ven la MISMA instantánea aunque otra sesión registre intentos o reactive en
--   medio (en READ COMMITTED eso revertía una migración correcta). Precedente aplicado en producción con `!` (db query
--   --linked --file): 20260930172255 y 20260831060000.
-- PRECONDICIÓN: B5 aplicada (md5 de obtener_base_gestion y del resumen en el preflight); su único envoltorio en la base es
-- el resumen (preflight). La pantalla viva valida la fila con `v.object` (claves nuevas se ignoran) y llama sin
-- parámetro o con `p_vendedor_id`: sigue funcionando.
--
-- REVERSA: `supabase/scripts/base-gestion/reversa-b6b.sql` (borra la detalle y reinstala la firma y el cuerpo de B5). No
-- toca datos.
begin;
-- Codex r1 (P2): una sola instantánea para la foto y el postflight. Tiene que ir ANTES de cualquier consulta.
set transaction isolation level repeatable read;
set local lock_timeout = '10s';
set local statement_timeout = '60s';
set local search_path = '';
set local quote_all_identifiers = off;

do $preflight$
begin
  if (
    (select md5(p.prosrc) = 'b2629fba517938457b64cdbc5856ee82'
        and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'recibido_en'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid)'))
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    and to_regprocedure('crm.obtener_base_gestion(uuid,boolean)') is null
    and to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)') is null
    and (select count(*) = 1 from pg_proc p where p.proname = 'obtener_base_gestion' and p.pronamespace = 'crm'::regnamespace)
    -- Su único envoltorio en la base es el resumen (envoltorio DEFINER: todo dato nuevo sale por él).
    and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname not in ('pg_catalog', 'information_schema')
                       and p.prosrc ~ 'obtener_base_gestion'
                       and p.oid not in (coalesce(to_regprocedure('crm.obtener_base_gestion(uuid)')::oid, 0), coalesce(to_regprocedure('crm.base_gestion_resumen()')::oid, 0)))
  ) is not true then
    raise exception 'PREFLIGHT: falta B5 o el resumen no es el medido, B6b ya esta aplicada o la lista tiene otro envoltorio';
  end if;
end;
$preflight$;

-- Foto del censo analítico: el postflight exige que no cambie.
create temp table _b6b_censo_antes on commit drop as select c.objeto from private.contadores_crudos_leads_citas() c;

-- Foto de la lista VIVA (B5) como Gerencia (todo el ámbito), con su orden: el postflight exige la misma con false.
create temp table _b6b_lista_antes (ord bigint, fila text) on commit drop;
do $foto$
declare
  v_ger uuid;
begin
  select e.perfil_id into v_ger from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if v_ger is null then
    raise notice 'base_gestion_ver_vetados: sin Gerencia activa en esta base; la identidad con B5 NO RUN';
    return;
  end if;
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
  insert into pg_temp._b6b_lista_antes (ord, fila)
  select t.ordinality, row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado,
                           t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos,
                           t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta,
                           t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en)::text
    from crm.obtener_base_gestion() with ordinality t;
  insert into pg_temp._b6b_lista_antes (ord, fila) values (0, 'gerencia:' || v_ger::text);  -- quién hizo la foto
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
end;
$foto$;

-- ── La lista, con los vetados a pedido ──────────────────────────────────────────────────────────────────────
drop function crm.obtener_base_gestion(uuid);
create function crm.obtener_base_gestion(p_vendedor_id uuid DEFAULT NULL::uuid, p_incluir_vetados boolean DEFAULT false)
 RETURNS TABLE(lead_id uuid, nombre_completo text, telefono text, distrito text, origen text, categoria_interes text, monto_estimado numeric, moneda text, motivo_descarte text, descartado_en timestamp with time zone, dias_desde_descarte integer, etapa_maxima text, intentos integer, ultimo_resultado text, ultimo_intento_en timestamp with time zone, proxima_llamada_en timestamp with time zone, rellamada_hoy boolean, enfriado_hasta date, ciclo_n integer, vendedor_id uuid, gestiona text, recibido_en timestamp with time zone, no_contactar boolean, no_contactar_en timestamp with time zone, no_contactar_motivo text, no_contactar_por text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_vetados boolean := coalesce(p_incluir_vetados, false);  -- B6b: null = false
begin
  v_rol := private.base_gestion_rol(v_uid);
  -- B6b (Miguel, 03/10/2026): los leads «No contactar» solo los ven Supervisión y Gerencia, y solo si los piden.
  if v_vetados and (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervision y Gerencia ven los leads marcados No contactar' using errcode = '42501';
  end if;
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
           coalesce(l.tenencia_desde, l.creado_en) as recibido_en,  -- B5: cuando le llego el lead a quien lo tiene (el MES del lead)
           l.no_contactar,  -- B6b: solo puede venir en true si se pidieron los vetados
           l.inversionista_id, l.dni,  -- B6b: para resolver la persona del lead (no se devuelven)
           private.base_gestion_intentos_desde(l.descartado_en, l.creado_en, l.enfriado_hasta, v_hoy) as desde  -- D13: ventana desde el descarte o desde el fin del ultimo descanso
    from crm.leads l
    where l.activo and l.etapa = 'descartado' and (not l.no_contactar or v_vetados)  -- B6b: los vetados, solo a pedido
      and (l.enfriado_hasta is null or l.enfriado_hasta <= v_hoy or (v_vetados and l.no_contactar))  -- B6b: un vetado en descanso tambien se ve; un no vetado en descanso, no
      and private.base_gestion_lead_visible(v_uid, v_rol, l.vendedor_id, l.asignado_supervisor_id)
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
  ),
  intentos as (
    -- B3c: contador, último resultado (desempate por intento_n, Codex B3 #5) y último intento salen de la MISMA definición
    -- que usan el núcleo y el enfriamiento: private.base_gestion_intentos_ciclo, con la ventana D13 de cada lead.
    select c.lead_id, c.n, c.ultimo, c.ultimo_en
    from (select array_agg(b.id order by b.id) as ids, array_agg(b.desde order by b.id) as desdes from base b) q
    cross join lateral private.base_gestion_intentos_ciclo(q.ids, q.desdes) c
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
  ),
  marca as (
    -- B6b: cuándo, por qué y quién marcó «No contactar». Evento vigente del veto: si el lead tiene persona y la persona está
    -- vetada, la ÚLTIMA nota del veto entre TODOS los leads de la persona (los que marcar/levantar/postventa actualizan); si
    -- no, la última nota del propio lead. Se muestra solo si ese evento es un «marcar» y su lead es visible para quien llama.
    select b.id as lead_id, ev.creado_en, ev.motivo, ev.creado_por
    from base b
    cross join lateral (
      -- La persona, EXACTAMENTE como la resuelven marcar/levantar: enlace; si no, puente (canónica); si no, DNI.
      select coalesce(b.inversionista_id,
                      (select private.inversionista_canonica(il.inversionista_id) from crm.inversionista_leads il
                        where il.lead_id = b.id order by (il.rol = 'canonico') desc, il.inversionista_id limit 1),
                      private.inversionista_por_documento('DNI', b.dni)) as id
    ) pe
    left join crm.inversionistas i on i.id = pe.id
    cross join lateral (
      -- La más reciente entre las ÚLTIMAS notas de cada lead del conjunto: cada una sale del índice (lead_id, creado_en desc).
      select n.ev_lead, n.creado_en, n.accion, n.creado_por, n.motivo
        from (select b.id as lid
              union
              select x from private.leads_de_persona_veto(pe.id) x where i.no_contactar is true) s  -- el conjunto de las puertas
        cross join lateral (
          select a.lead_id as ev_lead, a.creado_en, a.id, a.metadata->>'accion' as accion, a.creado_por,
                 coalesce(a.metadata->>'motivo',
                          case when a.metadata ? 'postventa_gestion_id' then pg_catalog.regexp_replace(a.detalle, '^No contactar: ', '') end) as motivo
            from crm.actividades a
           where a.lead_id = s.lid and a.metadata->>'evento' = 'no_contactar'
           order by a.creado_en desc, a.id desc
           limit 1
        ) n
       order by n.creado_en desc, n.id desc
       limit 1
    ) ev
    join crm.leads le on le.id = ev.ev_lead
    where b.no_contactar and ev.accion = 'marcar'
      and le.activo and private.base_gestion_lead_visible(v_uid, v_rol, le.vendedor_id, le.asignado_supervisor_id)  -- nada de otro equipo
  )
  select b.id, b.nombre_completo, b.telefono, b.distrito, b.origen, b.categoria_interes, b.monto_estimado, b.moneda,
         b.motivo_descarte, b.descartado_en,
         case when b.descartado_en is null then null else (v_hoy - (b.descartado_en at time zone 'America/Lima')::date)::integer end,
         case coalesce(e.rango, 0) when 1 then 'nuevo' when 2 then 'contactado' when 3 then 'reunion_agendada'
                                   when 4 then 'propuesta_enviada' when 5 then 'convertido' else 'sin_datos' end,
         coalesce(i.n, 0), i.ultimo, i.ultimo_en,
         b.proxima_llamada_en,
         (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy),  -- B6b: un vetado nunca va a «Llamar hoy»
         b.enfriado_hasta, b.ciclo_actual, b.vendedor_id, p.nombre_completo, b.recibido_en,
         b.no_contactar, m.creado_en, m.motivo, pm.nombre_completo
  from base b
  left join intentos i on i.lead_id = b.id
  left join etapas e on e.lead_id = b.id
  left join public.perfiles p on p.id = b.vendedor_id
  left join marca m on m.lead_id = b.id
  left join public.perfiles pm on pm.id = m.creado_por
  -- Contrato (encargo): rellamada vencida o de hoy → etapa maxima (desc) → dias desde el descarte (asc); la hora de la
  -- rellamada solo desempata (Codex B3 #4). B6b: los vetados, al final (sin vetados el orden es el de B5).
  order by b.no_contactar,
           (not b.no_contactar and b.proxima_llamada_en is not null and (b.proxima_llamada_en at time zone 'America/Lima')::date <= v_hoy) desc,
           coalesce(e.rango, 0) desc,
           (b.descartado_en at time zone 'America/Lima')::date desc nulls last,  -- menos dias desde el descarte primero
           b.proxima_llamada_en asc nulls last,
           b.id;
end;
$function$;
alter function crm.obtener_base_gestion(uuid, boolean) owner to postgres;
revoke all on function crm.obtener_base_gestion(uuid, boolean) from public, anon, authenticated, service_role;
grant execute on function crm.obtener_base_gestion(uuid, boolean) to authenticated;
comment on function crm.obtener_base_gestion(uuid, boolean) is 'Base para gestión (B3): leads descartados vivos del ámbito del actor (analista → los suyos; Supervisión → subárbol; Gerencia → todo), sin «no contactar» ni descanso vigente (salvo p_incluir_vetados, ver B6b), con intentos del ciclo, último resultado, próxima rellamada, etapa máxima alcanzada y quién gestiona. Orden: rellamada vencida o de hoy → etapa máxima → menos días desde el descarte. p_vendedor_id filtra un analista dentro del ámbito. DEFINER: ámbito explícito (espejo de leads_select), search_path vacío, EXECUTE solo authenticated. B3c (03/10/2026): sus conteos de intentos salen de private.base_gestion_intentos_ciclo; fuera del censo analítico. B5 (03/10/2026): devuelve al final recibido_en = coalesce(tenencia_desde, creado_en), cuándo le llegó el lead a quien lo tiene: el MES por el que se organiza el analista. B6b (03/10/2026, F4): p_incluir_vetados (default false; null = false) suma los leads «No contactar» del ámbito, también los que están en descanso; solo Supervisión y Gerencia (otro rol → 42501). Los vetados van al final y nunca en «Llamar hoy» (rellamada_hoy = false). Columnas finales no_contactar, no_contactar_en, no_contactar_motivo y no_contactar_por (nombre del autor): de la nota del evento vigente del veto — si la persona del lead (enlace, puente o DNI, como en marcar/levantar) está vetada, la última nota del veto entre los leads de la persona (private.leads_de_persona_veto ∪ el propio lead); si no, la del propio lead — solo si es un «marcar» (también el de postventa, motivo en el detalle) y su lead es visible para quien llama; si no, NULL. Residuo: empate exacto de clock_timestamp, desempate por id. La nota de veto que actividades_insert deja escribir desde la API se cierra en B6c (decisión de Miguel 04/10). Con false, el resultado es el de B5. Envoltorios DEFINER en la base: crm.base_gestion_resumen y crm.base_gestion_resumen_detalle (re-auditarlos si cambia leads_select).';

-- ── El detalle de las cifras del panel por analista ─────────────────────────────────────────────────────────
create function crm.base_gestion_resumen_detalle(p_vendedor_id uuid, p_cifra text)
 RETURNS TABLE(lead_id uuid, nombre_completo text, en timestamp with time zone, detalle text, autor text, sigue_en_base boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_hoy date := (now() at time zone 'America/Lima')::date;
begin
  -- B6b (Miguel, 03/10/2026: «todo número se abre»): las filas detrás de una cifra de crm.base_gestion_resumen.
  v_rol := private.base_gestion_rol(v_uid);
  if (v_rol in ('supervisor', 'gerencia')) is not true then
    raise exception 'Solo Supervision y Gerencia ven el resumen de la base' using errcode = '42501';
  end if;
  if p_cifra is null or p_cifra not in ('intentos_hoy', 'reactivaciones_mes') then
    raise exception 'Cifra invalida: se espera intentos_hoy o reactivaciones_mes' using errcode = '22023';
  end if;
  if p_vendedor_id is null then
    raise exception 'Indica el analista' using errcode = '22023';
  end if;
  -- Mismo ámbito que el resumen: el analista tiene que ser una fila de ESE resumen (se le pregunta a él; sin copiar su predicado).
  if not exists (select 1 from crm.base_gestion_resumen() r where r.vendedor_id = p_vendedor_id) then
    raise exception 'Analista no encontrado o fuera de tu ambito' using errcode = 'P0002';
  end if;
  -- Los predicados de cada cifra son, letra por letra, los de crm.base_gestion_resumen (atribución al DUEÑO actual del
  -- lead; día y mes de Lima): filas = cifra. Un lead retirado (activo = false) cuenta como en la cifra, sin nombre ni nota.
  if p_cifra = 'intentos_hoy' then
    return query
    select a.lead_id, case when l.activo then l.nombre_completo end, a.creado_en, a.metadata->>'resultado', pa.nombre_completo,
           a.lead_id in (select g.lead_id from crm.obtener_base_gestion(p_vendedor_id) g)
      from crm.actividades a join private.base_gestion_leads_de(p_vendedor_id) d on d.lead_id = a.lead_id
      join crm.leads l on l.id = a.lead_id
      left join public.perfiles pa on pa.id = a.creado_por
     where a.metadata->>'evento' = 'intento_base'
       and a.creado_en >= (v_hoy::timestamp at time zone 'America/Lima')
       and (a.creado_en at time zone 'America/Lima')::date = v_hoy
     order by a.creado_en desc, a.id desc;
  else
    return query
    select a.lead_id, case when l.activo then l.nombre_completo end, a.creado_en, case when l.activo then a.detalle end, pa.nombre_completo,
           a.lead_id in (select g.lead_id from crm.obtener_base_gestion(p_vendedor_id) g)
      from crm.actividades a join private.base_gestion_leads_de(p_vendedor_id) d on d.lead_id = a.lead_id
      join crm.leads l on l.id = a.lead_id
      left join public.perfiles pa on pa.id = a.creado_por
     where a.metadata->>'evento' = 'reactivacion_base'
       and a.creado_en >= (date_trunc('month', v_hoy::timestamp) at time zone 'America/Lima')
       and date_trunc('month', a.creado_en at time zone 'America/Lima') = date_trunc('month', v_hoy::timestamp)
     order by a.creado_en desc, a.id desc;
  end if;
end;
$function$;
alter function crm.base_gestion_resumen_detalle(uuid, text) owner to postgres;
revoke all on function crm.base_gestion_resumen_detalle(uuid, text) from public, anon, authenticated, service_role;
grant execute on function crm.base_gestion_resumen_detalle(uuid, text) to authenticated;
comment on function crm.base_gestion_resumen_detalle(uuid, text) is 'Base para gestión (B6b, F4, 03/10/2026: «todo número se abre»): las filas detrás de una cifra de crm.base_gestion_resumen para UN analista. p_vendedor_id: el analista (obligatorio; tiene que ser una fila del resumen del actor, si no → P0002). p_cifra: intentos_hoy (intentos de la base de hoy en Lima sobre sus leads, registre quien registre; detalle = el resultado) o reactivaciones_mes (reactivaciones del mes en Lima; detalle = la nota); otro valor → 22023. Mismo rol que el resumen (Supervisión y Gerencia; el resto → 42501) y mismos predicados: tantas filas como la cifra. Salida: lead, nombre, en (cuándo), detalle, autor (quién lo registró) y sigue_en_base (el lead está hoy en crm.obtener_base_gestion del analista). Un lead retirado cuenta igual, sin nombre ni nota (la RLS no deja leerlo). Más reciente primero. DEFINER con ámbito del resumen, search_path vacío, EXECUTE solo authenticated; sin contadores (fuera del censo analítico). Es un envoltorio DEFINER nuevo de crm.obtener_base_gestion (sigue_en_base) y de crm.base_gestion_resumen (ámbito): si cambian leads_select o el gate de actor, re-auditarla.';

do $postflight$
declare
  v_ger uuid;
  v_vend uuid;
  v_r record;
  v_n_antes bigint;
  v_n_despues bigint;
  v_primero boolean := true;
begin
  -- 1. Cuerpos ensayados en el banco, contrato DEFINER/postgres/search_path vacío, ACL exacta, una sola sobrecarga.
  if (
    (select md5(p.prosrc) = '36af7e9cc4d6ec319b3d8004f3903473'
        and p.pronargs = 2 and p.pronargdefaults = 2
        and p.proargnames[pg_catalog.array_length(p.proargnames, 1)] = 'no_contactar_por'
        and p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'))
    and to_regprocedure('crm.obtener_base_gestion(uuid)') is null
    and (select count(*) = 1 from pg_proc p where p.proname = 'obtener_base_gestion' and p.pronamespace = 'crm'::regnamespace)
    and obj_description(to_regprocedure('crm.obtener_base_gestion(uuid,boolean)'), 'pg_proc') like '%B6b (03/10/2026, F4)%'
    and (select md5(p.prosrc) = '068372248be4127c80ba002542c9b4b8'
        and p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole
        and p.proconfig = array['search_path=""']::text[] and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)'))
    and (select count(*) = 1 from pg_proc p where p.proname = 'base_gestion_resumen_detalle' and p.pronamespace = 'crm'::regnamespace)
    and obj_description(to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)'), 'pg_proc') like 'Base para gestión (B6b%'
    -- El resumen no cambia (sigue llamando a la lista sin parámetros: no cuenta vetados).
    and (select md5(p.prosrc) = 'b773a7c49fbdfc45133b3405991b1958' and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
       from pg_proc p where p.oid = to_regprocedure('crm.base_gestion_resumen()'))
    -- El censo analítico no cambia y ninguna de las dos entra.
    and not exists (select 1 from private.contadores_crudos_leads_citas() c
                     where c.objeto in (to_regprocedure('crm.obtener_base_gestion(uuid,boolean)')::text,
                                        to_regprocedure('crm.base_gestion_resumen_detalle(uuid,text)')::text))
    and not exists (select 1 from private.contadores_crudos_leads_citas() c where c.objeto not in (select a.objeto from pg_temp._b6b_censo_antes a))
    and (select count(*) from pg_temp._b6b_censo_antes) = (select count(*) from private.contadores_crudos_leads_citas())
  ) is not true then
    raise exception 'POSTFLIGHT: obtener_base_gestion o la detalle no quedaron con el cuerpo ensayado, el contrato o la ACL exacta, el resumen cambio o el censo se movio';
  end if;

  -- 2. Con false, la lista es la de B5 (mismas filas y mismo orden) para la Gerencia de la foto; null = false; las columnas
  --    nuevas en false/NULL. El resumen y la detalle se ejecutan, y la detalle da tantas filas como su cifra.
  select pg_catalog.substr(a.fila, 10)::uuid into v_ger from pg_temp._b6b_lista_antes a where a.ord = 0;
  if v_ger is not null then
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    select count(*) into v_n_antes from pg_temp._b6b_lista_antes a where a.ord > 0;
    select count(*) into v_n_despues from crm.obtener_base_gestion(null, false);
    if (
      v_n_antes = v_n_despues
      and not exists (
        select t.ordinality, row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado,
                                 t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos,
                                 t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta,
                                 t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en)::text
          from crm.obtener_base_gestion(null, false) with ordinality t
        except all
        select a.ord, a.fila from pg_temp._b6b_lista_antes a where a.ord > 0)
      and not exists (
        select t.ordinality, t::text from crm.obtener_base_gestion(null, null) with ordinality t
        except all
        select t.ordinality, t::text from crm.obtener_base_gestion(null, false) with ordinality t)
      and not exists (select 1 from crm.obtener_base_gestion() t
                       where t.no_contactar or t.no_contactar_en is not null or t.no_contactar_motivo is not null or t.no_contactar_por is not null)
    ) is not true then
      raise exception 'POSTFLIGHT: con p_incluir_vetados = false la lista no es la de B5 (antes % filas, despues %)', v_n_antes, v_n_despues;
    end if;
    -- Las dos ramas de la detalle se ejecutan al menos una vez (compilarlas) y, en todo analista con cifra, filas = cifra.
    for v_r in select r.vendedor_id, r.intentos_hoy, r.reactivaciones_mes from crm.base_gestion_resumen() r loop
      if v_primero or v_r.intentos_hoy > 0 or v_r.reactivaciones_mes > 0 then
        if ((select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'intentos_hoy')) = v_r.intentos_hoy
            and (select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'reactivaciones_mes')) = v_r.reactivaciones_mes) is not true then
          raise exception 'POSTFLIGHT: la detalle no da tantas filas como la cifra del resumen para el analista %', v_r.vendedor_id;
        end if;
        v_primero := false;
      end if;
    end loop;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;

  -- 3. Un analista que pide los vetados → 42501 (sin escribir).
  select e.perfil_id into v_vend from crm.equipo e
   where e.activo and private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  if v_vend is not null then
    begin
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_vend, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_vend::text, true);
      perform 1 from crm.obtener_base_gestion(null, true);
      raise exception 'POSTFLIGHT: un analista pudo pedir los vetados' using errcode = 'P0001';
    exception when insufficient_privilege then
      if sqlerrm <> 'Solo Supervision y Gerencia ven los leads marcados No contactar' then
        raise exception 'POSTFLIGHT: el analista fue rechazado por otro motivo: %', sqlerrm using errcode = 'P0001';
      end if;
    end;
    perform pg_catalog.set_config('request.jwt.claims', '', true);
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  else
    raise notice 'base_gestion_ver_vetados: sin analista activo en esta base; el negativo del analista NO RUN';
  end if;
  raise notice 'base_gestion_ver_vetados OK: vetados solo a pedido de Supervision/Gerencia, con false la lista de B5 (% filas), detalle = cifra, ACL exacta, censo intacto', coalesce(v_n_despues::text, 'sin foto');
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
