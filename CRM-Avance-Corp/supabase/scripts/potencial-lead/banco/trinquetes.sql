-- Foto de los trinquetes del banco, para compararla ANTES y DESPUÉS de una migración (un cambio que
-- pasa sus propias pruebas puede romper un sello ajeno). Corre cada private.assert_*() sin
-- argumentos y anota si pasa o con qué error cae, más el censo de contadores crudos de leads y
-- citas. En un banco sin datos varios caen: lo que importa es que la foto NO CAMBIE. Todo se deshace.
begin;
do $g$
declare r record; v text;
begin
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || left(replace(sqlerrm, E'\n', ' '), 160);
    end;
    raise notice 'GATE % => %', r.f, v;
  end loop;
end $g$;
select 'CENSO ' || coalesce(string_agg(t::text, ' ;; ' order by t::text), '(vacio)') from private.contadores_crudos_leads_citas() t;
rollback;
