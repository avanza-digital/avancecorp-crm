-- Banco aislado. Toda la prueba vive en la transacción revertida por banco.mjs.
set local search_path='';
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
begin if p_ok is distinct from true then raise exception 'FAIL: %',p_mensaje; end if; end $$;
create function pg_temp.falla(p_sql text,p_codigo text) returns void language plpgsql as $$
begin
  begin execute p_sql; exception when others then
    if sqlstate=p_codigo then return; end if;
    raise exception 'Se esperaba %, llegó %: %',p_codigo,sqlstate,sqlerrm;
  end;
  raise exception 'No rechazó: %',p_sql;
end $$;
create temp table contexto(clave text primary key,valor jsonb);
grant all on contexto to authenticated;
select pg_temp.exigir(not has_table_privilege('authenticated','crm.inversionista_gestiones','select'),'F6 sin SELECT directo');
select pg_temp.exigir(not has_function_privilege('anon','crm.registro_actividad_v2_fn(date,date,uuid[],text[],text,integer,timestamptz,uuid,text,text)','execute'),'anon sin registro v2');
select pg_temp.exigir((select md5(prosrc)='4fe2e158e6d359fcc25c64bc6624d2e5' from pg_proc where oid='crm.postventa_tarea_fn(uuid,uuid,integer,text,jsonb,uuid)'::regprocedure)=false,'cierre actualizado');
select pg_temp.exigir((select md5(prosrc)='acc79d8b6825fbea47f1ada6547cf1db' from pg_proc where oid='private.registro_actividad_core(timestamptz,timestamptz,uuid[],text[],text,integer,timestamptz,uuid)'::regprocedure),'registro captación intacto');
select set_config('crm.op_privilegiada','on',true);
insert into crm.inversionista_datos_contacto(inversionista_id,nombre_completo,actualizado_por)
values('0796d977-f342-4f35-bb8a-d3ad2e2f826c','CLIENTE SINTETICO GESTIONES','b0000000-0000-4000-8000-000000000002')
on conflict(inversionista_id) do update set nombre_completo=excluded.nombre_completo;
select set_config('crm.op_privilegiada','off',true);
set local role authenticated;
insert into pg_temp.contexto values('antes',crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date));

-- Llamada → cita, las tres escrituras atómicas, resultado obligatorio para v2.
insert into pg_temp.contexto values('agenda',crm.postventa_agendar_fn(
  'cf000000-0000-4000-8000-000000000001','0796d977-f342-4f35-bb8a-d3ad2e2f826c',
  jsonb_build_object('tipo','llamada','titulo','Llamar por renovación','vence_en',now()+interval '1 day')));
select pg_temp.falla($q$select crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000011','cf000000-0000-4000-8000-000000000001',1,'cerrar','{"version":2,"estado":"completada","detalle":"Gestión sin resultado"}')$q$,'22023');
select pg_temp.falla($q$select crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000011','cf000000-0000-4000-8000-000000000001',1,'cerrar','{"version":2,"estado":"completada","resultado":"agendo_reunion","detalle":"No se indicó la siguiente cita"}')$q$,'22023');
insert into pg_temp.contexto values('payload',jsonb_build_object('version',2,'estado','completada','resultado','agendo_reunion','detalle','Aceptó una entrevista para renovar',
  'siguiente',jsonb_build_object('tipo','reunion','titulo','Entrevista de renovación','vence_en',now()+interval '1 day','duracion_min',30,'modalidad_reunion','presencial','ubicacion_reunion','Oficina sintética')));
insert into pg_temp.contexto values('cerrada',crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000011','cf000000-0000-4000-8000-000000000001',1,'cerrar',(select valor from pg_temp.contexto where clave='payload')));
select pg_temp.exigir((select valor from pg_temp.contexto where clave='cerrada')=
  crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000011','cf000000-0000-4000-8000-000000000001',1,'cerrar',(select valor from pg_temp.contexto where clave='payload')),'replay idéntico, sin segunda cita');
select pg_temp.falla($q$select crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000099','cf000000-0000-4000-8000-000000000001',1,'cerrar','{"version":2,"estado":"completada","resultado":"no_contesto","detalle":"Otro cierre"}')$q$,'P0409');
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'llamadas')::int=
  1+(select (valor->'totales'->'clientes'->>'llamadas')::int from pg_temp.contexto where clave='antes'),'una llamada de cliente visible al autor');
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'contestadas')::int=
  1+(select (valor->'totales'->'clientes'->>'contestadas')::int from pg_temp.contexto where clave='antes'),'llamada contestada explícita');
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=0,'agendar no es asistir');

