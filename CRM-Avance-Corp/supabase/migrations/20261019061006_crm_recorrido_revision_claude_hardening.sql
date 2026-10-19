-- Los ajustes de error y fecha conservan propietarios, autorización y ACL.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$
declare r record;v_firma text;v_md5 text;
begin
  for v_firma,v_md5 in select * from (values
    ('crm.acceso_inversion_fn(uuid,text,jsonb)','b45c309fce1003058ee42de5804d95a9'),
    ('crm.recorrido_configurar_fn(text,text,integer,timestamptz)','e117179d10e2bc67b203e929647f7c53')
  ) x(firma,huella) loop
    select * into strict r from pg_proc where oid=to_regprocedure(v_firma);
    if md5(pg_get_functiondef(r.oid))<>v_md5 or r.proowner<>'postgres'::regrole or not r.prosecdef
      or not coalesce('search_path=""'=any(r.proconfig),false)
      or not has_function_privilege('authenticated',r.oid,'EXECUTE')
      or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
        where a.grantee<>r.proowner and a.grantee<>'authenticated'::regrole) then
      raise exception 'Contrato o permisos inesperados en %',v_firma using errcode='55000';
    end if;
  end loop;
  perform private.assert_sla_nucleo();
end $$;
commit;
