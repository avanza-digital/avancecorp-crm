-- Pendientes de lo más reciente a lo más antiguo (20261020214445): prueba sintética en el BANCO
-- Docker propio (esquema de producción sin datos). Siembra sus propios actores y tareas SIN
-- triggers (session_replication_role), lee como authenticated/anon con identidad efectiva y
-- termina SIEMPRE en ROLLBACK. Requiere la migración instalada. Nunca contra producción.
--
--   docker exec -i -e PGPASSWORD=postgres <banco> psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -f supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql
begin;
set local statement_timeout = '300s';
set local timezone = 'America/Lima';
do $$ begin
  if shobj_description((select oid from pg_database where datname = current_database()), 'pg_database')
    is distinct from 'BANCO SINTETICO PENDIENTES RECIENTES / sin produccion' then
    raise exception 'PENDIENTES RECIENTES: sólo en el banco sintético (comment on database)';
  end if;
end $$;

create function pg_temp.afirmar(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'PENDIENTES RECIENTES: %', mensaje; end if; end $$;
create function pg_temp.codigo(comando text) returns text language plpgsql as $$
declare recibido text; begin
  begin execute comando; exception when others then recibido := sqlstate; end;
  return coalesce(recibido, 'ninguno');
end $$;
create function pg_temp.denegada(comando text, codigo text default '42501') returns void language plpgsql as $$
declare recibido text := pg_temp.codigo(comando); begin
  perform pg_temp.afirmar(recibido = codigo, format('error esperado %s; recibido %s: %s', codigo, recibido, comando));
end $$;
-- La imagen del banco lee request.jwt.claim.sub; producción también request.jwt.claims: se fijan las dos.
create function pg_temp.como(actor uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(actor::text, ''), true);
  perform set_config('request.jwt.claims', case when actor is null then '' else json_build_object('sub', actor, 'role', 'authenticated')::text end, true);
end $$;
-- Orden estricto de una página: (vence_en, id) baja (desc) o sube (asc) fila a fila.
create function pg_temp.estricta(items jsonb, descendente boolean) returns boolean language sql as $$
  select coalesce(bool_and(case when descendente then (f.v, f.id) < (f.v_ant, f.id_ant) else (f.v, f.id) > (f.v_ant, f.id_ant) end), true)
  from (
    select (x.value->>'vence_en')::timestamptz v, (x.value->>'id')::uuid id,
      lag((x.value->>'vence_en')::timestamptz) over (order by x.n) v_ant, lag((x.value->>'id')::uuid) over (order by x.n) id_ant
    from jsonb_array_elements(items) with ordinality x(value, n)
  ) f where f.v_ant is not null
$$;
create function pg_temp.ids(items jsonb, al_reves boolean default false) returns uuid[] language sql as $$
  select coalesce(array_agg((x.value->>'id')::uuid order by case when al_reves then -x.n else x.n end), '{}')
  from jsonb_array_elements(items) with ordinality x(value, n)
$$;

-- Actores y datos sintéticos (nombres que cantan que son de banco).
create temporary table pr_actores as select
  'a0000000-0000-4000-8000-000000000001'::uuid sup1, 'a0000000-0000-4000-8000-000000000002'::uuid v1,
  'a0000000-0000-4000-8000-000000000003'::uuid v2, 'a0000000-0000-4000-8000-000000000004'::uuid gerente,
  'a0000000-0000-4000-8000-000000000005'::uuid coordinador, 'a0000000-0000-4000-8000-000000000006'::uuid sup2,
  'a0000000-0000-4000-8000-000000000007'::uuid ajeno, 'a0000000-0000-4000-8000-000000000009'::uuid nadie,
  'b0000000-0000-4000-8000-000000000001'::uuid lead1;
grant select on pr_actores to authenticated, anon;
set local session_replication_role = replica;
insert into auth.users (id, email)
select x.id, x.correo
from pr_actores a cross join lateral (values (a.sup1, 'banco.sup1@pendientes.test'), (a.v1, 'banco.v1@pendientes.test'),
  (a.v2, 'banco.v2@pendientes.test'), (a.gerente, 'banco.gerente@pendientes.test'), (a.coordinador, 'banco.coord@pendientes.test'),
  (a.sup2, 'banco.sup2@pendientes.test'), (a.ajeno, 'banco.ajeno@pendientes.test')) x(id, correo);
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, debe_cambiar_password, titular_distinto, titular_distinto_usd)
select x.id, x.nombre, x.rol, true, 'DNI', false, false, false
from pr_actores a cross join lateral (values (a.sup1, 'BANCO SUP1', 'analista'), (a.v1, 'BANCO V1', 'analista'), (a.v2, 'BANCO V2', 'analista'),
  (a.gerente, 'BANCO GERENTE', 'admin'), (a.coordinador, 'BANCO COORD', 'analista'), (a.sup2, 'BANCO SUP2', 'analista'),
  (a.ajeno, 'BANCO AJENO', 'analista')) x(id, nombre, rol);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select x.id, x.rol, x.sup, true
