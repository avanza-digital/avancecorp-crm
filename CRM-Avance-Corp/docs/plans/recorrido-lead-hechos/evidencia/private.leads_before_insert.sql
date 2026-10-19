CREATE OR REPLACE FUNCTION private.leads_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Puente de productores legados: n8n conserva su recibo y su huella.
  -- No cambia la asignación, la procedencia ni la política de alta manual.
  if new.origen='formulario' and new.campania_origen='Formulario 3' then
    new.origen := 'formulario_3';
  end if;
  if new.origen='formulario_3' then
    if new.campania_origen is not null and new.campania_origen<>'Formulario 3' then
      raise exception 'El origen Formulario 3 no admite otra campaña' using errcode='22023';
    end if;
  end if;
  -- Tambien aplica a importaciones y mantenimiento: no crear nuevos Otro.
  -- B7: base_cargada solo con la valvula de la carga de bases (trg_leads_000_base_cargada_solo_puerta).
  if new.origen is null or new.origen not in ('referido','landing','formulario','formulario_3','oficina','web','campania','whatsapp','base_cargada') then
    raise exception using errcode = '22023', message = 'Selecciona un canal concreto: Landing, Formulario, Formulario 3, Referido o Walking';
  end if;
  if not v_priv then
    -- B8: el contacto de una base cargada nace DORMIDO (descartado, motivo base_cargada) solo bajo la válvula de la carga
    -- (private.bases_carga_nace_dormido, una sola definición). Cualquier otra alta sigue sin poder nacer terminal.
    if new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
       and not private.bases_carga_nace_dormido(new.origen, new.etapa, new.motivo_descarte, new.activo) then
      raise exception 'Un lead nuevo no puede nacer en estado terminal';
    end if;
    new.perfil_id := null;
    new.contrato_id := null;
    new.convertido_en := null;
  end if;
  return new;
end;
$function$
