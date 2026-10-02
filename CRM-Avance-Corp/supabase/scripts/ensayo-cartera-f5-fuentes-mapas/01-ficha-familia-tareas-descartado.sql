-- ENSAYO DESHECHO: copia temporal de la ficha con la familia precalculada; termina SIEMPRE en raise.
do $x$
declare
  v_def text; v_n1 int; v_n2 int; v_n3 int; v_n4 int;
  v_ids uuid[]; v_id uuid; v_actor uuid; v_i int := 0;
  v_a jsonb; v_b jsonb; v_ea text; v_eb text; v_t0 timestamptz; v_ta numeric; v_tb numeric;
  v_ok int := 0; v_bad int := 0; v_sa numeric := 0; v_sb numeric := 0; v_n int := 0; v_dif text := ''; v_res text := '';
  v_maxa numeric := 0; v_maxb numeric := 0;
begin
  v_def := pg_get_functiondef('crm.inversionista_ficha_fn'::regproc);
  v_def := replace(v_def, 'FUNCTION crm.inversionista_ficha_fn(', 'FUNCTION pg_temp.ficha_b(');
  select count(*) into v_n1 from regexp_matches(v_def, 'v_p record;\s*v_id uuid;', 'g');
  v_def := regexp_replace(v_def, '(v_p record;\s*v_id uuid;)', '\1 v_familia uuid[];');
  select count(*) into v_n2 from regexp_matches(v_def, 'v_id:=private\.inversionista_canonica\(p_inversionista\);', 'g');
  v_def := regexp_replace(v_def, '(v_id:=private\.inversionista_canonica\(p_inversionista\);)',
    '\1 select coalesce(array_agg(x.id),''{}'') into v_familia from (with recursive f as (select i.id, 1 as n from crm.inversionistas i where i.id=v_id union all select i.id, f.n+1 from f join crm.inversionistas i on i.inversionista_canonico_id=f.id where f.n<16) select id from f) x;');
  select count(*) into v_n3 from regexp_matches(v_def, 'private\.inversionista_canonica\(t\.inversionista_id\)\s*=\s*v_id', 'g');
  v_def := regexp_replace(v_def, 'private\.inversionista_canonica\(t\.inversionista_id\)\s*=\s*v_id',
    't.inversionista_id=any(v_familia) and private.inversionista_canonica(t.inversionista_id)=v_id', 'g');
  select count(*) into v_n4 from regexp_matches(v_def, 'private\.inversionista_canonica\(g\.inversionista_id\)\s*=\s*v_id', 'g');
  v_def := regexp_replace(v_def, 'private\.inversionista_canonica\(g\.inversionista_id\)\s*=\s*v_id',
    'g.inversionista_id=any(v_familia) and private.inversionista_canonica(g.inversionista_id)=v_id', 'g');
  if v_n1<>1 or v_n2<>1 or v_n3<>1 or v_n4<>2 then raise exception 'PATRONES inesperados: % % % %', v_n1, v_n2, v_n3, v_n4; end if;
  execute v_def;

  select array_agg(id) into v_ids from (
    (select distinct inversionista_id as id from crm.tareas where inversionista_id is not null)
    union (select id from (select id from crm.inversionistas where estado<>'fusionado' order by id limit 16) y)
  ) z;

  foreach v_actor in array array['bf1c562e-ed08-4cc3-92a8-34f1fa3e9127'::uuid, '2c10b18a-a15d-4952-952b-c4ab91b96153'::uuid] loop
    perform set_config('request.jwt.claims', json_build_object('sub', v_actor, 'role', 'authenticated')::text, true);
    v_ok := 0; v_bad := 0; v_sa := 0; v_sb := 0; v_n := 0; v_dif := ''; v_maxa := 0; v_maxb := 0;
    foreach v_id in array v_ids loop
      v_i := v_i + 1; v_a := null; v_b := null; v_ea := null; v_eb := null;
      if v_i % 2 = 0 then
        begin v_t0 := clock_timestamp(); v_a := crm.inversionista_ficha_fn(v_id,1,1); v_ta := extract(epoch from clock_timestamp()-v_t0)*1000; exception when others then v_ea := sqlerrm; v_ta := 0; end;
        begin v_t0 := clock_timestamp(); v_b := pg_temp.ficha_b(v_id,1,1); v_tb := extract(epoch from clock_timestamp()-v_t0)*1000; exception when others then v_eb := sqlerrm; v_tb := 0; end;
      else
        begin v_t0 := clock_timestamp(); v_b := pg_temp.ficha_b(v_id,1,1); v_tb := extract(epoch from clock_timestamp()-v_t0)*1000; exception when others then v_eb := sqlerrm; v_tb := 0; end;
        begin v_t0 := clock_timestamp(); v_a := crm.inversionista_ficha_fn(v_id,1,1); v_ta := extract(epoch from clock_timestamp()-v_t0)*1000; exception when others then v_ea := sqlerrm; v_ta := 0; end;
      end if;
      v_n := v_n + 1; v_sa := v_sa + v_ta; v_sb := v_sb + v_tb; v_maxa := greatest(v_maxa, v_ta); v_maxb := greatest(v_maxb, v_tb);
      if v_a is not distinct from v_b and v_ea is not distinct from v_eb then v_ok := v_ok + 1;
      else v_bad := v_bad + 1; v_dif := v_dif || format(' [%s a=%s b=%s claves=%s]', left(v_id::text,8), coalesce(v_ea,'json'), coalesce(v_eb,'json'),
        (select string_agg(k, ',') from (select jsonb_object_keys(coalesce(v_a,'{}')) k except select jsonb_object_keys(coalesce(v_b,'{}'))) q));
      end if;
    end loop;
    v_res := v_res || format('ACTOR %s: %s personas, iguales=%s distintas=%s | A media=%s ms max=%s | B media=%s ms max=%s%s || ',
      left(v_actor::text,8), v_n, v_ok, v_bad, round(v_sa/v_n), round(v_maxa), round(v_sb/v_n), round(v_maxb), v_dif);
  end loop;
  raise exception 'ENSAYO|%', v_res;
end $x$;
