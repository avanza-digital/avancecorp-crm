-- Sólo banco sintético, con rollback. Las llamadas pasan por el escritor real;
-- las lecturas públicas se ejecutan con authenticated, como PostgREST.
begin;
set local statement_timeout='180s';
create temporary table g_actores as
select (select perfil_id from crm.equipo where rol_crm='vendedor' and activo limit 1) as vendedor,
  (select perfil_id from crm.equipo where rol_crm='supervisor' and activo limit 1) as supervisor,
  (select perfil_id from crm.equipo where rol_crm='gerencia' and activo limit 1) as gerencia;
create temporary table g_leads(n integer primary key,id uuid unique);
create temporary table g_respuestas(clave text primary key,valor jsonb);
create function pg_temp.comprobar(ok boolean,caso text) returns void language plpgsql as $f$
begin if ok is not true then raise exception 'FAIL GESTION_COLA: %',caso; end if; end $f$;
select pg_temp.comprobar(vendedor is not null and supervisor is not null and gerencia is not null,'actores disponibles') from g_actores;

-- Volumen real de la consulta: 530 leads, superior a ambos topes anteriores.
-- La cirugía es exclusiva del fixture y queda entera dentro del rollback.
alter table crm.leads disable trigger user;
alter table crm.actividades disable trigger user;
insert into g_leads select n,gen_random_uuid() from generate_series(1,531) n;
insert into crm.leads(id,nombre_completo,telefono,origen,etapa,monto_estimado,vendedor_id,creado_por,creado_en,tenencia_desde,sla_global_iniciado_en)
select l.id,'COLA SINTETICA '||l.n,'900'||lpad(l.n::text,6,'0'),'oficina','contactado',25000,
  case when l.n=531 then a.supervisor else a.vendedor end,a.gerencia,
  now()-interval '40 days'+l.n*interval '1 minute',now()-interval '40 days',now()-interval '40 days'
from g_leads l cross join g_actores a;
insert into crm.actividades(lead_id,tipo,detalle,creado_por,creado_en)
select l.id,'llamada_realizada','Conversación histórica sintética',
  case when l.n=531 then a.supervisor else a.vendedor end,now()-interval '38 days'+l.n*interval '1 minute'
from g_leads l cross join g_actores a;
alter table crm.actividades enable trigger user;
alter table crm.leads enable trigger user;
-- Completar el historial causal que normalmente crea el trigger de alta.
-- El escritor de llamadas y tareas mantiene todas sus guardas activas.
alter table crm.lead_sla_ciclos disable trigger user;
alter table crm.lead_sla_etapas disable trigger user;
insert into crm.lead_sla_ciclos(lead_id,ciclo_n,politica_id,iniciado_en,
  primera_gestion_limite_en,primer_contacto_limite_en,primera_gestion_en,primer_contacto_en)
select l.id,l.ciclo_actual,p.id,l.sla_global_iniciado_en,
  l.sla_global_iniciado_en+p.primera_gestion_minutos*interval '1 minute',
  l.sla_global_iniciado_en+p.primer_contacto_minutos*interval '1 minute',
  now()-interval '38 days'+g.n*interval '1 minute',now()-interval '38 days'+g.n*interval '1 minute'
from crm.leads l join g_leads g on g.id=l.id
join crm.sla_politicas p on p.id=private.sla_politica_vigente(l.sla_global_iniciado_en);
insert into crm.lead_sla_etapas(lead_id,ciclo_n,episodio_n,etapa,politica_id,iniciado_en,limite_en)
select l.id,l.ciclo_actual,1,l.etapa,p.id,l.sla_global_iniciado_en,
  l.sla_global_iniciado_en+e.maximo_minutos*interval '1 minute'
from crm.leads l join g_leads g on g.id=l.id
join crm.sla_politicas p on p.id=private.sla_politica_vigente(l.sla_global_iniciado_en)
join crm.sla_politica_etapas e on e.politica_id=p.id and e.etapa=l.etapa;
alter table crm.lead_sla_ciclos enable trigger user;
alter table crm.lead_sla_etapas enable trigger user;
grant select on g_actores,g_leads to authenticated;
grant select,insert,update on g_respuestas to authenticated;

