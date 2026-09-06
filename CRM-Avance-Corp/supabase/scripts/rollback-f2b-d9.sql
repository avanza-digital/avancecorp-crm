-- ============================================================================
-- REVERSA de F2.b [D-9] (20260906100000): vuelve a colgar private.log_audit_crm() en crm.leads y crm.cierres_externos
-- (los triggers vivos de producción, byte a byte). Repetible dos veces. Las filas enmascaradas entre medias quedan así.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d9_auditores_sin_documento'));
do $guard$
begin
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal) not in ('CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()', 'CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''dni'', ''fecha_nacimiento'', ''genero'')') then
    raise exception 'F2.b D-9: trg_audit_leads no es el trigger vivo de producción ni el de D-9 (%)', (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal);
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal) not in ('CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()', 'CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''documento'')') then
    raise exception 'F2.b D-9: trg_audit_cierres_externos no es el trigger vivo de producción ni el de D-9 (%)', (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal);
  end if;
end
$guard$;
drop trigger if exists trg_audit_leads on crm.leads;
create trigger trg_audit_leads
  after insert or delete or update on crm.leads
  for each row execute function private.log_audit_crm();
drop trigger if exists trg_audit_cierres_externos on crm.cierres_externos;
create trigger trg_audit_cierres_externos
  after insert or delete or update on crm.cierres_externos
  for each row execute function private.log_audit_crm();
do $post$
begin
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()'
     or (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()' then
    raise exception 'REVERSA D-9: los triggers no volvieron byte a byte a los vivos de producción';
  end if;
  if exists (select 1 from private.tablas_sin_rastro() s where s.tabla in ('crm.leads', 'crm.cierres_externos')) then
    raise exception 'F2.b D-9: el trinquete de auditoría dejó de ver rastro completo en leads/cierres';
  end if;
  if not exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones()) then
    raise exception 'F2.b D-9: el sello de exenciones no cuadra (este cambio no toca las listas)';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906100000';
  raise notice 'REVERSA F2.b D-9 OK (versión 20260906100000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
