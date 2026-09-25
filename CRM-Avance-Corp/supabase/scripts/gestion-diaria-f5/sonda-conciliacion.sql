-- Sólo lectura, después de instalar F5. No reconoce ni presenta avisos.
-- Día Lima actual por defecto. Para otro día, fijar app.gd_auditoria_dia
-- en esta conexión antes de ejecutar el archivo (formato YYYY-MM-DD).
-- Las cifras crudas y la RPC se consultan en UNA sentencia/snapshot.
begin transaction isolation level read committed read only;
set local statement_timeout = '90s';
set local lock_timeout = '5s';
set local timezone = 'America/Lima';
do $identidad$
declare actor uuid;
begin
  perform private.assert_gestion_diaria_pulso();
  select e.perfil_id into actor from crm.equipo e
    where private.rol_crm(e.perfil_id) = 'gerencia' order by e.perfil_id limit 1;
  if actor is null then raise exception 'No hay gerencia efectiva para la auditoría'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  execute 'set local role authenticated';
end $identidad$;
with configuracion as materialized (
  select coalesce(nullif(current_setting('app.gd_auditoria_dia',true),''),
    (statement_timestamp() at time zone 'America/Lima')::date::text)::date as dia
), ventana as materialized (
  select dia,dia::timestamp at time zone 'America/Lima' as desde,
    (dia+1)::timestamp at time zone 'America/Lima' as hasta from configuracion
), respuesta as materialized (
  select crm.gestion_diaria_pulso_fn(dia) as j from configuracion
), llamadas as materialized (
  select count(*) as llamadas,
    count(*) filter(where coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as utiles,
    count(*) filter(where a.tipo='llamada_realizada'
      and coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as contestadas,
    count(distinct a.lead_id) as leads_unicos
  from crm.actividades a cross join ventana v
  where a.tipo in ('llamada_realizada','llamada_no_contestada')
    and a.creado_en>=v.desde and a.creado_en<v.hasta
), citas as materialized (
  select count(*) as citas_agendadas from crm.tareas t cross join ventana v
  where t.tipo='reunion' and t.creado_en>=v.desde and t.creado_en<v.hasta
), pendientes as materialized (
  select count(*) as vencidas from crm.tareas t
  where t.activo and t.estado='pendiente' and t.vence_en<statement_timestamp()
), equipos as materialized (
  select coalesce(sum((e#>>'{metricas,llamadas}')::bigint),0) as llamadas,
    coalesce(sum((e#>>'{metricas,utiles}')::bigint),0) as utiles,
    coalesce(sum((e#>>'{metricas,contestadas}')::bigint),0) as contestadas,
    coalesce(sum((e#>>'{metricas,citas_agendadas}')::bigint),0) as citas,
    coalesce(sum((e->>'tareas_vencidas')::bigint),0) as vencidas
  from respuesta r cross join lateral jsonb_array_elements(r.j->'equipos') e
), controles as (
  select jsonb_build_object(
    'llamadas',(r.j#>>'{actual,llamadas}')::bigint=l.llamadas,
    'utiles',(r.j#>>'{actual,utiles}')::bigint=l.utiles,
    'contestadas',(r.j#>>'{actual,contestadas}')::bigint=l.contestadas,
    'leads_unicos',(r.j#>>'{actual,leads_unicos}')::bigint=l.leads_unicos,
    'citas',(r.j#>>'{actual,citas_agendadas}')::bigint=c.citas_agendadas,
    'tasa_contacto',(r.j#>>'{actual,tasa_contacto}')::numeric is not distinct from
      round(100.0*l.contestadas/nullif(l.utiles,0),1),
    'llamadas_por_lead',(r.j#>>'{actual,llamadas_por_lead}')::numeric is not distinct from
      round(l.llamadas::numeric/nullif(l.leads_unicos,0),2),
    'pendientes_actuales',(r.j->>'vencidas_global')::bigint=p.vencidas,
    'cuadre_equipos',e.llamadas=l.llamadas and e.utiles=l.utiles
      and e.contestadas=l.contestadas and e.citas=c.citas_agendadas and e.vencidas=p.vencidas,
    'fecha',r.j->>'dia'=v.dia::text,
    'solo_lectura',current_setting('transaction_read_only')='on'
  ) as checks,
  jsonb_build_object('llamadas',l.llamadas,'utiles',l.utiles,'contestadas',l.contestadas,
    'leads_unicos',l.leads_unicos,'citas_agendadas',c.citas_agendadas,'vencidas_actuales',p.vencidas) as crudos,
  r.j->'actual' as tablero,v.dia,r.j->'generado_en' as generado_en
  from respuesta r cross join ventana v cross join llamadas l cross join citas c
    cross join pendientes p cross join equipos e
)
select jsonb_build_object(
  'estado',case when (select bool_and(value='true'::jsonb) from jsonb_each(c.checks)) then 'PASS' else 'FAIL' end,
  'dia',c.dia,'generado_en',c.generado_en,'checks',c.checks,'originales',c.crudos,'tablero',c.tablero,
  'alcance','Recuentos globales, tasas y suma de equipos frente a actividades y tareas originales bajo gerencia; una sentencia READ COMMITTED y READ ONLY.',
  'limite','No sustituye las pruebas de comparación histórica, hábitos, navegación ni permisos negativos.'
) as evidencia from controles c;
rollback;
