-- MONTAJE del ensayo de «el analista dado de baja o suspendido sigue en el desglose con su marca, y la fila «Otros» hace que el
-- desglose de reuniones sume el total» (bloque 2.12: D-43, D-46, D-47 y D-48) — se ejecuta en el LABORATORIO (banco Docker
-- local), NUNCA contra producción, y no escribe nada: todo vive en la transacción que `armar-ensayo.mjs` abre y termina en
-- `rollback`.
--
-- Va DELANTE de la migración (y en `--sin-migracion`, delante del oráculo a secas) porque mide «lo de antes» con las puertas
-- VIGENTES, para que el oráculo (`pruebas.sql`) lo compare con lo de después dentro de la misma transacción (`now()` es fijo:
-- también `generado_en`, así la comparación es byte a byte):
--   1. Crea los auxiliares temporales (sesión, registro de fallos, siembra, llamadas a las dos puertas y a las otras métricas).
--   2. Elige los actores reales del banco (OBLIGATORIOS: si faltan, el ensayo aborta en vez de salir verde sin mirar nada).
--   3. Pasa a A (analista) y a P (suspendido) al equipo de SUPV, el supervisor que consulta la agenda, y deja a M «desalineado»
--      (ficha de analista activa, perfil del Portal de Directorio: `private.rol_crm` no le da rol).
--   4. Neutraliza (activo = false, triggers apagados, dentro del rollback) las reuniones que contaminarían las ventanas.
--   5. Siembra las citas de los dos días del ensayo (todas ya vencidas y en su estado final), una tarea pendiente antigua de Q1 y
--      un lead sin próxima acción de R.
--   6. Mide con las puertas vigentes, SIN bajas ni suspendidos con actividad (todos activos) y CON ellos.
--
-- Escenario (hora de Lima; D1 = hoy − 40 días, D2 = hoy − 39 días, D3 = hoy − 38 días; las ventanas D1, D2 y D3 de reuniones son
-- ENTERAMENTE del ensayo):
--   D1 · A (analista → de baja): 3 realizadas, 1 no asistió, 1 cancelada por él, 1 reprogramada   → 6 pactadas
--        S (supervisor con cartera → de baja): 2 realizadas, 1 cancelada por el sistema          → 3 pactadas
--        B (analista activo, control): 1 realizada, 1 no asistió                                  → 2 pactadas
--   D2 · P («suspendido en el Portal»: ficha ACTIVA, perfil inactivo): 1 realizada, 1 no asistió  → en el desglose, marcado
--        B: 1 realizada                                                                          → tal cual
--        X (Gerencia → de baja): 1 realizada, 1 cancelada por la Gerencia G (ajena)              ┐
--        C (Coordinación activa): 1 no asistió                                                   │ fila «Otros» (D-47):
--        N (sin responsable: vendedor_id nulo): 1 realizada, 1 cancelada por el sistema          │ 7 pactadas, 4 realizadas,
--        Z (un perfil que NUNCA tuvo ficha, sembrado saltándose la FK): 1 realizada               │ divisor 5, 80,0 %
--        M (analista «desalineado»: ficha y perfil activos, sin rol efectivo): 1 realizada        ┘
--   D3 · C (Coordinación): 1 cancelada por el sistema → «Otros» es la ÚNICA fila del desglose, con divisor 0 (porcentaje nulo)
--   Agenda (cuenta por `creado_en`/`actualizado_en`, que en la siembra es AHORA, y la foto de pendientes):
--        A, S y P tienen actividad hoy (cierres y tareas creadas) → con D-48 aparecen marcados;
--        Q1 (de baja del banco) solo tiene una tarea PENDIENTE (creada en D1, vencida) → aparece «de baja»;
--        Q2 (de baja del banco) no tiene nada y R (suspendido del banco) solo un lead sin próxima acción (rezago, no
--        actividad) → siguen FUERA, como hoy (la definición de actividad es la de la app, `agenda-equipo-vista.ts:138-150`).
--
-- Estados que se miden:
--   «sin» = A, S, X y Q1 con la ficha activa y P con el perfil activo (nadie de baja ni suspendido CON actividad: Q2 y R lo
--           están, pero sin actividad ni citas, y siguen fuera con las dos puertas);
--   «con» = A, S, X y Q1 de baja (ficha inactiva) y P suspendido (perfil inactivo).
--
-- Cómo se siembra. Las citas se insertan ya en su estado final con los triggers de `crm.tareas` y `crm.leads` apagados
-- (`set local session_replication_role = replica`), como el ensayo del bloque 2.2: lo que se mide es cómo las métricas LEEN
-- las tablas, no el camino de escritura. La baja se siembra como el ESTADO que deja la baja real (`crm.equipo.activo = false`)
-- y la suspensión como el que deja el Portal (`public.perfiles.activo = false`). Los CHECK de las tablas siguen activos. Con los
-- triggers apagados tampoco actúa la FK `tareas_vendedor_id_fkey` (es un trigger interno): así se siembra Z, el caso imposible.
--
-- Quién llama: las puertas como cada actor, con la identidad en las DOS formas de los claims. NO se usa `set role` (llamar
-- bajo `set role` a una función sin EXECUTE tumba el Postgres del banco): los permisos se leen del catálogo. TODOS los actores
-- son obligatorios, también el lector global (Directorio), que D-54 nombra: sin él el ensayo ABORTA (no hay modo parcial).

