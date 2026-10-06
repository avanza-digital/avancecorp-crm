-- Oráculo de la novena (20261005224330, «Qué pasó hoy» paginada y por la hora de resolución) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql (v4 como DOBLE declarado). Se corre como dueño después de las siete, la
-- octava y la novena; todo en una transacción que termina en ROLLBACK. Cubre «Qué pasó hoy» (resuelta hoy aunque se
-- recibiera ayer, registrada ayer y corregida hoy, lo resuelto ayer fuera, orden por la hora de resolución, páginas
-- con cursor entre las dos ramas y con empate, cursor y límite validados, resultado, deshecho, vía, motivo, ámbito por
-- rol y equipo, lead dado de baja, borde del día de Lima) y la marca «Celular» de la octava, que no cambia.
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia; a9 está de baja.
-- Toda la transacción ve el mismo now(): las horas de resolución se fijan a mano (triggers de usuario apagados un
-- momento, como en el oráculo de la octava) para probar el orden y el cursor.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create function pg_temp.ev(p_id text, p_numero text)
returns jsonb language sql immutable as $$
  select jsonb_build_object('v', 1, 'evento_origen_id', p_id, 'numero', p_numero, 'direccion', 'saliente')
$$;
create function pg_temp.enviar(p_clave text, p_evento jsonb)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role service_role';
  v := crm.ingerir_llamada_celular_servicio(p_clave, p_evento);
  execute 'set local role none';
  return v;
