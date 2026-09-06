#!/usr/bin/env python3
# Genera la migración «la eliminación de contrato queda auditada a nombre del actor» a partir del
# functiondef VIVO de producción (vivas/crm.contrato_eliminacion_finalizar.functiondef.sql, huellas
# en huellas-prod.txt). Emite migración + reversa + registro con guardas por md5(pg_get_functiondef)
# y ACL exacta (metodología m2 del auditor-rls, 05/09/2026).
# Uso: python3 gen-eliminacion-atribuida.py <dir scripts/eliminacion> <dir supabase>
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
FN = 'crm.contrato_eliminacion_finalizar'
SIG = 'crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)'
ARGS = 'p_contrato_id uuid, p_token uuid, p_actor_id uuid'
ACL = '{postgres=X/postgres,service_role=X/postgres}'
viva = (S / 'vivas' / f'{FN}.functiondef.sql').read_text(encoding='utf-8')
assert md5(viva) == prod[FN]['functiondef'], 'el functiondef vivo no coincide con huellas-prod.txt'
H_PROD = prod[FN]['functiondef']

# ── La transformación: la claim del actor rodea los DELETE, con la misma técnica y la misma
#    restauración que private.poder_eliminar_contrato_como (precedente vivo en producción).
nuevo = viva
nuevo = rep(nuevo, """declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos integer;
begin
""", """declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos integer;
  -- Claim que había al entrar (NULL bajo service_role): se restaura al salir, como en
  -- private.poder_eliminar_contrato_como.
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
begin
""")
nuevo = rep(nuevo, """  v_objetos := jsonb_array_length(v_eliminacion.objetos);

  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada', p_contrato_id::text, true
  );
""", """  v_objetos := jsonb_array_length(v_eliminacion.objetos);

  -- El DELETE queda auditado a nombre del actor que preparó la eliminación (ya validado
  -- arriba por token + solicitado_por), aunque quien llame sea service_role —la edge del
  -- botón «Eliminar contrato» de Gerencia—: public.log_audit_change lee auth.uid(), que en
  -- esta base resuelve request.jwt.claim.sub. Sin esto el rastro quedaba con usuario NULL
  -- (medido en producción el 05/09/2026). Local a la transacción y restaurado al salir.
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada', p_contrato_id::text, true
  );
""")
nuevo = rep(nuevo, """  exception when others then
    perform set_config(
      'crm.contrato_pdf_eliminacion_autorizada', '', true
    );
    raise;
  end;
""", """  exception when others then
    perform set_config(
      'crm.contrato_pdf_eliminacion_autorizada', '', true
    );
    perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);
    raise;
  end;
""")
nuevo = rep(nuevo, """  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);

  return jsonb_build_object(
""", """  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);

  return jsonb_build_object(
""")
# Cordura: 1 lectura del valor previo + 3 set_config (fijar, restaurar en el handler, restaurar al salir).
assert nuevo.count("current_setting('request.jwt.claim.sub'") == 1, "lectura previa"
assert nuevo.count("set_config('request.jwt.claim.sub'") == 3, nuevo.count("set_config('request.jwt.claim.sub'")
H_NEW = md5(nuevo)
assert H_NEW != H_PROD

VERSION, NOMBRE = '20260905233000', 'crm_eliminacion_contrato_auditada_al_actor'
LOCK = "select pg_advisory_xact_lock(hashtext('crm_eliminacion_contrato_auditada_al_actor'));"
TAG = 'ELIMINACION AUDITADA'

