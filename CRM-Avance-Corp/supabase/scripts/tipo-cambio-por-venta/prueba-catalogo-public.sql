-- Solo huellas de catálogo: ninguna definición o dato personal sale del banco.
create function pg_temp.huella_catalogo_public() returns text language sql stable as $$
  select md5(jsonb_build_array(
    (select jsonb_agg(jsonb_build_array(p.oid,pg_get_functiondef(p.oid),p.proowner,p.proacl) order by p.oid)
      from pg_proc p where p.pronamespace='public'::regnamespace and p.prokind in('f','p')),
    (select jsonb_agg(jsonb_build_array(c.oid,c.relkind,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity,
        case when c.relkind in('v','m') then pg_get_viewdef(c.oid) end) order by c.oid)
      from pg_class c where c.relnamespace='public'::regnamespace),
    (select jsonb_agg(to_jsonb(a) order by a.attrelid,a.attnum) from pg_attribute a
      join pg_class c on c.oid=a.attrelid where c.relnamespace='public'::regnamespace and a.attnum>0),
    (select jsonb_agg(jsonb_build_array(c.oid,pg_get_constraintdef(c.oid)) order by c.oid)
      from pg_constraint c where c.connamespace='public'::regnamespace),
    (select jsonb_agg(jsonb_build_array(t.oid,pg_get_triggerdef(t.oid),t.tgenabled) order by t.oid)
      from pg_trigger t join pg_class c on c.oid=t.tgrelid where c.relnamespace='public'::regnamespace),
    (select jsonb_agg(to_jsonb(p) order by p.oid) from pg_policy p
      join pg_class c on c.oid=p.polrelid where c.relnamespace='public'::regnamespace)
  )::text);
$$;
create temp table catalogo_public_antes as select pg_temp.huella_catalogo_public() as huella;
