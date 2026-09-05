CREATE OR REPLACE FUNCTION crm.marcar_efectos_conversion(p_lead_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm((select auth.uid()));
  v_ok  boolean;
  v_inv0 uuid; v_inv1 uuid;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;

  -- El tope absoluto también manda AQUÍ: si ya pasó, esta reserva no vale para
  -- sellar nada, y la edge muere antes de crear la cuenta.
  -- F2.b (b4): si la reserva es por PERSONA, se bloquea la identidad antes de sellar
  -- (orden identidad -> reserva; la conversión coop lee las reservas bajo ese mismo lock).
  select r.inversionista_id into v_inv0 from crm.conversion_reservas r where r.lead_id = p_lead_id;
  perform 1 from crm.inversionistas i
   where i.id = v_inv0
     and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false)
   for update;
  -- F2.b (b5) [E3-12]: tras esperar, la persona reservada pudo fusionarse (la reserva ya apunta a la canónica): reintentar.
  if v_inv0 is not null and coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    select r.inversionista_id into v_inv1 from crm.conversion_reservas r where r.lead_id = p_lead_id;
    if v_inv1 is distinct from v_inv0 or exists (select 1 from crm.inversionistas i where i.id = v_inv0 and i.estado = 'fusionado') then
      raise exception 'La persona de esta reserva fue fusionada mientras se sellaba; vuelve a intentarlo' using errcode = '40001';
    end if;
  end if;
  update crm.conversion_reservas r
     set efectos_iniciados_en = coalesce(r.efectos_iniciados_en, now())
   where r.lead_id = p_lead_id
     and r.reservado_por = v_uid
     and r.vence_absoluto_en > now()
     and (r.expira_en > now() or r.efectos_iniciados_en is not null)
  returning true into v_ok;

  if not coalesce(v_ok, false) then
    raise exception using
      errcode = 'P0409',
      message = 'La reserva de esta conversion ya no esta viva',
      hint    = 'Vuelve a empezar la conversion desde la ficha del lead.';
  end if;

  return jsonb_build_object('ok', true, 'lead_id', p_lead_id);
end;
$function$