# Identidad de la puerta por functiondef completo (cabecera incluida) + dueño/DEFINER/search_path + ACL EXACTA.
GUARD = f"""  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
    and pg_get_function_identity_arguments(p.oid) = '{ARGS}';
  if v_h is null then
    raise exception '{TAG}: falta {SIG}';
  end if;
  if v_h is distinct from '{H_PROD}' and v_h is distinct from '{H_NEW}' then
    raise exception '{TAG}: {SIG} no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
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
-- CRM · LA ELIMINACIÓN DE CONTRATO QUEDA AUDITADA A NOMBRE DEL ACTOR (crm.contrato_eliminacion_finalizar)
-- ============================================================================
--
-- QUÉ PASÓ (05/09/2026, medido en producción). El botón «Eliminar contrato» de Gerencia borra por
-- la puerta oficial (contrato_eliminacion_preparar + finalizar), pero su edge la llama con
-- service_role: dentro, auth.uid() es NULL y public.log_audit_change deja el DELETE de
-- public.contratos SIN actor (usuario_id NULL). Se vio en el contrato 2026-01-000247 borrado a
-- las 17:03:24Z: la puerta recibe p_actor_id y lo valida (token + solicitado_por), pero no se lo
-- cuenta a la auditoría. El único rastro del actor vivía en private.contrato_eliminaciones, que
-- la propia puerta borra al finalizar.
--
-- QUÉ HACE. finalizar fija request.jwt.claim.sub = p_actor_id (local a la transacción) DESPUÉS de
-- validar el token y ANTES de los DELETE, y lo restaura al valor previo al salir (también en el
-- handler de excepción). Así auth.uid() —lo que lee log_audit_change— resuelve al actor y el
-- DELETE queda a su nombre, venga de la edge (service_role) o de un SQL como postgres. Es la
-- MISMA técnica y la misma restauración que ya usa en producción private.poder_eliminar_contrato_como.
--
-- QUÉ MÁS CAMBIA CON LA CLAIM (auditor-rls, 05/09). Dentro de la ventana, auth.uid() es el actor para
-- TODO lo que dispara el DELETE: log_audit_change en public.contratos y en las cascadas
-- (cronograma_pagos, contrato_titulares), private.log_audit_crm en crm.contrato_cuentas_pago,
-- crm.operaciones_cartera y crm.leads (SET NULL de contrato_id): todo ese rastro queda a nombre del
-- actor, que es el efecto deseado. Y hay UN cambio de comportamiento, acotado y en la dirección
-- correcta: si el contrato borrado es el NUEVO de una RENOVACIÓN, el BEFORE DELETE
-- trg_contratos_05_restaurar_operacion restaura el ORIGEN con dos UPDATE anidados: sus cuotas
-- 'trasladado' (cronograma_pagos) y su cabecera (estado, renovado_a_id/cerrado_en/cerrado_por a
-- null). Los dos pasan por guards del portal que leen auth.uid() vía es_superadmin():
-- public.proteger_cuotas_contrato_cerrado (frena cuotas de un contrato 'renovado' salvo superadmin)
-- y public.proteger_campos_inmutables (re-congela esas tres columnas salvo superadmin). Hoy, con
-- claim NULL, ningún actor es superadmin: la restauración falla en el primer guard y el DELETE
-- muere con P0001 «El contrato está cerrado (renovado): sus cuotas no se pueden modificar» —el botón
-- de Gerencia NO puede borrar una renovación, para nadie—. Con la claim del actor: un SUPERADMIN pasa
-- ambos guards, el origen se restaura de verdad y el borrado funciona (la intención del trigger
-- restaurador); un ADMIN queda exactamente como hoy (P0001). Ningún otro trigger del camino DELETE
-- lee auth.uid() (bloquear_fila_contrato_pdf, proteger_contrato_documental, el propio
-- restaurar_operacion). La autorización de finalizar sigue siendo el token + solicitado_por =
-- p_actor_id, intacta. El oráculo (caso E) mide las dos ramas, admin (P0001) y superadmin (restaura).
--
-- QUÉ NO TOCA. Ni preparar (no muta nada auditado: su INSERT en private.contrato_eliminaciones no
-- tiene trigger de auditoría) ni la firma, el tipo de retorno, el dueño, DEFINER, search_path ni
-- la ACL {ACL} de finalizar. Sin DROP. Nada de public.
--
-- IDENTIDAD DE LA PUERTA (metodología m2 del auditor-rls): guardas y postflight fijan
-- md5(pg_get_functiondef(oid)) —cabecera incluida—, dueño/DEFINER/search_path por IGUALDAD y la
-- ACL EXACTA; no solo md5(prosrc). Vivo {H_PROD} → nuevo {H_NEW}.
--
-- Generada por scripts/eliminacion/gen-eliminacion-atribuida.py desde
-- scripts/eliminacion/vivas/{FN}.functiondef.sql. Reversa: scripts/rollback-eliminacion-atribuida.sql.
-- Registro: scripts/registrar-eliminacion-atribuida.sql. Oráculo: scripts/oraculo-eliminacion-atribuida.sh.
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

select 'ELIMINACION_AUDITADA_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
           and pg_get_function_identity_arguments(p.oid) = '{ARGS}') as huella;
"""

rb = f"""-- ============================================================================
-- REVERSA de «la eliminación de contrato queda auditada a nombre del actor» ({VERSION}):
-- restaura crm.contrato_eliminacion_finalizar byte a byte al functiondef VIVO de producción
-- (md5 {H_PROD}) y desregistra la versión. Repetible. Tras la reversa el DELETE vuelve a quedar
-- sin actor cuando llama service_role (el estado anterior).
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
    raise exception 'POSTFLIGHT REVERSA: el texto restaurado no es el vivo de producción (%)', v_h;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '{VERSION}') then
    raise exception 'POSTFLIGHT REVERSA: la versión {VERSION} sigue registrada';
  end if;
end
$post$;

commit;

select 'REVERSA_ELIMINACION_AUDITADA_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
           and pg_get_function_identity_arguments(p.oid) = '{ARGS}') as huella;
"""

assert '$m$' not in mig
reg = f"""-- REGISTRO en supabase_migrations.schema_migrations de «la eliminación de contrato queda auditada al actor».
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente; se niega si la migración no está aplicada o si la versión ya está registrada con OTRO contenido.
-- Toma el MISMO candado que la migración y la reversa: un registro y una reversa concurrentes se serializan.
begin;
set local lock_timeout = '5s';
{LOCK}
do $chk$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
         and pg_get_function_identity_arguments(p.oid) = '{ARGS}') is distinct from '{H_NEW}' then
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
select 'REGISTRO_ELIMINACION_AUDITADA_OK' as resultado, version, name, md5(statements[1]) as huella_archivo
from supabase_migrations.schema_migrations where version = '{VERSION}';
"""

(W / 'migrations' / f'{VERSION}_{NOMBRE}.sql').write_text(mig, encoding='utf-8')
(W / 'scripts' / 'rollback-eliminacion-atribuida.sql').write_text(rb, encoding='utf-8')
(W / 'scripts' / 'registrar-eliminacion-atribuida.sql').write_text(reg, encoding='utf-8')
(S / 'huellas-generadas.txt').write_text(
    f"{FN} functiondef PROD  {H_PROD}\n"
    f"{FN} functiondef NUEVO {H_NEW}\n"
    f"migracion {VERSION} md5(archivo) {md5(mig)}\n", encoding='utf-8')
print(f"PROD  {H_PROD}\nNUEVO {H_NEW}\nmig   {md5(mig)}")
