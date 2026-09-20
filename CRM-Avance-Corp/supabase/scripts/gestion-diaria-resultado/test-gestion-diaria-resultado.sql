-- Oráculo del resultado tipificado de llamada (Gestión Diaria, Fase 2) sobre la
-- copia del banco. Corre como postgres con la identidad del actor en
-- request.jwt.claim.sub (como PostgREST); para lo que depende de la RLS cambia
-- al rol authenticated. ESCRIBE de verdad (llamadas, tareas, descartes,
-- deshacer) y termina con rollback. Acaba con GESTION_DIARIA_RESULTADO_OK o
-- revienta con el nombre de la comprobación. Los actores y los leads se
-- DESCUBREN del fixture: el analista activo con más leads abiertos sin veto,
-- su supervisor, un analista de otro equipo.
begin;
set local statement_timeout = '120s';

create temporary table o_actores on commit drop as
with v as (
  select e.perfil_id, e.supervisor_id from crm.equipo e
  where e.rol_crm = 'vendedor' and e.activo and e.supervisor_id is not null
    and exists (select 1 from crm.equipo s where s.perfil_id = e.supervisor_id and s.rol_crm = 'supervisor' and s.activo)
  order by e.perfil_id
)
select (select perfil_id from v limit 1) as v1,
       (select supervisor_id from v limit 1) as sup1,
       (select perfil_id from v offset 1 limit 1) as v_ajeno,
       (select perfil_id from crm.equipo where rol_crm = 'gerencia' and activo limit 1) as ger;

-- El fixture del banco es pequeño: los leads del oráculo NACEN aquí por la vía
-- legal (crm.crear_lead_si_disponible, como test-rls.mjs), con la identidad de
-- gerencia, asignados al analista. Diez para v1 (todos en «nuevo», sin intentos)
-- y uno para el analista ajeno. Se deshacen con el rollback final.
create temporary table o_leads (n int, id uuid, etapa text) on commit drop;
create temporary table o_ajeno (id uuid) on commit drop;
do $alta$
declare a o_actores; i int; v jsonb; v_id uuid;
begin
  select * into a from o_actores;
  if a.v1 is null or a.sup1 is null or a.v_ajeno is null or a.ger is null then
    raise exception 'FIXTURE: faltan actores (v1 %, sup1 %, v_ajeno %, ger %)', a.v1, a.sup1, a.v_ajeno, a.ger;
  end if;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.ger, 'role', 'authenticated')::text, true);
  for i in 1..12 loop
    v_id := gen_random_uuid();
    v := crm.crear_lead_si_disponible(
      p_nombre_completo => format('ORACULO F2 LEAD %s', i), p_telefono => format('9997%s', lpad(i::text, 5, '0')),
      p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
      p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
      p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v1, p_nota => 'fixture del oraculo F2',
      p_telefono_alternativo => case when i = 6 then '999799999' else null end);
    insert into o_leads select i, l.id, l.etapa from crm.leads l where l.id = v_id and l.vendedor_id = a.v1 and l.activo and l.etapa = 'nuevo';
  end loop;
  v_id := gen_random_uuid();
  v := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ORACULO F2 AJENO', p_telefono => '999788888',
    p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
    p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
    p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v_ajeno, p_nota => 'fixture del oraculo F2',
    p_telefono_alternativo => null);
  insert into o_ajeno select l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v_ajeno and l.activo;
  if (select cardinality(array_agg(id)) from o_leads) is distinct from 12 or not exists (select 1 from o_ajeno) then
    raise exception 'FIXTURE: no se pudieron crear los leads del oraculo (%)', (select cardinality(array_agg(id)) from o_leads);
  end if;
end $alta$;

do $oraculo$
declare
  a o_actores;
  L uuid[];
  v jsonb; v2 jsonb; v_meta jsonb;
  v_op uuid; v_op2 uuid; v_act uuid; v_sig uuid; v_tarea crm.tareas%rowtype; v_lead crm.leads%rowtype;
  v_manana date; v_ts10 timestamptz; v_ts16 timestamptz; v_domingo timestamptz; v_21 timestamptz; v_pasado timestamptz; v_pasado_manana timestamptz;
  v_n_antes int; v_tareas_antes int; v_etapa text; v_estado text; v_sql text;
  v_lima timestamp;