set local statement_timeout = '300s';

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

-- Un lead del ensayo. Teléfono aleatorio con la forma del CHECK (`uq_leads_telefono_vivo` lo exige único entre los vivos).
create function pg_temp.lead(p_vendedor uuid, p_nombre text, p_etapa text default 'reunion_agendada') returns uuid
language plpgsql as $f$
declare v_id uuid;
begin
  insert into crm.leads (nombre_completo, telefono, origen, etapa, monto_estimado, moneda, vendedor_id, activo)
  values (p_nombre, '+519' || lpad((floor(random() * 100000000))::bigint::text, 8, '0'),
          'campania', p_etapa, 1000.00, 'PEN', p_vendedor, true)
  returning id into v_id;
  return v_id;
end;
$f$;

-- Una cita (tarea de tipo reunión) ya en su estado final, con la forma que exigen los CHECK de `crm.tareas`
-- (la misma función que el ensayo del bloque 2.2, más quién la canceló):
--   completada → resultado 'interesado' · no_show → motivo 'cliente_no_asistio' · cancelada → motivo 'cancelada_cliente' y
--   cancelada_por 'asesor' (con el id de quien la anuló: el propio responsable salvo que se diga otro) o 'sistema' ·
--   reprogramada → motivo 'reprogramada'.
create function pg_temp.cita(p_lead uuid, p_vendedor uuid, p_titulo text, p_vence timestamptz, p_estado text,
                             p_cancelada_por text default null, p_cancelada_por_id uuid default null)
returns uuid language plpgsql as $f$
declare
  v_id uuid;
  v_quien text := case when p_estado = 'cancelada' then coalesce(p_cancelada_por, 'asesor') end;
begin
  insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, estado, modalidad_reunion, ubicacion_reunion,
                          resultado_reunion, motivo_no_realizada, cancelada_por, cancelada_por_id, activo, creado_por)
  values (p_lead, p_vendedor, 'reunion', p_titulo, p_vence, p_estado, 'virtual', null,
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

-- Una tarea PENDIENTE (llamada: no entra en la métrica de reuniones), creada y vencida en el pasado.
create function pg_temp.pendiente(p_lead uuid, p_vendedor uuid, p_titulo text, p_creada timestamptz, p_vence timestamptz)
returns uuid language plpgsql as $f$
declare v_id uuid;
begin
  insert into crm.tareas (lead_id, vendedor_id, tipo, titulo, vence_en, estado, activo, creado_por, creado_en, actualizado_en)
  values (p_lead, p_vendedor, 'llamada', p_titulo, p_vence, 'pendiente', true, p_vendedor, p_creada, p_creada)
  returning id into v_id;
  return v_id;
end;
$f$;

-- La respuesta ENTERA de la puerta de reuniones (lo que recibe la pantalla, `generado_en` incluido), como un actor. Un error se
-- devuelve como texto (`error <SQLSTATE> <mensaje>`) para poder compararlo también.
create function pg_temp.puerta(p_actor uuid, p_desde date, p_hasta date) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.sesion(p_actor);
  begin
    v := crm.metricas_reuniones_fn(p_desde, p_hasta)::text;
  exception when others then
    v := 'error ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.sesion(null);
  return v;
end;
$f$;

-- Lo que ve un rol al consultar reuniones: la respuesta entera (texto) o su error.
create function pg_temp.ve(p_actor uuid, p_desde date, p_hasta date) returns text language sql as $$
  select pg_temp.puerta(p_actor, p_desde, p_hasta);
$$;

-- La respuesta ENTERA de la puerta de la agenda, como un actor (o su error, como texto).
create function pg_temp.agenda(p_actor uuid, p_desde date, p_hasta date) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.sesion(p_actor);
  begin
    v := crm.metricas_agenda_fn(p_desde, p_hasta)::text;
  exception when others then
    v := 'error ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.sesion(null);
  return v;
end;
$f$;

-- La implementación de reuniones (ANTES del desglose), como la Gerencia: qué elementos hay y qué cifras traen.
create function pg_temp.implementacion(p_gerencia uuid, p_desde date, p_hasta date) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_gerencia);
  v := private.metricas_reuniones_implementacion(p_desde, p_hasta);
  perform pg_temp.sesion(null);
  return v;
