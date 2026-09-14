-- Banco exclusivo, esquema completo, dentro de BEGIN/ROLLBACK. Sin DDL de producción.
-- El ejecutor crea pg_temp.citas_base_anterior con la definición previa exacta
-- y aplica la candidata en la misma transacción antes de estas aserciones.
set local statement_timeout='180s';
create temporary table citas_base_ids as
select n,gen_random_uuid() as lead_id,gen_random_uuid() as tarea_id,
  (select id from public.perfiles where correo=case when n=8 then 'vend2.crm@demo.avancecorp.pe' else 'vend1.crm@demo.avancecorp.pe' end) as analista,
  (select id from public.perfiles where correo='vend2.crm@demo.avancecorp.pe') as otro
from generate_series(1,8) n;
do $$ begin assert (select bool_and(analista is not null and otro is not null) from citas_base_ids),'Falta la semilla sintética del banco'; end $$;
select set_config('request.jwt.claim.sub','',true);
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por,alta_manual)
select lead_id,'CITAS BASE SINTETICA '||n,'+51975'||lpad(n::text,6,'0'),'referido',10000,'PEN',analista,
  case when n=7 then otro else analista end,n in(6,7) from citas_base_ids;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por,modalidad_reunion,ubicacion_reunion)
select tarea_id,lead_id,'reunion','CITAS BASE SINTETICA',now()-interval '1 hour',analista,'presencial','Oficina de prueba'
from citas_base_ids where n in(1,6,7);
select set_config('request.jwt.claim.sub',(select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $$
declare r jsonb; viejo jsonb; normalizado jsonb; n integer; d date; g uuid;
begin
  d:=date_trunc('month',now() at time zone 'America/Lima')::date;
  g:=auth.uid();
  viejo:=pg_temp.citas_base_anterior(d,(d+interval '1 month - 1 day')::date);
  r:=crm.citas_gerencia_consulta_fn(d,(d+interval '1 month - 1 day')::date);
  assert r->'gestion'->>'citas_por_lead'='1.25','Meta interna 1,25';
  assert r->'gestion'->>'entrevistas_porcentaje'='70' and r->'gestion'->>'depositos_porcentaje'='70','Objetivos 70/70';
  assert r->'gestion'->>'actividad_manuales' is null,'No inventar la regla manual pendiente';
  select count(*) into n from jsonb_array_elements(r->'gestion'->'asignaciones') a join citas_base_ids m on m.lead_id=(a->>'lead_id')::uuid;
  assert n=8,'Incluye los ocho asignados, cinco de ellos sin cita';
  select count(*) into n from jsonb_array_elements(r->'gestion'->'asignaciones') a join citas_base_ids m on m.lead_id=(a->>'lead_id')::uuid where (a->>'manual_propio')::boolean;
  assert n=1,'Excluye sólo registro propio, no manual ajeno';
  assert exists(select 1 from jsonb_array_elements(r->'gestion'->'asignaciones') a join citas_base_ids m on m.lead_id=(a->>'lead_id')::uuid where m.n=8),'Analista con cero citas';
  select count(*) into n from jsonb_array_elements(r->'citas') a join citas_base_ids m on m.tarea_id=(a->>'id')::uuid where (a->>'manual_propio')::boolean;
  assert n=1,'La cita informa autoría manual propia';
  normalizado:=jsonb_set(r-'gestion','{citas}',(select jsonb_agg(c.valor-'manual_propio' order by c.orden) from jsonb_array_elements(r->'citas') with ordinality c(valor,orden)));
  assert normalizado=viejo,'Preserva todos los campos del contrato y embudo previos';
  assert not exists(select 1 from jsonb_array_elements(r->'gestion'->'asignaciones') a group by a->>'lead_id',a->>'analista_id' having count(*)>1),'No duplica persona/analista';
  assert not exists(select 1 from jsonb_array_elements(r->'gestion'->'asignaciones') a where (a->>'asignado_en')::timestamptz<d::timestamp at time zone 'America/Lima' or (a->>'asignado_en')::timestamptz>now()),'Mes y corte de asignación';
  perform set_config('request.jwt.claim.sub',(select otro::text from citas_base_ids limit 1),true);
  begin
    perform crm.citas_gerencia_consulta_fn(d,(d+interval '1 month - 1 day')::date);
    raise exception 'Un analista pudo consultar toda la base';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform crm.citas_gerencia_consulta_fn(d,(d+interval '1 month - 1 day')::date);
    raise exception 'Se consultó sin sesión';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',g::text,true);
  assert not has_function_privilege('anon','crm.citas_gerencia_consulta_fn(date,date)','execute'),'Anon sin RPC';
  assert not has_function_privilege('authenticated','private.citas_episodios(timestamptz,timestamptz,timestamptz,uuid[])','execute'),'Núcleo sin puerta directa';
  raise notice 'CITAS_BASE_ASIGNADA_PASS: meta 1,25, 70/70, base sin citas, manual propio/ajeno, paridad V2, corte y permisos.';
end $$;
-- El oráculo temporal también llama al núcleo; se retira antes del censo final.
drop function pg_temp.citas_base_anterior(date,date);
select private.assert_analitica_leads_citas();