from pr_actores a cross join lateral (values (a.sup1, 'supervisor', null::uuid), (a.sup2, 'supervisor', null), (a.v1, 'vendedor', a.sup1),
  (a.v2, 'vendedor', a.sup1), (a.ajeno, 'vendedor', a.sup2), (a.gerente, 'gerencia', null), (a.coordinador, 'coordinador', null)) x(id, rol, sup);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo)
select a.lead1, 'BANCO LEAD DE V1', '+51987650001', 'landing', 50000, 'PEN', 'contactado', a.v1, true from pr_actores a;
-- 15 vencidas (hace 1..15 h), 8 futuras (dentro de 1..8 h, ids 16..23) y un EMPATE exacto de vence_en (ids 24 y 25, hace 30 h): 25 pendientes.
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, creado_por)
select ('c0000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, a.lead1, a.v1, 'llamada', 'BANCO TAREA ' || i,
  case when i <= 15 then now() - make_interval(hours => i) when i <= 23 then now() + make_interval(hours => i - 15) else now() - interval '30 hours' end, a.v1
from pr_actores a cross join generate_series(1, 25) i
union all
select ('c0000000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, a.lead1, a.v2, 'llamada', 'BANCO TAREA V2 ' || i, now() - interval '1 hour', a.v2
from pr_actores a cross join generate_series(31, 32) i
union all
select 'c0000000-0000-4000-8000-000000000033'::uuid, a.lead1, a.ajeno, 'llamada', 'BANCO TAREA AJENO', now() - interval '1 hour', a.ajeno
from pr_actores a;
-- Una tarea cerrada y una inactiva de v1: NO entran.
insert into crm.tareas (id, lead_id, vendedor_id, tipo, titulo, vence_en, creado_por, estado, activo)
select ('c0000000-0000-4000-8000-0000000000' || i)::uuid, a.lead1, a.v1, 'llamada', 'BANCO FUERA ' || i, now() - interval '2 hours', a.v1,
  case when i = 41 then 'completada' else 'pendiente' end, i <> 42
from pr_actores a cross join (values (41), (42)) x(i);
set local session_replication_role = origin;
select pg_temp.afirmar((select count(*) from crm.tareas t, pr_actores a where t.vendedor_id = a.v1 and t.activo and t.estado = 'pendiente') = 25, 'siembra: 25 pendientes de v1');

-- El núcleo G4a con otro nombre, acreditado por md5(prosrc) del cuerpo VIVO de producción (medido el 20/10/2026 en el banco a paridad).
create function pg_temp.core_g4a(
  p_analista_id uuid, p_solo_vencidas boolean, p_limite integer,
  p_despues_de timestamptz, p_despues_id uuid
) returns jsonb
language plpgsql stable security invoker set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_ambito jsonb;
  v_ahora timestamptz := statement_timestamp();
  v_respuesta jsonb;
  v_invalida boolean;
begin
  -- También protege la invocación directa del núcleo por authenticated. Supervisión y,
  -- desde G4a (27/09/2026), Gerencia; el rol nulo se rechaza explícitamente (Codex).
  if v_uid is null or not coalesce(v_rol in ('supervisor', 'gerencia'), false) then
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;
  -- Supervisión: su árbol, como en H3. Gerencia: el roster canónico con supervisor nulo
  -- (toda la operación visible, «fuera» incluido), el mismo de gestion_diaria_equipo_core.
  v_ambito := private.gestion_diaria_equipo_ambito(case when v_rol = 'supervisor' then v_uid end);
  if p_analista_id is null or p_solo_vencidas is null or p_limite is null
    or p_limite < 1 or p_limite > 100
    or (p_despues_de is null) <> (p_despues_id is null)
    or (p_despues_de is not null and not isfinite(p_despues_de)) then
    raise exception 'Parámetros de pendientes inválidos' using errcode = '22023';
  end if;
  if not exists (select 1 from jsonb_array_elements(v_ambito->'roster') r
    where (r->>'analista_id')::uuid = p_analista_id) then
    -- Ajeno, inactivo e inexistente tienen idéntica respuesta.
    raise exception 'No autorizado para consultar pendientes' using errcode = '42501';
  end if;

  -- Resumen y página comparten sentencia y RLS. La referencia no determina
  -- quién es responsable de la tarea ni elimina tareas sin lead visible.
  with base as materialized (
    select t.id, t.vendedor_id, t.tipo, t.titulo, t.vence_en,
      t.lead_id, t.perfil_id, t.inversionista_id
    from crm.tareas t
    where t.vendedor_id = p_analista_id and t.activo and t.estado = 'pendiente'
  ), resumen as (
    select coalesce(cardinality(array_agg(b.id)), 0) as tareas_pendientes,
      coalesce(cardinality(array_agg(b.id) filter (where b.vence_en < v_ahora)), 0) as tareas_vencidas,
      coalesce(bool_or(num_nonnulls(b.lead_id, b.perfil_id, b.inversionista_id) <> 1
        or not isfinite(b.vence_en)), false) as invalida
    from base b
  ), sonda as materialized (
    select b.* from base b
    where (not p_solo_vencidas or b.vence_en < v_ahora)
      and (p_despues_de is null or (b.vence_en, b.id) > (p_despues_de, p_despues_id))
    order by b.vence_en, b.id limit p_limite + 1
  ), pagina as materialized (
    select s.* from sonda s order by s.vence_en, s.id limit p_limite
  ), estado as (
    select coalesce(cardinality(array_agg(s.id)), 0) > p_limite as hay_mas from sonda s
  )
  select jsonb_build_object(
    'version', 1, 'zona', 'America/Lima', 'supervisor_id', v_uid,
    'analista_id', p_analista_id, 'generado_en', v_ahora, 'pendientes_al', v_ahora,
    'solo_vencidas', p_solo_vencidas, 'limite', p_limite,
    'resumen', jsonb_build_object('tareas_pendientes', r.tareas_pendientes,
      'tareas_vencidas', r.tareas_vencidas),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'vendedor_id', p.vendedor_id, 'tipo', p.tipo, 'titulo', p.titulo,
      'vence_en', p.vence_en, 'estado', 'pendiente',
      'referencia_tipo', case when p.lead_id is not null then 'lead'
        when p.perfil_id is not null then 'perfil' else 'postventa' end,
      'lead_id', case when nullif(btrim(l.nombre_completo), '') is not null then l.id end,
      'lead_nombre', nullif(btrim(l.nombre_completo), '')
    ) order by p.vence_en, p.id) from pagina p left join crm.leads l on l.id = p.lead_id), '[]'::jsonb),
    'hay_mas', e.hay_mas,
    'siguiente_cursor', case when e.hay_mas then (select jsonb_build_object(
      'despues_de', p.vence_en, 'despues_id', p.id)
      from pagina p order by p.vence_en desc, p.id desc limit 1) else null end
  ), r.invalida into v_respuesta, v_invalida from resumen r cross join estado e;
  if v_invalida then
    raise exception 'No se pudo confirmar la integridad de las tareas' using errcode = '22000';
  end if;
  return v_respuesta;
