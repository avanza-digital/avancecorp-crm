-- B9 · Bases cargadas: repartir y recoger (20261004222602), en el banco. UNA transacción con impersonación (claims + set local
-- role), statement_timeout de authenticated (8 s) y ROLLBACK al final. Falla el proceso si hay un FAIL. Corre sobre un banco
-- LOCAL con B7, B8 y B9 aplicadas y los actores de seed:demo. Siembra bases «B9 suite …», contactos y leads con teléfonos
-- 9669200xx…9669205xx, que se deshacen con el ROLLBACK. Mundo de PRODUCCIÓN: la bandera de identidad resolver_en_puertas
-- ENCENDIDA.
-- Qué prueba:
--   A catálogo (EXECUTE solo authenticated en las puertas, núcleo cerrado, censo, topes, el assert de gestión diaria);
--   B roles (anon, service_role, analista, coordinación → 42501) y forma (modo, asignaciones, analista, cantidad, repetidos,
--     topes), base (inexistente, de otro equipo, de un supervisor de abajo → P0002; retirada, dueño inactivo → 22023);
--   C el analista: fuera del equipo del DUEÑO (P0002, también si es del equipo del actor), inactivo o supervisor (22023), del
--     subárbol anidado (pasa), Gerencia a cualquiera;
--   D bloque feliz «v1 5 · v2 4»: los más antiguos, el lead SIGUE descartado (sin ciclo SLA, sin episodio, sin tenencia), la
--     pertenencia, la actividad «reasignación», el recibo, el replay, la Base para gestión del analista (y su «Mes»), y si no
--     alcanzan → 22023 con detail = disponibles;
--   E bloque que salta: No contactar, descanso, en gestión (B6), retirado, fuera del ámbito, reactivado → omitidos por motivo;
--   F individual: rechazos (todo o nada, 22023 con detail), ya_asignado, reasignar a otro, en gestión al mismo analista, fuera de
--     la base o del ámbito (P0002), el analista anterior de un lead armado, Gerencia a otro equipo;
--   G recoger: solo sin intento desde asignado_en y sin B6, lo movido por otra vía queda, vuelve a la bandeja del DUEÑO, ámbito
--     del analista, Gerencia, replay, analista inactivo, tope (pendientes), dueño inactivo;
--   H contactos_de_base: cada estado del contrato, filtros, columnas, nada fuera del ámbito (ni retirados);
--   I el replay vuelve a juzgar las referencias del recibo;
--   K sin efectos de SLA ni episodios; el candado B6 sigue vivo en el lead; L regresión (B8 sigue cargando; assert; sello);
--   r1: R la regla nueva de B6 (Miguel 04/10: el seguimiento activo cuenta desde que el dueño actual recibió el lead) en la
--     ayudante, el candado del lead, el gris del rescate y recoger; un intento DURANTE la operación (misma sentencia) no se
--     hereda (bloque: «ocupado»; individual: 55P03); Gerencia vuelve a repartir lo que B9 dio fuera del equipo (F18–F19);
--     recoger de un analista de baja no exige «sin intento» (G9) y uno activo con un intento viejo sí (G9b);
--   r2: R8 rellamada del dueño anterior no se hereda (se lee del último intento posterior al corte, no de la columna), R9
--     A → B → A, R10 una «reasignación» sin cambio de vendedor no corta; Q las actividades «reasignación» no se cambian ni se
--     borran (ni por la API ni por las 4 vías DEFINER que actualizan actividades); P presupuesto de candados (bloque y recoger
--     abortan con 55P03 si los rechazados bajo candado lo agotan).
--   r3: Q8 fija el SQLSTATE (23505); Q10–Q14 el corte tampoco se FABRICA: una «reasignación» falsa hacia el dueño (RLS 42501) y
--     un intento falso (sello 42501) no entran y el candado no cambia; Q14 es el control (si entraran, liberarían o alargarían).
-- Mutantes: `node supabase/scripts/base-gestion/b9-mutantes.mjs --puerto <puerto>` inyecta cada uno en @@MUTANTE@@.
-- Concurrencia (dos sesiones): supabase/scripts/base-gestion/b9-concurrencia.sh (aparte: una transacción no la prueba).
\set ON_ERROR_STOP on
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'b9-repartir: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
begin;
set local statement_timeout = '8s';
-- @@MUTANTE@@

-- ───────── Utilidades (pg_temp: se van con el ROLLBACK) ─────────
-- OJO: una sentencia no ve lo que escriben las funciones volátiles que ella misma llama (su foto es la del inicio): cada paso
-- que escribe va en su propia sentencia (insert into resp …) y su efecto se lee en la siguiente.
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
create temp table c (k text primary key, id uuid not null unique);   -- contactos / leads de la suite por clave
create temp table act (k text primary key, id uuid not null);         -- actores por clave
create temp table bases (k text primary key, id uuid);
create temp table resp (k text primary key, v jsonb);
-- B10 (20261004223253) aplicada cambia DOS casos de B9 por contrato (los demás pasan igual con y sin B10): D10 — B10 saca de la
-- lista de Supervisión y Gerencia los dormidos del ARCHIVO sin repartir (viven en la pestaña «Bases»; contrato §B10) — y Q2 —
-- con B10, el núcleo de intentos es private.base_gestion_intento_capital_core (el de 6 argumentos lo envuelve sin capital)—.
create temp table b10 as select (to_regprocedure('crm.seguimiento_bases()') is not null) as aplicada;
create function pg_temp.sesion(p uuid, p_rol text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text, ''), true),
         set_config('request.jwt.claims', case when p is null and p_rol = 'authenticated' then ''
                                               else json_build_object('sub', p, 'role', p_rol)::text end, true);
$$;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
create function pg_temp.a(p_k text) returns uuid language sql stable as $$ select id from pg_temp.act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql stable as $$ select id from pg_temp.c where k = p_k $$;
create function pg_temp.b(p_k text) returns uuid language sql stable as $$ select id from pg_temp.bases where k = p_k $$;
create function pg_temp.ak(p uuid) returns text language sql stable as $$ select coalesce((select k from pg_temp.act where id = p), p::text) $$;
create function pg_temp.ck(p uuid) returns text language sql stable as $$ select coalesce((select k from pg_temp.c where id = p), p::text) $$;
-- prueba / valor / detalle: ejecutan p_sql como p_rol/p_uid y lo DESHACEN.
create function pg_temp.prueba(p_caso text, p_esperado text, p_sql text, p_rol text default null, p_uid uuid default null) returns void language plpgsql as $$
declare v text;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if v is null then v := sqlstate || ' ' || sqlerrm; end if;
  end;
  perform pg_temp.caso(p_caso, p_esperado, v);
end $$;
create function pg_temp.valor(p_sql text, p_rol text default null, p_uid uuid default null) returns text language plpgsql as $$
declare v text; v_ok boolean := false;
begin
  begin
    perform pg_temp.sesion(p_uid, case when p_rol = 'service_role' then 'service_role' else 'authenticated' end);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql into v;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if not v_ok then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  return coalesce(v, '(nulo)');
end $$;
create function pg_temp.detalle(p_sql text, p_rol text default null, p_uid uuid default null) returns text language plpgsql as $$
declare v text; v_det text;
begin
  begin
    perform pg_temp.sesion(p_uid);
    if p_rol is not null then execute format('set local role %I', p_rol); end if;
    execute p_sql;
    v := 'paso';
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if v is null then get stacked diagnostics v_det = pg_exception_detail; v := sqlstate || '|' || coalesce(nullif(v_det, ''), '(sin detail)'); end if;
  end;
  return v;
end $$;
-- tras: prepara el mundo como postgres sin usuario (p_prep), corre p_sql como authenticated/p_uid; devuelve el primer valor o
-- «ERROR …»; deshace TODO (preparación incluida).
create function pg_temp.tras(p_prep text, p_sql text, p_uid uuid) returns text language plpgsql as $$
declare v text; v_ok boolean := false;
begin
  begin
    perform pg_temp.sesion(null);
    execute p_prep;
    perform pg_temp.sesion(p_uid);
    execute 'set local role authenticated';
    execute p_sql into v;
    v_ok := true;
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if not v_ok then v := 'ERROR ' || sqlstate || ' ' || sqlerrm; end if;
  end;
  return coalesce(v, '(nulo)');
end $$;
-- secuencia: corre los pasos EN ORDEN dentro de UNA sentencia (misma statement_timestamp; cada EXECUTE ve lo anterior): los que
-- empiezan con «PG:» como postgres sin usuario (andamio; «PG!» igual, sin valor: admite varias sentencias), los «AS:<uuid>:»
-- como authenticated de ESE usuario, y el resto como authenticated/p_uid. Devuelve los valores unidos con «|»
-- (o «ERROR <sqlstate> <mensaje>» en el paso que falla, y se detiene) y lo DESHACE todo.
create function pg_temp.secuencia(p_uid uuid, variadic p_pasos text[]) returns text language plpgsql as $$
declare v text; v_out text := ''; s text;
begin
  begin
    foreach s in array p_pasos loop
      if left(s, 3) = 'PG:' then
        execute 'reset role';
        perform pg_temp.sesion(null);
        execute substr(s, 4) into v;
      elsif left(s, 3) = 'AS:' then
        perform pg_temp.sesion(substr(s, 4, 36)::uuid);
        execute 'set local role authenticated';
        execute substr(s, 41) into v;
      elsif left(s, 3) = 'PG!' then
        execute 'reset role';
        perform pg_temp.sesion(null);
        execute substr(s, 4);
        v := 'ok';
      else
        perform pg_temp.sesion(p_uid);
        execute 'set local role authenticated';
        execute s into v;
      end if;
      v_out := v_out || case when v_out = '' then '' else '|' end || coalesce(v, '(nulo)');
    end loop;
    raise exception using errcode = 'P0001', message = 'B9_DESHACER';
  exception when others then
    if sqlerrm <> 'B9_DESHACER' then
      v_out := v_out || case when v_out = '' then '' else '|' end || 'ERROR ' || sqlstate || ' ' || sqlerrm;
    end if;
  end;
  return v_out;
