-- Funciones internas de la conversión: no tienen EXECUTE para authenticated (llamarlas con ese rol
-- TUMBA el Postgres local), así que se llaman como postgres, que es como las usan sus llamadores:
--   · las *_sin_cartera_fn con los claims de gerencia (su gate pide un perfil del CRM);
--   · la alarma SIN claims (sesión de operador): con claims de usuario responde 42501.
begin;
create temp table foto_int(rpc text primary key, claims text, ok boolean, resultado jsonb) on commit drop;
insert into foto_int(rpc, claims) values
  ('crm.alarma_conversion_fn(''2026-09-01'')', ''),
  ('crm.conversion_mensual_sin_cartera_fn(''2026-09-01'')', '{"sub":"b0000000-0000-4000-8000-000000000003","role":"authenticated"}'),
  ('crm.cumplimiento_metas_sin_cartera_fn(''2026-09-01'')', '{"sub":"b0000000-0000-4000-8000-000000000003","role":"authenticated"}');
do $i$
declare r record; v_res jsonb;
begin
  for r in select rpc, claims from foto_int order by rpc loop
    perform set_config('request.jwt.claims', r.claims, true);
    begin
      execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from %s t', r.rpc) into v_res;
      update foto_int set ok = true, resultado = v_res where rpc = r.rpc;
    exception when others then
      update foto_int set ok = false, resultado = jsonb_build_object('sqlstate', sqlstate, 'mensaje', sqlerrm) where rpc = r.rpc;
    end;
  end loop;
  perform set_config('request.jwt.claims', '', true);
end $i$;
insert into ensayo.foto select :'etapa', 'interno', rpc, ok, resultado from foto_int;
commit;