end;
$function$;
select pg_temp.afirmar(md5(prosrc) = '43f946b14f91bfd7da15d384fecdde67', 'la copia G4a de la prueba no es el cuerpo vivo')
from pg_proc where oid = 'pg_temp.core_g4a(uuid,boolean,integer,timestamptz,uuid)'::regprocedure;

-- 1. La v1 y el envoltorio siguen siendo G4a al byte en la respuesta (misma sentencia = mismo statement_timestamp).
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
select pg_temp.afirmar(pg_temp.core_g4a(v1, false, 25, null, null) = private.gestion_diaria_pendientes_core(v1, false, 25, null, null)
  and pg_temp.core_g4a(v1, true, 7, null, null) = private.gestion_diaria_pendientes_core(v1, true, 7, null, null)
  and pg_temp.core_g4a(v1, false, 100, null, null) = crm.gestion_diaria_pendientes_fn(v1, false, 100)
  and pg_temp.core_g4a(v1, false, 7, null, null) = private.gestion_diaria_pendientes_core(v1, false, 7, null, null, false),
  'ascendente: v1, envoltorio y núcleo con false = G4a') from pr_actores;
-- También con cursor intermedio (lo que usan los bundles publicados al «Cargar más»): misma segunda página que G4a, en Todas y en Vencidas.
select pg_temp.afirmar(pg_temp.core_g4a(a.v1, false, 7, (c1->'siguiente_cursor'->>'despues_de')::timestamptz, (c1->'siguiente_cursor'->>'despues_id')::uuid)
    = private.gestion_diaria_pendientes_core(a.v1, false, 7, (c1->'siguiente_cursor'->>'despues_de')::timestamptz, (c1->'siguiente_cursor'->>'despues_id')::uuid)
  and pg_temp.core_g4a(a.v1, true, 5, (c2->'siguiente_cursor'->>'despues_de')::timestamptz, (c2->'siguiente_cursor'->>'despues_id')::uuid)
    = crm.gestion_diaria_pendientes_fn(a.v1, true, 5, (c2->'siguiente_cursor'->>'despues_de')::timestamptz, (c2->'siguiente_cursor'->>'despues_id')::uuid)
  and (c1->>'hay_mas')::boolean and (c2->>'hay_mas')::boolean,
  'ascendente con cursor: envoltorio y v1 = G4a en la segunda página')
