CREATE OR REPLACE FUNCTION crm.retomar_conversion_gerencia_fn(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid()); v_inv uuid; v_r crm.conversion_reservas%rowtype; v_est jsonb; v_token text; v_clave text;
begin
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia retoma una conversión' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select r.inversionista_id into v_inv from crm.conversion_reservas r where r.lead_id = p_lead_id;
  if v_inv is null then
    raise exception 'Este lead no tiene una reserva por persona' using errcode = 'P0002';
  end if;
  perform 1 from crm.inversionistas i where i.id = v_inv for update;
  select * into v_r from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if v_r.efectos_iniciados_en is null then
    raise exception 'La reserva no está sellada: basta con volver a reservar' using errcode = 'P0409';
  end if;
  v_clave := 'auth_persona:' || v_inv::text;
  select i.resultado into v_est from crm.multiempresa_idempotencia i where i.clave = v_clave for update;
  if v_est is null or v_est->>'estado' = 'enlazado' then
    raise exception 'No hay una conversión a medias que retomar' using errcode = 'P0409';
  end if;
  if (v_est->>'lead_id')::uuid is distinct from p_lead_id or v_r.claim_id is distinct from (v_est->>'claim_id')::uuid then
    raise exception 'La reserva y el claim de esta persona no corresponden a este lead' using errcode = 'P0409';
  end if;
  -- Nunca expulsa a una ejecución viva: solo pasado el tope de la reserva o con el lease del claim vencido (Codex E2 #10).
  if v_r.vence_absoluto_en > pg_catalog.now() and (v_est->>'lease_hasta')::timestamptz > pg_catalog.now() then
    raise exception 'La conversión sigue viva (reserva y claim vigentes): no hay nada que retomar todavía' using errcode = 'P0409';
  end if;
  v_token := pg_catalog.encode(extensions.gen_random_bytes(24), 'hex');
  v_est := v_est || pg_catalog.jsonb_build_object('token_hash', private.saga_token_hash(v_token), 'owner', v_uid,
    'lease_hasta', pg_catalog.now() + interval '10 minutes', 'actualizado_en', pg_catalog.now(), 'retomado_por_gerencia', true);
  update crm.multiempresa_idempotencia set resultado = v_est, version = version + 1 where clave = v_clave;
  update crm.conversion_reservas r
     set reservado_por = v_uid, reservado_en = pg_catalog.now(),
         expira_en = pg_catalog.now() + interval '5 minutes', vence_absoluto_en = pg_catalog.now() + interval '30 minutes'
   where r.lead_id = p_lead_id;
  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'inversionista_id', v_inv,
    'claim_id', (v_est->>'claim_id')::uuid, 'token', v_token, 'estado', v_est->>'estado',
    'version', (select i.version from crm.multiempresa_idempotencia i where i.clave = v_clave),
    'auth_user_id', (v_est->>'auth_user_id')::uuid, 'perfil_id', (v_est->>'perfil_id')::uuid, 'reanudar', true);
end;
$function$

