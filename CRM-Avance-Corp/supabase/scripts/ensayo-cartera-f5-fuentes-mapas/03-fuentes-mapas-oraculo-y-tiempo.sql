-- ENSAYO DESHECHO: cartera_f5_fuentes con canónica y analista atribuido calculados UNA vez por llamada (CTEs), no por fila.
do $x$
declare v_def text; v_n1 int; v_n2 int; v_n3 int; v_n4 int; v_ctes text;
  v_t0 timestamptz; v_ta numeric := 0; v_tb numeric := 0; v_i int; v_ma text; v_mb text; v_na int; v_nb int; v_fun text; v_ms numeric;
begin
  v_ctes := 'with recursive w as ( select i.id as origen, i.id, i.inversionista_canonico_id, 1 as n from crm.inversionistas i '
    || 'union all select w.origen, i.id, i.inversionista_canonico_id, w.n+1 from w join crm.inversionistas i on i.id = w.inversionista_canonico_id where w.n < 16 ), '
    || 'canon as ( select origen as id, coalesce((array_agg(id order by n desc) filter (where inversionista_canonico_id is null))[1], origen) as canon from w group by origen ), '
    || 'cad as ( select c.id as raiz, c.id as contrato_id, 0 as nivel, array[c.id] as visitados from public.contratos c '
    || 'union all select cd.raiz, o.contrato_origen_id, cd.nivel + 1, cd.visitados || o.contrato_origen_id from cad cd join crm.operaciones_cartera o on o.contrato_nuevo_id = cd.contrato_id '
    || 'where o.contrato_origen_id is not null and not (o.contrato_origen_id = any(cd.visitados)) and cd.nivel < 100 ), '
    || 'atrib as ( select distinct on (cd.raiz) cd.raiz, con.analista_cierre_id from cad cd join public.contratos con on con.id = cd.contrato_id where con.categoria = ''upgrade'' order by cd.raiz, cd.nivel asc ), '
    || 'canon_map as ( select coalesce(jsonb_object_agg(id::text, canon::text), ''{}''::jsonb) as m from canon ), '
    || 'atrib_map as ( select coalesce(jsonb_object_agg(raiz::text, analista_cierre_id::text), ''{}''::jsonb) as m from atrib ) ';
  v_def := pg_get_functiondef('private.cartera_f5_fuentes'::regproc);
  v_def := replace(v_def, 'FUNCTION private.cartera_f5_fuentes(', 'FUNCTION pg_temp.fuentes_b(');
  select count(*) into v_n1 from regexp_matches(v_def, '\$function\$\s*select c\.id,', 'g');
  v_def := regexp_replace(v_def, '(\$function\$\s*)(select c\.id,)', '\1' || replace(v_ctes, '\', '\\') || '\2');
  select count(*) into v_n2 from regexp_matches(v_def, 'private\.analista_atribuido_cadena\(c\.id\)', 'g');
  v_def := replace(v_def, 'private.analista_atribuido_cadena(c.id)', '(((select m from atrib_map)->>c.id::text)::uuid)');
  select count(*) into v_n3 from regexp_matches(v_def, 'private\.inversionista_canonica\(x\.id\)', 'g');
  v_def := replace(v_def, 'private.inversionista_canonica(x.id)', 'coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)');
  select count(*) into v_n4 from regexp_matches(v_def, 'pg_temp\.fuentes_b', 'g');
  if v_n1<>1 or v_n2<>1 or v_n3<>2 or v_n4<>1 then raise exception 'PATRONES inesperados: % % % %', v_n1, v_n2, v_n3, v_n4; end if;
  execute v_def;

  perform set_config('request.jwt.claims', json_build_object('sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','role','authenticated')::text, true);
  -- oráculo: mismas filas, mismo orden por texto
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into v_na, v_ma from private.cartera_f5_fuentes() f;
  select count(*), md5(string_agg(f::text, '|' order by f::text)) into v_nb, v_mb from pg_temp.fuentes_b() f;
  -- tiempos: 5 pasadas alternas tras calentar
  perform count(*) from private.cartera_f5_fuentes(); perform count(*) from pg_temp.fuentes_b();
  for v_i in 1..5 loop
    v_t0 := clock_timestamp(); perform count(*) from private.cartera_f5_fuentes(); v_ta := v_ta + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform count(*) from pg_temp.fuentes_b(); v_tb := v_tb + extract(epoch from clock_timestamp()-v_t0)*1000;
  end loop;
  set local track_functions = 'all';
  perform count(*) from pg_temp.fuentes_b();
  select string_agg(format('%s×%s=%sms', funcname, calls, round(total_time)), ' ' order by total_time desc) into v_fun
    from (select funcname, calls, total_time from pg_stat_xact_user_functions order by total_time desc limit 6) q;
  raise exception 'FUENTES|filas A=% B=% | md5 iguales=% | A media=% ms | B media=% ms | dentro de B: %', v_na, v_nb, (v_ma = v_mb), round(v_ta/5,1), round(v_tb/5,1), v_fun;
end $x$;
