-- B10 · Bases cargadas: seguimiento, la base en la lista del analista y el capital al reactivar (20261004223253), en el banco.
-- UNA transacción con impersonación (claims + set local role), statement_timeout de authenticated (8 s) y ROLLBACK al final.
-- Falla el proceso si hay un FAIL. Corre sobre un banco LOCAL con B7, B8, B9 r2 y B10 aplicadas, los actores de seed:demo y SIN
-- bases (correr limpiar-entre-corridas.sql o el gate antes). Siembra leads b1000000-… y teléfonos 96679xxxx, que se deshacen.
-- Las bases se cargan por las PUERTAS reales de B8 (crear_base, cargar_base_lote, armar_base_crm) y se REPARTEN y RECOGEN por
-- las de B9 (crm.repartir_base, crm.recoger_de_base: r2, nada simulado). Andamio de fechas (como postgres): tras el reparto
-- real, pg_temp.repartir fecha asignado_en y su «reasignación» en el día pedido, para probar los bordes (sin tocar 3 días, un
-- intento anterior al reparto); la sección U reparte y recoge sin tocar fechas.
-- Qué prueba:
--   A catálogo: puertas DEFINER con EXECUTE solo authenticated, núcleo cerrado, la puerta publicada de reactivar y el intento
--     INTACTOS, el núcleo de 4 argumentos sustituido por el de 6, una sola sobrecarga, la copia de B6b exacta, censo;
--   B equivalencia SIN bases: la lista nueva (26 columnas de B6b) = la COPIA EXACTA del cuerpo vivo de B6b, actor por actor,
--     con y sin vetados y con analista, en filas y orden; base_id y base_nombre NULL;
--   C mundo: 5 bases por las puertas de B8 (Feria de sup1 con 16 contactos en 13 estados, Sur de sup2 con una pertenencia
--     retirada, Anidada del sup anidado, Retirada —base inactiva— y Armada desde el CRM con 2 descartados de vend1);
--   D la lista con bases: fuera los dormidos SIN REPARTIR (Supervisión y Gerencia, con y sin vetados); dentro los repartidos
--     (el analista los ve con base_nombre), los armados con analista, los movidos a la bandeja, los de una base retirada o
--     una pertenencia retirada (sin base); equivalencia con B6b menos los excluidos (independiente del ayudante);
--   E seguimiento: cada cifra de cada base y de cada analista con su valor esperado; estados; rojo a los 3 días (borde);
--     descanso (borde); desde asignado_en (un intento anterior no cuenta); identidades ocultas fuera del ámbito; cifra = detalle
--     para TODA base y analista (Supervisión y Gerencia) y suma por analista = cifra de la base;
--   F roles: analista, coordinación, desactivado → 42501; anon y service_role sin EXECUTE; otro supervisor y el anidado → P0002;
--     base retirada → P0002; cifra inválida («avance», NULL, otra) → 22023; analista sin contactos en la base → P0002;
--   G capital al reactivar: puerta publicada y _v2 sin capital → 22023; forma del capital y de la moneda → 22023; con capital
--     → contactado, capital en el lead y en el episodio, moneda NULL = la del lead; con capital ya puesto se ignora; replay;
--     supervisor; fuera del ámbito → P0002; sin sesión → 42501; «agendó cita» sin capital → 22023 sin dejar intento; la puerta
--     publicada con un lead con capital, igual que antes (mismas claves); el intento «agendó cita» por la puerta publicada y por
--     registrar_intento_base_v2 sin capital → 22023 sin dejar intento; con capital → reactiva con ese capital; un intento normal
--     sin capital, igual que hoy (la _v2 ignora el capital);
--   H F4: el resumen y su detalle siguen cuadrando (Supervisión y Gerencia) y «en base» = la lista del analista.
--   r1 (Codex P2 y auditor-rls P3): «sin repartir» = DISPONIBLE (una definición, la misma de la exclusión de la lista): cada
--     contacto con su estado esperado ESCRITO A MANO (sin el arreglo de cifras): asignado por otra vía antes del reparto, retirado,
--     vetado, reactivado (y luego movido o no), movido a otra bandeja, recogido, armado con su analista, armado de una bandeja;
--     los vetados sin repartir salen en «Ver no contactar»; base_nombre solo si se ve la base o es el analista del lead;
--     seguimiento_base sin analista_id fuera del ámbito; el capital en la identidad del replay y el capital efectivo en la respuesta.
--   r3 (coordinador, E1): un armado desde el CRM que conserva su analista anterior es «sin repartir» y el bloque lo elige (si
--     ese analista lo trabaja, «trabajado»); un sin reparto que salió del descarte con cita o reactivación de la base es
--     cita/reactivado (como B9); la lista oculta SOLO a los dormidos del ARCHIVO sin repartir (un armado nunca se oculta).
--   r2 (coordinador): U · la definición ÚNICA del estado (private.bases_carga_estado_contacto) en B9 y B10: su tabla de verdad;
--     el bloque de crm.repartir_base elige SOLO el estado sin_repartir (nunca un armado con su analista previo, un movido, un
--     vetado o uno en descanso) y los nombra en omitidos; el individual rechaza lo movido y acepta al analista previo; recoger =
--     el estado sin_tocar (un vetado no se recoge); crm.contactos_de_base devuelve el MISMO estado que el seguimiento y su filtro
--     «sin_repartir» = la cifra sin_repartir; el intento por registrar_intento_base_v2 escribe la metadata del intento como el
--     núcleo de B3c y su rellamada activa el candado de B9 (private.base_gestion_en_gestion_hasta → individual en_gestion).
-- Mutantes: `node supabase/scripts/base-gestion/b10-mutantes.mjs --puerto <puerto>` inyecta cada uno en @@MUTANTE@@.
\set ON_ERROR_STOP on
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b10-seguimiento: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
set local statement_timeout = '8s';
-- @@MUTANTE@@

-- Copia EXACTA del cuerpo vivo de B6b (20261004045038, md5 36af7e9c…) en pg_temp: el oráculo de «lo demás, idéntico».
create function pg_temp.b6b_obtener(p_vendedor_id uuid DEFAULT NULL::uuid, p_incluir_vetados boolean DEFAULT false)
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

-- ───────── Utilidades (pg_temp: se van con el ROLLBACK) ─────────
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
create temp table c (clave text primary key, id uuid);   -- contactos del mundo por clave (F01…, D1, G1…)
create temp table bx (nombre text primary key, id uuid);  -- bases por nombre
create function pg_temp.sesion(p uuid, p_rol text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true),
         set_config('request.jwt.claims', case when p is null and p_rol = 'authenticated' then ''
                                               else json_build_object('sub', p, 'role', p_rol)::text end, true);
$$;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
-- valor: primer valor de p_sql como p_uid —con p_rol: SET ROLE (la ruta real); sin él: postgres con los claims— o
-- «ERROR <sqlstate> <mensaje>»; deshace todo.
create function pg_temp.valor(p_sql text, p_uid uuid default null, p_rol text default null) returns text language plpgsql as $$
declare v text; v_ok boolean := false;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol in ('anon', 'service_role') then p_rol else 'authenticated' end);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql into v;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'B10_DESHACER';
  exception when others then
    if not v_ok then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  perform pg_temp.sesion(null);
  return coalesce(v, '(nulo)');
end $$;
-- ejecutar: corre p_sql como authenticated con el usuario p_uid y CONSERVA su efecto. Si falla, devuelve «ERROR …» (deshace
-- lo suyo) y la suite sigue: los casos que dependen de ese resultado caen con su nombre.
create function pg_temp.ejecutar(p_sql text, p_uid uuid) returns text language plpgsql as $$
declare v text;
begin
  begin
    perform pg_temp.sesion(p_uid);
    execute 'set local role authenticated';
    execute p_sql into v;
    execute 'reset role';
  exception when others then
    v := 'ERROR ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.sesion(null);
  return v;
end $$;
-- repartir: crm.repartir_base REAL (B9, individual: un contacto a un analista) como p_actor; si no reparte exactamente 1, la
-- suite aborta (el mundo no sería el contado a mano). Andamio de fechas (como postgres): asignado_en y la «reasignación» que
-- escribió el reparto se fechan en p_en.
create function pg_temp.repartir(p_lead uuid, p_analista uuid, p_actor uuid, p_en timestamptz) returns void language plpgsql as $$
declare v_base uuid; v_r text; v_desde timestamptz := clock_timestamp();
begin
  select bl.base_id into v_base from crm.base_carga_leads bl where bl.lead_id = p_lead and bl.activo;
  v_r := pg_temp.ejecutar(format('select crm.repartir_base(gen_random_uuid(), %L, %L::jsonb)::text', v_base,
           jsonb_build_object('modo', 'individual', 'asignaciones', jsonb_build_array(jsonb_build_object('lead_id', p_lead, 'analista_id', p_analista)))), p_actor);
  if v_r is null or v_r like 'ERROR%' or (v_r::jsonb ->> 'repartidos') is distinct from '1' then
    raise exception 'b10-seguimiento: el reparto REAL de % no repartió 1: %', p_lead, v_r;
  end if;
  update crm.base_carga_leads set asignado_en = p_en where lead_id = p_lead and activo;
  update crm.actividades set creado_en = p_en where lead_id = p_lead and tipo = 'reasignacion' and creado_en >= v_desde;
end $$;
-- recoger: crm.recoger_de_base REAL (B9) como p_actor: la respuesta (o «ERROR …»).
create function pg_temp.recoger(p_base uuid, p_analista uuid, p_actor uuid) returns text language sql as $$
  select pg_temp.ejecutar(format('select crm.recoger_de_base(gen_random_uuid(), %L, %L)::text', p_base, p_analista), p_actor) $$;
-- bloque: crm.repartir_base REAL en bloque (un analista, una cantidad) como p_actor: la respuesta (o «ERROR …»).
create function pg_temp.bloque(p_base uuid, p_analista uuid, p_n int, p_actor uuid) returns text language sql as $$
  select pg_temp.ejecutar(format('select crm.repartir_base(gen_random_uuid(), %L, %L::jsonb)::text', p_base,
    jsonb_build_object('modo', 'bloque', 'asignaciones', jsonb_build_array(jsonb_build_object('analista_id', p_analista, 'cantidad', p_n)))), p_actor) $$;
-- individual: crm.repartir_base REAL individual (varios contactos a un analista) como p_actor: la respuesta (o «ERROR …» con
-- el detail de los rechazados).
create function pg_temp.individual(p_base uuid, p_leads uuid[], p_analista uuid, p_actor uuid) returns text language plpgsql as $$
declare v text;
begin
  begin
    perform pg_temp.sesion(p_actor);
    execute 'set local role authenticated';
    select crm.repartir_base(gen_random_uuid(), p_base, jsonb_build_object('modo', 'individual', 'asignaciones',
             (select jsonb_agg(jsonb_build_object('lead_id', x, 'analista_id', p_analista) order by o) from unnest(p_leads) with ordinality u(x, o))))::text into v;
    execute 'reset role';
  exception when others then
    declare d text;
    begin
      get stacked diagnostics d = pg_exception_detail;
      v := 'ERROR ' || sqlstate || ' ' || coalesce(d, '');
    end;
  end;
  perform pg_temp.sesion(null);
  return v;
end $$;
-- El subárbol de un supervisor (oráculo, independiente de private.bases_carga_subarbol).
create function pg_temp.subarbol(p uuid) returns setof uuid language sql security definer set search_path = '' as $$
  with recursive s as (select e.perfil_id from crm.equipo e where e.perfil_id = p
                       union select e.perfil_id from crm.equipo e join s on e.supervisor_id = s.perfil_id)
  select s.perfil_id from s $$;
-- Los «sin repartir» (disponibles), escritos aparte del ayudante (joins y NOT EXISTS): oráculo de la exclusión. r2: también
-- en el ámbito del dueño (su bandeja o la de un supervisor de su subárbol) y sin descanso.
create function pg_temp.excluidos() returns setof uuid language sql security definer set search_path = '' as $$
  select l.id from crm.leads l
    join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo and bl.procedencia = 'archivo'  -- r3: solo los dormidos del archivo
    join crm.bases_carga b on b.id = bl.base_id and b.activo
   where bl.analista_id is null and l.activo and not l.no_contactar and l.etapa = 'descartado' and l.vendedor_id is null
     and (l.enfriado_hasta is null or l.enfriado_hasta <= (now() at time zone 'America/Lima')::date)
     and l.asignado_supervisor_id in (select pg_temp.subarbol(b.supervisor_id))
     and (l.asignado_supervisor_id = b.supervisor_id
          or not exists (select 1 from crm.actividades a where a.lead_id = l.id and a.tipo = 'reasignacion' and a.creado_en >= bl.creado_en)) $$;
-- Huella de una lista (filas + orden) proyectada a las 26 columnas de B6b: la copia (con o sin los excluidos) y la nueva.
create function pg_temp.h_b6b(p uuid, v boolean, p_excluir boolean) returns text language sql as $$
  select count(*) || ':' || coalesce(md5(string_agg(row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text, '|' order by t.ordinality)), '-')
    from pg_temp.b6b_obtener(p, v) with ordinality t
   where not p_excluir or t.lead_id not in (select pg_temp.excluidos()) $$;
create function pg_temp.h_b10(p uuid, v boolean) returns text language sql as $$
  select count(*) || ':' || coalesce(md5(string_agg(row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte, t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en, t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en, t.no_contactar, t.no_contactar_en, t.no_contactar_motivo, t.no_contactar_por)::text, '|' order by t.ordinality)), '-')
    from crm.obtener_base_gestion(p, v) with ordinality t $$;
-- La base de un lead en la lista del actor: su base_nombre, «(sin base)» o «sin fila».
create function pg_temp.base_en_lista(p_lead uuid, p_vet boolean default false, p_v uuid default null) returns text language sql as $$
  select coalesce((select coalesce(t.base_nombre, '(sin base)') from crm.obtener_base_gestion(p_v, p_vet) t where t.lead_id = p_lead), 'sin fila') $$;
-- Una base en seguimiento_bases: «total/sin_repartir/repartidos/sin_tocar/trabajados/en_descanso/citas/reactivados/avance|
-- movidos_otra_via/retirados/no_contactar».
create function pg_temp.sb(p_nombre text) returns text language sql as $$
  select coalesce((select format('%s/%s/%s/%s/%s/%s/%s/%s/%s|%s/%s/%s', s.total, s.sin_repartir, s.repartidos, s.sin_tocar, s.trabajados, s.en_descanso,
                                 s.citas, s.reactivados, s.avance, s.movidos_otra_via, s.retirados, s.no_contactar)
                     from crm.seguimiento_bases() s where s.nombre = p_nombre), 'sin fila') $$;
-- Un analista en seguimiento_base: «asignados/sin_tocar/sin_tocar_3_dias/trabajados/en_descanso/citas/reactivados/movidos|
-- retirados/no_contactar» (p_analista NULL = la fila SIN identificar).
create function pg_temp.sa(p_base uuid, p_analista uuid) returns text language sql as $$
  select coalesce((select string_agg(format('%s/%s/%s/%s/%s/%s/%s/%s|%s/%s', s.asignados, s.sin_tocar, s.sin_tocar_3_dias, s.trabajados, s.en_descanso,
                                            s.citas, s.reactivados, s.movidos_otra_via, s.retirados, s.no_contactar), ' ; ')
                     from crm.seguimiento_base(p_base) s where s.analista_id is not distinct from p_analista), 'sin fila') $$;
-- El subárbol del usuario de la sesión (para comparar a mano qué bases ve).
create function pg_temp.sesion_subarbol() returns setof uuid language sql security definer set search_path = '' as $$
  with recursive s as (select e.perfil_id from crm.equipo e where e.perfil_id = (select auth.uid())
                       union select e.perfil_id from crm.equipo e join s on e.supervisor_id = s.perfil_id)
  select s.perfil_id from s $$;