begin
  select * into a from o_actores;
  select array_agg(id order by n) into L from o_leads;   -- L[1]..L[10]
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', a.v1, 'role', 'authenticated')::text, true);

  v_manana := ((now() at time zone 'America/Lima')::date + 1);
  if extract(isodow from v_manana) = 7 then v_manana := v_manana + 1; end if;
  v_ts10 := (v_manana + time '10:00') at time zone 'America/Lima';
  v_ts16 := (v_manana + time '16:00') at time zone 'America/Lima';
  v_pasado_manana := ((v_manana + 1 + case when extract(isodow from v_manana + 1) = 7 then 1 else 0 end) + time '10:00') at time zone 'America/Lima';
  v_domingo := ((v_manana + (7 - extract(isodow from v_manana))::int) + time '10:00') at time zone 'America/Lima';
  v_21 := (v_manana + time '21:00') at time zone 'America/Lima';
  v_pasado := now() - interval '1 hour';

  -- ── A. volver_a_llamar con tarea siguiente: actividad + metadata + tarea + etapa ──
  select coalesce(cardinality(array_agg(x.id)), 0) into v_n_antes from crm.actividades x
   where x.lead_id = L[2] and x.tipo in ('llamada_realizada','llamada_no_contestada')
     and x.creado_en >= private.inicio_ciclo_lead(L[2]);
  select etapa into v_etapa from crm.leads where id = L[2];
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[2], 'volver_a_llamar', null, 'Pide que la llamen mañana',
         jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts10));
  if (v->>'ok')::boolean is not true or (v->>'version')::int <> 2 or (v->>'operacion_id')::uuid <> v_op
     or v->>'comando' <> 'registrar_llamada' or (v->>'lead_id')::uuid <> L[2] or (v->>'replay')::boolean
     or (v->>'actividad_id')::uuid <> v_op or v->>'siguiente_id' is null or (v->>'descartado')::boolean
     or v->>'resultado' <> 'volver_a_llamar' or (v->>'intento_n')::int <> v_n_antes + 1 then
    raise exception 'A: sobre inesperado: %', v;
  end if;
  v_sig := (v->>'siguiente_id')::uuid;
  select metadata into v_meta from crm.actividades where id = v_op and lead_id = L[2] and tipo = 'llamada_realizada' and creado_por = a.v1;
  if v_meta is null or v_meta->>'evento' <> 'resultado_llamada' or v_meta->>'resultado' <> 'volver_a_llamar'
     or v_meta->>'etapa_anterior' <> v_etapa or (v_meta->>'siguiente_id')::uuid <> v_sig
     or (v_meta->>'descartado')::boolean or v_meta ? 'submotivo' or v_meta ? 'tarea_id' then
    raise exception 'A: metadata inesperada: %', v_meta;
  end if;
  select * into v_tarea from crm.tareas where id = v_sig;
  if v_tarea.lead_id <> L[2] or v_tarea.tipo <> 'llamada' or v_tarea.estado <> 'pendiente' or v_tarea.vence_en <> v_ts10 then
    raise exception 'A: tarea siguiente inesperada: % % %', v_tarea.tipo, v_tarea.estado, v_tarea.vence_en;
  end if;
  if (select etapa from crm.leads where id = L[2]) <> 'contactado' then raise exception 'A: el lead debio quedar en contactado'; end if;
  if not exists (select 1 from crm.sla_operacion_recibos r where r.actor_id = a.v1 and r.operacion_id = v_op and r.respuesta is not null) then
    raise exception 'A: no hay recibo confirmado';
  end if;

  -- ── B. replay idéntico: nada nuevo, mismo sobre, replay=true ───────────────
  select cardinality(array_agg(id)) into v_tareas_antes from crm.tareas where lead_id = L[2];
  v2 := crm.registrar_llamada_v3(v_op, L[2], 'volver_a_llamar', null, 'Pide que la llamen mañana',
          jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts10));
  if (v2->>'replay')::boolean is not true or (v2->>'actividad_id')::uuid <> v_op or (v2->>'siguiente_id')::uuid <> v_sig
     or v2->>'comando' <> 'registrar_llamada' or (v2->>'ok')::boolean is not true or (v2->>'intento_n')::int <> v_n_antes + 1 then
    raise exception 'B: replay inesperado: %', v2;
  end if;
  if (select cardinality(array_agg(id)) from crm.tareas where lead_id = L[2]) <> v_tareas_antes then raise exception 'B: el replay creo otra tarea'; end if;
  if (select metadata from crm.actividades where id = v_op) <> v_meta then raise exception 'B: el replay toco la metadata'; end if;

  -- ── C. replay con OTRO resultado → 23505 ───────────────────────────────────
  begin
    perform crm.registrar_llamada_v3(v_op, L[2], 'no_contesto', null, 'Pide que la llamen mañana',
      jsonb_build_object('tipo', 'llamada', 'titulo', 'Volver a llamar', 'vence_en', v_ts10));
    raise exception 'C: debio fallar con 23505';
  exception when others then
    if sqlstate <> '23505' then raise exception 'C: fallo con % (%), no con 23505', sqlstate, sqlerrm; end if;
  end;

  -- ── D. Validaciones: 22023 y sin rastro ────────────────────────────────────
  v_op2 := gen_random_uuid();
  for v_sql in select unnest(array[
    format('crm.registrar_llamada_v3(%L, %L, ''no_interesado'')', v_op2, L[3]),                                              -- sin submotivo
    format('crm.registrar_llamada_v3(%L, %L, ''no_interesado'', ''prestamo'')', v_op2, L[3]),                                -- submotivo de otro catálogo
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'')', v_op2, L[3]),                                            -- sin siguiente
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L)', v_op2, L[3], jsonb_build_object('tipo','whatsapp','titulo','x','vence_en',v_ts10)),
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_domingo)),
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_21)),
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_pasado)),
    format('crm.registrar_llamada_v3(%L, %L, ''agendo_reunion'')', v_op2, L[3]),                                             -- sin cita
    format('crm.registrar_llamada_v3(%L, %L, ''no_contesto'', ''otro'')', v_op2, L[3]),                                      -- submotivo indebido
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L, null, false, true)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_ts10)), -- no_insista indebido
    format('crm.registrar_llamada_v3(%L, %L, ''numero_errado'', null, null, %L, null, true)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_ts10)), -- descartar + siguiente
    format('crm.registrar_llamada_v3(%L, %L, ''volver_a_llamar'', null, null, %L, null, true)', v_op2, L[3], jsonb_build_object('tipo','llamada','titulo','x','vence_en',v_ts10)), -- descartar indebido
    format('crm.registrar_llamada_v3(%L, %L, ''fax'')', v_op2, L[3]),
    format('crm.registrar_llamada_v3(%L, %L, ''no_contesto'', null, null, null, %L)', v_op2, L[3], v_sig)                   -- tarea de OTRO lead
  ]) loop
    begin
      execute 'select ' || v_sql into v;
      raise exception 'D: debio fallar con 22023: %', v_sql;
    exception when others then
      if sqlstate <> '22023' then raise exception 'D: % fallo con % (%), no con 22023', v_sql, sqlstate, sqlerrm; end if;
    end;
  end loop;
  if exists (select 1 from crm.actividades where id = v_op2) or exists (select 1 from crm.sla_operacion_recibos where operacion_id = v_op2) then
    raise exception 'D: una validacion dejo rastro';
  end if;

  -- ── E. no_interesado: descarte con submotivo en la misma operación ─────────
  select etapa into v_etapa from crm.leads where id = L[3];
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[3], 'no_interesado', 'sin_fondos_ahora', 'Sin liquidez hasta diciembre');
  if (v->>'descartado')::boolean is not true or v->>'etapa' <> 'descartado' or (v->>'siguiente_id') is not null then raise exception 'E: sobre: %', v; end if;
  select * into v_lead from crm.leads where id = L[3];
  if v_lead.etapa <> 'descartado' or v_lead.motivo_descarte <> 'sin_fondos' or v_lead.descartado_por <> a.v1 or v_lead.descartado_en is null then
    raise exception 'E: lead no descartado como se esperaba: % % %', v_lead.etapa, v_lead.motivo_descarte, v_lead.descartado_por;
  end if;
  select metadata into v_meta from crm.actividades where id = v_op;
  if v_meta->>'submotivo' <> 'sin_fondos_ahora' or v_meta->>'motivo_descarte' <> 'sin_fondos'
     or v_meta->>'etapa_al_descartar' <> 'contactado' or (v_meta->>'descartado_en')::timestamptz <> v_lead.descartado_en
     or v_meta->>'etapa_anterior' <> v_etapa then
    raise exception 'E: metadata: %', v_meta;
  end if;
  if exists (select 1 from crm.tareas where lead_id = L[3] and estado = 'pendiente') then raise exception 'E: quedaron tareas pendientes tras el descarte'; end if;
  if not exists (select 1 from crm.actividades where lead_id = L[3] and tipo = 'cambio_etapa' and metadata->>'etapa_nueva' = 'descartado') then
    raise exception 'E: falta el cambio_etapa del descarte';
  end if;

  -- ── F. deshacer E: vuelve a la etapa que tenía al descartarse (contactado) ──
  v2 := crm.deshacer_resultado_llamada(v_op);
  if (v2->>'ok')::boolean is not true or (v2->>'descarte_revertido')::boolean is not true or (v2->>'tarea_cancelada')::boolean
     or v2->>'etapa' <> 'contactado' then raise exception 'F: sobre: %', v2; end if;
  select * into v_lead from crm.leads where id = L[3];
  if v_lead.etapa <> 'contactado' or v_lead.motivo_descarte is not null or v_lead.descartado_en is not null then
    raise exception 'F: lead no restaurado: % % %', v_lead.etapa, v_lead.motivo_descarte, v_lead.descartado_en;
  end if;
  select metadata into v_meta from crm.actividades where id = v_op;
  if v_meta->>'deshecho_en' is null or (v_meta->>'deshecho_por')::uuid <> a.v1 or v_meta->>'resultado' <> 'no_interesado' then raise exception 'F: metadata sin marca: %', v_meta; end if;
  if not exists (select 1 from crm.actividades where id = (v2->>'nota_id')::uuid and tipo = 'nota' and lead_id = L[3]
                 and metadata->>'evento' = 'resultado_deshecho' and (metadata->>'actividad_id')::uuid = v_op and creado_por = a.v1) then
    raise exception 'F: falta la nota del deshacer';
  end if;
  begin
    perform crm.deshacer_resultado_llamada(v_op);
    raise exception 'F: deshacer dos veces debio fallar';
  exception when others then
    if sqlstate <> '22023' then raise exception 'F: segundo deshacer fallo con % (%)', sqlstate, sqlerrm; end if;
  end;

  -- ── G. deshacer ajeno (otro analista, el supervisor) y fuera de 24 h ───────
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[4], 'no_interesado', 'desconfianza');
  if (select motivo_descarte from crm.leads where id = L[4]) <> 'sin_interes' then raise exception 'G: motivo esperado sin_interes'; end if;
  foreach v_estado in array array[a.v_ajeno::text, a.sup1::text] loop
    perform set_config('request.jwt.claim.sub', v_estado, true);
    begin
      perform crm.deshacer_resultado_llamada(v_op);
      raise exception 'G: % pudo deshacer lo de otro', v_estado;
    exception when others then
      if sqlstate <> 'P0002' then raise exception 'G: % fallo con % (%), no con P0002', v_estado, sqlstate, sqlerrm; end if;
    end;
  end loop;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  update crm.actividades set creado_en = creado_en - interval '25 hours' where id = v_op;  -- como postgres
  begin
    perform crm.deshacer_resultado_llamada(v_op);
    raise exception 'G: deshacer a las 25 h debio fallar';
  exception when others then
    if sqlstate <> '22023' or sqlerrm not like '%24 horas%' then raise exception 'G: 25 h fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  if (select etapa from crm.leads where id = L[4]) <> 'descartado' then raise exception 'G: el lead no debio moverse'; end if;

  -- ── H. numero_errado + descartar por datos inválidos (lead en nuevo: no avanza) ──
  if (select etapa from crm.leads where id = L[5]) = 'nuevo' then
    v_op := gen_random_uuid();
    v := crm.registrar_llamada_v3(v_op, L[5], 'numero_errado', null, null, null, null, true);
    if (v->>'descartado')::boolean is not true then raise exception 'H: sobre: %', v; end if;
    select * into v_lead from crm.leads where id = L[5];
    if v_lead.etapa <> 'descartado' or v_lead.motivo_descarte <> 'datos_invalidos' then raise exception 'H: lead: % %', v_lead.etapa, v_lead.motivo_descarte; end if;
    select metadata into v_meta from crm.actividades where id = v_op and tipo = 'llamada_no_contestada';
    if v_meta is null or v_meta->>'etapa_al_descartar' <> 'nuevo' then raise exception 'H: metadata: %', v_meta; end if;
    v2 := crm.deshacer_resultado_llamada(v_op);
    if v2->>'etapa' <> 'nuevo' or (v2->>'descarte_revertido')::boolean is not true then raise exception 'H: deshacer: %', v2; end if;
  else
    raise notice 'H omitido: el lead 5 no estaba en nuevo';
  end if;

  -- ── I. no_es_la_persona con tarea al 2.º número; sin avance de etapa ───────
  select etapa into v_etapa from crm.leads where id = L[6];
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[6], 'no_es_la_persona', null, 'Contestó su hermano', jsonb_build_object('tipo','llamada','titulo','Llamar al 2.º número','vence_en', v_ts10));
  if v->>'siguiente_id' is null or (v->>'descartado')::boolean then raise exception 'I: sobre: %', v; end if;
  if (select etapa from crm.leads where id = L[6]) <> v_etapa then raise exception 'I: una no contestada no mueve la etapa'; end if;
  if (select tipo from crm.actividades where id = v_op) <> 'llamada_no_contestada' then raise exception 'I: tipo'; end if;

  -- ── J. agendo_reunion: cita creada, lead en reunion_agendada; deshacer cancela y retrocede ──
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[7], 'agendo_reunion', null, 'Quiere verlo el jueves',
         jsonb_build_object('tipo','reunion','titulo','Cita con el cliente','vence_en', v_ts16, 'modalidad_reunion', 'presencial', 'ubicacion_reunion', 'Oficina San Isidro'));
  v_sig := (v->>'siguiente_id')::uuid;
  select * into v_tarea from crm.tareas where id = v_sig;
  if v_tarea.tipo <> 'reunion' or v_tarea.estado <> 'pendiente' then raise exception 'J: cita no creada'; end if;
  if (select etapa from crm.leads where id = L[7]) <> 'reunion_agendada' then raise exception 'J: el lead debio subir a reunion_agendada'; end if;
  v2 := crm.deshacer_resultado_llamada(v_op);
  if (v2->>'tarea_cancelada')::boolean is not true or (v2->>'descarte_revertido')::boolean or v2->>'etapa' <> 'contactado' then raise exception 'J: deshacer: %', v2; end if;
  if (select estado from crm.tareas where id = v_sig) <> 'cancelada' then raise exception 'J: la cita no se cancelo'; end if;

  -- ── K. no_contesto: «no responde» exige 2 intentos; el 2.º descarta ────────
  v_op := gen_random_uuid();
  begin
    perform crm.registrar_llamada_v3(v_op, L[1], 'no_contesto', null, null, null, null, true);
    raise exception 'K: con un solo intento no se descarta por no responde';
  exception when others then
    if sqlstate <> '22023' then raise exception 'K: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  if exists (select 1 from crm.actividades where id = v_op) then raise exception 'K: el rechazo dejo la actividad'; end if;
  v := crm.registrar_llamada_v3(v_op, L[1], 'no_contesto', null, null, jsonb_build_object('tipo','whatsapp','titulo','WhatsApp','vence_en', v_ts10));
  if (v->>'intento_n')::int <> 1 or v->>'siguiente_id' is null then raise exception 'K: primer intento: %', v; end if;
  v_op2 := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op2, L[1], 'no_contesto', null, null, null, null, true);
  if (v->>'descartado')::boolean is not true or (v->>'intento_n')::int <> 2 then raise exception 'K: segundo intento: %', v; end if;
  if (select motivo_descarte from crm.leads where id = L[1]) <> 'no_responde' then raise exception 'K: motivo no_responde'; end if;
  if (select estado from crm.tareas where id = (v_meta->>'x')::uuid) is not null then null; end if;

  -- ── L. Cerrar una tarea de LLAMADA con el resultado (camino cerrar_tarea_v2) ──
  select * into v_tarea from crm.tareas where lead_id = L[2] and tipo = 'llamada' and estado = 'pendiente' order by creado_en desc limit 1;
  if v_tarea.id is null then raise exception 'L: falta la tarea de llamada creada en A'; end if;
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[2], 'volver_a_llamar', null, 'Segunda llamada', jsonb_build_object('tipo','llamada','titulo','Tercer toque','vence_en', v_pasado_manana), v_tarea.id);
  v_act := (v->>'actividad_id')::uuid;
  if v_act = v_op or v->>'siguiente_id' is null or (v->>'tarea_id') is distinct from null then null; end if;
  if v_act is null or v_act = v_op then raise exception 'L: la actividad debe venir del cierre (id propio): %', v; end if;
  select * into v_tarea from crm.tareas where id = v_tarea.id;
  if v_tarea.estado <> 'completada' or v_tarea.resultado_actividad_id <> v_act then raise exception 'L: tarea no cerrada con la actividad: % %', v_tarea.estado, v_tarea.resultado_actividad_id; end if;
  select metadata into v_meta from crm.actividades where id = v_act;
  if (v_meta->>'tarea_id')::uuid <> v_tarea.id or v_meta->>'resultado' <> 'volver_a_llamar' or (v_meta->>'intento_n')::int <> v_n_antes + 2 then raise exception 'L: metadata: %', v_meta; end if;
  v2 := crm.registrar_llamada_v3(v_op, L[2], 'volver_a_llamar', null, 'Segunda llamada', jsonb_build_object('tipo','llamada','titulo','Tercer toque','vence_en', v_pasado_manana), v_tarea.id);
  if (v2->>'replay')::boolean is not true or (v2->>'actividad_id')::uuid <> v_act then raise exception 'L: replay: %', v2; end if;
  -- la cita cancelada de J no puede cerrarse por aquí (22023), ni una tarea de reunión
  begin
    perform crm.registrar_llamada_v3(gen_random_uuid(), L[7], 'no_contesto', null, null, null, v_sig);
    raise exception 'L: una cita cancelada no se cierra con una llamada';
  exception when others then
    if sqlstate <> '22023' then raise exception 'L: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;

  -- ── M. Lead ajeno e inexistente: 42501 con el mismo texto (sin fuga) ────────
  foreach v_estado in array array[(select id from o_ajeno)::text, gen_random_uuid()::text] loop
    begin
      perform crm.registrar_llamada_v3(gen_random_uuid(), v_estado::uuid, 'no_contesto');
      raise exception 'M: % debio recibir 42501', v_estado;
    exception when others then
      if sqlstate <> '42501' or sqlerrm <> 'Gestion no disponible en tu ambito' then raise exception 'M: % fallo con % (%)', v_estado, sqlstate, sqlerrm; end if;
    end;
  end loop;

  -- ── N. El supervisor registra sobre un lead de su analista ─────────────────
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[8], 'no_contesto');
  if (v->>'ok')::boolean is not true or (select creado_por from crm.actividades where id = (v->>'actividad_id')::uuid) <> a.sup1 then raise exception 'N: supervisor: %', v; end if;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);

  -- ── O. «No insistir»: se marca y NO se deshace ─────────────────────────────
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[9], 'pide_otro_producto', 'prestamo', null, null, null, false, true);
  if (v->>'no_insista')::boolean is not true or (select no_contactar from crm.leads where id = L[9]) is not true
     or (select motivo_descarte from crm.leads where id = L[9]) <> 'pide_credito' then raise exception 'O: no marcado: %', v; end if;
  begin
    perform crm.deshacer_resultado_llamada(v_op);
    raise exception 'O: un No insistir no se deshace';
  exception when others then
    if sqlstate <> 'P0429' then raise exception 'O: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;

  -- ── P. El supervisor reabre desde el Centro de rescate; el deshacer del analista ya no revierte ──
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[10], 'no_interesado', 'ya_invirtio_con_otro');
  if (select motivo_descarte from crm.leads where id = L[10]) <> 'competencia' then raise exception 'P: motivo competencia'; end if;
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  perform crm.reabrir_lead_fn(L[10]);
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  if (select etapa from crm.leads where id = L[10]) <> 'nuevo' then raise exception 'P: el supervisor no reabrio'; end if;
  v2 := crm.deshacer_resultado_llamada(v_op);
  if (v2->>'descarte_revertido')::boolean or v2->>'etapa' <> 'nuevo' then raise exception 'P: deshacer sobre descarte ya reabierto: %', v2; end if;

  -- ── R. Replay TARDÍO (la cita ya venció) recupera el recibo; replay con
  --      descarte o «No insistir» cambiados → 23505 (hallazgos Codex 19/09) ──
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[6], 'agendo_reunion', null, 'Cita inmediata',
         jsonb_build_object('tipo','reunion','titulo','Cita ya','vence_en', clock_timestamp() + interval '2 seconds', 'modalidad_reunion', 'virtual', 'enlace_reunion', 'https://meet.example/x'));
  perform pg_sleep(3);
  -- (el payload del writer debe ser IDÉNTICO: se reenvía la misma fecha)
  v2 := crm.registrar_llamada_v3(v_op, L[6], 'agendo_reunion', null, 'Cita inmediata',
          jsonb_build_object('tipo','reunion','titulo','Cita ya','vence_en', ((select t.vence_en from crm.tareas t where t.id = (v->>'siguiente_id')::uuid)), 'modalidad_reunion', 'virtual', 'enlace_reunion', 'https://meet.example/x'));
  if (v2->>'replay')::boolean is not true or (v2->>'actividad_id')::uuid <> v_op then raise exception 'R: replay tardio: %', v2; end if;
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[8], 'numero_errado', null, null, null, null, false);
  begin
    perform crm.registrar_llamada_v3(v_op, L[8], 'numero_errado', null, null, null, null, true);
    raise exception 'R: replay con descarte cambiado debio fallar';
  exception when others then
    if sqlstate <> '23505' then raise exception 'R: descarte cambiado fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  if (select etapa from crm.leads where id = L[8]) = 'descartado' then raise exception 'R: el replay descarto'; end if;

  -- ── S. El supervisor registra «volver a llamar» SIN agendar; al dueño se le exige ──
  perform set_config('request.jwt.claim.sub', a.sup1::text, true);
  v := crm.registrar_llamada_v3(gen_random_uuid(), L[11], 'volver_a_llamar', null, 'Lo llamo yo mañana');
  if (v->>'ok')::boolean is not true or v->>'siguiente_id' is not null then raise exception 'S: supervisor sin agenda: %', v; end if;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  begin
    perform crm.registrar_llamada_v3(gen_random_uuid(), L[11], 'agendo_reunion');
    raise exception 'S: al dueno se le exige la cita';
  exception when others then
    if sqlstate <> '22023' then raise exception 'S: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;

  -- ── T. Deshacer cuando OTRO lead vivo ya tiene el teléfono → 22023 humano, sin sellar ──
  v_op := gen_random_uuid();
  v := crm.registrar_llamada_v3(v_op, L[11], 'numero_errado', null, null, null, null, true);
  if (v->>'descartado')::boolean is not true then raise exception 'T: no descarto'; end if;
  perform set_config('request.jwt.claim.sub', a.ger::text, true);
  v2 := crm.crear_lead_si_disponible(p_nombre_completo => 'ORACULO F2 GEMELO', p_telefono => (select telefono from crm.leads where id = L[11]),
          p_origen => 'oficina', p_monto_estimado => 1000, p_moneda => 'PEN', p_id => gen_random_uuid(), p_correo => null, p_dni => null,
          p_genero => null, p_fecha_nacimiento => null, p_distrito => null, p_etapa => 'nuevo', p_categoria_interes => null,
          p_vendedor_id => a.v_ajeno, p_nota => null, p_telefono_alternativo => null);
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  begin
    perform crm.deshacer_resultado_llamada(v_op);
    raise exception 'T: debio fallar por telefono vivo';
  exception when others then
    if sqlstate <> '22023' or sqlerrm not like '%otro lead vivo%' then raise exception 'T: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  if (select etapa from crm.leads where id = L[11]) <> 'descartado' or (select metadata ? 'deshecho_en' from crm.actividades where id = v_op) then
    raise exception 'T: el fallo no debio sellar nada';
  end if;

  -- ── U. Un número errado NO es evidencia de «no responde» ─────────────────
  perform crm.registrar_llamada_v3(gen_random_uuid(), L[12], 'numero_errado');
  begin
    perform crm.registrar_llamada_v3(gen_random_uuid(), L[12], 'no_contesto', null, null, null, null, true);
    raise exception 'U: un numero errado no cuenta como intento sin respuesta';
  exception when others then
    if sqlstate <> '22023' then raise exception 'U: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;

  -- ── V. Deshacer un descarte = reapertura: ciclo nuevo declarado ────────────
  v_op := gen_random_uuid();
  perform crm.registrar_llamada_v3(v_op, L[12], 'no_interesado', 'otro');
  v2 := crm.deshacer_resultado_llamada(v_op);
  if (v2->>'ciclo_nuevo')::boolean is not true or (v2->>'descarte_revertido')::boolean is not true then raise exception 'V: %', v2; end if;

  -- ── Q. Bajo la RLS (rol authenticated): falsificación vetada, lecturas con metadata ──
  perform set_config('role', 'authenticated', true);
  begin
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (L[6], 'nota', 'falsa', '{"resultado":"volver_a_llamar"}'::jsonb, a.v1);
    raise exception 'Q: un INSERT con metadata.resultado debio morir';
  exception when others then
    if sqlstate <> '42501' then raise exception 'Q: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  begin
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (L[6], 'nota', 'falsa', '{"evento":"resultado_deshecho"}'::jsonb, a.v1);
    raise exception 'Q: un INSERT con evento resultado_deshecho debio morir';
  exception when others then
    if sqlstate <> '42501' then raise exception 'Q: fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (L[6], 'nota', 'nota normal', '{"evento":"revision"}'::jsonb, a.v1);
  begin
    update crm.actividades set metadata = '{"resultado":"no_contesto"}'::jsonb where id = v_act;
    raise exception 'Q: authenticated no debe poder actualizar actividades';
  exception when others then
    if sqlstate <> '42501' then raise exception 'Q: UPDATE fallo con % (%)', sqlstate, sqlerrm; end if;
  end;
  if (select metadata->>'resultado' from crm.actividades where id = v_act) <> 'volver_a_llamar' then raise exception 'Q: la metadata cambio'; end if;
  if not exists (select 1 from jsonb_array_elements(crm.actividades_de_lead_fn(L[2], 100)->'items') i
                 where (i->>'id')::uuid = v_act and i->'metadata'->>'resultado' = 'volver_a_llamar') then
    raise exception 'Q: el historial por lead no trae la metadata';
  end if;
  v := crm.registro_actividad_fn((now() at time zone 'America/Lima')::date, (now() at time zone 'America/Lima')::date, array[a.v1], null, null, 500);
  if not exists (select 1 from jsonb_array_elements(v->'items') i where (i->>'id')::uuid = v_act
                 and i->'metadata'->>'resultado' = 'volver_a_llamar' and (i->'metadata'->>'intento_n')::int = v_n_antes + 2) then
    raise exception 'Q: el registro de Gestion Diaria no trae el resultado';
  end if;
  if has_function_privilege('anon', 'crm.registrar_llamada_v3(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.llamada_registrar(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.deshacer_resultado_llamada(uuid)', 'EXECUTE') then
    raise exception 'Q: ACL abierta';
  end if;
  perform set_config('role', 'postgres', true);
end;
$oraculo$;

select 'GESTION_DIARIA_RESULTADO_OK';
rollback;
