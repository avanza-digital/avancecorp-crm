-- Oráculo de F4-a (20261005155914, enlace exacto encuesta ↔ llamada) sobre el banco REDUCIDO de
-- supabase/tests/llamadas-celular/base.sql, con la v4 como DOBLE declarado (base.sql). Se corre como dueño después de
-- las cinco y F4-a; todo en una transacción que termina en ROLLBACK. Cubre: sin id = v4; aviso antes y aviso tardío
-- (intención cumplida por la ingesta); reloj adelantado (sin la regla de los 10 minutos en el camino exacto, que sigue
-- en el manual); los enlaces imposibles guardan igual el resultado con su motivo; Deshacer → corregido (enlace e
-- intención pasan al corregido); la intención que no coincide se retira sin unir; la vía; los candados de la
-- intención; la purga a 32 días y la autorización. Las carreras van en la pasada de concurrencia del guion.
-- Equipo del banco: b1 supervisa a a1 y a2; b2 supervisa a a3; g1 es gerencia.
-- No sustituye el gate test-rls.mjs contra un banco con el esquema de producción (y la v4 real).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create function pg_temp.ev(p_id text, p_numero text, p_extra jsonb default '{}'::jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object('v', 1, 'evento_origen_id', p_id, 'numero', p_numero, 'direccion', 'saliente') || p_extra
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
create function pg_temp.v5(p_actor uuid, p_op uuid, p_lead uuid, p_resultado text, p_origen text, p_via text)
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_actor::text, true);
  execute 'set local role authenticated';
  v := crm.registrar_llamada_v5(p_op, p_lead, p_resultado, null, null, null, null, false, false, p_origen, p_via);
  execute 'set local role none';
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;
create function pg_temp.evento(p_id text)
returns crm.llamadas_celular_eventos language sql as $$
  select * from crm.llamadas_celular_eventos e where e.evento_origen_id = p_id
$$;
create function pg_temp.deshacer(p_act uuid)
returns void language sql as $$
  update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', now()) where id = p_act
$$;
create function pg_temp.enlace_de(p_id text)
returns crm.llamadas_celular_enlaces language sql as $$
  select l.* from crm.llamadas_celular_enlaces l join crm.llamadas_celular_eventos e on e.id = l.evento_id
  where e.evento_origen_id = p_id
$$;

do $oraculo$
declare
  a1 constant uuid := '00000000-0000-0000-0000-0000000000a1';
  a2 constant uuid := '00000000-0000-0000-0000-0000000000a2';
  a3 constant uuid := '00000000-0000-0000-0000-0000000000a3';
  b1 constant uuid := '00000000-0000-0000-0000-0000000000b1';
  g1 constant uuid := '00000000-0000-0000-0000-0000000000f1';
  c1 constant uuid := '00000000-0000-0000-0000-0000000000c1';
  c2 constant uuid := '00000000-0000-0000-0000-0000000000c2';
  c6 constant uuid := '00000000-0000-0000-0000-0000000000c6';
  t0 bigint := floor(extract(epoch from now()))::bigint - 50000;
  k1 text; k2 text; k4 text;
  v_r jsonb;
  v_ev crm.llamadas_celular_eventos%rowtype;
  v_enl crm.llamadas_celular_enlaces%rowtype;
  op uuid[] := array(select gen_random_uuid() from generate_series(1, 25));
  v_act uuid; v_act2 uuid;
  v_id text; v_id2 text;
  v_n integer;
  v_ok integer := 0;
  id_de constant text := 'C1-';
