CREATE OR REPLACE FUNCTION private.repartir_lead_implementacion(p_lead uuid, p_supervisor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor      uuid := (select auth.uid());
  v_lead       crm.leads%rowtype;
  v_sup_nombre text;
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads' using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios' using errcode = '22023';
  end if;

  select p.nombre_completo into v_sup_nombre
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_supervisor
    and e.rol_crm = 'supervisor' and e.activo = true and p.activo = true;
  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  for update;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  update crm.leads
     set asignado_supervisor_id = p_supervisor
   where id = p_lead and activo = true
     and vendedor_id is null and asignado_supervisor_id is null;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'repartido_en', statement_timestamp());
end;
$function$

