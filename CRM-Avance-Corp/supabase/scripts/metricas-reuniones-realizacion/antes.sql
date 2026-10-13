-- MONTAJE del ensayo de «"Realización" cuenta la cita realizada desde que se marca» — se ejecuta en el LABORATORIO
-- (banco Docker local), NUNCA contra producción, y no escribe nada: todo vive en la transacción que `armar-ensayo.mjs`
-- abre y termina en `rollback`.
--
-- Va DELANTE de la migración (y en `--sin-migracion`, delante del oráculo a secas) porque hace tres cosas que tienen que
-- ocurrir ANTES de reemplazar la función:
--   1. Crea los auxiliares temporales que usa el oráculo (`pruebas.sql`): sesión, registro de fallos, siembra, lectura.
--   2. Elige los actores reales del banco (una Gerencia y tres vendedores sin citas en las ventanas medidas) y los deja
--      en variables de la transacción. Son OBLIGATORIOS: si faltan, el ensayo aborta en vez de salir verde sin mirar nada.
--   3. Siembra un PERIODO YA PASADO (el mes anterior, con una cita de cada estado y todas con la hora vencida) y guarda
--      la respuesta de la puerta para ese periodo. El oráculo la vuelve a pedir DESPUÉS de la migración: tiene que ser
--      idéntica (caso 3 del encargo: los periodos pasados no cambian).
--
-- Cómo se siembra. Las citas se insertan ya en su estado final (completada, no_show, cancelada por el asesor o por el
-- sistema, reprogramada, pendiente) con los triggers de `crm.tareas` y `crm.leads` apagados (`set local
-- session_replication_role = replica`, que en este laboratorio sí puede ejecutar `postgres`): el candado BEFORE UPDATE
-- exige que todo cierre venga por una RPC de agenda y el BEFORE INSERT vuelve «sistema» toda cancelación. Lo que se mide
-- aquí es cómo la métrica LEE la tabla (`private.citas_episodios` sobre `crm.tareas`), no el camino de escritura, que ya
-- cubre el ensayo del bloque 2.1 (`no-asistio-espera-hora/`). Los CHECK de la tabla siguen activos: cada fila respeta la
-- forma real (motivo, modalidad, ubicación, quién canceló).
--
-- Quién llama: la puerta `crm.metricas_reuniones_fn` como la Gerencia del banco, con la identidad en las DOS formas de los
-- claims (`request.jwt.claim.sub` y `request.jwt.claims`). NO se usa `set role` (llamar bajo `set role` a una función sin
-- EXECUTE tumba el Postgres del banco): la ficha y la ACL se leen del catálogo (caso 8 del oráculo).

set local statement_timeout = '120s';

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
  if p_txt = '' then
    perform set_config('ensayo.oks', coalesce(current_setting('ensayo.oks', true), '') || 'ok ' || p_caso || E'\n', true);
  else
    perform set_config('ensayo.fallos',
      (coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer + 1)::text, true);
    perform set_config('ensayo.informe', coalesce(current_setting('ensayo.informe', true), '') || p_txt, true);
  end if;
end;
$f$;

-- Exige una condición: si no se cumple, registra «FALLO <caso>: <detalle>» (el prefijo literal es lo que juzga mutantes.sh).
create function pg_temp.exigir(p_caso text, p_ok boolean, p_detalle text) returns void language plpgsql as $f$
begin
  if coalesce(p_ok, false) then
    perform pg_temp.reg(p_caso, '');
  else
    perform pg_temp.reg(p_caso, format(E'FALLO %s: %s\n', p_caso, p_detalle));
  end if;
end;
$f$;

create function pg_temp.medir(p_txt text) returns void language sql as $$
  select set_config('ensayo.medidas', coalesce(current_setting('ensayo.medidas', true), '') || p_txt || E'\n', true);
$$;

-- Un lead del ensayo, dueño el vendedor, con un origen elegido (los cortes por origen lo necesitan). Teléfono aleatorio
-- con la forma del CHECK; `uq_leads_telefono_vivo` lo exige único entre los vivos.
create function pg_temp.lead(p_vendedor uuid, p_origen text, p_nombre text) returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into crm.leads (nombre_completo, telefono, origen, etapa, monto_estimado, moneda, vendedor_id, activo)
  values (p_nombre, '+519' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
          p_origen, 'reunion_agendada', 1000.00, 'PEN', p_vendedor, true)
  returning id into v_id;
  return v_id;
