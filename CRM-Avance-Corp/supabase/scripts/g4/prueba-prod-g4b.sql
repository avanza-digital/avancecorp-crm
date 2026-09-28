-- G4b · prueba SIN ESCRIBIR contra producción con cuentas reales (28/09/2026).
--
-- Qué prueba, con los datos reales y como cada rol real:
--   · la lista nueva (crm.gestion_diaria_citas_fn) ES la cifra que la pantalla ya muestra:
--     por analista (detalle del equipo, Gerencia y cada Supervisión), por equipo y «fuera»
--     (pulso) y la operación (pulso y private.gestion_diaria_llamadas);
--   · equipos + «fuera» parten la operación sin solaparse y cada analista cabe en ella;
--   · paginación con cursor (límite 5), orden (creado_en, id) estricto y forma de cada fila;
--   · denegaciones por rol (Supervisión fuera de su árbol, coordinación, analista, sin sesión,
--     lector global si existe) y por parámetros (rol ANTES que parámetros).
--
-- Por qué no escribe: es UN solo DO (una sentencia, atómica) que se pone en solo lectura
-- (transaction_read_only) y termina SIEMPRE en raise; además solo llama lecturas. El
-- resultado se lee en el mensaje del error: G4B_PROD_OK o G4B_PROD_FALLA.
--
-- 🔴 No llama NADA como anon ni ninguna función sin EXECUTE: en esta versión de Postgres eso
-- puede tumbar el servidor. El candado 0 aborta ANTES de cambiar de rol si la cadena de
-- funciones que se alcanza como authenticated tiene alguna sin permiso.
--
-- Si una diferencia lista ≠ cifra sale SOLO en el día de hoy, repetir: puede ser una cita
-- creada durante la corrida (cada consulta toma su propia foto en READ COMMITTED).
--
-- Uso (Miguel, con `!`, desde CRM-Avance-Corp):
--   npx supabase db query --linked --file supabase/scripts/g4/prueba-prod-g4b.sql
do $prueba$
declare
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_limite constant integer := 5;
  v_dias date[];
  v_gerentes uuid[];
  v_sups uuid[];
  v_coord uuid;
  v_vend uuid;
  v_lector uuid;
  v_sin_permiso text;
  v_bruto jsonb := '{}';
  v_casos jsonb := '[]';
  v_denegar jsonb := '[]';
  v_ids jsonb := '{}';
  v_fallos text[] := '{}';
  v_info text[] := '{}';
  v_n_casos integer := 0;
  v_n_paginas integer := 0;
  v_n_filas integer := 0;
  v_n_deneg integer := 0;
  v_n_parte integer := 0;
  v_max_paginas integer := 0;
  v_actor uuid;
  v_dia date;
  v_x jsonb;
  c record;
  v_pag jsonb;
  v_items jsonb;
  v_de timestamptz;
  v_id uuid;
  v_total integer;
  v_paginas integer;
  v_recibido text;
  v_ini timestamptz;
  v_fin timestamptz;
  v_a uuid[];
  v_b uuid[];
  v_texto text;