-- El ESTADO de cada contacto de una base, por su clave (como postgres, directo del ayudante, sin máscaras): «clave:estado,…».
create function pg_temp.estados(p_base text) returns text language sql as $$
  select string_agg(c.clave || ':' || x.estado, ',' order by c.clave)
    from private.bases_carga_seguimiento_filas(array[(select b.id from pg_temp.bx b where b.nombre = p_base)], (now() at time zone 'America/Lima')::date) x
    join pg_temp.c c on c.id = x.lead_id $$;
-- Las claves (pg_temp c) de las filas visibles de un detalle, ordenadas; «?» por cada fila oculta.
create function pg_temp.claves(p_base uuid, p_analista uuid, p_cifra text) returns text language sql as $$
  select coalesce(string_agg(coalesce(c.clave, '?'), ',' order by coalesce(c.clave, '?')), '(ninguna)')
    from crm.seguimiento_base_detalle(p_base, p_analista, p_cifra) d left join pg_temp.c c on c.id = d.lead_id $$;
-- Cifra = detalle para TODA base visible y cada analista, y suma por analista = cifra de la base: «cuadra» o los descuadres.
create function pg_temp.cuadre() returns text language plpgsql as $$
declare v_b record; v_a record; v_c text; v_n bigint; v_mal text[] := '{}';
begin
  for v_b in select s.* from crm.seguimiento_bases() s loop
    foreach v_c in array array['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'en_descanso', 'citas', 'reactivados',
                               'movidos_otra_via', 'retirados', 'no_contactar'] loop
      select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, null, v_c);
      if v_n is distinct from (to_jsonb(v_b) ->> v_c)::bigint then
        v_mal := v_mal || format('%s/%s %s≠%s', v_b.nombre, v_c, to_jsonb(v_b) ->> v_c, v_n);
      end if;
    end loop;
    -- Una fila sin identificar (analista de otro equipo) no se abre por analista: se abre por la base (y entra en la suma).
    for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s where s.analista_id is not null loop
      foreach v_c in array array['asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados', 'en_descanso', 'citas', 'reactivados', 'movidos_otra_via',
                                 'retirados', 'no_contactar'] loop
        select count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_c);
        if v_n is distinct from (to_jsonb(v_a) ->> v_c)::bigint then
          v_mal := v_mal || format('%s/%s/%s %s≠%s', v_b.nombre, v_a.analista_id, v_c, to_jsonb(v_a) ->> v_c, v_n);
        end if;
      end loop;
    end loop;
    -- r2: en descanso de la base cuenta también lo SIN reparto (estado de la definición única): por analista, ≤ la base.
    if (select row(coalesce(sum(s.asignados), 0), coalesce(sum(s.sin_tocar), 0), coalesce(sum(s.trabajados), 0),
                   coalesce(sum(s.citas), 0), coalesce(sum(s.reactivados), 0))
          from crm.seguimiento_base(v_b.base_id) s)
       is distinct from row(v_b.repartidos::bigint, v_b.sin_tocar::bigint, v_b.trabajados::bigint, v_b.citas::bigint, v_b.reactivados::bigint)
       or (select coalesce(sum(s.en_descanso), 0) from crm.seguimiento_base(v_b.base_id) s) > v_b.en_descanso then
      v_mal := v_mal || format('%s: la suma por analista no es la base', v_b.nombre);
    end if;
  end loop;
  return coalesce(nullif(array_to_string(v_mal, '; '), ''), 'cuadra');
end $$;
-- F4: el detalle de cada cifra del resumen = la cifra, y «en base» = la lista del analista: «cuadra» o los descuadres.
create function pg_temp.cuadre_f4() returns text language plpgsql as $$
declare v_r record; v_mal text[] := '{}';
begin
  for v_r in select x.* from crm.base_gestion_resumen() x loop
    if (select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'intentos_hoy')) <> v_r.intentos_hoy
       or (select count(*) from crm.base_gestion_resumen_detalle(v_r.vendedor_id, 'reactivaciones_mes')) <> v_r.reactivaciones_mes
       or (select count(*) from crm.obtener_base_gestion() g where g.vendedor_id = v_r.vendedor_id) <> v_r.en_base then
      v_mal := v_mal || v_r.vendedor_id::text;
    end if;
  end loop;
  return coalesce(nullif(array_to_string(v_mal, '; '), ''), 'cuadra');
end $$;
-- El texto como jsonb, o {"error": texto} (un «ERROR …» no tumba la suite).
create function pg_temp.j(p text) returns jsonb language plpgsql as $$
begin
  return p::jsonb;
exception when others then return jsonb_build_object('error', p);
end $$;
-- Respuesta de reactivar: sus claves ordenadas.
create function pg_temp.claves_json(p text) returns text language plpgsql as $$
begin
  return (select string_agg(k, ',' order by k) from jsonb_object_keys(p::jsonb) k);
exception when others then return 'no es json: ' || coalesce(p, '(nulo)');
end $$;

-- ───────── Actores (seed:demo) y precondiciones ─────────
create temp table f as select
  (select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe') v1,
  (select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe') v2,
  (select id from auth.users where email = 'vend3.crm@demo.avancecorp.pe') v3,
  (select id from auth.users where email = 'vend-anidado.crm@demo.avancecorp.pe') va,
  (select id from auth.users where email = 'vend-inactivo.crm@demo.avancecorp.pe') vi,
  (select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe') s1,
  (select id from auth.users where email = 'sup2.crm@demo.avancecorp.pe') s2,
  (select id from auth.users where email = 'sup-anidado.crm@demo.avancecorp.pe') sa,
  (select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe') g,
  (select id from auth.users where email = 'coordinador.crm@demo.avancecorp.pe') co,
  (now() at time zone 'America/Lima')::date hoy;
alter table f add column n_v1 text, add column n_v3 text, add column d2 timestamptz, add column d3 timestamptz, add column d4 timestamptz,
  add column d5 timestamptz;
update f set n_v1 = (select nombre_completo from public.perfiles where id = f.v1), n_v3 = (select nombre_completo from public.perfiles where id = f.v3),
  d2 = ((f.hoy - 2)::timestamp + interval '12 hours') at time zone 'America/Lima',  -- repartido hace 2 días de Lima (al mediodía)
  d3 = ((f.hoy - 3)::timestamp + interval '12 hours') at time zone 'America/Lima',  -- hace exactamente 3 días: ya en rojo
  d4 = ((f.hoy - 4)::timestamp + interval '12 hours') at time zone 'America/Lima',
  d5 = ((f.hoy - 5)::timestamp + interval '12 hours') at time zone 'America/Lima';
do $$ begin
  if (select v1 is null or v2 is null or v3 is null or va is null or vi is null or s1 is null or s2 is null or sa is null or g is null or co is null from f) then
    raise exception 'b10-seguimiento: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if to_regprocedure('crm.seguimiento_bases()') is null or to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is null
     or to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is null or to_regprocedure('crm.recoger_de_base(uuid,uuid,uuid)') is null then
    raise exception 'b10-seguimiento: B9 r2 y B10 (20261004223253) no están aplicadas en este banco';
  end if;
  if exists (select 1 from crm.bases_carga) or exists (select 1 from crm.leads where id::text like 'b1000000-%' or telefono like '+5196679%') then
    raise exception 'b10-seguimiento: el banco tiene bases o leads b1000000-…/96679xxxx (limpiar antes)';
  end if;
end $$;
grant select on f, c, bx, r to anon, authenticated, service_role;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ───────── A · Catálogo ─────────
select pg_temp.caso('A la copia de B6b es exacta (md5 del cuerpo vivo de B6b)', '36af7e9cc4d6ec319b3d8004f3903473',
  (select md5(prosrc) from pg_proc where oid = 'pg_temp.b6b_obtener(uuid,boolean)'::regprocedure));
select pg_temp.caso('A puertas: DEFINER de postgres, search_path vacío, ACL exacta (4 nuevas + la lista + la publicada de reactivar)', '6',
  (select count(*)::text from pg_proc p where p.oid in ('crm.seguimiento_bases()'::regprocedure, 'crm.seguimiento_base(uuid)'::regprocedure,
     'crm.seguimiento_base_detalle(uuid,uuid,text)'::regprocedure, 'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'::regprocedure,
     'crm.obtener_base_gestion(uuid,boolean)'::regprocedure, 'crm.reactivar_lead_base(uuid,uuid,text)'::regprocedure)
     and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']::text[]
     and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'));
select pg_temp.caso('A núcleo y ayudantes: sin EXECUTE para la API, ACL solo postgres', '0|13',
  (select count(*) filter (where has_function_privilege(r.rol, p.oid, 'EXECUTE')) || '|' || count(distinct p.oid) filter (where p.proacl::text = '{postgres=X/postgres}')
     from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) r(rol)
    where p.oid in ('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamptz,timestamptz,uuid,uuid[],date,boolean,boolean,boolean)'::regprocedure,
                    'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)'::regprocedure, 'private.bases_carga_contactos_core(uuid,uuid,text)'::regprocedure,
                    'private.bases_carga_reparto_recogible(uuid,uuid,timestamptz,boolean)'::regprocedure, 'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)'::regprocedure,
                    'private.bases_carga_seguimiento_cifras()'::regprocedure,
                    'private.bases_carga_seguimiento_rol(uuid)'::regprocedure, 'private.bases_carga_seguimiento_exigir_base(uuid,text,uuid)'::regprocedure,
                    'private.bases_carga_seguimiento_filas(uuid[],date)'::regprocedure,
                    'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)'::regprocedure,
                    'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'::regprocedure,
                    'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamptz,numeric,text)'::regprocedure,
                    'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'::regprocedure)));
select pg_temp.caso('A las puertas publicadas de reactivar y de intentos, el resumen y la detalle de F4: cuerpo INTACTO',
  'bf59d77929877e7a5eb46704d934363e|d92c791fbe6f84e5d4f8ca39357b4721|b773a7c49fbdfc45133b3405991b1958|068372248be4127c80ba002542c9b4b8',
  (select string_agg(md5(p.prosrc), '|' order by x.o) from unnest(array['crm.reactivar_lead_base(uuid,uuid,text)', 'crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)',
     'crm.base_gestion_resumen()', 'crm.base_gestion_resumen_detalle(uuid,text)']) with ordinality x(f, o) join pg_proc p on p.oid = x.f::regprocedure));
select pg_temp.caso('A una sola sobrecarga: lista, reactivar publicada, _v2, núcleo con capital (6 sin defaults) y el de 4 argumentos (su firma sigue); lo mismo para intentos', '1|1|1|1|1|true|true|1|1|1|1|true',
  (select concat_ws('|', count(*) filter (where proname = 'obtener_base_gestion'), count(*) filter (where proname = 'reactivar_lead_base'),
                     count(*) filter (where proname = 'reactivar_lead_base_v2'), count(*) filter (where proname = 'base_gestion_reactivar_capital_core'),
                     count(*) filter (where proname = 'base_gestion_reactivar_core'),
                     (to_regprocedure('private.base_gestion_reactivar_core(uuid,uuid,uuid,text)') is not null)::text,
                     (select (p.pronargs = 6 and p.pronargdefaults = 0)::text from pg_proc p where p.oid = to_regprocedure('private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)')),
                     count(*) filter (where proname = 'registrar_intento_base'), count(*) filter (where proname = 'registrar_intento_base_v2'),
                     count(*) filter (where proname = 'base_gestion_intento_core'), count(*) filter (where proname = 'base_gestion_intento_capital_core'),
                     (select (p.pronargs = 8 and p.pronargdefaults = 0)::text from pg_proc p where p.oid = to_regprocedure('private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamptz,numeric,text)')))
     from pg_proc where pronamespace in ('crm'::regnamespace, 'private'::regnamespace)));
select pg_temp.caso('A los núcleos de siempre delegan en los núcleos con capital, sin capital; las _v2 y «agendó cita» pasan el capital', 't|t|t|t|t',
  (select concat_ws('|', (select p.prosrc ~ 'base_gestion_reactivar_capital_core\(p_actor, p_operacion_id, p_lead_id, p_nota, null::numeric, null::text\)' from pg_proc p where p.oid = 'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)'::regprocedure),
                     (select p.prosrc ~ 'base_gestion_reactivar_capital_core\(v_uid, p_operacion_id, p_lead_id, p_nota, p_monto_estimado, p_moneda\)' from pg_proc p where p.oid = 'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'::regprocedure),
                     (select p.prosrc ~ 'base_gestion_intento_capital_core\(p_actor, p_operacion_id, p_lead_id, p_resultado, p_nota, p_proxima, null::numeric, null::text\)' from pg_proc p where p.oid = 'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamptz)'::regprocedure),
                     (select p.prosrc ~ 'p_proxima_llamada,\s+p_monto_estimado, p_moneda\)' from pg_proc p where p.oid = 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamptz,numeric,text)'::regprocedure),
                     (select p.prosrc ~ 'base_gestion_reactivar_capital_core\(p_actor, gen_random_uuid\(\), p_lead_id, ''Agendó cita desde la base para gestión'',\s+p_monto_estimado, p_moneda\)' from pg_proc p where p.oid = 'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamptz,numeric,text)'::regprocedure))));
select pg_temp.caso('A la lista: misma firma (2 parámetros con default) y termina en base_id, base_nombre', '2|2|base_id,base_nombre',
  (select concat_ws('|', p.pronargs, p.pronargdefaults, p.proargnames[array_length(p.proargnames, 1) - 1] || ',' || p.proargnames[array_length(p.proargnames, 1)])
     from pg_proc p where p.oid = 'crm.obtener_base_gestion(uuid,boolean)'::regprocedure));
select pg_temp.caso('A ninguna función de B10 en el censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c
    where c.objeto in ('crm.obtener_base_gestion(uuid,boolean)', 'crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)', 'crm.seguimiento_base_detalle(uuid,uuid,text)',
                       'private.bases_carga_seguimiento_filas(uuid[],date)', 'private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date,boolean,boolean,boolean)',
                       'private.bases_carga_reparto_motivo_bloque(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamp with time zone,timestamp with time zone,uuid,uuid[],date)', 'private.bases_carga_contactos_core(uuid,uuid,text)',
                       'private.bases_carga_reparto_recogible(uuid,uuid,timestamp with time zone,boolean)', 'private.bases_carga_repartir_core(uuid,uuid,uuid,jsonb)',
                       'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)', 'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)',
                       'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)', 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                       'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                       'private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone)')));
-- r2: tabla de verdad de la definición ÚNICA (lead inventado: sin hechos ni rastro; los hechos y el rastro los prueba el mundo).
create temp table tv as select f.*, array(select pg_temp.subarbol(f.s1)) as sub, gen_random_uuid() as x from f;
select pg_temp.caso('A r2/r3: la definición única del estado (tabla de verdad; un NULL nunca es «sin repartir»)',
  'retirado|retirado|no_contactar|no_contactar|movido_otra_via|movido_otra_via|movido_otra_via|movido_otra_via|movido_otra_via|en_descanso|en_descanso|sin_tocar|sin_repartir|sin_repartir|sin_repartir|movido_otra_via|sin_repartir|trabajado|sin_tocar|cita|reactivado|reactivado|movido_otra_via',
  (select concat_ws('|',
     private.bases_carga_estado_contacto(t.x, false, false, 'descartado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),         -- retirado
     private.bases_carga_estado_contacto(t.x, null, false, 'descartado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),          -- activo NULL
     private.bases_carga_estado_contacto(t.x, true, true, 'descartado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),           -- vetado
     private.bases_carga_estado_contacto(t.x, true, null, 'descartado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),           -- veto NULL
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v2, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy),         -- repartido, ya de otro
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v3, null, null, null, null, now(), t.s1, t.sub, t.hoy),          -- sin reparto, analista de otro equipo
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, t.s2, null, null, null, now(), t.s1, t.sub, t.hoy),          -- sin reparto, bandeja de otro equipo
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),          -- sin reparto, fuera del descarte
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy),         -- repartido, fuera sin cita ni reactivación
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, t.s1, t.hoy + 1, null, null, now(), t.s1, t.sub, t.hoy),     -- sin reparto, en descanso
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v1, null, t.hoy + 1, t.v1, now(), now(), t.s1, t.sub, t.hoy),    -- repartido, en descanso
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy),         -- repartido, sin intento
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v1, null, null, null, null, now(), t.s1, t.sub, t.hoy),          -- sin reparto, con su analista anterior (r3, E1): disponible
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy),          -- bandeja del dueño
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, t.sa, null, null, null, now(), t.s1, t.sub, t.hoy),          -- bandeja de un sup del subárbol
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, null, null, null, null, now(), t.s1, t.sub, t.hoy),          -- sin dueño
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', null, t.s1, t.hoy, null, null, now(), t.s1, t.sub, t.hoy),         -- el descanso termina hoy
     -- r3: los hechos que pasa quien ya los calculó (private.bases_carga_reparto_hechos): se usan tal cual.
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy, true, false, false),        -- repartido, con intento
     private.bases_carga_estado_contacto(t.x, true, false, 'descartado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy, false, false, false),       -- repartido, sin intento
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy, true, true, true),          -- repartido, salió con cita
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', t.v1, null, null, t.v1, now(), now(), t.s1, t.sub, t.hoy, false, false, true),        -- repartido, reactivado
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', t.v1, null, null, null, null, now(), t.s1, t.sub, t.hoy, false, false, true),         -- sin reparto, reactivado (como B9)
     private.bases_carga_estado_contacto(t.x, true, false, 'contactado', null, t.s1, null, null, null, now(), t.s1, t.sub, t.hoy, false, false, false))       -- sin reparto, fuera sin hechos
     from tv t));

