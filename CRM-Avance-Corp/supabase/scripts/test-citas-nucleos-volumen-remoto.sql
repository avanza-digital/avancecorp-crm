-- Carga sintética aislada dentro de una transacción; no desactiva triggers,
-- claves ni restricciones. El runner impide cualquier conexión a producción.
begin;
set local statement_timeout='180s';
-- Semilla por writer interno: conserva creado_en = now() en esta transacción.
-- Los permisos y el sello humano se verifican por HTTP, en peticiones sucesivas.
select set_config('request.jwt.claim.sub','',true);
create temporary table citas_volumen_meta as
select gen_random_uuid() lead_id,id analista from public.perfiles where correo='vend1.crm@demo.avancecorp.pe';
insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por)
select lead_id,'CITAS VOLUMEN SINTETICO','+51987319991','referido',10000,'PEN',analista,analista from citas_volumen_meta;
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por,modalidad_reunion,ubicacion_reunion)
select gen_random_uuid(),m.lead_id,'reunion','CITAS VOLUMEN '||n,
  timestamptz '2026-04-15 15:00+00' + n*interval '1 second',m.analista,'presencial','Oficina de prueba'
from citas_volumen_meta m cross join generate_series(1,10000) n;
select set_config('request.jwt.claim.sub',
  (select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $$ declare r jsonb; inicio timestamptz; begin
  inicio:=clock_timestamp();
  r:=private.citas_gerencia_consulta('2026-04-01','2026-04-30');
  assert jsonb_array_length(r->'citas')=10000,'Se entregan las 10.000 filas completas';
  assert (select count(distinct x->>'id') from jsonb_array_elements(r->'citas') x)=10000,'Sin duplicados';
  raise notice 'PASS 10000 completas; consulta % ms, % bytes',
    round(extract(epoch from clock_timestamp()-inicio)*1000),octet_length(r::text);
end $$;
-- Semilla por writer interno: conserva creado_en = now() en esta transacción.
-- Los permisos y el sello humano se verifican por HTTP, en peticiones sucesivas.
select set_config('request.jwt.claim.sub','',true);
insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,creado_por,modalidad_reunion,ubicacion_reunion)
select gen_random_uuid(),lead_id,'reunion','CITAS VOLUMEN 10001','2026-04-16 15:00+00',analista,'presencial','Oficina de prueba' from citas_volumen_meta;
select set_config('request.jwt.claim.sub',
  (select id::text from public.perfiles where correo='gerencia.crm@demo.avancecorp.pe'),true);
do $$ begin
  begin
    perform private.citas_gerencia_consulta('2026-04-01','2026-04-30');
    raise exception 'Se aceptó o truncó silenciosamente el historial de 10001 citas';
  exception when program_limit_exceeded then
    assert sqlerrm like 'La consulta supera el tamaño admitido%','Rechazo explícito por tamaño';
  end;
  raise notice 'PASS 10001 rechazada sin entregar un subconjunto';
end $$;
rollback;
