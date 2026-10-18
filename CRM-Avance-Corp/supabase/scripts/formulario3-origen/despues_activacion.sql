select pg_temp.exigir((select count(*)=5 from crm.leads where origen='formulario_3'),
 'B: solo los cinco F3 legados cambian de origen, incluido inactivo y veto');
select pg_temp.exigir((select vendedor_id='f6000000-0000-0000-0000-000000000001'::uuid from crm.leads
 where id='f6100000-0000-0000-0000-000000000004'), 'B: conserva analista vigente');
select pg_temp.exigir((select bool_and(origen='formulario') from crm.lead_asignaciones
 where lead_id='f6100000-0000-0000-0000-000000000004'), 'B: ledger físico no reescrito');
select pg_temp.exigir(private.origen_episodio_lead('formulario','formulario_3')='formulario_3'
 and private.origen_episodio_lead('landing','formulario_3')='landing', 'proyección limitada al origen legado');

-- El productor actual sigue activo: el mismo canal legado entra canónico.
set local role service_role;
create temporary table _recibos as select crm.importar_lead_fn(jsonb_build_object(
 'nombre_completo','Importación sintética F3','telefono','985000099','origen','formulario',
 'campania_origen','Formulario 3','monto_estimado',5000,'moneda','PEN',
 'consentimiento_en',now(),'consentimiento_fuente','Prueba local')) as recibo;
select pg_temp.exigir((select recibo->>'resultado'='importado' from _recibos),'n8n legado recibe alta confirmada');
reset role;
select pg_temp.exigir((select origen='formulario_3' and not alta_manual and vendedor_id is null
 from crm.leads where id=(select (recibo->>'lead_id')::uuid from _recibos)), 'n8n queda canónico, automático y en cola');
set local role service_role;
select pg_temp.exigir(crm.importar_lead_fn(jsonb_build_object(
 'nombre_completo','Importación sintética F3','telefono','985000099','origen','formulario_3',
 'campania_origen','Formulario 3','monto_estimado',5000,'moneda','PEN')) ->>'resultado'='duplicado',
 'reintento con canal nuevo no crea otro contacto');
reset role;
select pg_temp.exigir(private.datos_solicitud_comparables('{"canal":"formulario_3","capital":5000}'::jsonb)
 ='{"canal":"formulario","campania_origen":"Formulario 3","capital":5000}'::jsonb,
 'huella del canal nuevo equivale a la legada');
select pg_temp.exigir(private.datos_solicitud_comparables('{"canal":"landing","capital":5000}'::jsonb)
 ='{"canal":"landing","capital":5000}'::jsonb,'huellas de otros orígenes no cambian');
select pg_temp.exigir(private.normalizar_campania_origen(null,'formulario_3')='Formulario 3', 'canal F3 sin campaña explícita');
do $$ begin
  begin perform private.normalizar_campania_origen('"Otra"','formulario_3');
    raise exception 'FAIL: campaña incompatible aceptada'; exception when sqlstate '22023' then null; end;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000006',true);
select pg_temp.exigir((select count(*)=2 from crm.leads_por_repartir() where origen='formulario_3'),
 'cola canónica excluye asignados, inactivos y no contactar');
do $agenda$
declare d jsonb := crm.agenda_reparto_diaria((now() at time zone 'America/Lima')::date,1)#>'{dias,0}';
 a jsonb; g jsonb; n integer; fuera integer;
begin
  perform pg_temp.exigir(jsonb_array_length(d->'asignaciones')=2,'agenda conserva exactamente dos turnos');
  for a in select * from jsonb_array_elements(d->'asignaciones') loop
    select coalesce(sum((o->>'derivados')::int),0),coalesce(sum((o->>'fuera_turno')::int),0)
    into n,fuera from jsonb_array_elements(d->'origenes') o where o->>'turno'=a->>'origen';
    perform pg_temp.exigir(n=(a->>'derivados')::int and fuera=(a->>'fuera_turno')::int,
      'tabla por origen concilia con cada turno');
  end loop;
  select o into g from jsonb_array_elements(d->'origenes') o where o->>'origen'='formulario_3';
  perform pg_temp.exigir(g->>'turno'='formulario' and (g->>'derivados')::int=2,'F3 separado en tabla, mismo turno');
  select o into g from jsonb_array_elements(d->'origenes') o where o->>'origen'='referido';
  perform pg_temp.exigir(g->'turno'='null'::jsonb and g->'fuera_turno'='null'::jsonb,'origen sin turno visible sin inventar incumplimiento');
end $agenda$;
do $turno$ begin
  begin perform crm.repartir_lead('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: F3 aceptó otra supervisora con turno estricto'; exception when sqlstate '22023' then null; end;
  perform crm.repartir_lead('f6100000-0000-0000-0000-000000000001','f6000000-0000-0000-0000-000000000003');
  perform pg_temp.exigir(not exists(select 1 from crm.leads_por_repartir() where id='f6100000-0000-0000-0000-000000000001'),
    'reparto F3 confirmado sale de la cola');
  begin perform crm.guardar_agenda_reparto_diaria((now() at time zone 'America/Lima')::date,
    'f6000000-0000-0000-0000-000000000003','f6000000-0000-0000-0000-000000000005');
    raise exception 'FAIL: turno F3 entregado pudo cambiar'; exception when sqlstate '22023' then null; end;
end $turno$;
select pg_temp.exigir((crm.conversion_divisor_coordinacion_fn()#>>'{empresa,divisor_formulario_3}')::int=6,
 'RPC de conversión cuenta F3 una vez con peso de llegada Formulario');
select pg_temp.exigir((crm.conversion_divisor_coordinacion_fn()#>>'{empresa,divisor_formulario}')::int=1,
 'RPC de conversión mantiene Formulario separado');

do $permisos$ declare actor uuid; begin
  foreach actor in array array[
    'f6000000-0000-0000-0000-000000000001'::uuid,
    'f6000000-0000-0000-0000-000000000003'::uuid,
    'f6000000-0000-0000-0000-000000000007'::uuid,
    'f6000000-0000-0000-0000-000000000008'::uuid
  ] loop
    perform set_config('request.jwt.claim.sub',actor::text,true);
    begin perform crm.leads_por_repartir(); raise exception 'FAIL: cola autorizó %',actor;
    exception when insufficient_privilege then null; end;
    begin perform crm.agenda_reparto_diaria(current_date,1); raise exception 'FAIL: agenda autorizó %',actor;
    exception when insufficient_privilege then null; end;
    begin perform crm.conversion_divisor_coordinacion_fn(); raise exception 'FAIL: conversión autorizó %',actor;
    exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'PASS: vendedor, supervisor, gerencia inactiva y directorio no acceden a Coordinación';
end $permisos$;
reset role;
select set_config('request.jwt.claim.sub','',true);
select pg_temp.exigir(not has_function_privilege('anon','crm.leads_por_repartir()','EXECUTE')
 and not has_function_privilege('authenticated','private.origen_turno_reparto(text)','EXECUTE')
 and not has_function_privilege('authenticated','crm.importar_lead_fn(jsonb)','EXECUTE'),
 'ACL: anon sin cola, helpers privados, importador fuera de sesión humana');
