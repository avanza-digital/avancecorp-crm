# gen-d9.py — F2.b prerrequisito de activación [D-9] (bloque 2): los auditores genéricos de crm.leads y
# crm.cierres_externos dejan de copiar el DOCUMENTO en claro a public.audit_log ([E3-13]: b5 prometió que ninguno de
# SUS payloads lleva el documento; los auditores genéricos seguían copiando la fila entera con dni/documento).
# No transforma texto de función: RECUELGA los dos triggers sobre private.log_audit_sin_secretos (auditor ya VIVO en
# public.suscripciones_push, crm.agenda_ics y crm.inversionista_identificadores; el trinquete de auditoría lo reconoce
# por OID) con las columnas a enmascarar ('dni' en leads, 'documento' en cierres). Mismo nombre de trigger => mismo
# orden de disparo entre los AFTER de cada tabla. Genera la migración 20260906100000, su reversa y el registro.
# NO va detrás de la bandera: es un endurecimiento de privacidad sin efecto funcional (enmascararlo «solo con ON»
# seguiría copiando documentos hasta el encendido).
# Uso: python3 gen-d9.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
H_SIN = 'ae7225bc9e86131813ac0328fff4c3ae'   # private.log_audit_sin_secretos() en PROD (05/09) = banco
H_ENM = '8bf2a25abfca644962c3dbc5908490c5'   # private.enmascarar_claves(jsonb,text[])
H_CRM = '2d1b31c407d6eb882047112224792e73'   # private.log_audit_crm() (no se toca; el postflight lo comprueba intacto)
H_TSR = '55c8b52ad34a1d6478eb04d387a71dc3'   # private.tablas_sin_rastro() (reconoce a log_audit_sin_secretos por OID)
ADV = 'crm_f2b_d9_auditores_sin_documento'
VER = '20260906100000'; NAME = f'{VER}_crm_f2b_d9_auditores_de_leads_y_cierres_sin_documento'
OLD_L = "CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()"
NEW_L = "CREATE TRIGGER trg_audit_leads AFTER INSERT OR DELETE OR UPDATE ON crm.leads FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos('dni')"
OLD_C = "CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_crm()"
NEW_C = "CREATE TRIGGER trg_audit_cierres_externos AFTER INSERT OR DELETE OR UPDATE ON crm.cierres_externos FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos('documento')"
q = lambda s: "'" + s.replace("'", "''") + "'"   # literal SQL

def def_de(tabla, trg):
    return f"(select pg_get_triggerdef(t.oid) from pg_trigger t where t.tgrelid = '{tabla}'::regclass and t.tgname = '{trg}' and not t.tgisinternal)"

