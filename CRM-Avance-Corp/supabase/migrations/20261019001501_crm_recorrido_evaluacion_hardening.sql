-- Candados del bloque de evaluación, sin activar exigencia ni modificar public.
begin;
revoke all on crm.recorrido_control,crm.actividad_ciclo_contexto from public,anon,authenticated,service_role;
revoke all on function private.recorrido_contexto_guard(),private.recorrido_bloquear_insert(),
  private.recorrido_capturar_actividad(),private.recorrido_serializar_invalidacion(),
  private.recorrido_control_guard(),private.recorrido_evaluar(uuid[]) from public,anon,authenticated,service_role;
revoke all on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz)
  from public,anon,service_role;
grant execute on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz) to authenticated;
do $$
declare t text;r text;f record;
begin
  foreach t in array array['crm.recorrido_control','crm.actividad_ciclo_contexto'] loop
    if not (select relrowsecurity and relowner='postgres'::regrole from pg_class where oid=t::regclass)
      or exists(select 1 from pg_policy where polrelid=t::regclass) then
      raise exception 'Falta aislamiento del recorrido en %',t;end if;
    foreach r in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') then
        raise exception 'Privilegio directo inesperado: % sobre %',r,t;end if;
    end loop;
    if not exists(select 1 from pg_trigger where tgrelid=t::regclass and tgfoid='private.log_audit_crm()'::regprocedure
      and tgenabled='O' and tgtype=29) then raise exception 'Falta auditoria completa: %',t;end if;
  end loop;
  for f in select p.* from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='private' and p.proname like 'recorrido_%'
  loop
    if f.proowner<>'postgres'::regrole or not coalesce(f.proconfig@>array['search_path=""'],false)
      or exists(select 1 from aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) a where a.grantee<>f.proowner) then
      raise exception 'Propiedades o grants incorrectos: %',f.proname;end if;
  end loop;
  perform private.assert_sla_nucleo();
end $$;
commit;
