-- REQ-GER-MET-001, punto 5. Sólo banco aislado con las funciones reales
-- y los dobles de catálogo/capital declarados en la nota de auditoría.
-- No es una migración ni una nueva fuente de métricas para la aplicación.
\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() !~ '^crm_llegadas_'
     or inet_server_addr() is not null
     or current_setting('listen_addresses') <> ''
     or current_setting('data_directory') !~ '^/tmp/avancecorp-gerencia\.[A-Za-z0-9]+/data$'
     or to_regclass('private.capital_stub') is null then
    raise exception 'Requiere banco temporal aislado, sin TCP y con doble de capital';
  end if;
end $$;
set local plpgsql.check_asserts = on;
truncate crm.tareas, crm.leads, crm.lead_asignaciones, crm.operaciones_cartera,
  crm.equipo, public.perfiles, private.anulados_stub, private.capital_stub;
insert into public.perfiles(id,nombre_completo) values
 ('10000000-0000-4000-8000-000000000001','Ana'),
 ('10000000-0000-4000-8000-000000000002','Luis'),
 ('10000000-0000-4000-8000-000000000006','Supervisor fuera del roster'),
 ('10000000-0000-4000-8000-000000000004','Gerencia');
insert into crm.equipo(perfil_id,rol_crm)
select id,case when nombre_completo='Gerencia' then 'gerencia'
               when nombre_completo='Supervisor fuera del roster' then 'supervisor'
               else 'vendedor' end
