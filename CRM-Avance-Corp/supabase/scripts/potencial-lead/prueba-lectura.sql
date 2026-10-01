-- Prueba sintética de 20261001151704_crm_potencial_lead_lectura (fase 3, entrega A).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- ⚠️ Nunca se llama a una función sin EXECUTE bajo `set role` (tumba Postgres 17.6 con plan_filter):
-- el núcleo se llama como supabase_admin con la sesión del actor fijada; la puerta, como authenticated.
--
-- Mundo: gerencia G · supervisor S1 con sub-supervisor S1n · analista V1 (de S1) y V1n (de S1n) ·
-- supervisor S2 con analista V2 · coordinador C · directorio D · X con equipo inactivo ·
-- DH directorio HISTÓRICO (perfil de directorio sin fila en crm.equipo: lector global por la vía
-- vieja) · XP con el PERFIL inactivo aunque su fila de equipo siga activa · P usuario solo del
-- portal (sin fila en crm.equipo) · DM pareja desalineada (perfil de directorio con equipo vendedor).
-- Calendario simulado (hora de Lima): las marcas se ponen el lunes 2026-10-05 10:00.
--   L1  V1  contactado  estrella (antes tibio)      L1n V1n nuevo       tibio
--   L2  V2  contactado  estrella + contacto jue 08  LP  parqueado en S1 frío
--   LC  V1  convertido  estrella (congelada)        LD  V1  descartado  tibio (congelada)
--   LI  V1  INACTIVO    estrella (nadie lo ve)      L3  V1  contactado  sin marca
--   LPV parqueado con «supervisor» V1, sin marca    LK  V1  contactado  tibio que BAJÓ SOLA de estrella
--   LZ  V1  contactado  estrella marcada vie 09 21:00 Lima (en UTC ya es sábado)
--   LS  SIN ASIGNAR (sin analista ni supervisor), sin marca: solo lo ven gerencia y directorio, y
--       es el único lead que depende de la rama «rol = gerencia» de la policy.
--   NADA: un id que no existe.
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('G'), ('S1'), ('S1n'), ('V1'), ('V1n'), ('S2'), ('V2'), ('C'), ('D'), ('X'), ('DH'), ('XP'), ('P'), ('DM');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('L1'), ('L1n'), ('L2'), ('LP'), ('LC'), ('LD'), ('LI'), ('L3'), ('LPV'), ('LK'), ('LZ'), ('LS'), ('NADA');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.todos() returns uuid[] language sql as $$ select array_agg(id) from lds $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;
create function pg_temp.lima(p_texto text) returns timestamptz language sql as $$
  select (p_texto::timestamp at time zone 'America/Lima')
$$;