end;
$f$;

-- La implementación de la agenda (ANTES del filtro), como el actor que consulta (su ámbito lo decide la implementación).
create function pg_temp.agenda_impl(p_actor uuid, p_desde date, p_hasta date) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  begin
    v := private.metricas_agenda_implementacion(p_desde, p_hasta);
  exception when others then
    v := null;
  end;
  perform pg_temp.sesion(null);
  return v;
end;
$f$;

-- Las otras tres métricas del filtro común, como la Gerencia; la respuesta entera o su error, como texto.
create function pg_temp.otra(p_gerencia uuid, p_metrica text, p_desde date, p_hasta date) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.sesion(p_gerencia);
  begin
    v := case p_metrica
           when 'conversiones' then crm.metricas_conversiones_fn(p_desde, p_hasta, null)::text
           when 'conversiones_equipo' then crm.metricas_conversiones_equipo_fn(p_desde, p_hasta)::text
           when 'conversion_mensual' then crm.conversion_mensual_sin_cartera_fn(date_trunc('month', p_hasta)::date)::text
         end;
  exception when others then
    v := 'error ' || sqlstate || ' ' || sqlerrm;
  end;
  perform pg_temp.sesion(null);
  return v;
end;
$f$;

-- Un elemento de un arreglo de la respuesta por una clave; null si no está.
create function pg_temp.fila(p_payload jsonb, p_grupo text, p_clave text, p_valor text) returns jsonb language sql as $$
  select x from jsonb_array_elements(coalesce(p_payload -> p_grupo, '[]'::jsonb)) x where x ->> p_clave = p_valor limit 1;
$$;

-- Un contador de una fila (ausente cuenta como cero: así un «no está» se nota como un 0 inesperado).
create function pg_temp.n(p_fila jsonb, p_campo text) returns numeric language sql as $$
  select coalesce((p_fila ->> p_campo)::numeric, 0);
$$;

-- Resumen legible de una fila del desglose, del resumen o de la agenda, para los mensajes.
create function pg_temp.txt(p_fila jsonb) returns text language sql as $$
  select coalesce((select string_agg(k || '=' || coalesce(v, 'null'), ' ' order by k)
                     from jsonb_each_text(p_fila) e(k, v)
                    where k in ('nombre','rol','activo','de_baja','suspendido','otros','responsable_id','supervisor_nombre',
                                'pactadas','debieron_ocurrir','realizadas','no_show','canceladas',
                                'reprogramadas','canceladas_sistema_vencidas','canceladas_ajenas_vencidas',
                                'reprogramadas_vencidas','divisor_realizacion','pendientes_cierre','programadas_futuras',
                                'pct_realizacion','toques','completadas','no_asistio','tareas_creadas',
                                'reuniones_agendadas','pendientes','vencidas','leads_sin_accion')), '(fila ausente)');
$$;

