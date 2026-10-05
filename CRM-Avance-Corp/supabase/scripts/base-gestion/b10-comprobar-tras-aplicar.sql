-- B10 · comprobación de COMPORTAMIENTO tras aplicar 20261004223253 (Bases cargadas: seguimiento, la base en la lista y el capital
-- al reactivar). La migración solo acredita el catálogo y la identidad de la lista; esto se corre DESPUÉS del commit: en el banco,
-- en la rama con datos y, si Miguel quiere, en producción con `!` (`supabase db query --linked --file`).
-- NO ESCRIBE NADA: una sola transacción que termina SIEMPRE en ROLLBACK, y el recorrido entero además en una subtransacción
-- deshecha (los resultados viajan en variables). Solo crea filas NUEVAS transitorias (una base, dos contactos con teléfonos que no
-- existen, sus recibos y la actividad de reactivarlos) y las deshace. lock_timeout corto: un candado ocupado cuenta como NOT RUN.
-- Casos (con una Gerencia, un supervisor con un analista activo directo y ese analista, reales; los claims sin SET ROLE):
--   C1 catálogo: 5 puertas nuevas DEFINER con EXECUTE solo authenticated; núcleos y ayudantes sin EXECUTE; las puertas publicadas
--      de reactivar y de intentos intactas; una sola sobrecarga; ninguna en el censo;
--   C2 identidad: la lista de Gerencia (con y sin vetados) = una COPIA EXACTA del cuerpo de B6b sin los dormidos sin repartir,
--      en filas y orden (con los datos de esta base);
--   P1 crear la base del supervisor y un lote de 2 (uno sin capital, otro con 2000); P2 seguimiento_bases del supervisor:
--      total 2, sin repartir 2; P3 ninguno sale en la lista del supervisor ni de Gerencia; P4 reparto SIMULADO (B9: vendedor
--      del lead y pertenencia) del sin capital al analista: sale en SU lista con base_nombre; P5 su fila en seguimiento_base:
--      1 asignado, 1 sin tocar, 0 en rojo, y cada cifra de la base y del analista = su detalle; P6 la puerta publicada sobre el
--      sin capital → 22023; P7 la _v2 sin capital → 22023; P8 la _v2 con 3500 → contactado con 3500 en el lead; P9 el analista
--      → seguimiento_bases 42501; P10 F4: el detalle de cada cifra del resumen de Gerencia = la cifra; P11 la puerta
--      seguimiento_bases como authenticated (NOT RUN si el rol de la sesión no puede pasar a authenticated, p. ej. la CLI);
--   P12 «agendó cita» por la puerta publicada de intentos sobre el sin capital → 22023; P13 por registrar_intento_base_v2 sin
--      capital → 22023; P14 un intento normal sobre el sin capital por la _v2 (capital ignorado) → intento 1, sigue sin capital;
--   P15 «agendó cita» por la _v2 con 2600 sobre el segundo contacto (que YA tiene 2000; repartido al analista) → reactiva y el
--      capital sigue en 2000 (se ignora); P16 (r1) el mismo id de operación de P8 con otro capital → 23505 «otro contenido».
--   r2: el reparto es el REAL de B9 (crm.repartir_base, individual); P17 la lista de B9 (crm.contactos_de_base) da el MISMO
--      estado que el seguimiento de B10 y su filtro «sin_repartir» = la cifra (2); P18 tras el reparto, el mismo estado
--      (sin_tocar) por las dos puertas. C1 exige además la definición única, el clasificador de B9 borrado y sus puertas intactas.
--   r4: C3 (y P20 tras cargar) TODO contacto que la lista de Gerencia oculta —la COPIA de B6b menos la lista nueva— es un dormido
--      del archivo de una base viva, sin analista ni vendedor, en la bandeja del supervisor DUEÑO; P19 dos contactos más que
--      Gerencia reparte a analistas FUERA del equipo del supervisor: el supervisor ve UNA sola fila anónima con los dos, la suma
--      de sus filas = la base, y abrir por el UUID de un externo da P0002 «Analista no encontrado en esta base»; Gerencia no tiene
--      fila anónima (NOT RUN si no hay analistas fuera de ese equipo).
-- El VEREDICTO viaja como FILA: B10_COMPORTAMIENTO_OK n/n · B10_COMPORTAMIENTO_PARCIAL (con los NOT RUN) ·
--   B10_COMPORTAMIENTO_FALLA (y además aborta). Sin B10 aplicada: todo NOT RUN.
begin;
set local lock_timeout = '2s';
set local statement_timeout = '60s';
set local search_path = '';
create temp table _b10_r (n serial, caso text, esperado text, obtenido text, estado text);