begin
  set local transaction_read_only = on;

  -- 0. Candado: toda función que la prueba alcanza como authenticated tiene EXECUTE (se sigue
  --    la cadena por las llamadas de cada cuerpo mientras la función corra como invoker).
  with recursive cadena(oid) as (
    select unnest(array[
      'crm.gestion_diaria_citas_fn(date,text,uuid,integer,timestamptz,uuid)'::regprocedure,
      'crm.gestion_diaria_equipo_fn(date,uuid)'::regprocedure,
      'crm.gestion_diaria_pulso_fn(date)'::regprocedure,
      'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])'::regprocedure,
      'private.gestion_diaria_pulso_autores(timestamptz,timestamptz)'::regprocedure,
      'auth.uid()'::regprocedure]::oid[])
    union
    select q.oid from cadena k join pg_proc p on p.oid = k.oid
    cross join lateral regexp_matches(p.prosrc, '((?:private|crm|auth|public)\.[a-z_0-9]+)\s*\(', 'g') m
    join pg_proc q on q.pronamespace = split_part(m[1], '.', 1)::regnamespace
      and q.proname = split_part(m[1], '.', 2)
    where not p.prosecdef
  )
  select string_agg(k.oid::regprocedure::text, ' · ') into v_sin_permiso
  from cadena k where not has_function_privilege('authenticated', k.oid, 'EXECUTE');
  if v_sin_permiso is not null then
    raise exception 'G4B_PROD_ABORTADA (no se llamó a nada): authenticated sin EXECUTE en %', v_sin_permiso;
  end if;

  -- Actores reales (leídos como postgres, antes de cambiar de rol).
  select array_agg(e.perfil_id order by e.perfil_id) into v_gerentes
  from crm.equipo e where e.activo and private.rol_crm(e.perfil_id) = 'gerencia';
  select array_agg(e.perfil_id order by e.perfil_id) into v_sups
  from crm.equipo e where e.activo and private.rol_crm(e.perfil_id) = 'supervisor';
  select e.perfil_id into v_coord from crm.equipo e
  where e.activo and private.rol_crm(e.perfil_id) = 'coordinador' order by e.perfil_id limit 1;
  select e.perfil_id into v_vend from crm.equipo e
  where e.activo and private.rol_crm(e.perfil_id) = 'vendedor' order by e.perfil_id limit 1;
  select p.id into v_lector from public.perfiles p
  where p.activo and (private.rol_crm(p.id) = 'directorio'
    or (p.rol = 'directorio' and not exists (select 1 from crm.equipo e where e.perfil_id = p.id)))
  order by p.id limit 1;
  if v_gerentes is null or v_sups is null or v_vend is null then
    raise exception 'G4B_PROD_ABORTADA: faltan actores reales (gerencia %, supervisión %, analista %)',
      coalesce(cardinality(v_gerentes), 0), coalesce(cardinality(v_sups), 0), v_vend is not null;
  end if;

  -- Días: hoy, ayer, anteayer y el de más citas de la última semana.
  select array_agg(distinct s.d order by s.d) into v_dias from (
    select v_hoy - g as d from generate_series(0, 2) g
    union all
    (select (t.creado_en at time zone 'America/Lima')::date from crm.tareas t
     where t.tipo = 'reunion' and t.creado_en >= (v_hoy - 7)::timestamp at time zone 'America/Lima'
     group by 1 order by count(*) desc, 1 desc limit 1)
  ) s;
  -- Oráculo bruto (tabla leída como postgres): solo informativo.
  select coalesce(jsonb_object_agg(d::text, (select count(*) from crm.tareas t
      where t.tipo = 'reunion' and t.creado_en >= d::timestamp at time zone 'America/Lima'
        and t.creado_en < (d + 1)::timestamp at time zone 'America/Lima')), '{}'::jsonb)
  into v_bruto from unnest(v_dias) d;

  begin
    perform set_config('request.jwt.claims', '', true);
    execute 'set local role authenticated';

    -- 1. Casos: cada ámbito con la cifra que la pantalla ya muestra.
    --    G1: detalle por analista, equipos, «fuera» y operación. G2: solo la operación.
    foreach v_actor in array v_gerentes loop
      perform set_config('request.jwt.claim.sub', v_actor::text, true);
      foreach v_dia in array v_dias loop
        v_ini := v_dia::timestamp at time zone 'America/Lima';
        v_fin := (v_dia + 1)::timestamp at time zone 'America/Lima';
        v_x := crm.gestion_diaria_pulso_fn(v_dia);
        if v_actor = v_gerentes[1] then
          select v_casos || coalesce(jsonb_agg(jsonb_build_object(
              'actor', v_actor, 'dia', v_dia, 'ambito', 'analista', 'id', f->>'analista_id',
              'cifra', (f#>>'{marcador,citas_agendadas}')::integer,
              'etiqueta', format('G1|%s|analista|%s', v_dia, f->>'analista_id'))), '[]'::jsonb)
            into v_casos
          from jsonb_array_elements(crm.gestion_diaria_equipo_fn(v_dia, null)->'equipo') f;
          select v_casos || coalesce(jsonb_agg(jsonb_build_object(
              'actor', v_actor, 'dia', v_dia,
              'ambito', case when e->>'clave' = 'fuera' then 'fuera' else 'equipo' end,
              'id', case when e->>'clave' = 'fuera' then null else e->>'clave' end,
              'cifra', (e#>>'{metricas,citas_agendadas}')::integer,
              'etiqueta', format('G1|%s|%s|%s', v_dia,
                case when e->>'clave' = 'fuera' then 'fuera' else 'equipo' end, e->>'clave'))), '[]'::jsonb)
            into v_casos
          from jsonb_array_elements(v_x->'equipos') e;
        end if;
        v_casos := v_casos || jsonb_build_array(jsonb_build_object(
          'actor', v_actor, 'dia', v_dia, 'ambito', 'operacion', 'id', null,
          'cifra', (v_x#>>'{actual,citas_agendadas}')::integer,
          'cifra_llamadas', (select coalesce(sum(l.citas_agendadas), 0)::integer
            from private.gestion_diaria_llamadas(v_ini, v_fin,
              (select array_agg(a.id) from private.gestion_diaria_pulso_autores(v_ini, v_fin) a)) l),
          'etiqueta', format('G%s|%s|operacion|-', array_position(v_gerentes, v_actor), v_dia)));
      end loop;
    end loop;
    -- Cada Supervisión real: el detalle de SU árbol.
    foreach v_actor in array v_sups loop
      perform set_config('request.jwt.claim.sub', v_actor::text, true);
      foreach v_dia in array v_dias loop
        select v_casos || coalesce(jsonb_agg(jsonb_build_object(
            'actor', v_actor, 'dia', v_dia, 'ambito', 'analista', 'id', f->>'analista_id',
            'cifra', (f#>>'{marcador,citas_agendadas}')::integer,
            'etiqueta', format('S%s|%s|analista|%s', array_position(v_sups, v_actor), v_dia, f->>'analista_id'))), '[]'::jsonb)
          into v_casos
        from jsonb_array_elements(crm.gestion_diaria_equipo_fn(v_dia, null)->'equipo') f;
      end loop;
    end loop;

    -- 2. Cada caso: todas las páginas, lista = cifra, orden y forma.
    for c in select x.* from jsonb_to_recordset(v_casos) as x(actor uuid, dia date, ambito text,
        id uuid, cifra integer, cifra_llamadas integer, etiqueta text) loop
      perform set_config('request.jwt.claim.sub', c.actor::text, true);
      v_ini := c.dia::timestamp at time zone 'America/Lima';
      v_fin := (c.dia + 1)::timestamp at time zone 'America/Lima';
      v_items := '[]'; v_de := null; v_id := null; v_total := null; v_paginas := 0;
      begin
        loop
          v_pag := crm.gestion_diaria_citas_fn(c.dia, c.ambito, c.id, v_limite, v_de, v_id);
          v_paginas := v_paginas + 1;
          if jsonb_array_length(v_pag->'items') > v_limite
            or (v_pag->>'hay_mas')::boolean is distinct from (v_pag->'siguiente_cursor' <> 'null'::jsonb) then
            v_fallos := v_fallos || format('%s: página %s mal formada', c.etiqueta, v_paginas);
          end if;
          if v_total is null then
            v_total := (v_pag#>>'{resumen,total}')::integer;
          elsif v_total is distinct from (v_pag#>>'{resumen,total}')::integer then
            v_fallos := v_fallos || format('%s: el total cambia entre páginas', c.etiqueta);
          end if;
          v_items := v_items || (v_pag->'items');
          exit when not (v_pag->>'hay_mas')::boolean or v_paginas >= 200;
          v_de := (v_pag#>>'{siguiente_cursor,despues_de}')::timestamptz;
          v_id := (v_pag#>>'{siguiente_cursor,despues_id}')::uuid;
        end loop;
      exception when others then
        -- Un caso que revienta no apaga los demás: se anota y se sigue.
        v_fallos := v_fallos || format('%s: ERROR %s: %s', c.etiqueta, sqlstate, sqlerrm);
        continue;
      end;
      v_n_casos := v_n_casos + 1;
      v_n_paginas := v_n_paginas + v_paginas;
      v_n_filas := v_n_filas + jsonb_array_length(v_items);
      v_max_paginas := greatest(v_max_paginas, v_paginas);
      if jsonb_array_length(v_items) is distinct from v_total then
        v_fallos := v_fallos || format('%s: total %s y %s filas', c.etiqueta, v_total, jsonb_array_length(v_items));
      end if;
      if v_total is distinct from c.cifra then
        v_fallos := v_fallos || format('%s: lista %s ≠ cifra %s%s', c.etiqueta, v_total, c.cifra,
          case when c.dia = v_hoy then ' (hoy: repetir)' else '' end);
      end if;
      if c.cifra_llamadas is not null and c.cifra_llamadas is distinct from v_total then
        v_fallos := v_fallos || format('%s: lista %s ≠ gestion_diaria_llamadas %s', c.etiqueta, v_total, c.cifra_llamadas);
      end if;
      if exists (select 1 from jsonb_array_elements(v_items) with ordinality a(x, n)
          join jsonb_array_elements(v_items) with ordinality b(y, m) on b.m = a.n + 1
          where ((a.x->>'creado_en')::timestamptz, (a.x->>'id')::uuid)
             >= ((b.y->>'creado_en')::timestamptz, (b.y->>'id')::uuid)) then
        v_fallos := v_fallos || format('%s: orden (creado_en, id) no estricto', c.etiqueta);
      end if;
      if exists (select 1 from jsonb_array_elements(v_items) x
          where (x->>'creado_en')::timestamptz < v_ini or (x->>'creado_en')::timestamptz >= v_fin
            or x->>'id' is null or x->>'estado' is null or x->>'vence_en' is null
            or (x->'lead_id' = 'null'::jsonb) <> (x->'lead_nombre' = 'null'::jsonb)
            or (c.ambito = 'analista' and x->>'vendedor_id' is distinct from c.id::text)) then
        v_fallos := v_fallos || format('%s: fila fuera del día, del ámbito o mal formada', c.etiqueta);
      end if;
      v_ids := v_ids || jsonb_build_object(c.etiqueta,
        coalesce((select jsonb_agg(x->>'id') from jsonb_array_elements(v_items) x), '[]'::jsonb));
    end loop;

    -- No pasa en vacío: cada ámbito se ejercitó y hubo filas y paginación.
    select string_agg(format('%s=%s', s.k, s.n), ' ' order by s.k) into v_texto from (
      select split_part(x->>'etiqueta', '|', 1) || ':' || split_part(x->>'etiqueta', '|', 3) k, count(*) n
      from jsonb_array_elements(v_casos) x group by 1) s;
    v_info := v_info || format('casos por actor:ámbito %s', v_texto);
    if v_texto not like '%G1:analista=%' or v_texto not like '%G1:equipo=%' or v_texto not like '%G1:fuera=%'
      or v_texto not like '%G1:operacion=%' or v_texto not like '%S%:analista=%' then
      v_fallos := v_fallos || 'algún ámbito quedó sin casos (G1 analista/equipo/fuera/operación o Supervisión)';
    end if;
    if v_n_filas = 0 or v_max_paginas < 2 then
      v_fallos := v_fallos || format('prueba vacía: %s filas, máximo %s páginas', v_n_filas, v_max_paginas);
    end if;

    -- 3. G1: equipos + «fuera» = operación, sin repetidos; los analistas caben en la operación.
    foreach v_dia in array v_dias loop
      select coalesce(array_agg(i::uuid order by i::uuid), '{}') into v_a
      from jsonb_each(v_ids) k, jsonb_array_elements_text(k.value) i
      where k.key like format('G1|%s|equipo|%%', v_dia) or k.key = format('G1|%s|fuera|fuera', v_dia);
      select coalesce(array_agg(i::uuid order by i::uuid), '{}') into v_b
      from jsonb_array_elements_text(v_ids->format('G1|%s|operacion|-', v_dia)) i;
      v_n_parte := v_n_parte + 1;
      if v_a is distinct from v_b then
        v_fallos := v_fallos || format('%s: equipos + «fuera» (%s) no parten la operación (%s)',
          v_dia, cardinality(v_a), cardinality(v_b));
      end if;
      select coalesce(array_agg(i::uuid), '{}') into v_a
      from jsonb_each(v_ids) k, jsonb_array_elements_text(k.value) i
      where k.key like format('G1|%s|analista|%%', v_dia);
      if not (v_a <@ v_b) or cardinality(v_a) <> (select count(distinct u) from unnest(v_a) u) then
        v_fallos := v_fallos || format('%s: las listas por analista no caben en la operación o se repiten', v_dia);
      end if;
    end loop;

    -- 4. Denegaciones y parámetros: error esperado, nunca filas.
    v_denegar := jsonb_build_array(
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'analista', 'id', gen_random_uuid(), 'limite', 5, 'esperado', '42501', 'etiqueta', 'G1 analista inexistente'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'equipo', 'id', v_vend, 'limite', 5, 'esperado', '42501', 'etiqueta', 'G1 equipo de quien no es supervisor'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy + 1, 'ambito', 'operacion', 'limite', 5, 'esperado', '22023', 'etiqueta', 'G1 día futuro'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy - 366, 'ambito', 'operacion', 'limite', 5, 'esperado', '22023', 'etiqueta', 'G1 más de 365 días'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy - 365, 'ambito', 'operacion', 'limite', 5, 'esperado', 'ok', 'etiqueta', 'G1 borde de 365 días'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'operacion', 'limite', 0, 'esperado', '22023', 'etiqueta', 'G1 límite 0'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'operacion', 'limite', 101, 'esperado', '22023', 'etiqueta', 'G1 límite 101'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'analista', 'limite', 5, 'esperado', '22023', 'etiqueta', 'G1 analista sin id'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'operacion', 'id', v_vend, 'limite', 5, 'esperado', '22023', 'etiqueta', 'G1 operación con id'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'de', statement_timestamp(), 'esperado', '22023', 'etiqueta', 'G1 cursor a medias'),
      jsonb_build_object('actor', v_gerentes[1], 'dia', v_hoy, 'ambito', 'todo', 'limite', 5, 'esperado', '22023', 'etiqueta', 'G1 ámbito desconocido'),
      jsonb_build_object('actor', v_vend, 'dia', v_hoy, 'ambito', 'analista', 'id', v_vend, 'limite', 5, 'esperado', '42501', 'etiqueta', 'analista: su propia lista'),
      jsonb_build_object('actor', v_vend, 'dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'esperado', '42501', 'etiqueta', 'analista: la operación'),
      jsonb_build_object('dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'esperado', '42501', 'etiqueta', 'sin sesión'));
    if v_coord is not null then
      v_denegar := v_denegar || jsonb_build_array(
        jsonb_build_object('actor', v_coord, 'dia', v_hoy, 'ambito', 'analista', 'id', v_vend, 'limite', 5, 'esperado', '42501', 'etiqueta', 'coordinación: un analista'),
        jsonb_build_object('actor', v_coord, 'dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'esperado', '42501', 'etiqueta', 'coordinación: la operación'),
        jsonb_build_object('actor', v_coord, 'dia', v_hoy + 1, 'ambito', 'operacion', 'limite', 0, 'esperado', '42501', 'etiqueta', 'coordinación: rol antes que parámetros'));
    end if;
    if v_lector is not null then
      v_denegar := v_denegar || jsonb_build_array(
        jsonb_build_object('actor', v_lector, 'dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'esperado', '42501', 'etiqueta', 'lector global: la operación'));
    end if;
    foreach v_actor in array v_sups loop
      v_texto := format('S%s', array_position(v_sups, v_actor));
      v_denegar := v_denegar || jsonb_build_array(
        jsonb_build_object('actor', v_actor, 'dia', v_hoy, 'ambito', 'equipo', 'id', v_actor, 'limite', 5, 'esperado', '42501', 'etiqueta', v_texto || ' equipo propio'),
        jsonb_build_object('actor', v_actor, 'dia', v_hoy, 'ambito', 'fuera', 'limite', 5, 'esperado', '42501', 'etiqueta', v_texto || ' «fuera»'),
        jsonb_build_object('actor', v_actor, 'dia', v_hoy, 'ambito', 'operacion', 'limite', 5, 'esperado', '42501', 'etiqueta', v_texto || ' operación'),
        jsonb_build_object('actor', v_actor, 'dia', v_hoy, 'ambito', 'analista', 'id', gen_random_uuid(), 'limite', 5, 'esperado', '42501', 'etiqueta', v_texto || ' analista inexistente'));
      -- Un analista real de la operación que NO está en su árbol (si existe).
      select (x->>'id')::uuid into v_id from jsonb_array_elements(v_casos) x
      where x->>'etiqueta' like format('G1|%s|analista|%%', v_hoy)
        and not exists (select 1 from jsonb_array_elements(v_casos) y
          where y->>'etiqueta' = format('%s|%s|analista|%s', v_texto, v_hoy, x->>'id'))
      order by x->>'id' limit 1;
      if v_id is not null then
        v_denegar := v_denegar || jsonb_build_array(jsonb_build_object('actor', v_actor, 'dia', v_hoy,
          'ambito', 'analista', 'id', v_id, 'limite', 5, 'esperado', '42501', 'etiqueta', v_texto || ' analista fuera de su árbol'));
      end if;
      v_id := null;
    end loop;
    for c in select x.* from jsonb_to_recordset(v_denegar) as x(actor uuid, dia date, ambito text,
        id uuid, limite integer, de timestamptz, did uuid, esperado text, etiqueta text) loop
      perform set_config('request.jwt.claim.sub', coalesce(c.actor::text, ''), true);
      begin
        v_pag := crm.gestion_diaria_citas_fn(c.dia, c.ambito, c.id, c.limite, c.de, c.did);
        v_recibido := 'ok';
      exception when others then
        v_recibido := sqlstate;
      end;
      v_n_deneg := v_n_deneg + 1;
      if v_recibido is distinct from c.esperado then
        v_fallos := v_fallos || format('%s: esperado %s, recibido %s', c.etiqueta, c.esperado, v_recibido);
      end if;
    end loop;

    -- 5. Informativo (no falla): tabla sin RLS vs lista de G1, G1 vs G2, Supervisión vs Gerencia.
    select string_agg(format('%s tabla %s / G1 %s', d, v_bruto->>(d::text),
        jsonb_array_length(v_ids->format('G1|%s|operacion|-', d))), '; ' order by d)
      into v_texto from unnest(v_dias) d;
    v_info := v_info || format('citas por día: %s', v_texto);
    if cardinality(v_gerentes) > 1 then
      select count(*) into v_total from unnest(v_dias) d
      where v_ids->format('G1|%s|operacion|-', d) is distinct from v_ids->format('G2|%s|operacion|-', d);
      v_info := v_info || format('G1 y G2 ven distinta operación en %s de %s días', v_total, cardinality(v_dias));
    end if;
    select count(*) into v_total from jsonb_each(v_ids) k
    where k.key like 'S%|analista|%'
      and v_ids->('G1|' || split_part(k.key, '|', 2) || '|analista|' || split_part(k.key, '|', 4)) is distinct from k.value;
    v_info := v_info || format('listas de Supervisión distintas de las de Gerencia para el mismo analista y día: %s', v_total);
    v_info := v_info || format('actores: %s gerencia, %s supervisión, coordinación %s, lector global %s',
      cardinality(v_gerentes), cardinality(v_sups),
      case when v_coord is null then 'no hay' else 'sí' end, case when v_lector is null then 'no hay' else 'sí' end);

    execute 'reset role';
  exception when others then
    v_fallos := v_fallos || format('ERROR %s: %s', sqlstate, sqlerrm);
  end;

  raise exception 'ROLLBACK_A_PROPOSITO >> % · días % · casos lista=cifra %, páginas % (máx. % en un caso), filas %, particiones %, denegaciones % · INFO: % · FALLOS (%): %',
    case when cardinality(v_fallos) = 0 then 'G4B_PROD_OK' else 'G4B_PROD_FALLA' end,
    array_to_string(v_dias, ', '), v_n_casos, v_n_paginas, v_max_paginas, v_n_filas, v_n_parte, v_n_deneg,
    array_to_string(v_info, ' | '), cardinality(v_fallos),
    case when cardinality(v_fallos) = 0 then 'ninguno' else array_to_string(v_fallos[1:15], ' | ') end;
end $prueba$;