from pr_actores a, lateral (select pg_temp.core_g4a(a.v1, false, 7, null, null) c1, pg_temp.core_g4a(a.v1, true, 5, null, null) c2) q;
select pg_temp.afirmar(pg_temp.codigo(format('select pg_temp.core_g4a(%L,false,25,null,null)', x))
    = pg_temp.codigo(format('select crm.gestion_diaria_pendientes_v3_fn(%L,false,25,null,null)', x)),
  'la v3 da el mismo error que G4a para ' || coalesce(x::text, 'null'))
from pr_actores, unnest(array[ajeno, nadie, null]) x;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 0)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 101)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L, false, 25, now(), null)', v1), '22023') from pr_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L, false, 25, null, null, null)', v1), '22023') from pr_actores;

-- 2. La v3 en una página: EXACTAMENTE la v1 al revés; version 3; mismo resumen; cursor nulo.
select pg_temp.afirmar(pg_temp.ids(v3->'items') = pg_temp.ids(v1p->'items', true)
  and jsonb_array_length(v3->'items') = 25 and pg_temp.estricta(v3->'items', true)
  and (v3->>'version')::int = 3 and (v1p->>'version')::int = 1
  and v3->'resumen' = v1p->'resumen' and (v3#>>'{resumen,tareas_pendientes}')::int = 25 and (v3#>>'{resumen,tareas_vencidas}')::int = 17
  and (v3->>'hay_mas')::boolean = false and v3->'siguiente_cursor' = 'null'::jsonb
  and v3->>'supervisor_id' = sup1::text and v3->>'analista_id' = v1::text and (v3->>'solo_vencidas')::boolean = false
  and (v3->>'limite')::int = 100 and v3->>'zona' = 'America/Lima',
  'v3 = v1 al revés, version 3, mismo resumen')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3, crm.gestion_diaria_pendientes_fn(a.v1, false, 100) v1p) q;
-- El empate exacto de vence_en (ids 24 y 25, las dos más viejas) se desempata por id DESCENDENTE: 25 antes que 24, al final.
select pg_temp.afirmar((pg_temp.ids(v3->'items'))[24:25] = array['c0000000-0000-4000-8000-000000000025', 'c0000000-0000-4000-8000-000000000024']::uuid[],
  'empate: id descendente')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3) q;
-- El empate CRUZA un borde de página (auditor-rls): solo vencidas, 16 por página → la página 1 termina en el 25 y la 2 es EXACTAMENTE el 24
-- (mismo vence_en que el cursor, id menor). Un cursor que ignorara el id perdería o repetiría esa fila.
select pg_temp.afirmar(jsonb_array_length(p1->'items') = 16 and (p1->>'hay_mas')::boolean
    and p1->'siguiente_cursor'->>'despues_id' = 'c0000000-0000-4000-8000-000000000025'
    and pg_temp.ids(p2->'items') = array['c0000000-0000-4000-8000-000000000024']::uuid[] and (p2->>'hay_mas')::boolean = false,
  'empate en el borde de página: la segunda página es exactamente el id 24')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 16) p1) q1,
  lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 16, (q1.p1->'siguiente_cursor'->>'despues_de')::timestamptz, (q1.p1->'siguiente_cursor'->>'despues_id')::uuid) p2) q2;