GUARD_FN = f"""  if to_regprocedure('private.log_audit_sin_secretos()') is null
     or (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure) is distinct from '{H_SIN}'
     or not exists (select 1 from pg_proc p where p.oid = 'private.log_audit_sin_secretos()'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-9: private.log_audit_sin_secretos() no es el texto vivo de producción o perdió definer/search_path';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.enmascarar_claves(jsonb,text[])'::regprocedure) is distinct from '{H_ENM}' then
    raise exception 'F2.b D-9: private.enmascarar_claves(jsonb,text[]) no es el texto vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.tablas_sin_rastro()'::regprocedure) is distinct from '{H_TSR}' then
    raise exception 'F2.b D-9: private.tablas_sin_rastro() no es el texto vivo de producción (el trinquete debe reconocer al auditor sin secretos por OID)';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.log_audit_crm()'::regprocedure) is distinct from '{H_CRM}' then
    raise exception 'F2.b D-9: private.log_audit_crm() no es el texto vivo de producción';
  end if;
"""
GUARD_TRG = f"""  if {def_de('crm.leads','trg_audit_leads')} not in ({q(OLD_L)}, {q(NEW_L)}) then
    raise exception 'F2.b D-9: trg_audit_leads no es el trigger vivo de producción ni el de D-9 (%)', {def_de('crm.leads','trg_audit_leads')};
  end if;
  if {def_de('crm.cierres_externos','trg_audit_cierres_externos')} not in ({q(OLD_C)}, {q(NEW_C)}) then
    raise exception 'F2.b D-9: trg_audit_cierres_externos no es el trigger vivo de producción ni el de D-9 (%)', {def_de('crm.cierres_externos','trg_audit_cierres_externos')};
  end if;
"""
POST_COMUN = f"""  if exists (select 1 from private.tablas_sin_rastro() s where s.tabla in ('crm.leads', 'crm.cierres_externos')) then
    raise exception 'F2.b D-9: el trinquete de auditoría dejó de ver rastro completo en leads/cierres';
  end if;
  if not exists (select 1 from private.auditoria_sello h where h.huella = private.huella_exenciones()) then
    raise exception 'F2.b D-9: el sello de exenciones no cuadra (este cambio no toca las listas)';
  end if;
"""
mig = f"""-- ============================================================================
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
select pg_advisory_xact_lock(hashtext('{ADV}'));

do $guard$
begin
{GUARD_FN}{GUARD_TRG}end
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
  if {def_de('crm.leads','trg_audit_leads')} is distinct from {q(NEW_L)} then
    raise exception 'POSTFLIGHT D-9: trg_audit_leads no quedó como lo genera gen-d9.py';
  end if;
  if {def_de('crm.cierres_externos','trg_audit_cierres_externos')} is distinct from {q(NEW_C)} then
    raise exception 'POSTFLIGHT D-9: trg_audit_cierres_externos no quedó como lo genera gen-d9.py';
  end if;
  if exists (select 1 from pg_trigger t where t.tgname in ('trg_audit_leads', 'trg_audit_cierres_externos') and not t.tgisinternal and t.tgenabled not in ('O', 'A')) then
    raise exception 'POSTFLIGHT D-9: un auditor quedó deshabilitado';
  end if;
{POST_COMUN}{GUARD_FN}  raise notice 'F2.b D-9 OK: los auditores de crm.leads (dni) y crm.cierres_externos (documento) enmascaran el documento.';
end
$post$;
commit;
"""
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-9] ({VER}): vuelve a colgar private.log_audit_crm() en crm.leads y crm.cierres_externos
-- (los triggers vivos de producción, byte a byte). Repetible dos veces. Las filas enmascaradas entre medias quedan así.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('{ADV}'));
do $guard$
begin
{GUARD_TRG}end
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
  if {def_de('crm.leads','trg_audit_leads')} is distinct from {q(OLD_L)}
     or {def_de('crm.cierres_externos','trg_audit_cierres_externos')} is distinct from {q(OLD_C)} then
    raise exception 'REVERSA D-9: los triggers no volvieron byte a byte a los vivos de producción';
  end if;
{POST_COMUN}  delete from supabase_migrations.schema_migrations where version = '{VER}';
  raise notice 'REVERSA F2.b D-9 OK (versión {VER} desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d9.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-9]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; toma el MISMO advisory que la migración y la reversa (Codex #13); se niega si la versión ya está registrada con OTRO\n"
       "-- contenido, si los auditores no son los de D-9 o están deshabilitados, o si el auditor sin secretos / enmascarar_claves cambiaron (Codex #14).\n"
       f"begin;\nselect pg_advisory_xact_lock(hashtext('{ADV}'));\ndo $chk$\nbegin\n"
       f"  if {def_de('crm.leads','trg_audit_leads')} is distinct from {q(NEW_L)}\n     or {def_de('crm.cierres_externos','trg_audit_cierres_externos')} is distinct from {q(NEW_C)} then\n"
       "    raise exception 'REGISTRO D-9: los auditores VIVOS no son los de D-9 (aplica la migración ANTES de registrar)';\n  end if;\n"
       "  if exists (select 1 from pg_trigger t where t.tgname in ('trg_audit_leads', 'trg_audit_cierres_externos') and not t.tgisinternal and t.tgenabled not in ('O', 'A')) then\n"
       "    raise exception 'REGISTRO D-9: un auditor está deshabilitado';\n  end if;\n"
       + GUARD_FN.replace('F2.b D-9', 'REGISTRO D-9') + POST_COMUN.replace('F2.b D-9', 'REGISTRO D-9') +
       f"  if exists (select 1 from supabase_migrations.schema_migrations where version='{VER}' and (statements is null or array_length(statements, 1) is distinct from 1 or statements[1] is null or md5(statements[1]) <> '{H_MIG}')) then\n"
       f"    raise exception 'REGISTRO D-9: la versión {VER} ya está registrada con otro contenido (o incompleto: Codex N5)';\n  end if;\nend\n$chk$;\n"
       f"insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('{VER}', '{NAME[len(VER)+1:]}', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d9.sql').write_text(reg, encoding='utf-8')
print('D-9 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 migración', H_MIG)
