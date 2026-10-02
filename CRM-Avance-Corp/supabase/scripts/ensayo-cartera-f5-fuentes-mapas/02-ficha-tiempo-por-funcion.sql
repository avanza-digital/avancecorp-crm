do $x$
declare v_id uuid := '5a0c033a-5ff1-445c-9feb-a8306e43bc52'; v_res text; v_t0 timestamptz; v_ms int; v_pv text; v_esc text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','role','authenticated')::text, true);
  v_pv := crm.postventa_estado_fn()->>'habilitada'; v_esc := crm.cartera_inversionistas_estado_fn()->>'escritura_habilitada';
  perform crm.inversionista_ficha_fn(v_id,1,1);  -- calentar
  set local track_functions = 'all';
  v_t0 := clock_timestamp();
  perform crm.inversionista_ficha_fn(v_id,1,1);
  v_ms := round(extract(epoch from clock_timestamp()-v_t0)*1000);
  select string_agg(format('%s×%s total=%s propio=%s', funcname, calls, round(total_time), round(self_time)), ' · ' order by total_time desc)
    into v_res from (select funcname, calls, total_time, self_time from pg_stat_xact_user_functions order by total_time desc limit 28) f;
  raise exception 'FUNCIONES|ficha=% ms postventa_habilitada=% escritura_habilitada=% · %', v_ms, v_pv, v_esc, v_res;
end $x$;
