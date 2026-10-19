CREATE OR REPLACE FUNCTION private.trg_tareas_before_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_lead crm.leads%rowtype;
  v_cliente public.perfiles%rowtype;
  v_equipo crm.equipo%rowtype;
begin
  if new.lead_id is not null then
    -- El mismo row-lock serializa alta de tarea contra cierre/reasignación. Sin
    -- él, ambos commits podían dejar la tarea en el árbol anterior.
    select * into v_lead from crm.leads where id = new.lead_id for update;
    if not found then raise exception 'El lead de la tarea no existe'; end if;
    if v_lead.activo = false or v_lead.etapa in ('convertido','descartado') then
      raise exception 'El lead está cerrado: no admite tareas nuevas';
    end if;
    new.vendedor_id := v_lead.vendedor_id;
    new.asignado_supervisor_id := v_lead.asignado_supervisor_id;
  elsif new.perfil_id is not null then
    select * into v_cliente from public.perfiles p
    where p.id = new.perfil_id and p.rol = 'cliente'
    for share;
    if not found then raise exception 'El cliente de la tarea no existe'; end if;
    if not v_cliente.activo then
      raise exception 'El cliente está inactivo: no admite tareas comerciales nuevas';
    end if;
    if v_cliente.asesor_perfil_id is null then
      raise exception 'Asigna un Analista al cliente antes de agendar una gestión';
    end if;
    select * into v_equipo from crm.equipo e
    where e.perfil_id = v_cliente.asesor_perfil_id and e.activo
    for share;
    if not found or v_equipo.rol_crm not in ('vendedor','supervisor') then
      raise exception 'El Analista de la cartera no está activo en el CRM';
    end if;
    new.vendedor_id := v_cliente.asesor_perfil_id;
    new.asignado_supervisor_id := case
      when v_equipo.rol_crm = 'vendedor' then v_equipo.supervisor_id
      else null
    end;
  end if;

  if new.estado <> 'pendiente'
     and coalesce(current_setting('crm.op_tarea', true), 'off') <> 'on' then
    raise exception 'Una tarea nace pendiente; los cierres van por una RPC de agenda'
      using errcode = '22023';
  end if;
  if new.tipo = 'reunion' then
    new.modalidad_reunion := coalesce(new.modalidad_reunion, 'sin_clasificar');
  else
    new.modalidad_reunion := null;
    new.ubicacion_reunion := null;
    new.enlace_reunion := null;
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  if new.estado = 'pendiente' then
    new.resultado_reunion := null;
    new.motivo_no_realizada := null;
    new.detalle_cierre_reunion := null;
  end if;
  new.cancelada_por := case when new.estado = 'cancelada' then 'sistema' else null end;
  new.cancelada_por_id := null;
  return new;
end;
$function$
