-- El rechazo HTTP conserva la autorización gerencial y no amplía el acceso.
begin;
set local search_path='';
set local quote_all_identifiers=off;
do $$
declare r record;
begin
  select * into strict r from pg_proc
    where oid='crm.recorrido_configurar_fn(text,text,integer,timestamptz)'::regprocedure;
  if md5(pg_get_functiondef(r.oid))<>'6597bef760830dc37673df68e174cbec'
    or r.proowner<>'postgres'::regrole or not r.prosecdef
    or not coalesce('search_path=""'=any(r.proconfig),false)
    or not has_function_privilege('authenticated',r.oid,'EXECUTE')
    or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
      where a.grantee<>r.proowner and a.grantee<>'authenticated'::regrole) then
    raise exception 'El contrato o los permisos del control del recorrido no coinciden';
  end if;
  perform private.assert_sla_nucleo();
end $$;
commit;
