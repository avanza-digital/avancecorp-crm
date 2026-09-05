-- ============================================================================
-- REVERSA de «el alta de contrato es idempotente por clave» (20260905190000):
-- restaura crm.crear_contrato_con_cuenta_pdf_v2 byte a byte al texto VIVO de producción
-- (md5(prosrc) 68cc6c91e84061c0bdf6a62306085c14) y retira private.contrato_altas_idempotentes. Repetible.
-- Tras la reversa, una clave que viaje en p_contrato baja hasta public.crear_contrato,
-- que la ignora (solo lee sus propias claves): los clientes nuevos siguen funcionando,
-- sin la protección.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_alta_contrato_idempotente'));

do $guard$
declare v_h text; v_owner text; v_definer boolean; v_config text[];
begin
  select md5(p.prosrc), p.proowner::regrole::text, p.prosecdef, p.proconfig
    into v_h, v_owner, v_definer, v_config
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'ALTA IDEMPOTENTE: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '68cc6c91e84061c0bdf6a62306085c14' and v_h is distinct from '079d047f00d6355929615b1c49060b47' then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or not (v_config @> array['search_path=""']) then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    p_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  return v_resultado || jsonb_build_object('pdf', v_pdf);
end;
$function$;

drop table if exists private.contrato_altas_idempotentes;

do $post$
declare v_h text; v_owner text; v_definer boolean; v_config text[];
begin
  select md5(p.prosrc), p.proowner::regrole::text, p.prosecdef, p.proconfig
    into v_h, v_owner, v_definer, v_config
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'ALTA IDEMPOTENTE: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '68cc6c91e84061c0bdf6a62306085c14' and v_h is distinct from '079d047f00d6355929615b1c49060b47' then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or not (v_config @> array['search_path=""']) then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_h is distinct from '68cc6c91e84061c0bdf6a62306085c14' then
    raise exception 'POSTFLIGHT REVERSA: el texto restaurado no es el vivo de producción (%)', v_h;
  end if;
  if not has_function_privilege('authenticated', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'ALTA IDEMPOTENTE: los grants de crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no son los vivos (solo postgres y authenticated; ni anon, ni service_role, ni PUBLIC)';
  end if;
  if to_regclass('private.contrato_altas_idempotentes') is not null then
    raise exception 'POSTFLIGHT REVERSA: private.contrato_altas_idempotentes sigue existiendo';
  end if;
end
$post$;

commit;

select 'REVERSA_ALTA_IDEMPOTENTE_OK' as resultado,
       (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') as huella;
