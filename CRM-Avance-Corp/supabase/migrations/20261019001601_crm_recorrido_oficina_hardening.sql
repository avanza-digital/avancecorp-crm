begin;
revoke all on function private.recorrido_capturar_actividad() from public,anon,authenticated,service_role;
revoke all on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) from public,anon,service_role;
grant execute on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) to authenticated;
do $$
declare f record;
begin
  for f in select p.* from pg_proc p where p.oid in (
    'private.recorrido_capturar_actividad()'::regprocedure,
    'crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text)'::regprocedure)
  loop
    if f.proowner<>'postgres'::regrole or not f.prosecdef
      or not coalesce(f.proconfig@>array['search_path=""'],false) then
      raise exception 'Propietario o search_path incorrecto: %',f.proname;end if;
    if exists(select 1 from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a
      where a.grantee<>f.proowner and not (f.pronamespace='crm'::regnamespace and a.grantee='authenticated'::regrole)) then
      raise exception 'Grant inesperado: %',f.proname;end if;
  end loop;
  perform private.assert_sla_nucleo();
end $$;
commit;
