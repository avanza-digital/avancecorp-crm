-- ============================================================================
-- REVERSA de «la eliminación de contrato queda auditada a nombre del actor» (20260905233000):
-- restaura crm.contrato_eliminacion_finalizar byte a byte al functiondef VIVO de producción
-- (md5 8e78cb04c7c5b6d561cd3c6c15b7f270) y desregistra la versión. Repetible. Tras la reversa el DELETE vuelve a quedar
-- sin actor cuando llama service_role (el estado anterior).
-- ============================================================================
begin;
set local lock_timeout = '5s';
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
    raise;
  end;
  perform set_config('crm.contrato_pdf_eliminacion_autorizada', '', true);

  return jsonb_build_object(
    'ok', true,
    'contrato_id', p_contrato_id,
    'objetos_eliminados', v_objetos
  );
end;
$function$
;

delete from supabase_migrations.schema_migrations where version = '20260905233000';

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
  if v_h is distinct from '8e78cb04c7c5b6d561cd3c6c15b7f270' then
    raise exception 'POSTFLIGHT REVERSA: el texto restaurado no es el vivo de producción (%)', v_h;
  end if;
  if exists (select 1 from supabase_migrations.schema_migrations where version = '20260905233000') then
    raise exception 'POSTFLIGHT REVERSA: la versión 20260905233000 sigue registrada';
  end if;
end
$post$;

commit;

select 'REVERSA_ELIMINACION_AUDITADA_OK' as resultado,
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'contrato_eliminacion_finalizar'
           and pg_get_function_identity_arguments(p.oid) = 'p_contrato_id uuid, p_token uuid, p_actor_id uuid') as huella;
