-- Casos adicionales sobre el mismo fixture, después de la reasignación de la persona A.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
set local role authenticated;
create function pg_temp.cierre(p_tipo text,p_estado text,p_resultado text default null) returns jsonb language plpgsql as $$
declare v_clave uuid:=gen_random_uuid(); v_agenda jsonb; v_datos jsonb;
begin
  v_datos:=jsonb_build_object('tipo',p_tipo,'titulo','Ensayo de '||p_tipo,'vence_en',now()+interval '1 day');
  if p_tipo='reunion' then v_datos:=v_datos||'{"duracion_min":30,"modalidad_reunion":"presencial","ubicacion_reunion":"Oficina del banco"}'::jsonb; end if;
  v_agenda:=crm.postventa_agendar_fn(v_clave,'10bfe922-e51a-40f5-9557-4a3436923c09',v_datos);
  return crm.postventa_tarea_fn(gen_random_uuid(),v_clave,1,'cerrar',jsonb_strip_nulls(jsonb_build_object(
    'version',2,'estado',p_estado,'detalle','Resultado sintético para verificar las conexiones',
    case when p_tipo='reunion' then 'resultado_reunion' else 'resultado' end,p_resultado)));
end $$;
insert into pg_temp.contexto values('sin_respuesta',pg_temp.cierre('llamada','completada','no_contesto'));
insert into pg_temp.contexto values('whatsapp',pg_temp.cierre('whatsapp','completada','respondio'));
insert into pg_temp.contexto values('no_asistio',pg_temp.cierre('reunion','no_show'));
insert into pg_temp.contexto values('cancelada',pg_temp.cierre('reunion','cancelada'));
insert into pg_temp.contexto values('otra_entrevista',pg_temp.cierre('reunion','completada','seguimiento'));
insert into pg_temp.contexto values('tercera_entrevista',pg_temp.cierre('reunion','completada','interesado'));
select pg_temp.exigir(exists(select 1 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.metadata->>'tarea_id'=(select valor->'tarea'->>'id' from pg_temp.contexto where clave='sin_respuesta') and e.tipo='llamada_no_contestada' and e.contacto is not true),'no contestó es intento sin contacto');
select pg_temp.exigir((select count(*)=2 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.metadata->>'estado' in ('no_show','cancelada') and not e.operativa),'no_show y cancelación no simulan una gestión realizada');
select pg_temp.exigir((select count(*)=3 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e where e.tipo='reunion_realizada'),'dos asistencias a la misma persona son dos entrevistas');

-- Bundle anterior: sin resultado, recibo estable y nunca se inventa contacto.
select crm.postventa_agendar_fn('cf000000-0000-4000-8000-000000000021','10bfe922-e51a-40f5-9557-4a3436923c09',
  jsonb_build_object('tipo','llamada','titulo','Cierre del bundle anterior','vence_en',now()+interval '1 day'));
