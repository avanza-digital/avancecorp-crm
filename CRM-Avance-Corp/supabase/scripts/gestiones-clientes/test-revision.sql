-- Hallazgos de la revisión, sobre el mismo banco sintético transaccional.
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000002';
set local role authenticated;
savepoint catalogos;
do $$
declare r jsonb; resultado text; tarea uuid; envio jsonb; datos jsonb; evento record;
  dia date:=(now() at time zone 'America/Lima')::date;
begin
  for r in select * from jsonb_array_elements((select valor->'llamadas' from pg_temp.catalogo_ui)) loop
    tarea:=gen_random_uuid();
    perform crm.postventa_agendar_fn(tarea,'10bfe922-e51a-40f5-9557-4a3436923c09',
      jsonb_build_object('tipo','llamada','titulo','Catálogo de llamada','vence_en',now()+interval '1 day'));
    datos:=jsonb_build_object('version',2,'estado','completada','resultado',r->>'resultado','detalle','Resultado del catálogo real');
    if r->>'resultado' in ('agendo_reunion','volver_a_llamar') then
      datos:=datos||jsonb_build_object('siguiente',jsonb_strip_nulls(jsonb_build_object(
        'tipo',case when r->>'resultado'='agendo_reunion' then 'reunion' else 'llamada' end,
        'titulo','Compromiso registrado','vence_en',now()+interval '1 day',
        'duracion_min',case when r->>'resultado'='agendo_reunion' then 30 end,
        'modalidad_reunion',case when r->>'resultado'='agendo_reunion' then 'virtual' end)));
    end if;
    envio:=crm.postventa_tarea_fn(gen_random_uuid(),tarea,1,'cerrar',datos);
    select * into strict evento from private.gestiones_clientes_eventos(dia,dia) e where e.metadata->>'tarea_id'=tarea::text;
    perform pg_temp.exigir(evento.tipo=r->>'tipo' and evento.metadata->>'resultado'=r->>'resultado',
      'cada resultado de llamada del formulario conserva su tipo y resultado');
    perform pg_temp.exigir(evento.contacto=(r->>'resultado' not in ('no_contesto','numero_errado','no_es_la_persona')),
      'contacto correcto para cada resultado');
  end loop;
  for resultado in select jsonb_array_elements_text((select valor->'entrevistas' from pg_temp.catalogo_ui)) loop
    envio:=pg_temp.cierre('reunion','completada',resultado);
    perform pg_temp.exigir(exists(select 1 from private.gestiones_clientes_eventos(dia,dia) e
      where e.metadata->>'tarea_id'=envio->'tarea'->>'id' and e.tipo='reunion_realizada'
        and e.operativa and e.metadata->>'resultado_reunion'=resultado),'cada resultado comercial del formulario se conserva');
  end loop;
  -- El writer anterior ya exigía detalle; ambos estados deben rechazar y no cerrar.
  tarea:=gen_random_uuid();
  perform crm.postventa_agendar_fn(tarea,'10bfe922-e51a-40f5-9557-4a3436923c09',
    jsonb_build_object('tipo','reunion','titulo','Detalle obligatorio','vence_en',now()+interval '1 day','duracion_min',30,'modalidad_reunion','virtual'));
  foreach resultado in array array['cancelada','no_show'] loop
    perform pg_temp.falla(format('select crm.postventa_tarea_fn(%L,%L,1,''cerrar'',%L)',gen_random_uuid(),tarea,
      jsonb_build_object('estado',resultado)), '22023');
  end loop;
  perform pg_temp.exigir((select t.estado='pendiente' from crm.tareas t where t.id=tarea),'rechazo de detalle sin cierre parcial');
end $$;
rollback to catalogos;
reset role;