end;
$f$;

-- Una cita (tarea de tipo reunión) ya en su estado final, con la forma que exigen los CHECK de `crm.tareas`:
--   completada   → resultado_reunion 'interesado'
--   no_show      → motivo 'cliente_no_asistio'
--   cancelada    → motivo 'cancelada_cliente'; cancelada_por 'asesor' (con cancelada_por_id: el propio vendedor u otro) o 'sistema'
--   reprogramada → motivo 'reprogramada'
--   pendiente    → sin resultado ni motivo
--   presencial   → con ubicación
create function pg_temp.cita(p_lead uuid, p_vendedor uuid, p_titulo text, p_vence timestamptz, p_estado text,
                             p_modalidad text default 'virtual', p_cancelada_por text default null,
                             p_cancelada_por_id uuid default null)
returns uuid language plpgsql as $f$
declare
  v_id uuid;
  v_quien text := case when p_estado = 'cancelada' then coalesce(p_cancelada_por, 'asesor') end;
begin
  insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, estado, modalidad_reunion, ubicacion_reunion,
                          resultado_reunion, motivo_no_realizada, cancelada_por, cancelada_por_id, activo, creado_por)
  values (p_lead, p_vendedor, 'reunion', p_titulo, p_vence, p_estado, p_modalidad,
          case when p_modalidad = 'presencial' then 'Oficina (ensayo)' end,
          case when p_estado = 'completada' then 'interesado' end,
          case p_estado when 'no_show' then 'cliente_no_asistio' when 'cancelada' then 'cancelada_cliente'
                        when 'reprogramada' then 'reprogramada' end,
          v_quien,
          case when v_quien = 'asesor' then coalesce(p_cancelada_por_id, p_vendedor) end,
          true, p_vendedor)
  returning id into v_id;
  return v_id;
end;
$f$;

-- La respuesta de la puerta (lo mismo que recibe la pantalla), como la Gerencia del banco, sin `generado_en`.
create function pg_temp.payload(p_gerencia uuid, p_desde date, p_hasta date) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_gerencia);
  v := crm.metricas_reuniones_fn(p_desde, p_hasta);
  perform pg_temp.sesion(null);
  return v - 'generado_en';
end;
$f$;

-- Una fila de un corte (`modalidades`, `origenes`, `responsables`) por su clave; null si no está.
create function pg_temp.fila(p_payload jsonb, p_grupo text, p_clave text, p_valor text) returns jsonb language sql as $$
  select x from jsonb_array_elements(coalesce(p_payload -> p_grupo, '[]'::jsonb)) x where x ->> p_clave = p_valor limit 1;
$$;

-- Diferencia de un contador entre dos filas (una fila ausente cuenta como cero).
create function pg_temp.d(p_despues jsonb, p_antes jsonb, p_campo text) returns numeric language sql as $$
  select coalesce((p_despues ->> p_campo)::numeric, 0) - coalesce((p_antes ->> p_campo)::numeric, 0);
$$;

-- Un contador de una fila (una fila ausente, o un campo ausente, cuenta como cero: así un «no está» se nota como un 0 inesperado).
create function pg_temp.n(p_fila jsonb, p_campo text) returns numeric language sql as $$
  select coalesce((p_fila ->> p_campo)::numeric, 0);
$$;

-- Un porcentaje de una fila: null se conserva (la pantalla pinta «—»).
create function pg_temp.pct(p_fila jsonb, p_campo text) returns numeric language sql as $$
  select (p_fila ->> p_campo)::numeric;
$$;

-- Resumen legible de una fila de corte o del resumen, para los mensajes de fallo.
create function pg_temp.txt(p_fila jsonb) returns text language sql as $$
  select coalesce((select string_agg(k || '=' || coalesce(v, 'null'), ' ' order by k)
                     from jsonb_each_text(p_fila) e(k, v)
                    where k in ('pactadas','debieron_ocurrir','realizadas','no_show','canceladas','canceladas_sistema',
                                'reprogramadas','canceladas_sistema_vencidas','canceladas_ajenas_vencidas',
                                'reprogramadas_vencidas','divisor_realizacion','divisor_asistencia','pendientes_cierre',
                                'programadas_futuras','pct_realizacion')), '(fila ausente)');
$$;

