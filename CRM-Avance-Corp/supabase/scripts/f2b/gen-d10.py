# gen-d10.py — F2.b prerrequisito de activación [D-10]: la reserva de conversión POR PERSONA
# (crm.reservar_conversion_lead de 4 argumentos) cuenta el PUENTE en «un solo lead», como ya hacen las dos
# conversiones desde b5 (Codex B2). Genera la migración 20260905150000, su reversa y el registro
# TRANSFORMANDO el texto VIVO de producción (vivas/d10/crm.reservar_conversion_lead.4.sql, md5 en huellas-d10-prod.txt).
# Uso: python3 gen-d10.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'d10'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:80], s.count(old)); return s.replace(old, new)
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-d10-prod.txt').read_text().splitlines() if l.strip()}
ARGS = 'p_lead_id uuid, p_tipo_documento text, p_documento text, p_payload jsonb'
r_prev = viv('crm.reservar_conversion_lead.4')
assert hashlib.md5((r_prev + '\n').encode('utf-8')).hexdigest() == prod['crm.reservar_conversion_lead.4']
H_PROD = prod['crm.reservar_conversion_lead.4']
r = rep(r_prev, """  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
""", """  -- un solo lead TOTAL (invariante #6): la persona no puede tener OTRO lead.
  select l.id into v_otro from crm.leads l where l.inversionista_id = v_inv and l.id <> p_lead_id limit 1;
  -- F2.b [D-10] (Codex B2): si no hay OTRO enlace vivo, «un solo lead» cuenta también el PUENTE (crm.inversionista_leads,
  -- históricos del backfill sin enlace vivo), como ya hacen las dos conversiones desde b5; el propio lead no cuenta.
  -- Espejo de b5 (auditor D-10 M1): el enlace vivo se comprueba PRIMERO (el detalle señala el lead canónico cuando existe)
  -- y un lead ya cerrado conserva las respuestas de hoy (enlazado / «ya esta cerrado», más abajo). Mismo error y mismo
  -- detalle que hoy (el front no cambia).
  if v_otro is null and v_lead.etapa not in ('convertido', 'descartado') then
    select x into v_otro from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id order by x limit 1;
  end if;
""")
r = rep(r, """  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
""", """  if v_lead.inversionista_id is not null and v_lead.inversionista_id <> v_inv then
    raise exception 'El documento no es el de la persona de este lead' using errcode = 'P0409';
  end if;
  -- F2.b [D-10] (Codex #2): el PUENTE de ESTE lead también manda. Un lead que solo está en el puente (sin enlace vivo
  -- ni DNI) pertenece a la persona de su puente; con un documento que resuelve a otra persona no se reserva
  -- (la Gerencia lo corrige o fusiona), igual que ya exige crm.enlazar_lead_inversionista_fn (b5). Por la canónica.
  if exists (select 1 from crm.inversionista_leads il
              where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
""")
H_NEW = hashlib.md5((r + '\n').encode('utf-8')).hexdigest()
assert H_NEW != H_PROD
H_HELPER = '2421b2b78b02b8e93fd01598e2f54128'  # md5(pg_get_functiondef) de private.leads_de_identidades(uuid[]) en PROD (b5), = banco
GUARD_HELPER = f"""  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and pg_get_function_identity_arguments(p.oid)='p_ids uuid[]') is distinct from '{H_HELPER}'
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname='leads_de_identidades' and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-10: private.leads_de_identidades(uuid[]) no es el texto vivo de producción (b5) o perdió definer/search_path';
  end if;
"""
GUARD = f"""  v_h := null;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid) = '{ARGS}';
  if v_h is null then
    raise exception 'F2.b D-10: falta crm.reservar_conversion_lead(uuid,text,text,jsonb) (b4, 20260905110000)';
  end if;
  if v_h is distinct from '{H_PROD}' and v_h is distinct from '{H_NEW}' then
    raise exception 'F2.b D-10: crm.reservar_conversion_lead(uuid,text,text,jsonb) no es ni el texto vivo de producción ni el de D-10 (%)', v_h;
  end if;
"""
POST_GRANTS = """  if has_function_privilege('anon', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.reservar_conversion_lead(uuid,text,text,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.reservar_conversion_lead(uuid,text,text,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT D-10: los grants de la reserva por persona cambiaron (solo authenticated; ni anon, ni service_role, ni PUBLIC)';
  end if;
"""
mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-10] — LA RESERVA POR PERSONA
-- CUENTA EL PUENTE EN «UN SOLO LEAD» (Codex B2, como ya hacen las dos conversiones desde b5)
-- ============================================================================
--
-- QUE: con la bandera ENCENDIDA, crm.reservar_conversion_lead(lead, tipo, documento, payload) rechazaba una
-- segunda conversión de la misma persona SOLO si el otro lead llevaba el enlace vivo (leads.inversionista_id).
-- Los leads que solo están en el PUENTE (crm.inversionista_leads, históricos del backfill de F2 sin enlace vivo)
-- no contaban: la reserva —que es el preflight de la conversión Avance— abría claim y reserva para una persona
-- que las dos conversiones (b5) después rechazan. Ahora, si no hay OTRO enlace vivo, cuenta también el PUENTE
-- (private.leads_de_identidades) —espejo de b5: el enlace vivo primero, y un lead ya cerrado conserva sus
-- respuestas de hoy— con el MISMO error P0409 y el MISMO detalle (estado ya_es_cliente, lead_id): el front no cambia.
-- Transformada desde el texto VIVO de producción (scripts/f2b/gen-d10.py, guarda md5 EXACTA, postflight byte a byte).
-- Con la bandera APAGADA la sobrecarga sigue inerte (P0409 apagada antes de leer argumentos): aterriza apagada.
-- Ensayo: scripts/oraculo-f2b-d10-d11.sh (incluye [D-11]: replay de un claim terminal tras una fusión).
-- Reversa: scripts/rollback-f2b-d10.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d10_reserva_cuenta_puente'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_identidades(uuid[])') is null
     or to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is null then
    raise exception 'F2.b D-10: falta b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-10: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
{GUARD}{GUARD_HELPER}end
$guard$;

