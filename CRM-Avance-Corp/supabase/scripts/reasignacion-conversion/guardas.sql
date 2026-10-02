-- Comparación dentro de una sola transacción, sin retirar la candidata al acabar.
begin;
set local statement_timeout='60s';
do $$ begin
  if current_database()<>'reasignacion_conversion_v3_20260929' then
    raise exception 'Solo copia Docker aislada';
  end if;
end $$;
create temporary table guardas(firma text primary key, candidata text, base text) on commit drop;
do $$ declare f record; v_error text; begin
  for f in select p.oid::regprocedure::text firma from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname like 'assert\_%' escape '\'
      and p.pronargs=0 and p.prokind='f' order by p.proname loop
    v_error:=null;
    begin execute 'select '||f.firma;
    exception when others then v_error:=sqlstate||':'||sqlerrm; end;
    insert into guardas values(f.firma,v_error,null);
  end loop;
end $$;
drop trigger trg_leads_zzzz_conversion_responsable on crm.leads;
drop function private.trg_leads_sincronizar_conversion();
do $$ declare f record; v_error text; begin
  for f in select firma from guardas order by firma loop
    v_error:=null;
    begin execute 'select '||f.firma;
    exception when others then v_error:=sqlstate||':'||sqlerrm; end;
    update guardas set base=v_error where firma=f.firma;
  end loop;
  if exists(select 1 from guardas where candidata is not null and candidata is distinct from base) then
    raise exception 'Una guarda tiene un fallo nuevo: %',
      (select jsonb_agg(to_jsonb(g)) from guardas g where candidata is not null and candidata is distinct from base);
  end if;
  raise notice 'GUARDAS_PARIDAD_OK: % comprobadas, % fallos previos, cero fallos nuevos',
    (select count(*) from guardas),(select count(*) from guardas where base is not null);
end $$;
select firma,base as fallo_preexistente from guardas where base is not null order by firma;
rollback;
