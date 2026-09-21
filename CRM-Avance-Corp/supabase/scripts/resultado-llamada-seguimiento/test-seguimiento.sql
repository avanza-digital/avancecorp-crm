-- Base local autorizada; todas las escrituras del fixture terminan en rollback.
begin;
set local statement_timeout = '120s';
do $destino$
begin
  if current_database() <> 'gestion_diaria_f4_vista_chvrqh' then
    raise exception 'Este oraculo solo puede correr en la base local autorizada';
  end if;
end;
$destino$;

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
      p_nombre_completo => format('ORACULO V4 LEAD %s', i), p_telefono => format('9996%s', lpad(i::text, 5, '0')),
      p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
      p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
      p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v1, p_nota => 'fixture del oraculo V4',
      p_telefono_alternativo => case when i = 6 then '999699999' else null end);
    insert into o_leads select i, l.id, l.etapa from crm.leads l where l.id = v_id and l.vendedor_id = a.v1 and l.activo and l.etapa = 'nuevo';
  end loop;
  v_id := gen_random_uuid();
  v := crm.crear_lead_si_disponible(
    p_nombre_completo => 'ORACULO V4 AJENO', p_telefono => '999688888',
    p_origen => 'oficina', p_monto_estimado => 25000, p_moneda => 'PEN', p_id => v_id,
    p_correo => null, p_dni => null, p_genero => null, p_fecha_nacimiento => null, p_distrito => null,
    p_etapa => 'nuevo', p_categoria_interes => null, p_vendedor_id => a.v_ajeno, p_nota => 'fixture del oraculo V4',
    p_telefono_alternativo => null);
  insert into o_ajeno select l.id from crm.leads l where l.id = v_id and l.vendedor_id = a.v_ajeno and l.activo;
  if (select cardinality(array_agg(id)) from o_leads) is distinct from 12 or not exists (select 1 from o_ajeno) then
    raise exception 'FIXTURE: no se pudieron crear los leads del oraculo (%)', (select cardinality(array_agg(id)) from o_leads);
  end if;
end $alta$;

-- Altas del fixture como postgres; las llamadas probadas como authenticated.
create temporary table o_denegados on commit drop as
select perfil_id, rol_crm from crm.equipo where activo and rol_crm in ('coordinador', 'directorio');
grant select on o_actores, o_leads, o_ajeno, o_denegados to authenticated;
set local role authenticated;
do $casos$
declare
  a record; l uuid[]; d record; v jsonb; v2 jsonb; sig jsonb; meta jsonb;
  op uuid; op_legacy uuid; tarea uuid; ts timestamptz; dia date;
  q text; tipo_sig text; i int := 1; cantidad int; otro uuid;
