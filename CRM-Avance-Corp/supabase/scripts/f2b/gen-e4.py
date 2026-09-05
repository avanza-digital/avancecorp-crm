# gen-e4.py — F2.b E4: public.crear_contrato reconoce a la persona (ON) + candado del documento en public.perfiles.
# Genera migración 20260905140000, reversa y registro desde el texto VIVO (vivas/e4/public.crear_contrato.sql, md5 de prod).
# Uso: python3 gen-e4.py <dir scripts/f2b> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
viv = lambda n: (S/'vivas'/'e4'/f'{n}.sql').read_text(encoding='utf-8').rstrip('\n')
def rep(s, old, new, n=1):
    assert s.count(old) == n, (old[:80], s.count(old)); return s.replace(old, new)
prod = {l.split()[0]: l.split()[1] for l in (S/'huellas-e4-prod.txt').read_text().splitlines() if l.strip()}
cc_prev = viv('public.crear_contrato')
assert hashlib.md5((cc_prev + '\n').encode('utf-8')).hexdigest() == prod['public.crear_contrato']
H_PROD = prod['public.crear_contrato']
cc = rep(cc_prev, """  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
""", """  -- F2.b (E4) [D-1, OK de Miguel 05/09]: con la identidad unificada ENCENDIDA, crear un contrato RECONOCE
  -- a la persona ANTES del FOR SHARE de abajo (jerarquía -> documento -> identidad -> perfil, reentrante).
  -- Solo si el cliente existe activo (así un id inexistente sigue muriendo en el 42501 de siempre).
  -- Sin documento válido o con documento de otra persona reconocida -> P0409 (contrato §4.3, fail-closed).
  if coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
     and exists (select 1 from public.perfiles p where p.id = v_cliente_id and p.rol = 'cliente' and p.activo) then
    perform private.asegurar_identidad_perfil(v_cliente_id, 'contrato');
  end if;
  select p.asesor_perfil_id into v_asesor_id
  from public.perfiles p
  where p.id = v_cliente_id and p.rol = 'cliente' and p.activo
  for share;
  if not found then
    raise insufficient_privilege using
      message = 'Cliente no encontrado o fuera de tu cartera';
  end if;
""")
H_NEW = hashlib.md5((cc + '\n').encode('utf-8')).hexdigest()

TRIGGER = r"""-- ============================================================================
-- 2. Candado del documento en el Portal: el DNI/tipo de un cliente RECONOCIDO solo cambia por la corrección de Gerencia
-- ============================================================================
create or replace function private.trg_perfiles_documento_protegido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(old.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_new text := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(new.dni, ''), '[^A-Za-z0-9]', '', 'g'));
  v_told text := coalesce(nullif(pg_catalog.btrim(old.tipo_documento), ''), 'DNI');
  v_tnew text := coalesce(nullif(pg_catalog.btrim(new.tipo_documento), ''), 'DNI');
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    return new;
  end if;
  -- La corrección de Gerencia (crm.corregir_documento_inversionista_fn, b5) fija esta GUC alrededor de sus hechos.
  if coalesce(pg_catalog.current_setting('crm.correccion_documento', true) = 'on', false) then
    return new;
  end if;
  if v_old = v_new and v_told = v_tnew then
    return new;   -- mismo documento con otro formato: no es un cambio
  end if;
  if exists (select 1 from crm.inversionistas i where i.perfil_id = new.id and i.estado <> 'fusionado') then
    raise exception 'El documento de un cliente reconocido como persona solo se corrige desde el CRM (corrección de documento de Gerencia)'
      using errcode = 'P0409';
  end if;
  return new;
end;
$$;
revoke all on function private.trg_perfiles_documento_protegido() from public, anon, authenticated, service_role;
drop trigger if exists trg_perfiles_zz_documento_protegido on public.perfiles;
create trigger trg_perfiles_zz_documento_protegido
  before update of dni, tipo_documento on public.perfiles
  for each row execute function private.trg_perfiles_documento_protegido();
comment on trigger trg_perfiles_zz_documento_protegido on public.perfiles is
  'F2.b E4 (OK Miguel 05/09): con resolver_en_puertas encendida, el documento de un perfil enlazado a una identidad solo cambia bajo crm.correccion_documento=on (corrección de Gerencia). Apagada: inerte.';
"""

