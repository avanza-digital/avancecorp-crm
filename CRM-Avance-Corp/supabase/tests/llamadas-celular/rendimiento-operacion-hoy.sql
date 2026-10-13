\set ON_ERROR_STOP on
begin;
set local statement_timeout = '120s';
-- Solo banco local: datos sintéticos de rendimiento, descartados por ROLLBACK.
-- Los triggers se omiten únicamente durante la siembra masiva; la consulta se mide con ellos habilitados.
set local session_replication_role = replica;
create temp table f4e_actores as
select row_number() over () as n, vendedor_id as actor, id as lead, gen_random_uuid() as asignacion
from (select distinct on (l.vendedor_id) l.vendedor_id,l.id
      from crm.leads l join crm.equipo e on e.perfil_id=l.vendedor_id
      where l.activo and e.activo and e.rol_crm='vendedor'
      order by l.vendedor_id,l.id limit 3) x;
insert into crm.celulares_asignaciones(id,etiqueta,analista_id,credencial_hash)
select asignacion,'C'||(900+n),actor,md5(asignacion::text)||md5(actor::text) from f4e_actores;
create temp table f4e_historial as
select g.n, a.actor,a.lead,a.asignacion, gen_random_uuid() as evento,gen_random_uuid() as actividad,
       now() - make_interval(days => case when g.n%10=0 then g.n%30 else g.n%101 end) as fecha,
       g.n%10<>0 as enlazada, g.n%31=0 as deshecha
from generate_series(1,20000) g(n)
join f4e_actores a on a.n=1+(g.n % (select count(*) from f4e_actores));
insert into crm.llamadas_celular_eventos(id,asignacion_id,analista_id,evento_origen_id,numero_canonico,
 direccion,estado_tecnico,ocurrio_en,recibido_en,identificacion,atencion,lead_id,metodo_asociacion,asociado_en)
select evento,asignacion,actor,'C901-'||(floor(extract(epoch from fecha))::bigint+n)::text,'+51900000001','saliente','no_atendida',fecha,fecha,
 'identificado',case when enlazada then 'registrado' else 'requiere_resultado' end,lead,'exacto',fecha
from f4e_historial;
insert into crm.actividades(id,lead_id,tipo,metadata,creado_por,creado_en)
select actividad,lead,'llamada_no_contestada',jsonb_build_object('evento','resultado_llamada','resultado','no_contesto')
 ||case when deshecha then jsonb_build_object('deshecho_en',fecha) else '{}'::jsonb end,actor,fecha
from f4e_historial where enlazada;
insert into crm.llamadas_celular_enlaces(evento_id,actividad_id,lead_id,enlazado_por,via,creado_en,actualizado_en)
select evento,actividad,lead,actor,'pestana',fecha,fecha from f4e_historial where enlazada;
set local session_replication_role = origin;
analyze crm.llamadas_celular_eventos;
analyze crm.llamadas_celular_enlaces;
analyze crm.actividades;
select count(*) as eventos_sinteticos,count(*) filter(where enlazada) as enlazados,
       extract(day from max(fecha)-min(fecha)) as dias_historial from f4e_historial;
select set_config('request.jwt.claim.sub',(select id::text from auth.users where email='gerencia.crm@demo.avancecorp.pe'),true);
explain (analyze,buffers) select private.llamadas_celular_operacion_hoy(auth.uid(),null,statement_timestamp());
explain (analyze,buffers) select private.llamadas_celular_operacion_hoy(auth.uid(),null,statement_timestamp());
explain (analyze,buffers) select private.llamadas_celular_operacion_hoy(auth.uid(),null,statement_timestamp());
rollback;