-- Primera fila de «Vencidas»: la que venció hace MENOS (1 h); última: la más vieja (30 h, el empate).
select pg_temp.afirmar(v3->'items'->0->>'titulo' = 'BANCO TAREA 1' and v3->'items'->16->>'titulo' in ('BANCO TAREA 24', 'BANCO TAREA 25')
  and jsonb_array_length(v3->'items') = 17 and (v3->>'solo_vencidas')::boolean,
  'Vencidas: lo que venció hace menos arriba, lo más viejo al final')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, true, 100) v3) q;
-- Primera fila de «Todas»: la de fecha más lejana (dentro de 8 h).
select pg_temp.afirmar(v3->'items'->0->>'titulo' = 'BANCO TAREA 23', 'Todas: lo de fecha más lejana arriba')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3) q;
-- Los ítems de la v3 llevan las claves de la v2 (identidad) y las mismas claves base que la v1.
select pg_temp.afirmar((select bool_and(i ? 'id' and i ? 'vendedor_id' and i ? 'tipo' and i ? 'titulo' and i ? 'vence_en' and i ? 'estado'
    and i ? 'referencia_tipo' and i ? 'lead_id' and i ? 'lead_nombre' and i->>'referencia_tipo' = 'lead' and i->>'lead_nombre' = 'BANCO LEAD DE V1')
  from jsonb_array_elements(v3->'items') i)
  and (select array_agg(k order by k) from jsonb_object_keys(v3) k) = (select array_agg(k order by k) from jsonb_object_keys(pv2) k)
  and (select array_agg(k order by k) from jsonb_object_keys(v3->'items'->0) k) = (select array_agg(k order by k) from jsonb_object_keys(pv2->'items'->0) k),
  'v3: mismas claves que la v2 (sin claves nuevas)')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v3_fn(a.v1, false, 100) v3, crm.gestion_diaria_pendientes_v2_fn(a.v1, false, 100) pv2) q;
-- La v2 sigue ASCENDENTE (bundles publicados) y con version 2.
select pg_temp.afirmar(pg_temp.ids(pv2->'items') = pg_temp.ids(v1p->'items') and pg_temp.estricta(pv2->'items', false) and (pv2->>'version')::int = 2,
  'v2 sigue ascendente y version 2')
from pr_actores a, lateral (select crm.gestion_diaria_pendientes_v2_fn(a.v1, false, 100) pv2, crm.gestion_diaria_pendientes_fn(a.v1, false, 100) v1p) q;
reset role;

-- 3. Recorrido paginado de la v3 (7 por página): 4 páginas, sin repetir ni saltar, descendente también ENTRE páginas,
--    cursor = última fila de la página, y cada página siguiente sólo trae filas anteriores al cursor.
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
create temporary table pr_ids(id uuid primary key, pagina int, n int, vence_en timestamptz);
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; fila record; ultima jsonb; begin
  loop
    p := crm.gestion_diaria_pendientes_v3_fn((select v1 from pr_actores), false, 7, c_fecha, c_id);
    n := n + 1;
    perform pg_temp.afirmar(pg_temp.estricta(p->'items', true), format('página %s descendente', n));
    perform pg_temp.afirmar((p->>'version')::int = 3 and (p->>'limite')::int = 7 and jsonb_array_length(p->'items') <= 7, format('página %s: forma', n));
    perform pg_temp.afirmar(c_fecha is null or (select bool_and(((i->>'vence_en')::timestamptz, (i->>'id')::uuid) < (c_fecha, c_id)) from jsonb_array_elements(p->'items') i),
      format('página %s: todo anterior al cursor', n));
    for fila in select x.value, x.ord from jsonb_array_elements(p->'items') with ordinality x(value, ord) loop
      insert into pr_ids values ((fila.value->>'id')::uuid, n, fila.ord, (fila.value->>'vence_en')::timestamptz);
    end loop;
    ultima := p->'items'->(jsonb_array_length(p->'items') - 1);
    exit when not (p->>'hay_mas')::boolean;
    perform pg_temp.afirmar((p->>'hay_mas')::boolean = (jsonb_array_length(p->'items') = 7) and p->'siguiente_cursor' = jsonb_build_object('despues_de', ultima->'vence_en', 'despues_id', ultima->'id'),
      format('página %s: hay_mas sólo con página llena y cursor = última fila', n));
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 10, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 4 and (select count(*) from pr_ids) = 25, format('recorrido completo (%s páginas, %s filas)', n, (select count(*) from pr_ids)));
end $$;
select pg_temp.afirmar(bool_and(ok), 'descendente entre páginas') from (
  select (vence_en, id) < (lag(vence_en) over w, lag(id) over w) ok from pr_ids window w as (order by pagina, n)) x where ok is not null;