begin
  select * into a from o_actores;
  select array_agg(id order by n) into l from o_leads;
  perform set_config('request.jwt.claim.sub', a.v1::text, true);
  perform set_config('request.jwt.claims', jsonb_build_object('sub', a.v1, 'role', 'authenticated')::text, true);
  if current_user <> 'authenticated' then raise exception 'No se prueba el rol real'; end if;
  dia := (now() at time zone 'America/Lima')::date + 1;
  if extract(isodow from dia) = 7 then dia := dia + 1; end if;
  ts := (dia + time '10:00') at time zone 'America/Lima';

  -- A. Conservar cartera + actividad + agenda, atomicos.
  op := gen_random_uuid();
  sig := jsonb_build_object('tipo','whatsapp','titulo','Retomar cuando tenga fondos','vence_en',ts);
  v := crm.registrar_llamada_v4(op,l[1],'no_interesado','sin_fondos_ahora',null,sig);
  if v->>'descartado' <> 'false' or v->>'siguiente_id' is null or v->>'etapa' <> 'contactado'
     or v->>'resultado' <> 'no_interesado' then raise exception 'A: %', v; end if;
  if not exists(select 1 from crm.leads where id=l[1] and vendedor_id=a.v1 and etapa='contactado' and motivo_descarte is null)
     or not exists(select 1 from crm.tareas where id=(v->>'siguiente_id')::uuid and lead_id=l[1] and tipo='whatsapp' and estado='pendiente') then
    raise exception 'A: cartera o agenda incorrecta'; end if;
  select metadata into meta from crm.actividades where id=op;
  if meta->>'resultado' <> 'no_interesado' or meta->>'submotivo' <> 'sin_fondos_ahora' or meta->>'descartado' <> 'false' then
    raise exception 'A: metadata %', meta; end if;

  -- B. Replay posterior al veto: confirma lo guardado, no repite ni reinterpreta.
  select cardinality(array_agg(id)) into cantidad from crm.tareas where lead_id=l[1];
  perform crm.marcar_no_contactar(l[1], 'Fixture: veto posterior al guardado');
  v2 := crm.registrar_llamada_v4(op,l[1],'no_interesado','sin_fondos_ahora',null,sig);
  if v2->>'replay' <> 'true' or v2->>'siguiente_id' <> v->>'siguiente_id'
     or (select cardinality(array_agg(id)) from crm.tareas where lead_id=l[1]) <> cantidad then
    raise exception 'B: replay %', v2; end if;
  foreach q in array array[
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L)',op,l[1],sig),
    format('crm.registrar_llamada_v4(%L,%L,''pide_otro_producto'',''otro'',null,%L)',op,l[1],sig),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''sin_fondos_ahora'',''otra nota'',%L)',op,l[1],sig)
  ] loop
    begin execute 'select '||q; raise exception 'B: acepto reinterpretar el recibo';
    exception when unique_violation then null; end;
  end loop;

  -- C. Pide otro producto admite los cuatro tipos de la ficha del lead.
  foreach tipo_sig in array array['llamada','whatsapp','reunion','tarea'] loop
    i := i + 1;
    sig := jsonb_build_object('tipo',tipo_sig,'titulo','Seguimiento '||tipo_sig,'vence_en',ts);
    if tipo_sig='reunion' then sig := sig || '{"modalidad_reunion":"virtual","duracion_min":30}'::jsonb; end if;
    v := crm.registrar_llamada_v4(gen_random_uuid(),l[i],'pide_otro_producto','credito',null,sig);
    if v->>'descartado' <> 'false' or not exists(
      select 1 from crm.tareas where id=(v->>'siguiente_id')::uuid and lead_id=l[i] and tipo=tipo_sig and estado='pendiente')
    then raise exception 'C: tipo %: %',tipo_sig,v; end if;
  end loop;

  -- D. Cerrar llamada pendiente y agendar en la misma operacion.
  v := crm.registrar_llamada_v4(gen_random_uuid(),l[6],'no_contesto',null,null,
    jsonb_build_object('tipo','llamada','titulo','Llamada que se cierra','vence_en',ts));
  tarea := (v->>'siguiente_id')::uuid;
  v2 := crm.registrar_llamada_v4(gen_random_uuid(),l[6],'no_interesado','otro',null,
    jsonb_build_object('tipo','tarea','titulo','Preparar informacion','vence_en',ts),tarea);
  if v2->>'descartado' <> 'false' or v2->>'siguiente_id' is null
     or (select estado from crm.tareas where id=tarea) <> 'completada'
     or (select metadata->>'resultado' from crm.actividades where id=(v2->>'actividad_id')::uuid) <> 'no_interesado'
  then raise exception 'D: cierre atomico %',v2; end if;
  -- El writer compartido sella comando y tarea: no se reinterpreta un cierre.
  begin
    perform crm.registrar_llamada_v4((v2->>'operacion_id')::uuid,l[6],'no_interesado','otro',null,
      jsonb_build_object('tipo','tarea','titulo','Preparar informacion','vence_en',ts),(v2->>'siguiente_id')::uuid);
    raise exception 'D: replay con otra tarea fue admitido';
  exception when unique_violation then null; end;
  begin
    perform crm.registrar_llamada_v4((v2->>'operacion_id')::uuid,l[6],'no_interesado','otro',null,
      jsonb_build_object('tipo','tarea','titulo','Preparar informacion','vence_en',ts));
    raise exception 'D: replay cambio cierre por actividad libre';
  exception when unique_violation then null; end;

  -- E. Descartar explicito conserva razon, cancelaciones y deshacer.
  op := gen_random_uuid();
  v := crm.registrar_llamada_v4(op,l[6],'no_interesado','sin_fondos_ahora',null,null,null,true);
  if v->>'descartado' <> 'true' or (select motivo_descarte from crm.leads where id=l[6]) <> 'sin_fondos'
     or exists(select 1 from crm.tareas where lead_id=l[6] and estado='pendiente') then raise exception 'E: %',v; end if;
  begin
    perform crm.registrar_llamada_v4(op,l[6],'no_interesado','sin_fondos_ahora',null,null,null,false);
    raise exception 'E: replay cambio descarte';
  exception when unique_violation then null; end;
  v2 := crm.deshacer_resultado_llamada(op);
  if v2->>'descarte_revertido' <> 'true' or v2->>'etapa' <> 'contactado' then raise exception 'E: deshacer %',v2; end if;

  -- F. Rechazos sin escrituras parciales, incluido el veto existente.
  op := gen_random_uuid();
  sig := jsonb_build_object('tipo','llamada','titulo','No debe nacer','vence_en',ts);
  foreach q in array array[
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'')',op,l[7]),
    format('crm.registrar_llamada_v4(%L,%L,''pide_otro_producto'',''sin_fondos_ahora'')',op,l[7]),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L,null,true)',op,l[7],sig),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L,null,false,true)',op,l[7],sig),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L)',op,l[1],sig),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L)',op,l[7],sig||'{"tipo":"fax"}'),
    format('crm.registrar_llamada_v4(%L,%L,''numero_errado'',null,null,%L)',op,l[7],sig||'{"tipo":"whatsapp"}'),
    format('crm.registrar_llamada_v4(%L,%L,''no_interesado'',''otro'',null,%L)',op,l[7],sig||jsonb_build_object('vence_en',now()-interval '1 day'))
  ] loop
    begin execute 'select '||q; raise exception 'F: acepto input invalido %',q;
    exception when invalid_parameter_value then null; end;
  end loop;
  if exists(select 1 from crm.actividades where id=op) then raise exception 'F: dejo actividad parcial'; end if;

  -- G. No insistir no implica descarte, pero bloquea una nueva proxima accion.
  v := crm.registrar_llamada_v4(gen_random_uuid(),l[7],'pide_otro_producto','prestamo',null,null,null,false,true);
  if v->>'descartado' <> 'false' or v->>'no_insista' <> 'true'
     or not exists(select 1 from crm.leads where id=l[7] and no_contactar and etapa='contactado')
  then raise exception 'G: %',v; end if;
  v2 := crm.cola_accion_v2_fn(200,'todas');
  if exists(select 1 from jsonb_array_elements(v2->'items') x where (x->>'lead_id')::uuid in(l[1],l[7])) then
    raise exception 'G: la cola recomienda contactar a un lead vetado'; end if;

  -- Una tarea interna no adopta las restricciones horarias de los contactos.
  v := crm.registrar_llamada_v4(gen_random_uuid(),l[11],'no_interesado','otro',null,
    jsonb_build_object('tipo','tarea','titulo','Revisar internamente','vence_en',(dia+time '22:00') at time zone 'America/Lima'));
  if v->>'siguiente_id' is null then raise exception 'G: rechazo tarea interna nocturna'; end if;
  v := crm.registrar_llamada_v4(gen_random_uuid(),l[12],'pide_otro_producto','otro');
  if v->>'descartado' <> 'false' or v->>'siguiente_id' is not null then raise exception 'G: solo registrar %',v; end if;

  -- H. V3 conserva semantica y reintentos. V4 no reinterpreta recibos previos.
  op_legacy := gen_random_uuid();
  v := crm.registrar_llamada_v3(op_legacy,l[8],'pide_otro_producto','credito');
  if v->>'descartado' <> 'true' then raise exception 'H: se rompio legacy %',v; end if;
  begin
    perform crm.registrar_llamada_v4(op_legacy,l[8],'pide_otro_producto','credito');
    raise exception 'H: v4 reinterpreto v3';
  exception when unique_violation then null; end;
  v2 := crm.registrar_llamada_v3(op_legacy,l[8],'pide_otro_producto','credito');
  if v2->>'replay' <> 'true' or v2->>'descartado' <> 'true' then raise exception 'H: no recupero legacy %',v2; end if;

  -- I. Lead ajeno o inexistente: mismo rechazo sin revelar existencia.
  foreach otro in array array[(select id from o_ajeno),gen_random_uuid()] loop
    begin
      perform crm.registrar_llamada_v4(gen_random_uuid(),otro,'no_contesto');
      raise exception 'I: permitio gestionar fuera de ambito';
    exception when insufficient_privilege then
      if sqlerrm <> 'Gestion no disponible en tu ambito' then raise exception 'I: mensaje distinto %',sqlerrm; end if;
    end;
  end loop;

  -- J. Supervisor registra, pero la agenda pertenece al analista.
  perform set_config('request.jwt.claim.sub',a.sup1::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a.sup1,'role','authenticated')::text,true);
  v := crm.registrar_llamada_v4(gen_random_uuid(),l[9],'no_interesado','otro');
  if v->>'ok' <> 'true' or v->>'siguiente_id' is not null or v->>'descartado' <> 'false' then raise exception 'J: %',v; end if;
  begin
    perform crm.registrar_llamada_v4(gen_random_uuid(),l[9],'pide_otro_producto','otro',null,sig);
    raise exception 'J: supervisor creo agenda de otro';
  exception when insufficient_privilege then null; end;

  -- K. Roles excluidos no heredan la puerta de escritura.
  for d in select * from o_denegados loop
    perform set_config('request.jwt.claim.sub',d.perfil_id::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',d.perfil_id,'role','authenticated')::text,true);
    begin
      perform crm.registrar_llamada_v4(gen_random_uuid(),l[10],'no_contesto');
      raise exception 'K: permitio rol %',d.rol_crm;
    exception when insufficient_privilege then null; end;
  end loop;
end;
$casos$;
reset role;
do $permisos$
declare r text;
begin
  foreach r in array array['anon','service_role'] loop
    if has_function_privilege(r,'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)','EXECUTE') then
      raise exception 'Puerta expuesta a %',r; end if;
  end loop;
  if has_function_privilege('authenticated','private.llamada_registrar_v4(uuid,uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)','EXECUTE')
  then raise exception 'Nucleo expuesto'; end if;
  perform private.assert_gestion_diaria();
end;
$permisos$;
rollback;
select 'RESULTADO_SEGUIMIENTO_V4_OK';