insert into pg_temp.contexto values('legacy',crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000022','cf000000-0000-4000-8000-000000000021',1,'cerrar','{"estado":"completada","detalle":"Detalle antiguo sin clasificación"}'));
select pg_temp.exigir((select valor from pg_temp.contexto where clave='legacy')=crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000022','cf000000-0000-4000-8000-000000000021',1,'cerrar','{"estado":"completada","detalle":"Detalle antiguo sin clasificación"}'),'recibo del bundle anterior idéntico');
select pg_temp.exigir(exists(select 1 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.metadata->>'tarea_id'='cf000000-0000-4000-8000-000000000021' and e.metadata->>'resultado'='sin_resultado' and e.contacto is not true),'histórico sin resultado no afirma que contestó');

-- Reprogramar mueve el compromiso, sin asistencia ni evento operativo ficticio.
insert into pg_temp.contexto values('por_reprogramar',crm.postventa_agendar_fn('cf000000-0000-4000-8000-000000000031','10bfe922-e51a-40f5-9557-4a3436923c09',
  jsonb_build_object('tipo','reunion','titulo','Reprogramar entrevista','vence_en',now()+interval '1 day','duracion_min',30,'modalidad_reunion','presencial','ubicacion_reunion','Oficina')));
insert into pg_temp.contexto values('reprogramada',crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000032','cf000000-0000-4000-8000-000000000031',1,'reprogramar',jsonb_build_object('detalle','Pidió otro horario','vence_en',now()+interval '2 days')));
select pg_temp.exigir((select valor->'tarea'->>'estado'='reprogramada' and valor->'siguiente'->>'estado'='pendiente' from pg_temp.contexto where clave='reprogramada'),'original reprogramada y nueva pendiente');
select pg_temp.exigir(not exists(select 1 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e where e.metadata->>'tarea_id'='cf000000-0000-4000-8000-000000000031'),'reprogramar no simula llamada ni entrevista');

-- Un superior registra su propia ejecución sin atribuírsela al dueño de tarea.
select crm.postventa_agendar_fn('cf000000-0000-4000-8000-000000000041','10bfe922-e51a-40f5-9557-4a3436923c09',
  jsonb_build_object('tipo','llamada','titulo','La cierra supervisión','vence_en',now()+interval '1 day'));
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000001';
select crm.postventa_tarea_fn('cf000000-0000-4000-8000-000000000042','cf000000-0000-4000-8000-000000000041',1,'cerrar','{"version":2,"estado":"completada","resultado":"pide_otro_producto","detalle":"Supervisor atendió al cliente"}');
select pg_temp.exigir(exists(select 1 from private.gestiones_clientes_eventos((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.metadata->>'tarea_id'='cf000000-0000-4000-8000-000000000041' and e.creado_por=auth.uid()),'superior es el autor de su propia llamada');
reset role;
select pg_temp.exigir(exists(select 1 from crm.inversionista_gestiones where tarea_id='cf000000-0000-4000-8000-000000000041' and tipo='cierre'
  and creado_por='b0000000-0000-4000-8000-000000000001' and metadata->>'responsable_tarea_id'='b0000000-0000-4000-8000-000000000002'),'autor y responsable del momento son independientes');

-- Un perfil heredado sigue enlazando su ficha, sin fabricar un lead.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
select set_config('crm.op_privilegiada','on',true);
insert into crm.actividades_cliente(id,cliente_id,vendedor_id,tipo,detalle,creado_por,creado_en)
values('cf000000-0000-4000-8000-000000000051','c0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','llamada_realizada','Contacto del cliente heredado','b0000000-0000-4000-8000-000000000002',now());
-- Mismo timestamp e id en fuentes diferentes: el cursor usa origen además del uuid.
insert into crm.actividades_cliente(id,cliente_id,vendedor_id,tipo,detalle,creado_por,creado_en)
select id,'c0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','llamada_no_contestada','Intento legado','b0000000-0000-4000-8000-000000000002',creado_en
from crm.inversionista_gestiones where tarea_id='cf000000-0000-4000-8000-000000000021' and tipo='cierre';
select set_config('crm.op_privilegiada','off',true);
set local role authenticated;
select pg_temp.exigir(exists(select 1 from jsonb_array_elements(crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'items') e
  where e->>'origen'='perfil' and e->>'sujeto_id'='c0000000-0000-4000-8000-000000000002' and e->>'lead_id' is null and (e->>'identidad_visible')::boolean),'perfil heredado conserva sujeto y no fabrica lead');
do $$
declare v_p jsonb; v_c jsonb; v_claves text[]:='{}'; v_todas text[];
begin
  loop
    v_p:=crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date,
      p_limite=>1,p_antes_de=>(v_c->>'creado_en')::timestamptz,p_antes_id=>(v_c->>'id')::uuid,p_antes_origen=>v_c->>'origen');
    exit when jsonb_array_length(v_p->'items')=0;
    v_c:=v_p->'items'->0;
    perform pg_temp.exigir(not ((v_c->>'origen')||':'||(v_c->>'id')=any(v_claves)),'sin repeticiones al paginar');
    v_claves:=array_append(v_claves,(v_c->>'origen')||':'||(v_c->>'id'));
    if cardinality(v_claves)>40 then raise exception 'Cursor sin fin'; end if;
  end loop;
  select array_agg((e->>'origen')||':'||(e->>'id') order by n) into v_todas from jsonb_array_elements(
    crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date)->'items') with ordinality x(e,n);
  perform pg_temp.exigir(v_claves=v_todas,'paginación idéntica al registro, incluidos empates entre fuentes');
end $$;
select pg_temp.falla($q$select crm.registro_actividad_v2_fn(current_date,current_date,p_antes_de=>now())$q$,'22023');
select pg_temp.falla($q$select crm.citas_clientes_fn(current_date,current_date,p_limite=>0)$q$,'22023');
select pg_temp.exigir(not exists(select 1 from jsonb_array_elements(crm.registro_actividad_v2_fn((now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date,p_etapa=>'nuevo')->'items') e where e->>'origen'<>'lead'),'filtro de etapa excluye clientes');

-- El cliente del portal no es analista aunque use el rol autenticado.
set local request.jwt.claim.sub='c0000000-0000-4000-8000-000000000002';
select pg_temp.falla($q$select crm.registro_actividad_v2_fn(current_date,current_date)$q$,'42501');
select pg_temp.falla($q$select private.gestiones_clientes_eventos(current_date,current_date)$q$,'42501');
select pg_temp.falla($q$select private.gestion_cliente_identidad('10bfe922-e51a-40f5-9557-4a3436923c09',null)$q$,'42501');
reset role;
select 'PASS: no respuesta, WhatsApp, no-show, cancelación, asistencias repetidas, legacy, reprogramación, autoría, perfil, cursor y denegaciones';
