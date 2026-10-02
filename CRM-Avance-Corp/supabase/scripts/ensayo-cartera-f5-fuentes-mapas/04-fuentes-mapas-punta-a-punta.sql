-- ENSAYO DESHECHO: cartera_f5_fuentes con canónica y analista atribuido calculados UNA vez por llamada (CTEs), no por fila.
do $x$
declare v_def text; v_ids uuid[]; v_id uuid; v_j jsonb; v_antes jsonb := '{}'; v_desp jsonb := '{}'; v_k text; v_iguales int := 0; v_dist text := ''; v_tf_a numeric := 0; v_tf_b numeric := 0; v_tp_a numeric := 0; v_tp_b numeric := 0; v_tc_a numeric := 0; v_tc_b numeric := 0; v_te_a numeric := 0; v_te_b numeric := 0; v_n1 int; v_n2 int; v_n3 int; v_n4 int; v_ctes text;
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
    select count(*) into v_n1 from regexp_matches(v_def, '\$function\$\s*select c\.id,', 'g');
  v_def := regexp_replace(v_def, '(\$function\$\s*)(select c\.id,)', '\1' || replace(v_ctes, '\', '\\') || '\2');
  select count(*) into v_n2 from regexp_matches(v_def, 'private\.analista_atribuido_cadena\(c\.id\)', 'g');
  v_def := replace(v_def, 'private.analista_atribuido_cadena(c.id)', '(((select m from atrib_map)->>c.id::text)::uuid)');
  select count(*) into v_n3 from regexp_matches(v_def, 'private\.inversionista_canonica\(x\.id\)', 'g');
  v_def := replace(v_def, 'private.inversionista_canonica(x.id)', 'coalesce(((select m from canon_map)->>x.id::text)::uuid, x.id)');
  v_n4 := 1;
  if v_n1<>1 or v_n2<>1 or v_n3<>2 or v_n4<>1 then raise exception 'PATRONES inesperados: % % % %', v_n1, v_n2, v_n3, v_n4; end if;

  perform set_config('request.jwt.claims', json_build_object('sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127','role','authenticated')::text, true);
  select array_agg(id) into v_ids from ((select distinct inversionista_id as id from crm.tareas where inversionista_id is not null)
    union (select id from (select id from crm.inversionistas where estado<>'fusionado' order by id limit 16) y)) z;
  -- ANTES: oráculo y tiempos
  foreach v_id in array v_ids loop v_antes := v_antes || jsonb_build_object('ficha:'||v_id::text, md5(coalesce(crm.inversionista_ficha_fn(v_id,1,1)::text,'null'))); end loop;
  v_antes := v_antes || jsonb_build_object('agenda', md5(crm.postventa_agenda_fn()::text), 'estado', md5(crm.cartera_inversionistas_estado_fn()::text),
    'cartera', md5(crm.cartera_inversionistas_filtrada_fn(1,25,null,null,null,false,null,null,null,null,false)::text), 'pv_estado', md5(crm.postventa_estado_fn()::text));
  for v_i in 1..3 loop
    v_t0 := clock_timestamp(); perform crm.inversionista_ficha_fn('5a0c033a-5ff1-445c-9feb-a8306e43bc52',1,1); v_tf_a := v_tf_a + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.postventa_agenda_fn(); v_tp_a := v_tp_a + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.cartera_inversionistas_filtrada_fn(1,25,null,null,null,false,null,null,null,null,false); v_tc_a := v_tc_a + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.cartera_inversionistas_estado_fn(); v_te_a := v_te_a + extract(epoch from clock_timestamp()-v_t0)*1000;
  end loop;
  -- REEMPLAZO (se deshace con el raise final)
  execute v_def;
  foreach v_id in array v_ids loop v_desp := v_desp || jsonb_build_object('ficha:'||v_id::text, md5(coalesce(crm.inversionista_ficha_fn(v_id,1,1)::text,'null'))); end loop;
  v_desp := v_desp || jsonb_build_object('agenda', md5(crm.postventa_agenda_fn()::text), 'estado', md5(crm.cartera_inversionistas_estado_fn()::text),
    'cartera', md5(crm.cartera_inversionistas_filtrada_fn(1,25,null,null,null,false,null,null,null,null,false)::text), 'pv_estado', md5(crm.postventa_estado_fn()::text));
  for v_i in 1..3 loop
    v_t0 := clock_timestamp(); perform crm.inversionista_ficha_fn('5a0c033a-5ff1-445c-9feb-a8306e43bc52',1,1); v_tf_b := v_tf_b + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.postventa_agenda_fn(); v_tp_b := v_tp_b + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.cartera_inversionistas_filtrada_fn(1,25,null,null,null,false,null,null,null,null,false); v_tc_b := v_tc_b + extract(epoch from clock_timestamp()-v_t0)*1000;
    v_t0 := clock_timestamp(); perform crm.cartera_inversionistas_estado_fn(); v_te_b := v_te_b + extract(epoch from clock_timestamp()-v_t0)*1000;
  end loop;
  for v_k in select jsonb_object_keys(v_antes) loop
    if v_antes->>v_k = v_desp->>v_k then v_iguales := v_iguales + 1; else v_dist := v_dist || ' ' || v_k; end if;
  end loop;
  raise exception 'E2E|oráculo: % iguales de %, distintas:[%] | ficha % → % ms | agenda postventa % → % | cartera inv. % → % | estado cartera % → %',
    v_iguales, (select count(*) from jsonb_object_keys(v_antes)), v_dist, round(v_tf_a/3), round(v_tf_b/3), round(v_tp_a/3), round(v_tp_b/3), round(v_tc_a/3), round(v_tc_b/3), round(v_te_a/3), round(v_te_b/3);
end $x$;