end $$;
create function pg_temp.v5(p_actor uuid, p_op uuid, p_lead uuid, p_origen text)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.registrar_llamada_v5(p_op, p_lead, 'volver_a_llamar', null, null, null, null, false, false, p_origen, 'al_colgar');
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.descartar(p_actor uuid, p_evento uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  perform crm.descartar_llamada_celular(p_evento, 'personal');
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
create function pg_temp.resueltas(p_actor uuid, p_limite integer default 50, p_antes timestamptz default null, p_antes_id uuid default null)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.llamadas_celular_resueltas_hoy_fn(p_limite, p_antes, p_antes_id);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
-- Recorre todas las páginas con el cursor que devuelve cada una (tal cual, como texto) y junta los ids en orden.
create function pg_temp.todas(p_actor uuid, p_limite integer)
returns uuid[] language plpgsql as $$
declare
  v jsonb;
  v_ids uuid[] := '{}';
  v_antes timestamptz;
  v_antes_id uuid;
  v_vueltas integer := 0;
begin
  loop
    v := pg_temp.resueltas(p_actor, p_limite, v_antes, v_antes_id);
    if jsonb_array_length(v -> 'filas') > p_limite then
      raise exception 'ORACULO: una página trajo más de % filas (%)', p_limite, v;
    end if;
    v_ids := v_ids || pg_temp.ids(v -> 'filas');
    exit when v -> 'siguiente' = 'null'::jsonb or v -> 'siguiente' is null;
    if jsonb_array_length(v -> 'filas') <> p_limite then
      raise exception 'ORACULO: una página incompleta trajo «siguiente» (%)', v;
    end if;
    v_antes := (v -> 'siguiente' ->> 'resuelto_en')::timestamptz;
    v_antes_id := (v -> 'siguiente' ->> 'evento_id')::uuid;
    v_vueltas := v_vueltas + 1;
    if v_vueltas > 50 then raise exception 'ORACULO: el cursor no avanza (%)', v; end if;
  end loop;
  return v_ids;
end $$;
create function pg_temp.con_celular(p_actor uuid, p_ids uuid[])
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.actividades_con_llamada_celular_fn(p_ids);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.evento(p_id text)
returns uuid language sql as $$
  select e.id from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
$$;
-- Los evento_id de una lista de filas, ordenados como vienen.
create function pg_temp.ids(p_filas jsonb)
returns uuid[] language sql immutable as $$
  select coalesce(array_agg((f ->> 'evento_id')::uuid order by n), '{}') from jsonb_array_elements(p_filas) with ordinality as t(f, n)
$$;
-- Fija a mano cuándo se resolvió (enlace o descarte), con los triggers de usuario apagados un momento.
create function pg_temp.resuelta_en(p_evento uuid, p_en timestamptz)
returns void language plpgsql as $$
begin
  execute 'alter table crm.llamadas_celular_enlaces disable trigger user';
  execute 'alter table crm.llamadas_celular_eventos disable trigger user';
  update crm.llamadas_celular_enlaces set creado_en = least(creado_en, p_en), actualizado_en = p_en where evento_id = p_evento;
  update crm.llamadas_celular_eventos set descartado_en = p_en where id = p_evento and atencion = 'descartado_con_motivo';
  execute 'alter table crm.llamadas_celular_eventos enable trigger user';
  execute 'alter table crm.llamadas_celular_enlaces enable trigger user';
end $$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  a9 constant uuid := '00000000-0000-0000-0000-0000000000a9';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  b2 constant uuid := '00000000-0000-0000-0000-0000000000b2';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  c8 constant uuid := '00000000-0000-0000-0000-0000000000c8';
  t0 bigint := floor(extract(epoch from now()))::bigint - 50000;
  -- Inicio del día de hoy en Lima: las horas de resolución se fijan respecto a él.
  hoy constant timestamptz := date_trunc('day', now() at time zone 'America/Lima') at time zone 'America/Lima';
  k1 text; k2 text;
  op1 uuid := gen_random_uuid(); op4 uuid := gen_random_uuid(); op7 uuid := gen_random_uuid();
  op8 uuid := gen_random_uuid(); op8b uuid := gen_random_uuid(); op9 uuid := gen_random_uuid();
  e1 uuid; e2 uuid; e3 uuid; e4 uuid; e5 uuid; e6 uuid; e7 uuid; e8 uuid; e9 uuid; e10 uuid; e11 uuid; e12 uuid;
  empate uuid[];
  esperado uuid[];
  v_r jsonb;
  v_f jsonb;
  v_ok integer := 0;
begin
  -- ═════ Preparación: C1 de a1 y C2 de a3 (otro equipo) ═════
  update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  k1 := crm.asignar_celular('C1', a1) ->> 'credencial';
  k2 := crm.asignar_celular('C2', a3) ->> 'credencial';
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);

  -- e1: registrada al colgar (v5). e2: descartada. e3: pendiente. e4: de a3, registrada (otro equipo).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 1), '900000001'));
  e1 := pg_temp.evento('C1-' || (t0 + 1));
  v_r := pg_temp.v5(a1, op1, c1, 'C1-' || (t0 + 1));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO prep: e1 no quedó unida (%)', v_r; end if;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 2), '900000002'));
  e2 := pg_temp.evento('C1-' || (t0 + 2));
  perform pg_temp.descartar(a1, e2);
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 3), '900000001'));
  e3 := pg_temp.evento('C1-' || (t0 + 3));
  perform pg_temp.enviar(k2, pg_temp.ev('C2-' || (t0 + 4), '900000008'));
  e4 := pg_temp.evento('C2-' || (t0 + 4));
  v_r := pg_temp.v5(a3, op4, c8, 'C2-' || (t0 + 4));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO prep: e4 no quedó unida (%)', v_r; end if;
  -- e5: RECIBIDA ayer, descartada hoy (entra: cuenta el día en que se resolvió).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 5), '900000002'));
  e5 := pg_temp.evento('C1-' || (t0 + 5));
  perform pg_temp.descartar(a1, e5);
  -- e6: recibida y descartada ayer (fuera).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 6), '900000002'));
  e6 := pg_temp.evento('C1-' || (t0 + 6));
  perform pg_temp.descartar(a1, e6);
  -- e7: registrada ayer (fuera).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 7), '900000001'));
  e7 := pg_temp.evento('C1-' || (t0 + 7));
  v_r := pg_temp.v5(a1, op7, c1, 'C1-' || (t0 + 7));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO prep: e7 no quedó unida (%)', v_r; end if;
  -- e8: registrada ayer; hoy se deshace y se registra el corregido (entra, con el resultado nuevo).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 8), '900000001'));
  e8 := pg_temp.evento('C1-' || (t0 + 8));
  v_r := pg_temp.v5(a1, op8, c1, 'C1-' || (t0 + 8));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO prep: e8 no quedó unida (%)', v_r; end if;
  -- e9 (registrada) y e10 (descartada): resueltas en el MISMO instante, para el empate entre las dos ramas.
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 9), '900000001'));
  e9 := pg_temp.evento('C1-' || (t0 + 9));
  v_r := pg_temp.v5(a1, op9, c1, 'C1-' || (t0 + 9));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then raise exception 'ORACULO prep: e9 no quedó unida (%)', v_r; end if;
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 10), '900000002'));
  e10 := pg_temp.evento('C1-' || (t0 + 10));
  perform pg_temp.descartar(a1, e10);
  if e1 is null or e2 is null or e3 is null or e4 is null or e5 is null or e6 is null or e7 is null or e8 is null
     or e9 is null or e10 is null then
    raise exception 'ORACULO prep: faltan llamadas';
  end if;

  -- Horas de resolución (el orden de hoy, de la más tarde a la más temprana: e9 = e10, e8, e5, e4, e2, e1).
  perform pg_temp.resuelta_en(e1, hoy + interval '10 minutes');
  perform pg_temp.resuelta_en(e2, hoy + interval '20 minutes');
  perform pg_temp.resuelta_en(e4, hoy + interval '25 minutes');
  perform pg_temp.resuelta_en(e5, hoy + interval '30 minutes');
  perform pg_temp.resuelta_en(e6, hoy - interval '1 hour');
  perform pg_temp.resuelta_en(e7, hoy - interval '1 hour');
  perform pg_temp.resuelta_en(e8, hoy - interval '2 hours');
  perform pg_temp.resuelta_en(e9, hoy + interval '50 minutes');
  perform pg_temp.resuelta_en(e10, hoy + interval '50 minutes');
  -- Recibidas: e5 y e6 ayer; las demás, hoy. Así el orden por recepción no coincide con el de resolución.
  alter table crm.llamadas_celular_eventos disable trigger user;
  update crm.llamadas_celular_eventos set recibido_en = hoy - interval '3 hours' where id in (e5, e6);
  update crm.llamadas_celular_eventos set recibido_en = hoy + interval '1 minute' where id = e9;
  update crm.llamadas_celular_eventos set recibido_en = hoy + interval '2 minutes' where id = e10;
  update crm.llamadas_celular_eventos set recibido_en = hoy + interval '3 minutes' where id = e8;
  update crm.llamadas_celular_eventos set recibido_en = hoy + interval '4 minutes' where id = e2;
  update crm.llamadas_celular_eventos set recibido_en = hoy + interval '5 minutes' where id = e1;
  alter table crm.llamadas_celular_eventos enable trigger user;
  -- e8: Deshacer y el resultado corregido HOY. El enlace pasa al corregido y el trigger le vuelve a sellar la hora.
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = op8;
  v_r := pg_temp.v5(a1, op8b, c1, 'C1-' || (t0 + 8));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'movido'
     or (select actualizado_en from crm.llamadas_celular_enlaces where evento_id = e8) is distinct from now()
     or (select creado_en from crm.llamadas_celular_enlaces where evento_id = e8) >= hoy then
    raise exception 'ORACULO prep: el enlace de e8 no pasó hoy al corregido conservando su nacimiento de ayer (%)', v_r;
  end if;
  -- Su hora del día (creado_en sigue en ayer: resuelta_en solo lo baja, nunca lo sube).
  perform pg_temp.resuelta_en(e8, hoy + interval '40 minutes');
  empate := case when e9 > e10 then array[e9, e10] else array[e10, e9] end;
  esperado := empate || array[e8, e5, e2, e1];

  -- ═════ R. «Qué pasó hoy» ═════
  v_r := pg_temp.resueltas(a1);
  if pg_temp.ids(v_r -> 'filas') is distinct from esperado or v_r -> 'siguiente' <> 'null'::jsonb then
    raise exception 'ORACULO R1: a1 debía ver %, por hora de resolución, sin la pendiente, la de otro equipo ni lo resuelto ayer, y sin «siguiente» (%)', esperado, v_r;
  end if;
  select f into v_f from jsonb_array_elements(v_r -> 'filas') f where (f ->> 'evento_id')::uuid = e1;
  if v_f ->> 'atencion' is distinct from 'registrado' or (v_f ->> 'actividad_id')::uuid is distinct from op1
     or v_f ->> 'resultado' is distinct from 'volver_a_llamar' or v_f ->> 'via' is distinct from 'al_colgar'
     or (v_f ->> 'deshecho')::boolean is distinct from false or v_f ->> 'etiqueta' is distinct from 'C1'
     or (v_f ->> 'es_propia')::boolean is not true or (v_f ->> 'lead_id')::uuid is distinct from c1
     or (v_f ->> 'resuelto_en')::timestamptz is distinct from hoy + interval '10 minutes' then
    raise exception 'ORACULO R2: la registrada no trae su resultado, vía, etiqueta, lead u hora de resolución (%)', v_f;
  end if;
  select f into v_f from jsonb_array_elements(v_r -> 'filas') f where (f ->> 'evento_id')::uuid = e2;
  if v_f ->> 'atencion' is distinct from 'descartado_con_motivo' or v_f ->> 'motivo_descarte' is distinct from 'personal'
     or v_f ->> 'actividad_id' is not null or (v_f ->> 'resuelto_en')::timestamptz is distinct from hoy + interval '20 minutes' then
    raise exception 'ORACULO R3: la descartada no trae su motivo u hora de resolución (%)', v_f;
  end if;
  select f into v_f from jsonb_array_elements(v_r -> 'filas') f where (f ->> 'evento_id')::uuid = e8;
  if (v_f ->> 'actividad_id')::uuid is distinct from op8b or (v_f ->> 'deshecho')::boolean is distinct from false then
    raise exception 'ORACULO R11: la registrada ayer y corregida hoy debía salir con el resultado corregido (%)', v_f;
  end if;
  select f into v_f from jsonb_array_elements(v_r -> 'filas') f where (f ->> 'evento_id')::uuid = e5;
  if (v_f ->> 'recibido_en')::timestamptz >= hoy then
    raise exception 'ORACULO R12: e5 debía ser una llamada recibida ayer (%)', v_f;
  end if;
  v_r := pg_temp.resueltas(b1);
  if pg_temp.ids(v_r -> 'filas') is distinct from esperado or (v_r -> 'filas' -> 0 ->> 'es_propia')::boolean is not false then
    raise exception 'ORACULO R4: la supervisión de a1 debía ver las mismas, no como propias (%)', v_r;
  end if;
  v_r := pg_temp.resueltas(g1);
  if pg_temp.ids(v_r -> 'filas') is distinct from empate || array[e8, e5, e4, e2, e1] then
    raise exception 'ORACULO R5: gerencia debía ver las siete resueltas hoy, de los dos equipos, en orden (%)', v_r;
  end if;
  if pg_temp.ids(pg_temp.resueltas(a3) -> 'filas') is distinct from array[e4]
     or pg_temp.ids(pg_temp.resueltas(b2) -> 'filas') is distinct from array[e4] then
    raise exception 'ORACULO R6: el otro equipo debía ver solo la suya';
  end if;

  -- ═════ P. Páginas ═════
  v_r := pg_temp.resueltas(a1, 1);
  if jsonb_array_length(v_r -> 'filas') <> 1 or v_r -> 'siguiente' = 'null'::jsonb
     or (v_r -> 'siguiente' ->> 'evento_id')::uuid is distinct from empate[1]
     or (v_r -> 'siguiente' ->> 'resuelto_en')::timestamptz is distinct from hoy + interval '50 minutes' then
    raise exception 'ORACULO P1: la primera página de 1 debía traer una fila y el cursor de esa fila (%)', v_r;
  end if;
  foreach v_f in array array['1', '2', '4', '5', '6']::jsonb[] loop
    if pg_temp.todas(a1, (v_f #>> '{}')::integer) is distinct from esperado then
      raise exception 'ORACULO P2: con páginas de % no salió cada fila una vez y en orden (% / %)', v_f,
        pg_temp.todas(a1, (v_f #>> '{}')::integer), esperado;
    end if;
  end loop;
  if pg_temp.todas(g1, 2) is distinct from empate || array[e8, e5, e4, e2, e1] then
    raise exception 'ORACULO P3: gerencia por páginas de 2 no recorrió las siete en orden';
  end if;
  -- El cursor del empate: la página que empieza después de la primera del empate trae la segunda.
  v_r := pg_temp.resueltas(a1, 1, hoy + interval '50 minutes', empate[1]);
  if pg_temp.ids(v_r -> 'filas') is distinct from array[empate[2]] then
    raise exception 'ORACULO P4: el cursor perdió la otra llamada resuelta en el mismo instante (%)', v_r;
  end if;
  begin
    perform pg_temp.resueltas(a1, 50, now(), null);
    raise exception 'ORACULO P5: cursor sin evento_id aceptado';
  exception when sqlstate '22023' then v_ok := v_ok + 1;
  end;
  begin
    perform pg_temp.resueltas(a1, 50, null, e1);
    raise exception 'ORACULO P5: cursor sin resuelto_en aceptado';
  exception when sqlstate '22023' then v_ok := v_ok + 1;
  end;

  -- Deshacer el resultado sin volver a registrar: la fila sigue y lo dice (el enlace se conserva).
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = op1;
  select f into v_f from jsonb_array_elements(pg_temp.resueltas(a1) -> 'filas') f where (f ->> 'evento_id')::uuid = e1;
  if (v_f ->> 'deshecho')::boolean is not true then
    raise exception 'ORACULO R8: el resultado deshecho no se marca (%)', v_f;
  end if;
  foreach v_f in array array['0', '201']::jsonb[] loop
    begin
      perform pg_temp.resueltas(a1, (v_f #>> '{}')::integer);
      raise exception 'ORACULO R9: límite % aceptado', v_f;
    exception when sqlstate '22023' then v_ok := v_ok + 1;
    end;
  end loop;
  begin
    perform pg_temp.resueltas(a1, null);
    raise exception 'ORACULO R9: límite nulo aceptado';
  exception when sqlstate '22023' then v_ok := v_ok + 1;
  end;
  begin
    perform pg_temp.resueltas(a9);
    raise exception 'ORACULO R10: un analista de baja leyó «Qué pasó hoy»';
  exception when insufficient_privilege then v_ok := v_ok + 1;
  end;

  -- ═════ A. Marca «Celular» (de la octava; no cambia) ═════
  v_r := pg_temp.con_celular(a1, array[op1, op4, gen_random_uuid()]);
  if jsonb_array_length(v_r) <> 1 or (v_r -> 0 ->> 'actividad_id')::uuid is distinct from op1
     or v_r -> 0 ->> 'etiqueta' is distinct from 'C1' or v_r -> 0 ->> 'via' is distinct from 'al_colgar'
     or (v_r -> 0 ->> 'evento_id')::uuid is distinct from e1 then
    raise exception 'ORACULO A1: a1 debía ver solo la marca de su gestión (%)', v_r;
  end if;
  v_r := pg_temp.con_celular(g1, array[op1, op4]);
  if jsonb_array_length(v_r) <> 2 then raise exception 'ORACULO A2: gerencia debía ver las dos marcas (%)', v_r; end if;
  if pg_temp.con_celular(a3, array[op1]) <> '[]'::jsonb then raise exception 'ORACULO A3: otro equipo vio una marca ajena'; end if;
  if pg_temp.con_celular(a1, '{}') <> '[]'::jsonb or pg_temp.con_celular(a1, null) <> '[]'::jsonb then
    raise exception 'ORACULO A4: una lista vacía o nula no devolvió []';
  end if;
  begin
    perform pg_temp.con_celular(a1, array(select gen_random_uuid() from generate_series(1, 501)));
    raise exception 'ORACULO A5: se aceptaron más de 500 gestiones';
  exception when sqlstate '22023' then v_ok := v_ok + 1;
  end;
  begin
    perform pg_temp.con_celular(a9, array[op1]);
    raise exception 'ORACULO A6: un analista de baja leyó las marcas';
  exception when insufficient_privilege then v_ok := v_ok + 1;
  end;

  -- ═════ L. Borde del día de Lima (núcleo como dueño, con p_ahora fijo y lejos de hoy) ═════
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 11), '900000002'));
  e11 := pg_temp.evento('C1-' || (t0 + 11));
  perform pg_temp.descartar(a1, e11);
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 12), '900000002'));
  e12 := pg_temp.evento('C1-' || (t0 + 12));
  perform pg_temp.descartar(a1, e12);
  -- 04:59:59.999999 UTC = 23:59:59.999999 del 14/01 en Lima; 05:00 UTC = 00:00 del 15/01 en Lima.
  perform pg_temp.resuelta_en(e11, '2020-01-15 04:59:59.999999+00');
  perform pg_temp.resuelta_en(e12, '2020-01-15 05:00:00+00');
  perform set_config('request.jwt.claim.sub', g1::text, true);
  if pg_temp.ids(private.llamadas_celular_resueltas_hoy(g1, 50, '2020-01-15 12:00:00+00', null, null) -> 'filas') is distinct from array[e12]
     or pg_temp.ids(private.llamadas_celular_resueltas_hoy(g1, 50, '2020-01-15 04:00:00+00', null, null) -> 'filas') is distinct from array[e11] then
    raise exception 'ORACULO L1: el día no se cortó a la medianoche de Lima';
  end if;
  perform set_config('request.jwt.claim.sub', '', true);

  -- ═════ B. Lead dado de baja: sus llamadas desaparecen de las dos lecturas, también para gerencia ═════
  update crm.leads set activo = false where id = c1;
  if pg_temp.ids(pg_temp.resueltas(a1) -> 'filas') && array[e1, e8, e9]
     or pg_temp.ids(pg_temp.resueltas(g1) -> 'filas') && array[e1, e8, e9]
     or not (pg_temp.ids(pg_temp.resueltas(a1) -> 'filas') @> array[e10, e5, e2])
     or pg_temp.con_celular(g1, array[op1]) <> '[]'::jsonb then
    raise exception 'ORACULO B1: la llamada de un lead dado de baja siguió visible (o se llevó las de otros leads)';
  end if;

  if v_ok <> 8 then raise exception 'ORACULO: % de 8 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO RESUELTAS PAGINADAS OK: «Qué pasó hoy» por hora de resolución (recibida ayer y resuelta hoy, corregida hoy, lo de ayer fuera), páginas con cursor y empate entre ramas, cursor y límite validados, resultado, deshecho, vía, motivo, ámbito por rol y equipo, borde de Lima, lead dado de baja; marca «Celular» sin cambios';
end;
$oraculo$;

rollback;