-- ───────── B · Equivalencia con B6b SIN bases (actor por actor, filas y orden) ─────────
-- Descartados SIN base (el mundo de B6b): de vend1, vend2, vend3, del analista anidado y en la bandeja de sup1; uno vetado, uno
-- en descanso, uno con rellamada de hoy y uno con un intento (las ramas de la lista), para que la equivalencia compare algo.
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, x.sup, 1000, 'PEN', coalesce(x.v, x.sup), true
  from f, lateral (values
    ('b1000000-0000-4000-8000-0000000000a1'::uuid, 'B10 BASE V1 UNO', '966790801', f.v1, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a2'::uuid, 'B10 BASE V1 VETADO', '966790802', f.v1, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a3'::uuid, 'B10 BASE V1 DESCANSO', '966790803', f.v1, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a4'::uuid, 'B10 BASE V1 RELLAMADA', '966790804', f.v1, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a5'::uuid, 'B10 BASE V2', '966790805', f.v2, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a6'::uuid, 'B10 BASE V3', '966790806', f.v3, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a7'::uuid, 'B10 BASE ANIDADO', '966790807', f.va, null::uuid),
    ('b1000000-0000-4000-8000-0000000000a8'::uuid, 'B10 BASE BANDEJA S1', '966790808', null::uuid, f.s1)) x(id, nombre, tel, v, sup);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id::text like 'b1000000-0000-4000-8000-0000000000a%';
select pg_temp.ejecutar($q$select 'ok' from (select crm.marcar_no_contactar('b1000000-0000-4000-8000-0000000000a2', 'B10: vetado sin base')) x$q$, (select v1 from f));
select pg_temp.ejecutar($q$select crm.registrar_intento_base(gen_random_uuid(), 'b1000000-0000-4000-8000-0000000000a1', 'no_contesto')->>'resultado'$q$, (select v1 from f));
select set_config('crm.op_base_gestion', 'on', true);
update crm.leads set enfriado_hasta = (select hoy + 5 from f) where id = 'b1000000-0000-4000-8000-0000000000a3';
update crm.leads set proxima_llamada_en = ((select hoy from f)::timestamp at time zone 'America/Lima') + interval '1 minute' where id = 'b1000000-0000-4000-8000-0000000000a4';
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.caso(format('B sin bases: %s (vetados %s, analista %s) = B6b', x.quien, x.vet, coalesce(x.vq, '-')),
                    pg_temp.valor(format('select pg_temp.h_b6b(%L, %L, false)', x.v, x.vet), x.uid),
                    pg_temp.valor(format('select pg_temp.h_b10(%L, %L)', x.v, x.vet), x.uid))
  from f, lateral (values ('vend1', f.v1, false, null::uuid, null::text), ('vend2', f.v2, false, null, null), ('vend3', f.v3, false, null, null),
                          ('vend1', f.v1, false, f.v1, 'vend1'), ('vend-anidado', f.va, false, null, null),
                          ('sup1', f.s1, false, null, null), ('sup1', f.s1, true, null, null), ('sup1', f.s1, false, f.v1, 'vend1'),
                          ('sup2', f.s2, false, null, null), ('sup2', f.s2, true, null, null), ('sup-anidado', f.sa, true, null, null),
                          ('gerencia', f.g, false, null, null), ('gerencia', f.g, true, null, null), ('gerencia', f.g, true, f.v3, 'vend3')) x(quien, uid, vet, v, vq);
select pg_temp.caso('B sin bases, por la ruta real (authenticated): sup1 con vetados = B6b',
  pg_temp.valor('select pg_temp.h_b6b(null, true, false)', (select s1 from f), 'authenticated'),
  pg_temp.valor('select pg_temp.h_b10(null, true)', (select s1 from f), 'authenticated'));
select pg_temp.caso('B sin bases: base_id y base_nombre NULL en toda la lista de Gerencia', '0',
  pg_temp.valor('select count(*)::text from crm.obtener_base_gestion(null, true) t where t.base_id is not null or t.base_nombre is not null', (select g from f)));
select pg_temp.caso('B sin bases: la lista de Gerencia con vetados trae los 7 descartados sembrados (la equivalencia compara algo)', '7',
  pg_temp.valor($q$select count(*)::text from crm.obtener_base_gestion(null, true) t where t.lead_id::text like 'b1000000-0000-4000-8000-0000000000a%'$q$, (select g from f)));

-- ───────── C · El mundo: bases por las puertas de B8, reparto y recogida reales por las de B9 ─────────
-- Leads de vend1 (Armada y reactivar) y de vend3, con capital, descartados (como postgres, sin usuario).
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, 1000, 'PEN', x.v, true
  from f, lateral (values ('b1000000-0000-4000-8000-0000000000d1'::uuid, 'B10 ARMADA UNO', '966790501', f.v2),
                          ('b1000000-0000-4000-8000-0000000000d2'::uuid, 'B10 ARMADA DOS', '966790502', f.v1),
                          ('b1000000-0000-4000-8000-0000000000d3'::uuid, 'B10 ARMADA TRES', '966790503', f.v1),
                          ('b1000000-0000-4000-8000-0000000000e1'::uuid, 'B10 L1 DE VEND1', '966790701', f.v1),
                          ('b1000000-0000-4000-8000-0000000000e3'::uuid, 'B10 L3 DE VEND3', '966790702', f.v3)) x(id, nombre, tel, v);
-- D4: un descartado en la BANDEJA del sup anidado (sin analista), que también se arma.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo)
select 'b1000000-0000-4000-8000-0000000000d4', 'B10 ARMADA CUATRO', '966790504', 'oficina', 'nuevo', null, f.sa, 1000, 'PEN', f.sa, true from f;
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id::text like 'b1000000-%';
-- D1 nació de vend2 y sup1 se lo pasó a vend1 ANTES de armar la base: ese movimiento es anterior a la base y no cuenta.
select pg_temp.sesion((select s1 from f));
update crm.leads set vendedor_id = (select v1 from f) where id = 'b1000000-0000-4000-8000-0000000000d1';
select pg_temp.sesion(null);
update crm.actividades set creado_en = now() - interval '2 days' where lead_id = 'b1000000-0000-4000-8000-0000000000d1' and tipo = 'reasignacion';
insert into c values ('D1', 'b1000000-0000-4000-8000-0000000000d1'), ('D2', 'b1000000-0000-4000-8000-0000000000d2'), ('D3', 'b1000000-0000-4000-8000-0000000000d3'),
                     ('D4', 'b1000000-0000-4000-8000-0000000000d4'),
                     ('L1', 'b1000000-0000-4000-8000-0000000000e1'), ('L3', 'b1000000-0000-4000-8000-0000000000e3');
-- D3: reactivado por la base en un ciclo ANTERIOR (hace 10 días) y vuelto a descartar: entra a Armada y se reparte; esa
-- reactivación es anterior al reparto y no cuenta.
select pg_temp.ejecutar($q$select crm.reactivar_lead_base_v2(gen_random_uuid(), 'b1000000-0000-4000-8000-0000000000d3')->>'etapa'$q$, (select v1 from f));
select pg_temp.sesion(null);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = 'b1000000-0000-4000-8000-0000000000d3';
update crm.actividades set creado_en = now() - interval '10 days' where lead_id = 'b1000000-0000-4000-8000-0000000000d3' and metadata->>'evento' = 'reactivacion_base';
-- Las bases, cada una por su supervisor (B8).
insert into bx select x.nombre, pg_temp.ejecutar(format($q$select crm.crear_base(gen_random_uuid(), %L, 'archivo', null, 'b10.csv')->>'base_id'$q$, x.nombre), x.uid)::uuid
  from f, lateral (values ('B10 Feria', f.s1), ('B10 Sur', f.s2), ('B10 Anidada', f.sa), ('B10 Retirada', f.s1)) x(nombre, uid);
select pg_temp.caso('C Feria: 23 contactos (F07, F11, F20 y F23 con capital)', '23',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)->'lote'->>'cargadas'$q$, (select id from bx where nombre = 'B10 Feria'),
    (select jsonb_agg(jsonb_build_object('fila', i, 'nombre', 'B10 F' || lpad(i::text, 2, '0'), 'telefono', '9667901' || lpad(i::text, 2, '0'))
                      || case when i in (7, 11, 20, 23) then jsonb_build_object('capital', '1000') else '{}'::jsonb end order by i) from generate_series(1, 23) i)),
    (select s1 from f)));
select pg_temp.caso('C Sur (sup2): 2 contactos', '2',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 S01","telefono":"966790201"},{"fila":2,"nombre":"B10 S02","telefono":"966790202"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Sur')), (select s2 from f)));
select pg_temp.caso('C Anidada (sup anidado): 1 contacto', '1',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 N1","telefono":"966790301"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Anidada')), (select sa from f)));
select pg_temp.caso('C Retirada (sup1): 1 contacto', '1',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 R1","telefono":"966790401"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Retirada')), (select s1 from f)));
select pg_temp.caso('C Armada (sup1, desde el CRM): 3 descartados de vend1 y 1 de la bandeja del anidado', '4',
  pg_temp.ejecutar(format($q$select crm.armar_base_crm(gen_random_uuid(), 'B10 Armada', null, array[%L, %L, %L, %L]::uuid[])->>'incluidos'$q$,
    (select id from c where clave = 'D1'), (select id from c where clave = 'D2'), (select id from c where clave = 'D3'), (select id from c where clave = 'D4')), (select s1 from f)));
insert into bx select 'B10 Armada', b.id from crm.bases_carga b where b.nombre = 'B10 Armada';
insert into c select 'F' || lpad(i::text, 2, '0'), (select l.id from crm.leads l where l.telefono = '+519667901' || lpad(i::text, 2, '0')) from generate_series(1, 23) i;
insert into c select x.clave, (select l.id from crm.leads l where l.telefono = x.tel)
  from (values ('S01', '+51966790201'), ('S02', '+51966790202'), ('N1', '+51966790301'), ('R1', '+51966790401')) x(clave, tel);
-- Andamio de datos (como postgres): Retirada pasa a inactiva (la puerta de retirar no existe aún) y S02 sale de Sur.
update crm.bases_carga set activo = false where id = (select id from bx where nombre = 'B10 Retirada');
update crm.base_carga_leads set activo = false where lead_id = (select id from c where clave = 'S02');
select pg_temp.caso('C mundo: 27 contactos dormidos, 5 bases, 4 vivas', '27|5|4',
  concat_ws('|', (select count(*) from crm.leads l join c on c.id = l.id where l.origen = 'base_cargada' and l.etapa = 'descartado' and l.vendedor_id is null),
            (select count(*) from crm.bases_carga), (select count(*) from crm.bases_carga where activo)));
-- Reparto REAL (crm.repartir_base, individual) y fechado: vend1 F03–F13, vend2 F14–F15, vend3 F16 (este, por Gerencia: a otro
-- equipo), vend1 D3 (armado con él: queda registrado sin tocar el lead) y el analista anidado F21 (luego se recoge).
select pg_temp.repartir(c.id, f.v1, f.s1, case c.clave when 'F03' then f.d3 when 'F04' then f.d2 else f.d5 end)
  from c, f where c.clave between 'F03' and 'F13';
select pg_temp.repartir(c.id, f.v2, f.s1, f.d4) from c, f where c.clave in ('F14', 'F15');
select pg_temp.repartir(c.id, f.v3, f.g, f.d4) from c, f where c.clave = 'F16';
select pg_temp.repartir(c.id, f.v1, f.s1, f.d5) from c, f where c.clave = 'D3';
select pg_temp.repartir(c.id, f.va, f.s1, f.d5) from c, f where c.clave = 'F21';
-- El trabajo de cada contacto (por las puertas reales).
select pg_temp.caso('C F05: un intento (no contestó)', 'no_contesto',
  pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'no_contesto')->>'resultado'$q$, (select id from c where clave = 'F05')), (select v1 from f)));
select pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'no_contesto')->>'resultado'$q$, c.id), f.v1) from c, f where c.clave = 'F06';
select pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'no_contesto')->>'resultado'$q$, c.id), f.v1) from c, f where c.clave = 'F06';
select pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'no_contesto')->>'resultado'$q$, c.id), f.v1) from c, f where c.clave = 'F06';
select pg_temp.caso('C F06: tres intentos → descanso', '3|true',
  (select (select count(*) from crm.actividades a where a.lead_id = l.id and a.metadata->>'evento' = 'intento_base') || '|' || (l.enfriado_hasta > f.hoy)::text
     from crm.leads l, f where l.id = (select id from c where clave = 'F06')));
select pg_temp.caso('C F07: «agendó cita» (con capital) → reactivado', 'contactado',
  pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'agendo_reunion')->>'etapa'$q$, (select id from c where clave = 'F07')), (select v1 from f)));
select pg_temp.caso('C F08: reactivado por la _v2 con capital (sin intentos)', 'contactado',
  pg_temp.ejecutar(format($q$select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 2500)->>'etapa'$q$, (select id from c where clave = 'F08')), (select v1 from f)));
select pg_temp.caso('C F09: sup1 lo reasigna a vend2 por la ficha (otra vía)', 'ok',
  coalesce(pg_temp.ejecutar(format($q$update crm.leads set vendedor_id = %L where id = %L returning 'ok'$q$, (select v2 from f), (select id from c where clave = 'F09')), (select s1 from f)), '(nulo)'));
select pg_temp.caso('C F10: un intento ANTES del reparto (fechado 6 días atrás)', 'no_contesto',
  pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'no_contesto')->>'resultado'$q$, (select id from c where clave = 'F10')), (select v1 from f)));
