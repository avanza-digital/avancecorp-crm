-- ACL, funciones y guardianes conservados al ampliar el alcance del recorrido.
begin;
set local search_path='';
do $$
declare v_firma text;v_oid oid;r record;
begin
  foreach v_firma in array array['private.recorrido_exigir(uuid,text)',
    'private.recorrido_solicitud_guard()','private.recorrido_insert_convertido_guard()'] loop
    v_oid:=to_regprocedure(v_firma);
    select * into strict r from pg_proc where oid=v_oid;
    if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
      or not coalesce('search_path=""'=any(r.proconfig),false) then
      raise exception 'Owner, definer o search_path de recorrido incorrecto: %',v_firma;end if;
    if exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
      where a.grantee<>r.proowner) then
      raise exception 'Helper expuesto: %',v_firma;end if;
  end loop;
  foreach v_firma in array array['crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)',
    'crm.confirmar_inversion_revisada_fn(uuid,integer)','crm.acceso_inversion_fn(uuid,text,jsonb)',
    'private.conversion_lead_con_inversion()'] loop
    v_oid:=to_regprocedure(v_firma);
    select * into strict r from pg_proc where oid=v_oid;
    if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
      or not coalesce('search_path=""'=any(r.proconfig),false)
      or position('private.recorrido_exigir' in r.prosrc)=0 then
      raise exception 'Defensa no integrada: %',v_firma;end if;
    if exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
      where a.grantee<>r.proowner and not (r.pronamespace='crm'::regnamespace
        and a.grantee='authenticated'::regrole and a.privilege_type='EXECUTE')) then
      raise exception 'ACL ampliada al integrar recorrido: %',v_firma;end if;
  end loop;
  foreach v_firma in array array['crm.recorrido_configurar_fn(text,text,integer,timestamptz)',
    'crm.recorrido_leads_fn(uuid[])'] loop
    select * into strict r from pg_proc where oid=to_regprocedure(v_firma);
    if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
      or not coalesce('search_path=""'=any(r.proconfig),false)
      or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
        where a.grantee<>r.proowner and a.grantee<>'authenticated'::regrole) then
      raise exception 'Lectura o control del recorrido ampliaron permisos: %',v_firma;end if;
  end loop;
  if not (select relrowsecurity from pg_class where oid='crm.inversion_solicitudes'::regclass)
    or not exists(select 1 from pg_trigger where tgrelid='crm.inversion_solicitudes'::regclass
      and tgname='trg_audit_inversion_solicitudes' and tgenabled='O') then
    raise exception 'RLS o auditoría de solicitudes ausente';end if;
  if has_column_privilege('authenticated','crm.inversion_solicitudes','recorrido_confirmado','UPDATE')
    or has_column_privilege('anon','crm.inversion_solicitudes','recorrido_confirmado','UPDATE') then
    raise exception 'La evidencia confirmada no admite escritura directa de API';end if;
  perform private.assert_sla_nucleo();
end $$;
notify pgrst,'reload schema';
commit;
