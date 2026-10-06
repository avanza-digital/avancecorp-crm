-- Oráculo de la octava (20261005201010, lecturas de F4-b) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql (v4 como DOBLE declarado). Se corre como dueño después de las siete y la
-- octava; todo en una transacción que termina en ROLLBACK. Cubre «Qué pasó hoy» (solo resueltas, solo hoy en Lima,
-- resultado, deshecho, vía, motivo, ámbito por rol y equipo, lead dado de baja, límite) y la marca «Celular» (solo
-- las unidas y visibles, vacía, tope, roles).
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia; a9 está de baja.
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
create function pg_temp.resueltas(p_actor uuid, p_limite integer default 100)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.llamadas_celular_resueltas_hoy_fn(p_limite);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
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
-- Los evento_id de una respuesta, ordenados como vienen.
create function pg_temp.ids(p_filas jsonb)
returns uuid[] language sql immutable as $$
  select coalesce(array_agg((f ->> 'evento_id')::uuid order by n), '{}') from jsonb_array_elements(p_filas) with ordinality as t(f, n)
$$;

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
  k1 text; k2 text;
  op1 uuid := gen_random_uuid(); op4 uuid := gen_random_uuid();
  e1 uuid; e2 uuid; e3 uuid; e4 uuid; e5 uuid;
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

  -- e5: de AYER, descartada (no entra en «hoy»).
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 5), '900000002'));
  e5 := pg_temp.evento('C1-' || (t0 + 5));
  perform pg_temp.descartar(a1, e5);
  alter table crm.llamadas_celular_eventos disable trigger user;
  update crm.llamadas_celular_eventos set recibido_en = now() - interval '1 day' where id = e5;
  alter table crm.llamadas_celular_eventos enable trigger user;
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
  if e1 is null or e2 is null or e3 is null or e4 is null or e5 is null then raise exception 'ORACULO prep: faltan llamadas'; end if;

  -- ═════ R. «Qué pasó hoy» ═════
  v_r := pg_temp.resueltas(a1);
  if pg_temp.ids(v_r) is distinct from array[e2, e1] then
    raise exception 'ORACULO R1: a1 debía ver e2 y e1 (más reciente primero), sin la pendiente, la de otro equipo ni la de ayer (%)', v_r;
  end if;
  select f into v_f from jsonb_array_elements(v_r) f where (f ->> 'evento_id')::uuid = e1;
  if v_f ->> 'atencion' is distinct from 'registrado' or (v_f ->> 'actividad_id')::uuid is distinct from op1
     or v_f ->> 'resultado' is distinct from 'volver_a_llamar' or v_f ->> 'via' is distinct from 'al_colgar'
     or (v_f ->> 'deshecho')::boolean is distinct from false or v_f ->> 'etiqueta' is distinct from 'C1'
     or (v_f ->> 'es_propia')::boolean is not true or (v_f ->> 'lead_id')::uuid is distinct from c1 then
    raise exception 'ORACULO R2: la registrada no trae su resultado, vía, etiqueta o lead (%)', v_f;
  end if;
  select f into v_f from jsonb_array_elements(v_r) f where (f ->> 'evento_id')::uuid = e2;
  if v_f ->> 'atencion' is distinct from 'descartado_con_motivo' or v_f ->> 'motivo_descarte' is distinct from 'personal'
     or v_f ->> 'actividad_id' is not null then
    raise exception 'ORACULO R3: la descartada no trae su motivo (%)', v_f;
  end if;
  v_r := pg_temp.resueltas(b1);
  if pg_temp.ids(v_r) is distinct from array[e2, e1] or (v_r -> 0 ->> 'es_propia')::boolean is not false then
    raise exception 'ORACULO R4: la supervisión de a1 debía ver las mismas, no como propias (%)', v_r;
  end if;
  v_r := pg_temp.resueltas(g1);
  if not (pg_temp.ids(v_r) @> array[e1, e2, e4]) or pg_temp.ids(v_r) && array[e3, e5] or jsonb_array_length(v_r) <> 3 then
    raise exception 'ORACULO R5: gerencia debía ver las tres resueltas de hoy, de los dos equipos (%)', v_r;
  end if;
  if pg_temp.ids(pg_temp.resueltas(a3)) is distinct from array[e4] or pg_temp.ids(pg_temp.resueltas(b2)) is distinct from array[e4] then
    raise exception 'ORACULO R6: el otro equipo debía ver solo la suya';
  end if;
  if jsonb_array_length(pg_temp.resueltas(a1, 1)) <> 1 then
    raise exception 'ORACULO R7: el límite no se respetó';
  end if;
  -- Deshacer el resultado: la fila lo dice (el enlace se conserva).
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = op1;
  select f into v_f from jsonb_array_elements(pg_temp.resueltas(a1)) f where (f ->> 'evento_id')::uuid = e1;
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

  -- ═════ A. Marca «Celular» ═════
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

  -- ═════ B. Lead dado de baja: sus llamadas desaparecen de las dos lecturas, también para gerencia ═════
  update crm.leads set activo = false where id = c1;
  if pg_temp.ids(pg_temp.resueltas(a1)) && array[e1] or pg_temp.ids(pg_temp.resueltas(g1)) && array[e1]
     or pg_temp.con_celular(g1, array[op1]) <> '[]'::jsonb then
    raise exception 'ORACULO B1: la llamada de un lead dado de baja siguió visible';
  end if;

  if v_ok <> 6 then raise exception 'ORACULO: % de 6 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO LECTURAS ANALISTA OK: «Qué pasó hoy» (solo resueltas, solo hoy, resultado, deshecho, vía, motivo, ámbito por rol y equipo, límite) y marca «Celular» (solo unidas y visibles, vacía, tope, roles), lead dado de baja';
end;
$oraculo$;

rollback;