update crm.actividades set creado_en = now() - interval '6 days' where lead_id = (select id from c where clave = 'F10') and metadata->>'evento' = 'intento_base';
create temp table res_c (k text primary key, v text);
insert into res_c select 'F11', pg_temp.ejecutar(format('select crm.reabrir_lead_fn(%L)->>''etapa''', (select id from c where clave = 'F11')), (select v1 from f));
select pg_temp.caso('C F11: vend1 lo reabre con «Reabrir» (otra puerta)', 'nuevo|nuevo',
  (select v from res_c where k = 'F11') || '|' || (select l.etapa from crm.leads l where l.id = (select id from c where clave = 'F11')));
select pg_temp.caso('C F12: sup1 lo devuelve a su bandeja (otra vía)', 'ok',
  coalesce(pg_temp.ejecutar(format($q$update crm.leads set vendedor_id = null, asignado_supervisor_id = %L where id = %L returning 'ok'$q$, (select s1 from f), (select id from c where clave = 'F12')), (select s1 from f)), '(nulo)'));
select set_config('crm.op_base_gestion', 'on', true);
update crm.leads set enfriado_hasta = (select hoy from f) where id = (select id from c where clave = 'F13');  -- borde: descanso que termina hoy
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.caso('C F14: vend2 lo marca No contactar', 'ok',
  coalesce(pg_temp.ejecutar(format($q$select 'ok' from (select crm.marcar_no_contactar(%L, 'B10: no quiere')) x$q$, (select id from c where clave = 'F14')), (select v2 from f)), '(nulo)'));
update crm.leads set activo = false where id = (select id from c where clave = 'F15');  -- F15: retirado
-- r1 (Codex P2): contactos SIN reparto registrado que otra vía tocó.
-- F17: sup1 se lo asigna a vend1 por la ficha (sin reparto).
select pg_temp.caso('C F17: sup1 lo asigna a vend1 por la ficha, sin reparto', 'ok',
  coalesce(pg_temp.ejecutar(format($q$update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L returning 'ok'$q$, (select v1 from f), (select id from c where clave = 'F17')), (select s1 from f)), '(nulo)'));
update crm.leads set activo = false where id = (select id from c where clave = 'F18');  -- F18: retirado sin reparto
select pg_temp.caso('C F19: sup1 lo marca No contactar, sin reparto', 'ok',
  coalesce(pg_temp.ejecutar(format($q$select 'ok' from (select crm.marcar_no_contactar(%L, 'B10: no quiere')) x$q$, (select id from c where clave = 'F19')), (select s1 from f)), '(nulo)'));
-- F20: sup1 lo reactiva (con capital) desde su bandeja y luego se lo asigna a vend2; F23: lo reactiva y lo deja en su bandeja.
select pg_temp.caso('C F20 y F23: sup1 los reactiva por la _v2 sin reparto', 'contactado|contactado',
  pg_temp.ejecutar(format($q$select crm.reactivar_lead_base_v2(gen_random_uuid(), %L)->>'etapa'$q$, (select id from c where clave = 'F20')), (select s1 from f))
  || '|' || pg_temp.ejecutar(format($q$select crm.reactivar_lead_base_v2(gen_random_uuid(), %L)->>'etapa'$q$, (select id from c where clave = 'F23')), (select s1 from f)));
select pg_temp.caso('C F20: luego sup1 se lo asigna a vend2', 'ok',
  coalesce(pg_temp.ejecutar(format($q$update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L returning 'ok'$q$, (select v2 from f), (select id from c where clave = 'F20')), (select s1 from f)), '(nulo)'));
-- F21: repartido al analista anidado y RECOGIDO por sup1 con crm.recoger_de_base (B9): vuelve a la bandeja del dueño, sin reparto.
select pg_temp.caso('C F21: sup1 lo recoge del analista anidado (crm.recoger_de_base real)', '1|0|0',
  (select (x->>'recogidos') || '|' || (x->>'omitidos') || '|' || (x->>'pendientes')
     from (select pg_temp.j(pg_temp.recoger((select id from bx where nombre = 'B10 Feria'), (select va from f), (select s1 from f))) x) q));
-- F22: Gerencia lo pasa a la bandeja de sup2 (otra vía; sigue sin analista).
select pg_temp.sesion((select g from f));
update crm.leads set asignado_supervisor_id = (select s2 from f) where id = (select id from c where clave = 'F22');
select pg_temp.sesion(null);
select pg_temp.caso('C estado de los leads tras el trabajo (F05…F23)',
  'F05:descartado:v1|F06:descartado:v1|F07:contactado:v1|F08:contactado:v1|F09:descartado:v2|F10:descartado:v1|F11:nuevo:v1|F12:descartado:-|F13:descartado:v1|F14:descartado:v2|F15:descartado:v2|F16:descartado:v3|F17:descartado:v1|F18:descartado:-|F19:descartado:-|F20:contactado:v2|F21:descartado:-|F22:descartado:-|F23:contactado:-',
  (select string_agg(c.clave || ':' || l.etapa || ':' || case l.vendedor_id when f.v1 then 'v1' when f.v2 then 'v2' when f.v3 then 'v3' else '-' end, '|' order by c.clave)
     from c join crm.leads l on l.id = c.id, f where c.clave between 'F05' and 'F23'));

-- ───────── D · La lista con bases ─────────
select pg_temp.caso('D sup1: los dormidos sin repartir (F01, F02 y N1 del anidado) NO salen; con vetados tampoco', 'sin fila|sin fila|sin fila|sin fila|sin fila',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F01')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F02')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'N1')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F01')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'N1')), (select s1 from f))));
select pg_temp.caso('D r1/r3: también fuera F21 (dormido recogido); D4 (ARMADO de la bandeja del anidado, sin repartir) NO se oculta (E1), para sup1 y Gerencia', 'sin fila|B10 Armada|sin fila|B10 Armada',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F21')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'D4')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F21')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, false)', (select id from c where clave = 'D4')), (select g from f))));
select pg_temp.caso('D r1 (auditor P3): el vetado SIN repartir (F19) sale en «Ver no contactar» con su base; sin pedirlo, no', 'B10 Feria|sin fila|B10 Feria',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F19')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, false)', (select id from c where clave = 'F19')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F19')), (select g from f))));
select pg_temp.caso('D r1: los SIN reparto que otra vía tocó SÍ salen: F17 (asignado a vend1) para vend1 y sup1; F22 (bandeja de sup2) para Gerencia', 'B10 Feria|B10 Feria|B10 Feria',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F17')), (select v1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F17')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F22')), (select g from f))));
select pg_temp.caso('D r1 (auditor P3): base_nombre solo si se ve la base o se es el analista: sup2 ve F22 y F16 SIN base; vend3 ve F16 con base', '(sin base)|(sin base)|B10 Feria',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F22')), (select s2 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F16')), (select s2 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F16')), (select v3 from f))));
select pg_temp.caso('D r1: sup2 no ve el nombre de NINGUNA base que no sea de su subárbol (salvo los leads de los que es analista)', '0',
  pg_temp.valor($q$select count(*)::text from crm.obtener_base_gestion(null, true) t
                    join crm.base_carga_leads bl on bl.lead_id = t.lead_id and bl.activo join crm.bases_carga b on b.id = bl.base_id
                   where t.base_nombre is not null and b.supervisor_id not in (select pg_temp.sesion_subarbol()) and t.vendedor_id is distinct from (select s2 from pg_temp.f)$q$, (select s2 from f)));
select pg_temp.caso('D Gerencia: los dormidos sin repartir (F01, S01, N1) NO salen, con y sin vetados', 'sin fila|sin fila|sin fila|sin fila',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'F01')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'S01')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'N1')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L, false)', (select id from c where clave = 'S01')), (select g from f))));
select pg_temp.caso('D sup1: los repartidos y los armados con analista SÍ salen, con su base', 'B10 Feria|B10 Feria|B10 Armada|B10 Armada',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F03')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F09')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'D1')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'D2')), (select s1 from f))));
select pg_temp.caso('D sup1: F12 (repartido y devuelto a su bandeja por otra vía) SÍ sale: no es «sin repartir»', 'B10 Feria',
  pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F12')), (select s1 from f)));
select pg_temp.caso('D sup1: R1 (base RETIRADA) sale sin base', '(sin base)',
  pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'R1')), (select s1 from f)));
select pg_temp.caso('D Gerencia: S02 (pertenencia retirada) sale sin base', '(sin base)',
  pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'S02')), (select g from f)));
select pg_temp.caso('D Gerencia: F16 (repartido a vend3) sale con su base', 'B10 Feria',
  pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'F16')), (select g from f)));
select pg_temp.caso('D vend1 ve sus repartidos de Feria (F03 F04 F05 F10 F13), F17 (asignado por otra vía) y los armados con él (D1 D2 D3), con base_id y base_nombre',
  'D1:B10 Armada,D2:B10 Armada,D3:B10 Armada,F03:B10 Feria,F04:B10 Feria,F05:B10 Feria,F10:B10 Feria,F13:B10 Feria,F17:B10 Feria',
  pg_temp.valor($q$select string_agg(c.clave || ':' || t.base_nombre, ',' order by c.clave) from crm.obtener_base_gestion() t join pg_temp.c c on c.id = t.lead_id
                   where t.base_id = (select b.id from pg_temp.bx b where b.nombre = t.base_nombre)$q$, (select v1 from f), 'authenticated'));
select pg_temp.caso('D vend1: lo demás de Feria no está en su lista (descanso, reactivados, reasignado, reabierto, bandeja)', '0',
  pg_temp.valor($q$select count(*)::text from crm.obtener_base_gestion() t join pg_temp.c c on c.id = t.lead_id where c.clave in ('F06','F07','F08','F09','F11','F12','F01','F02','F21')$q$, (select v1 from f)));
select pg_temp.caso('D vend1 por su analista (p_vendedor_id) = su lista', 'igual',
  pg_temp.valor($q$select case when (select pg_temp.h_b10(null, false)) = (select pg_temp.h_b10((select v1 from pg_temp.f), false)) then 'igual' else 'distinta' end$q$, (select v1 from f)));
select pg_temp.caso(format('D con bases: %s (vetados %s) = B6b SIN los dormidos sin repartir (mismas filas y orden)', x.quien, x.vet),
                    pg_temp.valor(format('select pg_temp.h_b6b(null, %L, true)', x.vet), x.uid),
                    pg_temp.valor(format('select pg_temp.h_b10(null, %L)', x.vet), x.uid))
  from f, lateral (values ('vend1', f.v1, false), ('vend2', f.v2, false), ('vend3', f.v3, false), ('sup1', f.s1, false), ('sup1', f.s1, true),
                          ('sup2', f.s2, true), ('sup-anidado', f.sa, true), ('gerencia', f.g, false), ('gerencia', f.g, true)) x(quien, uid, vet);
select pg_temp.caso('D con bases: B6b SÍ mostraría dormidos sin repartir a sup1 y a Gerencia (la exclusión tiene efecto)', 'distinta|distinta',
  concat_ws('|', pg_temp.valor($q$select case when pg_temp.h_b6b(null, false, false) = pg_temp.h_b10(null, false) then 'igual' else 'distinta' end$q$, (select s1 from f)),
               pg_temp.valor($q$select case when pg_temp.h_b6b(null, true, false) = pg_temp.h_b10(null, true) then 'igual' else 'distinta' end$q$, (select g from f))));
select pg_temp.caso('D Gerencia: base_id y base_nombre = la base VIVA del lead en TODA la lista (independiente)', '0',
  pg_temp.valor($q$select count(*)::text from crm.obtener_base_gestion(null, true) t
                    left join (select bl.lead_id, b.id, b.nombre from crm.base_carga_leads bl join crm.bases_carga b on b.id = bl.base_id and b.activo where bl.activo) v on v.lead_id = t.lead_id
                   where t.base_id is distinct from v.id or t.base_nombre is distinct from v.nombre$q$, (select g from f)));
select pg_temp.caso('D el resumen de F4 de sup1 no cuenta dormidos (vend1 en base = su lista)', 'true',
  pg_temp.valor($q$select ((select r.en_base from crm.base_gestion_resumen() r where r.vendedor_id = (select v1 from pg_temp.f))
                          = (select count(*) from crm.obtener_base_gestion() g where g.vendedor_id = (select v1 from pg_temp.f)))::text$q$, (select s1 from f)));

-- ───────── E · Seguimiento: cada cifra ─────────
select pg_temp.caso('E sup1 ve Feria, Armada y Anidada (su subárbol); no Sur ni la Retirada', 'B10 Anidada,B10 Armada,B10 Feria',
  pg_temp.valor('select string_agg(s.nombre, '','' order by s.nombre) from crm.seguimiento_bases() s', (select s1 from f), 'authenticated'));
select pg_temp.caso('E Gerencia ve las 4 vivas', 'B10 Anidada,B10 Armada,B10 Feria,B10 Sur',
  pg_temp.valor('select string_agg(s.nombre, '','' order by s.nombre) from crm.seguimiento_bases() s', (select g from f)));
select pg_temp.caso('E sup2 ve solo Sur; el sup anidado solo Anidada', 'B10 Sur|B10 Anidada',
  pg_temp.valor('select string_agg(s.nombre, '','' order by s.nombre) from crm.seguimiento_bases() s', (select s2 from f))
  || '|' || pg_temp.valor('select string_agg(s.nombre, '','' order by s.nombre) from crm.seguimiento_bases() s', (select sa from f)));
-- Contados A MANO (r1, Codex P2), sin el arreglo de cifras: Feria tiene 23 contactos —
--   sin reparto: F01 F02 F21 (recogido) disponibles · F17 (asignado a vend1) y F22 (bandeja de sup2) movidos · F20 (reactivado y
--   asignado) y F23 (reactivado en la bandeja) reactivados por la base (r3, como B9; sin reparto: no cuentan en «reactivados»,
--   que mide lo repartido) · F18 retirado · F19 vetado;
--   con reparto (14): vend1 F03–F13 (F09 F11 F12 movidos), vend2 F14 (vetado) y F15 (retirado), vend3 F16.
--   → total 23 · sin_repartir 3 · repartidos 14 · sin_tocar 5 (F03 F04 F10 F13 F16) · trabajados 3 · descanso 1 · citas 1 ·
--     reactivados 2 · avance 3/14 · movidos 5 · retirados 2 · no_contactar 2.
select pg_temp.caso('E Feria (contada a mano): 23/3/14/5/3/1/1/2/0.2143 y movidos 5, retirados 2, vetados 2',
  '23/3/14/5/3/1/1/2/0.2143|5/2/2', pg_temp.valor($q$select pg_temp.sb('B10 Feria')$q$, (select s1 from f)));
select pg_temp.caso('E Feria es la misma para Gerencia', '23/3/14/5/3/1/1/2/0.2143|5/2/2', pg_temp.valor($q$select pg_temp.sb('B10 Feria')$q$, (select g from f)));
select pg_temp.caso('E estado de CADA contacto de Feria, escrito a mano (r1)',
  'F01:sin_repartir,F02:sin_repartir,F03:sin_tocar,F04:sin_tocar,F05:trabajado,F06:en_descanso,F07:cita,F08:reactivado,F09:movido_otra_via,F10:sin_tocar,F11:movido_otra_via,F12:movido_otra_via,F13:sin_tocar,F14:no_contactar,F15:retirado,F16:sin_tocar,F17:movido_otra_via,F18:retirado,F19:no_contactar,F20:reactivado,F21:sin_repartir,F22:movido_otra_via,F23:reactivado',
  pg_temp.estados('B10 Feria'));
