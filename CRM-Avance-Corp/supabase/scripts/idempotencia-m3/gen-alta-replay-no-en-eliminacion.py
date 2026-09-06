#!/usr/bin/env python3
# Genera la migración «el replay del alta no devuelve un contrato en eliminación» (m3 del auditor-rls) a partir
# del functiondef VIVO de producción de crm.crear_contrato_con_cuenta_pdf_v2 (la v2.1 de idempotencia ya aplicada;
# vivas/…functiondef.sql, huellas en huellas-prod.txt). Guardas por md5(pg_get_functiondef) + ACL exacta (m2).
# Uso: python3 gen-alta-replay-no-en-eliminacion.py <dir scripts/idempotencia-m3> <dir supabase>
import sys, pathlib, hashlib
S = pathlib.Path(sys.argv[1]); W = pathlib.Path(sys.argv[2])
md5 = lambda t: hashlib.md5(t.encode('utf-8')).hexdigest()
def rep(s, old, new):
    assert s.count(old) == 1, f'ancla no única ({s.count(old)}): {old[:70]!r}'
    return s.replace(old, new)
prod = {}
for l in (S / 'huellas-prod.txt').read_text(encoding='utf-8').splitlines():
    if l.strip():
        p = l.split(); prod[p[0]] = {'prosrc': p[2], 'functiondef': p[4]}
FN = 'crm.crear_contrato_con_cuenta_pdf_v2'
SIG = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'
ARGS = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb'
ACL = '{postgres=X/postgres,authenticated=X/postgres}'
viva = (S / 'vivas' / f'{FN}.functiondef.sql').read_text(encoding='utf-8')
assert md5(viva) == prod[FN]['functiondef'], 'el functiondef vivo no coincide con huellas-prod.txt'
H_PROD = prod[FN]['functiondef']

# ── m3: en la rama de replay, tras bloquear la fila del contrato y ANTES de devolverlo, la misma pregunta
#    y el mismo 55000 que hace el alta en private.crear_job_contrato_pdf_base.
nuevo = rep(viva, """      end;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
""", """      end;
      -- Eliminación PREPARADA y aún no finalizada (Gerencia pulsó «Eliminar» y la edge todavía
      -- no borró): no se devuelve como «alta recuperada» un contrato que está a punto de
      -- desaparecer. La misma pregunta y el mismo 55000 que hace el alta
      -- (private.crear_job_contrato_pdf_base); la fila ya está bloqueada, así que la
      -- respuesta es estable hasta que esta transacción termine.
      if private.contrato_en_eliminacion(v_contrato_id) then
        raise exception 'El contrato está en proceso de eliminación'
          using errcode = '55000';
      end if;
      if not private.puede_leer_contrato_pdf_como(v_contrato_id, v_actor_id) then
""")
assert nuevo.count('private.contrato_en_eliminacion(v_contrato_id)') == 1
H_NEW = md5(nuevo); assert H_NEW != H_PROD

VERSION, NOMBRE = '20260905234500', 'crm_alta_idempotente_replay_no_en_eliminacion'
# El MISMO candado que la migración/reversa/registro de idempotencia (20260905190000): misma función.
LOCK = "select pg_advisory_xact_lock(hashtext('crm_alta_contrato_idempotente'));"
TAG = 'REPLAY EN ELIMINACION'
GUARD = f"""  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = '{ARGS}';
  if v_h is null then
    raise exception '{TAG}: falta {SIG}';
  end if;
  if v_h is distinct from '{H_PROD}' and v_h is distinct from '{H_NEW}' then
    raise exception '{TAG}: {SIG} no es ni el texto vivo de producción (v2.1 de idempotencia) ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or v_config <> array['search_path=""'] then
    raise exception '{TAG}: {SIG} perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_acl is distinct from '{ACL}' then
    raise exception '{TAG}: la ACL de {SIG} no es la viva {ACL} (%)', v_acl;
  end if;
"""
DECL = "declare v_h text; v_owner text; v_definer boolean; v_config text[]; v_acl text;"

