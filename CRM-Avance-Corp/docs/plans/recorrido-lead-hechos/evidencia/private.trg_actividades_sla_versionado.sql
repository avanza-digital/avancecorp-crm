CREATE OR REPLACE FUNCTION private.trg_actividades_sla_versionado()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  v_contacto boolean;
  v_evento_en timestamptz:=statement_timestamp();
begin
  if new.lead_id is null or new.tipo not in (
    'llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'
  ) then return null; end if;
  v_contacto:=new.tipo in ('llamada_realizada','whatsapp_recibido','reunion_realizada');
  perform set_config('crm.sla_writer','on',true);
  update crm.lead_sla_ciclos c set
    primera_gestion_en=coalesce(c.primera_gestion_en,v_evento_en),
    primer_contacto_en=case when v_contacto then coalesce(c.primer_contacto_en,v_evento_en)
      else c.primer_contacto_en end
  from crm.leads l
  where l.id=new.lead_id and c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
    and (c.primera_gestion_en is null or (v_contacto and c.primer_contacto_en is null));

  -- El ledger de responsabilidad conserva sus propios hitos: una transferencia
  -- posterior no reasigna el trabajo del analista anterior ni obliga a releer
  -- timestamps de actividades controlables por el payload.
  update crm.lead_asignacion_sla_hitos h set
    primera_gestion_en=coalesce(h.primera_gestion_en,v_evento_en),
    primer_contacto_en=case when v_contacto
      then coalesce(h.primer_contacto_en,v_evento_en) else h.primer_contacto_en end
  from crm.lead_asignaciones a
  where a.id=h.lead_asignacion_id and a.lead_id=new.lead_id
    and a.analista_id=new.creado_por and a.finalizado_en is null
    and v_evento_en>=a.asignado_en
    and (h.primera_gestion_en is null or (v_contacto and h.primer_contacto_en is null));
  perform set_config('crm.sla_writer','off',true);
  return null;
end;
$function$