end $$;
-- ejecutar: corre p_sql como authenticated/p_uid y CONSERVA su efecto; si falla devuelve {"error": …} (deshace lo suyo).
create function pg_temp.ejecutar(p_sql text, p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  begin
    perform pg_temp.sesion(p_uid);
    execute 'set local role authenticated';
    execute p_sql into v;
    execute 'reset role';
  exception when others then
    v := jsonb_build_object('error', sqlstate || ' ' || sqlerrm);
  end;
  perform pg_temp.sesion(null);
  return v;
end $$;
-- ok: «ok» si el paso de preparación funcionó, o su error (un mutante que lo rompe cae con nombre).
create function pg_temp.ok(p jsonb) returns text language sql as $$ select case when p ? 'error' then p->>'error' else 'ok' end $$;
create function pg_temp.a_jsonb(p text) returns jsonb language plpgsql as $$
begin
  return p::jsonb;
exception when others then
  return jsonb_build_object('error', p);
end $$;
-- Pedidos.
create function pg_temp.bq(p_a uuid[], p_n int[]) returns jsonb language sql as $$
  select jsonb_build_object('modo', 'bloque', 'asignaciones',
    coalesce((select jsonb_agg(jsonb_build_object('analista_id', x.a, 'cantidad', x.n) order by x.o) from unnest(p_a, p_n) with ordinality x(a, n, o)), '[]'::jsonb)) $$;
create function pg_temp.ind(p_l uuid[], p_a uuid[]) returns jsonb language sql as $$
  select jsonb_build_object('modo', 'individual', 'asignaciones',
    coalesce((select jsonb_agg(jsonb_build_object('lead_id', x.l, 'analista_id', x.a) order by x.o) from unnest(p_l, p_a) with ordinality x(l, a, o)), '[]'::jsonb)) $$;
create function pg_temp.rep(p_base uuid, p_rep jsonb, p_op uuid default null) returns text language sql as $$
  select format('select crm.repartir_base(%L, %L, %L::jsonb)', coalesce(p_op, gen_random_uuid()), p_base, p_rep) $$;
create function pg_temp.rec(p_base uuid, p_a uuid, p_op uuid default null) returns text language sql as $$
  select format('select crm.recoger_de_base(%L, %L, %L)', coalesce(p_op, gen_random_uuid()), p_base, p_a) $$;
create function pg_temp.lista(p_base uuid, p_estado text default 'todos') returns text language sql as $$
  select format('select coalesce(string_agg(coalesce(c.k, ''?'') || '':'' || x.estado, '','' order by x.n), ''(vacía)'') from crm.contactos_de_base(%L%s) with ordinality x(lead_id, nombre_completo, telefono, distrito, agregado_en, analista_id, analista_nombre, estado, n) left join pg_temp.c c on c.id = x.lead_id',
                p_base, case when p_estado is null then '' else ', ' || quote_literal(p_estado) end) $$;
-- Lectura de respuestas.
create function pg_temp.res(p jsonb) returns text language sql stable as $$
  select case when p ? 'error' then p->>'error' else
    (p->>'repartidos') || '|'
    || coalesce((select string_agg(pg_temp.ak((x->>'analista_id')::uuid) || ':' || (x->>'cantidad'), ',' order by o)
                   from jsonb_array_elements(p->'por_analista') with ordinality y(x, o)), '') || '|'
    || coalesce((select string_agg(case when x->>'lead_id' is null then (x->>'motivo') || ':' || (x->>'cantidad')
                                        else pg_temp.ck((x->>'lead_id')::uuid) || ':' || (x->>'motivo') end, ',' order by o)
                   from jsonb_array_elements(p->'omitidos') with ordinality y(x, o)), '') end $$;
create function pg_temp.reco(p jsonb) returns text language sql as $$
  select case when p ? 'error' then p->>'error' else concat_ws('|', p->>'recogidos', p->>'omitidos', p->>'pendientes') end $$;
create function pg_temp.rech(p text) returns text language sql stable as $$
  select case when position('|' in p) = 0 then p else
    split_part(p, '|', 1) || '|' || coalesce((select string_agg(pg_temp.ck((x->>'lead_id')::uuid) || ':' || (x->>'motivo'), ',' order by o)
                                                from jsonb_array_elements(pg_temp.a_jsonb(substr(p, position('|' in p) + 1))->'rechazados') with ordinality y(x, o)),
                                               substr(p, position('|' in p) + 1)) end $$;
-- duenos: quién tiene cada lead (analista, o b:<supervisor> si está en su bandeja), en el orden de las claves.
create function pg_temp.duenos(p_ks text[]) returns text language sql stable as $$
  select string_agg(coalesce(pg_temp.ak(l.vendedor_id), 'b:' || pg_temp.ak(l.asignado_supervisor_id)), ',' order by x.o)
    from unnest(p_ks) with ordinality x(k, o) join pg_temp.c c on c.k = x.k join crm.leads l on l.id = c.id $$;
create function pg_temp.pert(p_ks text[]) returns text language sql stable as $$
  select string_agg(coalesce(pg_temp.ak(bl.analista_id), '-'), ',' order by x.o)
    from unnest(p_ks) with ordinality x(k, o) join pg_temp.c c on c.k = x.k join crm.base_carga_leads bl on bl.lead_id = c.id and bl.activo $$;
create function pg_temp.ks(p_pref text, p_desde int, p_hasta int) returns text[] language sql as $$
  select array_agg(p_pref || lpad(g::text, 2, '0') order by g) from generate_series(p_desde, p_hasta) g $$;
-- filas de un lote: nombre «B9 <PREF><nn>», teléfono <base> + nn, distrito Lince, capital 5000.
create function pg_temp.filas(p_pref text, p_desde int, p_hasta int, p_tel text) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('fila', g, 'nombre', 'B9 ' || upper(p_pref) || lpad(g::text, 2, '0'), 'telefono', p_tel || lpad(g::text, 2, '0'),
                                      'distrito', 'Lince', 'capital', '5000') order by g)
    from generate_series(p_desde, p_hasta) g $$;
create function pg_temp.registrar(p_pref text, p_desde int, p_hasta int, p_tel text) returns void language sql as $$
  insert into pg_temp.c (k, id)
  select p_pref || lpad(g::text, 2, '0'), l.id from generate_series(p_desde, p_hasta) g join crm.leads l on l.telefono = '+51' || p_tel || lpad(g::text, 2, '0') $$;
-- ordenar: fija el orden de llegada a la base (agregado_en) de las claves dadas (andamio, postgres sin usuario).
create function pg_temp.ordenar(p_ks text[]) returns void language sql as $$
  update crm.base_carga_leads bl set creado_en = now() - make_interval(mins => 1000 - x.o::int)
    from unnest(p_ks) with ordinality x(k, o) join pg_temp.c c on c.k = x.k where bl.lead_id = c.id and bl.activo $$;
-- fuera: cuántos de los ids (texto separado por comas) NO ve p_uid (espejo de leads_select) o están retirados.
create function pg_temp.fuera(p_ids text, p_uid uuid, p_rol text) returns text language plpgsql as $$
declare v int;
begin
  perform pg_temp.sesion(p_uid);
  select count(*) into v from unnest(string_to_array(p_ids, ',')) u(id) join crm.leads l on l.id = u.id::uuid
   where not private.base_gestion_lead_visible(p_uid, p_rol, l.vendedor_id, l.asignado_supervisor_id) or not l.activo;
  perform pg_temp.sesion(null);
  return v::text;
end $$;
create function pg_temp.baja(p uuid) returns text language sql as $$
  select format('alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo = false where perfil_id = %L; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia', p) $$;
create function pg_temp.alta(p uuid) returns text language sql as $$
  select format('alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia; update crm.equipo set activo = true where perfil_id = %L; alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia', p) $$;
create function pg_temp.exec(p_sql text) returns text language plpgsql as $$
begin
  perform pg_temp.sesion(null);
  execute p_sql;
  return 'ok';
end $$;
create function pg_temp.intento(p_k text, p_uid uuid, p_res text default 'no_contesto') returns jsonb language sql as $$
  select pg_temp.ejecutar(format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, null, null)', pg_temp.l(p_k), p_res), p_uid) $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;
grant select on c, act, bases to anon, authenticated, service_role;

-- ───────── Actores (seed:demo) y precondiciones ─────────
insert into act (k, id) select x.k, u.id from (values ('v1', 'vend1'), ('v2', 'vend2'), ('v3', 'vend3'), ('va', 'vend-anidado'), ('vi', 'vend-inactivo'),
                                                      ('s1', 'sup1'), ('s2', 'sup2'), ('sa', 'sup-anidado'), ('g', 'gerencia'), ('co', 'coordinador')) x(k, e)
  join auth.users u on u.email = x.e || '.crm@demo.avancecorp.pe';
do $$ begin
  if (select count(*) from pg_temp.act) <> 10 then
    raise exception 'b9-repartir: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if to_regprocedure('crm.repartir_base(uuid,uuid,jsonb)') is null or to_regprocedure('crm.cargar_base_lote(uuid,uuid,jsonb)') is null then
    raise exception 'b9-repartir: B8 y B9 (20261004222602) no están aplicadas en este banco';
  end if;
  if exists (select 1 from crm.leads where telefono like '+5196692%') or exists (select 1 from crm.bases_carga where nombre like 'B9 suite%') then
    raise exception 'b9-repartir: ya hay leads 96692xxxx o bases «B9 suite» en el banco';
  end if;
  if private.rol_crm(pg_temp.a('vi')) is not null or private.rol_crm(pg_temp.a('va')) is distinct from 'vendedor'
     or private.rol_crm(pg_temp.a('sa')) is distinct from 'supervisor'
     or not exists (select 1 from crm.equipo e where e.perfil_id = pg_temp.a('sa') and e.supervisor_id = pg_temp.a('s1'))
     or not exists (select 1 from crm.equipo e where e.perfil_id = pg_temp.a('va') and e.supervisor_id = pg_temp.a('sa')) then
    raise exception 'b9-repartir: el equipo de seed:demo no es el esperado (sup1 → sup-anidado → vend-anidado; vend-inactivo inactivo)';
  end if;
end $$;
update crm.multiempresa_flags set activo = true where nombre = 'resolver_en_puertas';

-- ───────── Siembra ─────────
-- Base A (archivo, de S1): 12 contactos k01…k12 en tres lotes, con capital; orden de llegada k01 → k12.
insert into bases select 'A', (pg_temp.ejecutar('select crm.crear_base(gen_random_uuid(), ''B9 suite A'', ''archivo'', null, ''a.csv'')', pg_temp.a('s1'))->>'base_id')::uuid;
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('A'), pg_temp.filas('k', 1, 4, '9669200')), pg_temp.a('s1'));
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('A'), pg_temp.filas('k', 5, 8, '9669200')), pg_temp.a('s1'));
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('A'), pg_temp.filas('k', 9, 12, '9669200')), pg_temp.a('s1'));
select pg_temp.registrar('k', 1, 12, '9669200');
select pg_temp.ordenar(pg_temp.ks('k', 1, 12));
-- Base B (armada desde el CRM por S1): 6 descartados de V1 (cb01…cb06) que CONSERVAN su analista (E13).
select pg_temp.sesion(null);
insert into crm.leads (nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select 'B9 CB' || lpad(g::text, 2, '0'), '9669201' || lpad(g::text, 2, '0'), 'oficina', 'nuevo', pg_temp.a('v1'), 1000, 'PEN', pg_temp.a('v1'), true
  from generate_series(1, 6) g;
update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where telefono like '+519669201%';
select pg_temp.registrar('cb', 1, 6, '9669201');
insert into bases select 'B', (pg_temp.ejecutar(format('select crm.armar_base_crm(gen_random_uuid(), ''B9 suite B'', null, %L::uuid[])',
  (select array_agg(pg_temp.l(k) order by k) from unnest(pg_temp.ks('cb', 1, 6)) k)), pg_temp.a('s1'))->>'base_id')::uuid;
select pg_temp.ordenar(pg_temp.ks('cb', 1, 6));
-- Base C (archivo, de SUP-ANIDADO): 3 contactos c01…c03. Base D (de S2): 2 contactos d01, d02.
insert into bases select 'C', (pg_temp.ejecutar('select crm.crear_base(gen_random_uuid(), ''B9 suite C'', ''archivo'', null, ''c.csv'')', pg_temp.a('sa'))->>'base_id')::uuid;
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('C'), pg_temp.filas('c', 1, 3, '9669202')), pg_temp.a('sa'));
select pg_temp.registrar('c', 1, 3, '9669202');
select pg_temp.ordenar(pg_temp.ks('c', 1, 3));
insert into bases select 'D', (pg_temp.ejecutar('select crm.crear_base(gen_random_uuid(), ''B9 suite D'', ''archivo'', null, ''d.csv'')', pg_temp.a('s2'))->>'base_id')::uuid;
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('D'), pg_temp.filas('d', 1, 2, '9669203')), pg_temp.a('s2'));
select pg_temp.registrar('d', 1, 2, '9669203');
-- Base E (archivo, de S1): 10 contactos e01…e10 para los estados.
insert into bases select 'E', (pg_temp.ejecutar('select crm.crear_base(gen_random_uuid(), ''B9 suite E'', ''archivo'', null, ''e.csv'')', pg_temp.a('s1'))->>'base_id')::uuid;
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('E'), pg_temp.filas('e', 1, 10, '9669204')), pg_temp.a('s1'));
select pg_temp.registrar('e', 1, 10, '9669204');
select pg_temp.ordenar(pg_temp.ks('e', 1, 10));
-- Base F (archivo, de S1): 70 contactos f01…f70 para el presupuesto de candados.
insert into bases select 'F', (pg_temp.ejecutar('select crm.crear_base(gen_random_uuid(), ''B9 suite F'', ''archivo'', null, ''f.csv'')', pg_temp.a('s1'))->>'base_id')::uuid;
select pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('F'), pg_temp.filas('f', 1, 70, '9669207')), pg_temp.a('s1'));
select pg_temp.registrar('f', 1, 70, '9669207');
select pg_temp.ordenar(pg_temp.ks('f', 1, 70));
do $$ begin
  if (select count(*) from pg_temp.bases where id is not null) <> 6 or (select count(*) from pg_temp.c) <> 103
     or (select count(*) from crm.base_carga_leads bl join pg_temp.c c on c.id = bl.lead_id where bl.activo and bl.analista_id is null) <> 103 then
    raise exception 'b9-repartir: la siembra no quedó como se esperaba (bases %, contactos %)', (select count(*) from pg_temp.bases where id is not null), (select count(*) from pg_temp.c);
  end if;
