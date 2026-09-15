-- Muestra retrospectiva fijada por huellas del corte, sin datos personales.
-- Las RPC registran lecturas. ROLLBACK deshace esa auditoría de ensayo.
begin isolation level read committed;
set local statement_timeout='45s';
set local lock_timeout='2s';
set local search_path='';
do $fichas$
declare
  v_actor uuid; p record; ficha jsonb; items jsonb; esperadas jsonb;
  totales_esperados jsonb; v_dif bigint; v_totales_dif bigint; v_pag integer;
  v_desde integer; v_hasta integer; v_count bigint; v_despues jsonb;
  resultados jsonb:='[]'; v_error text;
begin
  select e.perfil_id into strict v_actor from crm.piloto_f8_miembros m
    join crm.equipo e on e.perfil_id=m.perfil_id and e.activo
    join public.perfiles pf on pf.id=e.perfil_id and pf.activo
    where m.activo and m.rol_esperado='gerencia' and e.rol_crm='gerencia';
  for p in select id from crm.inversionistas
    where md5('G7-20260915:'||id::text)=any(array['32eb2adebcb2ae55fce168a9e4140667','94a4f8012ef55481c279f47735066d94','28c883d2b5948d6ba701bef5338d8e81','8b8c94db2df50cee07300a04f29a9a65','4c696cec54398fdae37fc14ce94fbdab','8110aeffb3e790d223f33e403e35eb62','a0607b69829bd5bec7f29f9407290cc9','07a0eaae1907b7f72b8054a5ea504554','1eea5517ff5b8b95e49643742ccbfe1e','ede357a3712d64e14170eb6f27fac5c6','b82ebec7e14173981236a1a840d34b08','446eb764f302ff30a8845fa4a2e1e41d','43c4d1d1a77e076e83d8ed0c2b517338','f40422364703537f4c268365d67ad3b4','ff369985fa7539a2daa4b36ef66393e2','a9dd0b0519aed56bdaa5982a5482ef81','758c59871f621d31213b1f70c2da31fc','6496dbd4f6364d96e1073a3f7f8f07d7','450283c48765afb9b958d322524b43ff'])
    order by id
  loop
    select coalesce(jsonb_agg(jsonb_build_object('fuente_id',f.fuente_id,'empresa',f.empresa,
      'moneda',f.moneda,'capital',f.capital,'analista_origen_id',f.analista_origen_id,
      'fecha_imputacion',f.fecha_imputacion) order by f.empresa,f.fuente_id),'[]'),count(*)
      into esperadas,v_count from private.cartera_f5_fuentes_reales() f where f.inversionista_id=p.id;
    select coalesce(jsonb_agg(to_jsonb(t) order by empresa,moneda),'[]') into totales_esperados
      from(select empresa,moneda,count(*) cantidad,sum(capital) capital_registrado
        from private.cartera_f5_fuentes_reales() f where f.inversionista_id=p.id group by empresa,moneda)t;
    ficha:=null; items:='[]'; v_error:=null; v_totales_dif:=0;
    perform set_config('request.jwt.claim.sub',v_actor::text,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    set local role authenticated;
    begin
      for v_pag in 1..greatest(1,ceil(v_count/25.0)::integer) loop
        ficha:=crm.inversionista_ficha_fn(p.id,v_pag,1);
        if ficha is null or (ficha->>'inversiones_total')::bigint is distinct from v_count then
          raise exception 'Ficha o total no coincide';
        end if;
        items:=items||(ficha->'inversiones');
        select count(*) into v_totales_dif from(
          (select empresa,moneda,cantidad,capital_registrado from jsonb_to_recordset(totales_esperados)
            t(empresa text,moneda text,cantidad bigint,capital_registrado numeric)
           except all
           select empresa,moneda,cantidad,capital_registrado from jsonb_to_recordset(ficha->'totales')
            t(empresa text,moneda text,cantidad bigint,capital_registrado numeric))
          union all
          (select empresa,moneda,cantidad,capital_registrado from jsonb_to_recordset(ficha->'totales')
            t(empresa text,moneda text,cantidad bigint,capital_registrado numeric)
           except all
           select empresa,moneda,cantidad,capital_registrado from jsonb_to_recordset(totales_esperados)
            t(empresa text,moneda text,cantidad bigint,capital_registrado numeric))
        )d;
        if v_totales_dif<>0 then raise exception 'Totales no coinciden'; end if;
      end loop;
    exception when others then v_error:=sqlstate;
    end;
    reset role;
    select count(*) into v_dif from(
      (select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion
        from jsonb_to_recordset(esperadas) f(fuente_id uuid,empresa text,moneda text,
          capital numeric,analista_origen_id uuid,fecha_imputacion date)
       except all
       select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion
        from jsonb_to_recordset(items) f(fuente_id uuid,empresa text,moneda text,
          capital numeric,analista_origen_id uuid,fecha_imputacion date))
      union all
      (select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion
        from jsonb_to_recordset(items) f(fuente_id uuid,empresa text,moneda text,
          capital numeric,analista_origen_id uuid,fecha_imputacion date)
       except all
       select fuente_id,empresa,moneda,capital,analista_origen_id,fecha_imputacion
        from jsonb_to_recordset(esperadas) f(fuente_id uuid,empresa text,moneda text,
          capital numeric,analista_origen_id uuid,fecha_imputacion date))
    )d;
    select coalesce(jsonb_agg(jsonb_build_object('fuente_id',f.fuente_id,'empresa',f.empresa,
      'moneda',f.moneda,'capital',f.capital,'analista_origen_id',f.analista_origen_id,
      'fecha_imputacion',f.fecha_imputacion) order by f.empresa,f.fuente_id),'[]')
      into v_despues from private.cartera_f5_fuentes_reales() f where f.inversionista_id=p.id;
    resultados:=resultados||jsonb_build_array(jsonb_build_object('persona',md5('G7-20260915:'||p.id::text),
      'inversiones',v_count,'diferencias_fuentes',v_dif,'diferencias_totales',v_totales_dif,
      'error',v_error,'fuente_estable',esperadas=v_despues,'ficha_hash',md5(ficha::text)));
  end loop;
  if jsonb_array_length(resultados)<>19 then raise exception 'Cambió la muestra de 19 personas'; end if;
  perform set_config('g7.fichas',resultados::text,true);
end;
$fichas$;
select jsonb_build_object('corte',statement_timestamp(),'metodo','RPC productiva con rol authenticated, Gerencia nominal, comparación NUMERIC y ROLLBACK; no Auth/HTTP ni UI.',
  'fichas',current_setting('g7.fichas')::jsonb) evidencia;
rollback;