reset role;
select pg_temp.afirmar((select count(*) from pr_ids) = count(*) and bool_and(t.id in (select id from pr_ids)),
  'el recorrido es exactamente el conjunto de pendientes activas de v1')
from pr_actores a, crm.tareas t where t.vendedor_id = a.v1 and t.activo and t.estado = 'pendiente';
-- Solo vencidas, paginado (5 por página): 17 filas en 4 páginas, todas anteriores a pendientes_al y descendentes.
select pg_temp.como(sup1) from pr_actores;
set local role authenticated;
do $$ declare p jsonb; c_fecha timestamptz; c_id uuid; n int := 0; filas int := 0; begin
  loop
    p := crm.gestion_diaria_pendientes_v3_fn((select v1 from pr_actores), true, 5, c_fecha, c_id);
    n := n + 1; filas := filas + jsonb_array_length(p->'items');
    perform pg_temp.afirmar(pg_temp.estricta(p->'items', true) and (p->>'solo_vencidas')::boolean
      and (select bool_and((i->>'vence_en')::timestamptz < (p->>'pendientes_al')::timestamptz) from jsonb_array_elements(p->'items') i),
      format('vencidas página %s', n));
    perform pg_temp.afirmar((p#>>'{resumen,tareas_vencidas}')::int = 17 and (p#>>'{resumen,tareas_pendientes}')::int = 25, 'vencidas: resumen previo al filtro');
    exit when not (p->>'hay_mas')::boolean;
    c_fecha := (p#>>'{siguiente_cursor,despues_de}')::timestamptz; c_id := (p#>>'{siguiente_cursor,despues_id}')::uuid;
    perform pg_temp.afirmar(n < 10, 'el cursor debe terminar');
  end loop;
  perform pg_temp.afirmar(n = 4 and filas = 17, format('vencidas: %s páginas, %s filas', n, filas));
end $$;
reset role;

-- 4. Quién puede: Gerencia (toda la operación, supervisor_id = quien consulta); sup2 no lee a v1; analista, coordinación,
--    uid sin rol y sin identidad: 42501 en la v3 y en el núcleo de 6; anon: sin EXECUTE.
select pg_temp.como(gerente) from pr_actores;
set local role authenticated;
select pg_temp.afirmar(p->>'supervisor_id' = gerente::text and p->>'analista_id' = v1::text and jsonb_array_length(p->'items') = 25 and pg_temp.estricta(p->'items', true),
  'Gerencia lee a v1 en la v3') from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(v1, false, 100) p) q;
select pg_temp.afirmar(jsonb_array_length(p->'items') = 1 and p->'items'->0->>'vendedor_id' = ajeno::text, 'Gerencia lee al ajeno')
from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(ajeno, false, 100) p) q;
reset role;
select pg_temp.como(sup2) from pr_actores;
set local role authenticated;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', v1)) from pr_actores;
select pg_temp.afirmar(jsonb_array_length(p->'items') = 1 and p->'items'->0->>'titulo' = 'BANCO TAREA AJENO' and p->>'supervisor_id' = sup2::text, 'sup2 lee a su analista')
from pr_actores, lateral (select crm.gestion_diaria_pendientes_v3_fn(ajeno, false, 100) p) q;
reset role;
do $$ declare actor uuid; begin
  for actor in select unnest(array[v1, v2, coordinador, nadie, null]) from pr_actores loop
    perform pg_temp.como(actor);
    execute 'set local role authenticated';
    perform pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', (select v1 from pr_actores)));
    perform pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null,true)', (select v1 from pr_actores)));
    execute 'reset role';
  end loop;
end $$;
select pg_temp.afirmar(not has_function_privilege('anon', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'EXECUTE')
  and has_function_privilege('authenticated', 'crm.gestion_diaria_pendientes_v3_fn(uuid,boolean,integer,timestamptz,uuid)', 'EXECUTE'),
  'ACL: anon y service_role sin EXECUTE; authenticated con EXECUTE');