select set_config('request.jwt.claim.sub',vendedor::text,true) is not null from g_actores;
set local role authenticated;
insert into g_respuestas values ('antes',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8));
select pg_temp.comprobar((valor->>'total')::integer=530,'cola completa superior a 500') from g_respuestas where clave='antes';
select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=1),'primero antes de gestionar') from g_respuestas where clave='antes';
insert into g_respuestas select 'llamada1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=1;
insert into g_respuestas values ('despues1',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8));
select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=2),'siguiente pendiente tras guardar') from g_respuestas where clave='despues1';
select pg_temp.comprobar((valor#>>'{totales,sin_conversacion,gestionados}')::integer=1,'una gestión confirmada') from g_respuestas where clave='despues1';
insert into g_respuestas select 'anclada1',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8,'lead:'||id) from g_leads where n=1;
select pg_temp.comprobar((valor->>'pagina')::integer=66 and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=1),
  'el gestionado está en la última página completa') from g_respuestas where clave='anclada1';
select pg_temp.comprobar(valor#>>'{items,1,ultima_gestion,resultado}'='no_contesto' and
  (valor#>>'{items,1,senal,dias_sin_conversacion}')::integer>=37,'resultado visible sin reiniciar conversación') from g_respuestas where clave='anclada1';
select 'GESTION_COLA_FIXTURE:'||valor::text from g_respuestas where clave='anclada1';
insert into g_respuestas select 'llamada2',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=2;
insert into g_respuestas select 'reintento1',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto') from g_leads where n=1;
insert into g_respuestas values ('ultima',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',66,8));
select pg_temp.comprobar(valor#>>'{items,0,lead_id}'=(select id::text from g_leads where n=2)
  and valor#>>'{items,1,lead_id}'=(select id::text from g_leads where n=1)
  and (valor#>>'{totales,sin_conversacion,gestionados}')::integer=2,'dos leads, tres llamadas; el último atendido queda último') from g_respuestas where clave='ultima';

-- Siguiente cruza el límite de la página y recorre todos los pendientes.
insert into g_respuestas select 'salto',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8,'lead:'||id) from g_leads where n=10;
select pg_temp.comprobar(valor->>'siguiente'='lead:'||(select id::text from g_leads where n=11),'siguiente entre páginas') from g_respuestas where clave='salto';

-- Una clave ajena no amplía el ámbito y no provoca una diferencia de error.
insert into g_respuestas select 'ajeno',crm.gestion_diaria_cola_trabajo_fn('todo',0,200,'lead:'||id) from g_leads where n=531;
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=531)),
  'ancla ajena nunca expone otra cartera') from g_respuestas where clave='ajeno';
-- Las denegaciones se comprueban en conexiones separadas en ensayar.mjs,
-- igual que las peticiones independientes de la API.

-- Programación futura válida escrita con el mismo comando que el formulario.
insert into g_respuestas select 'programada',crm.registrar_llamada_v4(gen_random_uuid(),id,'no_contesto',null,null,
  jsonb_build_object('tipo','llamada','titulo','Reintento sintético','vence_en',
    ((((now() at time zone 'America/Lima')::date+1)+time '10:00') at time zone 'America/Lima')))
from g_leads where n=3;
insert into g_respuestas select 'programada_hoy',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_leads where n=3;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=3)
  and f.value->>'estado_trabajo'='programado'),'reintento futuro fuera de pendientes') from g_respuestas where clave='programada_hoy';

select crm.deshacer_resultado_llamada((valor->>'actividad_id')::uuid)->>'ok' from g_respuestas where clave='llamada2';
insert into g_respuestas select 'deshecha',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_leads where n=2;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=2)
  and f.value->>'estado_trabajo'='pendiente' and f.value->'ultima_gestion'='null'::jsonb),'deshacer recalcula avance') from g_respuestas where clave='deshecha';
reset role;