-- Confirmar mantiene pendiente y no suma entrevista; asistir sí.
insert into pg_temp.contexto values('confirmada',crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000012',
  (select (valor->'siguiente'->>'id')::uuid from pg_temp.contexto where clave='cerrada'),1,'confirmar','{}'));
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=0,'confirmar no es asistir');
insert into pg_temp.contexto values('entrevista',crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000013',
  (select (valor->'tarea'->>'id')::uuid from pg_temp.contexto where clave='confirmada'),
  (select (valor->'tarea'->>'postventa_revision')::int from pg_temp.contexto where clave='confirmada'),'cerrar',
  '{"version":2,"estado":"completada","resultado_reunion":"propuesta","detalle":"Se realizó y presentamos la propuesta de renovación"}'));
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=1,'asistencia registrada una sola vez');

-- Supervisor y gerencia leen el resultado y el cliente, el otro equipo no.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000001';
insert into pg_temp.contexto values('registro',crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date));
select pg_temp.exigir(exists(select 1 from jsonb_array_elements((select valor->'items' from pg_temp.contexto where clave='registro')) e
  where e->>'tipo'='reunion_realizada' and e->>'sujeto_tipo'='inversionista' and e->'metadata'->>'resultado_reunion'='propuesta'
    and e->>'sujeto_nombre'='BANCO CLIENTE A UNO' and e->>'creado_por'='b0000000-0000-4000-8000-000000000002'),'supervisor ve autor, ficha y resultado');
select pg_temp.exigir((crm.citas_clientes_fn((now() at time zone 'America/Lima')::date,((now()+interval '2 days') at time zone 'America/Lima')::date)->'resumen'->>'entrevistas')::int=1,'Citas refleja la entrevista');
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000011';
select pg_temp.exigir(jsonb_array_length(crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'items')=0,'otro supervisor sin registros');
select pg_temp.falla($q$select crm.gestiones_resumen_fn(current_date,current_date,array['b0000000-0000-4000-8000-000000000002'::uuid])$q$,'42501');
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000003';
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=1,'Gerencia ve la entrevista');

-- Redacción tras reasignar: el autor conserva el conteo, pierde identidad/detalle/enlace.
reset role;
select set_config('crm.op_privilegiada','on',true);
update crm.inversionistas set responsable_relacion_id='b0000000-0000-4000-8000-000000000013' where id='0796d977-f342-4f35-bb8a-d3ad2e2f826c';
select set_config('crm.op_privilegiada','off',true);
set local role authenticated;
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000001';
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=1,'reasignación no borra el trabajo');
select pg_temp.exigir(not exists(select 1 from jsonb_array_elements(crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'items') e
  where e->>'origen'='postventa' and (e->>'sujeto_id' is not null or e->>'inversionista_id' is not null or e->>'detalle' is not null or e->'metadata'->>'tarea_id' is not null)),'sin PII ni enlaces fuera de cartera');
reset role;
select pg_temp.exigir((select count(*)=1 from crm.inversionista_gestiones where tarea_id='cf000000-0000-4000-8000-000000000001' and tipo='cierre'),'idempotencia del historial');
select pg_temp.exigir((select bool_and(metadata->>'responsable_tarea_id'='b0000000-0000-4000-8000-000000000002') from crm.inversionista_gestiones where tarea_id='cf000000-0000-4000-8000-000000000001' and tipo='cierre'),'responsable al cerrar conservado');
select 'PASS: cierre, validación, idempotencia, confirmación, entrevista, supervisión y reasignación';