-- Fixtures sin disparadores (solo filas que cumplen los CHECK).
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@lectura.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo)
  select id, 'LECTURA ' || k, case when k in ('D', 'DH', 'DM') then 'directorio' when k = 'G' then 'admin' else 'analista' end, k <> 'XP' from act;
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
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, asignado_supervisor_id, activo, motivo_descarte) values
  (pg_temp.l('L1'),  'LECTURA L1',  '+51987640001', 'landing', 50000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('L1n'), 'LECTURA L1N', '+51987640002', 'landing', 15000, 'PEN', 'nuevo',      pg_temp.a('V1n'), null, true, null),
  (pg_temp.l('L2'),  'LECTURA L2',  '+51987640003', 'landing', 30000, 'PEN', 'contactado', pg_temp.a('V2'),  null, true, null),
  (pg_temp.l('LP'),  'LECTURA LP',  '+51987640004', 'landing', 12000, 'PEN', 'nuevo',      null, pg_temp.a('S1'), true, null),
  (pg_temp.l('LC'),  'LECTURA LC',  '+51987640005', 'landing', 20000, 'PEN', 'convertido', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LD'),  'LECTURA LD',  '+51987640006', 'landing', 20000, 'PEN', 'descartado', pg_temp.a('V1'),  null, true, 'sin_interes'),
  (pg_temp.l('LI'),  'LECTURA LI',  '+51987640007', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, false, null),
  (pg_temp.l('L3'),  'LECTURA L3',  '+51987640008', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LPV'), 'LECTURA LPV', '+51987640009', 'landing', 20000, 'PEN', 'nuevo',      null, pg_temp.a('V1'), true, null),
  (pg_temp.l('LK'),  'LECTURA LK',  '+51987640010', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LZ'),  'LECTURA LZ',  '+51987640011', 'landing', 20000, 'PEN', 'contactado', pg_temp.a('V1'),  null, true, null),
  (pg_temp.l('LS'),  'LECTURA LS',  '+51987640012', 'landing', 20000, 'PEN', 'nuevo',      null, null, true, null);
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en) values
  (pg_temp.l('L1'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), 'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'tibio',    'caducidad', pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LZ'),  'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
insert into crm.lead_potencial_eventos (lead_id, nivel_anterior, nivel_nuevo, motivo, por, creado_en) values
  (pg_temp.l('L1'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-02 09:00')),
  (pg_temp.l('L1'),  'tibio',    'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L1n'), null,       'tibio',    'manual',    pg_temp.a('S1n'), pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('L2'),  null,       'estrella', 'manual',    pg_temp.a('V2'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LP'),  null,       'frio',     'manual',    pg_temp.a('S1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LC'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LD'),  null,       'tibio',    'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LI'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-05 10:00')),
  (pg_temp.l('LK'),  'estrella', 'tibio',    'caducidad', null,             pg_temp.lima('2026-10-11 05:10')),
  (pg_temp.l('LZ'),  null,       'estrella', 'manual',    pg_temp.a('V1'),  pg_temp.lima('2026-10-09 21:00'));
-- L2: un CONTACTO el jueves 10-08 15:00 reinicia su reloj.
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en) values
  (pg_temp.l('L2'), 'llamada_no_contestada', 'prueba de lectura', pg_temp.a('V2'), pg_temp.lima('2026-10-08 15:00'));
set local session_replication_role = origin;

-- Identidad de la sesión, en las DOS formas (producción lee request.jwt.claims; la imagen del banco
-- solo request.jwt.claim.sub).
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- El núcleo con calendario simulado. Por defecto, justo antes de la corrida de las 05:10 Lima de
-- p_hoy (la próxima corrida es hoy); p_proxima permite ensayar «ya pasó la corrida de hoy».
create function pg_temp.leer(p_actor uuid, p_ids uuid[], p_hoy date, p_corte timestamptz default null, p_proxima date default null) returns jsonb language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  return private.potencial_lectura(p_actor, p_ids, p_hoy, coalesce(p_corte, (p_hoy::timestamp + time '05:10') at time zone 'America/Lima'), coalesce(p_proxima, p_hoy));
end $f$;

-- Un ítem resumido: nivel/origen/nivel_marcado · días · baja_a@baja_el · puede.
create function pg_temp.item(p_items jsonb, p_k text) returns text language sql as $$
  select coalesce((
    select coalesce(i ->> 'nivel', '-') || '/' || coalesce(i ->> 'origen', '-') || '/' || coalesce(i ->> 'nivel_marcado', '-')
           || ' d=' || coalesce(i ->> 'dias_sin_gestion', '-')
           || ' baja=' || coalesce(i ->> 'baja_a', '-') || '@' || coalesce(i ->> 'baja_el', '-')
           || ' puede=' || (i ->> 'puede_marcar')
    from jsonb_array_elements(p_items) i where (i ->> 'lead_id')::uuid = pg_temp.l(p_k)), '(no viaja)')
$$;
-- Las claves de los leads que trae una lista de ítems.
create function pg_temp.claves(p_items jsonb) returns text language sql as $$
  select coalesce(string_agg(d.k, ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(p_items) i join lds d on d.id = (i ->> 'lead_id')::uuid
$$;

-- La puerta, como la llama la pantalla: authenticated. Devuelve el sobre o {"error": SQLSTATE}.
create function pg_temp.puerta(p_actor uuid, p_ids uuid[]) returns jsonb language plpgsql as $f$
declare v jsonb;
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    v := crm.potencial_leads_fn(p_ids);
    reset role;
    return v;
  exception when others then
    reset role;
    return jsonb_build_object('error', sqlstate);
  end;
end $f$;

-- Lo que la RLS REAL de crm.leads deja ver a un actor (la vara con la que se mide el espejo).
create function pg_temp.ve_rls(p_actor uuid) returns text language plpgsql as $f$
declare v_ids uuid[] := pg_temp.todos(); v_vistos uuid[];
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    select array_agg(l.id) into v_vistos from crm.leads l where l.id = any (v_ids);
  exception when others then
    reset role;
    return 'error ' || sqlstate;
  end;
  reset role;
  return coalesce((select string_agg(d.k, ',' order by d.k) from lds d where d.id = any (v_vistos)), '(ninguno)');
end $f$;

-- ¿Puede marcar DE VERDAD? Se intenta por la puerta de la fase 1 y se deshace (subtransacción).
create function pg_temp.puede_real(p_actor uuid, p_lead uuid) returns boolean language plpgsql as $f$
begin
  perform pg_temp.sesion(p_actor);
  set local role authenticated;
  begin
    perform crm.marcar_potencial_lead_fn(p_lead, 'tibio'::crm.nivel_potencial);
    raise exception 'deshacer' using errcode = 'P9999';
  exception
    when sqlstate 'P9999' then reset role; return true;
    when others then reset role; return false;
  end;
end $f$;
-- «clave:t/f» de lo que la puerta dice que el actor puede marcar, y de lo que puede de verdad.
create function pg_temp.puede_puerta(p_actor uuid) returns text language sql as $$
  select coalesce(string_agg(d.k || ':' || left(i ->> 'puede_marcar', 1), ',' order by d.k), '(ninguno)')
  from jsonb_array_elements(pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items') i
  join lds d on d.id = (i ->> 'lead_id')::uuid
$$;
create function pg_temp.puede_verdad(p_actor uuid) returns text language plpgsql as $f$
declare v text; v_items jsonb := pg_temp.puerta(p_actor, pg_temp.todos()) -> 'items';
begin
  select coalesce(string_agg(d.k || ':' || left(pg_temp.puede_real(p_actor, d.id)::text, 1), ',' order by d.k), '(ninguno)') into v
  from jsonb_array_elements(v_items) i join lds d on d.id = (i ->> 'lead_id')::uuid;
  return v;
end $f$;

do $prueba$
declare
  v jsonb;
  v_n integer;
  r record;
  v_muchos uuid[];
begin
  -- ── Permisos (del catálogo: nunca se llama sin EXECUTE bajo set role) ──
  perform pg_temp.esperar('EXECUTE de la puerta: authenticated sí; anon y service_role no', 'true/false/false',
    has_function_privilege('authenticated', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE del núcleo: nadie de la API', 'false/false/false',
    has_function_privilege('authenticated', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text || '/' ||
    has_function_privilege('anon', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text || '/' ||
    has_function_privilege('service_role', 'private.potencial_lectura(uuid,uuid[],date,timestamptz,date)', 'EXECUTE')::text);
  perform pg_temp.esperar('EXECUTE de los dos ayudantes de fechas: nadie de la API', '0',
    (select count(*)::text from unnest(array['anon', 'authenticated', 'service_role']) rr(rol),
            unnest(array['private.potencial_proxima_baja(crm.nivel_potencial,date,date)', 'private.potencial_proxima_corrida(timestamptz)']) f(fn)
      where has_function_privilege(rr.rol, f.fn, 'EXECUTE')));

  perform pg_temp.esperar('los roles de puente (métricas y gestión diaria) no ejecutan ninguno de los 3 ayudantes privados', '0',
    (select count(*)::text from unnest(array['crm_metricas_bridge', 'crm_gestion_diaria_lector']) rr(rol),
            unnest(array['private.potencial_lectura(uuid,uuid[],date,timestamptz,date)',
                         'private.potencial_proxima_baja(crm.nivel_potencial,date,date)', 'private.potencial_proxima_corrida(timestamptz)']) f(fn)
      where has_function_privilege(rr.rol, f.fn, 'EXECUTE')));
  -- crm_gestion_diaria_lector es miembro de authenticated a propósito (20260922184459): hereda el
  -- EXECUTE de toda puerta. No inicia sesión ni lleva JWT: sin sesión, la puerta lo rechaza.
  perform pg_temp.esperar('EXECUTE de la puerta en los roles de puente: solo el lector, heredado de authenticated', 'false/true',
    has_function_privilege('crm_metricas_bridge', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text || '/' ||
    has_function_privilege('crm_gestion_diaria_lector', 'crm.potencial_leads_fn(uuid[])', 'EXECUTE')::text);
  begin
    perform pg_temp.sesion(null);
    set local role crm_gestion_diaria_lector;
    perform crm.potencial_leads_fn(pg_temp.todos());
    reset role;
    perform pg_temp.esperar('el rol lector de gestión diaria, sin sesión → 42501', '42501', 'sin error');
  exception when others then
    reset role;
    perform pg_temp.esperar('el rol lector de gestión diaria, sin sesión → 42501', '42501', sqlstate);
  end;

  -- ── Bandera APAGADA: la puerta admite, pero no entrega nada ──
  perform pg_temp.esperar('bandera apagada al empezar', 'false', (select activo::text from crm.multiempresa_flags where nombre = 'potencial_lead'));
  perform pg_temp.esperar('apagada: V1 recibe habilitada=false y sin ítems', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: gerencia igual', '{"items": [], "version": 1, "habilitada": false}',
    pg_temp.puerta(pg_temp.a('G'), pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: sin sesión sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('apagada: X (equipo inactivo) sigue siendo 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);

  -- ── Bandera ENCENDIDA ──
  update crm.multiempresa_flags set activo = true where nombre = 'potencial_lead';

  -- Admisión y validación de la puerta.
  perform pg_temp.esperar('sin sesión → 42501', '{"error": "42501"}', pg_temp.puerta(null, pg_temp.todos())::text);
  perform pg_temp.esperar('X (equipo inactivo) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('X'), pg_temp.todos())::text);
  perform pg_temp.esperar('XP (perfil inactivo con equipo activo) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('XP'), pg_temp.todos())::text);
  perform pg_temp.esperar('P (usuario del portal sin membresía en el CRM) → 42501', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('P'), pg_temp.todos())::text);
  perform pg_temp.esperar('sin ids (null) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), null)::text);
  perform pg_temp.esperar('sin ids (vacío) → encendida y vacía', '{"items": [], "version": 1, "habilitada": true}', pg_temp.puerta(pg_temp.a('V1'), array[]::uuid[])::text);
  select array_agg(gen_random_uuid()) into v_muchos from generate_series(1, 200);
  perform pg_temp.esperar('200 ids → pasa', 'true', (pg_temp.puerta(pg_temp.a('V1'), v_muchos) ->> 'habilitada'));
  perform pg_temp.esperar('201 ids → 22023', '{"error": "22023"}', pg_temp.puerta(pg_temp.a('V1'), v_muchos || gen_random_uuid())::text);
  -- El tope cuenta TODOS los elementos: una matriz de 3 × 67 = 201 no se cuela (auditor-rls f3a).
  perform pg_temp.esperar('matriz 3×67 (201 ids) → 22023', '{"error": "22023"}', pg_temp.puerta(pg_temp.a('V1'),
    (select array_agg(s.fila) from (select array_agg(gen_random_uuid()) as fila from generate_series(1, 201) g group by g % 3) s))::text);
  perform pg_temp.esperar('matriz 2×2 con leads propios: se leen igual', 'L1,L3',
    pg_temp.claves(pg_temp.puerta(pg_temp.a('V1'), array[array[pg_temp.l('L1'), pg_temp.l('L3')], array[pg_temp.l('L2'), pg_temp.l('NADA')]]) -> 'items'));

  -- Forma del sobre y del ítem.
  v := pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos());
  perform pg_temp.esperar('sobre: version, habilitada, items', 'habilitada,items,version', (select string_agg(k, ',' order by k) from jsonb_object_keys(v) k));
  perform pg_temp.esperar('ítem: las 9 claves del contrato', 'baja_a,baja_el,dias_sin_gestion,lead_id,marcado_en,nivel,nivel_marcado,origen,puede_marcar',
    (select string_agg(k, ',' order by k) from jsonb_object_keys(v -> 'items' -> 0) k));
  perform pg_temp.esperar('ítems ordenados por lead_id', 'true',
    ((select array_agg(i ->> 'lead_id') from jsonb_array_elements(v -> 'items') i)
     = (select array_agg(x order by x) from (select i ->> 'lead_id' as x from jsonb_array_elements(v -> 'items') i) s))::text);
  perform pg_temp.esperar('ningún lead repetido en los ítems', 'true',
    ((select count(*) from jsonb_array_elements(v -> 'items') i) = (select count(distinct i ->> 'lead_id') from jsonb_array_elements(v -> 'items') i))::text);
  perform pg_temp.esperar('ids repetidos: un ítem por lead', '1',
    jsonb_array_length(pg_temp.puerta(pg_temp.a('V1'), array[pg_temp.l('L1'), pg_temp.l('L1'), pg_temp.l('L1')]) -> 'items')::text);

  -- ── Visibilidad: lo que entrega la puerta por actor (LI inactivo y NADA no viajan nunca) ──
  perform pg_temp.esperar('V1 ve lo suyo (y LPV, parqueado a su nombre)', 'L1,L3,LC,LD,LK,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V1n ve solo L1n', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('V1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1n ve su subárbol', 'L1n', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1n'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 ve su subárbol y su parqueo', 'L1,L1n,L3,LC,LD,LK,LP,LPV,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('V2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S2 ve solo L2', 'L2', pg_temp.claves(pg_temp.puerta(pg_temp.a('S2'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('gerencia ve todo lo vivo, también lo sin asignar', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('G'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('directorio (lector global) ve todo lo vivo', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('D'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('directorio histórico (sin membresía) ve todo lo vivo', 'L1,L1n,L2,L3,LC,LD,LK,LP,LPV,LS,LZ', pg_temp.claves(pg_temp.puerta(pg_temp.a('DH'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('coordinación: admitida y sin leads', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('C'), pg_temp.todos()) -> 'items'));
  perform pg_temp.esperar('S1 no ve el lead sin asignar', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('S1'), array[pg_temp.l('LS')]) -> 'items'));
  perform pg_temp.esperar('V2 preguntando por un lead ajeno: no viaja', '(ninguno)', pg_temp.claves(pg_temp.puerta(pg_temp.a('V2'), array[pg_temp.l('L1')]) -> 'items'));

  -- ── EQUIVALENCIA con la RLS real de crm.leads, actor por actor ──
  for r in select k, id from act where k not in ('X', 'XP', 'P', 'DM') order by k loop
    perform pg_temp.esperar('espejo = RLS real para ' || r.k, pg_temp.ve_rls(r.id), pg_temp.claves(pg_temp.puerta(r.id, pg_temp.todos()) -> 'items'));
  end loop;
  perform pg_temp.esperar('X: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('X')));
  perform pg_temp.esperar('XP: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('XP')));
  perform pg_temp.esperar('P: la RLS real tampoco le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('P')));
  perform pg_temp.esperar('DM (perfil de directorio con equipo vendedor): la RLS real no le deja ver nada', '(ninguno)', pg_temp.ve_rls(pg_temp.a('DM')));
  perform pg_temp.esperar('DM: la puerta lo rechaza (una pareja desalineada es una revocación)', '{"error": "42501"}', pg_temp.puerta(pg_temp.a('DM'), pg_temp.todos())::text);

  -- ── puede_marcar: lo que dice la puerta = lo que la puerta de marcar permite de verdad ──
  perform pg_temp.esperar('V1 puede marcar lo abierto y suyo (no cerrados ni parqueo)', 'L1:t,L3:t,LC:f,LD:f,LK:t,LPV:f,LZ:t', pg_temp.puede_puerta(pg_temp.a('V1')));
  perform pg_temp.esperar('S1 puede marcar su subárbol abierto y su parqueo', 'L1:t,L1n:t,L3:t,LC:f,LD:f,LK:t,LP:t,LPV:t,LZ:t', pg_temp.puede_puerta(pg_temp.a('S1')));
  perform pg_temp.esperar('gerencia ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('G')));
  perform pg_temp.esperar('directorio ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('D')));
  perform pg_temp.esperar('directorio histórico ve pero no marca', 'L1:f,L1n:f,L2:f,L3:f,LC:f,LD:f,LK:f,LP:f,LPV:f,LS:f,LZ:f', pg_temp.puede_puerta(pg_temp.a('DH')));
  for r in select k, id from act where k not in ('X', 'XP', 'P', 'DM', 'C') order by k loop
    perform pg_temp.esperar('puede_marcar = marcar de verdad para ' || r.k, pg_temp.puede_verdad(r.id), pg_temp.puede_puerta(r.id));
  end loop;
  perform pg_temp.esperar('probar «puede de verdad» no dejó marcas nuevas', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── El calendario (núcleo con fecha simulada, como V1 salvo que se diga) ──
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1 estrella recién marcada: 0 días, baja a tibio el dom 10-11', 'estrella/manual/estrella d=0 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  perform pg_temp.esperar('mar 10-06 · L3 sin marca: todo null y puede marcar', '-/-/- d=- baja=-@- puede=true', pg_temp.item(v, 'L3'));
  perform pg_temp.esperar('mar 10-06 · LPV parqueado sin marca: V1 lo ve pero no lo marca', '-/-/- d=- baja=-@- puede=false', pg_temp.item(v, 'LPV'));
  perform pg_temp.esperar('mar 10-06 · LI inactivo no viaja', '(no viaja)', pg_temp.item(v, 'LI'));
  perform pg_temp.esperar('mar 10-06 · un id que no existe no viaja', '(no viaja)', pg_temp.item(v, 'NADA'));
  perform pg_temp.esperar('mar 10-06 · marcado_en viaja', '2026-10-05 10:00', (
    select to_char((i ->> 'marcado_en')::timestamptz at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from jsonb_array_elements(v) i where (i ->> 'lead_id')::uuid = pg_temp.l('L1')));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-10');
  perform pg_temp.esperar('sáb 10-10 · L1: 4 días (mar-vie), sigue bajando el dom 10-11', 'estrella/manual/estrella d=4 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-11');
  perform pg_temp.esperar('dom 10-11 · L1: 5 días, baja HOY (pendiente de la corrida)', 'estrella/manual/estrella d=5 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LC convertido: conserva la estrella, no baja ni se marca', 'estrella/manual/estrella d=5 baja=-@- puede=false', pg_temp.item(v, 'LC'));
  perform pg_temp.esperar('lun 10-12 · LD descartado: conserva el tibio, no baja ni se marca', 'tibio/manual/tibio d=5 baja=-@- puede=false', pg_temp.item(v, 'LD'));
  perform pg_temp.esperar('lun 10-12 · LK bajó sola: tibio por caducidad, la persona puso estrella, baja a frío el sáb 10-17', 'tibio/caducidad/estrella d=5 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'LK'));
  perform pg_temp.esperar('lun 10-12 · LZ marcada vie 21:00 Lima: 1 día (el sábado), no 0', 'estrella/manual/estrella d=1 baja=tibio@2026-10-16 puede=true', pg_temp.item(v, 'LZ'));

  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-19');
  perform pg_temp.esperar('lun 10-19 · L1 con 11 días sin corrida: va directo a frío, hoy', 'estrella/manual/estrella d=11 baja=frio@2026-10-19 puede=true', pg_temp.item(v, 'L1'));

  -- La próxima corrida (Codex f3a r1 y r2): horario NOMINAL con cinco minutos de margen. A las 05:40
  -- en punto la última pasada puede no haber arrancado: se sigue respondiendo hoy hasta las 05:45.
  perform pg_temp.esperar('próxima corrida: 05:09 → hoy; 05:40:00 → hoy; 05:44:59 → hoy; 05:45:00 → mañana; 23:59 → mañana; 00:00 → hoy',
    '2026-10-05/2026-10-05/2026-10-05/2026-10-06/2026-10-06/2026-10-06',
    private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:09:00'))::text || '/' || private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:40:00'))::text || '/' ||
    private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:44:59'))::text || '/' || private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 05:45:00'))::text || '/' ||
    private.potencial_proxima_corrida(pg_temp.lima('2026-10-05 23:59:59'))::text || '/' || private.potencial_proxima_corrida(pg_temp.lima('2026-10-06 00:00:00'))::text);
  -- El caso de Codex: estrella del lun 05 vista el VIERNES 16 después de la corrida (9 días). La
  -- próxima pasada es el sábado 17, que ya cuenta 10: va directo a frío, no a tibio.
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-16', pg_temp.lima('2026-10-16 09:00'), '2026-10-17');
  perform pg_temp.esperar('vie 10-16 tras la corrida · L1 con 9 días: baja a FRÍO el sáb 10-17', 'estrella/manual/estrella d=9 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-16', pg_temp.lima('2026-10-16 05:00'), '2026-10-16');
  perform pg_temp.esperar('vie 10-16 antes de la corrida · L1 con 9 días: baja a tibio HOY', 'estrella/manual/estrella d=9 baja=tibio@2026-10-16 puede=true', pg_temp.item(v, 'L1'));
  v := pg_temp.leer(pg_temp.a('V1'), pg_temp.todos(), '2026-10-11', pg_temp.lima('2026-10-11 09:00'), '2026-10-12');
  perform pg_temp.esperar('dom 10-11 tras la corrida · L1 pendiente: baja MAÑANA lun 10-12', 'estrella/manual/estrella d=5 baja=tibio@2026-10-12 puede=true', pg_temp.item(v, 'L1'));

  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-06');
  perform pg_temp.esperar('mar 10-06 · L1n tibio: baja a frío el sáb 10-17 (10 días)', 'tibio/manual/tibio d=0 baja=frio@2026-10-17 puede=true', pg_temp.item(v, 'L1n'));
  v := pg_temp.leer(pg_temp.a('S1'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · LP frío: no baja más', 'frio/manual/frio d=5 baja=-@- puede=true', pg_temp.item(v, 'LP'));

  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('lun 10-12 · L2 con contacto el jue 10-08: 2 días, baja el jue 10-15', 'estrella/manual/estrella d=2 baja=tibio@2026-10-15 puede=true', pg_temp.item(v, 'L2'));
  v := pg_temp.leer(pg_temp.a('V2'), pg_temp.todos(), '2026-10-07');
  perform pg_temp.esperar('mié 10-07 · L2 antes de su contacto: el contacto futuro aún no cuenta', 'estrella/manual/estrella d=1 baja=tibio@2026-10-11 puede=true', pg_temp.item(v, 'L2'));

  v := pg_temp.leer(pg_temp.a('G'), pg_temp.todos(), '2026-10-12');
  perform pg_temp.esperar('gerencia · L1: ve la marca y cuándo baja, no marca', 'estrella/manual/estrella d=5 baja=tibio@2026-10-12 puede=false', pg_temp.item(v, 'L1'));

  -- Núcleo: argumentos.
  perform pg_temp.esperar('núcleo sin ids → []', '[]', pg_temp.leer(pg_temp.a('V1'), null, '2026-10-06')::text);
  begin
    perform private.potencial_lectura(null, pg_temp.todos(), '2026-10-06', now(), '2026-10-06');
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', 'sin error');
  exception when others then
    perform pg_temp.esperar('núcleo sin actor → 22023', '22023', sqlstate);
  end;
  -- El núcleo con un actor que NO es el de la sesión (Codex f3a r1): sesión de V2, actor gerencia.
  begin
    perform pg_temp.sesion(pg_temp.a('V2'));
    perform private.potencial_lectura(pg_temp.a('G'), pg_temp.todos(), '2026-10-06', now(), '2026-10-06');
    perform pg_temp.esperar('núcleo con actor ajeno a la sesión → 42501', '42501', 'sin error');
  exception when others then
    perform pg_temp.esperar('núcleo con actor ajeno a la sesión → 42501', '42501', sqlstate);
  end;

  -- ── Solo lectura: nada cambió en las tablas de la marca ──
  perform pg_temp.esperar('la lectura no escribió marcas ni eventos', '9/11',
    (select count(*)::text from crm.lead_potencial where lead_id in (select id from lds)) || '/' ||
    (select count(*)::text from crm.lead_potencial_eventos where lead_id in (select id from lds)));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'LECTURA potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'LECTURA potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
