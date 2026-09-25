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
with informes as materialized (
 select n as periodo,crm.gestion_diaria_habitos_fn(null,n) as j
 from (values(7),(14),(30)) t(n)
), personas as materialized (
 select i.periodo,i.j,p as persona from informes i cross join lateral jsonb_array_elements(i.j->'personas') p
), dias as materialized (
 select p.periodo,p.j,(p.persona->>'analista_id')::uuid as analista_id,d as datos
 from personas p cross join lateral jsonb_array_elements(p.persona->'dias') d
), contraste as materialized (
 select d.periodo,
  (d.datos->>'llamadas')::bigint=c.total
   and (d.datos->>'utiles')::bigint=c.utiles
   and (d.datos->>'contestadas')::bigint=c.contestadas as recuentos,
  (d.datos->>'primera_llamada_en')::timestamptz is not distinct from c.primera as primera,
  (d.datos->>'ultima_llamada_en')::timestamptz is not distinct from c.ultima as ultima,
  (d.datos->>'tasa_contacto')::numeric is not distinct from round(100.0*c.contestadas/nullif(c.utiles,0),1) as tasa,
  (d.datos#>>'{jornada,hueco,desde}')::timestamptz is not distinct from h.anterior
   and (d.datos#>>'{jornada,hueco,hasta}')::timestamptz is not distinct from h.creado_en
   and (d.datos#>>'{jornada,hueco,minutos}')::numeric is not distinct from round(extract(epoch from(h.creado_en-h.anterior))/60,1) as hueco
 from dias d
 cross join lateral (
  select count(*) as total,
   count(*) filter(where coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as utiles,
   count(*) filter(where a.tipo='llamada_realizada' and coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as contestadas,
   min(a.creado_en) as primera,max(a.creado_en) as ultima
  from crm.actividades a where a.creado_por=d.analista_id
   and a.tipo in ('llamada_realizada','llamada_no_contestada')
   and a.creado_en>=(d.datos->>'dia')::date::timestamp at time zone 'America/Lima'
   and a.creado_en<((d.datos->>'dia')::date+1)::timestamp at time zone 'America/Lima'
 ) c
 left join lateral (
  select x.* from (
   select a.id,a.creado_en,lag(a.creado_en) over(order by a.creado_en,a.id) as anterior
   from crm.actividades a where a.creado_por=d.analista_id
    and a.tipo in ('llamada_realizada','llamada_no_contestada')
    and a.creado_en>=(d.datos#>>'{jornada,inicio}')::timestamptz
    and a.creado_en<(d.datos#>>'{jornada,observado_hasta}')::timestamptz
  ) x where x.anterior is not null
  order by x.creado_en-x.anterior desc,x.anterior,x.creado_en,x.id limit 1
 ) h on true
), globales as materialized (
 select i.periodo,i.j,
  (i.j#>>'{operacion,llamadas}')::bigint=c.total
   and (i.j#>>'{operacion,utiles}')::bigint=c.utiles
   and (i.j#>>'{operacion,contestadas}')::bigint=c.contestadas
   and (i.j#>>'{operacion,tasa_contacto}')::numeric is not distinct from round(100.0*c.contestadas/nullif(c.utiles,0),1) as operacion,
  c.total,c.utiles,c.contestadas
 from informes i cross join lateral (
  select count(*) as total,
   count(*) filter(where coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as utiles,
   count(*) filter(where a.tipo='llamada_realizada' and coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona')) as contestadas
  from crm.actividades a where a.tipo in ('llamada_realizada','llamada_no_contestada')
   and a.creado_en>=(i.j->>'desde')::date::timestamp at time zone 'America/Lima'
   and a.creado_en<((i.j->>'hasta')::date+1)::timestamp at time zone 'America/Lima'
 ) c
), pruebas as (
 select g.periodo,g.j->>'desde' as desde,g.j->>'hasta' as hasta,
  jsonb_array_length(g.j->'personas') as personas,
  (select count(*) from contraste c where c.periodo=g.periodo) as personas_dias,
  jsonb_build_object('operacion',g.operacion,
   'recuentos_diarios',(select bool_and(c.recuentos) from contraste c where c.periodo=g.periodo),
   'primeras_llamadas',(select bool_and(c.primera) from contraste c where c.periodo=g.periodo),
   'ultimas_llamadas',(select bool_and(c.ultima) from contraste c where c.periodo=g.periodo),
   'tasas_diarias',(select bool_and(c.tasa) from contraste c where c.periodo=g.periodo),
   'huecos_entre_llamadas',(select bool_and(c.hueco) from contraste c where c.periodo=g.periodo),
   'umbral_apagado',g.j->'umbral_tasa_baja'='null'::jsonb,
   'periodo',(g.j->>'dias_incluidos')::integer=g.periodo,
   'solo_lectura',current_setting('transaction_read_only')='on') as checks,
  jsonb_build_object('llamadas',g.total,'utiles',g.utiles,'contestadas',g.contestadas) as originales
 from globales g
)
select jsonb_build_object('estado',case when bool_and((select bool_and(value='true'::jsonb) from jsonb_each(p.checks))) then 'PASS' else 'FAIL' end,
 'fecha',statement_timestamp(),'periodos',jsonb_agg(to_jsonb(p) order by p.periodo),
 'alcance','7/14/30 días. RPC frente a actividades originales por persona/día y total; primera/última llamada, tasa y mayor intervalo dentro de jornada, una sentencia READ ONLY.',
 'limite','No revalida en esta sonda la asignación jerárquica ni todas las reglas históricas de cortes; cubiertas por matrices y auditoría F4.') as evidencia from pruebas p;
rollback;
