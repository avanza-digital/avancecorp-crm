-- Reversa de 20260925002615_crm_audit_log_solo_anadir.sql: quita el candado y devuelve los
-- permisos que tenía public.audit_log el 24/09/2026 (anon/authenticated arwd,
-- service_role arwdDxtm).
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $rollback$ begin
  -- El candado se identifica por su DEFINICIÓN, no solo por el nombre: si alguien
  -- lo cambió después, esta reversa no es la que corresponde.
  if md5(pg_get_functiondef('private.trg_audit_log_solo_anadir()'::regprocedure)) <> 'c93672e85de5070fd1a5cf39b5113725' then
    raise exception 'audit_log: la función del candado no es la que instaló la migración';
  end if;
  if (select string_agg(t.tgname || ':' || t.tgtype::text || ':' || t.tgenabled::text || ':' || t.tgfoid::regprocedure::text, ',' order by t.tgname)
        from pg_trigger t where t.tgrelid = 'public.audit_log'::regclass and not t.tgisinternal)
     is distinct from 'trg_audit_log_sin_vaciar:34:O:private.trg_audit_log_solo_anadir(),trg_audit_log_solo_anadir:27:O:private.trg_audit_log_solo_anadir()' then
    raise exception 'audit_log: los triggers no son los que instaló la migración';
  end if;
  if (select c.relacl::text from pg_class c where c.oid = 'public.audit_log'::regclass)
     is distinct from '{postgres=arwdDxtm/postgres,anon=ar/postgres,authenticated=ar/postgres,service_role=arm/postgres}' then
    raise exception 'audit_log: el ACL no es el que dejó la migración';
  end if;
end; $rollback$;
drop trigger trg_audit_log_sin_vaciar on public.audit_log;
drop trigger trg_audit_log_solo_anadir on public.audit_log;
drop function private.trg_audit_log_solo_anadir();
grant update, delete on table public.audit_log to anon, authenticated;
grant update, delete, truncate, references, trigger on table public.audit_log to service_role;
do $postflight$
declare v_rol text; v_priv text;
begin
  foreach v_rol in array array['anon', 'authenticated'] loop
    foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE'] loop
      if not has_table_privilege(v_rol, 'public.audit_log', v_priv) then
        raise exception 'reversa: % no recuperó %', v_rol, v_priv;
      end if;
    end loop;
  end loop;
  foreach v_priv in array array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'] loop
    if not has_table_privilege('service_role', 'public.audit_log', v_priv) then
      raise exception 'reversa: service_role no recuperó %', v_priv;
    end if;
  end loop;
  -- Y el ACL es, letra por letra, el que medía el preflight de la migración.
  if (select c.relacl::text from pg_class c where c.oid = 'public.audit_log'::regclass)
     is distinct from '{postgres=arwdDxtm/postgres,anon=arwd/postgres,authenticated=arwd/postgres,service_role=arwdDxtm/postgres}' then
    raise exception 'reversa: el ACL no quedó idéntico al previo (%)',
      (select c.relacl::text from pg_class c where c.oid = 'public.audit_log'::regclass);
  end if;
end; $postflight$;
select 'ROLLBACK_AUDIT_LOG_OK' as veredicto,
  (select c.relacl::text from pg_class c where c.oid = 'public.audit_log'::regclass) as acl;
commit;
