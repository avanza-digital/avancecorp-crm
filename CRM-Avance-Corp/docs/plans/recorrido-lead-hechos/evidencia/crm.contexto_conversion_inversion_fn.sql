CREATE OR REPLACE FUNCTION crm.contexto_conversion_inversion_fn(p_lead uuid, p_persona uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_ctx jsonb; v_l crm.leads%rowtype; v_motivo text; v_persona uuid;
begin
  select * into v_l from crm.leads where id=p_lead and activo;
  if not found or not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
    v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
  end if;
  v_ctx:=private.inversion_persona_lectura(coalesce(p_persona,v_l.inversionista_id));
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  if private.inversionista_canonica(v_l.inversionista_id) is distinct from v_persona then
    raise exception 'El lead no corresponde a la persona consultada' using errcode='42501';
  end if;
  v_ctx:=v_ctx||jsonb_build_object('nombre',coalesce(
    (select nombre_completo from public.perfiles where id=(v_ctx->>'perfil_id')::uuid),v_l.nombre_completo));
  if v_l.etapa='convertido' and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=p_lead and estado='confirmada') then
    -- Consultar el resultado confirmado no habilita otra inversión ni exige
    -- que la persona conserve hoy la capacidad de operar.
    v_motivo:='La inversión inicial ya está confirmada.';
  else
    begin
      v_ctx:=private.inversion_contexto_lectura(v_persona,p_lead);
    exception when sqlstate 'P0409' or sqlstate 'P0429' then
      get stacked diagnostics v_motivo=message_text;
    end;
  end if;
  return jsonb_build_object(
    'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado in ('preparada','confirmada')),
    'documento_tipo',(select tipo_documento from crm.inversionista_identificadores
      where inversionista_id=v_persona and estado='vigente' and verificado
      order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1),
    'persona',jsonb_build_object(
    'inversionista_id',v_ctx->>'inversionista_id','perfil_id',v_ctx->>'perfil_id',
    'nombre',v_ctx->>'nombre','correo',v_l.correo,'telefono',v_l.telefono,
    'responsable_id',v_ctx->>'responsable_id','responsable_nombre',
      (select nombre_completo from public.perfiles where id=(v_ctx->>'responsable_id')::uuid)),
    'capacidades',jsonb_build_object('nueva_inversion',v_motivo is null,
      'motivo_no_operable',v_motivo));
end $function$