do $montaje$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_mes_pasado date := (date_trunc('month', (now() at time zone 'America/Lima')::date) - interval '1 month')::date;
  v_fin_mes_pasado date := (date_trunc('month', (now() at time zone 'America/Lima')::date) - interval '1 day')::date;
  v_gerencia uuid;
  v_vendedores uuid[];
  v_lead uuid;
  v_ts timestamptz;
  v_pasado jsonb;
  v_neutralizadas integer;
  v_futuras integer;
begin
  -- ── Actores reales del banco (OBLIGATORIOS) ───────────────────────────────────────────────────────────────────────
  -- La Gerencia que consulta: fila activa en el equipo con rol gerencia y rol efectivo gerencia (`private.rol_crm`).
  select e.perfil_id into v_gerencia
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'gerencia' and private.rol_crm(e.perfil_id) = 'gerencia'
  order by p.nombre_completo, e.perfil_id limit 1;
  -- Tres vendedores efectivos (rol del Portal comercial, supervisor efectivo) SIN ninguna reunión desde el inicio del mes
  -- pasado: así sus filas del corte por responsable son enteramente del ensayo y se comprueban en absoluto. Se prefieren los
  -- que no tienen ninguna; si el laboratorio no tiene tres así, se completan con los de MENOS reuniones, y esas reuniones se
  -- NEUTRALIZAN más abajo dentro de esta transacción (F4.2, 09/10/2026: el banco corrido sobre el laboratorio igual a
  -- producción dejó una reunión de hoy a `PASO08 VEND3`, uno de los tres actores de la fase 2, y el montaje abortaba con
  -- «faltan actores … =2»). En el laboratorio de la fase 2 los tres no tenían ninguna: el resultado es el mismo.
  select array_agg(perfil_id order by nombre, perfil_id) into v_vendedores
  from (
    select e.perfil_id, p.nombre_completo as nombre
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and p.rol = 'comercial'
      and private.rol_crm(e.perfil_id) = 'vendedor' and private.rol_crm(e.supervisor_id) = 'supervisor'
    order by (select count(*) from crm.tareas t
               where t.vendedor_id = e.perfil_id and t.tipo = 'reunion' and t.activo
                 and t.vence_en >= (v_mes_pasado::timestamp at time zone 'America/Lima')),
             p.nombre_completo, e.perfil_id
    limit 3
  ) s;
  if v_gerencia is null or coalesce(cardinality(v_vendedores), 0) < 3 then
    raise exception 'ENSAYO ABORTADO: faltan actores (gerencia=%, vendedores sin citas desde el mes pasado=%)',
      v_gerencia, coalesce(cardinality(v_vendedores), 0);
  end if;
  perform set_config('ensayo.gerencia', v_gerencia::text, true);
  perform set_config('ensayo.vendedor_a', v_vendedores[1]::text, true);
  perform set_config('ensayo.vendedor_b', v_vendedores[2]::text, true);
  perform set_config('ensayo.vendedor_c', v_vendedores[3]::text, true);

  -- ── Precondiciones del laboratorio (si no se cumplen, el ensayo aborta: nunca un verde sin medir) ───────────────
  -- 1. Ninguna reunión preexistente con la hora en el futuro: las cifras de la línea base son de citas vencidas y por
  --    tanto NO cambian con la migración; si hubiera una anticipada ajena, los deltas quedarían contaminados. F4.2-bis
  --    (09/10/2026): el banco corrido sobre el laboratorio igual a producción deja reuniones de HOY con la hora unas tres
  --    horas por delante (9 a las 15:00 Lima, de PASO08 VEND1 y VEND3), y el montaje abortaba aquí hasta que esa hora
  --    pasaba. Como las de los actores (paso 3), se NEUTRALIZAN (activo = false, triggers apagados, dentro de esta
  --    transacción: se deshacen con el rollback) ANTES de sembrar y de tomar ninguna medida: el núcleo solo cuenta tareas
  --    activas, así que la línea base vuelve a ser solo de citas vencidas. Si aun así quedara alguna, aborta como antes.
  execute 'set local session_replication_role = replica';
  update crm.tareas t set activo = false
   where t.tipo = 'reunion' and t.activo and t.vence_en > now();
  get diagnostics v_futuras = row_count;
  execute 'set local session_replication_role = origin';
  if exists (select 1 from crm.tareas t where t.tipo = 'reunion' and t.activo and t.vence_en > now()) then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene reuniones con hora futura; los deltas no serían del ensayo';
  end if;
  perform set_config('ensayo.futuras_neutralizadas', v_futuras::text, true);
  -- 2. Margen con la medianoche de Lima: las citas vencidas (hasta -8 min) y las anticipadas (hasta +8 min) tienen que
  --    caer en la fecha de HOY en Lima, que es la ventana que mide el oráculo (`p_hasta <= hoy`).
  if ((now() - interval '10 minutes') at time zone 'America/Lima')::date <> v_hoy
     or ((now() + interval '10 minutes') at time zone 'America/Lima')::date <> v_hoy then
    raise exception 'ENSAYO ABORTADO: a menos de 10 minutos de la medianoche de Lima (ahora % Lima); repetir en unos minutos',
      now() at time zone 'America/Lima';
  end if;
  -- 3. Las reuniones que los tres actores ya tuvieran desde el inicio del mes pasado se NEUTRALIZAN (activo = false, con los
  --    triggers apagados; se deshace con el rollback), ANTES de sembrar y de tomar ninguna medida: el núcleo
  --    `private.citas_episodios` solo cuenta tareas activas, así que sus filas del corte por responsable vuelven a ser
  --    enteramente del ensayo. No se toca ninguna otra reunión; la línea base (en `pruebas.sql`) se toma después.
  execute 'set local session_replication_role = replica';
  update crm.tareas t set activo = false
   where t.vendedor_id = any(v_vendedores) and t.tipo = 'reunion' and t.activo
     and t.vence_en >= (v_mes_pasado::timestamp at time zone 'America/Lima');
  get diagnostics v_neutralizadas = row_count;
  execute 'set local session_replication_role = origin';
  if exists (select 1 from crm.tareas t
              where t.vendedor_id = any(v_vendedores) and t.tipo = 'reunion' and t.activo
                and t.vence_en >= (v_mes_pasado::timestamp at time zone 'America/Lima')) then
    raise exception 'ENSAYO ABORTADO: no se pudieron neutralizar las reuniones previas de los actores';
  end if;
  -- (El oráculo lo enseña en su «medida actores»: `pruebas.sql` empieza vaciando las medidas.)
  perform set_config('ensayo.neutralizadas', v_neutralizadas::text, true);

  -- ── Caso 3: un PERIODO YA PASADO (mes anterior), una cita de cada estado, todas con la hora vencida ─────────────
  execute 'set local session_replication_role = replica';
  v_lead := pg_temp.lead(v_vendedores[1], 'campania', 'ENSAYO Realizacion · mes pasado');
  v_ts := ((v_mes_pasado + 14)::timestamp at time zone 'America/Lima') + interval '10 hours';
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P1 realizada (mes pasado)', v_ts, 'completada');
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P2 no asistio (mes pasado)', v_ts + interval '1 hour', 'no_show');
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P3 cancelada por el asesor (mes pasado)', v_ts + interval '2 hours',
                       'cancelada', 'virtual', 'asesor', v_vendedores[1]);
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P4 cancelada por el sistema (mes pasado)', v_ts + interval '3 hours',
                       'cancelada', 'virtual', 'sistema');
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P5 reprogramada (mes pasado)', v_ts + interval '4 hours', 'reprogramada');
  perform pg_temp.cita(v_lead, v_vendedores[1], 'P6 pendiente vencida (mes pasado)', v_ts + interval '5 hours', 'pendiente');
  execute 'set local session_replication_role = origin';

  v_pasado := pg_temp.payload(v_gerencia, v_mes_pasado, v_fin_mes_pasado);
  if v_pasado is null or (v_pasado #>> '{resumen,pactadas}') is null then
    raise exception 'ENSAYO ABORTADO: la puerta no respondió para el periodo pasado (% a %)', v_mes_pasado, v_fin_mes_pasado;
  end if;
  perform set_config('ensayo.pasado_desde', v_mes_pasado::text, true);
  perform set_config('ensayo.pasado_hasta', v_fin_mes_pasado::text, true);
  perform set_config('ensayo.pasado_antes', v_pasado::text, true);
  perform set_config('ensayo.huella_antes',
    (select md5(p.prosrc) || '|' || md5(pg_get_functiondef(p.oid)) from pg_proc p
      where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure), true);
end;
$montaje$;