do $montaje$
declare
  v_hoy date := (now() at time zone 'America/Lima')::date;
  v_d1 date := (now() at time zone 'America/Lima')::date - 40;
  v_d2 date := (now() at time zone 'America/Lima')::date - 39;
  v_d3 date := (now() at time zone 'America/Lima')::date - 38;
  v_mes date := date_trunc('month', (now() at time zone 'America/Lima')::date)::date;
  v_g uuid; v_dir uuid; v_coord uuid; v_supv uuid; v_a uuid; v_b uuid; v_s uuid; v_x uuid; v_p uuid; v_z uuid;
  v_m uuid; v_q1 uuid; v_q2 uuid; v_r uuid;
  v_vendedores uuid[]; v_supervisores uuid[]; v_bajas uuid[];
  v_p_sembrado boolean := false;
  v_n_ventanas integer; v_n_actores integer; v_n_bajas_previas integer; v_bajas_previas integer;
  v_lead uuid;
  v_t1 timestamptz; v_t2 timestamptz;
  r record;
  w record;
begin
  -- ── Actores reales del banco (OBLIGATORIOS salvo el lector global) ─────────────────────────────────────────────────
  -- G: la Gerencia que consulta (rol efectivo gerencia), la primera por nombre (la misma regla que el ensayo del 2.2).
  select e.perfil_id into v_g
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'gerencia' and private.rol_crm(e.perfil_id) = 'gerencia'
  order by p.nombre_completo, e.perfil_id limit 1;
  -- X: OTRA Gerencia, que se dará de baja (un ex Gerencia con citas: rol NO pedido, va a «Otros»).
  select e.perfil_id into v_x
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'gerencia' and private.rol_crm(e.perfil_id) = 'gerencia'
    and e.perfil_id is distinct from v_g
  order by p.nombre_completo, e.perfil_id limit 1;
  -- DIR: un lector global (Directorio). OBLIGATORIO: D-54 le da a Directorio la marca «suspendido» en la agenda.
  select e.perfil_id into v_dir
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'directorio' and private.rol_crm(e.perfil_id) = 'directorio'
  order by p.nombre_completo, e.perfil_id limit 1;
  -- C: Coordinación activa (rol no pedido: sus citas van a «Otros»; como quien consulta: 42501).
  select e.perfil_id into v_coord
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo and e.rol_crm = 'coordinador' and private.rol_crm(e.perfil_id) = 'coordinador'
  order by p.nombre_completo, e.perfil_id limit 1;
  -- A, B y M: tres analistas efectivos (los de MENOS reuniones). A se dará de baja; B sigue activo (control y rol que
  -- consulta); M se deja «desalineado» (su perfil del Portal pasa a Directorio: `private.rol_crm` no le da rol).
  select array_agg(perfil_id order by n, nombre, perfil_id) into v_vendedores
  from (
    select e.perfil_id, p.nombre_completo as nombre,
           (select count(*) from crm.tareas t where t.vendedor_id = e.perfil_id and t.tipo = 'reunion' and t.activo) as n
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'vendedor' and private.rol_crm(e.perfil_id) = 'vendedor'
    order by 3, 2, 1 limit 3
  ) s;
  -- S y SUPV: dos supervisores efectivos. S (el de menos reuniones) se dará de baja; SUPV consulta (y recibe a A y a P).
  select array_agg(perfil_id order by n, nombre, perfil_id) into v_supervisores
  from (
    select e.perfil_id, p.nombre_completo as nombre,
           (select count(*) from crm.tareas t where t.vendedor_id = e.perfil_id and t.tipo = 'reunion' and t.activo) as n
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'supervisor' and private.rol_crm(e.perfil_id) = 'supervisor'
    order by 3, 2, 1 limit 2
  ) s;
  v_a := v_vendedores[1]; v_b := v_vendedores[2]; v_m := v_vendedores[3];
  v_s := v_supervisores[1]; v_supv := v_supervisores[2];
  -- P: «suspendido en el Portal» = ficha de analista ACTIVA con el perfil inactivo. Se prefiere el que ya tenga el banco; si
  --    no hay, se suspende (dentro del rollback) el perfil de otro analista activo.
  select e.perfil_id into v_p
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo is not true and e.rol_crm = 'vendedor'
  order by p.nombre_completo, e.perfil_id limit 1;
  if v_p is null then
    select e.perfil_id into v_p
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.activo and p.activo and e.rol_crm = 'vendedor' and e.perfil_id <> all (array[v_a, v_b, v_m])
    order by p.nombre_completo, e.perfil_id limit 1;
    if v_p is not null then
      execute 'set local session_replication_role = replica';
      update public.perfiles set activo = false where id = v_p;
      execute 'set local session_replication_role = origin';
      v_p_sembrado := true;
    end if;
  end if;
  -- R: OTRO suspendido en el Portal (ficha de analista o supervisor activa, perfil inactivo), que no tendrá actividad: solo
  --    un lead sin próxima acción (rezago). Tiene que seguir fuera de la agenda.
  select e.perfil_id into v_r
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.activo and p.activo is not true and e.rol_crm in ('vendedor', 'supervisor') and e.perfil_id <> v_p
  order by p.nombre_completo, e.perfil_id limit 1;
  -- Q1 y Q2: dos fichas de analista o supervisor YA dadas de baja en el banco. Q1 solo tendrá una tarea pendiente antigua
  --    (aparece «de baja» en la agenda); Q2, nada (sigue fuera).
  select array_agg(perfil_id order by nombre, perfil_id) into v_bajas
  from (
    select e.perfil_id, p.nombre_completo as nombre
    from crm.equipo e join public.perfiles p on p.id = e.perfil_id
    where e.activo is false and e.rol_crm in ('vendedor', 'supervisor')
    order by 2, 1 limit 2
  ) s;
  v_q1 := v_bajas[1]; v_q2 := v_bajas[2];
  -- Z: un perfil que NUNCA tuvo ficha en crm.equipo (cualquier rol del Portal).
  select p.id into v_z
  from public.perfiles p
  where not exists (select 1 from crm.equipo e where e.perfil_id = p.id)
  order by p.nombre_completo, p.id limit 1;

  if v_dir is null then
    raise exception 'ENSAYO ABORTADO: falta un lector global (Directorio) activo en el banco: este ensayo prueba lo que ve Directorio (D-54) y no tiene modo parcial';
  end if;
  if v_g is null or v_x is null or v_coord is null or v_a is null or v_b is null or v_m is null or v_s is null
     or v_supv is null or v_p is null or v_r is null or v_q1 is null or v_q2 is null or v_z is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (gerencia=%, otra gerencia=%, coordinación=%, analistas=%, supervisores=%, suspendido en Portal=%, otro suspendido=%, dados de baja del banco=%, perfil sin ficha=%)',
      v_g, v_x, v_coord, coalesce(cardinality(v_vendedores), 0), coalesce(cardinality(v_supervisores), 0), v_p, v_r,
      coalesce(cardinality(v_bajas), 0), v_z;
  end if;
  perform set_config('ensayo.g', v_g::text, true);
  perform set_config('ensayo.x', v_x::text, true);
  perform set_config('ensayo.dir', v_dir::text, true);
  perform set_config('ensayo.coord', v_coord::text, true);
  perform set_config('ensayo.a', v_a::text, true);
  perform set_config('ensayo.b', v_b::text, true);
  perform set_config('ensayo.m', v_m::text, true);
  perform set_config('ensayo.s', v_s::text, true);
  perform set_config('ensayo.supv', v_supv::text, true);
  perform set_config('ensayo.p', v_p::text, true);
  perform set_config('ensayo.r', v_r::text, true);
  perform set_config('ensayo.q1', v_q1::text, true);
  perform set_config('ensayo.q2', v_q2::text, true);
  perform set_config('ensayo.z', v_z::text, true);
  perform set_config('ensayo.p_sembrado', v_p_sembrado::text, true);
  perform set_config('ensayo.d1', v_d1::text, true);
  perform set_config('ensayo.d2', v_d2::text, true);
  perform set_config('ensayo.d3', v_d3::text, true);

  -- ── A y P pasan al equipo de SUPV (la agenda del supervisor); M queda «desalineado» ────────────────────────────────
  execute 'set local session_replication_role = replica';
  update crm.equipo e set supervisor_id = v_supv where e.perfil_id in (v_a, v_p);
  update public.perfiles p set rol = 'directorio' where p.id = v_m;
  execute 'set local session_replication_role = origin';
  if private.rol_crm(v_m) is not null
     or (select count(*) from crm.equipo e where e.perfil_id in (v_a, v_p) and e.supervisor_id = v_supv) <> 2 then
    raise exception 'ENSAYO ABORTADO: no se pudo pasar a A y P al equipo de SUPV o dejar a M sin rol efectivo';
  end if;

  -- ── Neutralizar lo que contaminaría las ventanas (activo = false; el núcleo solo cuenta tareas activas) ────────────
  v_t1 := v_d1::timestamp at time zone 'America/Lima';
  v_t2 := (v_d3 + 1)::timestamp at time zone 'America/Lima';
  execute 'set local session_replication_role = replica';
  -- (a) las reuniones de los tres días del ensayo: sus ventanas pasan a ser enteramente del ensayo;
  update crm.tareas t set activo = false where t.tipo = 'reunion' and t.activo and t.vence_en >= v_t1 and t.vence_en < v_t2;
  get diagnostics v_n_ventanas = row_count;
  -- (b) las de A, S, P y M (de cualquier fecha): sus citas son solo las del ensayo;
  update crm.tareas t set activo = false where t.tipo = 'reunion' and t.activo and t.vendedor_id in (v_a, v_s, v_p, v_m);
  get diagnostics v_n_actores = row_count;
  -- (c) las de quien YA estaba dado de baja o suspendido en el banco con una ficha de analista o supervisor: «sin» tiene
  --     que ser sin bajas ni suspendidos con citas (se cuentan antes, como medida del laboratorio).
  select count(distinct e.perfil_id) into v_bajas_previas
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where (e.activo is false or p.activo is not true) and e.rol_crm in ('vendedor', 'supervisor');
  update crm.tareas t set activo = false
   where t.tipo = 'reunion' and t.activo
     and exists (select 1 from crm.equipo e join public.perfiles p on p.id = e.perfil_id
                  where e.perfil_id = t.vendedor_id and (e.activo is false or p.activo is not true)
                    and e.rol_crm in ('vendedor', 'supervisor'));
  get diagnostics v_n_bajas_previas = row_count;
  execute 'set local session_replication_role = origin';
  if exists (select 1 from crm.tareas t where t.tipo = 'reunion' and t.activo and t.vence_en >= v_t1 and t.vence_en < v_t2)
     or exists (select 1 from crm.tareas t where t.tipo = 'reunion' and t.activo and t.vendedor_id in (v_a, v_s, v_p, v_m))
     or exists (select 1 from crm.tareas t join crm.equipo e on e.perfil_id = t.vendedor_id
                  join public.perfiles p on p.id = e.perfil_id
                 where t.tipo = 'reunion' and t.activo and (e.activo is false or p.activo is not true)
                   and e.rol_crm in ('vendedor', 'supervisor')) then
    raise exception 'ENSAYO ABORTADO: no se pudieron neutralizar las reuniones que contaminarían las ventanas';
  end if;
  perform set_config('ensayo.neutralizadas',
    format('%s de los tres días del ensayo · %s de A, S, P y M · %s de %s dados de baja o suspendidos que ya tenía el banco',
           v_n_ventanas, v_n_actores, v_n_bajas_previas, v_bajas_previas), true);

  -- ── Siembra (todas vencidas: D1 y D2 son de hace más de un mes) ──────────────────────────────────────────────────
  execute 'set local session_replication_role = replica';
  v_t1 := (v_d1::timestamp at time zone 'America/Lima') + interval '9 hours';
  v_lead := pg_temp.lead(v_a, 'ENSAYO 2.12 · A');
  perform pg_temp.cita(v_lead, v_a, 'A1 realizada', v_t1, 'completada');
  perform pg_temp.cita(v_lead, v_a, 'A2 realizada', v_t1 + interval '1 hour', 'completada');
  perform pg_temp.cita(v_lead, v_a, 'A3 realizada', v_t1 + interval '2 hours', 'completada');
  perform pg_temp.cita(v_lead, v_a, 'A4 no asistio', v_t1 + interval '3 hours', 'no_show');
  perform pg_temp.cita(v_lead, v_a, 'A5 cancelada por el asesor', v_t1 + interval '4 hours', 'cancelada', 'asesor');
  perform pg_temp.cita(v_lead, v_a, 'A6 reprogramada', v_t1 + interval '5 hours', 'reprogramada');
  v_lead := pg_temp.lead(v_s, 'ENSAYO 2.12 · S');
  perform pg_temp.cita(v_lead, v_s, 'S1 realizada', v_t1, 'completada');
  perform pg_temp.cita(v_lead, v_s, 'S2 realizada', v_t1 + interval '1 hour', 'completada');
  perform pg_temp.cita(v_lead, v_s, 'S3 cancelada por el sistema', v_t1 + interval '2 hours', 'cancelada', 'sistema');
  v_lead := pg_temp.lead(v_b, 'ENSAYO 2.12 · B');
  perform pg_temp.cita(v_lead, v_b, 'B1 realizada', v_t1, 'completada');
  perform pg_temp.cita(v_lead, v_b, 'B2 no asistio', v_t1 + interval '1 hour', 'no_show');
  v_t2 := (v_d2::timestamp at time zone 'America/Lima') + interval '10 hours';
  perform pg_temp.cita(v_lead, v_b, 'B3 realizada (D2)', v_t2, 'completada');
  v_lead := pg_temp.lead(v_p, 'ENSAYO 2.12 · P');
  perform pg_temp.cita(v_lead, v_p, 'P1 realizada (suspendido en Portal)', v_t2, 'completada');
  perform pg_temp.cita(v_lead, v_p, 'P2 no asistio (suspendido en Portal)', v_t2 + interval '1 hour', 'no_show');
  v_lead := pg_temp.lead(v_x, 'ENSAYO 2.12 · X');
  perform pg_temp.cita(v_lead, v_x, 'X1 realizada (ex Gerencia)', v_t2, 'completada');
  perform pg_temp.cita(v_lead, v_x, 'X2 cancelada por la Gerencia G (ajena)', v_t2 + interval '1 hour', 'cancelada', 'asesor', v_g);
  perform pg_temp.cita(pg_temp.lead(v_coord, 'ENSAYO 2.12 · C'), v_coord, 'C1 no asistio (Coordinación)', v_t2, 'no_show');
  v_lead := pg_temp.lead(v_b, 'ENSAYO 2.12 · N');
  perform pg_temp.cita(v_lead, null, 'N1 realizada (sin responsable)', v_t2, 'completada');
  perform pg_temp.cita(v_lead, null, 'N2 cancelada por el sistema (sin responsable)', v_t2 + interval '1 hour', 'cancelada', 'sistema');
  perform pg_temp.cita(pg_temp.lead(v_b, 'ENSAYO 2.12 · Z'), v_z, 'Z1 realizada (perfil sin ficha)', v_t2, 'completada');
  perform pg_temp.cita(pg_temp.lead(v_m, 'ENSAYO 2.12 · M'), v_m, 'M1 realizada (analista desalineado)', v_t2, 'completada');
  -- D3: una sola cita, de Coordinación y cancelada por el sistema: «Otros» es la única fila y su divisor es 0.
  perform pg_temp.cita(pg_temp.lead(v_coord, 'ENSAYO 2.12 · C3'), v_coord, 'C3 cancelada por el sistema (D3)',
                       (v_d3::timestamp at time zone 'America/Lima') + interval '10 hours', 'cancelada', 'sistema');
  -- Q1: una tarea PENDIENTE (llamada) creada y vencida en D1: su única «actividad» en la agenda es la foto de pendientes.
  perform pg_temp.pendiente(pg_temp.lead(v_q1, 'ENSAYO 2.12 · Q1', 'contactado'), v_q1, 'Q1 llamada pendiente', v_t1, v_t1 + interval '1 hour');
  -- R: un lead abierto SIN próxima acción (rezago: no es actividad en la definición de la app).
  perform pg_temp.lead(v_r, 'ENSAYO 2.12 · R', 'nuevo');
  execute 'set local session_replication_role = origin';

  -- ── Estado «sin»: nadie de baja ni suspendido CON actividad (A, S, X y Q1 con la ficha activa; P con el perfil activo) ─
  execute 'set local session_replication_role = replica';
  update crm.equipo e set activo = true where e.perfil_id in (v_a, v_s, v_x, v_q1);
  update public.perfiles p set activo = true where p.id = v_p;
  execute 'set local session_replication_role = origin';

  -- ── Lo de ANTES, SIN: reuniones (cinco ventanas y cada rol) y agenda (cuatro ventanas y cada rol) ───────────────────
  for w in select * from (values ('d1', v_d1, v_d1), ('d2', v_d2, v_d2), ('d3', v_d3, v_d3), ('hoy', v_hoy, v_hoy),
                                  ('mes', v_mes, v_hoy), ('anio', v_hoy - 365, v_hoy)) x(k, desde, hasta)
  loop
    perform set_config('ensayo.sin.' || w.k, pg_temp.puerta(v_g, w.desde, w.hasta), true);
  end loop;
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('coordinacion', v_coord), ('supervisor', v_supv),
                                  ('analista', v_b), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor)
  loop
    perform set_config('ensayo.vis.sin.' || r.k, pg_temp.ve(r.actor, v_d1, v_d1), true);
    perform set_config('ensayo.vis2.sin.' || r.k, pg_temp.ve(r.actor, v_d2, v_d2), true);
  end loop;
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('supervisor', v_supv), ('analista', v_b),
                                  ('coordinacion', v_coord), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor)
  loop
    for w in select * from (values ('hoy', v_hoy, v_hoy), ('semana', v_hoy - 6, v_hoy), ('mes', v_mes, v_hoy),
                                    ('d1d2', v_d1, v_d2)) x(k, desde, hasta)
    loop
      perform set_config('ensayo.ag.sin.' || r.k || '.' || w.k, pg_temp.agenda(r.actor, w.desde, w.hasta), true);
    end loop;
  end loop;

  -- ── Estado «con»: la BAJA de A, S, X y Q1 (crm.fijar_membresia_activa_fn) y la SUSPENSIÓN de P (el Portal) ───────────
  execute 'set local session_replication_role = replica';
  update crm.equipo e set activo = false where e.perfil_id in (v_a, v_s, v_x, v_q1);
  update public.perfiles p set activo = false where p.id = v_p;
  execute 'set local session_replication_role = origin';
  if (select count(*) from crm.equipo e where e.perfil_id in (v_a, v_s, v_x, v_q1) and e.activo is false) <> 4
     or (select p.activo from public.perfiles p where p.id = v_p) is not false then
    raise exception 'ENSAYO ABORTADO: no se pudo dejar de baja a A, S, X y Q1 o suspender a P';
  end if;

  -- ── Lo de ANTES, CON: las mismas ventanas y roles, y las otras tres métricas ────────────────────────────────────────
  for w in select * from (values ('d1', v_d1, v_d1), ('d2', v_d2, v_d2), ('d3', v_d3, v_d3), ('hoy', v_hoy, v_hoy),
                                  ('mes', v_mes, v_hoy), ('anio', v_hoy - 365, v_hoy)) x(k, desde, hasta)
  loop
    perform set_config('ensayo.con.' || w.k, pg_temp.puerta(v_g, w.desde, w.hasta), true);
  end loop;
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('coordinacion', v_coord), ('supervisor', v_supv),
                                  ('analista', v_b), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor)
  loop
    perform set_config('ensayo.vis.con.' || r.k, pg_temp.ve(r.actor, v_d1, v_d1), true);
    perform set_config('ensayo.vis2.con.' || r.k, pg_temp.ve(r.actor, v_d2, v_d2), true);
  end loop;
  for r in select * from (values ('gerencia', v_g), ('lector', v_dir), ('supervisor', v_supv), ('analista', v_b),
                                  ('coordinacion', v_coord), ('analista_a', v_a), ('suspendido', v_p), ('anonimo', null::uuid)) a(k, actor)
  loop
    for w in select * from (values ('hoy', v_hoy, v_hoy), ('semana', v_hoy - 6, v_hoy), ('mes', v_mes, v_hoy),
                                    ('d1d2', v_d1, v_d2)) x(k, desde, hasta)
    loop
      perform set_config('ensayo.ag.con.' || r.k || '.' || w.k, pg_temp.agenda(r.actor, w.desde, w.hasta), true);
    end loop;
  end loop;
  -- Las otras tres métricas del filtro común, en el mes en curso.
  perform set_config('ensayo.otra.conversiones', pg_temp.otra(v_g, 'conversiones', v_mes, v_hoy), true);
  perform set_config('ensayo.otra.conversiones_equipo', pg_temp.otra(v_g, 'conversiones_equipo', v_mes, v_hoy), true);
  perform set_config('ensayo.otra.conversion_mensual', pg_temp.otra(v_g, 'conversion_mensual', v_mes, v_hoy), true);
end;
$montaje$;