select pg_temp.como(sup1) from pr_actores;
set local role anon;
select pg_temp.denegada(format('select crm.gestion_diaria_pendientes_v3_fn(%L)', v1)) from pr_actores;
select pg_temp.denegada(format('select private.gestion_diaria_pendientes_core(%L,false,25,null,null,true)', v1)) from pr_actores;
reset role;

-- 5. La cola del analista: SOLO cambió el ORDER BY (el resto del cuerpo, al byte) y el orden nuevo es el pedido.
select pg_temp.afirmar(md5(replace(replace(p.prosrc,
$nuevo$  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA entre grupos;
  -- dentro de Vencidas, Sin primer intento y Sin conversación va primero lo más reciente
  -- (Miguel, 20/10/2026) y Hoy sigue por hora; gestionados/programados quedan detrás y el
  -- último guardado queda último.
$nuevo$, $viejo$  -- Orden completo ANTES del límite. Pendientes conservan la prioridad SLA;
  -- gestionados/programados quedan detrás y el último guardado queda último.
$viejo$),
$nuevo$    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'='tarea_hoy' then (f.value->>'referencia_en')::timestamptz end nulls last,
    case when f.value->>'estado_trabajo'='pendiente' and f.value->>'grupo'<>'tarea_hoy' then (f.value->>'referencia_en')::timestamptz end desc nulls last,
$nuevo$, $viejo$    case when f.value->>'estado_trabajo'='pendiente' then (f.value->>'referencia_en')::timestamptz end nulls last,
$viejo$)) = '2679f956c5bb271d3aac847b84690592', 'cola: fuera del ORDER BY, el cuerpo es el vivo al byte')
from pg_proc p where p.oid = 'crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)'::regprocedure;
-- Filas controladas: se sustituye el ayudante privado SOLO dentro de esta transacción (rollback al final).
create or replace function private.gestion_diaria_cola_filas(p_actor uuid, p_rol text, p_ahora timestamptz)
returns jsonb language sql stable security invoker set search_path = '' as $$
  select jsonb_build_array(
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a1','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '2 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a2','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',p_ahora + interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000a3','grupo','primera_atencion','estado_trabajo','pendiente','referencia_en',null,'ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000b1','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '5 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','cliente','clave','tarea:00000000-0000-4000-8000-0000000000b2','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000b3','grupo','tarea_vencida','estado_trabajo','pendiente','referencia_en',p_ahora - interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000c1','grupo','tarea_hoy','estado_trabajo','pendiente','referencia_en',p_ahora + interval '6 hours','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','cliente','clave','tarea:00000000-0000-4000-8000-0000000000c2','grupo','tarea_hoy','estado_trabajo','pendiente','referencia_en',p_ahora + interval '1 hour','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000d1','grupo','sin_conversacion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '20 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000d2','grupo','sin_conversacion','estado_trabajo','pendiente','referencia_en',p_ahora - interval '8 days','ultima_gestion',null,'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e1','grupo','tarea_vencida','estado_trabajo','gestionado','referencia_en',p_ahora - interval '1 hour','ultima_gestion',jsonb_build_object('en',p_ahora - interval '10 minutes'),'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e2','grupo','primera_atencion','estado_trabajo','gestionado','referencia_en',p_ahora - interval '1 hour','ultima_gestion',jsonb_build_object('en',p_ahora - interval '30 minutes'),'proxima_tarea',null),
    jsonb_build_object('tipo','lead','clave','lead:00000000-0000-4000-8000-0000000000e3','grupo','tarea_hoy','estado_trabajo','programado','referencia_en',p_ahora + interval '3 hours','ultima_gestion',null,'proxima_tarea',jsonb_build_object('vence_en',p_ahora + interval '3 hours'))
  )