mig = f"""-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b E4 — LAS DOS PIEZAS DE `public` (OK de Miguel 05/09) [D-1]
-- ============================================================================
--
-- ⚠️ Excepción documentada: esta migración del CRM TOCA `public` (regla del subproyecto) con OK explícito de Miguel
-- (05/09/2026, RETOMAR-60 §4): (1) public.crear_contrato transformada desde el texto vivo (guarda md5 de prod);
-- (2) trigger nuevo en public.perfiles. TODO detrás de la bandera resolver_en_puertas: apagada = byte a byte / inerte.
--
-- QUE:
--   * public.crear_contrato: con la bandera ENCENDIDA y el cliente activo, reconoce a la persona
--     (private.asegurar_identidad_perfil) ANTES de su FOR SHARE: jerarquía -> documento -> identidad -> perfil.
--     Sin documento válido o con documento de otra persona reconocida -> P0409 (fail-closed). OFF: idéntica.
--   * trg_perfiles_zz_documento_protegido (BEFORE UPDATE OF dni, tipo_documento): con la bandera encendida, el
--     documento de un perfil ENLAZADO a una identidad no fusionada solo cambia bajo crm.correccion_documento=on
--     (la fija crm.corregir_documento_inversionista_fn, b5). Mismo documento con otro formato: pasa. OFF: inerte.
--   * Colaboradores y registros del Portal: FUERA de la identidad (decisión de Miguel): nada que construir.
-- Reversa: scripts/rollback-f2b-e4.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_e4_public_contrato_y_candado'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.asegurar_identidad_perfil(uuid,text)') is null
     or to_regprocedure('crm.corregir_documento_inversionista_fn(uuid,text,text,text,uuid)') is null then
    raise exception 'F2.b E4: falta b3 (20260905100000) o b5 (20260905120000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b E4: la bandera resolver_en_puertas está ENCENDIDA; este lote aterriza apagado';
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_h from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb';
  if v_h is null then
    raise exception 'F2.b E4: falta public.crear_contrato(jsonb,jsonb)';
  end if;
  if v_h is distinct from '{H_PROD}' and v_h is distinct from '{H_NEW}' then
    raise exception 'F2.b E4: public.crear_contrato no es ni el texto vivo de producción ni el de E4 (%)', v_h;
  end if;
end
$guard$;

-- ============================================================================
-- 1. public.crear_contrato reconoce a la persona (rama ON; OFF byte a byte)
-- ============================================================================
{cc}
;

{TRIGGER}
do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid)='p_contrato jsonb, p_cronograma jsonb') is distinct from '{H_NEW}' then
    raise exception 'POSTFLIGHT E4: public.crear_contrato no quedó byte a byte como la genera gen-e4.py';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido' and not tgisinternal) then
    raise exception 'POSTFLIGHT E4: falta el trigger del candado';
  end if;
  if has_function_privilege('anon', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or has_function_privilege('service_role', 'private.trg_perfiles_documento_protegido()', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'private.trg_perfiles_documento_protegido()'::regprocedure and a.grantee = 0) then
    raise exception 'POSTFLIGHT E4: grants indebidos en la función del trigger';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT E4: la bandera quedó encendida';
  end if;
  raise notice 'F2.b E4 OK: crear_contrato reconoce a la persona (ON) y el documento del Portal queda bajo candado (ON). Bandera APAGADA.';
end
$post$;
commit;
"""
(W/'migrations'/'20260905140000_crm_f2b_e4_contrato_reconoce_persona_y_candado_documento.sql').write_text(mig, encoding='utf-8')

rb = f"""-- ============================================================================
-- REVERSA de F2.b E4 (20260905140000): restaura public.crear_contrato byte a byte (md5 de prod) y suelta el candado.
-- Se NIEGA si la bandera está encendida. Repetible dos veces.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_e4_reversa'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA E4: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
drop trigger if exists trg_perfiles_zz_documento_protegido on public.perfiles;
drop function if exists private.trg_perfiles_documento_protegido();

{cc_prev}
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='crear_contrato' and pg_get_function_identity_arguments(p.oid)='p_contrato jsonb, p_cronograma jsonb') is distinct from '{H_PROD}' then
    raise exception 'REVERSA E4: public.crear_contrato no volvió byte a byte al vivo de producción';
  end if;
  if exists (select 1 from pg_trigger where tgrelid='public.perfiles'::regclass and tgname='trg_perfiles_zz_documento_protegido')
     or to_regprocedure('private.trg_perfiles_documento_protegido()') is not null then
    raise exception 'REVERSA E4: quedó el candado';
  end if;
  raise notice 'REVERSA F2.b E4 OK';
end
$post$;
commit;
"""
(W/'scripts'/'rollback-f2b-e4.sql').write_text(rb, encoding='utf-8')
reg = "-- REGISTRO en supabase_migrations.schema_migrations de F2.b E4. `db query --linked --file` NO registra: correr DESPUÉS de aplicar. Idempotente.\nbegin;\ninsert into supabase_migrations.schema_migrations (version, name, statements)\nvalues ('20260905140000', 'crm_f2b_e4_contrato_reconoce_persona_y_candado_documento', array[$m$" + mig + "$m$])\non conflict (version) do nothing;\ncommit;\n"
(W/'scripts'/'registrar-f2b-e4.sql').write_text(reg, encoding='utf-8')
print('E4 migración', len(mig.splitlines()), 'líneas; reversa', len(rb.splitlines()), '; md5 prod', H_PROD, 'md5 E4', H_NEW)
