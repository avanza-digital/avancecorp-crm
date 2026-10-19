begin;
set local search_path='';
alter function private.recorrido_capturar_actividad() set search_path='';
alter function private.recorrido_serializar_invalidacion() set search_path='';
revoke all on function private.recorrido_capturar_actividad(),private.recorrido_serializar_invalidacion()
  from public,anon,authenticated,service_role;
do $$ declare r record; begin
  for r in select * from pg_proc where oid in ('private.recorrido_capturar_actividad()'::regprocedure,
    'private.recorrido_serializar_invalidacion()'::regprocedure) loop
    if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
      or not coalesce('search_path=""'=any(r.proconfig),false)
      or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
        where a.grantee<>r.proowner and a.privilege_type='EXECUTE') then
      raise exception 'Owner, definer, search_path o ACL incorrectos: %',r.oid::regprocedure;
    end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid='crm.actividad_ciclo_contexto'::regclass)
    or not exists(select 1 from pg_trigger where tgrelid='crm.actividad_ciclo_contexto'::regclass
      and tgname='audit_actividad_ciclo_contexto' and tgenabled='O') then
    raise exception 'Falta RLS o auditoria del contexto';
  end if;
  perform private.assert_sla_nucleo();
end $$;
notify pgrst,'reload schema';
commit;