mig = f"""-- ============================================================================
-- CRM · EL REPLAY DEL ALTA NO DEVUELVE UN CONTRATO EN ELIMINACIÓN (crm.crear_contrato_con_cuenta_pdf_v2, m3)
-- ============================================================================
--
-- QUÉ. Enmienda la v2.1 de «el alta es idempotente por clave» (20260905190000, aplicada en prod el
-- 05/09/2026). Hallazgo m3 del auditor-rls: la rama de replay bloqueaba la fila del contrato y
-- comprobaba lectura, pero no preguntaba private.contrato_en_eliminacion, así que un contrato con
-- eliminación PREPARADA (Gerencia pulsó «Eliminar»; la edge aún no finalizó, o quedó a medias) se
-- devolvía como «alta recuperada» con idempotente:true. El alta nueva SÍ lo pregunta
-- (private.crear_job_contrato_pdf_base → 55000). Ventana rara (preparar y finalizar corren en la
-- misma llamada de la edge), pero real si la edge muere entre medias: la remediación del 05/09 tuvo
-- que comprobar a mano «preparación pendiente» por lo mismo.
--
-- QUÉ HACE. En la rama de replay, tras bloquear la fila (con lo que la respuesta es estable en la
-- transacción) y antes de devolver el contrato: si private.contrato_en_eliminacion(v_contrato_id)
-- → 55000 'El contrato está en proceso de eliminación', el mismo mensaje y código del alta. Nada
-- más cambia: sin clave byte a byte, replay normal, lápida P0409, huella distinta P0409, todo igual.
--
-- QUÉ NO TOCA. Firma, retorno, dueño, DEFINER, search_path, ACL {ACL}; sin DROP; nada de public;
-- ni la tabla de memoria ni crear_contrato_con_cuenta ni public.crear_contrato.
--
-- IDENTIDAD DE LA PUERTA (m2 del auditor-rls): guardas y postflight fijan md5(pg_get_functiondef(oid))
-- —cabecera incluida—, dueño/DEFINER/search_path por IGUALDAD y la ACL EXACTA. Vivo (v2.1) {H_PROD}
-- → nuevo {H_NEW}. Mismo advisory lock que 20260905190000: misma función.
--
-- ORDEN DE REVERSA: esta se revierte ANTES que 20260905190000 (su reversa exige el texto de v2.1).
--
-- Generada por scripts/idempotencia-m3/gen-alta-replay-no-en-eliminacion.py desde
-- scripts/idempotencia-m3/vivas/{FN}.functiondef.sql. Reversa: scripts/rollback-alta-replay-en-eliminacion.sql.
-- Registro: scripts/registrar-alta-replay-en-eliminacion.sql. Oráculo: scripts/oraculo-alta-replay-en-eliminacion.sh.
-- ============================================================================
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
{LOCK}

do $guard$
{DECL}
begin
{GUARD}end
$guard$;

{nuevo};

do $post$
{DECL}
begin
{GUARD}  if v_h is distinct from '{H_NEW}' then
    raise exception 'POSTFLIGHT {TAG}: el texto instalado no es el de esta migración (%)', v_h;
  end if;
end
$post$;

commit;

select 'ALTA_REPLAY_EN_ELIMINACION_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') as huella;
"""

rb = f"""-- ============================================================================
-- REVERSA de «el replay del alta no devuelve un contrato en eliminación» ({VERSION}): restaura
-- crm.crear_contrato_con_cuenta_pdf_v2 byte a byte al functiondef VIVO de producción (la v2.1 de
-- idempotencia, md5 {H_PROD}) y desregistra la versión. Repetible. Correr ANTES de la reversa de
-- 20260905190000 si hubiera que revertir también la idempotencia.
-- ============================================================================
begin;
set local lock_timeout = '5s';
{LOCK}

do $guard$
{DECL}
begin
{GUARD}end
$guard$;

{viva};

delete from supabase_migrations.schema_migrations where version = '{VERSION}';

do $post$
{DECL}
begin
{GUARD}  if v_h is distinct from '{H_PROD}' then
    raise exception 'POSTFLIGHT REVERSA: el texto restaurado no es el vivo (v2.1) de producción (%)', v_h;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '{VERSION}') then
    raise exception 'POSTFLIGHT REVERSA: la versión {VERSION} sigue registrada';
  end if;
end
$post$;

commit;

select 'REVERSA_ALTA_REPLAY_EN_ELIMINACION_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') as huella;
"""

assert '$m$' not in mig
reg = f"""-- REGISTRO en supabase_migrations.schema_migrations de «el replay del alta no devuelve un contrato en eliminación».
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente; se niega si la migración no está aplicada o si la versión ya está registrada con OTRO contenido.
-- Mismo candado que migración y reversa (y que la familia 20260905190000): un registro y una reversa concurrentes se serializan.
begin;
set local lock_timeout = '5s';
{LOCK}
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') is distinct from '{H_NEW}' then
    raise exception 'REGISTRO {TAG}: la migración {VERSION} NO está aplicada (la puerta no lleva el texto nuevo); aplica primero';
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version='{VERSION}' and coalesce(md5(statements[1]), '') <> '{md5(mig)}') then
    raise exception 'REGISTRO {TAG}: la versión {VERSION} ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('{VERSION}', '{NOMBRE}', array[$m${mig}$m$])
on conflict (version) do nothing;
commit;
select 'REGISTRO_ALTA_REPLAY_EN_ELIMINACION_OK' as resultado, version, name, md5(statements[1]) as huella_archivo
from supabase_migrations.schema_migrations where version = '{VERSION}';
"""
(W / 'migrations' / f'{VERSION}_{NOMBRE}.sql').write_text(mig, encoding='utf-8')
(W / 'scripts' / 'rollback-alta-replay-en-eliminacion.sql').write_text(rb, encoding='utf-8')
(W / 'scripts' / 'registrar-alta-replay-en-eliminacion.sql').write_text(reg, encoding='utf-8')
(S / 'huellas-generadas.txt').write_text(
    f"{FN} functiondef PROD  {H_PROD}\n{FN} functiondef NUEVO {H_NEW}\nmigracion {VERSION} md5(archivo) {md5(mig)}\n", encoding='utf-8')
print(f"PROD  {H_PROD}\nNUEVO {H_NEW}\nmig   {md5(mig)}")
