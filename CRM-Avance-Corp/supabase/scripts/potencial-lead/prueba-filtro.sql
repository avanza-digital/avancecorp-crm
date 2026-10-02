-- Prueba sintética de 20261001212341_crm_cartera_filtro_potencial (fase 3, entrega B).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- Necesita delante la función ANTERIOR (la firma de 13) como pg_temp.cartera_filtrada_anterior:
--   cat banco/anterior-13.sql prueba-filtro.sql | docker exec -i -e PGPASSWORD=postgres <banco> \
--     psql -U supabase_admin -h 127.0.0.1 -d postgres
-- (lo hace banco/ciclo-fase3b.sh). ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role`
-- (tumba Postgres 17.6 con plan_filter): los permisos se leen del catálogo.
--
-- Mundo (el de prueba-lectura.sql más un lead): gerencia G · supervisor S1 con sub-supervisor S1n ·
-- analista V1 (de S1) y V1n (de S1n) · supervisor S2 con analista V2 · coordinador C (opera el
-- reparto) · directorio D · X con equipo inactivo · DH directorio HISTÓRICO · XP con el perfil
-- inactivo · P usuario solo del portal · DM pareja desalineada.
--   L1  V1  contactado  estrella                L1n V1n nuevo       tibio
--   L2  V2  contactado  estrella                LP  parqueado en S1 frío
--   LC  V1  convertido ayer, estrella           LD  V1  descartado  tibio
--   LI  V1  INACTIVO    estrella (nadie lo ve)  L3  V1  contactado  sin marca
--   LPV parqueado con «supervisor» V1, sin marca    LK  V1  contactado  tibio (bajó sola)
--   LZ  V1  contactado  estrella                LS  SIN ASIGNAR, sin marca
--   LSM SIN ASIGNAR (sin analista ni supervisor), tibio: solo lo ven gerencia y directorio. Dentro
--       de crm.resumen_cartera_fn (DEFINER) entra en la bandeja de quien opera el reparto, pero su
--       marca NO se le entrega: coordinación no recibe conteos por nivel.
--   LCS V2 convertido ayer, sin marca · LDS V2 descartado, sin marca (los cerrados también cuentan)
--   LCV V2 convertido hace 60 días, estrella: fuera de la ventana de 45 días, no aparece ni cuenta.
--   Además: L1 tiene tenencia y un contacto posterior (con gestión) y LK fue reasignado.
begin;
set local lock_timeout = '5s';

do $guarda$
begin
  if to_regprocedure('pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') is null then
    raise exception 'FILTRO: falta pg_temp.cartera_filtrada_anterior; corre: cat banco/anterior-13.sql prueba-filtro.sql | psql …';
  end if;
  -- La «anterior» es de verdad la anterior: el cuerpo de la firma de 13 de 20261001154153.
  if (select md5(p.prosrc) from pg_proc p
       where p.oid = to_regprocedure('pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'))
     is distinct from 'cb7741fe73fe4da698943d78369bc4cc' then
    raise exception 'FILTRO: la función de comparación no es el cuerpo de la firma de 13';
  end if;
end;
$guarda$;

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X'), ('DH'), ('XP'), ('P'), ('DM');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('LSM'), ('LCS'), ('LDS'), ('LCV');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@filtro.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'FILTRO ' || k, case when k in ('D', 'DH', 'DM') then 'directorio' when k = 'G' then 'admin' else 'analista' end, k <> 'XP' from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('G'), 'gerencia', null, true),
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('S1n'), 'supervisor', pg_temp.a('S1'), true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('V1n'), 'vendedor', pg_temp.a('S1n'), true),
  (pg_temp.a('S2'), 'supervisor', null, true),
  (pg_temp.a('V2'), 'vendedor', pg_temp.a('S2'), true),
  (pg_temp.a('C'), 'coordinador', null, true),
  (pg_temp.a('D'), 'directorio', null, true),
  (pg_temp.a('X'), 'vendedor', pg_temp.a('S1'), false),
  (pg_temp.a('XP'), 'vendedor', pg_temp.a('S1'), true),
  (pg_temp.a('DM'), 'vendedor', pg_temp.a('S1'), true);
-- actualizado_en escalonado: el orden de la lista (actualizado_en desc, id) queda determinado.
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte, convertido_en, actualizado_en) values
  (pg_temp.l('LCS'), 'FILTRO LCS', '+51987650014', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V2'),  null, true, null, now() - interval '1 day', now() - interval '14 minutes'),
  (pg_temp.l('LDS'), 'FILTRO LDS', '+51987650015', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V2'),  null, true, 'sin_interes', null, now() - interval '15 minutes'),
  (pg_temp.l('LCV'), 'FILTRO LCV', '+51987650016', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V2'),  null, true, null, now() - interval '60 days', now() - interval '16 minutes'),
  (pg_temp.l('L1'),  'FILTRO L1',  '+51987650001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '1 minute'),
  (pg_temp.l('L1n'), 'FILTRO L1N', '+51987650002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null, null, now() - interval '2 minutes'),
  (pg_temp.l('L2'),  'FILTRO L2',  '+51987650003', 'landing', 30000, 'USD', 'contactado', pg_temp.a('V2'),  null, true, null, null, now() - interval '3 minutes'),
  (pg_temp.l('LP'),  'FILTRO LP',  '+51987650004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null, null, now() - interval '4 minutes'),
  (pg_temp.l('LC'),  'FILTRO LC',  '+51987650005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null, now() - interval '1 day', now() - interval '5 minutes'),
  (pg_temp.l('LD'),  'FILTRO LD',  '+51987650006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes', null, now() - interval '6 minutes'),
  (pg_temp.l('LI'),  'FILTRO LI',  '+51987650007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null, null, now() - interval '7 minutes'),
  (pg_temp.l('L3'),  'FILTRO L3',  '+51987650008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '8 minutes'),
  (pg_temp.l('LPV'), 'FILTRO LPV', '+51987650009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null, null, now() - interval '9 minutes'),
  (pg_temp.l('LK'),  'FILTRO LK',  '+51987650010', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '10 minutes'),
  (pg_temp.l('LZ'),  'FILTRO LZ',  '+51987650011', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null, null, now() - interval '11 minutes'),
  (pg_temp.l('LS'),  'FILTRO LS',  '+51987650012', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null, null, now() - interval '12 minutes'),
  (pg_temp.l('LSM'), 'FILTRO LSM', '+51987650013', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null, null, now() - interval '13 minutes');
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values
  (pg_temp.l('L1'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('L1n'), 'tibio',    'manual',    pg_temp.a('S1n'), now()),
  (pg_temp.l('L2'),  'estrella', 'manual',    pg_temp.a('V2'),  now()),
  (pg_temp.l('LP'),  'frio',     'manual',    pg_temp.a('S1'),  now()),
  (pg_temp.l('LC'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LD'),  'tibio',    'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LI'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LK'),  'tibio',    'caducidad', pg_temp.a('V1'),  now()),
  (pg_temp.l('LZ'),  'estrella', 'manual',    pg_temp.a('V1'),  now()),
  (pg_temp.l('LSM'), 'tibio',    'manual',    pg_temp.a('S1'),  now()),
  (pg_temp.l('LCV'), 'estrella', 'manual',    pg_temp.a('V2'),  now());
-- L1: su analista lo recibió hace dos días y lo llamó ayer (con gestión). LK: pasó por V2 antes.
update crm.leads set tenencia_desde = now() - interval '2 days' where id = pg_temp.l('L1');
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en, metadata) values
  (pg_temp.l('L1'), 'llamada_realizada', 'prueba del filtro', pg_temp.a('V1'), now() - interval '1 day', '{}'::jsonb),
  (pg_temp.l('LK'), 'reasignacion', 'prueba del filtro', null, now() - interval '3 days',
   jsonb_build_object('vendedor_anterior', pg_temp.a('V2'), 'vendedor_nuevo', pg_temp.a('V1')));
-- crm.resumen_cartera_fn (el envoltorio) exige un peso del referido: un banco sin datos no lo tiene.
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  select date '2026-01-01', 0.5, 'FILTRO: fila sintética del banco' where not exists (select 1 from crm.conversion_pesos);
set local session_replication_role = origin;

-- Identidad de la sesión, en las DOS formas (producción lee request.jwt.claims; la imagen del banco
-- solo request.jwt.claim.sub).
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- La cartera, como la llama la pantalla: authenticated. `p_args` es el texto de los argumentos.
-- Devuelve el sobre o {"error": SQLSTATE}. `p_fn` permite llamar a la ANTERIOR con lo mismo.
create function pg_temp.cartera(p_actor uuid, p_args text default '', p_fn text default 'crm.cartera_filtrada_fn') returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    execute 'select ' || p_fn || '(' || p_args || ')' into v;
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;
-- El resumen por el envoltorio DEFINER (ahí la cartera corre sin RLS y entra la bandeja del reparto).
create function pg_temp.envoltorio(p_actor uuid) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.resumen_cartera_fn();
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;
-- Las claves de los leads de una respuesta, en el ORDEN en que vienen.
create function pg_temp.claves(p_sobre jsonb) returns text language sql as $$
  select case when p_sobre ? 'error' then 'error ' || (p_sobre ->> 'error') else coalesce((
    select string_agg(d.k, ',' order by i.ord)
    from jsonb_array_elements(p_sobre -> 'items') with ordinality i(item, ord)
    join lds d on d.id = (i.item ->> 'id')::uuid), '(ninguno)') end
$$;
-- Las mismas claves en orden alfabético (para comparar conjuntos).
create function pg_temp.conjunto(p_sobre jsonb) returns text language sql as $$
  select case when p_sobre ? 'error' then 'error ' || (p_sobre ->> 'error') else coalesce((
    select string_agg(d.k, ',' order by d.k)
    from jsonb_array_elements(p_sobre -> 'items') i join lds d on d.id = (i ->> 'id')::uuid), '(ninguno)') end
$$;
-- El bloque de potencial de un resumen: filtro · E/T/F/S · vivos.
create function pg_temp.pot(p_resumen jsonb) returns text language sql as $$
  select case when p_resumen is null then '(sin resumen)'
    when p_resumen ? 'error' then 'error ' || (p_resumen ->> 'error')
    when not (p_resumen ? 'potencial') then '(sin clave) v=' || (p_resumen #>> '{totales,vivos}')
    else coalesce(p_resumen #>> '{potencial,filtro}', '-')
      || ' E' || (p_resumen #>> '{potencial,estrella}') || ' T' || (p_resumen #>> '{potencial,tibio}')
      || ' F' || (p_resumen #>> '{potencial,frio}') || ' S' || (p_resumen #>> '{potencial,sin_marca}')
      || ' v=' || (p_resumen #>> '{totales,vivos}') end
$$;
-- Lo que la RLS REAL de crm.leads deja ver a un actor (la vara independiente).
create function pg_temp.ve_rls(p_actor uuid) returns uuid[] language plpgsql as $f$
declare v_ids uuid[] := (select array_agg(id) from lds); v_vistos uuid[];
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select array_agg(l.id) into v_vistos from crm.leads l where l.id = any (v_ids);
  exception when others then
    reset role;
    return null;
  end;
  reset role;
  return coalesce(v_vistos, '{}');
end $f$;
-- ORÁCULO independiente: con la RLS real y la tabla de marcas (leída como administrador), lo que
-- debería devolver la cartera para un actor y un nivel: «claves | E T F S» de lo que ve.
create function pg_temp.oraculo(p_actor uuid, p_nivel text default null) returns text language sql as $$
  with visibles as (
    select d.k, p.nivel::text as nivel
    from unnest(pg_temp.ve_rls(p_actor)) v(id)
    join lds d on d.id = v.id
    join crm.leads l on l.id = d.id
    left join crm.lead_potencial p on p.lead_id = d.id
    -- La ventana operativa de la cartera: sin fechas, un convertido de más de 45 días no entra.
    where l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days'
  )
  select coalesce((select string_agg(k, ',' order by k) from visibles
                    where p_nivel is null or (p_nivel = 'sin_marca' and nivel is null) or nivel = p_nivel), '(ninguno)')
    || ' | E' || (select count(*) from visibles where nivel = 'estrella')
    || ' T' || (select count(*) from visibles where nivel = 'tibio')
    || ' F' || (select count(*) from visibles where nivel = 'frio')
    || ' S' || (select count(*) from visibles where nivel is null)
$$;
-- Lo mismo, tal como lo devuelve la cartera.
create function pg_temp.respuesta(p_actor uuid, p_nivel text default null) returns text language sql as $$
  with s as (select pg_temp.cartera(p_actor, 'p_limite => 200' || coalesce(', p_potencial => ' || quote_literal(p_nivel), '')) as v)
  select case when s.v ? 'error' then 'error ' || (s.v ->> 'error') else pg_temp.conjunto(s.v)
    || ' | E' || (s.v #>> '{resumen,potencial,estrella}') || ' T' || (s.v #>> '{resumen,potencial,tibio}')
    || ' F' || (s.v #>> '{resumen,potencial,frio}') || ' S' || (s.v #>> '{resumen,potencial,sin_marca}') end
  from s
$$;
-- ¿Un resumen trae sus cuatro conteos y el total, y los cuatro SUMAN el total? En positivo y con
-- `is true`: una respuesta nula, con error, sin el bloque o con el bloque vacío NO es buena (Codex
-- f3b r1 y r2: comparar con `is distinct from` daba por buenos dos NULL).
create function pg_temp.resumen_bueno(p_resumen jsonb) returns boolean language sql as $$
  select coalesce(
    p_resumen is not null and not (p_resumen ? 'error')
    and (p_resumen #>> '{potencial,estrella}')::int + (p_resumen #>> '{potencial,tibio}')::int
        + (p_resumen #>> '{potencial,frio}')::int + (p_resumen #>> '{potencial,sin_marca}')::int
        = (p_resumen #>> '{totales,vivos}')::int, false)
$$;
-- Los ids que el ayudante entrega a un actor (llamado como administrador con su sesión). NULL si
-- falla: quien compara tiene que distinguir «no entrega nada» de «no se pudo preguntar».
create function pg_temp.ayudante_ids(p_actor uuid) returns uuid[] language plpgsql as $f$
declare v uuid[];
begin
  perform pg_temp.sesion(p_actor);
  begin
    select coalesce(array_agg(m.lead_id), '{}') into v from private.cartera_potencial_fn() m;
    return v;
  exception when others then
    return null;
  end;
end $f$;
-- El ayudante, llamado como administrador con la sesión del actor: las claves que devuelve.
create function pg_temp.ayudante(p_actor uuid) returns text language plpgsql as $f$
declare v text;
begin
  perform pg_temp.sesion(p_actor);
  begin
    select coalesce(string_agg(d.k || ':' || left(m.nivel, 1), ',' order by d.k), '(ninguno)') into v
    from private.cartera_potencial_fn() m join lds d on d.id = m.lead_id;
    return v;
  exception when others then
    return 'error ' || sqlstate;
  end;
end $f$;

do $prueba$
declare
  v jsonb;
  w jsonb;
  v_n integer;
  ak text;
  nv text;
  ca text;
  v_txt text;
  v_iguales integer := 0;
  v_total integer := 0;
  v_dist text := '';
  f14 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)';
  ayu constant text := 'private.cartera_potencial_fn()';
  llamadas constant text[] := array[
    $c$p_limite => 200$c$,
    $c$p_limite => 2$c$,
    $c$p_limite => 200, p_etapa => 'contactado'$c$,
    $c$p_limite => 200, p_etapa => 'descartado'$c$,
    $c$p_limite => 200, p_texto => 'filtro l'$c$,
    $c$p_limite => 200, p_origen => 'landing'$c$,
    $c$p_limite => 200, p_procedencia => 'sistema'$c$,
    $c$p_limite => 200, p_reasignados => true$c$,
    $c$p_limite => 200, p_sin_asignar => true$c$,
    $c$p_limite => 200, p_gestion => 'sin_gestion'$c$,
    $c$p_limite => 200, p_gestion => 'con_gestion'$c$,
    $c$p_limite => 200, p_desde => (now() at time zone 'America/Lima')::date - 30, p_hasta => (now() at time zone 'America/Lima')::date$c$,
    $c$p_limite => 3, p_antes_de => now() - interval '4 minutes', p_antes_id => '00000000-0000-4000-8000-000000000000'$c$,
    $c$200, null, null, 'nuevo', null, false, null, null, null, null, null, false, null$c$
  ];
begin
  -- ── Permisos (del catálogo: nunca se llama sin EXECUTE bajo set role) ──
  perform pg_temp.esperar('EXECUTE de la cartera: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', f14, 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', f14, 'EXECUTE')::text || '/' || has_function_privilege('service_role', f14, 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE del ayudante: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', ayu, 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', ayu, 'EXECUTE')::text || '/' || has_function_privilege('service_role', ayu, 'EXECUTE')::text);
  perform pg_temp.esperar('el ayudante: DEFINER, STABLE, solo search_path vacío, dueño postgres', 'true/s/{"search_path=\"\""}/postgres',
    (select p.prosecdef::text || '/' || p.provolatile::text || '/' || p.proconfig::text || '/' || p.proowner::regrole::text
       from pg_proc p where p.oid = to_regprocedure(ayu)));
  perform pg_temp.esperar('la cartera sigue INVOKER, STABLE y con una sola firma', 'false/s/1',
    (select p.prosecdef::text || '/' || p.provolatile::text from pg_proc p where p.oid = to_regprocedure(f14)) || '/' ||
    (select count(*)::text from pg_proc p where p.proname = 'cartera_filtrada_fn' and p.pronamespace = 'crm'::regnamespace));
  perform pg_temp.esperar('la tabla de la marca sigue sin SELECT para la API (ni por columna)', 'false/false/false/false',
    has_table_privilege('authenticated', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_any_column_privilege('authenticated', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_table_privilege('anon', 'crm.lead_potencial', 'SELECT')::text || '/' ||
    has_any_column_privilege('anon', 'crm.lead_potencial', 'SELECT')::text);
  perform pg_temp.esperar('el rol de puente de métricas no ejecuta ni la cartera ni el ayudante', 'false/false',
    has_function_privilege('crm_metricas_bridge', f14, 'EXECUTE')::text || '/' || has_function_privilege('crm_metricas_bridge', ayu, 'EXECUTE')::text);

  -- ══ Bandera APAGADA: todo como antes ══
  update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
  v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200');
  perform pg_temp.esperar('apagada: V1 ve sus 7 leads, en su orden', 'L1,LC,LD,L3,LPV,LK,LZ', pg_temp.claves(v));
  perform pg_temp.esperar('apagada: el resumen NO trae la clave potencial', '(sin clave) v=7', pg_temp.pot(v -> 'resumen'));
  perform pg_temp.esperar('apagada: pedir el filtro → 55000', 'error 55000', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('apagada: pedir «sin_marca» → 55000', 'error 55000', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('apagada: un valor inválido sigue siendo 22023 (se valida antes)', 'error 22023', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_potencial => 'caliente'$c$)));
  perform pg_temp.esperar('apagada: p_potencial null explícito pasa', 'L1,L3,LC,LD,LK,LPV,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200, p_potencial => null')));
  perform pg_temp.esperar('apagada: el ayudante no devuelve nada (gerencia)', '(ninguno)', pg_temp.ayudante(pg_temp.a('G')));
  perform pg_temp.esperar('apagada: el envoltorio responde y tampoco trae la clave', '(sin clave) v=7', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform pg_temp.esperar('apagada: sin sesión → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(null, 'p_limite => 200')));
  -- Igualdad con la ANTERIOR, byte a byte salvo generado_en.
  foreach ak in array array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    foreach ca in array llamadas loop
      v := pg_temp.cartera(pg_temp.a(ak), ca, 'pg_temp.cartera_filtrada_anterior');
      w := pg_temp.cartera(pg_temp.a(ak), ca);
      v_total := v_total + 1;
      if v is not null and not (v ? 'error') and (v - 'generado_en') = (w - 'generado_en') then v_iguales := v_iguales + 1;
      else v_dist := left(v_dist || ' · ' || ak || ' [' || ca || ']', 600); end if;
    end loop;
  end loop;
  perform pg_temp.esperar('apagada: la respuesta es la de la firma de 13 (10 actores × 14 llamadas)', '140 de 140', v_iguales || ' de ' || v_total || v_dist);

  -- ══ Bandera ENCENDIDA ══
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

  -- Admisión y validación.
  perform pg_temp.esperar('sin sesión → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(null, $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('X (equipo inactivo) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('X'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('XP (perfil inactivo) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('XP'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('P (solo portal) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('P'), $c$p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('DM (pareja desalineada) → 42501', 'error 42501', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('DM'), $c$p_potencial => 'estrella'$c$)));
  foreach nv in array array['caliente', 'ESTRELLA', 'Tibio', '', ' frio', 'sin marca', 'todos'] loop
    perform pg_temp.esperar('valor inválido «' || nv || '» → 22023', 'error 22023',
      pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_potencial => ' || quote_literal(nv))));
  end loop;

  -- Forma: una clave nueva en el resumen y ninguna más; las filas, como siempre.
  v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200');
  w := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200', 'pg_temp.cartera_filtrada_anterior');
  perform pg_temp.esperar('encendida: las claves de arriba son las de la anterior', 'true',
    ((select array_agg(x order by x) from jsonb_object_keys(v) x) = (select array_agg(x order by x) from jsonb_object_keys(w) x))::text);
  perform pg_temp.esperar('encendida: el resumen gana SOLO la clave potencial', 'potencial',
    (select string_agg(x, ',' order by x) from jsonb_object_keys(v -> 'resumen') x where not (w -> 'resumen') ? x));
  perform pg_temp.esperar('encendida: las claves de potencial son cinco', 'estrella,filtro,frio,sin_marca,tibio',
    (select string_agg(x, ',' order by x) from jsonb_object_keys(v #> '{resumen,potencial}') x));
  perform pg_temp.esperar('encendida: las filas tienen las claves de siempre (sin potencial_nivel)', 'true/false',
    ((select array_agg(x order by x) from jsonb_object_keys(v #> '{items,0}') x) = (select array_agg(x order by x) from jsonb_object_keys(w #> '{items,0}') x))::text
    || '/' || ((v #> '{items,0}') ? 'potencial_nivel')::text);
  perform pg_temp.esperar('encendida y sin filtro: quitando resumen.potencial, es la respuesta anterior', 'true',
    ((v - 'generado_en') #- '{resumen,potencial}' = (w - 'generado_en'))::text);
  perform pg_temp.esperar('encendida: omitido y null explícito dan lo mismo', 'true',
    ((v - 'generado_en') = (pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200, p_potencial => null') - 'generado_en'))::text);

  -- Lo que ve cada rol, sin filtro: lista, conteos por nivel y total.
  perform pg_temp.esperar('G sin filtro (el convertido de hace 60 días no entra)', 'L1,L1n,L2,L3,LC,LCS,LD,LDS,LK,LP,LPV,LS,LSM,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200')));
  perform pg_temp.esperar('G: conteos (los cerrados sin marca cuentan en «sin marca»)', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('G'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('D (directorio) ve lo mismo que gerencia', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('D'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('DH (directorio histórico) igual', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.cartera(pg_temp.a('DH'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1 sin filtro', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200')));
  perform pg_temp.esperar('S1: conteos', '- E3 T3 F1 S2 v=9', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S1n: solo el lead de su analista', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('S1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1: conteos', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V1n: conteos', '- E0 T1 F0 S0 v=1', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1n'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V2: su estrella, un convertido y un descartado sin marca; el convertido viejo no cuenta', '- E1 T0 F0 S2 v=3', pg_temp.pot(pg_temp.cartera(pg_temp.a('V2'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('S2: conteos', '- E1 T0 F0 S2 v=3', pg_temp.pot(pg_temp.cartera(pg_temp.a('S2'), 'p_limite => 200') -> 'resumen'));
  perform pg_temp.esperar('V2 con sin_marca: los dos cerrados sin marca', 'LCS,LDS', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V2'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('V2 con estrella: el convertido de hace 60 días sigue fuera de la ventana', 'L2', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V2'), $c$p_limite => 200, p_potencial => 'estrella'$c$)));

  -- Cada nivel, rol por rol: la lista es la del nivel, el total es el del nivel, y los cuatro
  -- conteos NO cambian al elegir (se cuentan antes del filtro). Contra el oráculo de la RLS real.
  foreach ak in array array['G', 'D', 'DH', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    perform pg_temp.esperar(ak || ' sin filtro = oráculo (RLS real + tabla de marcas)', pg_temp.oraculo(pg_temp.a(ak)), pg_temp.respuesta(pg_temp.a(ak)));
    foreach nv in array array['estrella', 'tibio', 'frio', 'sin_marca'] loop
      perform pg_temp.esperar(ak || ' con ' || nv || ' = oráculo', pg_temp.oraculo(pg_temp.a(ak), nv), pg_temp.respuesta(pg_temp.a(ak), nv));
    end loop;
  end loop;
  -- Y a mano, para que el oráculo no sea la única vara.
  perform pg_temp.esperar('V1 con estrella', 'L1,LC,LZ', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1 con estrella: eco, conteos intactos y total del nivel', 'estrella E3 T2 F0 S2 v=3',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1 con tibio (uno manual y uno que bajó solo)', 'LD,LK', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1 con frio: ninguno, y el total es cero', 'frio E3 T2 F0 S2 v=0',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'frio'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1 con sin_marca', 'L3,LPV', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('S1 con frio: el parqueado en su bandeja', 'LP', pg_temp.claves(pg_temp.cartera(pg_temp.a('S1'), $c$p_limite => 200, p_potencial => 'frio'$c$)));
  perform pg_temp.esperar('G con tibio: incluye el sin asignar (lo ve por ser gerencia)', 'L1n,LD,LK,LSM', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('el inactivo LI (estrella) no aparece ni cuenta para nadie', 'false',
    (pg_temp.conjunto(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_potencial => 'estrella'$c$)) ~ 'LI')::text);

  -- El resto del resumen sale de la base YA filtrada (totales, capital, embudo), como con los demás filtros.
  v := pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'estrella'$c$);
  perform pg_temp.esperar('V1 estrella: abiertos, convertidos y capital asignado en soles', '2/1/70000',
    (v #>> '{resumen,totales,abiertos}') || '/' || (v #>> '{resumen,totales,convertidos}') || '/' || (v #>> '{resumen,capital,asignado,pen}'));
  perform pg_temp.esperar('V1 estrella: el embudo suma el total', '3',
    (select sum((e ->> 'n')::int)::text from jsonb_array_elements(v #> '{resumen,embudo}') e));

  -- Se combina con los demás filtros: los conteos respetan la etapa pedida.
  perform pg_temp.esperar('V1, contactado + estrella', 'L1,LZ', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_etapa => 'contactado', p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1, contactado: conteos de esa etapa', 'estrella E2 T1 F0 S1 v=2',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_etapa => 'contactado', p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('S1, sin asignar + frio', 'LP', pg_temp.claves(pg_temp.cartera(pg_temp.a('S1'), $c$p_limite => 200, p_sin_asignar => true, p_potencial => 'frio'$c$)));
  perform pg_temp.esperar('G, texto + tibio', 'LSM', pg_temp.claves(pg_temp.cartera(pg_temp.a('G'), $c$p_limite => 200, p_texto => 'filtro lsm', p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1, sin gestión + sin_marca (un parqueado no tiene gestión)', 'L3,LPV', pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'sin_gestion', p_potencial => 'sin_marca'$c$)));
  perform pg_temp.esperar('V1, con gestión + estrella: el que su analista ya llamó', 'L1',
    pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'con_gestion', p_potencial => 'estrella'$c$)));
  perform pg_temp.esperar('V1, con gestión: los conteos son los de esa base', 'estrella E1 T0 F0 S0 v=1',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_gestion => 'con_gestion', p_potencial => 'estrella'$c$) -> 'resumen'));
  perform pg_temp.esperar('V1, reasignados + tibio: el que vino de otro analista', 'LK',
    pg_temp.claves(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_reasignados => true, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('V1, reasignados + estrella: ninguno, y los conteos dicen por qué', 'estrella E0 T1 F0 S0 v=0',
    pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_reasignados => true, p_potencial => 'estrella'$c$) -> 'resumen'));
  -- Negativa cruzada: pedir el analista de OTRO equipo con un nivel no enseña nada ni cuenta nada.
  perform pg_temp.esperar('V1 pidiendo a V2 + estrella: nada y cuatro ceros', '(ninguno) / estrella E0 T0 F0 S0 v=0',
    (select pg_temp.conjunto(x.v) || ' / ' || pg_temp.pot(x.v -> 'resumen')
       from (select pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 200, p_vendedor_id => %L, p_potencial => 'estrella'$c$, pg_temp.a('V2'))) as v) x));

  -- El cursor recorre SOLO el nivel pedido, sin saltos ni repetidos.
  v := pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 2, p_potencial => 'estrella'$c$);
  perform pg_temp.esperar('cursor: primera página de estrella', 'L1,LC', pg_temp.claves(v));
  w := pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 2, p_potencial => 'estrella', p_antes_de => %L, p_antes_id => %L$c$,
    v #>> '{items,1,actualizado_en}', v #>> '{items,1,id}'));
  perform pg_temp.esperar('cursor: segunda página de estrella', 'LZ', pg_temp.claves(w));
  perform pg_temp.esperar('cursor: el total no depende de la página', '3/3', (v #>> '{resumen,totales,vivos}') || '/' || (w #>> '{resumen,totales,vivos}'));
  -- Con EMPATE de sello (LC y LZ a la misma hora) desempata el id: de uno en uno, salen los tres una vez.
  perform set_config('session_replication_role', 'replica', true);
  update crm.leads set actualizado_en = (select x.actualizado_en from crm.leads x where x.id = pg_temp.l('LC')) where id = pg_temp.l('LZ');
  perform set_config('session_replication_role', 'origin', true);
  v_txt := '';
  w := null;
  for v_n in 1..4 loop
    v := pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 1, p_potencial => ''estrella''' || coalesce(format(', p_antes_de => %L, p_antes_id => %L',
      w #>> '{items,0,actualizado_en}', w #>> '{items,0,id}'), ''));
    exit when jsonb_array_length(v -> 'items') = 0;
    v_txt := v_txt || case when v_txt = '' then '' else ',' end || pg_temp.claves(v);
    w := v;
  end loop;
  perform pg_temp.esperar('cursor con empate de sello: los tres, una vez cada uno', 'L1,LC,LZ',
    (select string_agg(x, ',' order by x) from regexp_split_to_table(v_txt, ',') x));
  perform pg_temp.esperar('cursor con empate: sin repetidos', '3', (select count(distinct x)::text from regexp_split_to_table(v_txt, ',') x));
  -- Un cursor con un id AJENO solo es una posición: no enseña ese lead ni otro nivel.
  perform pg_temp.esperar('cursor con el id de un lead ajeno: sigue sin enseñar nada fuera del nivel y del ámbito', 'true',
    (select bool_and(d.k in ('L1', 'LC', 'LZ'))::text
       from jsonb_array_elements(pg_temp.cartera(pg_temp.a('V1'), format($c$p_limite => 200, p_potencial => 'estrella', p_antes_de => %L, p_antes_id => %L$c$,
              now()::text, pg_temp.l('L2'))) -> 'items') i join lds d on d.id = (i ->> 'id')::uuid));

  -- El coordinador: por la API ve lo que la RLS le deja; dentro del envoltorio DEFINER entra la
  -- bandeja del reparto (LP, LPV, LS y LSM) y sus marcas tienen que contar.
  perform pg_temp.esperar('C (coordinación) por la API: su RLS no le deja ver leads y no recibe conteos por nivel', '(ninguno) / (sin clave) v=0',
    (select pg_temp.conjunto(x.v) || ' / ' || pg_temp.pot(x.v -> 'resumen') from (select pg_temp.cartera(pg_temp.a('C'), 'p_limite => 200') as v) x));
  perform pg_temp.esperar('C pidiendo un nivel → 55000: para quien no tiene ámbito de filas el filtro no existe', 'error 55000',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('C'), $c$p_limite => 200, p_potencial => 'tibio'$c$)));
  perform pg_temp.esperar('C en el envoltorio: cuenta su bandeja de reparto (4) pero SIN conteos por nivel', '(sin clave) v=4', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('C'))));
  perform pg_temp.esperar('V1 en el envoltorio: los mismos conteos que por la API', '- E3 T2 F0 S2 v=7', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform pg_temp.esperar('G en el envoltorio', '- E4 T4 F1 S5 v=14', pg_temp.pot(pg_temp.envoltorio(pg_temp.a('G'))));
  -- Una respuesta de error o sin el bloque también cuenta como falla (Codex f3b r1: NULL no es «igual»).
  perform pg_temp.esperar('los cuatro conteos suman el total sin filtro (los 9 roles con ámbito, API y envoltorio)', '18 respuestas, 0 malas',
    (select count(*)::text || ' respuestas, ' || count(*) filter (where pg_temp.resumen_bueno(x.r) is not true)::text || ' malas'
       from unnest(array['G', 'D', 'DH', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2']) a(k),
       lateral (select pg_temp.cartera(pg_temp.a(a.k), 'p_limite => 1') -> 'resumen' as r union all select pg_temp.envoltorio(pg_temp.a(a.k))) x));
  -- El propio verificador, frente a respuestas rotas: todas tienen que contar como malas.
  perform pg_temp.esperar('el verificador de sumas rechaza: error, nulo, sin bloque, bloque vacío, sin total, suma que no cuadra y un conteo que falta', 'f,f,f,f,f,f,f / t',
    (select string_agg(left(pg_temp.resumen_bueno(m.r)::text, 1), ',' order by m.n) from (values
        (1, pg_temp.envoltorio(pg_temp.a('P'))),
        (2, null::jsonb),
        (3, '{"totales":{"vivos":3}}'::jsonb),
        (4, '{"potencial":{}}'::jsonb),
        (5, '{"potencial":{"estrella":1,"tibio":1,"frio":1,"sin_marca":0}}'::jsonb),
        (6, '{"totales":{"vivos":4},"potencial":{"estrella":1,"tibio":1,"frio":1,"sin_marca":0}}'::jsonb),
        (7, '{"totales":{"vivos":3},"potencial":{"estrella":1,"tibio":1,"frio":1}}'::jsonb)) m(n, r))
    || ' / ' || left(pg_temp.resumen_bueno('{"totales":{"vivos":3},"potencial":{"filtro":null,"estrella":1,"tibio":1,"frio":1,"sin_marca":0}}'::jsonb)::text, 1));

  -- El ayudante por dentro: solo las marcas del ámbito del actor.
  perform pg_temp.esperar('ayudante, G: todas las marcas de leads activos', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('G')));
  perform pg_temp.esperar('ayudante, D: igual que gerencia', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('D')));
  perform pg_temp.esperar('ayudante, DH (directorio histórico): igual que gerencia', 'L1:e,L1n:t,L2:e,LC:e,LCV:e,LD:t,LK:t,LP:f,LSM:t,LZ:e', pg_temp.ayudante(pg_temp.a('DH')));
  perform pg_temp.esperar('ayudante, S1: su equipo y su bandeja', 'L1:e,L1n:t,LC:e,LD:t,LK:t,LP:f,LZ:e', pg_temp.ayudante(pg_temp.a('S1')));
  perform pg_temp.esperar('ayudante, V1: solo lo suyo', 'L1:e,LC:e,LD:t,LK:t,LZ:e', pg_temp.ayudante(pg_temp.a('V1')));
  perform pg_temp.esperar('ayudante, V2: solo lo suyo', 'L2:e,LCV:e', pg_temp.ayudante(pg_temp.a('V2')));
  perform pg_temp.esperar('ayudante, C: nada (operar el reparto no da a leer marcas)', '(ninguno)', pg_temp.ayudante(pg_temp.a('C')));
  perform pg_temp.esperar('ayudante, DM (pareja desalineada) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('DM')));
  -- El ayudante nunca entrega más que la RLS: los ids que devuelve a cada rol están dentro de los
  -- que ese rol lee. Se comparan UUID, y si alguna de las dos lecturas falla (NULL) el rol cuenta
  -- como malo: un oráculo caído no puede dar la prueba por buena (Codex f3b r2).
  perform pg_temp.esperar('ayudante ⊆ RLS para los 10 roles admitidos (ids, y las dos lecturas respondieron)', '10 roles, 0 malos',
    (select count(*)::text || ' roles, ' || count(*) filter (where (x.del_ayudante is not null and x.de_la_rls is not null
                                                              and x.del_ayudante <@ x.de_la_rls) is not true)::text || ' malos'
       from (select pg_temp.ayudante_ids(pg_temp.a(a.k)) as del_ayudante, pg_temp.ve_rls(pg_temp.a(a.k)) as de_la_rls
               from unnest(array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2']) a(k)) x));
  perform pg_temp.esperar('esa comparación ve un oráculo caído: sin respuesta de la RLS o del ayudante, el rol es malo', 't/t/t',
    left(((null::uuid[] is not null and '{}'::uuid[] <@ '{}'::uuid[]) is not true)::text, 1) || '/' ||
    left(((pg_temp.ayudante_ids(pg_temp.a('P')) is not null and pg_temp.ve_rls(pg_temp.a('V1')) is not null
           and pg_temp.ayudante_ids(pg_temp.a('P')) <@ pg_temp.ve_rls(pg_temp.a('V1'))) is not true)::text, 1) || '/' ||
    left(((array[pg_temp.l('L2')] <@ pg_temp.ve_rls(pg_temp.a('V1'))) is not true)::text, 1));
  perform pg_temp.esperar('ayudante, sin sesión → 42501', 'error 42501', pg_temp.ayudante(null));
  perform pg_temp.esperar('ayudante, P (solo portal) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('P')));
  perform pg_temp.esperar('ayudante, X (equipo inactivo) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('X')));
  perform pg_temp.esperar('ayudante, XP (perfil inactivo) → 42501', 'error 42501', pg_temp.ayudante(pg_temp.a('XP')));

  -- Encendida, la igualdad sigue: quitando resumen.potencial, cada respuesta es la anterior.
  v_iguales := 0; v_total := 0; v_dist := '';
  foreach ak in array array['G', 'D', 'DH', 'C', 'S1', 'S1n', 'S2', 'V1', 'V1n', 'V2'] loop
    foreach ca in array llamadas loop
      v := pg_temp.cartera(pg_temp.a(ak), ca, 'pg_temp.cartera_filtrada_anterior');
      w := pg_temp.cartera(pg_temp.a(ak), ca);
      v_total := v_total + 1;
      if v is not null and not (v ? 'error') and (v - 'generado_en') = ((w - 'generado_en') #- '{resumen,potencial}')
         -- Todos reciben el bloque menos coordinación, que no tiene ámbito de filas.
         and ((w #> '{resumen,potencial}') is not null) = (ak <> 'C') then v_iguales := v_iguales + 1;
      else v_dist := left(v_dist || ' · ' || ak || ' [' || ca || ']', 600); end if;
    end loop;
  end loop;
  perform pg_temp.esperar('encendida: quitando resumen.potencial, la respuesta es la de la firma de 13 (10 × 14)', '140 de 140', v_iguales || ' de ' || v_total || v_dist);

  -- La marca cambia y el filtro lo ve en la siguiente llamada (no hay copia guardada).
  update crm.lead_potencial set nivel = 'frio' where lead_id = pg_temp.l('L1');
  perform pg_temp.esperar('tras bajar L1 a frío: V1', '- E2 T2 F1 S2 v=7', pg_temp.pot(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200') -> 'resumen'));
  delete from crm.lead_potencial where lead_id = pg_temp.l('LK');
  perform pg_temp.esperar('tras quitar la marca de LK: V1 con sin_marca', 'L3,LK,LPV', pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), $c$p_limite => 200, p_potencial => 'sin_marca'$c$)));

  -- ── Solo lectura: la cartera no escribió nada en las tablas de la marca ──
  perform pg_temp.esperar('la cartera no escribió marcas ni eventos', '10/0',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── Con el potencial apagado (o sin ámbito de filas) el ayudante NI SE LLAMA ──
  -- Se sustituye por uno que explota: apagada, la cartera responde igual; encendida, explota.
  create or replace function private.cartera_potencial_fn() returns table(lead_id uuid, nivel text)
    language plpgsql stable security definer set search_path = '' as $x$
    begin raise exception 'el ayudante fue llamado' using errcode = 'P0777'; end $x$;
  perform pg_temp.esperar('ayudante que explota, bandera encendida: la cartera lo llama', 'error P0777',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));
  perform pg_temp.esperar('ayudante que explota, bandera encendida, coordinación: no se le llama', '(ninguno)',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('C'), 'p_limite => 200')));
  -- Por el envoltorio la base de coordinación SÍ tiene filas (su bandeja): ahí la unión con las
  -- marcas se recorrería de verdad si la guarda no cortara antes (Codex f3b r2).
  perform pg_temp.esperar('ayudante que explota, encendida, coordinación por el envoltorio (4 filas): tampoco se le llama', '(sin clave) v=4',
    pg_temp.pot(pg_temp.envoltorio(pg_temp.a('C'))));
  perform pg_temp.esperar('ayudante que explota, encendida, V1 por el envoltorio: sí se le llama', 'error P0777',
    pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  -- Con plan GENÉRICO forzado (el parámetro no se conoce al planificar) la guarda sigue cortando.
  perform set_config('plan_cache_mode', 'force_generic_plan', true);
  perform pg_temp.esperar('plan genérico, encendida, coordinación por el envoltorio: no se le llama', '(sin clave) v=4',
    pg_temp.pot(pg_temp.envoltorio(pg_temp.a('C'))));
  perform pg_temp.esperar('plan genérico, encendida, V1: sí se le llama', 'error P0777',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));
  update crm.multiempresa_flags set activo = false where nombre = 'potencial_lead';
  perform pg_temp.esperar('plan genérico, bandera apagada: no se le llama y la cartera responde', 'L1,L3,LC,LD,LK,LPV,LZ',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));
  perform pg_temp.esperar('plan genérico, bandera apagada, por el envoltorio: tampoco', '(sin clave) v=7',
    pg_temp.pot(pg_temp.envoltorio(pg_temp.a('V1'))));
  perform set_config('plan_cache_mode', 'auto', true);
  perform pg_temp.esperar('ayudante que explota, bandera apagada: no se le llama y la cartera responde', 'L1,L3,LC,LD,LK,LPV,LZ',
    pg_temp.conjunto(pg_temp.cartera(pg_temp.a('V1'), 'p_limite => 200')));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'FILTRO potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'FILTRO potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
