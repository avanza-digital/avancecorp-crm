-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-9]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.
-- Idempotente; toma el MISMO advisory que la migración y la reversa (Codex #13); se niega si la versión ya está registrada con OTRO
-- contenido, si los auditores no son los de D-9 o están deshabilitados, o si el auditor sin secretos / enmascarar_claves cambiaron (Codex #14).
begin;
select pg_advisory_xact_lock(hashtext('crm_f2b_d9_auditores_sin_documento'));
do $chk$
begin
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''dni'')'
     or (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''documento'')' then
    raise exception 'REGISTRO D-9: los auditores VIVOS no son los de D-9 (aplica la migración ANTES de registrar)';
  end if;
  if exists (select 1 from pg_trigger t where t.tgname in ('trg_audit_leads', 'trg_audit_cierres_externos') and not t.tgisinternal and t.tgenabled not in ('O', 'A')) then
    raise exception 'REGISTRO D-9: un auditor está deshabilitado';
  end if;
  if to_regprocedure('private.log_audit_sin_secretos()') is null
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure) is distinct from 'ae7225bc9e86131813ac0328fff4c3ae'
     or not exists (select 1 from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'REGISTRO D-9: private.log_audit_sin_secretos() no es el texto vivo de producción o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.enmascarar_claves(jsonb,text[])'::regprocedure) is distinct from '8bf2a25abfca644962c3dbc5908490c5' then
    raise exception 'REGISTRO D-9: private.enmascarar_claves(jsonb,text[]) no es el texto vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.tablas_sin_rastro()'::regprocedure) is distinct from '55c8b52ad34a1d6478eb04d387a71dc3' then
    raise exception 'REGISTRO D-9: private.tablas_sin_rastro() no es el texto vivo de producción (el trinquete debe reconocer al auditor sin secretos por OID)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_crm()'::regprocedure) is distinct from '2d1b31c407d6eb882047112224792e73' then
    raise exception 'REGISTRO D-9: private.log_audit_crm() no es el texto vivo de producción';
  end if;
  if exists (select 1 from private.tablas_sin_rastro() s where s.tabla in ('crm.leads', 'crm.cierres_externos')) then
    raise exception 'REGISTRO D-9: el trinquete de auditoría dejó de ver rastro completo en leads/cierres';
  end if;
  if not exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones()) then
    raise exception 'REGISTRO D-9: el sello de exenciones no cuadra (este cambio no toca las listas)';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260906100000' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> 'e951a37ad994427383c45c1ab7577402')) then
    raise exception 'REGISTRO D-9: la versión 20260906100000 ya está registrada con otro contenido (o incompleto: Codex N5)';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260906100000', 'crm_f2b_d9_auditores_de_leads_y_cierres_sin_documento', array[$m$-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-9] — LOS AUDITORES GENÉRICOS DE
-- LEADS Y CIERRES NO COPIAN EL DOCUMENTO EN CLARO (bloque 2 del plan de activación, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE: private.log_audit_crm() copia la fila ENTERA (to_jsonb(old/new)) a public.audit_log. En crm.leads eso incluye
-- `dni` y en crm.cierres_externos `documento`: cada corrección de DNI, cada cambio de etapa, cada reapunte de un
-- cierre dejaba el documento en claro en la auditoría ([E3-13]: b5 garantiza que NINGUNO de sus payloads lleva el
-- documento; los auditores genéricos eran la deuda [D-9]). Los dos triggers pasan a private.log_audit_sin_secretos
-- (auditor ya VIVO en suscripciones_push, agenda_ics e inversionista_identificadores; enmascara con "***" sin
-- huella, conserva los null, y omite el UPDATE que solo mueve `actualizado_en`) con la columna a enmascarar.
-- Mismo nombre de trigger => mismo orden de disparo. Nada más cambia: mismas tablas, mismos verbos, mismo
-- `fila_id`, mismo actor; el trinquete (private.tablas_sin_rastro) reconoce ese auditor por OID.
-- NO va detrás de la bandera resolver_en_puertas: es privacidad, sin efecto funcional; enmascarar «solo con ON»
-- seguiría copiando documentos hasta el encendido. Las filas HISTÓRICAS de audit_log (163 de leads y 33 de cierres
-- con documento en claro el 05/09) no se tocan: decisión aparte de Miguel (la auditoría no se reescribe sola).
-- Ensayo: scripts/oraculo-f2b-d9.sh. Reversa: scripts/rollback-f2b-d9.sql. Registro: scripts/registrar-f2b-d9.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d9_auditores_sin_documento'));

do $guard$
begin
  if to_regprocedure('private.log_audit_sin_secretos()') is null
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure) is distinct from 'ae7225bc9e86131813ac0328fff4c3ae'
     or not exists (select 1 from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-9: private.log_audit_sin_secretos() no es el texto vivo de producción o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.enmascarar_claves(jsonb,text[])'::regprocedure) is distinct from '8bf2a25abfca644962c3dbc5908490c5' then
    raise exception 'F2.b D-9: private.enmascarar_claves(jsonb,text[]) no es el texto vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.tablas_sin_rastro()'::regprocedure) is distinct from '55c8b52ad34a1d6478eb04d387a71dc3' then
    raise exception 'F2.b D-9: private.tablas_sin_rastro() no es el texto vivo de producción (el trinquete debe reconocer al auditor sin secretos por OID)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_crm()'::regprocedure) is distinct from '2d1b31c407d6eb882047112224792e73' then
    raise exception 'F2.b D-9: private.log_audit_crm() no es el texto vivo de producción';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal) not in ('CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()', 'CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''dni'')') then
    raise exception 'F2.b D-9: trg_audit_leads no es el trigger vivo de producción ni el de D-9 (%)', (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal);
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal) not in ('CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()', 'CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''documento'')') then
    raise exception 'F2.b D-9: trg_audit_cierres_externos no es el trigger vivo de producción ni el de D-9 (%)', (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal);
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.leads: el auditor enmascara `dni`
-- ============================================================================
drop trigger if exists trg_audit_leads on crm.leads;
create trigger trg_audit_leads
  after insert or delete or update on crm.leads
  for each row execute function private.log_audit_sin_secretos('dni');

