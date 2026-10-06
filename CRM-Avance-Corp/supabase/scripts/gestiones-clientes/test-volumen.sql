-- Estrés local de historial: 90.000 eventos (30.000 por fuente), hasta 300 días.
-- No representa la distribución productiva de personas/roles. Todo se revierte.
savepoint volumen;
set local statement_timeout='45s';
set local request.jwt.claim.sub='b0000000-0000-4000-8000-000000000003';
set local role authenticated;
insert into pg_temp.contexto values('antes_volumen',crm.gestiones_resumen_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date));
reset role;
create temp table carga as select gen_random_uuid() id,i,
  now()-((i%least(300,greatest(1,current_date-date '2026-01-01')))||' days')::interval
    -(i||' microseconds')::interval instante from generate_series(1,30000) i;
-- Preparación masiva de fixtures: triggers reactivados antes de leer con authenticated.
alter table crm.tareas disable trigger user;
alter table crm.inversionista_gestiones disable trigger user;
alter table crm.actividades disable trigger user;
alter table crm.actividades_cliente disable trigger user;
insert into crm.tareas(id,tipo,titulo,vence_en,inversionista_id,vendedor_id,estado,postventa_revision,creado_en)
select id,'llamada','Carga sintética de historial',instante,'10bfe922-e51a-40f5-9557-4a3436923c09',
  'b0000000-0000-4000-8000-000000000002','completada',2,instante from carga;
insert into crm.inversionista_gestiones(inversionista_id,tarea_id,tipo,detalle,metadata,creado_por,creado_en)
select '10bfe922-e51a-40f5-9557-4a3436923c09',id,'cierre','Evento F6 de carga',
  '{"estado":"completada","tipo_tarea":"llamada","resultado":"pide_otro_producto"}',
  'b0000000-0000-4000-8000-000000000002',instante from carga;
insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por,creado_en)
select 'cf000000-0000-4000-8000-000000000071','llamada_realizada','Evento lead de carga','{}',
  'b0000000-0000-4000-8000-000000000002',instante from carga;
insert into crm.actividades_cliente(cliente_id,vendedor_id,tipo,detalle,creado_por,creado_en)
select 'c0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002',
  'llamada_no_contestada','Evento perfil de carga','b0000000-0000-4000-8000-000000000002',instante from carga;
alter table crm.tareas enable trigger user;
alter table crm.inversionista_gestiones enable trigger user;
alter table crm.actividades enable trigger user;
alter table crm.actividades_cliente enable trigger user;
analyze crm.tareas;
analyze crm.inversionista_gestiones;
analyze crm.actividades;
analyze crm.actividades_cliente;
set local role authenticated;
insert into pg_temp.contexto values('despues_volumen',crm.gestiones_resumen_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date));
select pg_temp.exigir((select (valor->'totales'->'total'->>'llamadas')::int from pg_temp.contexto where clave='despues_volumen')=
  90000+(select (valor->'totales'->'total'->>'llamadas')::int from pg_temp.contexto where clave='antes_volumen'),
  'el resumen cuenta los 90.000 eventos, sin truncarlos por el límite del Registro');
select pg_temp.exigir((select (valor->'totales'->'total'->>'contestadas')::int from pg_temp.contexto where clave='despues_volumen')=
  60000+(select (valor->'totales'->'total'->>'contestadas')::int from pg_temp.contexto where clave='antes_volumen'),
  '60.000 contactos y 30.000 intentos no contestados');
select 'PLAN: Registro mixto, primera página de 50 / 90.000 eventos';
explain(analyze,buffers) select crm.registro_actividad_v2_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date);
insert into pg_temp.contexto values('pagina_volumen',crm.registro_actividad_v2_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date));
select pg_temp.exigir(jsonb_array_length((select valor->'items' from pg_temp.contexto where clave='pagina_volumen'))=50,
  'Registro devuelve su límite exacto después de unir las fuentes');
select 'PLAN: Resumen completo de 90.000 eventos';
explain(analyze,buffers) select crm.gestiones_resumen_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date);
select 'PLAN: Citas sobre 30.000 tareas adicionales';
explain(analyze,buffers) select crm.citas_clientes_fn(
  (now() at time zone 'America/Lima')::date-365,(now() at time zone 'America/Lima')::date);
reset role;
rollback to volumen;
select 'PASS: 90.000 eventos sintéticos, conteos completos, página acotada, EXPLAIN con rol gerencia; carga revertida';
