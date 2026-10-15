-- A puede recibir el catálogo nuevo sin exponerlo aún a pestañas anteriores.
select pg_temp.exigir(not exists(select 1 from jsonb_array_elements(
  private.ranking_origen_live(date_trunc('month',now() at time zone 'America/Lima')::date,
    'f6000000-0000-0000-0000-000000000001','[]')->'filas') f
  where f->>'origen'='formulario_3'), 'A: ranking vacío conserva catálogo conocido por el cliente previo');
savepoint alta_compatible;
set local role authenticated;
select set_config('request.jwt.claim.sub','f6000000-0000-0000-0000-000000000001',true);
do $$ begin
  begin
    perform crm.crear_lead_si_disponible('ALTA COMPATIBLE F3','985009999','formulario_3',1000,'PEN');
    raise exception 'FAIL: A admitió un origen manual desconocido por las pestañas previas';
  exception when insufficient_privilege then
    if sqlerrm not like 'Formulario 3 estará disponible%' then raise; end if;
  end;
end $$;
reset role;
select pg_temp.exigir(not exists(select 1 from crm.leads where telefono='+51985009999'),
  'A: alta manual F3 espera la activación, sin introducir datos que rompan pestañas anteriores');
select set_config('request.jwt.claim.sub','',true);
select crm.importar_lead_fn('{"nombre_completo":"IMPORTACION COMPATIBLE F3","telefono":"985009998","origen":"formulario_3","monto_estimado":1000,"moneda":"PEN"}');
select pg_temp.exigir((select count(*)=1 and bool_and(origen='formulario' and campania_origen='Formulario 3' and not alta_manual)
  from crm.leads where telefono='+51985009998'), 'A: importación canónica se persiste temporalmente con contrato legado');
rollback to savepoint alta_compatible;