select pg_temp.caso('E estado de CADA contacto de Armada, escrito a mano (r3): D1 y D2 conservan su analista y están DISPONIBLES (E1; D1 se movió ANTES de la base), D4 disponible',
  'D1:sin_repartir,D2:sin_repartir,D3:sin_tocar,D4:sin_repartir', pg_temp.estados('B10 Armada'));
select pg_temp.caso('E Armada (r3): D1, D2 (con su analista anterior) y D4 sin repartir, D3 repartido sin tocar', '4/3/1/1/0/0/0/0/0.0000|0/0/0', pg_temp.valor($q$select pg_temp.sb('B10 Armada')$q$, (select s1 from f)));
select pg_temp.caso('E r1: cada cifra nueva se abre en SUS contactos (Gerencia)', 'F01,F02,F21|F09,F11,F12,F17,F22|F14,F19|?,?|D1,D2,D4',
  pg_temp.valor(format($q$select pg_temp.claves(%1$L, null, 'sin_repartir') || '|' || pg_temp.claves(%1$L, null, 'movidos_otra_via') || '|'
                          || pg_temp.claves(%1$L, null, 'no_contactar') || '|' || pg_temp.claves(%1$L, null, 'retirados') || '|' || pg_temp.claves(%2$L, null, 'sin_repartir')$q$,
    (select id from bx where nombre = 'B10 Feria'), (select id from bx where nombre = 'B10 Armada')), (select g from f)));
select pg_temp.caso('E r1: sup1 abre los movidos sin ver a F22 (bandeja de sup2: fuera de su ámbito)', '4|1',
  pg_temp.valor(format($q$select count(d.lead_id) || '|' || count(*) filter (where d.lead_id is null) from crm.seguimiento_base_detalle(%L, null, 'movidos_otra_via') d$q$,
    (select id from bx where nombre = 'B10 Feria')), (select s1 from f)));