begin
  -- ═════ Preparación ═════
  update crm.llamadas_celular_politica set limite_envios_minuto = 600, limite_envios_dia = 20000;
  perform set_config('request.jwt.claim.sub', g1::text, true); execute 'set local role authenticated';
  k1 := crm.asignar_celular('C1', a1) ->> 'credencial';
  k2 := crm.asignar_celular('C2', a3) ->> 'credencial';
  k4 := crm.asignar_celular('C4', b1) ->> 'credencial';
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);

  -- ═════ A. Sin id: igual que la v4, con enlace null ═════
  v_r := pg_temp.v5(a1, op[1], c1, 'volver_a_llamar', null, null);
  if not (v_r ? 'enlace') or jsonb_typeof(v_r -> 'enlace') <> 'null' or (v_r ->> 'actividad_id')::uuid <> op[1]
     or not exists (select 1 from crm.actividades where id = op[1]) then
    raise exception 'ORACULO A1: sin id, la v5 no se comportó como la v4 (%)', v_r;
  end if;

  -- ═════ B. El aviso llegó antes: la encuesta lo une al colgar; el replay no duplica ═════
  v_id := id_de || (t0 + 1);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', v_id, 'al_colgar');
  v_enl := pg_temp.enlace_de(v_id);
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' or v_enl.actividad_id is distinct from op[2] or v_enl.via is distinct from 'al_colgar'
     or (pg_temp.evento(v_id)).atencion is distinct from 'registrado' then
    raise exception 'ORACULO B1: con el aviso ya llegado, la encuesta no quedó unida al colgar (%, %)', v_r, row_to_json(v_enl);
  end if;
  v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'repetido' or (v_r ->> 'replay')::boolean is not true
     or (select count(*) from crm.llamadas_celular_enlaces) <> 1 then
    raise exception 'ORACULO B2: el reintento de la encuesta no respondió «repetido» o duplicó (%)', v_r;
  end if;

  -- ═════ C. Reloj del celular adelantado: el camino exacto une; el manual conserva la regla de 10 minutos ═════
  v_id := id_de || floor(extract(epoch from now() + interval '20 minutes'))::bigint;
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002',
    jsonb_build_object('ocurrio_en', to_char(now() + interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
  v_r := pg_temp.v5(a1, op[3], c2, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'enlazado' then
    raise exception 'ORACULO C1: con el reloj adelantado el enlace exacto se rechazó (%)', v_r;
  end if;
  v_id := id_de || (floor(extract(epoch from now() + interval '20 minutes'))::bigint + 1);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000006',
    jsonb_build_object('ocurrio_en', to_char(now() + interval '20 minutes', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c6, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
  v_ev := pg_temp.evento(v_id);
  begin
    perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
    perform crm.enlazar_llamada_celular(v_ev.id, v_act);
    raise exception 'ORACULO C2: el enlace manual perdió la regla de los 10 minutos';
  exception when sqlstate '22023' then
    if sqlerrm not like '%antes de la llamada%' then raise exception 'ORACULO C2: rechazo con otro motivo (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;

  -- ═════ D. Aviso tardío: la encuesta deja una intención y la ingesta la cumple sola ═════
  v_id := id_de || (t0 + 4);
  v_r := pg_temp.v5(a1, op[4], c1, 'no_contesto', v_id, 'pestana');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente'
     or not exists (select 1 from private.llamadas_celular_intenciones
                    where evento_origen_id = v_id and actividad_id = op[4] and via = 'pestana' and analista_id = a1) then
    raise exception 'ORACULO D1: sin aviso, la encuesta no dejó su intención (%)', v_r;
  end if;
  v_r := pg_temp.v5(a1, op[4], c1, 'no_contesto', v_id, 'pestana');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente' or (select count(*) from private.llamadas_celular_intenciones) <> 1 then
    raise exception 'ORACULO D2: el reintento con la intención pendiente no respondió «pendiente» (%)', v_r;
  end if;
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  v_enl := pg_temp.enlace_de(v_id);
  if v_enl.actividad_id is distinct from op[4] or v_enl.via is distinct from 'pestana' or v_enl.enlazado_por is distinct from a1
     or (pg_temp.evento(v_id)).atencion is distinct from 'registrado'
     or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
    raise exception 'ORACULO D3: al llegar el aviso, la intención no se cumplió (%)', row_to_json(v_enl);
  end if;

  -- ═════ E. Enlaces imposibles: el resultado se guarda IGUAL y la respuesta dice por qué ═════
  v_r := pg_temp.v5(a1, op[5], c1, 'volver_a_llamar', 'X1-123', 'al_colgar');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'no_enlazado' or v_r -> 'enlace' ->> 'motivo' is distinct from 'id_invalido'
     or not exists (select 1 from crm.actividades where id = op[5]) then
    raise exception 'ORACULO E1: un id mal formado no guardó el resultado o no dio su motivo (%)', v_r;
  end if;
  v_r := pg_temp.v5(a1, op[6], c1, 'volver_a_llamar', id_de || floor(extract(epoch from now() - interval '31 days'))::bigint, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'id_invalido' then raise exception 'ORACULO E2: un id fuera de la ventana se aceptó (%)', v_r; end if;
  v_r := pg_temp.v5(a1, op[7], c1, 'volver_a_llamar', 'C2-' || (t0 + 7), 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'celular_ajeno' then raise exception 'ORACULO E3: el id del celular de otro analista se aceptó (%)', v_r; end if;
  v_id := id_de || (t0 + 8);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
  v_r := pg_temp.v5(a1, op[8], c1, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'otro_lead' or (pg_temp.evento(v_id)).atencion is distinct from 'requiere_resultado' then
    raise exception 'ORACULO E4: la llamada de otro lead se unió (%)', v_r;
  end if;
  v_id := id_de || (t0 + 9);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  v_ev := pg_temp.evento(v_id);
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  perform crm.descartar_llamada_celular(v_ev.id, 'personal');
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
  v_r := pg_temp.v5(a1, op[9], c1, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'descartada' then raise exception 'ORACULO E5: se unió una llamada descartada (%)', v_r; end if;
  v_r := pg_temp.v5(a1, op[10], c1, 'volver_a_llamar', id_de || (t0 + 1), 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'ya_tiene_resultado' or not exists (select 1 from crm.actividades where id = op[10]) then
    raise exception 'ORACULO E6: un segundo resultado reemplazó al vigente (%)', v_r;
  end if;
  -- Ambigua (900000006 es de c6 y c7, los dos del equipo de b1): no se une por este camino; va a la pestaña.
  v_id := 'C4-' || (t0 + 11);
  perform pg_temp.enviar(k4, pg_temp.ev(v_id, '900000006'));
  v_r := pg_temp.v5(b1, op[11], c6, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'otro_lead' or (pg_temp.evento(v_id)).identificacion is distinct from 'ambiguo' then
    raise exception 'ORACULO E7: la ambigua se unió por el camino exacto (%)', v_r;
  end if;
  -- El aviso llegó y se ignoró (entrante): no se guarda intención, nunca se cumpliría.
  v_id := id_de || (t0 + 12);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001', '{"direccion": "entrante"}'));
  v_r := pg_temp.v5(a1, op[12], c1, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'sin_llamada' or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
    raise exception 'ORACULO E8: con el aviso ignorado se guardó una intención (%)', v_r;
  end if;
  -- El mismo resultado (replay) con otro id: ya está unido a otra llamada.
  v_r := pg_temp.v5(a1, op[2], c1, 'volver_a_llamar', id_de || (t0 + 13), 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'resultado_ya_enlazado' then
    raise exception 'ORACULO E9: un resultado ya unido se dejó como intención de otra llamada (%)', v_r;
  end if;

  -- Una segunda encuesta con el mismo id y la primera pendiente (no deshecha): no la reemplaza.
  v_id := id_de || (t0 + 22);
  perform pg_temp.v5(a1, op[21], c1, 'volver_a_llamar', v_id, 'al_colgar');
  v_r := pg_temp.v5(a1, op[22], c1, 'volver_a_llamar', v_id, 'pestana');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'ya_tiene_resultado'
     or (select actividad_id from private.llamadas_celular_intenciones where evento_origen_id = v_id) <> op[21] then
    raise exception 'ORACULO E10: una segunda encuesta reemplazó la intención vigente (%)', v_r;
  end if;

  -- ═════ F. Deshacer → corregido: el enlace y la intención pasan al resultado corregido ═════
  perform pg_temp.deshacer(op[2]);
  v_r := pg_temp.v5(a1, op[13], c1, 'volver_a_llamar', id_de || (t0 + 1), 'al_colgar');
  v_enl := pg_temp.enlace_de(id_de || (t0 + 1));
  if v_r -> 'enlace' ->> 'estado' is distinct from 'movido' or v_enl.actividad_id is distinct from op[13] or v_enl.via is distinct from 'al_colgar' then
    raise exception 'ORACULO F1: el enlace no pasó al resultado corregido (%, %)', v_r, row_to_json(v_enl);
  end if;
  v_id := id_de || (t0 + 14);
  perform pg_temp.v5(a1, op[14], c2, 'volver_a_llamar', v_id, 'al_colgar');
  perform pg_temp.deshacer(op[14]);
  v_r := pg_temp.v5(a1, op[15], c2, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'estado' is distinct from 'pendiente'
     or (select actividad_id from private.llamadas_celular_intenciones where evento_origen_id = v_id) <> op[15] then
    raise exception 'ORACULO F2: la intención no pasó al resultado corregido (%)', v_r;
  end if;
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
  if (pg_temp.enlace_de(v_id)).actividad_id is distinct from op[15] then
    raise exception 'ORACULO F3: el aviso no se unió al resultado corregido';
  end if;
  v_r := pg_temp.v5(a1, op[14], c2, 'volver_a_llamar', v_id, 'al_colgar');
  if v_r -> 'enlace' ->> 'motivo' is distinct from 'resultado_deshecho' then
    raise exception 'ORACULO F4: el reintento de un resultado deshecho se unió (%)', v_r;
  end if;

  -- ═════ G. La intención que no coincide se retira sin unir ═════
  v_id := id_de || (t0 + 16);
  perform pg_temp.v5(a1, op[16], c1, 'volver_a_llamar', v_id, 'al_colgar');
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000002'));
  v_ev := pg_temp.evento(v_id);
  if v_ev.lead_id is distinct from c2 or v_ev.atencion is distinct from 'requiere_resultado' or pg_temp.enlace_de(v_id) is not null
     or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
    raise exception 'ORACULO G1: la intención de otro lead se cumplió o no se retiró (%)', row_to_json(v_ev);
  end if;
  v_id := id_de || (t0 + 17);
  perform pg_temp.v5(a1, op[17], c1, 'volver_a_llamar', v_id, 'al_colgar');
  perform pg_temp.deshacer(op[17]);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  if (pg_temp.evento(v_id)).atencion is distinct from 'requiere_resultado' or pg_temp.enlace_de(v_id) is not null
     or exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = v_id) then
    raise exception 'ORACULO G2: la intención con el resultado deshecho se cumplió o no se retiró';
  end if;

  -- ═════ H. La vía: manual en el enlace a mano; inmutable ═════
  v_id := id_de || (t0 + 18);
  perform pg_temp.enviar(k1, pg_temp.ev(v_id, '900000001'));
  insert into crm.actividades (lead_id, tipo, metadata, creado_por)
  values (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
  v_ev := pg_temp.evento(v_id);
  perform set_config('request.jwt.claim.sub', a1::text, true); execute 'set local role authenticated';
  perform crm.enlazar_llamada_celular(v_ev.id, v_act);
  execute 'set local role none'; perform set_config('request.jwt.claim.sub', '', true);
  if (pg_temp.enlace_de(v_id)).via is distinct from 'manual' then raise exception 'ORACULO H1: el enlace manual no quedó con vía «manual»'; end if;
  begin
    update crm.llamadas_celular_enlaces set via = 'al_colgar' where id = (pg_temp.enlace_de(v_id)).id;
    raise exception 'ORACULO H2: la vía de un enlace cambió';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;

  -- ═════ I. Validaciones de la v5 (fallan sin guardar nada) y autorización ═════
  begin
    perform pg_temp.v5(a1, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), null);
    raise exception 'ORACULO I1: con id y sin vía, la v5 guardó';
  exception when sqlstate '22023' then v_ok := v_ok + 1; end;
  begin
    perform pg_temp.v5(a1, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), 'manual');
    raise exception 'ORACULO I2: la v5 aceptó la vía «manual»';
  exception when sqlstate '22023' then v_ok := v_ok + 1; end;
  begin
    perform pg_temp.v5(a2, op[19], c1, 'volver_a_llamar', id_de || (t0 + 19), 'al_colgar');
    raise exception 'ORACULO I3: la v5 registró por un lead fuera de ámbito';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  if exists (select 1 from crm.actividades where id = op[19]) then
    raise exception 'ORACULO I4: una v5 rechazada dejó un resultado';
  end if;

  -- ═════ J. Candados de la intención ═════
  v_id := id_de || (t0 + 20);
  perform pg_temp.v5(a1, op[20], c1, 'volver_a_llamar', v_id, 'al_colgar');
  begin
    delete from private.llamadas_celular_intenciones where evento_origen_id = v_id;
    raise exception 'ORACULO J1: una intención se borró a mano';
  exception when insufficient_privilege then
    if sqlerrm not like '%no se borra a mano%' then raise exception 'ORACULO J1: frenado por otra regla (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;
  begin
    update private.llamadas_celular_intenciones set lead_id = c2 where evento_origen_id = v_id;
    raise exception 'ORACULO J2: una intención cambió de lead';
  exception when insufficient_privilege then v_ok := v_ok + 1; end;
  begin
    update private.llamadas_celular_intenciones set actividad_id = op[5] where evento_origen_id = v_id;
    raise exception 'ORACULO J3: una intención pasó a otro resultado sin deshacer el anterior';
  exception when insufficient_privilege then
    if sqlerrm not like '%si el anterior se deshizo%' then raise exception 'ORACULO J3: frenado por otra regla (%)', sqlerrm; end if;
    v_ok := v_ok + 1;
  end;

  -- ═════ K. Purga: intenciones a los 32 días ═════
  insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
    (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act;
  insert into crm.actividades (lead_id, tipo, metadata, creado_por) values
    (c1, 'llamada_realizada', '{"evento": "resultado_llamada", "resultado": "volver_a_llamar"}', a1) returning id into v_act2;
  insert into private.llamadas_celular_intenciones (evento_origen_id, analista_id, lead_id, actividad_id, via, creado_en) values
    ('C1-1000000001', a1, c1, v_act, 'al_colgar', now() - interval '33 days'),
    ('C1-1000000002', a1, c1, v_act2, 'al_colgar', now() - interval '31 days');
  select count(*) into v_n from private.llamadas_celular_intenciones;
  perform private.caducar_llamadas_celular();
  if exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = 'C1-1000000001')
     or not exists (select 1 from private.llamadas_celular_intenciones where evento_origen_id = 'C1-1000000002')
     or (select count(*) from private.llamadas_celular_intenciones) <> v_n - 1 then
    raise exception 'ORACULO K1: la purga no retiró solo la intención de más de 32 días';
  end if;

  if v_ok <> 8 then raise exception 'ORACULO: % de 8 rechazos esperados', v_ok; end if;
  raise notice 'ORACULO ENLACE EXACTO OK: sin id = v4, aviso antes, aviso tardío (intención cumplida), reloj adelantado (manual con 10 min), enlaces imposibles que guardan igual (id, ventana, celular ajeno, otro lead, descartada, ya con resultado, ambigua, aviso ignorado, resultado ya unido), Deshacer → corregido, intención que no coincide, vía, validaciones, candados y purga comprobados';
end;
$oraculo$;

rollback;