end $$;

-- ───────── A · Catálogo ─────────
select pg_temp.caso('A1 las 3 puertas: DEFINER de postgres, search_path vacío, EXECUTE solo authenticated (ni anon, ni service_role, ni PUBLIC)', '3',
  (select count(*)::text from pg_proc p where p.oid in ('crm.repartir_base(uuid,uuid,jsonb)'::regprocedure, 'crm.recoger_de_base(uuid,uuid,uuid)'::regprocedure,
                                                        'crm.contactos_de_base(uuid,text)'::regprocedure)
     and p.prosecdef and p.proowner = 'postgres'::regrole and p.proconfig @> array['search_path=""']
     and has_function_privilege('authenticated', p.oid, 'EXECUTE') and not has_function_privilege('anon', p.oid, 'EXECUTE')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE') and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)));
select pg_temp.caso('A2 el núcleo privado de B9 (10 funciones) sin EXECUTE para la API', '10|0',
  (select count(distinct p.oid)::text || '|' || count(*) filter (where has_function_privilege(x.rol, p.oid, 'EXECUTE'))::text
     from pg_proc p cross join unnest(array['anon', 'authenticated', 'service_role']) x(rol)
    where p.pronamespace = 'private'::regnamespace
      and (p.proname like 'bases\_carga\_reparto\_%' or p.proname in ('bases_carga_repartir_core', 'bases_carga_recoger_core', 'bases_carga_contactos_core'))));
select pg_temp.caso('A3 ninguna función de B9 entra al censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c where c.objeto ~ 'bases_carga_reparto_|bases_carga_repartir_core|bases_carga_recoger_core|bases_carga_contactos_core|repartir_base|recoger_de_base|contactos_de_base'));
select pg_temp.caso('A4 topes: 500 contactos por operación, 100 analistas, holgura de candados 50', '500|100|50',
  (select format('%s|%s|%s', k.max_contactos, k.max_analistas, k.holgura_candados) from private.bases_carga_reparto_constantes() k));
select pg_temp.caso('A5 assert_gestion_diaria_resultado pasa con B9', 'OK', left(pg_temp.valor('select private.assert_gestion_diaria_resultado()'), 2));
select pg_temp.caso('A6 la ayudante de B6 tiene la regla nueva (cuenta desde la «reasignación» hacia el dueño), sin EXECUTE para la API', 'true|false',
  (select (p.prosrc ~ 'vendedor_nuevo' and p.provolatile = 's')::text || '|' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
     from pg_proc p where p.oid = 'private.base_gestion_en_gestion_hasta(uuid)'::regprocedure));

-- ───────── B · Roles, forma y base ─────────
select pg_temp.prueba('B1 anon → 42501 (sin EXECUTE)', '42501 permission denied for schema crm',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'anon');
select pg_temp.prueba('B2 service_role → 42501 (sin EXECUTE)', '42501 permission denied for function repartir_base',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'service_role');
select pg_temp.prueba('B3 el analista → 42501', '42501 Solo Supervisión y Gerencia reparten y ven las bases',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('v1'));
select pg_temp.prueba('B4 Coordinación → 42501', '42501 Solo Supervisión y Gerencia reparten y ven las bases',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('co'));
select pg_temp.prueba('B5 el analista recoge → 42501', '42501 Solo Supervisión y Gerencia reparten y ven las bases',
  pg_temp.rec(pg_temp.b('A'), pg_temp.a('v1')), 'authenticated', pg_temp.a('v1'));
select pg_temp.prueba('B6 el analista lista los contactos de una base → 42501', '42501 Solo Supervisión y Gerencia reparten y ven las bases',
  pg_temp.lista(pg_temp.b('A')), 'authenticated', pg_temp.a('v1'));
select pg_temp.prueba('B7 base nula → 22023', '22023 La base es obligatoria',
  pg_temp.rep(null, pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B8 reparto nulo → 22023', '22023 El reparto llega como {"modo": "bloque" o "individual", "asignaciones": [...]}',
  format('select crm.repartir_base(gen_random_uuid(), %L, null)', pg_temp.b('A')), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B9 modo desconocido → 22023', '22023 El modo del reparto es «bloque» o «individual»',
  pg_temp.rep(pg_temp.b('A'), '{"modo": "todos", "asignaciones": []}'), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B10 sin asignaciones → 22023', '22023 Un reparto en bloque trae entre 1 y 100 asignaciones (este trae 0)',
  pg_temp.rep(pg_temp.b('A'), '{"modo": "bloque", "asignaciones": []}'), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B11 analista que no es un uuid → 22023', '22023 La asignación 1 no trae un analista válido',
  pg_temp.rep(pg_temp.b('A'), '{"modo": "bloque", "asignaciones": [{"analista_id": "x", "cantidad": 1}]}'), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('B12 cantidad 0, 1.5, «40» (texto) o ausente → 22023', 'x4',
  (select 'x' || count(*) from (values ('0'), ('1.5'), ('"40"'), ('null')) q(v)
    where pg_temp.valor(pg_temp.rep(pg_temp.b('A'), format('{"modo": "bloque", "asignaciones": [{"analista_id": "%s", "cantidad": %s}]}', pg_temp.a('v1'), q.v)::jsonb),
                        'authenticated', pg_temp.a('s1')) = 'ERROR 22023 La asignación 1 no trae una cantidad entera mayor que 0'));
select pg_temp.prueba('B13 el mismo analista dos veces → 22023', '22023 El analista de la asignación 2 se repite',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1'), pg_temp.a('v1')], array[1, 1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B14 un bloque de 501 → 22023 (tope)', '22023 Un reparto mueve hasta 500 contactos por operación (este pide 501)',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1'), pg_temp.a('v2')], array[500, 1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B15 un bloque a 101 analistas → 22023', '22023 Un reparto en bloque trae entre 1 y 100 asignaciones (este trae 101)',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array(select gen_random_uuid() from generate_series(1, 101)), array(select 1 from generate_series(1, 101)))), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B16 un individual de 501 filas → 22023 (tope)', '22023 Un reparto en individual trae entre 1 y 500 asignaciones (este trae 501)',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array(select gen_random_uuid() from generate_series(1, 501)), array(select pg_temp.a('v1') from generate_series(1, 501)))), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B17 un individual a 101 analistas → 22023', '22023 Un reparto va a lo más a 100 analistas',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array(select gen_random_uuid() from generate_series(1, 101)), array(select gen_random_uuid() from generate_series(1, 101)))), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B18 el mismo contacto dos veces → 22023', '22023 El contacto de la asignación 2 se repite',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k01'), pg_temp.l('k01')], array[pg_temp.a('v1'), pg_temp.a('v2')])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B19 un contacto que no es un uuid → 22023', '22023 La asignación 1 no trae un contacto válido',
  pg_temp.rep(pg_temp.b('A'), format('{"modo": "individual", "asignaciones": [{"lead_id": "x", "analista_id": "%s"}]}', pg_temp.a('v1'))::jsonb), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B20 sin id de operación → 22023', '22023 El identificador de la operación es obligatorio',
  format('select crm.repartir_base(null, %L, %L::jsonb)', pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B21 base inexistente → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.rep(gen_random_uuid(), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B22 S2 reparte la base de S1 → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v3')], array[1])), 'authenticated', pg_temp.a('s2'));
select pg_temp.prueba('B23 un supervisor de ABAJO (sup-anidado) reparte la base de S1 → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('va')], array[1])), 'authenticated', pg_temp.a('sa'));
select pg_temp.caso('B24 base retirada → 22023', 'ERROR 22023 La base está retirada: no se reparte',
  pg_temp.tras(format('update crm.bases_carga set activo = false where id = %L', pg_temp.b('A')),
               pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), pg_temp.a('s1')));
select pg_temp.caso('B25 el supervisor dueño inactivo (reparte Gerencia) → 22023', 'ERROR 22023 El supervisor dueño de la base ya no está activo: no se puede repartir',
  pg_temp.tras(pg_temp.baja(pg_temp.a('s1')),
               pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), pg_temp.a('g')));
select pg_temp.prueba('B26 recoger sin analista → 22023', '22023 La base y el analista son obligatorios',
  pg_temp.rec(pg_temp.b('A'), null), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B27 recoger en una base de otro equipo → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.rec(pg_temp.b('A'), pg_temp.a('v1')), 'authenticated', pg_temp.a('s2'));
select pg_temp.prueba('B28 lista con un filtro desconocido → 22023', '22023 El filtro es sin_repartir, repartidos o todos',
  pg_temp.lista(pg_temp.b('A'), 'otros'), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('B29 lista de una base de otro equipo → P0002', 'P0002 Base no encontrada o fuera de tu ámbito',
  pg_temp.lista(pg_temp.b('A')), 'authenticated', pg_temp.a('s2'));
select pg_temp.prueba('B30 lista sin base → 22023', '22023 La base es obligatoria',
  pg_temp.lista(null), 'authenticated', pg_temp.a('s1'));

-- ───────── C · El analista ─────────
select pg_temp.prueba('C1 S1 reparte a un analista de OTRO equipo → P0002', 'P0002 Analista no encontrado o fuera del equipo de la base',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v3')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('C2 S1 reparte a un analista inactivo de otro equipo → P0002', 'P0002 Analista no encontrado o fuera del equipo de la base',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('vi')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('C3 S1 reparte a un analista SUYO dado de baja → 22023', 'ERROR 22023 El analista no existe, no está activo o no es analista',
  pg_temp.tras(pg_temp.baja(pg_temp.a('v2')),
               pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v2')], array[1])), pg_temp.a('s1')));
select pg_temp.prueba('C4 S1 reparte a un supervisor de su subárbol → 22023 (no es analista)', '22023 El analista no existe, no está activo o no es analista',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('sa')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('C5 S1 reparte al analista del subárbol ANIDADO → pasa', '1|va:1|',
  pg_temp.res(pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('va')], array[1])), 'authenticated', pg_temp.a('s1')))));
select pg_temp.caso('C6 Gerencia reparte a un analista de OTRO equipo → pasa', '1|v3:1|',
  pg_temp.res(pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v3')], array[1])), 'authenticated', pg_temp.a('g')))));
select pg_temp.prueba('C7 Gerencia reparte a un id que no es nadie → 22023', '22023 El analista no existe, no está activo o no es analista',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[gen_random_uuid()], array[1])), 'authenticated', pg_temp.a('g'));
select pg_temp.prueba('C8 S1 reparte la base de SUP-ANIDADO a V1 (de S1, no del dueño) → P0002', 'P0002 Analista no encontrado o fuera del equipo de la base',
  pg_temp.rep(pg_temp.b('C'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('C9 S1 reparte la base de SUP-ANIDADO a su analista → pasa', '1|va:1|',
  pg_temp.res(pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('C'), pg_temp.bq(array[pg_temp.a('va')], array[1])), 'authenticated', pg_temp.a('s1')))));