-- ============================================================================
-- 1. crm.reservar_conversion_lead(uuid,text,text,jsonb): «un solo lead» = enlace vivo ∪ puente
-- ============================================================================
{r}
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='{ARGS}') is distinct from '{H_NEW}' then
    raise exception 'POSTFLIGHT D-10: crm.reservar_conversion_lead(uuid,text,text,jsonb) no quedó byte a byte como la genera gen-d10.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='p_lead_id uuid') is distinct from 'a067183bfe986cf7bd5f82b4ed6674d7' then
    raise exception 'POSTFLIGHT D-10: la reserva de 1 argumento (camino de hoy, bandera apagada) cambió';
  end if;
{POST_GRANTS}{GUARD_HELPER}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-10: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-10 OK: la reserva por persona cuenta el puente en «un solo lead» (rama ON). Bandera APAGADA.';
end
$post$;
commit;
"""
NAME = '20260905150000_crm_f2b_d10_reserva_por_persona_cuenta_puente'
(W/'migrations'/f'{NAME}.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b [D-10] (20260905150000): restaura crm.reservar_conversion_lead(uuid,text,text,jsonb) byte a byte
-- (md5 de prod {H_PROD}). Se NIEGA si la bandera está encendida. Repetible dos veces.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d10_reserva_cuenta_puente'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA D-10: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
do $guard$
declare v_h text;
begin
{GUARD}end
$guard$;

{r_prev}
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='{ARGS}') is distinct from '{H_PROD}' then
    raise exception 'REVERSA D-10: la reserva por persona no volvió byte a byte al vivo de producción';
  end if;
{POST_GRANTS}  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'REVERSA D-10: la bandera se ENCENDIÓ mientras se revertía; no se confirma la reversa';
  end if;
  -- El ledger del servidor acompaña a la realidad (Codex D-10 #7): una reversa desregistra la versión.
  delete from supabase_migrations.schema_migrations where version = '20260905150000';
  raise notice 'REVERSA F2.b D-10 OK (versión 20260905150000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-d10.sql').write_text(rb, encoding='utf-8')
H_MIG = hashlib.md5(mig.encode('utf-8')).hexdigest()
reg = ("-- REGISTRO en supabase_migrations.schema_migrations de F2.b [D-10]. `db query --linked --file` NO registra: correr DESPUÉS de aplicar.\n"
       "-- Idempotente; se niega si la versión ya está registrada con OTRO contenido.\nbegin;\ndo $chk$\nbegin\n"
       "  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reservar_conversion_lead' and pg_get_function_identity_arguments(p.oid)='" + ARGS + "') is distinct from '" + H_NEW + "' then\n"
       "    raise exception 'REGISTRO D-10: la reserva por persona VIVA no es el texto de D-10 (aplica la migración ANTES de registrar)';\n  end if;\n"
       "  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then\n"
       "    raise exception 'REGISTRO D-10: la bandera está ENCENDIDA; D-10 aterriza apagada';\n  end if;\n"
       "  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905150000' and md5(statements[1]) <> '" + H_MIG + "') then\n"
       "    raise exception 'REGISTRO D-10: la versión 20260905150000 ya está registrada con otro contenido';\n  end if;\nend\n$chk$;\n"
       "insert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('20260905150000', 'crm_f2b_d10_reserva_por_persona_cuenta_puente', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n")
(W/'scripts'/'registrar-f2b-d10.sql').write_text(reg, encoding='utf-8')
print('D-10 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; reserva 4-args prod', H_PROD, 'D-10', H_NEW, '; md5 migración', H_MIG)