$$;
select pg_temp.como(v1) from pr_actores;
set local role authenticated;
select pg_temp.afirmar((select array_agg(i->>'clave' order by n) from jsonb_array_elements(c->'items') with ordinality x(i, n)) = array[
    -- Sin primer intento: lo más reciente primero (la referencia futura, luego la de hace 2 días), sin referencia al final.
    'lead:00000000-0000-4000-8000-0000000000a2', 'lead:00000000-0000-4000-8000-0000000000a1', 'lead:00000000-0000-4000-8000-0000000000a3',
    -- Vencidas: lo que venció hace menos primero; empate exacto por clave (collate "C": «lead:» < «tarea:»); la de hace 5 días al final.
    'lead:00000000-0000-4000-8000-0000000000b3', 'tarea:00000000-0000-4000-8000-0000000000b2', 'lead:00000000-0000-4000-8000-0000000000b1',
    -- Hoy: por hora, lo más próximo primero.
    'tarea:00000000-0000-4000-8000-0000000000c2', 'lead:00000000-0000-4000-8000-0000000000c1',
    -- Sin conversación: lo más reciente primero (8 días antes que 20).
    'lead:00000000-0000-4000-8000-0000000000d2', 'lead:00000000-0000-4000-8000-0000000000d1',
    -- Gestionados/programados detrás, el último guardado al final (como antes).
    'lead:00000000-0000-4000-8000-0000000000e3', 'lead:00000000-0000-4000-8000-0000000000e2', 'lead:00000000-0000-4000-8000-0000000000e1']
  and (c->>'total')::int = 13 and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000a2' and c->>'siguiente' = 'lead:00000000-0000-4000-8000-0000000000a1'
  and (c#>>'{totales,todo,pendientes}')::int = 10 and (c->>'vuelta_completa')::boolean = false,
  'cola: el orden nuevo del día')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('todo', 0, 200) c) q;
-- Filtro «Vencidas», 2 por página: la primera página trae las dos más recientes; elegida la primera, «siguiente» es la segunda.
select pg_temp.afirmar((select array_agg(i->>'clave' order by n) from jsonb_array_elements(c->'items') with ordinality x(i, n))
    = array['lead:00000000-0000-4000-8000-0000000000b3', 'tarea:00000000-0000-4000-8000-0000000000b2']
  and (c->>'total')::int = 4 and c->>'filtro' = 'tarea_vencida' and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000b3'
  and c->>'siguiente' = 'tarea:00000000-0000-4000-8000-0000000000b2',
  'cola: filtro Vencidas paginado con el orden nuevo')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('tarea_vencida', 0, 2) c) q;
-- Anclar por clave sigue funcionando: la página de la vencida más vieja es la segunda (posición 2 → página 1 con límite 2).
select pg_temp.afirmar((c->>'pagina')::int = 1 and c->>'elegido' = 'lead:00000000-0000-4000-8000-0000000000b1' and c->>'siguiente' = 'lead:00000000-0000-4000-8000-0000000000b3',
  'cola: ancla por clave con el orden nuevo')
from pr_actores a, lateral (select crm.gestion_diaria_cola_trabajo_fn('tarea_vencida', 0, 2, 'lead:00000000-0000-4000-8000-0000000000b1') c) q;
reset role;
select pg_temp.como(gerente) from pr_actores;
set local role authenticated;
select pg_temp.denegada('select crm.gestion_diaria_cola_trabajo_fn()');
reset role;

-- 6. El gate H3: sus filas de pendientes en verde con el sello nuevo (su veredicto completo depende de gates ajenos; se muestra).
do $$ declare v_firma text; v_hash text; v text; begin
  for v_firma, v_hash in select * from (values
    ('private.gestion_diaria_equipo_ambito(uuid)', 'af06caf4d0ea5d392d9c36f069b3501b'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)', '681d76d982dbba77c2cc556e725ead0a'),
    ('private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid,boolean)', 'b55e6776ebfdbb2fdd61789ef06b26b6'),
    ('crm.gestion_diaria_pendientes_fn(uuid,boolean,integer,timestamptz,uuid)', 'd69dd41dbd7106283584e7d6b1cc9e1a')
  ) as firmas(firma, huella) loop
    perform pg_temp.afirmar(exists (select 1 from pg_proc p where p.oid = to_regprocedure(v_firma)
      and not p.prosecdef and p.provolatile = 's' and p.proowner = 'postgres'::regrole and p.proconfig = array['search_path=""']
      and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
      and not has_function_privilege('service_role', p.oid, 'EXECUTE') and md5(pg_get_functiondef(p.oid)) = v_hash), 'gate H3 fila ' || v_firma);
  end loop;
  begin perform private.assert_gestion_diaria_pendientes(); v := 'OK'; exception when others then v := sqlerrm; end;
  raise notice 'veredicto del gate H3 en el banco: %', v;
  perform pg_temp.afirmar(v not like '%gestion_diaria_pendientes%', 'el gate H3 no señala a pendientes');
end $$;

select 'PENDIENTES_RECIENTES_OK' as resultado;
rollback;