select pg_temp.caso('E Armada/vend1: D3 se reactivó ANTES del reparto → sin tocar y en rojo, no reactivado', '1/1/1/0/0/0/0/0|0/0|D3',
  pg_temp.valor(format('select pg_temp.sa(%L, %L) || ''|'' || pg_temp.claves(%L, %L, ''sin_tocar'')', (select id from bx where nombre = 'B10 Armada'), (select v1 from f),
    (select id from bx where nombre = 'B10 Armada'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E Sur: la pertenencia retirada no cuenta (total 1)', '1/1/0/0/0/0/0/0/0.0000|0/0/0', pg_temp.valor($q$select pg_temp.sb('B10 Sur')$q$, (select g from f)));
select pg_temp.caso('E Feria/vend1: asignados 11, sin tocar 4, en rojo 3, trabajados 3, descanso 1, cita 1, reactivados 2, movidos 3', '11/4/3/3/1/1/2/3|0/0',
  pg_temp.valor(format('select pg_temp.sa(%L, %L)', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E Feria/vend2: 2 asignados: 1 vetado y 1 retirado (r1: el retirado ya no es «movido»)', '2/0/0/0/0/0/0/0|1/1',
  pg_temp.valor(format('select pg_temp.sa(%L, %L)', (select id from bx where nombre = 'B10 Feria'), (select v2 from f)), (select s1 from f)));
select pg_temp.caso('E Feria/vend3 (otro equipo, repartido por Gerencia): 1 sin tocar en rojo (Gerencia)', '1/1/1/0/0/0/0/0|0/0',
  pg_temp.valor(format('select pg_temp.sa(%L, %L)', (select id from bx where nombre = 'B10 Feria'), (select v3 from f)), (select g from f)));
select pg_temp.caso('E r1 (auditor P3): para sup1, la fila de vend3 sale SIN analista_id ni nombre, con sus cifras', '1/1/1/0/0/0/0/0|0/0|(sin nombre)|sin fila',
  pg_temp.valor(format($q$select pg_temp.sa(%1$L, null) || '|' || coalesce((select s.analista_nombre from crm.seguimiento_base(%1$L) s where s.analista_id is null), '(sin nombre)')
                          || '|' || pg_temp.sa(%1$L, %2$L)$q$, (select id from bx where nombre = 'B10 Feria'), (select v3 from f)), (select s1 from f)));
select pg_temp.caso('E estados de los asignados de vend1', 'cita,en_descanso,movido_otra_via,movido_otra_via,movido_otra_via,reactivado,sin_tocar,sin_tocar,sin_tocar,sin_tocar,trabajado',
  pg_temp.valor(format('select string_agg(d.estado, '','' order by d.estado) from crm.seguimiento_base_detalle(%L, %L, ''asignados'') d', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E estados de vend2: No contactar y el retirado', 'no_contactar,retirado',
  pg_temp.valor(format('select string_agg(d.estado, '','' order by d.estado) from crm.seguimiento_base_detalle(%L, %L, ''asignados'') d', (select id from bx where nombre = 'B10 Feria'), (select v2 from f)), (select s1 from f)));
select pg_temp.caso('E sin tocar de vend1 = F03 F04 F10 F13 (el intento de F10 fue ANTES del reparto)', 'F03,F04,F10,F13',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''sin_tocar'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E en rojo (≥ 3 días de Lima): F03 (justo 3), F10 y F13; F04 (2 días) no', 'F03,F10,F13',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''sin_tocar_3_dias'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E trabajados = F05 F06 F07, con su último resultado', 'F05:no_contesto,F06:no_contesto,F07:agendo_reunion',
  pg_temp.valor(format($q$select string_agg(c.clave || ':' || d.ultimo_resultado, ',' order by c.clave) from crm.seguimiento_base_detalle(%L, %L, 'trabajados') d join pg_temp.c c on c.id = d.lead_id$q$,
    (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E en descanso = F06 (F13 termina hoy: ya no)', 'F06',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''en_descanso'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E citas = F07; reactivados = F07 F08', 'F07|F07,F08',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''citas'') || ''|'' || pg_temp.claves(%L, %L, ''reactivados'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f),
    (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E movidos por otra vía = F09 (reasignado), F11 (reabierto), F12 (a la bandeja)', 'F09,F11,F12',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''movidos_otra_via'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E sin intentos desde el reparto: último intento NULL en los sin tocar (también F10)', '0',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''sin_tocar'') d where d.ultimo_intento_en is not null', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E último intento de vend1 = el más reciente de F05/F06/F07', 'true',
  pg_temp.valor(format($q$select ((select s.ultimo_intento_en from crm.seguimiento_base(%L) s where s.analista_id = %L)
                                 = (select max(a.creado_en) from crm.actividades a join pg_temp.c c on c.id = a.lead_id where c.clave in ('F05','F06','F07') and a.metadata->>'evento' = 'intento_base'))::text$q$,
    (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E sin repartir de Feria = F01 F02 F21; total de Feria = 23 filas', 'F01,F02,F21|23',
  pg_temp.valor(format('select pg_temp.claves(%L, null, ''sin_repartir'') || ''|'' || (select count(*) from crm.seguimiento_base_detalle(%L, null, ''total''))', (select id from bx where nombre = 'B10 Feria'),
    (select id from bx where nombre = 'B10 Feria')), (select s1 from f)));
select pg_temp.caso('E Gerencia ve a vend3 identificado (id y nombre)', (select n_v3 from f),
  pg_temp.valor(format('select (select s.analista_nombre from crm.seguimiento_base(%L) s where s.analista_id = %L)', (select id from bx where nombre = 'B10 Feria'), (select v3 from f)), (select g from f)));
select pg_temp.caso('E sup1 ve el nombre de su analista', (select n_v1 from f),
  pg_temp.valor(format('select (select s.analista_nombre from crm.seguimiento_base(%L) s where s.analista_id = %L)', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E r4: sup1 no abre por el UUID de vend3 (otro equipo: P0002, Codex r2) y su contacto cuenta sin delatar quién es en la base; Gerencia lo ve', 'ERROR P0002 Analista no encontrado en esta base|true|F16',
  pg_temp.valor(format('select pg_temp.claves(%L, %L, ''asignados'')', (select id from bx where nombre = 'B10 Feria'), (select v3 from f)), (select s1 from f))
  || '|' || pg_temp.valor(format('select (pg_temp.claves(%L, null, ''asignados'') like ''%%?%%'')::text', (select id from bx where nombre = 'B10 Feria')), (select s1 from f))
  || '|' || pg_temp.valor(format('select pg_temp.claves(%L, %L, ''asignados'')', (select id from bx where nombre = 'B10 Feria'), (select v3 from f)), (select g from f)));
select pg_temp.caso('E el retirado (F15) cuenta sin nombre ni id, también para Gerencia', '(oculto)/(oculto)',
  pg_temp.valor(format($q$select coalesce(d.lead_id::text, '(oculto)') || '/' || coalesce(d.nombre_completo, '(oculto)') from crm.seguimiento_base_detalle(%L, %L, 'retirados') d$q$,
    (select id from bx where nombre = 'B10 Feria'), (select v2 from f)), (select g from f)));
select pg_temp.caso('E sup1 ve el nombre de un contacto suyo en el detalle', 'B10 F03',
  pg_temp.valor(format($q$select d.nombre_completo from crm.seguimiento_base_detalle(%L, %L, 'sin_tocar_3_dias') d where d.lead_id = (select id from pg_temp.c where clave = 'F03')$q$,
    (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));
select pg_temp.caso('E todo número se abre: cifra = detalle y suma por analista = base (sup1)', 'cuadra', pg_temp.valor('select pg_temp.cuadre()', (select s1 from f), 'authenticated'));
select pg_temp.caso('E todo número se abre: cifra = detalle y suma por analista = base (Gerencia)', 'cuadra', pg_temp.valor('select pg_temp.cuadre()', (select g from f)));
select pg_temp.caso('E el detalle de «sin repartir» de un analista está vacío', '0',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''sin_repartir'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select s1 from f)));

-- ───────── F · Roles y ámbito ─────────
select pg_temp.caso(format('F %s → seguimiento_bases 42501', x.quien), 'ERROR 42501 Solo Supervisión y Gerencia ven el seguimiento de las bases',
                    pg_temp.valor('select count(*)::text from crm.seguimiento_bases()', x.uid, 'authenticated'))
  from f, lateral (values ('vend1', f.v1), ('coordinador', f.co), ('vend-inactivo', f.vi)) x(quien, uid);
select pg_temp.caso('F vend1 → seguimiento_base y detalle de su propia base 42501', 'ERROR 42501 Solo Supervisión y Gerencia ven el seguimiento de las bases|ERROR 42501 Solo Supervisión y Gerencia ven el seguimiento de las bases',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base(%L)', (select id from bx where nombre = 'B10 Feria')), (select v1 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''asignados'')', (select id from bx where nombre = 'B10 Feria'), (select v1 from f)), (select v1 from f), 'authenticated'));
select pg_temp.caso('F sin sesión → 42501', 'ERROR 42501 Solo Supervisión y Gerencia ven el seguimiento de las bases',
  pg_temp.valor('select count(*)::text from crm.seguimiento_bases()', null, 'authenticated'));
select pg_temp.caso('F anon y service_role sin EXECUTE', 'ERROR 42501 permission denied|ERROR 42501 permission denied for function seguimiento_base_detalle',
  split_part(pg_temp.valor('select count(*)::text from crm.seguimiento_bases()', null, 'anon'), ' for ', 1)
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, null, ''total'')', (select id from bx where nombre = 'B10 Feria')), null, 'service_role'));
select pg_temp.caso('F sup2 → Feria (de sup1): P0002 en seguimiento_base y en el detalle', 'ERROR P0002 Base no encontrada o fuera de tu ámbito|ERROR P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base(%L)', (select id from bx where nombre = 'B10 Feria')), (select s2 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, null, ''total'')', (select id from bx where nombre = 'B10 Feria')), (select s2 from f), 'authenticated'));
select pg_temp.caso('F el sup anidado → Feria (de su jefe) P0002; sup1 → Anidada (de su subárbol) sí', 'ERROR P0002 Base no encontrada o fuera de tu ámbito|0',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base(%L)', (select id from bx where nombre = 'B10 Feria')), (select sa from f), 'authenticated')
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base(%L)', (select id from bx where nombre = 'B10 Anidada')), (select s1 from f), 'authenticated'));
select pg_temp.caso('F la base RETIRADA → P0002 (también para Gerencia)', 'ERROR P0002 Base no encontrada o fuera de tu ámbito|ERROR P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base(%L)', (select id from bx where nombre = 'B10 Retirada')), (select s1 from f))
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, null, ''total'')', (select id from bx where nombre = 'B10 Retirada')), (select g from f)));
select pg_temp.caso('F base NULL → 22023; base inexistente → P0002', 'ERROR 22023 Indica la base|ERROR P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.valor('select count(*)::text from crm.seguimiento_base(null)', (select s1 from f))
  || '|' || pg_temp.valor('select count(*)::text from crm.seguimiento_base(gen_random_uuid())', (select g from f)));
select pg_temp.caso(format('F cifra %s → 22023', coalesce(x.cifra, 'NULL')), 'ERROR 22023 Cifra inválida',
  split_part(pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, null, %L)', (select id from bx where nombre = 'B10 Feria'), x.cifra), (select s1 from f)), ':', 1))
  from (values ('avance'), (null), ('otra'), ('Total')) x(cifra);
select pg_temp.caso('F p_cifra se pasa por nombre sin p_analista_id (el default no estorba)', '23',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(p_base_id => %L, p_cifra => ''total'')', (select id from bx where nombre = 'B10 Feria')), (select s1 from f), 'authenticated'));
select pg_temp.caso('F un analista sin contactos en la base → P0002', 'ERROR P0002 Analista no encontrado en esta base',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''total'')', (select id from bx where nombre = 'B10 Armada'), (select v3 from f)), (select s1 from f)));

-- ───────── G · Capital al reactivar ─────────
insert into bx select 'B10 Reactivar', pg_temp.ejecutar($q$select crm.crear_base(gen_random_uuid(), 'B10 Reactivar', 'archivo', null, 'r.csv')->>'base_id'$q$, (select s1 from f))::uuid;
select pg_temp.caso('G base Reactivar: 6 contactos (G2 con 3000; G3 en USD sin capital)', '6',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 G1","telefono":"966790601"},{"fila":2,"nombre":"B10 G2","telefono":"966790602","capital":"3000"},{"fila":3,"nombre":"B10 G3","telefono":"966790603","moneda":"USD"},{"fila":4,"nombre":"B10 G4","telefono":"966790604"},{"fila":5,"nombre":"B10 G5","telefono":"966790605"},{"fila":6,"nombre":"B10 G6","telefono":"966790606"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Reactivar')), (select s1 from f)));
insert into c select 'G' || i, (select l.id from crm.leads l where l.telefono = '+519667906' || lpad(i::text, 2, '0')) from generate_series(1, 6) i;
select pg_temp.repartir(c.id, f.v1, f.s1, f.d5) from c, f where c.clave like 'G_' order by c.clave;
select pg_temp.caso('G puerta publicada, lead sin capital → 22023', 'ERROR 22023 Indica el capital estimado para reactivar',
  pg_temp.valor(format('select crm.reactivar_lead_base(gen_random_uuid(), %L)::text', (select id from c where clave = 'G1')), (select v1 from f), 'authenticated'));
select pg_temp.caso('G _v2 sin capital → 22023', 'ERROR 22023 Indica el capital estimado para reactivar',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, ''nota'')::text', (select id from c where clave = 'G1')), (select v1 from f), 'authenticated'));
select pg_temp.caso(format('G _v2 capital %s → 22023', x.m), 'ERROR 22023 El capital estimado debe ser mayor que 0, de hasta 9999999999.99 y con 2 decimales como maximo',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, %s)::text', (select id from c where clave = 'G1'), x.m), (select v1 from f), 'authenticated'))
  from (values ('0'), ('-5'), ('1.001'), ('10000000000'), ('''NaN''::numeric')) x(m);
select pg_temp.caso(format('G _v2 moneda %s → 22023', x.mo), 'ERROR 22023 La moneda del capital es PEN o USD',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 100, %L)::text', (select id from c where clave = 'G1'), x.mo), (select v1 from f), 'authenticated'))
  from (values ('EUR'), ('pen'), ('')) x(mo);
select pg_temp.caso('G el lead sigue igual tras los rechazos (descartado, sin capital)', 'descartado|(sin capital)|PEN',
  (select concat_ws('|', l.etapa, coalesce(l.monto_estimado::text, '(sin capital)'), l.moneda) from crm.leads l where l.id = (select id from c where clave = 'G1')));
create temp table op as select gen_random_uuid() as g1, gen_random_uuid() as g6;
create temp table res (k text primary key, v text);
grant select on op, res to authenticated;
insert into res select 'G1', pg_temp.ejecutar(format('select crm.reactivar_lead_base_v2(%L, %L, null, 5000)::text', (select g1 from op), (select id from c where clave = 'G1')), (select v1 from f));
select pg_temp.caso('G _v2 con 5000 (moneda NULL) → contactado, con las MISMAS claves que la puerta publicada (r1: + el capital efectivo y el pedido)',
  'ciclo_n,etapa,evento,lead_id,moneda,monto_estimado,ok,reabierto_por,reactivado_en,replay,solicitud_moneda,solicitud_monto', pg_temp.claves_json((select v from res where k = 'G1')));
select pg_temp.caso('G r1: la respuesta trae el capital EFECTIVO del lead y el pedido', '5000|PEN|5000|',
  concat_ws('|', pg_temp.j((select v from res where k = 'G1'))->>'monto_estimado', pg_temp.j((select v from res where k = 'G1'))->>'moneda',
            pg_temp.j((select v from res where k = 'G1'))->>'solicitud_monto', coalesce(pg_temp.j((select v from res where k = 'G1'))->>'solicitud_moneda', '')));
select pg_temp.caso('G G1: capital 5000.00 PEN (moneda del lead), contactado, ciclo 2, episodio abierto con ese capital', 'contactado|5000|PEN|2|5000.00|PEN',
  (select concat_ws('|', l.etapa, l.monto_estimado, l.moneda, l.ciclo_actual, la.monto_estimado, la.moneda)
     from crm.leads l left join crm.lead_asignaciones la on la.lead_id = l.id and la.finalizado_en is null where l.id = (select id from c where clave = 'G1')));
select pg_temp.caso('G replay de la _v2 (mismo id y mismo capital, 5000.00 = 5000) → replay', 'true|contactado',
  pg_temp.valor(format('select (x->>''replay'') || ''|'' || (x->>''etapa'') from crm.reactivar_lead_base_v2(%L, %L, null, 5000.00) x', (select g1 from op), (select id from c where clave = 'G1')), (select v1 from f), 'authenticated'));
select pg_temp.caso('G r1 (Codex): mismo id con OTRO capital u otra moneda → 23505 «otro contenido»', 'ERROR 23505 Esta operacion ya corresponde a otro contenido|ERROR 23505 Esta operacion ya corresponde a otro contenido|ERROR 23505 Esta operacion ya corresponde a otro contenido',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(%L, %L, null, 6000)::text', (select g1 from op), (select id from c where clave = 'G1')), (select v1 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select crm.reactivar_lead_base_v2(%L, %L, null, 5000, ''USD'')::text', (select g1 from op), (select id from c where clave = 'G1')), (select v1 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select crm.reactivar_lead_base(%L, %L)::text', (select g1 from op), (select id from c where clave = 'G1')), (select v1 from f), 'authenticated'));
select pg_temp.caso('G G1 ya no está descartado → 22023', 'ERROR 22023 El lead ya no esta en la base (no esta descartado)',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 5000)::text', (select id from c where clave = 'G1')), (select v1 from f), 'authenticated'));
insert into res select 'G3', pg_temp.ejecutar(format('select x->>''etapa'' from crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 1500.25) x', (select id from c where clave = 'G3')), (select v1 from f));
select pg_temp.caso('G G3 (USD sin capital) con 1500.25 y moneda NULL → conserva USD', 'contactado|1500.25|USD',
  (select v from res where k = 'G3') || (select '|' || l.monto_estimado || '|' || l.moneda from crm.leads l where l.id = (select id from c where clave = 'G3')));
insert into res select 'G4', pg_temp.ejecutar(format('select x->>''etapa'' from crm.reactivar_lead_base_v2(gen_random_uuid(), %L, ''sup1 reactiva'', 800, ''USD'') x', (select id from c where clave = 'G4')), (select s1 from f));
select pg_temp.caso('G G4 por sup1 (su equipo) con 800 USD → USD', 'contactado|800|USD',
  (select v from res where k = 'G4') || (select '|' || l.monto_estimado || '|' || l.moneda from crm.leads l where l.id = (select id from c where clave = 'G4')));
insert into res select 'G2', pg_temp.ejecutar(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 1, ''USD'')::text', (select id from c where clave = 'G2')), (select v1 from f));
select pg_temp.caso('G G2 (ya con 3000 PEN): la _v2 ignora 1 USD; la respuesta dice el capital efectivo (3000 PEN) y el pedido (1 USD)', 'contactado|3000|PEN|3000|PEN|1|USD',
  concat_ws('|', pg_temp.j((select v from res where k = 'G2'))->>'etapa',
            (select l.monto_estimado || '|' || l.moneda from crm.leads l where l.id = (select id from c where clave = 'G2')),
            pg_temp.j((select v from res where k = 'G2'))->>'monto_estimado', pg_temp.j((select v from res where k = 'G2'))->>'moneda',
            pg_temp.j((select v from res where k = 'G2'))->>'solicitud_monto', pg_temp.j((select v from res where k = 'G2'))->>'solicitud_moneda'));
select pg_temp.caso('G «agendó cita» sobre un lead sin capital → 22023 y no deja intento', 'ERROR 22023 Indica el capital estimado para reactivar|0|descartado',
  pg_temp.valor(format('select crm.registrar_intento_base(gen_random_uuid(), %L, ''agendo_reunion'')::text', (select id from c where clave = 'G5')), (select v1 from f), 'authenticated')
  || '|' || (select count(*) from crm.actividades a where a.lead_id = (select id from c where clave = 'G5') and a.metadata->>'evento' = 'intento_base')
  || '|' || (select l.etapa from crm.leads l where l.id = (select id from c where clave = 'G5')));
select pg_temp.caso('G registrar_intento_base_v2: «agendó cita» sin capital → 22023 y no deja intento', 'ERROR 22023 Indica el capital estimado para reactivar|0',
  pg_temp.valor(format('select crm.registrar_intento_base_v2(gen_random_uuid(), %L, ''agendo_reunion'')::text', (select id from c where clave = 'G5')), (select v1 from f), 'authenticated')
  || '|' || (select count(*) from crm.actividades a where a.lead_id = (select id from c where clave = 'G5') and a.metadata->>'evento' = 'intento_base'));
select pg_temp.caso('G registrar_intento_base_v2: «agendó cita» con capital 0 → 22023', 'ERROR 22023 El capital estimado debe ser mayor que 0, de hasta 9999999999.99 y con 2 decimales como maximo',
  pg_temp.valor(format('select crm.registrar_intento_base_v2(gen_random_uuid(), %L, ''agendo_reunion'', null, null, 0)::text', (select id from c where clave = 'G5')), (select v1 from f), 'authenticated'));
insert into res select 'G5a', pg_temp.ejecutar(format('select crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'')::text', (select id from c where clave = 'G5')), (select v1 from f));
insert into res select 'G5b', pg_temp.ejecutar(format('select crm.registrar_intento_base_v2(gen_random_uuid(), %L, ''no_contesto'', null, null, 999, ''USD'')::text', (select id from c where clave = 'G5')), (select v1 from f));
select pg_temp.caso('G intento normal sobre un lead sin capital, igual que hoy (publicada y _v2, que ignora el capital): intento 1 y 2, sin reactivar, sin capital',
  '1|false|2|false|descartado|(sin capital)|PEN',
  concat_ws('|', pg_temp.j((select v from res where k = 'G5a'))->>'intento_n', pg_temp.j((select v from res where k = 'G5a'))->>'reactivado',
            pg_temp.j((select v from res where k = 'G5b'))->>'intento_n', pg_temp.j((select v from res where k = 'G5b'))->>'reactivado',
            (select concat_ws('|', l.etapa, coalesce(l.monto_estimado::text, '(sin capital)'), l.moneda) from crm.leads l where l.id = (select id from c where clave = 'G5'))));
insert into res select 'G6', pg_temp.ejecutar(format('select crm.registrar_intento_base_v2(%L, %L, ''agendo_reunion'', ''cita el lunes'', null, 1800, ''USD'')::text', (select g6 from op), (select id from c where clave = 'G6')), (select v1 from f));
select pg_temp.caso('G registrar_intento_base_v2: «agendó cita» con 1800 USD → reactiva con ese capital (lead y episodio)', 'contactado|true|agendo_reunion|contactado|1800|USD|1800.00|USD',
  concat_ws('|', pg_temp.j((select v from res where k = 'G6'))->>'etapa', pg_temp.j((select v from res where k = 'G6'))->>'reactivado', pg_temp.j((select v from res where k = 'G6'))->>'resultado',
            (select concat_ws('|', l.etapa, l.monto_estimado, l.moneda, la.monto_estimado, la.moneda)
               from crm.leads l left join crm.lead_asignaciones la on la.lead_id = l.id and la.finalizado_en is null where l.id = (select id from c where clave = 'G6'))));
select pg_temp.caso('G r1: el intento responde con el capital efectivo (1800 USD); su replay con otro capital → 23505; con el mismo, replay', '1800|USD|ERROR 23505 Esta operacion ya corresponde a otro contenido|true',
  concat_ws('|', pg_temp.j((select v from res where k = 'G6'))->>'monto_estimado', pg_temp.j((select v from res where k = 'G6'))->>'moneda',
            pg_temp.valor(format('select crm.registrar_intento_base_v2(%L, %L, ''agendo_reunion'', ''cita el lunes'', null, 1900, ''USD'')::text', (select g6 from op), (select id from c where clave = 'G6')), (select v1 from f), 'authenticated'),
            pg_temp.valor(format('select x->>''replay'' from crm.registrar_intento_base_v2(%L, %L, ''agendo_reunion'', ''cita el lunes'', null, 1800, ''USD'') x', (select g6 from op), (select id from c where clave = 'G6')), (select v1 from f), 'authenticated')));
select pg_temp.caso('G la _v2 de intentos responde con las MISMAS claves que la publicada', 'igual',
  case when (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.j((select v from res where k = 'G5a'))) k)
          = (select string_agg(k, ',' order by k) from jsonb_object_keys(pg_temp.j((select v from res where k = 'G6'))) k) then 'igual'
       else 'distintas: ' || coalesce((select v from res where k = 'G6'), '(nulo)') end);
select pg_temp.caso('G registrar_intento_base_v2 sin sesión → 42501; service_role sin EXECUTE', 'ERROR 42501 No autorizado|ERROR 42501 permission denied for function registrar_intento_base_v2',
  pg_temp.valor(format('select crm.registrar_intento_base_v2(gen_random_uuid(), %L, ''no_contesto'')::text', (select id from c where clave = 'G5')), null, 'authenticated')
  || '|' || pg_temp.valor(format('select crm.registrar_intento_base_v2(gen_random_uuid(), %L, ''no_contesto'')::text', (select id from c where clave = 'G5')), null, 'service_role'));
select pg_temp.caso('G _v2 sobre un lead de otro equipo → P0002', 'ERROR P0002 Lead no encontrado o fuera de tu ambito',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 100)::text', (select id from c where clave = 'L3')), (select v1 from f), 'authenticated'));
select pg_temp.caso('G _v2 sin sesión → 42501; anon y service_role sin EXECUTE', 'ERROR 42501 No autorizado|ERROR 42501 permission denied|ERROR 42501 permission denied for function reactivar_lead_base_v2',
  pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 100)::text', (select id from c where clave = 'G5')), null, 'authenticated')
  || '|' || split_part(pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 100)::text', (select id from c where clave = 'G5')), null, 'anon'), ' for ', 1)
  || '|' || pg_temp.valor(format('select crm.reactivar_lead_base_v2(gen_random_uuid(), %L, null, 100)::text', (select id from c where clave = 'G5')), null, 'service_role'));
insert into res select 'L1', pg_temp.claves_json(pg_temp.ejecutar(format('select crm.reactivar_lead_base(gen_random_uuid(), %L)::text', (select id from c where clave = 'L1')), (select v1 from f)));
select pg_temp.caso('G puerta publicada con un lead CON capital (llamada posicional de siempre): contactado, mismas claves',
  'ciclo_n,etapa,evento,lead_id,moneda,monto_estimado,ok,reabierto_por,reactivado_en,replay,solicitud_moneda,solicitud_monto|contactado|1000',
  (select v from res where k = 'L1') || (select '|' || l.etapa || '|' || l.monto_estimado from crm.leads l where l.id = (select id from c where clave = 'L1')));
select pg_temp.caso('G Reactivar en el seguimiento: 6 asignados, 2 trabajados (G5, G6), 1 cita (G6), 5 reactivados', '6/0/0/2/0/1/5/0|0/0',
  pg_temp.valor(format('select pg_temp.sa(%L, %L)', (select id from bx where nombre = 'B10 Reactivar'), (select v1 from f)), (select s1 from f)));

-- ───────── H · F4 sigue cuadrando, y todo el seguimiento tras G ─────────
select pg_temp.caso('H F4 sup1: detalle = cifra y en base = la lista del analista', 'cuadra', pg_temp.valor('select pg_temp.cuadre_f4()', (select s1 from f), 'authenticated'));
select pg_temp.caso('H F4 Gerencia: detalle = cifra y en base = la lista del analista', 'cuadra', pg_temp.valor('select pg_temp.cuadre_f4()', (select g from f)));
select pg_temp.caso('H F4: vend1 tiene intentos de hoy (el cuadre compara algo)', 'true',
  pg_temp.valor($q$select ((select r.intentos_hoy from crm.base_gestion_resumen() r where r.vendedor_id = (select v1 from pg_temp.f)) >= 5)::text$q$, (select s1 from f)));
select pg_temp.caso('H seguimiento tras G: cifra = detalle (Gerencia)', 'cuadra', pg_temp.valor('select pg_temp.cuadre()', (select g from f)));

-- ───────── U · r2/r3: la definición ÚNICA del estado en B9 y B10 (reparto y recogida reales, sin tocar fechas) ─────────
-- Dos bases nuevas de sup1: «B10 Unica» (archivo: U1…U5) y «B10 Unica Armada» (desde el CRM: UA y UC, descartados de vend1 que
-- CONSERVAN su analista; UB, de la bandeja del sup anidado). Preparación: U2 vetado, U3 en descanso, U4 asignado a vend2 por la
-- ficha (otra vía).
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, asignado_supervisor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, x.sup, 1000, 'PEN', coalesce(x.v, x.sup), true
  from f, lateral (values ('b1000000-0000-4000-8000-0000000000fa'::uuid, 'B10 U ARMADO CON VEND1', '966790901', f.v1, null::uuid),
                          ('b1000000-0000-4000-8000-0000000000fb'::uuid, 'B10 U ARMADO DE BANDEJA', '966790902', null::uuid, f.sa),
                          ('b1000000-0000-4000-8000-0000000000fc'::uuid, 'B10 U ARMADO CON VEND1 DOS', '966790903', f.v1, null::uuid)) x(id, nombre, tel, v, sup);
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde'
 where id in ('b1000000-0000-4000-8000-0000000000fa', 'b1000000-0000-4000-8000-0000000000fb', 'b1000000-0000-4000-8000-0000000000fc');
insert into c values ('UA', 'b1000000-0000-4000-8000-0000000000fa'), ('UB', 'b1000000-0000-4000-8000-0000000000fb'), ('UC', 'b1000000-0000-4000-8000-0000000000fc');
insert into bx select 'B10 Unica', pg_temp.ejecutar($q$select crm.crear_base(gen_random_uuid(), 'B10 Unica', 'archivo', null, 'u.csv')->>'base_id'$q$, (select s1 from f))::uuid;
select pg_temp.caso('U base Unica: 5 contactos (U5 con capital); Unica Armada: UA y UC (con vend1) y UB (bandeja del anidado)', '5|3',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 U1","telefono":"966790911"},{"fila":2,"nombre":"B10 U2","telefono":"966790912"},{"fila":3,"nombre":"B10 U3","telefono":"966790913"},{"fila":4,"nombre":"B10 U4","telefono":"966790914"},{"fila":5,"nombre":"B10 U5","telefono":"966790915","capital":"2000"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Unica')), (select s1 from f))
  || '|' || pg_temp.ejecutar(format($q$select crm.armar_base_crm(gen_random_uuid(), 'B10 Unica Armada', null, array[%L, %L, %L]::uuid[])->>'incluidos'$q$,
    (select id from c where clave = 'UA'), (select id from c where clave = 'UB'), (select id from c where clave = 'UC')), (select s1 from f)));
insert into bx select 'B10 Unica Armada', b.id from crm.bases_carga b where b.nombre = 'B10 Unica Armada';
insert into c select 'U' || i, (select l.id from crm.leads l where l.telefono = '+5196679091' || i) from generate_series(1, 5) i;
select pg_temp.caso('U preparar: U2 vetado por sup1, U4 asignado a vend2 por la ficha', 'ok|ok',
  coalesce(pg_temp.ejecutar(format($q$select 'ok' from (select crm.marcar_no_contactar(%L, 'B10 U: no quiere')) x$q$, (select id from c where clave = 'U2')), (select s1 from f)), '(nulo)')
  || '|' || coalesce(pg_temp.ejecutar(format($q$update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L returning 'ok'$q$, (select v2 from f), (select id from c where clave = 'U4')), (select s1 from f)), '(nulo)'));
select set_config('crm.op_base_gestion', 'on', true);
update crm.leads set enfriado_hasta = (select hoy + 5 from f) where id = (select id from c where clave = 'U3');
select set_config('crm.op_base_gestion', 'off', true);
-- Estados por la lista de B9 (crm.contactos_de_base) = por el detalle de B10 (seguimiento_base_detalle): UNA definición.
create function pg_temp.estados_b9(p_base text, p_filtro text default 'todos') returns text language sql as $$
  select coalesce(string_agg(c.clave || ':' || x.estado, ',' order by c.clave), '(ninguno)')
    from crm.contactos_de_base((select b.id from pg_temp.bx b where b.nombre = p_base), p_filtro) x join pg_temp.c c on c.id = x.lead_id $$;
create function pg_temp.estados_b10(p_base text) returns text language sql as $$
  select coalesce(string_agg(c.clave || ':' || d.estado, ',' order by c.clave), '(ninguno)')
    from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = p_base), null, 'total') d join pg_temp.c c on c.id = d.lead_id $$;
-- El primer rechazado de un individual («ERROR 22023 <detail>»): «motivo|clave»; si no rechazó, lo que devolvió (no aborta).
create function pg_temp.rechazo(p text) returns text language plpgsql as $$
begin
  if p like 'ERROR 22023 %' then
    return (select (d #>> '{rechazados,0,motivo}') || '|' || coalesce((select c.clave from pg_temp.c c where c.id = (d #>> '{rechazados,0,lead_id}')::uuid), '?')
              from (select substr(p, 13)::jsonb as d) x);
  end if;
  return 'no rechazó: ' || left(coalesce(p, '(nulo)'), 120);
exception when others then
  return 'no rechazó: ' || left(coalesce(p, '(nulo)'), 120);
end $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
select pg_temp.caso('U estados de Unica por la lista de B9 (contactos_de_base, todos) = escritos a mano', 'U1:sin_repartir,U2:no_contactar,U3:en_descanso,U4:movido_otra_via,U5:sin_repartir',
  pg_temp.valor($q$select pg_temp.estados_b9('B10 Unica')$q$, (select s1 from f), 'authenticated'));
select pg_temp.caso('U … = los del seguimiento de B10 (seguimiento_base_detalle, total)', 'U1:sin_repartir,U2:no_contactar,U3:en_descanso,U4:movido_otra_via,U5:sin_repartir',
  pg_temp.valor($q$select pg_temp.estados_b10('B10 Unica')$q$, (select s1 from f), 'authenticated'));
select pg_temp.caso('U r3 (E1): Unica Armada: los armados con su analista anterior (UA, UC) y el de bandeja (UB) están DISPONIBLES (B9 = B10)', 'UA:sin_repartir,UB:sin_repartir,UC:sin_repartir|UA:sin_repartir,UB:sin_repartir,UC:sin_repartir',
  pg_temp.valor($q$select pg_temp.estados_b9('B10 Unica Armada') || '|' || pg_temp.estados_b10('B10 Unica Armada')$q$, (select s1 from f), 'authenticated'));
select pg_temp.caso('U Unica (contado a mano): 5 · sin repartir 2 (U1 U5) · descanso 1 (U3, sin reparto) · movido 1 (U4) · vetado 1 (U2)', '5/2/0/0/0/1/0/0/0.0000|1/0/1',
  pg_temp.valor($q$select pg_temp.sb('B10 Unica')$q$, (select s1 from f)));
select pg_temp.caso('U Unica Armada (contado a mano): 3 · sin repartir 3 (UA UB UC)', '3/3/0/0/0/0/0/0/0.0000|0/0/0',
  pg_temp.valor($q$select pg_temp.sb('B10 Unica Armada')$q$, (select s1 from f)));
select pg_temp.caso('U el filtro «sin_repartir» de contactos_de_base (como B9: sin analista de la base) trae los 5 con su estado; la cifra sin_repartir = los de ese estado', 'U1:sin_repartir,U2:no_contactar,U3:en_descanso,U4:movido_otra_via,U5:sin_repartir|2|2',
  pg_temp.valor($q$select pg_temp.estados_b9('B10 Unica', 'sin_repartir') || '|' || (select s.sin_repartir from crm.seguimiento_bases() s where s.nombre = 'B10 Unica')
                   || '|' || (select count(*) from crm.contactos_de_base((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica'), 'todos') x where x.estado = 'sin_repartir')$q$,
    (select s1 from f), 'authenticated'));
select pg_temp.caso('U el filtro por defecto de contactos_de_base es «sin_repartir»', 'U1:sin_repartir,U2:no_contactar,U3:en_descanso,U4:movido_otra_via,U5:sin_repartir',
  pg_temp.valor($q$select pg_temp.estados_b9('B10 Unica', null)$q$, (select s1 from f), 'authenticated'));
select pg_temp.caso('U Armada (r1) por la lista de B9: D1, D2 y D4 disponibles, D3 sin tocar (= el seguimiento)', 'D1:sin_repartir,D2:sin_repartir,D3:sin_tocar,D4:sin_repartir|igual',
  pg_temp.valor($q$select pg_temp.estados_b9('B10 Armada') || '|' || case when pg_temp.estados_b9('B10 Armada') = pg_temp.estados_b10('B10 Armada') then 'igual' else 'distinto' end$q$,
    (select s1 from f), 'authenticated'));
select pg_temp.caso('U los retirados (F15, F18) cuentan en el seguimiento pero no salen en la lista de B9 (solo contactos activos)', '2|0',
  pg_temp.valor($q$select (select s.retirados from crm.seguimiento_bases() s where s.nombre = 'B10 Feria') || '|'
                          || (select count(*) from crm.contactos_de_base((select b.id from pg_temp.bx b where b.nombre = 'B10 Feria'), 'todos') x
                               where x.lead_id in (select c.id from pg_temp.c c where c.clave in ('F15', 'F18')))$q$, (select g from f), 'authenticated'));
-- r3 (coordinador): la lista de la base para gestión oculta SOLO a los dormidos del archivo sin repartir; un armado nunca se oculta.
select pg_temp.caso('U r3: lista de sup1: U1 (dormido del archivo, sin repartir) no sale; UA, UB y UC (armados, sin repartir) SÍ, con su base', 'sin fila|B10 Unica Armada|B10 Unica Armada|B10 Unica Armada',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'U1')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UA')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UB')), (select s1 from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UC')), (select s1 from f))));
select pg_temp.caso('U r3: … igual para Gerencia; y vend1 (su analista anterior) sigue viendo UA y UC con su base', 'sin fila|B10 Unica Armada|B10 Unica Armada|B10 Unica Armada|B10 Unica Armada',
  concat_ws('|', pg_temp.valor(format('select pg_temp.base_en_lista(%L, true)', (select id from c where clave = 'U1')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UA')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UB')), (select g from f)),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UA')), (select v1 from f), 'authenticated'),
               pg_temp.valor(format('select pg_temp.base_en_lista(%L)', (select id from c where clave = 'UC')), (select v1 from f), 'authenticated')));
-- El intento por registrar_intento_base_v2 escribe la metadata del intento como el núcleo de B3c, y su rellamada activa el
-- candado de B9 (private.base_gestion_en_gestion_hasta lee metadata.proxima_llamada_en del último intento tras el corte). vend1
-- trabaja UA (su armado, sin repartir): queda «trabajado» y el bloque no lo elige.
create temp table ru (k text primary key, v jsonb);
grant select on ru to authenticated;
create temp table pv as select date_trunc('second', now()) + interval '9 days' as prox;
grant select on pv to authenticated;
insert into ru select 'v2rell', pg_temp.j(pg_temp.ejecutar(format($q$select crm.registrar_intento_base_v2(gen_random_uuid(), %L, 'volver_a_llamar', 'rellamar en 9 días', %L)::text$q$,
  (select id from c where clave = 'UA'), (select prox from pv)), (select v1 from f)));
-- El mismo intento por la puerta PUBLICADA (núcleo de B3c) sobre D3 (de vend1, repartido): la metadata de referencia.
insert into ru select 'pubrell', pg_temp.j(pg_temp.ejecutar(format($q$select crm.registrar_intento_base(gen_random_uuid(), %L, 'volver_a_llamar', 'rellamar en 9 días', %L)::text$q$,
  (select id from c where clave = 'D3'), (select prox from pv)), (select v1 from f)));
select pg_temp.caso('U la _v2 con rellamada escribe la metadata del intento como la puerta publicada (núcleo de B3c): mismas claves y mismos valores salvo los del lead', 'true|igual|igual',
  (select ((a.metadata->>'proxima_llamada_en')::timestamptz = (select prox from pv))::text
          || '|' || case when (select string_agg(k, ',' order by k) from jsonb_object_keys(a.metadata - 'respuesta') k)
                            = (select string_agg(k, ',' order by k) from jsonb_object_keys((select a2.metadata - 'respuesta' from crm.actividades a2
                                where a2.lead_id = (select id from c where clave = 'D3') and a2.metadata->>'evento' = 'intento_base' order by a2.creado_en desc limit 1)) k)
                         then 'igual' else 'distintas' end
          || '|' || case when (a.metadata - 'respuesta' - 'intento_n' - 'ciclo_n')
                            = (select a2.metadata - 'respuesta' - 'intento_n' - 'ciclo_n' from crm.actividades a2
                                where a2.lead_id = (select id from c where clave = 'D3') and a2.metadata->>'evento' = 'intento_base' order by a2.creado_en desc limit 1)
                         then 'igual' else 'distinta: ' || (a.metadata - 'respuesta')::text end
     from crm.actividades a where a.lead_id = (select id from c where clave = 'UA') and a.metadata->>'evento' = 'intento_base'));
select pg_temp.caso('U … el candado de B9: en gestión hasta el día de la rellamada (9 días > 7); UA sin repartir y en gestión = «trabajado» (como B9)', 'true|trabajado|trabajado',
  ((select private.base_gestion_en_gestion_hasta((select id from c where clave = 'UA'))) = ((select prox from pv) at time zone 'America/Lima')::date)::text
  || '|' || pg_temp.valor($q$select d.estado from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica Armada'), null, 'total') d where d.lead_id = (select c.id from pg_temp.c c where c.clave = 'UA')$q$, (select s1 from f), 'authenticated')
  || '|' || pg_temp.valor($q$select x.estado from crm.contactos_de_base((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica Armada'), 'todos') x where x.lead_id = (select c.id from pg_temp.c c where c.clave = 'UA')$q$, (select s1 from f), 'authenticated'));
-- El bloque elige SOLO el estado sin_repartir —también un armado con su analista anterior (E1)—; lo demás sale en omitidos.
select pg_temp.caso('U bloque de 3 en Unica → 22023: solo hay 2 (U1 y U5)', 'ERROR 22023 Solo hay 2 contactos disponibles para repartir en esta base (pediste 3)',
  pg_temp.bloque((select id from bx where nombre = 'B10 Unica'), (select v2 from f), 3, (select s1 from f)));
insert into ru select 'bloque', pg_temp.j(pg_temp.bloque((select id from bx where nombre = 'B10 Unica'), (select v2 from f), 2, (select s1 from f)));
select pg_temp.caso('U bloque de 2 en Unica a vend2 → U1 y U5; omitidos: en descanso, movido por otra vía, No contactar', '2|en_descanso:1,movido_otra_via:1,no_contactar:1|v2,b:s1,v2,v2',
  concat_ws('|', (select v->>'repartidos' from ru where k = 'bloque'),
            (select string_agg((o->>'motivo') || ':' || (o->>'cantidad'), ',' order by o->>'motivo') from ru, jsonb_array_elements(ru.v->'omitidos') o where ru.k = 'bloque'),
            (select string_agg(case l.vendedor_id when f.v1 then 'v1' when f.v2 then 'v2' else 'b:' || case l.asignado_supervisor_id when f.s1 then 's1' else '?' end end, ',' order by c.clave)
               from c join crm.leads l on l.id = c.id, f where c.clave in ('U1', 'U4', 'U3', 'U5') and l.id = c.id)));
select pg_temp.caso('U r3: bloque de 3 en Unica Armada → 22023: solo hay 2 (UB y UC; UA está en gestión de vend1)', 'ERROR 22023 Solo hay 2 contactos disponibles para repartir en esta base (pediste 3)',
  pg_temp.bloque((select id from bx where nombre = 'B10 Unica Armada'), (select v2 from f), 3, (select s1 from f)));
insert into ru select 'armada', pg_temp.j(pg_temp.bloque((select id from bx where nombre = 'B10 Unica Armada'), (select v2 from f), 2, (select s1 from f)));
select pg_temp.caso('U r3 (E1): bloque de 2 en Unica Armada → UB y UC: el armado con su analista anterior (UC) pasa de vend1 a vend2 con su «reasignación»; UA (en gestión) omitido', '2|en_gestion:1|v1|v2|v2|1',
  concat_ws('|', (select v->>'repartidos' from ru where k = 'armada'),
            (select string_agg((o->>'motivo') || ':' || (o->>'cantidad'), ',' order by o->>'motivo') from ru, jsonb_array_elements(ru.v->'omitidos') o where ru.k = 'armada'),
            (select case l.vendedor_id when f.v1 then 'v1' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'UA')),
            (select case l.vendedor_id when f.v2 then 'v2' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'UB')),
            (select case l.vendedor_id when f.v2 then 'v2' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'UC')),
            (select count(*) from crm.actividades a, f where a.lead_id = (select id from c where clave = 'UC') and a.tipo = 'reasignacion'
               and (a.metadata->>'vendedor_anterior')::uuid = f.v1 and (a.metadata->>'vendedor_nuevo')::uuid = f.v2)));
-- El individual: lo movido por otra vía se rechaza; el armado en gestión solo va a su propio analista.
select pg_temp.caso('U individual de U4 (movido por otra vía) a vend1 → 22023 con el rechazado movido_otra_via', 'movido_otra_via|U4',
  pg_temp.rechazo(pg_temp.individual((select id from bx where nombre = 'B10 Unica'), array[(select id from c where clave = 'U4')], (select v1 from f), (select s1 from f))));
select pg_temp.caso('U individual de UA (en gestión de vend1) a vend2 → 22023 en_gestion', 'en_gestion|UA',
  pg_temp.rechazo(pg_temp.individual((select id from bx where nombre = 'B10 Unica Armada'), array[(select id from c where clave = 'UA')], (select v2 from f), (select s1 from f))));
insert into ru select 'ua', pg_temp.j(pg_temp.individual((select id from bx where nombre = 'B10 Unica Armada'), array[(select id from c where clave = 'UA')], (select v1 from f), (select s1 from f)));
select pg_temp.caso('U individual de UA a vend1 (su analista) → repartido sin tocar el lead (sin «reasignación»), sin tocar (su intento fue antes del reparto)', '1|v1|v1|0|sin_tocar',
  concat_ws('|', (select v->>'repartidos' from ru where k = 'ua'),
            (select case l.vendedor_id when f.v1 then 'v1' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'UA')),
            (select case bl.analista_id when f.v1 then 'v1' else '?' end from crm.base_carga_leads bl, f where bl.lead_id = (select id from c where clave = 'UA') and bl.activo),
            (select count(*) from crm.actividades a where a.lead_id = (select id from c where clave = 'UA') and a.tipo = 'reasignacion'),
            pg_temp.valor($q$select d.estado from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica Armada'), null, 'total') d
                             where d.lead_id = (select c.id from pg_temp.c c where c.clave = 'UA')$q$, (select s1 from f), 'authenticated')));
select pg_temp.caso('U … recoger de vend1 en Unica Armada → 0 recogidos, 1 omitido (UA en seguimiento activo B6)', '0|1',
  coalesce((select (x->>'recogidos') || '|' || (x->>'omitidos') from (select pg_temp.j(pg_temp.recoger((select id from bx where nombre = 'B10 Unica Armada'), (select v1 from f), (select s1 from f))) x) q), '(nulo)'));
-- Recoger = el estado sin_tocar: un vetado no se recoge.
select pg_temp.caso('U preparar: sup1 veta U5 (repartido a vend2)', 'ok',
  coalesce(pg_temp.ejecutar(format($q$select 'ok' from (select crm.marcar_no_contactar(%L, 'B10 U: no quiere')) x$q$, (select id from c where clave = 'U5')), (select s1 from f)), '(nulo)'));
insert into ru select 'recoger', pg_temp.j(pg_temp.recoger((select id from bx where nombre = 'B10 Unica'), (select v2 from f), (select s1 from f)));
select pg_temp.caso('U recoger de vend2 en Unica → solo U1 (sin tocar); U5 (vetado) no: omitido', '1|1|0|b:s1|v2|sin_repartir|no_contactar',
  concat_ws('|', (select v->>'recogidos' from ru where k = 'recoger'), (select v->>'omitidos' from ru where k = 'recoger'), (select v->>'pendientes' from ru where k = 'recoger'),
            (select case when l.vendedor_id is null and l.asignado_supervisor_id = f.s1 then 'b:s1' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'U1')),
            (select case l.vendedor_id when f.v2 then 'v2' else '?' end from crm.leads l, f where l.id = (select id from c where clave = 'U5')),
            pg_temp.valor($q$select d.estado from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica'), null, 'total') d where d.lead_id = (select c.id from pg_temp.c c where c.clave = 'U1')$q$, (select s1 from f), 'authenticated'),
            pg_temp.valor($q$select d.estado from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica'), null, 'total') d where d.lead_id = (select c.id from pg_temp.c c where c.clave = 'U5')$q$, (select s1 from f), 'authenticated')));
-- Recoger en Feria (B9 real): de vend1 solo lo SIN TOCAR (F03, F04, F10 —su intento fue ANTES del reparto— y F13); F05 y F06
-- (trabajados), F07 y F08 (fuera del descarte) y F09, F11 y F12 (movidos) quedan.
insert into ru select 'recoger-feria', pg_temp.j(pg_temp.recoger((select id from bx where nombre = 'B10 Feria'), (select v1 from f), (select s1 from f)));
select pg_temp.caso('U recoger de vend1 en Feria → F03, F04, F10 y F13 (sin tocar: el intento de F10 fue ANTES del reparto); los otros 7 quedan', '4|7|0|F03:sin_repartir,F04:sin_repartir,F10:sin_repartir,F13:sin_repartir',
  concat_ws('|', (select v->>'recogidos' from ru where k = 'recoger-feria'), (select v->>'omitidos' from ru where k = 'recoger-feria'), (select v->>'pendientes' from ru where k = 'recoger-feria'),
            pg_temp.valor($q$select string_agg(c.clave || ':' || d.estado, ',' order by c.clave) from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Feria'), null, 'total') d
                             join pg_temp.c c on c.id = d.lead_id where c.clave in ('F03', 'F04', 'F10', 'F13')$q$, (select s1 from f), 'authenticated')));
-- Coherencia global (Gerencia): para TODA base viva, el estado de cada contacto en la lista de B9 = su estado en el seguimiento
-- de B10, y la cifra sin_repartir = los contactos de la lista de B9 en ese estado.
select pg_temp.caso('U coherencia B9 = B10 en todas las bases vivas (Gerencia): mismo estado por contacto y cifra sin_repartir = los de ese estado', 'coherente',
  pg_temp.valor($q$select coalesce(string_agg(m, '; '), 'coherente') from (
      select s.nombre || ': ' || x.lead_id || ' ' || x.estado || '≠' || coalesce(d.estado, '(sin fila)') as m
        from crm.seguimiento_bases() s
        cross join lateral crm.contactos_de_base(s.base_id, 'todos') x
        left join lateral (select d.estado from crm.seguimiento_base_detalle(s.base_id, null, 'total') d where d.lead_id = x.lead_id) d on true
       where x.estado is distinct from d.estado
      union all
      select s.nombre || ': sin_repartir ' || s.sin_repartir || '≠' || (select count(*) from crm.contactos_de_base(s.base_id, 'todos') x where x.estado = 'sin_repartir')
        from crm.seguimiento_bases() s
       where s.sin_repartir <> (select count(*) from crm.contactos_de_base(s.base_id, 'todos') x where x.estado = 'sin_repartir')) q$q$, (select g from f), 'authenticated'));
select pg_temp.caso('U todo número se abre tras U (sup1 y Gerencia)', 'cuadra|cuadra',
  pg_temp.valor('select pg_temp.cuadre()', (select s1 from f), 'authenticated') || '|' || pg_temp.valor('select pg_temp.cuadre()', (select g from f)));
-- ───────── V · r4 (Codex r2, 2 P2; auditor-rls P3-1): la fila anónima, el analista externo explícito y un estado NULL ─────────
-- «B10 Anon» de sup1: 3 contactos que Gerencia reparte a vend1 (del equipo de sup1) y a vend3 y vend4 (de sup2).
insert into bx select 'B10 Anon', pg_temp.ejecutar($q$select crm.crear_base(gen_random_uuid(), 'B10 Anon', 'archivo', null, 'anon.csv')->>'base_id'$q$, (select s1 from f))::uuid;
alter table f add column v4 uuid;
update f set v4 = (select id from auth.users where email = 'vend4.crm@demo.avancecorp.pe');
select pg_temp.caso('V Anon: 3 contactos', '3',
  pg_temp.ejecutar(format($q$select crm.cargar_base_lote(gen_random_uuid(), %L, '[{"fila":1,"nombre":"B10 V1","telefono":"966790921"},{"fila":2,"nombre":"B10 V2","telefono":"966790922"},{"fila":3,"nombre":"B10 V3","telefono":"966790923"}]'::jsonb)->'lote'->>'cargadas'$q$,
    (select id from bx where nombre = 'B10 Anon')), (select s1 from f)));
insert into c select 'V' || i, (select l.id from crm.leads l where l.telefono = '+5196679092' || i) from generate_series(1, 3) i;
select pg_temp.caso('V Anon: Gerencia reparte V1 a vend1 y V2, V3 a vend3 y vend4 (otro equipo)', '3',
  (select coalesce(pg_temp.j(x)->>'repartidos', x) from (select pg_temp.ejecutar(format($q$select crm.repartir_base(gen_random_uuid(), %L, %L::jsonb)::text$q$, (select id from bx where nombre = 'B10 Anon'),
       jsonb_build_object('modo', 'individual', 'asignaciones', jsonb_build_array(
         jsonb_build_object('lead_id', (select id from c where clave = 'V1'), 'analista_id', f.v1),
         jsonb_build_object('lead_id', (select id from c where clave = 'V2'), 'analista_id', f.v3),
         jsonb_build_object('lead_id', (select id from c where clave = 'V3'), 'analista_id', f.v4)))), f.g) as x from f) q));
grant select on f to anon, authenticated, service_role;
select pg_temp.caso('V r4 (Codex P2-1): sup1 ve a vend1 con nombre y UNA sola fila anónima con la suma de vend3 y vend4 (la última)', '1/1/0/0/0/0/0/0|0/0 ; 2/2/0/0/0/0/0/0|0/0|2|1',
  pg_temp.valor(format($q$select pg_temp.sa(%1$L, (select v1 from pg_temp.f)) || ' ; ' || pg_temp.sa(%1$L, null) || '|' || (select count(*) from crm.seguimiento_base(%1$L))
                          || '|' || (select count(*) from crm.seguimiento_base(%1$L) s where s.analista_id is null and s.analista_nombre is null)$q$, (select id from bx where nombre = 'B10 Anon')), (select s1 from f), 'authenticated'));
select pg_temp.caso('V … la última fila es la anónima; la base (3 repartidos, 3 sin tocar) = la suma de sus filas = su detalle; los externos sin identificar', 'anonima|3|3|3|3|2',
  pg_temp.valor(format($q$select (select case when s.analista_id is null then 'anonima' else 'con nombre' end from crm.seguimiento_base(%1$L) with ordinality s order by s.ordinality desc limit 1)
                          || '|' || (select b.repartidos from crm.seguimiento_bases() b where b.base_id = %1$L) || '|' || (select sum(s.asignados) from crm.seguimiento_base(%1$L) s)
                          || '|' || (select b.sin_tocar from crm.seguimiento_bases() b where b.base_id = %1$L)
                          || '|' || (select count(*) from crm.seguimiento_base_detalle(%1$L, null, 'asignados'))
                          || '|' || (select count(*) from crm.seguimiento_base_detalle(%1$L, null, 'asignados') d where d.lead_id is null)$q$, (select id from bx where nombre = 'B10 Anon')), (select s1 from f), 'authenticated'));
select pg_temp.caso('V r4 (Codex P2-2): sup1 abre Anon por el UUID de vend3 (externo CON contactos) → P0002, el MISMO mensaje que vend2 (suyo, sin contactos)',
  'ERROR P0002 Analista no encontrado en esta base|ERROR P0002 Analista no encontrado en esta base|ERROR P0002 Analista no encontrado en esta base',
  pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''asignados'')', (select id from bx where nombre = 'B10 Anon'), (select v3 from f)), (select s1 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''total'')', (select id from bx where nombre = 'B10 Anon'), (select v4 from f)), (select s1 from f), 'authenticated')
  || '|' || pg_temp.valor(format('select count(*)::text from crm.seguimiento_base_detalle(%L, %L, ''asignados'')', (select id from bx where nombre = 'B10 Anon'), (select v2 from f)), (select s1 from f), 'authenticated'));
select pg_temp.caso('V Gerencia ve las tres filas con nombre (nunca una anónima) y abre la de vend3 en su contacto', '3|0|V2',
  pg_temp.valor(format($q$select (select count(*) from crm.seguimiento_base(%1$L) s where s.analista_id is not null and s.analista_nombre is not null)
                          || '|' || (select count(*) from crm.seguimiento_base(%1$L) s where s.analista_id is null)
                          || '|' || (select string_agg(c.clave, ',') from crm.seguimiento_base_detalle(%1$L, (select v3 from pg_temp.f), 'asignados') d join pg_temp.c c on c.id = d.lead_id)$q$,
    (select id from bx where nombre = 'B10 Anon')), (select g from f)));
-- Un estado NULL (doble de la definición única, solo dentro de una subtransacción deshecha) nunca se reparte (auditor-rls P3-1).
create function pg_temp.con_estado_nulo(p_que text) returns text language plpgsql as $$
declare v text;
begin
  begin
    execute $d$create or replace function private.bases_carga_estado_contacto(p_lead_id uuid, p_activo boolean, p_no_contactar boolean, p_etapa text,
               p_vendedor_id uuid, p_asignado_supervisor_id uuid, p_enfriado_hasta date, p_analista_id uuid, p_asignado_en timestamptz,
               p_agregado_en timestamptz, p_dueno uuid, p_subarbol uuid[], p_hoy date, p_intento boolean default null, p_cita boolean default null,
               p_reactivado boolean default null) returns text language sql stable set search_path = '' as 'select null::text'$d$;
    if p_que = 'bloque' then
      v := pg_temp.bloque((select id from pg_temp.bx where nombre = 'B10 Unica'), (select v1 from pg_temp.f), 1, (select s1 from pg_temp.f));
    else
      v := pg_temp.rechazo(pg_temp.individual((select id from pg_temp.bx where nombre = 'B10 Unica'), array[(select id from pg_temp.c where clave = 'U1')],
                                              (select v1 from pg_temp.f), (select s1 from pg_temp.f)));
    end if;
    raise exception using errcode = 'P0001', message = 'B10_DESHACER';
  exception when others then
    if sqlerrm <> 'B10_DESHACER' then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  return v;
end $$;
select pg_temp.caso('V r4 (auditor P3-1): con un estado NULL (doble), el bloque no elige a U1 (sin repartir)', 'ERROR 22023 Solo hay 0 contactos disponibles para repartir en esta base (pediste 1)',
  pg_temp.con_estado_nulo('bloque'));
select pg_temp.caso('V r4 (auditor P3-1): … y el individual lo rechaza con el motivo sin_estado', 'sin_estado|U1', pg_temp.con_estado_nulo('individual'));
select pg_temp.caso('V … el doble se deshizo: U1 sigue sin repartir por la definición única', 'sin_repartir',
  pg_temp.valor($q$select d.estado from crm.seguimiento_base_detalle((select b.id from pg_temp.bx b where b.nombre = 'B10 Unica'), null, 'total') d where d.lead_id = (select c.id from pg_temp.c c where c.clave = 'U1')$q$, (select s1 from f), 'authenticated'));
select pg_temp.caso('V todo número se abre tras V (sup1 y Gerencia)', 'cuadra|cuadra',
  pg_temp.valor('select pg_temp.cuadre()', (select s1 from f), 'authenticated') || '|' || pg_temp.valor('select pg_temp.cuadre()', (select g from f)));

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 300)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B10: hay casos FAIL'; end if; end $$;
rollback;