from public.perfiles;
insert into crm.leads(id,creado_en,origen,etapa,perfil_id,moneda)
select ('20000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n=1 then '2026-09-01 08:00-05'::timestamptz
      else '2026-09-02 12:00-05'::timestamptz end,
 'landing','convertido',
 ('30000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n=1 then 'PEN' else 'USD' end from generate_series(1,2) n;
-- Dos leads de agosto cierran exactamente en fronteras Lima de septiembre;
-- no pertenecen al lote N1, sí a N4 cuando su fecha de cierre entra al rango.
insert into crm.leads(id,creado_en,origen,etapa,perfil_id,moneda)
values
 ('20000000-0000-4000-8000-000000000003','2026-08-30 08:00-05',
  'referido','convertido','30000000-0000-4000-8000-000000000003','PEN'),
 ('20000000-0000-4000-8000-000000000004','2026-08-20 08:00-05',
  'landing','convertido','30000000-0000-4000-8000-000000000004','PEN'),
 -- Avance comercial real sin cita completada: N1 no puede inferir asistencia.
 ('20000000-0000-4000-8000-000000000005','2026-09-02 14:00-05',
  'landing','propuesta_enviada','30000000-0000-4000-8000-000000000005','PEN');
insert into crm.lead_asignaciones(lead_id,analista_id,origen,asignado_en,resultado,resultado_en)
select id,'10000000-0000-4000-8000-000000000001',origen,creado_en,
 case when id='20000000-0000-4000-8000-000000000001' then 'convertido' end,
 case when id='20000000-0000-4000-8000-000000000001'
      then '2026-09-03 15:00-05'::timestamptz end
from crm.leads;
-- El segundo lead llegó primero a Ana, pero lo cerró Luis: N1 debe quedar en
-- la primera analista y N4 en el autor real del cierre.
insert into crm.lead_asignaciones(
 lead_id,analista_id,origen,asignado_en,resultado,resultado_en)
values (
 '20000000-0000-4000-8000-000000000002',
 '10000000-0000-4000-8000-000000000002','landing','2026-09-02 13:00-05',
 'convertido','2026-09-03 23:30-05');
insert into crm.lead_asignaciones(
 lead_id,analista_id,origen,asignado_en,resultado,resultado_en)
values
 ('20000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000001','referido','2026-08-30 08:00-05',
  'convertido','2026-09-04 00:00-05'),
 ('20000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000006','landing','2026-08-21 08:00-05',
  'convertido','2026-08-23 00:00-05');
-- Tres operaciones elegibles, pero el núcleo selecciona sólo la primera por
-- cliente/mes: renovación del cliente 1 y upgrade del cliente 2.
insert into crm.operaciones_cartera(
 id,cliente_id,vendedor_id,tipo,fecha_operacion,periodo,moneda,
 capital_renovado,capital_adicional,elegible_conversion,creado_por,creado_en)
values
 ('50000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','renovacion','2026-09-02',
  '2026-09-01','PEN',100,null,true,
  '10000000-0000-4000-8000-000000000001','2026-09-02 09:00-05'),
 ('50000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','upgrade','2026-09-03',
  '2026-09-01','PEN',null,25,true,
  '10000000-0000-4000-8000-000000000001','2026-09-03 09:00-05'),
 ('50000000-0000-4000-8000-000000000003',
  '30000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001','upgrade','2026-09-03',
  '2026-09-01','USD',null,20,true,
  '10000000-0000-4000-8000-000000000001','2026-09-03 10:00-05');
insert into crm.tareas(id,lead_id,vendedor_id,tipo,estado,vence_en,
 modalidad_reunion,cancelada_por,cancelada_por_id,activo)
select ('40000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
 case when n in (3,14) then '20000000-0000-4000-8000-000000000002'::uuid
      else '20000000-0000-4000-8000-000000000001'::uuid end,
 '10000000-0000-4000-8000-000000000001',
 case when n=13 then 'llamada' else 'reunion' end,
 case when n in (1,2,3,12,13,14) then 'completada' when n=4 then 'no_show'
      when n in (5,6,7,11) then 'cancelada' when n=8 then 'reprogramada'
      else 'pendiente' end,
 case when n in (2,3) then '2026-09-02 10:00-05'::timestamptz
      when n in (10,11) then '2026-09-03 10:00-05'::timestamptz
      when n=14 then '2026-09-04 00:00-05'::timestamptz
      else '2026-09-01 10:00-05'::timestamptz end,
 case when n=2 then 'presencial' else 'virtual' end,
 case when n in (5,6) then 'asesor' when n=7 then 'sistema' end,
 case when n=6 then '10000000-0000-4000-8000-000000000002'::uuid
      when n=5 then '10000000-0000-4000-8000-000000000001'::uuid end,
 n<>12 from generate_series(1,14) n;
-- Hechos ya clasificados de dinero: ambos clientes tienen PEN y USD.
-- Este doble comprueba el consumo del agregador; NO audita el núcleo de capital.
insert into private.capital_stub(tipo,medida,cliente_id,moneda,monto,fecha)
values
 ('contrato_real','stock','30000000-0000-4000-8000-000000000001','PEN',100,'2026-09-03 15:00-05'),
 ('contrato_real','stock','30000000-0000-4000-8000-000000000001','USD',7,'2026-09-03 15:00-05'),
 ('contrato_real','stock','30000000-0000-4000-8000-000000000002','USD',20,'2026-09-03 15:00-05'),
 ('contrato_real','stock','30000000-0000-4000-8000-000000000002','PEN',9,'2026-09-03 15:00-05');
set local test.uid='10000000-0000-4000-8000-000000000004';
do $$ declare r record; j jsonb; m jsonb; c jsonb; o jsonb; s jsonb; begin
 select count(*) n, count(*) filter(where debio_ocurrir) debidas,
  count(*) filter(where realizada) realizadas, count(*) filter(where no_show) no_show,
  count(*) filter(where cancelada_asesor) asesor, count(*) filter(where cancelada_sistema) sistema,
  count(*) filter(where reprogramada) reprogramadas,
  count(*) filter(where pendiente_cierre) pendientes,
  count(*) filter(where programada_futura) futuras
 into r from private.citas_episodios('2026-09-01 00:00-05','2026-09-04 00:00-05','2026-09-02 12:00-05');
 assert row(r.n,r.debidas,r.realizadas,r.no_show,r.asesor,r.sistema,r.reprogramadas,r.pendientes,r.futuras)
  is not distinct from row(11::bigint,9::bigint,3::bigint,1::bigint,2::bigint,2::bigint,1::bigint,1::bigint,1::bigint),
  'Estados, cancelada nula, exclusión de inactivas/no reuniones o frontera Lima incorrectos';
 j:=crm.metricas_reuniones_fn('2026-09-01','2026-09-03');
 assert (j#>>'{resumen,pactadas}')::int is not distinct from 11;
 assert (j#>>'{resumen,pct_realizacion}')::numeric is not distinct from 37.5;
 assert (j#>>'{resumen,pct_asistencia}')::numeric is not distinct from 75.0;
 assert (j#>>'{responsables,0,pct_realizacion}')::numeric is not distinct from 42.9,
  'Cancelación ajena conserva el divisor propio del responsable';
 assert (j#>>'{conversion,leads_reunidos}')::int is not distinct from 2,
  'Tres eventos de dos personas no son tres personas';
 assert (j#>>'{conversion,contratos}')::int is not distinct from 2;
 assert (j#>>'{conversion,capital_pen}')::numeric is not distinct from 100
    and (j#>>'{conversion,capital_usd}')::numeric is not distinct from 20,
  'Semántica vigente: stock en moneda del lead, contado una vez en última cita';
 select value into m from jsonb_array_elements(j->'modalidades') where value->>'modalidad'='virtual';
 assert (m->>'debieron_ocurrir')::int is not distinct from 10
    and (m->>'realizadas')::int is not distinct from 2
    and (m->>'pct_realizacion')::numeric is not distinct from 28.6,
  'El bruto no es el divisor: 2/7=28.6%, no 2/10';
 assert (m->>'divisor_realizacion')::int is not distinct from 7
    and (m->>'canceladas_sistema_vencidas')::int is not distinct from 2
    and (m->>'reprogramadas_vencidas')::int is not distinct from 1,
  'N2 debe exponer el divisor 7 y sus exclusiones 2+1, sin recalcular el porcentaje';

 j:=crm.metricas_conversiones_fn('2026-09-01','2026-09-03',null);
 c:=j->'citas_reales';
 assert c->>'unidad' is not distinct from 'lead_id'
    and c->>'base' is not distinct from 'llegadas_unicas'
    and c->>'fecha_cita' is not distinct from 'vence_en'
    and (c->>'leads_base')::int is not distinct from 3
    and (c->>'leads_con_cita_real')::int is not distinct from 2
    and (c->>'citas_realizadas')::int is not distinct from 3
    and (c->>'citas_anteriores_al_alta')::int is not distinct from 1
    and (c->>'pct_llegadas_con_cita_real')::numeric is not distinct from 66.7,
  'N1 debe contar tres lead_id, no inferir cita del avance y excluir el evento anterior al alta';
 assert exists (
   select 1 from jsonb_array_elements(j->'origenes') x
   where x->>'origen'='landing'
     and (x->>'leads_con_cita_real')::int=2
     and (x->>'citas_realizadas')::int=3
 ) and exists (
   select 1 from jsonb_array_elements(j->'responsables') x
   where x->>'vendedor_id'='10000000-0000-4000-8000-000000000001'
     and (x->>'leads_con_cita_real')::int=2
     and (x->>'citas_realizadas')::int=3
 ), 'N1 debe conservar origen y primer analista en sus desgloses';

 o:=j->'conversion_operaciones';
 assert o->>'lectura' is not distinct from 'viva'
    and (o->>'completo')::boolean
    and o->>'desde' is not distinct from '2026-09-01'
    and o->>'hasta' is not distinct from '2026-09-03'
    and (o->>'cantidad')::int is not distinct from 2
    and (o->>'aporte_total')::numeric is not distinct from 1.15
    and jsonb_array_length(o->'detalle') is not distinct from 2,
  'N3 debe transportar exactamente las dos operaciones elegidas por el núcleo';
 assert exists (
   select 1 from jsonb_array_elements(o->'detalle') d
   where d->>'operacion_id'='50000000-0000-4000-8000-000000000001'
     and d->>'analista_id'='10000000-0000-4000-8000-000000000001'
     and d->>'categoria'='renovacion'
     and d->>'periodo'='2026-09-01'
     and (d->>'fecha_numerador')::timestamptz='2026-09-02 00:00-05'::timestamptz
     and (d->>'aporte_numerador')::numeric=0.15
 ) and exists (
   select 1 from jsonb_array_elements(o->'detalle') d
   where d->>'operacion_id'='50000000-0000-4000-8000-000000000003'
     and d->>'analista_id'='10000000-0000-4000-8000-000000000001'
     and d->>'categoria'='upgrade'
     and d->>'periodo'='2026-09-01'
     and (d->>'fecha_numerador')::timestamptz='2026-09-03 00:00-05'::timestamptz
     and (d->>'aporte_numerador')::numeric=1
 ) and not exists (
   select 1 from jsonb_array_elements(o->'detalle') d
   where d->>'operacion_id'='50000000-0000-4000-8000-000000000002'
 ), 'N3 no puede volver a elegir operaciones ni incluir la segunda del cliente/mes';

 s:=j->'cierres_por_semana';
 assert s->>'desde' is not distinct from '2026-09-01'
    and s->>'hasta' is not distinct from '2026-09-03'
    and s->>'base' is not distinct from 'fecha_numerador'
    and s->>'atribucion' is not distinct from 'autor_cierre'
    and not (s->>'incluye_operaciones_cartera')::boolean
    and (s->>'cierres')::int is not distinct from 2
    and (s->>'aporte_cierres')::numeric is not distinct from 2
    and (s->>'cierres_fuera_del_roster')::int is not distinct from 0
    and (s->>'aporte_cierres_fuera_del_roster')::numeric is not distinct from 0
    and jsonb_array_length(s->'semanas') is not distinct from 1
    and (s#>>'{semanas,0,cierres}')::int is not distinct from 2
    and (s#>>'{semanas,0,cierres_fuera_del_roster}')::int is not distinct from 0,
  'N4 debe agrupar los dos cierres por su fecha real, sin mezclar cartera';
 assert exists (
   select 1 from jsonb_array_elements(j->'responsables') x
   where x->>'vendedor_id'='10000000-0000-4000-8000-000000000001'
     and (x#>>'{cierres_por_semana,0,cierres}')::int=1
 ) and exists (
   select 1 from jsonb_array_elements(j->'responsables') x
   where x->>'vendedor_id'='10000000-0000-4000-8000-000000000002'
     and (x#>>'{cierres_por_semana,0,cierres}')::int=1
 ), 'N4 debe atribuir cada cierre a quien lo consiguió, no a quien recibió el lead';

 -- El ranking cliente/mes ocurre antes del filtro: al recortar el día 2, la
 -- segunda operación del cliente 1 no puede ascender. El cierre 23:30 Lima ya
 -- es 04:30 UTC del día siguiente, pero pertenece al 3 de septiembre comercial.
 j:=crm.metricas_conversiones_fn('2026-09-03','2026-09-03',null);
 o:=j->'conversion_operaciones';
 assert (o->>'cantidad')::int is not distinct from 1
    and jsonb_array_length(o->'detalle') is not distinct from 1
    and o#>>'{detalle,0,operacion_id}' is not distinct from
      '50000000-0000-4000-8000-000000000003'
    and not exists (
      select 1 from jsonb_array_elements(o->'detalle') d
      where d->>'operacion_id'='50000000-0000-4000-8000-000000000002'
    ), 'N3 no debe promover la segunda operación al recortar el rango';
 assert (j#>>'{cierres_por_semana,cierres}')::int is not distinct from 2,
   'N4 debe ubicar el cierre 23:30 por su día America/Lima, no por el día UTC';

 -- El filtro de origen recorta el lote y los cierres; Cartera permanece global
 -- porque una operación no tiene origen de lead que se pueda inventar.
 j:=crm.metricas_conversiones_fn('2026-09-01','2026-09-03','referido');
 assert (j#>>'{citas_reales,leads_base}')::int is not distinct from 0
    and (j#>>'{citas_reales,leads_con_cita_real}')::int is not distinct from 0
    and j#>'{citas_reales,pct_llegadas_con_cita_real}'='null'::jsonb,
  'N1 con lote vacío conserva cero real y porcentaje sin base';
 assert (j->'conversion_operaciones') ? 'origen_filtrado'
    and j#>'{conversion_operaciones,origen_filtrado}'='null'::jsonb
    and (j#>>'{conversion_operaciones,cantidad}')::int is not distinct from 2,
  'N3 debe declarar que su mapa completo de Cartera es global';
 assert j#>>'{cierres_por_semana,origen_filtrado}' is not distinct from 'referido'
    and (j#>>'{cierres_por_semana,cierres}')::int is not distinct from 0
    and (j#>>'{cierres_por_semana,semanas,0,cierres}')::int is not distinct from 0,
  'N4 debe respetar el origen sin convertir vacío en ausencia';

 j:=crm.metricas_conversiones_fn('2026-08-15','2026-09-04',null);
 s:=j->'cierres_por_semana';
 assert jsonb_array_length(s->'semanas') is not distinct from 3
    and s#>>'{semanas,0,desde}' is not distinct from '2026-08-15'
    and s#>>'{semanas,0,hasta}' is not distinct from '2026-08-21'
    and (s#>>'{semanas,0,cierres}')::int is not distinct from 0
    and s#>>'{semanas,1,desde}' is not distinct from '2026-08-22'
    and s#>>'{semanas,1,hasta}' is not distinct from '2026-08-28'
    and (s#>>'{semanas,1,cierres}')::int is not distinct from 1
    and (s#>>'{semanas,1,cierres_fuera_del_roster}')::int is not distinct from 1
    and (s#>>'{semanas,1,aporte_cierres_fuera_del_roster}')::numeric is not distinct from 1
    and s#>>'{semanas,2,desde}' is not distinct from '2026-08-29'
    and s#>>'{semanas,2,hasta}' is not distinct from '2026-09-04'
    and (s#>>'{semanas,2,cierres}')::int is not distinct from 3
    and (s#>>'{semanas,2,aporte_cierres}')::numeric is not distinct from 2.15
    and (s->>'cierres')::int is not distinct from 4
    and (s->>'aporte_cierres')::numeric is not distinct from 3.15
    and (s->>'cierres_fuera_del_roster')::int is not distinct from 1
    and (s->>'aporte_cierres_fuera_del_roster')::numeric is not distinct from 1,
  'N4 debe separar cantidad/aporte, respetar medianoches Lima y construir todos los bloques';

 j:=crm.metricas_reuniones_fn('2026-08-01','2026-08-03');
 assert (j#>>'{resumen,pactadas}')::int is not distinct from 0
    and j#>'{resumen,pct_realizacion}'='null'::jsonb,
  'Sin citas no equivale a un porcentaje de cero';
 raise notice 'OK: N1-N4, estados, personas/eventos, porcentajes, selección, cierres, monedas y vacío';
end $$;
set local role authenticated;
do $$ declare j jsonb; begin
 j:=crm.metricas_reuniones_fn('2026-09-01','2026-09-03');
 assert (j#>>'{resumen,realizadas}')::int is not distinct from 3;
 j:=crm.metricas_conversiones_fn('2026-09-01','2026-09-03',null);
 assert (j#>>'{citas_reales,leads_con_cita_real}')::int is not distinct from 2
    and (j#>>'{conversion_operaciones,cantidad}')::int is not distinct from 2
    and (j#>>'{cierres_por_semana,cierres}')::int is not distinct from 2;
 begin
  perform private.citas_episodios('2026-09-01','2026-09-04',now());
  raise exception 'Un navegador obtuvo acceso directo al núcleo privado';
 exception when insufficient_privilege then null; end;
 perform set_config('test.uid','10000000-0000-4000-8000-000000000001',true);
 begin
  perform crm.metricas_reuniones_fn('2026-09-01','2026-09-03');
  raise exception 'Un vendedor obtuvo el reporte global';
 exception when insufficient_privilege then null; end;
 begin
  perform crm.metricas_conversiones_fn('2026-09-01','2026-09-03',null);
  raise exception 'Un vendedor obtuvo el reporte de conversión global';
 exception when insufficient_privilege then null; end;
 perform set_config('test.uid','',true);
 begin
  perform crm.metricas_reuniones_fn('2026-09-01','2026-09-03');
  raise exception 'El reporte funcionó sin identidad';
 exception when insufficient_privilege then null; end;
 begin
  perform crm.metricas_conversiones_fn('2026-09-01','2026-09-03',null);
  raise exception 'El reporte de conversión funcionó sin identidad';
 exception when insufficient_privilege then null; end;
 raise notice 'OK: fachada para Gerencia, núcleo cerrado, vendedor y sin identidad denegados';
end $$;
reset role;
rollback;
