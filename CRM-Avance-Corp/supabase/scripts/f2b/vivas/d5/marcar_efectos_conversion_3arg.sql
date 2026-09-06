CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid, p_claim_id uuid, p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_loc record;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode = '42501';
  end if;
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token)
     or (v_loc.estado->>'lead_id')::uuid is distinct from p_lead_id then
    raise exception 'Saga: claim o token inválidos para este lead' using errcode = '42501';
  end if;
  -- La reserva de este lead debe ser de este claim y de su identidad (Codex E2 #5).
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead no corresponde a este claim' using errcode = 'P0409';
  end if;
  -- F2.b [D-13]: los documentos vigentes de la persona ANTES de su lock (orden documento -> persona, el de la reserva, la toma
  -- y la fusión): una toma/reapertura por ese documento en vuelo termina antes o después de este sellado, nunca en medio.
  perform private.identidad_bloquear_documentos_de(array[v_loc.inversionista_id]);
  -- Veto revalidado bajo el lock de la identidad, ANTES del punto de no retorno (Codex E2 #11).
  perform 1 from crm.inversionistas i where i.id = v_loc.inversionista_id for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona del claim pudo fusionarse: reintentar (la fusión exige claims terminales).
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.estado = 'fusionado') then
    raise exception 'La persona de este claim fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
  end if;
  if exists (select 1 from crm.inversionistas i where i.id = v_loc.inversionista_id and i.no_contactar) then
    raise exception 'La persona tiene la restricción «No insistir»: no se convierte' using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (Codex #4, auditor v3 M1): el lead FOR SHARE tras la persona y ANTES de la reserva (orden persona -> lead ->
  -- reserva, el mismo de la reserva por persona, la conversión coop y la fusión: sin arista nueva).
  perform 1 from crm.leads l where l.id = p_lead_id for share;
  -- F2.b [D-13] (Codex #5): la pareja (lead, claim, persona) se revalida bajo el lock de la RESERVA: tras esperar, otra reserva
  -- del mismo lead para otra persona no se sella con este claim.
  perform 1 from crm.conversion_reservas r where r.lead_id = p_lead_id for update;
  if not exists (select 1 from crm.conversion_reservas r
                  where r.lead_id = p_lead_id and r.claim_id = p_claim_id and r.inversionista_id = v_loc.inversionista_id) then
    raise exception 'La reserva de este lead cambió mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex v3 B3): el token se relee tras los locks: una reanudación de la reserva mientras se esperaba rota el
  -- token del mismo claim, y esa ejecución vieja no debe autorizar efectos.
  perform 1 from crm.multiempresa_idempotencia m where m.clave = v_loc.clave for share;   -- orden reserva -> claim (b4)
  select * into v_loc from private.saga_auth_localizar(p_claim_id);
  if not found or v_loc.estado->>'token_hash' is distinct from private.saga_token_hash(p_token) then
    raise exception 'El claim cambió (token rotado) mientras se sellaba; vuelve a reservar' using errcode = '40001';
  end if;
  -- F2.b [D-13] (Codex #4): el lead debe seguir vivo y sin otra persona (una conversión directa para otra persona, o un
  -- descarte, mientras la reserva esperaba, no se sella).
  if not exists (select 1 from crm.leads l where l.id = p_lead_id and l.activo
                  and l.etapa not in ('convertido', 'descartado')
                  and (l.inversionista_id is null or private.inversionista_canonica(l.inversionista_id) = v_loc.inversionista_id)
                  and (l.dni is null or private.inversionista_por_documento('DNI', l.dni) = v_loc.inversionista_id)) then   -- Codex v3 B2
    raise exception 'El lead ya no está disponible para esta conversión (convertido, descartado, con otro documento o de otra persona): no se sella'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1/#3): «un solo lead» revalidado bajo el lock de la persona ANTES del punto de no retorno, contando
  -- enlace, puente y sueltos vivos con su documento: un lead de esta persona nacido, reabierto o tomado mientras la reserva
  -- esperaba (o ya vencida) no deja cuentas de portal huérfanas; Gerencia revisa o fusiona.
  if exists (select 1 from private.leads_de_personas(array[v_loc.inversionista_id]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene otro lead: no se sella la conversión (revisión o fusión de Gerencia)'
      using errcode = 'P0409';
  end if;
  return crm.marcar_efectos_conversion(p_lead_id);
end;
$function$

