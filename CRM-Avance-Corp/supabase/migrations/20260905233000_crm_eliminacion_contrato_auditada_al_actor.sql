-- ============================================================================
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
-- la ACL {postgres=X/postgres,service_role=X/postgres} de finalizar. Sin DROP. Nada de public.
--
-- IDENTIDAD DE LA PUERTA (metodología m2 del auditor-rls): guardas y postflight fijan
-- md5(pg_get_functiondef(oid)) —cabecera incluida—, dueño/DEFINER/search_path por IGUALDAD y la
-- ACL EXACTA; no solo md5(prosrc). Vivo 8e78cb04c7c5b6d561cd3c6c15b7f270 → nuevo 5e398eaff1aef4a557e7ebb31d19fcf0.
--
-- Generada por scripts/eliminacion/gen-eliminacion-atribuida.py desde
-- scripts/eliminacion/vivas/crm.contrato_eliminacion_finalizar.functiondef.sql. Reversa: scripts/rollback-eliminacion-atribuida.sql.
-- Registro: scripts/registrar-eliminacion-atribuida.sql. Oráculo: scripts/oraculo-eliminacion-atribuida.sh.
-- ============================================================================
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtext('crm_eliminacion_contrato_auditada_al_actor'));

do $guard$
declare v_h text; v_owner text; v_definer boolean; v_config text[]; v_acl text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato_id uuid, p_token uuid, p_actor_id uuid';
  if v_h is null then
    raise exception 'ELIMINACION AUDITADA: falta crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)';
  end if;
  if v_h is distinct from '8e78cb04c7c5b6d561cd3c6c15b7f270' and v_h is distinct from '5e398eaff1aef4a557e7ebb31d19fcf0' then
    raise exception 'ELIMINACION AUDITADA: crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or v_config <> array['search_path=""'] then
    raise exception 'ELIMINACION AUDITADA: crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'ELIMINACION AUDITADA: la ACL de crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) no es la viva {postgres=X/postgres,service_role=X/postgres} (%)', v_acl;
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION crm.contrato_eliminacion_finalizar(p_contrato_id uuid, p_token uuid, p_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eliminacion private.contrato_eliminaciones%rowtype;
  v_objetos integer;
  -- Claim que había al entrar (NULL bajo service_role): se restaura al salir, como en
  -- private.poder_eliminar_contrato_como.
  v_sub_anterior text := current_setting('request.jwt.claim.sub', true);
begin
  perform private.bloquear_fila_contrato_pdf(p_contrato_id);

  select * into v_eliminacion
  from private.contrato_eliminaciones e
  where e.contrato_id = p_contrato_id
    and e.token = p_token
    and e.solicitado_por = p_actor_id
  for update;
  if not found then
    raise exception 'La preparación de eliminación no existe o venció'
      using errcode = 'P0002';
  end if;
  v_objetos := jsonb_array_length(v_eliminacion.objetos);

  -- El DELETE queda auditado a nombre del actor que preparó la eliminación (ya validado
  -- arriba por token + solicitado_por), aunque quien llame sea service_role —la edge del
  -- botón «Eliminar contrato» de Gerencia—: public.log_audit_change lee auth.uid(), que en
  -- esta base resuelve request.jwt.claim.sub. Sin esto el rastro quedaba con usuario NULL
  -- (medido en producción el 05/09/2026). Local a la transacción y restaurado al salir.
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);
  perform set_config(
    'crm.contrato_pdf_eliminacion_autorizada', p_contrato_id::text, true
  );
  begin
    delete from private.contrato_pdfs p
    where p.contrato_id = p_contrato_id;
    delete from private.contrato_pdf_jobs j
    where j.contrato_id = p_contrato_id;
    delete from private.contrato_eliminaciones e
    where e.contrato_id = p_contrato_id;
    delete from public.contratos c
    where c.id = p_contrato_id;
    if not found then
      raise exception 'Contrato no encontrado' using errcode = 'P0002';
    end if;
  exception when others then
    perform set_config(
      'crm.contrato_pdf_eliminacion_autorizada', '', true
    );
    perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);
    raise;
  end;
  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);
  perform set_config('request.jwt.claim.sub', coalesce(v_sub_anterior, ''), true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'objetos_eliminados', v_objetos
  );
end;
$function$
;

do $post$
declare v_h text; v_owner text; v_definer boolean; v_config text[]; v_acl text;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef, p.proconfig, p.proacl::text
    into v_h, v_owner, v_definer, v_config, v_acl
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato_id uuid, p_token uuid, p_actor_id uuid';
  if v_h is null then
    raise exception 'ELIMINACION AUDITADA: falta crm.contrato_eliminacion_finalizar(uuid,uuid,uuid)';
  end if;
  if v_h is distinct from '8e78cb04c7c5b6d561cd3c6c15b7f270' and v_h is distinct from '5e398eaff1aef4a557e7ebb31d19fcf0' then
    raise exception 'ELIMINACION AUDITADA: crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or v_config <> array['search_path=""'] then
    raise exception 'ELIMINACION AUDITADA: crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'ELIMINACION AUDITADA: la ACL de crm.contrato_eliminacion_finalizar(uuid,uuid,uuid) no es la viva {postgres=X/postgres,service_role=X/postgres} (%)', v_acl;
  end if;
  if v_h is distinct from '5e398eaff1aef4a557e7ebb31d19fcf0' then
    raise exception 'POSTFLIGHT ELIMINACION AUDITADA: el texto instalado no es el de esta migración (%)', v_h;
  end if;
end
$post$;

commit;

select 'ELIMINACION_AUDITADA_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
           and pg_get_function_identity_arguments(p.oid) = 'p_contrato_id uuid, p_token uuid, p_actor_id uuid') as huella;