-- Fronteras de Lima probadas sobre el proyector con reloj explícito privado.
insert into g_respuestas select 'manana',private.gestion_diaria_cola_filas(vendedor,'vendedor',
  ((((now() at time zone 'America/Lima')::date+1)+time '00:01') at time zone 'America/Lima')) from g_actores;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor) f where f.value->>'lead_id'=(select id::text from g_leads where n=1)
  and f.value->>'estado_trabajo'='pendiente' and f.value->'ultima_gestion'='null'::jsonb),'nuevo día reinicia la vuelta') from g_respuestas where clave='manana';
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor) f where f.value->>'lead_id'=(select id::text from g_leads where n=3)
  and f.value->>'estado_trabajo'='programado'),'medianoche no adelanta el compromiso') from g_respuestas where clave='manana';
insert into g_respuestas select 'vence',private.gestion_diaria_cola_filas(vendedor,'vendedor',
  ((((now() at time zone 'America/Lima')::date+1)+time '10:00') at time zone 'America/Lima')) from g_actores;
select pg_temp.comprobar(exists(select 1 from jsonb_array_elements(valor) f where f.value->>'lead_id'=(select id::text from g_leads where n=3)
  and f.value->>'estado_trabajo'='pendiente'),'compromiso recupera prioridad a su hora') from g_respuestas where clave='vence';

-- Cambio de tenencia: el nuevo responsable recibe trabajo pendiente.
alter table crm.leads disable trigger user;
update crm.leads set vendedor_id=(select supervisor from g_actores),tenencia_desde=clock_timestamp()
  where id=(select id from g_leads where n=1);
alter table crm.leads enable trigger user;
select set_config('request.jwt.claim.sub',supervisor::text,true) is not null from g_actores;
set local role authenticated;
insert into g_respuestas select 'reasignada',crm.gestion_diaria_cola_trabajo_fn('todo',0,8,'lead:'||id) from g_leads where n=1;
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(valor->'items') f where f.value->>'lead_id'=(select id::text from g_leads where n=1)
  and f.value->'ultima_gestion'<>'null'::jsonb),'no hereda el avance de otro analista') from g_respuestas where clave='reasignada';
reset role;

-- Exclusiones del ámbito y estados terminales no se rescatan como gestionados.
alter table crm.leads disable trigger user;
update crm.leads set activo=false where id=(select id from g_leads where n=4);
update crm.leads set no_contactar=true where id=(select id from g_leads where n=5);
update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=(select id from g_leads where n=6);
alter table crm.leads enable trigger user;
select set_config('request.jwt.claim.sub',vendedor::text,true) is not null from g_actores;
set local role authenticated;
insert into g_respuestas values ('exclusiones',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,200));
select pg_temp.comprobar(not exists(select 1 from jsonb_array_elements(valor->'items') f
  where f.value->>'lead_id' in (select id::text from g_leads where n in (1,4,5,6,531))),
  'reasignados, inactivos, no contactar, descartados y ajenos excluidos') from g_respuestas where clave='exclusiones';
reset role;
-- Estado final de una vuelta grande; fixture directo con rollback. El escritor
-- real v4 ya se ejerció arriba y no se modifica para simular el volumen.
alter table crm.actividades disable trigger user;
insert into crm.actividades(lead_id,tipo,detalle,creado_por,creado_en,metadata)
select l.id,'llamada_no_contestada','Cierre de vuelta sintético',a.vendedor,statement_timestamp(),
  jsonb_build_object('evento','resultado_llamada','resultado','no_contesto','etapa_anterior','contactado')
from g_leads l cross join g_actores a where l.n between 2 and 530;
alter table crm.actividades enable trigger user;
set local role authenticated;
insert into g_respuestas values ('completa',crm.gestion_diaria_cola_trabajo_fn('sin_conversacion',0,8));
select pg_temp.comprobar((valor->>'vuelta_completa')::boolean and valor->'elegido'='null'::jsonb
  and valor->'siguiente'='null'::jsonb and (valor#>>'{totales,sin_conversacion,pendientes}')::integer=0,
  'fin de vuelta sin volver a sugerir el primero') from g_respuestas where clave='completa';
reset role;

select pg_temp.comprobar(not has_function_privilege('anon','crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)','EXECUTE')
  and not has_function_privilege('service_role','crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)','EXECUTE'),'ACL cerrada');
select 'GESTION_DIARIA_COLA_OK: 530 leads, orden completo, reintentos, Lima, deshacer y permisos';
rollback;
