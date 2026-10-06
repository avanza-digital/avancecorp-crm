-- Oráculo de la décima (20261006150154, id de origen en la bandeja y el detalle) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql (v4 como DOBLE declarado). Se corre como dueño después de las nueve y la
-- décima; todo en una transacción que termina en ROLLBACK. Cubre: cada fila de la bandeja y el detalle traen su id de
-- origen (el del celular, no otro), por páginas también; el ámbito no cambia (otro equipo no ve ni lee); y el propósito:
-- con el id de la fila, la v5 desde la pestaña deja la llamada unida con vía «pestana».
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
create function pg_temp.bandeja(p_actor uuid, p_limite integer default 50, p_antes timestamptz default null, p_antes_id uuid default null)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.llamadas_celular_bandeja_fn(p_limite, p_antes, p_antes_id);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.detalle(p_actor uuid, p_evento uuid)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.llamada_celular_detalle_fn(p_evento);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.v5(p_actor uuid, p_op uuid, p_lead uuid, p_origen text, p_via text)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.registrar_llamada_v5(p_op, p_lead, 'volver_a_llamar', null, null, null, null, false, false, p_origen, p_via);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.evento(p_id text)
returns uuid language sql as $$
  select e.id from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
$$;
-- La fila de la bandeja de un evento, o null.
create function pg_temp.fila(p_bandeja jsonb, p_evento uuid)
returns jsonb language sql immutable as $$
  select f from jsonb_array_elements(p_bandeja -> 'filas') f where (f ->> 'evento_id')::uuid = p_evento
$$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  t0 bigint := floor(extract(epoch from now()))::bigint - 50000;
  k1 text; k2 text;
  e1 uuid; e2 uuid; e3 uuid;
  v_r jsonb;
  v_f jsonb;
  v_ids text[] := '{}';
  v_ok integer := 0;
begin
  -- ═════ Preparación: C1 de a1 y C2 de a3 (otro equipo) ═════
  update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  k1 := crm.asignar_celular('C1', a1) ->> 'credencial';
  k2 := crm.asignar_celular('C2', a3) ->> 'credencial';
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 1), '900000001'));
  perform pg_temp.enviar(k1, pg_temp.ev('C1-' || (t0 + 2), '900000001'));
  perform pg_temp.enviar(k2, pg_temp.ev('C2-' || (t0 + 3), '900000008'));
  e1 := pg_temp.evento('C1-' || (t0 + 1));
  e2 := pg_temp.evento('C1-' || (t0 + 2));
  e3 := pg_temp.evento('C2-' || (t0 + 3));
  if e1 is null or e2 is null or e3 is null then raise exception 'ORACULO prep: faltan llamadas'; end if;

  -- ═════ O. El id de origen en la bandeja y el detalle ═════
  v_r := pg_temp.bandeja(a1);
  if pg_temp.fila(v_r, e1) ->> 'evento_origen_id' is distinct from 'C1-' || (t0 + 1)
     or pg_temp.fila(v_r, e2) ->> 'evento_origen_id' is distinct from 'C1-' || (t0 + 2) then
    raise exception 'ORACULO O1: cada fila de la bandeja debía traer su propio id de origen (%)', v_r;
  end if;
  if pg_temp.fila(v_r, e1) ->> 'atencion' is distinct from 'requiere_resultado' then
    raise exception 'ORACULO O2: la fila perdió la atención efectiva (%)', pg_temp.fila(v_r, e1);
  end if;
  -- Por páginas de 1: cada página trae el id de su fila.
  v_r := pg_temp.bandeja(a1, 1);
  v_ids := v_ids || (v_r -> 'filas' -> 0 ->> 'evento_origen_id');
  v_r := pg_temp.bandeja(a1, 1, (v_r -> 'siguiente' ->> 'recibido_en')::timestamptz, (v_r -> 'siguiente' ->> 'evento_id')::uuid);
  v_ids := v_ids || (v_r -> 'filas' -> 0 ->> 'evento_origen_id');
  if not (v_ids @> array['C1-' || (t0 + 1), 'C1-' || (t0 + 2)]) then
    raise exception 'ORACULO O3: por páginas no salieron los dos ids de origen (%)', v_ids;
  end if;
  v_f := pg_temp.detalle(a1, e1);
  if v_f ->> 'evento_origen_id' is distinct from 'C1-' || (t0 + 1) or (v_f ->> 'evento_id')::uuid is distinct from e1 then
    raise exception 'ORACULO O4: el detalle debía traer su id de origen (%)', v_f;
  end if;
  if pg_temp.detalle(b1, e1) ->> 'evento_origen_id' is distinct from 'C1-' || (t0 + 1) then
    raise exception 'ORACULO O5: la supervisión de a1 debía leer el mismo id';
  end if;

  -- ═════ A. El ámbito no cambia ═════
  if pg_temp.fila(pg_temp.bandeja(a1), e3) is not null or pg_temp.fila(pg_temp.bandeja(a3), e1) is not null then
    raise exception 'ORACULO A1: la bandeja mostró una llamada de otro equipo';
  end if;
  begin
    perform pg_temp.detalle(a3, e1);
    raise exception 'ORACULO A2: otro equipo leyó el detalle';
  exception when insufficient_privilege then v_ok := v_ok + 1;
  end;

  -- ═════ P. El propósito: con el id de la fila, la v5 desde la pestaña deja la llamada unida ═════
  v_f := pg_temp.fila(pg_temp.bandeja(a1), e1);
  v_r := pg_temp.v5(a1, gen_random_uuid(), c1, v_f ->> 'evento_origen_id', 'pestana');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado'
     or (select via from crm.llamadas_celular_enlaces where evento_id = e1) is distinct from 'pestana'
     or pg_temp.fila(pg_temp.bandeja(a1), e1) is not null then
    raise exception 'ORACULO P1: registrar desde la pestaña con el id de la fila debía unir la llamada y sacarla de la bandeja (%)', v_r;
  end if;

  if v_ok <> 1 then raise exception 'ORACULO: % de 1 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO BANDEJA CON ORIGEN OK: id de origen en cada fila (también por páginas) y en el detalle, ámbito sin cambios, y la v5 desde la pestaña une la llamada con vía «pestana»';
end;
$oraculo$;

rollback;