-- ============================================================================
-- 2. crm.cierres_externos: el auditor enmascara `documento`
-- ============================================================================
drop trigger if exists trg_audit_cierres_externos on crm.cierres_externos;
create trigger trg_audit_cierres_externos
  after insert or delete or update on crm.cierres_externos
  for each row execute function private.log_audit_sin_secretos('documento');

do $post$
begin
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.leads'::regclass and t.tgname = 'trg_audit_leads' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''dni'')' then
    raise exception 'POSTFLIGHT D-9: trg_audit_leads no quedó como lo genera gen-d9.py';
  end if;
  if (select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = 'crm.cierres_externos'::regclass and t.tgname = 'trg_audit_cierres_externos' and not t.tgisinternal) is distinct from 'CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos(''documento'')' then
    raise exception 'POSTFLIGHT D-9: trg_audit_cierres_externos no quedó como lo genera gen-d9.py';
  end if;
  if exists (select 1 from pg_trigger t where t.tgname in ('trg_audit_leads', 'trg_audit_cierres_externos') and not t.tgisinternal and t.tgenabled not in ('O', 'A')) then
    raise exception 'POSTFLIGHT D-9: un auditor quedó deshabilitado';
  end if;
  if exists (select 1 from private.tablas_sin_rastro() s where s.tabla in ('crm.leads', 'crm.cierres_externos')) then
    raise exception 'F2.b D-9: el trinquete de auditoría dejó de ver rastro completo en leads/cierres';
  end if;
  if not exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones()) then
    raise exception 'F2.b D-9: el sello de exenciones no cuadra (este cambio no toca las listas)';
  end if;
  if to_regprocedure('private.log_audit_sin_secretos()') is null
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure) is distinct from 'ae7225bc9e86131813ac0328fff4c3ae'
     or not exists (select 1 from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-9: private.log_audit_sin_secretos() no es el texto vivo de producción o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.enmascarar_claves(jsonb,text[])'::regprocedure) is distinct from '8bf2a25abfca644962c3dbc5908490c5' then
    raise exception 'F2.b D-9: private.enmascarar_claves(jsonb,text[]) no es el texto vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.tablas_sin_rastro()'::regprocedure) is distinct from '55c8b52ad34a1d6478eb04d387a71dc3' then
    raise exception 'F2.b D-9: private.tablas_sin_rastro() no es el texto vivo de producción (el trinquete debe reconocer al auditor sin secretos por OID)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_crm()'::regprocedure) is distinct from '2d1b31c407d6eb882047112224792e73' then
    raise exception 'F2.b D-9: private.log_audit_crm() no es el texto vivo de producción';
  end if;
  raise notice 'F2.b D-9 OK: los auditores de crm.leads (dni) y crm.cierres_externos (documento) enmascaran el documento.';
end
$post$;
commit;
$m$])
on conflict (version) do nothing;
commit;