-- ───────── D · Bloque feliz: «V1 5 · V2 4» ─────────
create temp table antes as select
  (select count(*) from crm.lead_sla_ciclos s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') ciclos,
  (select count(*) from crm.lead_sla_etapas s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') etapas,
  (select count(*) from crm.lead_asignaciones s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') episodios;
insert into resp values ('opA', to_jsonb(gen_random_uuid()));
insert into resp select 'A1', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1'), pg_temp.a('v2')], array[5, 4]), (select (v #>> '{}')::uuid from resp where k = 'opA')), pg_temp.a('s1'));
select pg_temp.caso('D1 bloque V1 5 · V2 4 → 9 repartidos, por analista en el orden pedido, sin omitidos', '9|v1:5,v2:4|',
  pg_temp.res((select v from resp where k = 'A1')));
select pg_temp.caso('D2 los MÁS ANTIGUOS en la base, en el orden de las asignaciones; el resto sigue en la bandeja de S1', 'v1,v1,v1,v1,v1,v2,v2,v2,v2,b:s1,b:s1,b:s1',
  pg_temp.duenos(pg_temp.ks('k', 1, 12)));
select pg_temp.caso('D3 los 9 SIGUEN dormidos: descartados base_cargada, sin bandeja, sin tenencia, ciclo 1, misma fecha de descarte', '9',
  (select count(*)::text from crm.leads l join pg_temp.c c on c.id = l.id
    where c.k in (select unnest(pg_temp.ks('k', 1, 9))) and l.etapa = 'descartado' and l.motivo_descarte = 'base_cargada' and l.origen = 'base_cargada'
      and l.vendedor_id is not null and l.asignado_supervisor_id is null and l.tenencia_desde is null and l.ciclo_actual = 1
      and l.descartado_en = l.creado_en and l.activo));
select pg_temp.caso('D4 la pertenencia: analista = el del lead, asignado_por S1, asignado_en después de llegar; las 3 sin repartir, vacías', '9|3',
  (select count(*) filter (where bl.analista_id = l.vendedor_id and bl.asignado_por = pg_temp.a('s1') and bl.asignado_en > bl.creado_en)::text || '|'
          || count(*) filter (where bl.analista_id is null and bl.asignado_en is null and bl.asignado_por is null)::text
     from crm.base_carga_leads bl join crm.leads l on l.id = bl.lead_id join pg_temp.c c on c.id = l.id where c.k like 'k%' and bl.activo));
select pg_temp.caso('D5 sin ciclo SLA, sin etapa SLA y sin episodio nuevos (el lead no «llega» al analista)', 'true',
  (select ((select count(*) from crm.lead_sla_ciclos s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') = a.ciclos
       and (select count(*) from crm.lead_sla_etapas s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') = a.etapas
       and (select count(*) from crm.lead_asignaciones s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%') = a.episodios
       and a.ciclos = 0 and a.episodios = 0)::text from antes a));
select pg_temp.caso('D6 la actividad «reasignación» (Bandeja de S1 → analista), una por contacto, por S1', '9',
  (select count(*)::text from crm.actividades a join pg_temp.c c on c.id = a.lead_id join crm.leads l on l.id = a.lead_id
    where c.k like 'k%' and a.tipo = 'reasignacion' and a.creado_por = pg_temp.a('s1') and (a.metadata->>'supervisor_anterior')::uuid = pg_temp.a('s1')
      and (a.metadata->>'vendedor_nuevo')::uuid = l.vendedor_id and a.metadata->>'vendedor_anterior' is null));
select pg_temp.caso('D7 el recibo «repartir» de S1 guarda la respuesta', 'true',
  (select (o.tipo = 'repartir' and o.base_id = pg_temp.b('A') and o.respuesta = (select v from resp where k = 'A1'))::text
     from crm.base_carga_operaciones o where o.actor = pg_temp.a('s1') and o.operacion_id = (select (v #>> '{}')::uuid from resp where k = 'opA')));
select pg_temp.caso('D8 la Base para gestión de V1 trae SUS 5 contactos de la base; la de V2, sus 4', 'k01,k02,k03,k04,k05|k06,k07,k08,k09',
  pg_temp.valor('select string_agg(c.k, '','' order by c.k) from crm.obtener_base_gestion() o join pg_temp.c c on c.id = o.lead_id where c.k like ''k%''', 'authenticated', pg_temp.a('v1'))
  || '|' || pg_temp.valor('select string_agg(c.k, '','' order by c.k) from crm.obtener_base_gestion() o join pg_temp.c c on c.id = o.lead_id where c.k like ''k%''', 'authenticated', pg_temp.a('v2')));
select pg_temp.caso('D9 «Mes» del analista: recibido_en = creado_en del contacto (la carga), en todos los suyos', 'true',
  pg_temp.valor('select bool_and(o.recibido_en = l.creado_en)::text from crm.obtener_base_gestion() o join pg_temp.c c on c.id = o.lead_id join crm.leads l on l.id = o.lead_id where c.k like ''k%''',
                'authenticated', pg_temp.a('v1')));
select pg_temp.caso('D10 en la vista de S1 los repartidos ya no son de su bandeja (tienen analista); los 3 sin repartir, sí (B10: no, viven en «Bases»)', case when (select aplicada from pg_temp.b10) then '9|0' else '9|3' end,
  pg_temp.valor('select count(*) filter (where o.vendedor_id is not null)::text || ''|'' || count(*) filter (where o.vendedor_id is null)::text from crm.obtener_base_gestion() o join pg_temp.c c on c.id = o.lead_id where c.k like ''k%''',
                'authenticated', pg_temp.a('s1')));
insert into resp select 'A1r', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1'), pg_temp.a('v2')], array[5, 4]), (select (v #>> '{}')::uuid from resp where k = 'opA')), pg_temp.a('s1'));
select pg_temp.caso('D11 replay: el mismo id con el mismo pedido devuelve la MISMA respuesta (y no reparte de nuevo)', 'true|v1,v1,v1,v1,v1,v2,v2,v2,v2,b:s1,b:s1,b:s1|9',
  ((select v from resp where k = 'A1r') = (select v from resp where k = 'A1'))::text || '|' || pg_temp.duenos(pg_temp.ks('k', 1, 12)) || '|'
  || (select count(*)::text from crm.actividades a join pg_temp.c c on c.id = a.lead_id where c.k like 'k%' and a.tipo = 'reasignacion'));
select pg_temp.prueba('D12 el mismo id con OTRO pedido → 22023', '22023 Este identificador de operación ya se usó con un pedido distinto',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1]), (select (v #>> '{}')::uuid from resp where k = 'opA')), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('D13 si no alcanzan → 22023 con detail = disponibles (3)', '22023|3',
  pg_temp.detalle(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[4])), 'authenticated', pg_temp.a('s1')));
select pg_temp.prueba('D14 … y el mensaje dice cuántos hay y cuántos se pidieron', '22023 Solo hay 3 contactos disponibles para repartir en esta base (pediste 4)',
  pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[4])), 'authenticated', pg_temp.a('s1'));

-- ───────── E · El bloque salta lo que no se puede repartir ─────────
select pg_temp.caso('E0 preparar: S1 marca No contactar k10 (por su puerta)', 'ok',
  pg_temp.ok(pg_temp.ejecutar(format('select crm.marcar_no_contactar(%L, ''B9 suite: pidió que no lo llamen'')', pg_temp.l('k10')), pg_temp.a('s1'))));
select pg_temp.sesion(null);
update crm.leads set enfriado_hasta = (now() at time zone 'America/Lima')::date + 5 where id = pg_temp.l('k11');  -- descanso (andamio sin usuario)
select pg_temp.caso('E1 bloque de 2 con UNO solo elegible (k12) → 22023 con detail 1', '22023|1',
  pg_temp.detalle(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[2])), 'authenticated', pg_temp.a('s1')));
insert into resp select 'A2', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1')], array[1])), pg_temp.a('s1'));
select pg_temp.caso('E2 bloque de 1 → k12; omitidos por motivo, sin id (en descanso, No contactar)', '1|v1:1|en_descanso:1,no_contactar:1',
  pg_temp.res((select v from resp where k = 'A2')));
select pg_temp.caso('E3 … el elegido es k12; k10 y k11 siguen en la bandeja', 'b:s1,b:s1,v1', pg_temp.duenos(pg_temp.ks('k', 10, 12)));
-- Base B (armada): cb01 en gestión de V1 (intento), cb02 retirado, cb03 sacado del ámbito (a V3), cb05 reactivado por V1.
select pg_temp.caso('E4 preparar la base B (intento de V1 en cb01, reactivar cb05)', 'ok|ok',
  pg_temp.ok(pg_temp.intento('cb01', pg_temp.a('v1'))) || '|'
  || pg_temp.ok(pg_temp.ejecutar(format('select crm.reactivar_lead_base(gen_random_uuid(), %L, null)', pg_temp.l('cb05')), pg_temp.a('v1'))));
select pg_temp.sesion(null);
update crm.leads set activo = false where id = pg_temp.l('cb02');
update crm.leads set vendedor_id = pg_temp.a('v3'), asignado_supervisor_id = null where id = pg_temp.l('cb03');
select pg_temp.caso('E5 lista de B para S1: cb01 trabajado (sin repartir, en gestión), cb04/cb06 sin repartir, cb05 reactivado; cb02 (retirado) y cb03 (otro equipo) NO salen', 'cb01:trabajado,cb04:sin_repartir,cb05:reactivado,cb06:sin_repartir',
  pg_temp.valor(pg_temp.lista(pg_temp.b('B')), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('E6 lista de B para Gerencia: además cb03 (movido por otra vía); el retirado no sale', 'cb01:trabajado,cb03:movido_otra_via,cb04:sin_repartir,cb05:reactivado,cb06:sin_repartir',
  pg_temp.valor(pg_temp.lista(pg_temp.b('B')), 'authenticated', pg_temp.a('g')));
select pg_temp.caso('E7 bloque de 3 en B: solo 2 elegibles (cb04, cb06) → 22023 con detail 2', '22023|2',
  pg_temp.detalle(pg_temp.rep(pg_temp.b('B'), pg_temp.bq(array[pg_temp.a('v2')], array[3])), 'authenticated', pg_temp.a('s1')));
insert into resp select 'B1', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('B'), pg_temp.bq(array[pg_temp.a('v2')], array[1])), pg_temp.a('s1'));
select pg_temp.caso('E8 bloque de 1 en B → el más antiguo elegible (cb04); omitidos: en gestión, fuera del ámbito, retirado, reactivado', '1|v2:1|en_gestion:1,fuera_de_ambito:1,inactivo:1,no_descartado:1',
  pg_temp.res((select v from resp where k = 'B1')));
select pg_temp.caso('E9 … cb04 pasa de V1 (analista anterior) a V2, con su «reasignación» V1 → V2', 'v2|1',
  pg_temp.duenos(array['cb04']) || '|' || (select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('cb04') and a.tipo = 'reasignacion'
    and (a.metadata->>'vendedor_anterior')::uuid = pg_temp.a('v1') and (a.metadata->>'vendedor_nuevo')::uuid = pg_temp.a('v2') and a.creado_por = pg_temp.a('s1')));

-- ───────── F · Individual ─────────
select pg_temp.caso('F1 individual de un No contactar → 22023, detail con el rechazado y su motivo', '22023|k10:no_contactar',
  pg_temp.rech(pg_temp.detalle(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k10')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('s1'))));
insert into resp select 'F2', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k11'), pg_temp.l('k06')], array[pg_temp.a('v2'), pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('F2 individual con uno en descanso y otro válido → TODO O NADA (k06 sigue con V2)', '22023 1 de los contactos pedidos no se pueden repartir (en gestión, en descanso, No contactar o fuera de la base); no se repartió ninguno|v2',
  coalesce((select v->>'error' from resp where k = 'F2'), pg_temp.res((select v from resp where k = 'F2'))) || '|' || pg_temp.duenos(array['k06']));
select pg_temp.caso('F3 … su detail nombra solo el rechazado (k11, en descanso)', '22023|k11:en_descanso',
  pg_temp.rech(pg_temp.detalle(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k11'), pg_temp.l('k06')], array[pg_temp.a('v2'), pg_temp.a('v1')])), 'authenticated', pg_temp.a('s1'))));
insert into resp select 'F4', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k01')], array[pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('F4 individual de k01 a V1 (ya es suyo) → omitido ya_asignado, 0 repartidos', '0||k01:ya_asignado', pg_temp.res((select v from resp where k = 'F4')));
insert into resp select 'F5', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k02'), pg_temp.l('k06')], array[pg_temp.a('v2'), pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('F5 individual: k02 (de V1) a V2 y k06 (de V2) a V1 → se REASIGNAN', '2|v2:1,v1:1|', pg_temp.res((select v from resp where k = 'F5')));
select pg_temp.caso('F6 … lead y pertenencia con el analista nuevo; asignado_en renovado; «reasignación» V1 → V2 en k02', 'v2,v1|v2,v1|true|1',
  pg_temp.duenos(array['k02', 'k06']) || '|' || pg_temp.pert(array['k02', 'k06']) || '|'
  || (select (bl.asignado_en > (select max(bl2.asignado_en) from crm.base_carga_leads bl2 where bl2.lead_id = pg_temp.l('k01')))::text
        from crm.base_carga_leads bl where bl.lead_id = pg_temp.l('k02') and bl.activo) || '|'
  || (select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('k02') and a.tipo = 'reasignacion'
        and (a.metadata->>'vendedor_anterior')::uuid = pg_temp.a('v1') and (a.metadata->>'vendedor_nuevo')::uuid = pg_temp.a('v2')));
select pg_temp.caso('F7 preparar: V1 registra un intento en k03 (seguimiento activo B6)', 'ok', pg_temp.ok(pg_temp.intento('k03', pg_temp.a('v1'))));
select pg_temp.caso('F8 individual de k03 (en gestión de V1) a V2 → 22023 en_gestion (no llega al candado B6 del lead)', '22023|k03:en_gestion',
  pg_temp.rech(pg_temp.detalle(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k03')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('s1'))));
select pg_temp.caso('F9 individual de k03 a V1 (el que lo trabaja) → ya_asignado, no es una reasignación', '0||k03:ya_asignado',
  pg_temp.res(pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k03')], array[pg_temp.a('v1')])), 'authenticated', pg_temp.a('s1')))));
select pg_temp.prueba('F10 individual de un id que no es de la base → P0002', 'P0002 Hay contactos que no están en esta base o están fuera de tu ámbito',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[gen_random_uuid()], array[pg_temp.a('v1')])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('F11 individual en la base A de un contacto de la base D (de S2) → P0002', 'P0002 Hay contactos que no están en esta base o están fuera de tu ámbito',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('d01')], array[pg_temp.a('v1')])), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('F12 individual en la base B de cb03 (ya de V3, otro equipo) por S1 → P0002 (no lo ve)', 'P0002 Hay contactos que no están en esta base o están fuera de tu ámbito',
  pg_temp.rep(pg_temp.b('B'), pg_temp.ind(array[pg_temp.l('cb03')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('F13 … Gerencia sí lo ve, pero salió del ámbito del dueño → 22023 fuera_de_ambito', '22023|cb03:fuera_de_ambito',
  pg_temp.rech(pg_temp.detalle(pg_temp.rep(pg_temp.b('B'), pg_temp.ind(array[pg_temp.l('cb03')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('g'))));
select pg_temp.caso('F14 individual de un reactivado (cb05) → 22023 no_descartado', '22023|cb05:no_descartado',
  pg_temp.rech(pg_temp.detalle(pg_temp.rep(pg_temp.b('B'), pg_temp.ind(array[pg_temp.l('cb05')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('s1'))));
insert into resp select 'F15', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('B'), pg_temp.ind(array[pg_temp.l('cb06')], array[pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('F15 individual de cb06 (armado, sigue con su analista anterior V1) a V1 → repartido sin tocar el lead (sin «reasignación»)', '1|v1:1||v1|v1|0',
  pg_temp.res((select v from resp where k = 'F15')) || '|' || pg_temp.duenos(array['cb06']) || '|' || pg_temp.pert(array['cb06']) || '|'
  || (select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('cb06') and a.tipo = 'reasignacion'));
insert into resp select 'F16', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k12')], array[pg_temp.a('v3')])), pg_temp.a('g'));
select pg_temp.caso('F16 Gerencia reparte k12 a V3 (otro equipo) → pasa', '1|v3:1||v3', pg_temp.res((select v from resp where k = 'F16')) || '|' || pg_temp.duenos(array['k12']));
select pg_temp.caso('F17 … S1 ya no ve k12 en la lista de A; Gerencia sí, sin tocar y con el nombre de su analista', 'false|k12:sin_tocar:ANALISTA TRES',
  pg_temp.valor(format('select (count(*) > 0)::text from crm.contactos_de_base(%L, ''todos'') x where x.lead_id = %L', pg_temp.b('A'), pg_temp.l('k12')), 'authenticated', pg_temp.a('s1'))
  || '|' || pg_temp.valor(format('select ''k12:'' || x.estado || '':'' || x.analista_nombre from crm.contactos_de_base(%L, ''todos'') x where x.lead_id = %L', pg_temp.b('A'), pg_temp.l('k12')), 'authenticated', pg_temp.a('g')));
select pg_temp.caso('F18 Gerencia vuelve a repartir k12 (B9 se lo dio a V3, fuera del equipo del dueño) → pasa', '1|v2:1|',
  pg_temp.res(pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k12')], array[pg_temp.a('v2')])), 'authenticated', pg_temp.a('g')))));
select pg_temp.caso('F19 … pero si OTRA vía sacó un repartido del equipo (k02 a V3), Gerencia no lo reparte → 22023', 'ok|ERROR 22023 1 de los contactos pedidos no se pueden repartir (en gestión, en descanso, No contactar o fuera de la base); no se repartió ninguno',
  pg_temp.secuencia(pg_temp.a('g'), format('PG:update crm.leads set vendedor_id = %L where id = %L returning ''ok''', pg_temp.a('v3'), pg_temp.l('k02')),
                    pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k02')], array[pg_temp.a('v1')]))));

-- ───────── G · Recoger ─────────
select pg_temp.sesion(null);
update crm.leads set vendedor_id = pg_temp.a('v2'), asignado_supervisor_id = null where id = pg_temp.l('k05');  -- otra vía (E14): la pertenencia sigue diciendo V1
insert into resp values ('opG', to_jsonb(gen_random_uuid()));
insert into resp select 'G1', pg_temp.ejecutar(pg_temp.rec(pg_temp.b('A'), pg_temp.a('v1'), (select (v #>> '{}')::uuid from resp where k = 'opG')), pg_temp.a('s1'));
select pg_temp.caso('G1 S1 recoge lo de V1 en A: k01, k04, k06 (sin tocar); quedan k03 (tocado) y k05 (movido por otra vía)', '3|2|0',
  pg_temp.reco((select v from resp where k = 'G1')));
select pg_temp.caso('G2 … los recogidos vuelven a la bandeja de S1 sin analista en la pertenencia; k03 sigue con V1 y k05 con V2', 'b:s1,b:s1,b:s1,v1,v2|-,-,-,v1,v1',
  pg_temp.duenos(array['k01', 'k04', 'k06', 'k03', 'k05']) || '|' || pg_temp.pert(array['k01', 'k04', 'k06', 'k03', 'k05']));
select pg_temp.caso('G3 … y salen de la Base para gestión de V1 (queda k03)', 'k03',
  pg_temp.valor('select string_agg(c.k, '','' order by c.k) from crm.obtener_base_gestion() o join pg_temp.c c on c.id = o.lead_id where c.k like ''k%''', 'authenticated', pg_temp.a('v1')));
select pg_temp.caso('G4 … siguen dormidos y sin episodio: descartados, sin ciclo SLA', '3|0',
  (select count(*) filter (where l.etapa = 'descartado' and l.tenencia_desde is null)::text || '|'
          || (select count(*) from crm.lead_sla_ciclos s where s.lead_id in (pg_temp.l('k01'), pg_temp.l('k04'), pg_temp.l('k06'))
              ) + (select count(*) from crm.lead_asignaciones s where s.lead_id in (pg_temp.l('k01'), pg_temp.l('k04'), pg_temp.l('k06')))
     from crm.leads l where l.id in (pg_temp.l('k01'), pg_temp.l('k04'), pg_temp.l('k06'))));
select pg_temp.prueba('G5 S1 recoge de V3 (otro equipo) → P0002', 'P0002 Analista no encontrado o fuera del equipo de la base',
  pg_temp.rec(pg_temp.b('A'), pg_temp.a('v3')), 'authenticated', pg_temp.a('s1'));
insert into resp select 'G6', pg_temp.ejecutar(pg_temp.rec(pg_temp.b('A'), pg_temp.a('v3')), pg_temp.a('g'));
select pg_temp.caso('G6 Gerencia recoge lo de V3 (k12) → vuelve a la bandeja del DUEÑO (S1), no a Gerencia', '1|0|0|b:s1|-',
  pg_temp.reco((select v from resp where k = 'G6')) || '|' || pg_temp.duenos(array['k12']) || '|' || pg_temp.pert(array['k12']));
select pg_temp.caso('G7 replay de la recogida → la MISMA respuesta; el mismo id con otro analista → 22023', 'true|ERROR 22023 Este identificador de operación ya se usó con un pedido distinto',
  (pg_temp.ejecutar(pg_temp.rec(pg_temp.b('A'), pg_temp.a('v1'), (select (v #>> '{}')::uuid from resp where k = 'opG')), pg_temp.a('s1')) = (select v from resp where k = 'G1'))::text
  || '|' || pg_temp.valor(pg_temp.rec(pg_temp.b('A'), pg_temp.a('v2'), (select (v #>> '{}')::uuid from resp where k = 'opG')), 'authenticated', pg_temp.a('s1')));
-- Seguimiento activo SIN intento desde el reparto: cb01 (V1 lo trabaja desde antes) se le «da» a V1 mismo y se intenta recoger.
insert into resp select 'G8a', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('B'), pg_temp.ind(array[pg_temp.l('cb01')], array[pg_temp.a('v1')])), pg_temp.a('s1'));
insert into resp select 'G8', pg_temp.ejecutar(pg_temp.rec(pg_temp.b('B'), pg_temp.a('v1')), pg_temp.a('s1'));
select pg_temp.caso('G8 recoger en B: cb06 (sin tocar) sí; cb01 (sin intento DESDE el reparto pero en seguimiento activo B6) no', '1|v1:1||1|1|0|v1,b:s1',
  pg_temp.res((select v from resp where k = 'G8a')) || '|' || pg_temp.reco((select v from resp where k = 'G8')) || '|' || pg_temp.duenos(array['cb01', 'cb06']));
select pg_temp.caso('G9a preparar: V2 registra un intento en k07 (tocado)', 'ok', pg_temp.ok(pg_temp.intento('k07', pg_temp.a('v2'))));
-- r1 (auditor P3): con V2 de baja, private.base_gestion_en_gestion_hasta da NULL (una baja libera) y recoger no exige «sin
-- intento»: también k07 (tocado) vuelve a la bandeja.
select pg_temp.caso('G9 recoger lo de un analista del equipo DADO DE BAJA (V2) → pasa TODO lo suyo, también k07 (tocado)', '4|0|0',
  pg_temp.reco(pg_temp.a_jsonb(pg_temp.tras(pg_temp.baja(pg_temp.a('v2')),
                                            pg_temp.rec(pg_temp.b('A'), pg_temp.a('v2')), pg_temp.a('s1')))));
-- Con V2 ACTIVO y un intento de hace 8 días (después de su reparto, hace 10; antes del descarte, así que B6 no lo cuenta):
-- solo «sin intento desde asignado_en» deja k07 (andamio: fechas movidas solo en esta transacción deshecha).
select pg_temp.caso('G9b un analista ACTIVO con un intento viejo (sin seguimiento activo B6) no pierde ese contacto: k02, k08, k09 sí; k07 no', '3|1|0',
  pg_temp.reco(pg_temp.a_jsonb(pg_temp.tras(format('update crm.actividades set creado_en = now() - interval ''8 days'' where lead_id = %1$L and metadata->>''evento'' = ''intento_base''; '
                                                   || 'update crm.base_carga_leads set asignado_en = now() - interval ''10 days'' where lead_id = %1$L and activo; '
                                                   || 'update crm.actividades set creado_en = now() - interval ''10 days'' where lead_id = %1$L and tipo = ''reasignacion''', pg_temp.l('k07')),
                                            pg_temp.rec(pg_temp.b('A'), pg_temp.a('v2')), pg_temp.a('s1')))));
select pg_temp.caso('G10 tope por operación (2): de 3 recogibles recoge 2 y deja 1 pendiente (k07, tocado y en gestión, omitido)', '2|1|1',
  pg_temp.reco(pg_temp.a_jsonb(pg_temp.tras('create or replace function private.bases_carga_reparto_constantes() returns table(max_contactos integer, max_analistas integer, holgura_candados integer) language sql immutable set search_path = '''' as $f$ select 2, 100, 50 $f$',
                                            pg_temp.rec(pg_temp.b('A'), pg_temp.a('v2')), pg_temp.a('s1')))));
select pg_temp.caso('G11 el supervisor dueño inactivo (recoge Gerencia) → 22023', 'ERROR 22023 El supervisor dueño de la base ya no está activo: no se puede recoger',
  pg_temp.tras(pg_temp.baja(pg_temp.a('s1')), pg_temp.rec(pg_temp.b('A'), pg_temp.a('v2')), pg_temp.a('g')));
insert into resp select 'G12a', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('C'), pg_temp.bq(array[pg_temp.a('va')], array[2])), pg_temp.a('s1'));
select pg_temp.caso('G12a S1 reparte 2 de la base de SUP-ANIDADO a su analista', '2|va:2||va,va,b:sa', pg_temp.res((select v from resp where k = 'G12a')) || '|' || pg_temp.duenos(pg_temp.ks('c', 1, 3)));
insert into resp select 'G12b', pg_temp.ejecutar(pg_temp.rec(pg_temp.b('C'), pg_temp.a('va')), pg_temp.a('s1'));
select pg_temp.caso('G12 … y S1 la recoge: vuelve a la bandeja del DUEÑO (sup-anidado), no a S1', '2|0|0|b:sa,b:sa,b:sa',
  pg_temp.reco((select v from resp where k = 'G12b')) || '|' || pg_temp.duenos(pg_temp.ks('c', 1, 3)));

-- ───────── H · contactos_de_base: los estados del contrato ─────────
insert into resp select 'E1', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('E'), pg_temp.ind(array[pg_temp.l('e02'), pg_temp.l('e03'), pg_temp.l('e04'), pg_temp.l('e05'), pg_temp.l('e06'), pg_temp.l('e07'), pg_temp.l('e10')],
                                                                                array[pg_temp.a('v1'), pg_temp.a('v1'), pg_temp.a('v1'), pg_temp.a('v1'), pg_temp.a('v1'), pg_temp.a('v1'), pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('H0 preparar E: 7 a V1; intentos (e03 uno, e04 tres → descanso), cita (e05), reactivar (e06), Reabrir (e10), No contactar (e08)',
  '7|v1:7||ok|ok|ok|ok|ok|ok|ok|ok',
  pg_temp.res((select v from resp where k = 'E1')) || '|' || pg_temp.ok(pg_temp.intento('e03', pg_temp.a('v1'))) || '|' || pg_temp.ok(pg_temp.intento('e04', pg_temp.a('v1')))
  || '|' || pg_temp.ok(pg_temp.intento('e04', pg_temp.a('v1'))) || '|' || pg_temp.ok(pg_temp.intento('e04', pg_temp.a('v1')))
  || '|' || pg_temp.ok(pg_temp.intento('e05', pg_temp.a('v1'), 'agendo_reunion'))
  || '|' || pg_temp.ok(pg_temp.ejecutar(format('select crm.reactivar_lead_base(gen_random_uuid(), %L, null)', pg_temp.l('e06')), pg_temp.a('v1')))
  || '|' || pg_temp.ok(pg_temp.ejecutar(format('select crm.reabrir_lead_fn(%L)', pg_temp.l('e10')), pg_temp.a('v1')))
  || '|' || pg_temp.ok(pg_temp.ejecutar(format('select crm.marcar_no_contactar(%L, ''B9 suite: no'')', pg_temp.l('e08')), pg_temp.a('s1'))));
select pg_temp.sesion(null);
update crm.leads set vendedor_id = pg_temp.a('v2'), asignado_supervisor_id = null where id = pg_temp.l('e07');   -- repartido y movido por otra vía (dentro del equipo)
update crm.leads set asignado_supervisor_id = null, vendedor_id = pg_temp.a('v3') where id = pg_temp.l('e09');   -- sin repartir, sacado del ámbito
select pg_temp.caso('H1 lista de E para S1 (todos): un estado por contacto, en el orden de llegada; e09 (otro equipo) no sale',
  'e01:sin_repartir,e02:sin_tocar,e03:trabajado,e04:en_descanso,e05:cita,e06:reactivado,e07:movido_otra_via,e08:no_contactar,e10:movido_otra_via',
  pg_temp.valor(pg_temp.lista(pg_temp.b('E')), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('H2 lista de E para Gerencia: también e09, movido por otra vía', 'e09:movido_otra_via',
  pg_temp.valor(format('select ''e09:'' || x.estado from crm.contactos_de_base(%L, ''todos'') x where x.lead_id = %L', pg_temp.b('E'), pg_temp.l('e09')), 'authenticated', pg_temp.a('g')));
select pg_temp.caso('H3 filtro por defecto = sin_repartir (e01, e08)', 'e01:sin_repartir,e08:no_contactar',
  pg_temp.valor(pg_temp.lista(pg_temp.b('E'), null), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('H4 filtro sin_repartir explícito y NULL = el mismo', 'true',
  (pg_temp.valor(pg_temp.lista(pg_temp.b('E'), 'sin_repartir'), 'authenticated', pg_temp.a('s1'))
   = pg_temp.valor(format('select coalesce(string_agg(coalesce(c.k, ''?'') || '':'' || x.estado, '','' order by x.n), ''(vacía)'') from crm.contactos_de_base(%L, null) with ordinality x(lead_id, nombre_completo, telefono, distrito, agregado_en, analista_id, analista_nombre, estado, n) left join pg_temp.c c on c.id = x.lead_id', pg_temp.b('E')), 'authenticated', pg_temp.a('s1')))::text);
select pg_temp.caso('H5 filtro repartidos', 'e02:sin_tocar,e03:trabajado,e04:en_descanso,e05:cita,e06:reactivado,e07:movido_otra_via,e10:movido_otra_via',
  pg_temp.valor(pg_temp.lista(pg_temp.b('E'), 'repartidos'), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('H6 columnas de un repartido: nombre, teléfono, distrito, agregado_en (= llegada a la base), analista y su nombre', 'B9 E02|+51966920402|Lince|v1|ANALISTA UNO|true',
  (select regexp_replace(q.v, '\|[^|]*$', '') || '|'
          || (split_part(q.v, '|', 6) = (select bl.creado_en::text from crm.base_carga_leads bl where bl.lead_id = pg_temp.l('e02') and bl.activo))::text
     from (select pg_temp.valor(format('select concat_ws(''|'', x.nombre_completo, x.telefono, x.distrito, pg_temp.ak(x.analista_id), x.analista_nombre, x.agregado_en::text) from crm.contactos_de_base(%L, ''todos'') x where x.lead_id = %L',
                                       pg_temp.b('E'), pg_temp.l('e02')), 'authenticated', pg_temp.a('s1')) v) q));
select pg_temp.caso('H7 el contacto retirado (cb02) no sale ni para Gerencia', '0',
  pg_temp.valor(format('select count(*)::text from crm.contactos_de_base(%L, ''todos'') x where x.lead_id = %L', pg_temp.b('B'), pg_temp.l('cb02')), 'authenticated', pg_temp.a('g')));
select pg_temp.caso('H8 la lista de B para S1 no trae NINGÚN contacto fuera de su ámbito ni retirado (4 contactos, 0 fuera)', '4|0',
  (select cardinality(string_to_array(q.v, ','))::text || '|' || pg_temp.fuera(q.v, pg_temp.a('s1'), 'supervisor')
     from (select pg_temp.valor(format('select string_agg(x.lead_id::text, '','') from crm.contactos_de_base(%L, ''todos'') x', pg_temp.b('B')), 'authenticated', pg_temp.a('s1')) v) q));
-- Un intento registrado DURANTE la operación (misma sentencia: la «reasignación» lleva su hora) no lo hereda el analista nuevo:
-- el individual falla con 55P03 (reintenta); el bloque lo salta («ocupado») y reparte el siguiente.
select pg_temp.caso('H9x intento de S1 sobre e01 y reparto individual a V1 en la MISMA sentencia → 55P03 (no se hereda)', 'ok|ERROR 55P03 Otra operación está usando alguno de esos contactos; reintenta',
  pg_temp.secuencia(pg_temp.a('s1'), format('select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', null, null)', pg_temp.l('e01')),
                    pg_temp.rep(pg_temp.b('E'), pg_temp.ind(array[pg_temp.l('e01')], array[pg_temp.a('v1')]))));
select pg_temp.caso('H9y … en bloque (base A: k01 el más antiguo sin repartir) → salta k01 («ocupado») y reparte k04', 'ok|1|v2:1|en_descanso:1,no_contactar:1,ocupado:1|v2',
  (select split_part(s, '|', 1) || '|' || pg_temp.res(pg_temp.a_jsonb(split_part(s, '|', 2))) || '|' || split_part(s, '|', 3)
     from pg_temp.secuencia(pg_temp.a('s1'), format('select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', null, null)', pg_temp.l('k01')),
                            pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v2')], array[1])),
                            format('PG:select pg_temp.ak(vendedor_id) from crm.leads where id = %L', pg_temp.l('k04'))) s));
select pg_temp.caso('H9a preparar: S1 registra un intento sobre e01 (sin repartir, en SU bandeja)', 'ok', pg_temp.ok(pg_temp.intento('e01', pg_temp.a('s1'))));
insert into resp select 'H9', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('E'), pg_temp.ind(array[pg_temp.l('e01')], array[pg_temp.a('v1')])), pg_temp.a('s1'));
select pg_temp.caso('H9 … en otra sentencia, e01 a V1: para V1 está «sin tocar» (los hechos cuentan desde asignado_en)', '1|v1:1||e01:sin_tocar',
  pg_temp.res((select v from resp where k = 'H9')) || '|'
  || pg_temp.valor(format('select ''e01:'' || x.estado from crm.contactos_de_base(%L, ''repartidos'') x where x.lead_id = %L', pg_temp.b('E'), pg_temp.l('e01')), 'authenticated', pg_temp.a('s1')));
-- ───────── R · La regla nueva de B6 (Miguel, 04/10): el seguimiento activo cuenta desde que el DUEÑO ACTUAL recibió el lead ─────────
select pg_temp.caso('R1 la llamada de S1 sobre su bandeja ANTES de repartir no deja a V1 en gestión (ayudante NULL)', 'null',
  coalesce(private.base_gestion_en_gestion_hasta(pg_temp.l('e01'))::text, 'null'));
select pg_temp.caso('R2 un intento del analista que lo tiene (V1 en k03) → en gestión 7 días', 'true',
  (private.base_gestion_en_gestion_hasta(pg_temp.l('k03')) = (now() at time zone 'America/Lima')::date + 7)::text);
select pg_temp.caso('R3 dueño anterior con un intento (V2 en k07, dado de baja) y reasignado a V1 → V1 NO hereda el candado', 'ok|1|v1:1||null',
  (select split_part(x.s, '|', 1) || '|' || pg_temp.res(pg_temp.a_jsonb(split_part(x.s, '|', 2))) || '|' || split_part(x.s, '|', 3)
     from (select pg_temp.secuencia(pg_temp.a('s1'), 'PG!' || pg_temp.baja(pg_temp.a('v2')),
                                    pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k07')], array[pg_temp.a('v1')])),
                                    format('PG:select coalesce(private.base_gestion_en_gestion_hasta(%L)::text, ''null'')', pg_temp.l('k07'))) as s) x));
select pg_temp.caso('R4 un intento de S1 sobre un lead que YA es de V1 (e02, repartido a V1) cuenta para V1 → en gestión 7 días', 'ok|true',
  (select split_part(x.s, '|', 1) || '|' || split_part(x.s, '|', 2)
     from (select pg_temp.secuencia(pg_temp.a('s1'), format('select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', null, null)', pg_temp.l('e02')),
                                    format('PG:select (private.base_gestion_en_gestion_hasta(%L) = (now() at time zone ''America/Lima'')::date + 7)::text', pg_temp.l('e02'))) as s) x));
select pg_temp.caso('R7 el gris del Centro de rescate sigue: un descarte del mes de V1 con un intento (de S1) → no se puede rescatar, «en gestión por» V1 hasta hoy + 7', 'ok|ok|ok|false,ANALISTA UNO,true',
  pg_temp.secuencia(pg_temp.a('s1'),
    format('PG:insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values (''b9000000-0000-4000-8000-000000000007'', ''B9 RESCATE'', ''966920601'', ''oficina'', ''nuevo'', %1$L, 1000, ''PEN'', %1$L, true) returning ''ok''', pg_temp.a('v1')),
    'PG:update crm.leads set etapa = ''descartado'', motivo_descarte = ''sin_interes'' where id = ''b9000000-0000-4000-8000-000000000007'' returning ''ok''',
    'select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), ''b9000000-0000-4000-8000-000000000007'', ''no_contesto'', null, null)',
    'select x.puede_rescatar::text || '','' || x.en_gestion_por || '','' || (x.en_gestion_hasta = (now() at time zone ''America/Lima'')::date + 7)::text from crm.rescate_descartes_mes((now() at time zone ''America/Lima'')::date) x where x.lead_id = ''b9000000-0000-4000-8000-000000000007'''));
select pg_temp.caso('R5 el candado del lead (toda vía): S1 mueve e01 de V1 a V2 por la tabla → PASA (la llamada de S1 fue antes de que V1 lo recibiera)', 'paso',
  pg_temp.valor(format('update crm.leads set vendedor_id = %L where id = %L returning ''paso''', pg_temp.a('v2'), pg_temp.l('e01')), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('R6 … y con un intento de V1 (ya suyo) el candado sigue: mover k03 → P0409', 'ERROR P0409',
  left(pg_temp.valor(format('update crm.leads set vendedor_id = %L where id = %L returning 1', pg_temp.a('v2'), pg_temp.l('k03')), 'authenticated', pg_temp.a('s1')), 11));
select pg_temp.sesion(null);
update crm.leads set activo = false where id = pg_temp.l('e02');   -- retirado después del reparto
-- r1: e01 está «sin tocar» por V1 y la llamada de S1 fue ANTES de que V1 lo recibiera: con la regla nueva de B6 no es seguimiento
-- activo de V1 → recoger se lo lleva.
insert into resp select 'H10', pg_temp.ejecutar(pg_temp.rec(pg_temp.b('E'), pg_temp.a('v1')), pg_temp.a('s1'));
select pg_temp.caso('H10 S1 recoge lo de V1 en E: SOLO e01 (la llamada de S1 fue antes del reparto: regla nueva de B6); el retirado, los tocados, la cita, el reactivado, el movido y el reabierto quedan', '1|7|0|b:s1,v1,v1',
  pg_temp.reco((select v from resp where k = 'H10')) || '|' || pg_temp.duenos(array['e01', 'e02', 'e06']));
-- r2 · R8: la rellamada del dueño anterior no la hereda el nuevo: se lee del último intento posterior al corte, no de la columna
-- del lead (que aquí se deja «vieja» a propósito, andamio).
select pg_temp.caso('R8 rellamada del dueño anterior (V1, a 9 días) → de baja → reasignado a V2 → intento de V2 sin agendar: el candado dura SOLO los 7 días de su intento', 'ok|ok|ok|ok|ok|ok|ok|true',
  pg_temp.secuencia(pg_temp.a('s1'),
    format('PG:insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values (''b9000000-0000-4000-8000-000000000008'', ''B9 R8'', ''966920602'', ''oficina'', ''nuevo'', %1$L, 1000, ''PEN'', %1$L, true) returning ''ok''', pg_temp.a('v1')),
    'PG:update crm.leads set etapa = ''descartado'', motivo_descarte = ''sin_interes'' where id = ''b9000000-0000-4000-8000-000000000008'' returning ''ok''',
    format('AS:%s:select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), ''b9000000-0000-4000-8000-000000000008'', ''volver_a_llamar'', null, now() + interval ''9 days'')', pg_temp.a('v1')),
    'PG!' || pg_temp.baja(pg_temp.a('v1')),
    format('update crm.leads set vendedor_id = %L where id = ''b9000000-0000-4000-8000-000000000008'' returning ''ok''', pg_temp.a('v2')),
    format('AS:%s:select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), ''b9000000-0000-4000-8000-000000000008'', ''no_contesto'', null, null)', pg_temp.a('v2')),
    'PG:update crm.leads set proxima_llamada_en = now() + interval ''9 days'' where id = ''b9000000-0000-4000-8000-000000000008'' returning ''ok''',
    'PG:select (private.base_gestion_en_gestion_hasta(''b9000000-0000-4000-8000-000000000008'') = (now() at time zone ''America/Lima'')::date + 7)::text'));
-- R9 A → B → A, paso a paso (cada movimiento en su propia sentencia: la «reasignación» lleva la hora de la sentencia).
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
values ('b9000000-0000-4000-8000-000000000009', 'B9 R9', '966920603', 'oficina', 'nuevo', pg_temp.a('v1'), 1000, 'PEN', pg_temp.a('v1'), true);
update crm.leads set etapa = 'descartado', motivo_descarte = 'sin_interes' where id = 'b9000000-0000-4000-8000-000000000009';
insert into c values ('r9', 'b9000000-0000-4000-8000-000000000009');
create temp table r9 (paso text, v text);
insert into r9 select '1', pg_temp.ok(pg_temp.intento('r9', pg_temp.a('v1')));
select pg_temp.exec(pg_temp.baja(pg_temp.a('v1')));
insert into r9 select '2', pg_temp.ok(pg_temp.ejecutar(format('update crm.leads set vendedor_id = %L where id = %L returning jsonb_build_object(''ok'', true)', pg_temp.a('v2'), pg_temp.l('r9')), pg_temp.a('s1')));
insert into r9 select '3', pg_temp.ok(pg_temp.intento('r9', pg_temp.a('v2')));
select pg_temp.exec(pg_temp.alta(pg_temp.a('v1')) || '; ' || pg_temp.baja(pg_temp.a('v2')));
insert into r9 select '4', pg_temp.ok(pg_temp.ejecutar(format('update crm.leads set vendedor_id = %L where id = %L returning jsonb_build_object(''ok'', true)', pg_temp.a('v1'), pg_temp.l('r9')), pg_temp.a('s1')));
insert into r9 select '5', coalesce(private.base_gestion_en_gestion_hasta(pg_temp.l('r9'))::text, 'null');
insert into r9 select '6', pg_temp.ok(pg_temp.intento('r9', pg_temp.a('v1')));
insert into r9 select '7', (private.base_gestion_en_gestion_hasta(pg_temp.l('r9')) = (now() at time zone 'America/Lima')::date + 7)::text;
select pg_temp.exec(pg_temp.alta(pg_temp.a('v2')));
select pg_temp.caso('R9 A → B → A: intento de V1, pasa a V2 (V1 de baja), intento de V2, vuelve a V1 (V2 de baja): nada bloquea a V1; un intento suyo, 7 días', 'ok|ok|ok|ok|null|ok|true',
  (select string_agg(v, '|' order by paso) from r9));
select pg_temp.caso('R10 una «reasignación» SIN cambio de vendedor (V1 → V1, andamio) no corta: el intento previo de V1 sigue contando', 'ok|ok|ok|ok|true',
  pg_temp.secuencia(pg_temp.a('s1'),
    format('PG:insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo) values (''b9000000-0000-4000-8000-00000000000a'', ''B9 R10'', ''966920604'', ''oficina'', ''nuevo'', %1$L, 1000, ''PEN'', %1$L, true) returning ''ok''', pg_temp.a('v1')),
    'PG:update crm.leads set etapa = ''descartado'', motivo_descarte = ''sin_interes'' where id = ''b9000000-0000-4000-8000-00000000000a'' returning ''ok''',
    format('AS:%s:select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), ''b9000000-0000-4000-8000-00000000000a'', ''no_contesto'', null, null)', pg_temp.a('v1')),
    format('PG:insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en) values (''b9000000-0000-4000-8000-00000000000a'', ''reasignacion'', ''x'', jsonb_build_object(''movimiento'', ''sin_cambio'', ''vendedor_anterior'', %1$L::uuid, ''vendedor_nuevo'', %1$L::uuid), %1$L, clock_timestamp()) returning ''ok''', pg_temp.a('v1')),
    'PG:select (private.base_gestion_en_gestion_hasta(''b9000000-0000-4000-8000-00000000000a'') = (now() at time zone ''America/Lima'')::date + 7)::text'));

-- ───────── I · El replay vuelve a juzgar lo que nombra ─────────
insert into resp values ('opI', to_jsonb(gen_random_uuid()));
insert into resp select 'I1', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k09')], array[pg_temp.a('v2')]), (select (v #>> '{}')::uuid from resp where k = 'opI')), pg_temp.a('s1'));
select pg_temp.caso('I1 S1: k09 a V2 (ya es suyo) → el recibo nombra k09 (ya_asignado)', '0||k09:ya_asignado', pg_temp.res((select v from resp where k = 'I1')));
select pg_temp.caso('I2 Gerencia lleva k09 a V3 (fuera del ámbito de S1)', '1|v3:1|',
  pg_temp.res(pg_temp.ejecutar(pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k09')], array[pg_temp.a('v3')])), pg_temp.a('g'))));
select pg_temp.prueba('I3 el replay de S1 ya no devuelve k09 → P0002', 'P0002 La respuesta guardada nombra contactos que ya no están a tu alcance; repite la operación con otro identificador',
  pg_temp.rep(pg_temp.b('A'), pg_temp.ind(array[pg_temp.l('k09')], array[pg_temp.a('v2')]), (select (v #>> '{}')::uuid from resp where k = 'opI')), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('I4 el replay del bloque (sin referencias) sigue devolviendo su recibo', 'true',
  (pg_temp.a_jsonb(pg_temp.valor(pg_temp.rep(pg_temp.b('A'), pg_temp.bq(array[pg_temp.a('v1'), pg_temp.a('v2')], array[5, 4]), (select (v #>> '{}')::uuid from resp where k = 'opA')), 'authenticated', pg_temp.a('s1')))
   = (select v from resp where k = 'A1'))::text);

-- ───────── K · Efectos ─────────
select pg_temp.caso('K1 ningún contacto de A (todos siguen descartados) tiene ciclo SLA, etapa SLA ni episodio', '0|0|0',
  (select count(*) from crm.lead_sla_ciclos s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%')::text || '|'
  || (select count(*) from crm.lead_sla_etapas s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%')::text || '|'
  || (select count(*) from crm.lead_asignaciones s join pg_temp.c c on c.id = s.lead_id where c.k like 'k%')::text);
select pg_temp.caso('K2 el candado B6 sigue en el lead: S1 mueve k03 (en gestión de V1) por la tabla → P0409', 'ERROR P0409',
  left(pg_temp.valor(format('update crm.leads set vendedor_id = %L where id = %L returning 1', pg_temp.a('v2'), pg_temp.l('k03')), 'authenticated', pg_temp.a('s1')), 11));
select pg_temp.caso('K3 recibos de S1: 1 por operación nueva (repartir y recoger), ninguno por replay ni por rechazo', 'true',
  (select (count(*) filter (where o.tipo = 'repartir') = 11 and count(*) filter (where o.tipo = 'recoger') = 4)::text
     from crm.base_carga_operaciones o where o.actor = pg_temp.a('s1') and o.tipo in ('repartir', 'recoger') and o.base_id in (select id from pg_temp.bases)));

-- ───────── Q · Las actividades «reasignación» (el corte de B6) no se cambian ni se borran ─────────
create temp table q as select (select a.id from crm.actividades a where a.lead_id = pg_temp.l('k01') and a.tipo = 'reasignacion' and a.creado_por = pg_temp.a('s1') order by a.creado_en limit 1) reasig;
grant select on q to authenticated;
select pg_temp.caso('Q1 authenticated y anon sin UPDATE, DELETE ni TRUNCATE en crm.actividades (solo INSERT y SELECT)', 'false|false|false|false|false|false',
  concat_ws('|', has_table_privilege('authenticated', 'crm.actividades', 'UPDATE')::text, has_table_privilege('authenticated', 'crm.actividades', 'DELETE')::text,
            has_table_privilege('authenticated', 'crm.actividades', 'TRUNCATE')::text, has_table_privilege('anon', 'crm.actividades', 'UPDATE')::text,
            has_table_privilege('anon', 'crm.actividades', 'DELETE')::text, has_table_privilege('anon', 'crm.actividades', 'TRUNCATE')::text));
select pg_temp.caso('Q2 las ÚNICAS funciones que hacen UPDATE o DELETE en crm.actividades son las 4 conocidas (B10: el núcleo de intentos es el de capital; el de siempre lo envuelve)',
  case when (select aplicada from pg_temp.b10) then 'crm.deshacer_resultado_llamada(uuid),private.base_gestion_intento_capital_core(uuid,uuid,uuid,text,text,timestamp with time zone,numeric,text),private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean),private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)'
       else 'crm.deshacer_resultado_llamada(uuid),private.base_gestion_intento_core(uuid,uuid,uuid,text,text,timestamp with time zone),private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean),private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)' end,
  (select string_agg(p.oid::regprocedure::text, ',' order by p.oid::regprocedure::text) from pg_proc p where p.prosrc ~* '(update|delete\s+from)\s+crm\.actividades'));
select pg_temp.prueba('Q3 S1 cambia la metadata de una «reasignación» por la tabla → 42501', '42501 permission denied for table actividades',
  format('update crm.actividades set metadata = metadata || ''{"vendedor_nuevo": null}'' where id = %L', (select reasig from q)), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('Q4 S1 la borra → 42501', '42501 permission denied for table actividades',
  format('delete from crm.actividades where id = %L', (select reasig from q)), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('Q5 Gerencia le cambia el tipo y la fecha → 42501', '42501 permission denied for table actividades',
  format('update crm.actividades set tipo = ''nota'', creado_en = now() - interval ''30 days'' where id = %L', (select reasig from q)), 'authenticated', pg_temp.a('g'));
select pg_temp.caso('Q6 intento de la base con el id de esa «reasignación» (de S1) como operación → 23505, no la toca', 'ERROR 23505 Esta operacion ya corresponde a otro contenido',
  pg_temp.valor(format('select crm.registrar_intento_base(%L, %L, ''no_contesto'', null, null)', (select reasig from q), pg_temp.l('k10')), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('Q7 deshacer un resultado de llamada con el id de esa «reasignación» → 22023, no la toca', 'ERROR 22023 Esta actividad no es un resultado de llamada',
  pg_temp.valor(format('select crm.deshacer_resultado_llamada(%L)', (select reasig from q)), 'authenticated', pg_temp.a('s1')));
select pg_temp.caso('Q8 registrar una llamada (v4) con el id de esa «reasignación» como operación → 23505 (choque de clave), no la toca', 'ERROR 23505',
  left(pg_temp.valor(format('select crm.registrar_llamada_v4(%L, %L, ''no_contesto'')', (select reasig from q),
                            (select l.id from crm.leads l where l.vendedor_id = pg_temp.a('v1') and l.activo and l.etapa in ('nuevo', 'contactado') order by l.id limit 1)),
                     'authenticated', pg_temp.a('v1')), 11));
select pg_temp.caso('Q9 … y la «reasignación» sigue igual (tipo, vendedor_nuevo, fecha)', 'reasignacion|true',
  (select a.tipo || '|' || ((a.metadata->>'vendedor_nuevo')::uuid = pg_temp.a('v1'))::text from crm.actividades a where a.id = (select reasig from q)));
-- r3 (auditor P3): el corte de B6 no se puede FABRICAR. k03 es de V1 y está en gestión (su intento, F7): ni una «reasignación»
-- falsa (que cortaría desde el futuro) ni un intento falso (con una rellamada lejana) entran por la API, y el candado no cambia.
select pg_temp.caso('Q10 k03 en gestión de V1 (su intento): hoy + 7', 'true',
  (private.base_gestion_en_gestion_hasta(pg_temp.l('k03')) = (now() at time zone 'America/Lima')::date + 7)::text);
select pg_temp.prueba('Q11 S1 inserta una «reasignación» falsa hacia V1 (fechada en el futuro) → 42501 de la RLS (la policy de INSERT excluye el tipo)',
  '42501 new row violates row-level security policy for table "actividades"',
  format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en) values (%L, ''reasignacion'', ''falsa'', jsonb_build_object(''movimiento'', ''transferido'', ''vendedor_anterior'', %L::uuid, ''vendedor_nuevo'', %L::uuid), %L, now() + interval ''1 hour'')',
         pg_temp.l('k03'), pg_temp.a('v2'), pg_temp.a('v1'), pg_temp.a('s1')), 'authenticated', pg_temp.a('s1'));
select pg_temp.prueba('Q12 S1 inserta un intento falso (nota con evento intento_base y rellamada a 30 días) → 42501 del sello de la base para gestión',
  '42501 Las actividades de la base para gestion solo las escribe su nucleo',
  format('insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por) values (%L, ''nota'', ''falso'', jsonb_build_object(''evento'', ''intento_base'', ''resultado'', ''volver_a_llamar'', ''intento_n'', 1, ''ciclo_n'', 1, ''proxima_llamada_en'', now() + interval ''30 days''), %L)',
         pg_temp.l('k03'), pg_temp.a('s1')), 'authenticated', pg_temp.a('s1'));
select pg_temp.caso('Q13 … y el candado de k03 no cambió (hoy + 7) y no entró ninguna de las dos', 'true|0',
  (private.base_gestion_en_gestion_hasta(pg_temp.l('k03')) = (now() at time zone 'America/Lima')::date + 7)::text || '|'
  || (select count(*)::text from crm.actividades a where a.lead_id = pg_temp.l('k03') and a.detalle in ('falsa', 'falso')));
-- Control de la prueba: si entraran (como postgres sin usuario, en transacciones deshechas), la «reasignación» falsa LIBERARÍA k03
-- y el intento falso lo ALARGARÍA a 30 días: por eso importa que la API los rechace.
select pg_temp.caso('Q14 (control) si entraran: la «reasignación» falsa libera k03 (NULL) y el intento falso lo alarga a 30 días', 'x|null|x|true',
  pg_temp.secuencia(pg_temp.a('s1'),
    format('PG:insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en) values (%L, ''reasignacion'', ''falsa'', jsonb_build_object(''movimiento'', ''transferido'', ''vendedor_anterior'', %L::uuid, ''vendedor_nuevo'', %L::uuid), %L, now() + interval ''1 hour'') returning ''x''',
           pg_temp.l('k03'), pg_temp.a('v2'), pg_temp.a('v1'), pg_temp.a('s1')),
    format('PG:select coalesce(private.base_gestion_en_gestion_hasta(%L)::text, ''null'')', pg_temp.l('k03'))) || '|'
  || pg_temp.secuencia(pg_temp.a('s1'),
    format('PG:insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por, creado_en) values (%L, ''nota'', ''falso'', jsonb_build_object(''evento'', ''intento_base'', ''resultado'', ''volver_a_llamar'', ''intento_n'', 1, ''ciclo_n'', 1, ''proxima_llamada_en'', now() + interval ''30 days''), %L, clock_timestamp()) returning ''x''',
           pg_temp.l('k03'), pg_temp.a('s1')),
    format('PG:select (private.base_gestion_en_gestion_hasta(%L) = ((now() + interval ''30 days'') at time zone ''America/Lima'')::date)::text', pg_temp.l('k03'))));

-- ───────── P · Presupuesto de candados (Codex r2): los rechazados bajo candado no se acumulan sin límite ─────────
-- Un intento registrado DURANTE la operación (misma sentencia) hace que el contacto pase la foto y caiga en la revisión bajo
-- candado: queda bloqueado. Con 60 así y un bloque de 1, el presupuesto (1 + 50) se agota → 55P03, nada se reparte.
select pg_temp.caso('P1 60 contactos que caen bajo candado y un bloque de 1 → presupuesto agotado (51) → 55P03, todo o nada', repeat('ok|', 60) || 'ERROR 55P03 Los contactos están cambiando; reintenta',
  pg_temp.secuencia(pg_temp.a('s1'), variadic (select array_agg(format('select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', null, null)', pg_temp.l(k)) order by k)
                                               from unnest(pg_temp.ks('f', 1, 60)) k)
                                       || pg_temp.rep(pg_temp.b('F'), pg_temp.bq(array[pg_temp.a('v1')], array[1]))));
select pg_temp.caso('P2 con 5 así y un bloque de 2 → dentro del presupuesto: reparte f06 y f07, «ocupado» 5', 'ok|ok|ok|ok|ok|2|v1:2|ocupado:5|v1,v1',
  (select concat_ws('|', split_part(x.s, '|', 1), split_part(x.s, '|', 2), split_part(x.s, '|', 3), split_part(x.s, '|', 4), split_part(x.s, '|', 5))
          || '|' || pg_temp.res(pg_temp.a_jsonb(split_part(x.s, '|', 6))) || '|' || split_part(x.s, '|', 7)
     from (select pg_temp.secuencia(pg_temp.a('s1'), variadic (select array_agg(format('select ''ok'' from crm.registrar_intento_base(gen_random_uuid(), %L, ''no_contesto'', null, null)', pg_temp.l(k)) order by k)
                                                                 from unnest(pg_temp.ks('f', 1, 5)) k)
                                                         || pg_temp.rep(pg_temp.b('F'), pg_temp.bq(array[pg_temp.a('v1')], array[2]))
                                                         || format('PG:select pg_temp.ak(l6.vendedor_id) || '','' || pg_temp.ak(l7.vendedor_id) from crm.leads l6, crm.leads l7 where l6.id = %L and l7.id = %L', pg_temp.l('f06'), pg_temp.l('f07'))) as s) x));
insert into resp select 'P3', pg_temp.ejecutar(pg_temp.rep(pg_temp.b('F'), pg_temp.bq(array[pg_temp.a('v1')], array[10])), pg_temp.a('s1'));
select pg_temp.caso('P3 preparar: f01…f10 a V1', '10|v1:10|', pg_temp.res((select v from resp where k = 'P3')));
-- Recoger: la revisión bajo candado se instrumenta (solo en esta transacción deshecha) para rechazar todo; con tope 2 y holgura
-- 3 el presupuesto es 5 → 55P03. Control: sin instrumentar, recoge 2 y deja 8 pendientes.
select pg_temp.caso('P4 recoger: si todo cae bajo candado, el presupuesto (tope 2, holgura 3 → 5) se agota → 55P03', 'ERROR 55P03 Los contactos están cambiando; reintenta',
  pg_temp.tras('create or replace function private.bases_carga_reparto_constantes() returns table(max_contactos integer, max_analistas integer, holgura_candados integer) language sql immutable set search_path = '''' as $f$ select 2, 100, 3 $f$; '
               || 'create temp table if not exists vistos (id uuid); '
               || 'create or replace function private.bases_carga_reparto_recogible(p_lead_id uuid, p_analista_id uuid, p_asignado_en timestamptz, p_baja boolean) returns boolean language plpgsql set search_path = '''' as $f$ begin if exists (select 1 from pg_temp.vistos v where v.id = p_lead_id) then return false; end if; insert into pg_temp.vistos values (p_lead_id); return true; end $f$',
               pg_temp.rec(pg_temp.b('F'), pg_temp.a('v1')), pg_temp.a('s1')));
select pg_temp.caso('P5 control: con tope 2 y holgura 3, sin instrumentar → recoge 2 y deja 8 pendientes', '2|0|8',
  pg_temp.reco(pg_temp.a_jsonb(pg_temp.tras('create or replace function private.bases_carga_reparto_constantes() returns table(max_contactos integer, max_analistas integer, holgura_candados integer) language sql immutable set search_path = '''' as $f$ select 2, 100, 3 $f$',
                                            pg_temp.rec(pg_temp.b('F'), pg_temp.a('v1')), pg_temp.a('s1')))));

-- ───────── L · Regresión ─────────
select pg_temp.caso('L1 B8 sigue cargando en una base con contactos repartidos', '1:cargada',
  (select string_agg((x->>'fila') || ':' || (x->>'veredicto'), ',') from jsonb_array_elements(
     pg_temp.ejecutar(format('select crm.cargar_base_lote(gen_random_uuid(), %L, %L::jsonb)', pg_temp.b('A'), pg_temp.filas('n', 1, 1, '9669205')), pg_temp.a('s1'))->'filas') x));
select pg_temp.caso('L2 el sello del descarte conserva su huella', '150d7ae56bb2094733f7620a1362c29e',
  (select md5(pg_get_functiondef('private.trg_leads_zz_sello_descarte()'::regprocedure))));

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 300)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B9: hay casos FAIL'; end if; end $$;
rollback;