-- Los tipos admitidos por el CHECK son todos representables por el frontend.
do $$
declare v_check text; v_tipo text;
begin
  select pg_get_constraintdef(oid) into strict v_check from pg_constraint
    where conrelid='crm.actividades_cliente'::regclass and conname='actividades_cliente_tipo_check';
  for v_tipo in select m[1] from regexp_matches(v_check,'''([^'']+)''::text','g') m loop
    perform pg_temp.exigir((select valor->'tipos_actividad' ? v_tipo from pg_temp.catalogo_ui),'tipo legado admitido en la UI: '||v_tipo);
  end loop;
end $$;

savepoint nombre_vacio;
-- Simula un registro histórico sin nombre; no cambia las reglas del writer.
alter table crm.leads disable trigger user;
update crm.leads set nombre_completo='' where id='cf000000-0000-4000-8000-000000000071';
alter table crm.leads enable trigger user;
set local role authenticated;
select pg_temp.exigir(exists(select 1 from jsonb_array_elements(crm.registro_actividad_v2_fn(
  (now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date,p_cartera=>'leads')->'items') e
  where e->>'lead_id'='cf000000-0000-4000-8000-000000000071' and e->>'sujeto_nombre'='Sin nombre' and e->>'lead_nombre'='Sin nombre'),
  'un nombre vacío no inutiliza toda la página ni cambia su identidad');
rollback to nombre_vacio;
reset role;

savepoint espejo_legacy;
select set_config('crm.op_privilegiada','on',true);
insert into crm.actividades_cliente(id,cliente_id,vendedor_id,tarea_id,tipo,detalle,creado_por)
values('cf000000-0000-4000-8000-000000000091','c0000000-0000-4000-8000-000000000002',
  'b0000000-0000-4000-8000-000000000002','cf000000-0000-4000-8000-000000000021','llamada_realizada',
  'Espejo sintético de cierre F6','b0000000-0000-4000-8000-000000000002');
select set_config('crm.op_privilegiada','off',true);
update crm.multiempresa_flags set activo=false where nombre='postventa_neutral';
set local role authenticated;
select pg_temp.exigir(not exists(select 1 from private.gestiones_clientes_eventos(
  (now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.id='cf000000-0000-4000-8000-000000000091' or e.origen='postventa'),
  'apagar F6 no expone sus cierres a través de un espejo legado');
select pg_temp.exigir(exists(select 1 from private.gestiones_clientes_eventos(
  (now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date) e
  where e.id='cf000000-0000-4000-8000-000000000051'),'F6 apagada conserva el evento auténtico del perfil');
rollback to espejo_legacy;
reset role;

savepoint conteos_sin_f5;
-- Si el resumen consulta F5, esta sonda hace fallar la prueba. Se revierte con el savepoint.
create function pg_temp.f5_prohibida() returns void language plpgsql as $$
begin raise exception 'No debe resolver identidad F5 en un conteo o página de leads'; end $$;
do $$
declare v_oid oid:='private.cartera_f5_personas_visibles()'::regprocedure; v_cuerpo text;
begin
  select prosrc into strict v_cuerpo from pg_proc where oid=v_oid;
  execute replace(pg_get_functiondef(v_oid),v_cuerpo,
    'select x.* from private.cartera_f5_personas_visibles(null::uuid) x cross join pg_temp.f5_prohibida()');
end $$;
set local role authenticated;
select pg_temp.exigir((select count(*)=0 from private.gestiones_clientes_identidades('[]')),'lista vacía no consulta F5');
select pg_temp.exigir(jsonb_array_length(crm.registro_actividad_v2_fn(
  (now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date,p_cartera=>'leads')->'items')>0,
  'página solo leads no consulta F5');
select pg_temp.exigir((crm.gestiones_resumen_fn((now() at time zone 'America/Lima')::date,
  (now() at time zone 'America/Lima')::date)->'totales'->'clientes'->>'entrevistas')::int=3,
  'resumen conserva las entrevistas sin resolver identidades');
select pg_temp.exigir(not exists(select 1 from private.gestiones_operativas_eventos(
  (now() at time zone 'America/Lima')::date,(now() at time zone 'America/Lima')::date,p_detalles=>false) e
  where e.identidad is not null or e.detalle is not null or e.metadata is not null or e.lead_id is not null),
  'ruta de conteo no devuelve datos privados de clientes o leads');
-- Control positivo: la sonda realmente bloquea cuando sí se pide identidad.
select pg_temp.falla($q$select * from private.gestiones_clientes_identidades('[{"persona":"10bfe922-e51a-40f5-9557-4a3436923c09"}]')$q$,'P0001');
rollback to conteos_sin_f5;
reset role;
select 'PASS: catálogo real UI→SQL, detalle legacy obligatorio, tipos CHECK, nombre vacío, deduplicación con F6 apagada y conteo sin PII/F5';