-- Copia EXACTA del cuerpo de B6b (20261004045038, md5 36af7e9c…): el oráculo de C2 (se borra con el ROLLBACK).
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

do $comprobar$
declare
  v_ger uuid;
  v_sup uuid;
  v_ana uuid;
  v_tel1 text;
  v_tel2 text;
  v_tel3 text;
  v_tel4 text;
  v_l3 uuid;
  v_l4 uuid;
  v_ext uuid[];
  v_k integer;
  v_res jsonb := '{}'::jsonb;  -- resultados del recorrido (sobreviven al deshacer la subtransacción)
  v_base uuid;
  v_nombre text := 'B10 comprobación ' || pg_catalog.to_char(pg_catalog.clock_timestamp(), 'YYYYMMDDHH24MISSUS');
  v_l1 uuid;
  v_l2 uuid;
  v_r text;
  v_op uuid := gen_random_uuid();
  v_j jsonb;
  v_i integer;
  v_n bigint;
  v_mal text[] := '{}';
  v_b record;
  v_a record;
  v_c text;
  c record;
begin
  if to_regprocedure('crm.seguimiento_bases()') is null or to_regprocedure('crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)') is null then
    insert into pg_temp._b10_r (caso, esperado, obtenido, estado) values ('precondición', 'B10 aplicada', 'B10 NO está aplicada', 'NOT RUN');
    return;
  end if;
  select e.perfil_id into v_ger from crm.equipo e where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  select e.supervisor_id, e.perfil_id into v_sup, v_ana from crm.equipo e
   where private.rol_crm(e.perfil_id) = 'vendedor' and private.rol_crm(e.supervisor_id) = 'supervisor' order by e.supervisor_id, e.perfil_id limit 1;
  for v_i in 1..40 loop
    v_tel1 := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel1))
          and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel1));
    v_tel1 := null;
  end loop;
  for v_i in 1..40 loop
    v_tel2 := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when v_tel2 is distinct from v_tel1 and not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel2))
          and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel2));
    v_tel2 := null;
  end loop;
  for v_i in 1..40 loop
    v_tel3 := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when v_tel3 is distinct from v_tel1 and v_tel3 is distinct from v_tel2
          and not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel3))
          and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel3));
    v_tel3 := null;
  end loop;
  for v_i in 1..40 loop
    v_tel4 := '9' || pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 100000000))::bigint::text, 8, '0');
    exit when v_tel4 is distinct from v_tel1 and v_tel4 is distinct from v_tel2 and v_tel4 is distinct from v_tel3
          and not exists (select 1 from crm.leads l where l.telefono = private.normalizar_telefono(v_tel4))
          and not exists (select 1 from public.perfiles p where private.normalizar_telefono(p.telefono) = private.normalizar_telefono(v_tel4));
    v_tel4 := null;
  end loop;
  if v_ger is null or v_sup is null or v_ana is null or v_tel1 is null or v_tel2 is null then
    insert into pg_temp._b10_r (caso, esperado, obtenido, estado)
    values ('precondición', 'una Gerencia, un supervisor con un analista activo y dos teléfonos libres',
            pg_catalog.format('gerencia %s · supervisor %s · analista %s · teléfonos %s %s', v_ger, v_sup, v_ana, v_tel1, v_tel2), 'NOT RUN');
    return;
  end if;

  -- C1 · catálogo.
  v_res := v_res || pg_catalog.jsonb_build_object('C1', (
    (select pg_catalog.count(*) from pg_catalog.pg_proc p
      where p.oid in ('crm.seguimiento_bases()'::regprocedure, 'crm.seguimiento_base(uuid)'::regprocedure, 'crm.seguimiento_base_detalle(uuid,uuid,text)'::regprocedure,
                      'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)'::regprocedure, 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamptz,numeric,text)'::regprocedure)
        and p.prosecdef and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}' and p.proconfig = array['search_path=""']::text[]) = 5
    and not exists (select 1 from pg_catalog.pg_proc p cross join pg_catalog.unnest(array['anon', 'authenticated', 'service_role']) r(rol)
                     where p.pronamespace = 'private'::regnamespace
                       and (p.proname like 'bases\_carga\_seguimiento\_%' or p.proname in ('bases_carga_estado_contacto', 'bases_carga_reparto_motivo_bloque',
                                                                                      'bases_carga_contactos_core', 'bases_carga_reparto_recogible',
                                                                                      'bases_carga_repartir_core', 'base_gestion_reactivar_core',
                                                                                      'base_gestion_reactivar_capital_core', 'base_gestion_intento_core',
                                                                                      'base_gestion_intento_capital_core'))
                       and pg_catalog.has_function_privilege(r.rol, p.oid, 'EXECUTE'))
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'crm.reactivar_lead_base(uuid,uuid,text)'::regprocedure) = 'bf59d77929877e7a5eb46704d934363e'
    -- r2: la definición única existe, el clasificador de B9 no, y las tres puertas de B9 conservan su cuerpo.
    and to_regprocedure('private.bases_carga_estado_contacto(uuid,boolean,boolean,text,uuid,uuid,date,uuid,timestamptz,timestamptz,uuid,uuid[],date,boolean,boolean,boolean)') is not null
    and to_regprocedure('private.bases_carga_reparto_estado(boolean,boolean,text,uuid,boolean,date,uuid,boolean,boolean,boolean,boolean,date)') is null
    and (select pg_catalog.string_agg(pg_catalog.md5(p.prosrc), ',' order by p.proname) from pg_catalog.pg_proc p
          where p.oid in ('crm.contactos_de_base(uuid,text)'::regprocedure, 'crm.recoger_de_base(uuid,uuid,uuid)'::regprocedure, 'crm.repartir_base(uuid,uuid,jsonb)'::regprocedure))
        = 'd528bab6930698d160f9635417a3ca7a,4744f70e69c0f70c22a6a295184e3095,fd7531ba7cd7cf8a259a389e2895ee2e'
    and (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = 'crm.registrar_intento_base(uuid,uuid,text,text,timestamp with time zone)'::regprocedure) = 'd92c791fbe6f84e5d4f8ca39357b4721'
    and (select pg_catalog.count(*) from pg_catalog.pg_proc p where p.pronamespace in ('crm'::regnamespace, 'private'::regnamespace)
          and p.proname in ('obtener_base_gestion', 'reactivar_lead_base', 'reactivar_lead_base_v2', 'base_gestion_reactivar_core',
                            'base_gestion_reactivar_capital_core', 'seguimiento_bases', 'seguimiento_base', 'seguimiento_base_detalle',
                            'registrar_intento_base', 'registrar_intento_base_v2', 'base_gestion_intento_core', 'base_gestion_intento_capital_core')) = 12
    and not exists (select 1 from private.contadores_crudos_leads_citas() x
                     where x.objeto in ('crm.obtener_base_gestion(uuid,boolean)', 'crm.seguimiento_bases()', 'crm.seguimiento_base(uuid)', 'crm.seguimiento_base_detalle(uuid,uuid,text)',
                                        'private.bases_carga_seguimiento_filas(uuid[],date)', 'crm.reactivar_lead_base_v2(uuid,uuid,text,numeric,text)',
                                        'private.base_gestion_reactivar_capital_core(uuid,uuid,uuid,text,numeric,text)',
                                        'private.base_gestion_reactivar_core(uuid,uuid,uuid,text)', 'crm.registrar_intento_base_v2(uuid,uuid,text,text,timestamp with time zone,numeric,text)',
                                        'private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text)')))::text);

  -- C2 · identidad con la copia de B6b, como Gerencia (sin escribir nada).
  perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
  v_res := v_res || pg_catalog.jsonb_build_object('C2', (not exists (
    with excl as (
      -- los dormidos del ARCHIVO sin repartir (disponibles), escrito aparte de la definición única (r1; r2: en el ámbito del
      -- dueño y sin descanso; r3: solo procedencia archivo, un armado nunca se oculta).
      select l.id from crm.leads l
        join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo and bl.procedencia = 'archivo'
        join crm.bases_carga b on b.id = bl.base_id and b.activo
       where bl.analista_id is null and l.activo and not l.no_contactar and l.etapa = 'descartado' and l.vendedor_id is null
         and (l.enfriado_hasta is null or l.enfriado_hasta <= (pg_catalog.now() at time zone 'America/Lima')::date)
         and l.asignado_supervisor_id in (select private.bases_carga_subarbol(b.supervisor_id))
         and (l.asignado_supervisor_id = b.supervisor_id
              or not exists (select 1 from crm.actividades a where a.lead_id = l.id and a.tipo = 'reasignacion' and a.creado_en >= bl.creado_en))
    ),
    esperado as (
      select m.modo, pg_catalog.row_number() over (partition by m.modo order by t.ordinality) as ord,
             row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte,
                 t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en,
                 t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en, t.no_contactar, t.no_contactar_en,
                 t.no_contactar_motivo, t.no_contactar_por)::text as fila
        from (values (false), (true)) m(modo) cross join lateral pg_temp.b6b_obtener(null, m.modo) with ordinality t
       where t.lead_id not in (select x.id from excl x)
    ),
    obtenido as (
      select m.modo, t.ordinality as ord,
             row(t.lead_id, t.nombre_completo, t.telefono, t.distrito, t.origen, t.categoria_interes, t.monto_estimado, t.moneda, t.motivo_descarte,
                 t.descartado_en, t.dias_desde_descarte, t.etapa_maxima, t.intentos, t.ultimo_resultado, t.ultimo_intento_en, t.proxima_llamada_en,
                 t.rellamada_hoy, t.enfriado_hasta, t.ciclo_n, t.vendedor_id, t.gestiona, t.recibido_en, t.no_contactar, t.no_contactar_en,
                 t.no_contactar_motivo, t.no_contactar_por)::text as fila
        from (values (false), (true)) m(modo) cross join lateral crm.obtener_base_gestion(null, m.modo) with ordinality t
    )
    (select * from esperado except all select * from obtenido) union all (select * from obtenido except all select * from esperado)))::text
    || '|' || (select pg_catalog.count(*) from crm.obtener_base_gestion(null, true))::text);
  -- C3 · r4: TODO contacto oculto (copia de B6b menos la lista nueva, como Gerencia) es un dormido del archivo en la bandeja del dueño.
  v_res := v_res || pg_catalog.jsonb_build_object('C3', (not exists (
    select 1 from pg_temp.b6b_obtener(null, true) t
      join crm.leads l on l.id = t.lead_id
      left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo
      left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
     where t.lead_id not in (select o.lead_id from crm.obtener_base_gestion(null, true) o)
       and (bc.id is not null and bl.procedencia = 'archivo' and bl.analista_id is null and l.vendedor_id is null
            and l.asignado_supervisor_id is not distinct from bc.supervisor_id) is not true))::text);

  -- El recorrido con escrituras, en una subtransacción que se deshace.
  begin
    -- P1 · la base y el lote, como el supervisor.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    v_base := (crm.crear_base(gen_random_uuid(), v_nombre, 'archivo', null, 'b10-comprobar.csv') ->> 'base_id')::uuid;
    v_res := v_res || pg_catalog.jsonb_build_object('P1', crm.cargar_base_lote(gen_random_uuid(), v_base,
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('fila', 1, 'nombre', 'B10 Comprobar sin capital', 'telefono', v_tel1),
                                   pg_catalog.jsonb_build_object('fila', 2, 'nombre', 'B10 Comprobar con capital', 'telefono', v_tel2, 'capital', '2000'))) -> 'lote' ->> 'cargadas');
    v_l1 := (select l.id from crm.leads l where l.telefono = private.normalizar_telefono(v_tel1));
    v_l2 := (select l.id from crm.leads l where l.telefono = private.normalizar_telefono(v_tel2));
    -- P2 · seguimiento_bases del supervisor.
    v_res := v_res || pg_catalog.jsonb_build_object('P2', (select pg_catalog.format('%s/%s/%s', s.total, s.sin_repartir, s.repartidos) from crm.seguimiento_bases() s where s.base_id = v_base));
    -- P17 · r2: la lista de B9 = el seguimiento de B10 (mismo estado; filtro sin_repartir = la cifra).
    v_res := v_res || pg_catalog.jsonb_build_object('P17',
      (select pg_catalog.count(*) from crm.contactos_de_base(v_base, 'sin_repartir'))::text || '|'
      || case when not exists (select 1 from crm.contactos_de_base(v_base, 'todos') x
                                left join crm.seguimiento_base_detalle(v_base, null, 'total') d on d.lead_id = x.lead_id
                               where x.estado is distinct from d.estado)
              then 'igual' else 'distinto' end);
    -- P3 · fuera de la lista del supervisor y de Gerencia.
    v_res := v_res || pg_catalog.jsonb_build_object('P3', (select pg_catalog.count(*) from crm.obtener_base_gestion(null, true) g where g.lead_id in (v_l1, v_l2))::text);
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    v_res := v_res || pg_catalog.jsonb_build_object('P3', (v_res ->> 'P3') || '|' || (select pg_catalog.count(*) from crm.obtener_base_gestion(null, true) g where g.lead_id in (v_l1, v_l2))::text);
    -- P20 · r4: como Gerencia, los 2 dormidos recién cargados están ocultos y TODO lo oculto cumple la regla de C3.
    v_res := v_res || pg_catalog.jsonb_build_object('P20',
      (select pg_catalog.count(*) from (values (v_l1), (v_l2)) x(id) where x.id not in (select o.lead_id from crm.obtener_base_gestion(null, true) o))::text
      || '|' || (not exists (
        select 1 from pg_temp.b6b_obtener(null, true) t
          join crm.leads l on l.id = t.lead_id
          left join crm.base_carga_leads bl on bl.lead_id = l.id and bl.activo
          left join crm.bases_carga bc on bc.id = bl.base_id and bc.activo
         where t.lead_id not in (select o.lead_id from crm.obtener_base_gestion(null, true) o)
           and (bc.id is not null and bl.procedencia = 'archivo' and bl.analista_id is null and l.vendedor_id is null
                and l.asignado_supervisor_id is not distinct from bc.supervisor_id) is not true))::text);
    -- P4 · reparto REAL de B9 (crm.repartir_base, individual), con el supervisor como actor.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    v_j := crm.repartir_base(gen_random_uuid(), v_base, pg_catalog.jsonb_build_object('modo', 'individual', 'asignaciones',
             pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('lead_id', v_l1, 'analista_id', v_ana))));
    -- P18 · r2: tras el reparto, el mismo estado por las dos puertas.
    v_res := v_res || pg_catalog.jsonb_build_object('P18',
      (v_j ->> 'repartidos') || '|' || coalesce((select x.estado from crm.contactos_de_base(v_base, 'todos') x where x.lead_id = v_l1), '(sin fila)')
      || '|' || coalesce((select d.estado from crm.seguimiento_base_detalle(v_base, null, 'total') d where d.lead_id = v_l1), '(sin fila)'));
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ana::text, true);
    v_res := v_res || pg_catalog.jsonb_build_object('P4', coalesce((select g.base_nombre = v_nombre and g.base_id = v_base from crm.obtener_base_gestion() g where g.lead_id = v_l1), false)::text);
    -- P9 · el analista no ve el seguimiento.
    begin
      perform 1 from crm.seguimiento_bases();
      v_res := v_res || pg_catalog.jsonb_build_object('P9', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P9', sqlstate || ' ' || sqlerrm);
    end;
    -- P6 · la puerta publicada sobre el sin capital → 22023.
    begin
      perform crm.reactivar_lead_base(gen_random_uuid(), v_l1);
      v_res := v_res || pg_catalog.jsonb_build_object('P6', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P6', sqlstate || ' ' || sqlerrm);
    end;
    -- P5 · su fila y cada cifra = su detalle (como el supervisor).
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    v_r := (select pg_catalog.format('%s/%s/%s', s.asignados, s.sin_tocar, s.sin_tocar_3_dias) from crm.seguimiento_base(v_base) s where s.analista_id = v_ana);
    for v_b in select s.* from crm.seguimiento_bases() s where s.base_id = v_base loop
      foreach v_c in array array['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'en_descanso', 'citas', 'reactivados'] loop
        select pg_catalog.count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, null, v_c);
        if v_n is distinct from (pg_catalog.to_jsonb(v_b) ->> v_c)::bigint then v_mal := v_mal || v_c; end if;
      end loop;
      for v_a in select s.* from crm.seguimiento_base(v_b.base_id) s loop
        foreach v_c in array array['asignados', 'sin_tocar', 'sin_tocar_3_dias', 'trabajados', 'en_descanso', 'citas', 'reactivados', 'movidos_otra_via'] loop
          select pg_catalog.count(*) into v_n from crm.seguimiento_base_detalle(v_b.base_id, v_a.analista_id, v_c);
          if v_n is distinct from (pg_catalog.to_jsonb(v_a) ->> v_c)::bigint then v_mal := v_mal || ('analista/' || v_c); end if;
        end loop;
      end loop;
    end loop;
    v_res := v_res || pg_catalog.jsonb_build_object('P5', coalesce(v_r, 'sin fila') || '|' || coalesce(nullif(pg_catalog.array_to_string(v_mal, ','), ''), 'cuadra'));
    -- P7 y P8 · la _v2, como el analista. Antes, P12–P14: «agendó cita» y un intento normal sobre el sin capital.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ana::text, true);
    begin
      perform crm.registrar_intento_base(gen_random_uuid(), v_l1, 'agendo_reunion');
      v_res := v_res || pg_catalog.jsonb_build_object('P12', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P12', sqlstate || ' ' || sqlerrm);
    end;
    begin
      perform crm.registrar_intento_base_v2(gen_random_uuid(), v_l1, 'agendo_reunion');
      v_res := v_res || pg_catalog.jsonb_build_object('P13', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P13', sqlstate || ' ' || sqlerrm);
    end;
    v_r := crm.registrar_intento_base_v2(gen_random_uuid(), v_l1, 'no_contesto', null, null, 999) ->> 'intento_n';
    v_res := v_res || pg_catalog.jsonb_build_object('P14', v_r || '|' || (select coalesce(l.monto_estimado::text, 'sin capital') || '|' || l.etapa from crm.leads l where l.id = v_l1));
    begin
      perform crm.reactivar_lead_base_v2(gen_random_uuid(), v_l1);
      v_res := v_res || pg_catalog.jsonb_build_object('P7', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P7', sqlstate || ' ' || sqlerrm);
    end;
    v_j := crm.reactivar_lead_base_v2(v_op, v_l1, 'B10 comprobación', 3500);
    v_res := v_res || pg_catalog.jsonb_build_object('P8', (v_j ->> 'etapa') || '|' || (select l.monto_estimado::text || '|' || l.etapa from crm.leads l where l.id = v_l1)
                                                       || '|' || (v_j ->> 'monto_estimado'));
    -- P16 · r1: el mismo id con otro capital → 23505 «otro contenido».
    begin
      perform crm.reactivar_lead_base_v2(v_op, v_l1, 'B10 comprobación', 3600);
      v_res := v_res || pg_catalog.jsonb_build_object('P16', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P16', sqlstate || ' ' || sqlerrm);
    end;
    -- P15 · el segundo contacto (con 2000) repartido al analista; «agendó cita» por la _v2 con 2600 → reactiva, capital 2000.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    perform crm.repartir_base(gen_random_uuid(), v_base, pg_catalog.jsonb_build_object('modo', 'individual', 'asignaciones',
              pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('lead_id', v_l2, 'analista_id', v_ana))));
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ana, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ana::text, true);
    v_r := crm.registrar_intento_base_v2(gen_random_uuid(), v_l2, 'agendo_reunion', 'B10 comprobación', null, 2600) ->> 'reactivado';
    v_res := v_res || pg_catalog.jsonb_build_object('P15', v_r || '|' || (select l.monto_estimado::text || '|' || l.etapa from crm.leads l where l.id = v_l2));
    -- P19 · r4 (Codex r2): dos contactos más, que Gerencia reparte a analistas FUERA del equipo del supervisor.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
    v_ext := array(select e.perfil_id from crm.equipo e
                    where e.activo and private.rol_crm(e.perfil_id) = 'vendedor' and private.es_destino_crm_activo(e.perfil_id, array['vendedor']::text[])
                      and e.perfil_id not in (select private.vendedor_ids_visibles(v_sup))
                    order by e.perfil_id limit 2);
    v_k := pg_catalog.cardinality(v_ext);
    if coalesce(v_k, 0) = 0 or v_tel3 is null or v_tel4 is null then
      v_res := v_res || pg_catalog.jsonb_build_object('P19', 'NOT RUN: sin analistas activos fuera del equipo del supervisor o sin teléfonos libres');
    else
      perform crm.cargar_base_lote(gen_random_uuid(), v_base,
        pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('fila', 1, 'nombre', 'B10 Comprobar externo uno', 'telefono', v_tel3),
                                     pg_catalog.jsonb_build_object('fila', 2, 'nombre', 'B10 Comprobar externo dos', 'telefono', v_tel4)));
      v_l3 := (select l.id from crm.leads l where l.telefono = private.normalizar_telefono(v_tel3));
      v_l4 := (select l.id from crm.leads l where l.telefono = private.normalizar_telefono(v_tel4));
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      perform crm.repartir_base(gen_random_uuid(), v_base, pg_catalog.jsonb_build_object('modo', 'individual', 'asignaciones',
                pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('lead_id', v_l3, 'analista_id', v_ext[1]),
                                             pg_catalog.jsonb_build_object('lead_id', v_l4, 'analista_id', v_ext[v_k]))));
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_sup, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_sup::text, true);
      v_r := (select pg_catalog.count(*) filter (where s.analista_id is null)::text
                     || '|' || coalesce(sum(s.asignados) filter (where s.analista_id is null), 0)::text
                     || '|' || (sum(s.asignados) = (select sb.repartidos from crm.seguimiento_bases() sb where sb.base_id = v_base))::text
                from crm.seguimiento_base(v_base) s);
      begin
        perform 1 from crm.seguimiento_base_detalle(v_base, v_ext[1], 'asignados');
        v_r := v_r || '|pasó';
      exception when others then
        v_r := v_r || '|' || sqlstate || ' ' || sqlerrm;
      end;
      perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
      perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
      v_r := v_r || '|' || (select pg_catalog.count(*) filter (where s.analista_id is null) from crm.seguimiento_base(v_base) s)::text;
      v_res := v_res || pg_catalog.jsonb_build_object('P19', v_r);
    end if;
    -- P10 · F4 como Gerencia.
    perform pg_catalog.set_config('request.jwt.claims', pg_catalog.json_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', v_ger::text, true);
    v_mal := '{}';
    for c in select x.* from crm.base_gestion_resumen() x loop
      if (select pg_catalog.count(*) from crm.base_gestion_resumen_detalle(c.vendedor_id, 'intentos_hoy')) <> c.intentos_hoy
         or (select pg_catalog.count(*) from crm.base_gestion_resumen_detalle(c.vendedor_id, 'reactivaciones_mes')) <> c.reactivaciones_mes then
        v_mal := v_mal || c.vendedor_id::text;
      end if;
    end loop;
    v_res := v_res || pg_catalog.jsonb_build_object('P10', coalesce(nullif(pg_catalog.array_to_string(v_mal, ','), ''), 'cuadra'));
    -- P11 · la puerta como authenticated (la ruta real de PostgREST).
    begin
      set local role authenticated;
      perform 1 from crm.seguimiento_bases();
      reset role;
      v_res := v_res || pg_catalog.jsonb_build_object('P11', 'pasó');
    exception when others then
      v_res := v_res || pg_catalog.jsonb_build_object('P11', sqlstate || ' ' || sqlerrm);
    end;
    raise exception using errcode = 'P0001', message = 'B10_DESHACER';
  exception when others then
    if sqlerrm <> 'B10_DESHACER' then
      v_res := v_res || pg_catalog.jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
    end if;
  end;
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  perform pg_catalog.set_config('request.jwt.claim.sub', '', true);

  for c in select * from (values
      (1, 'C1', 'C1 catálogo: 5 puertas DEFINER solo authenticated, núcleos cerrados, puertas publicadas intactas, sobrecargas, censo', 'true'),
      (2, 'C2', 'C2 la lista de Gerencia = copia de B6b sin los dormidos sin repartir (con y sin vetados); filas con vetados', 'true|' || coalesce((v_res ->> 'C2'), '|?')),
      (3, 'P1', 'P1 la base del supervisor y un lote de 2', '2'),
      (4, 'P2', 'P2 seguimiento_bases: total 2, sin repartir 2, repartidos 0', '2/2/0'),
      (5, 'P3', 'P3 los dormidos sin repartir no salen en la lista del supervisor ni de Gerencia', '0|0'),
      (6, 'P4', 'P4 el analista ve su contacto repartido con base_id y base_nombre', 'true'),
      (7, 'P5', 'P5 el analista: 1 asignado, 1 sin tocar, 0 en rojo; cada cifra = su detalle', '1/1/0|cuadra'),
      (8, 'P6', 'P6 la puerta publicada sobre un lead sin capital → 22023', '22023 Indica el capital estimado para reactivar'),
      (9, 'P7', 'P7 la _v2 sin capital → 22023', '22023 Indica el capital estimado para reactivar'),
      (10, 'P8', 'P8 la _v2 con 3500 → contactado, con el capital en el lead y en la respuesta (r1)', 'contactado|3500|contactado|3500'),
      (11, 'P9', 'P9 el analista → seguimiento_bases 42501', '42501 Solo Supervisión y Gerencia ven el seguimiento de las bases'),
      (12, 'P10', 'P10 F4: el detalle de cada cifra del resumen de Gerencia = la cifra', 'cuadra'),
      (13, 'P11', 'P11 seguimiento_bases como authenticated', 'pasó'),
      (14, 'P12', 'P12 «agendó cita» por la puerta publicada de intentos sobre un lead sin capital → 22023', '22023 Indica el capital estimado para reactivar'),
      (15, 'P13', 'P13 «agendó cita» por registrar_intento_base_v2 sin capital → 22023', '22023 Indica el capital estimado para reactivar'),
      (16, 'P14', 'P14 un intento normal sobre el sin capital por la _v2 (capital ignorado): intento 1, sigue sin capital y descartado', '1|sin capital|descartado'),
      (17, 'P15', 'P15 «agendó cita» por la _v2 sobre un lead con 2000: reactiva y conserva 2000', 'true|2000|contactado'),
      (18, 'P16', 'P16 r1: el mismo id de operación con otro capital → 23505', '23505 Esta operacion ya corresponde a otro contenido'),
      (19, 'P17', 'P17 r2: la lista de B9 da el mismo estado que el seguimiento y su filtro sin_repartir = la cifra (2)', '2|igual'),
      (20, 'P18', 'P18 r2: tras el reparto REAL de B9, sin_tocar por las dos puertas', '1|sin_tocar|sin_tocar'),
      (21, 'C3', 'C3 r4: todo lo que la lista oculta es un dormido del archivo sin analista en la bandeja del dueño', 'true'),
      (22, 'P20', 'P20 r4: los 2 dormidos cargados están ocultos y todo lo oculto cumple la regla de C3', '2|true'),
      (23, 'P19', 'P19 r4: el supervisor ve UNA fila anónima con los 2 externos, la suma = la base, el UUID externo → P0002; Gerencia, ninguna anónima', '1|2|true|P0002 Analista no encontrado en esta base|0')) x(k, clave, caso, esperado) loop
    v_r := coalesce(v_res ->> c.clave, 'sin resultado: ' || coalesce(v_res ->> 'error', '(nada)'));
    if c.clave = 'C2' then
      c.esperado := 'true|' || pg_catalog.split_part(v_r, '|', 2);
    end if;
    insert into pg_temp._b10_r (caso, esperado, obtenido, estado)
    values (c.caso, c.esperado, v_r,
            case when v_r = c.esperado then 'PASS'
                 when v_r like '55P03 %' or coalesce(v_res ->> 'error', '') like '55P03 %' then 'NOT RUN'
                 when c.k = 13 and v_r like '42501 permission denied to set role%' then 'NOT RUN'
                 when c.k = 23 and v_r like 'NOT RUN%' then 'NOT RUN'
                 else 'FAIL' end);
  end loop;
end;
$comprobar$;

-- Detalle (para psql) y, al final, el veredicto en UNA fila.
select format('%s %s · esperado %s · obtenido %s', r.estado, r.caso, r.esperado, left(r.obtenido, 200)) from pg_temp._b10_r r order by r.n;
select case
         when count(*) filter (where r.estado = 'FAIL') > 0 then
           'B10_COMPORTAMIENTO_FALLA: ' || string_agg(r.caso || ' → ' || left(r.obtenido, 120), ' | ' order by r.n) filter (where r.estado = 'FAIL')
         when count(*) filter (where r.estado = 'NOT RUN') > 0 then
           format('B10_COMPORTAMIENTO_PARCIAL: %s PASS · NOT RUN: %s', count(*) filter (where r.estado = 'PASS'),
                  string_agg(r.caso || ' (' || left(r.obtenido, 100) || ')', ' | ' order by r.n) filter (where r.estado = 'NOT RUN'))
         else format('B10_COMPORTAMIENTO_OK %s/%s', count(*), count(*))
       end as veredicto
  from pg_temp._b10_r r;
do $falla$
begin
  if exists (select 1 from pg_temp._b10_r where estado = 'FAIL') then
    raise exception 'B10: la comprobacion de comportamiento FALLA (ver el veredicto)';
  end if;
end;
$falla$;
rollback;
