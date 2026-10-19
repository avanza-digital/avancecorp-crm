CREATE OR REPLACE FUNCTION private.trg_tareas_before_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_op      boolean := coalesce(current_setting('crm.op_tarea', true), 'off') = 'on';
  v_sistema boolean := coalesce(current_setting('crm.cancela_sistema', true), 'off') = 'on';
  v_uid     uuid    := (select auth.uid());
  v_asesor  boolean;
  v_cambio_vencimiento boolean;
begin
  v_cambio_vencimiento := new.vence_en is distinct from old.vence_en;

  if old.estado <> 'pendiente' then
    raise exception 'La tarea ya esta cerrada; una reunion reprogramada conserva su historia'
      using errcode = '22023';
  end if;
  if new.estado in ('completada','no_show','reprogramada') and not v_op then
    raise exception 'Cerrar o reprogramar una reunion va por la RPC de agenda'
      using errcode = '22023';
  end if;
  if new.estado = 'cancelada' and not v_op and not v_sistema and v_uid is not null then
    raise exception 'Anular una tarea va por crm.cerrar_tarea()'
      using errcode = '22023';
  end if;
  if new.resultado_actividad_id is distinct from old.resultado_actividad_id and not v_op then
    raise exception 'El resultado lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if (
    new.resultado_reunion is distinct from old.resultado_reunion
    or new.motivo_no_realizada is distinct from old.motivo_no_realizada
    or new.detalle_cierre_reunion is distinct from old.detalle_cierre_reunion
  ) and not v_op then
    raise exception 'El resultado de la reunion lo escribe la RPC de cierre'
      using errcode = '22023';
  end if;
  if old.tipo = 'reunion' and v_cambio_vencimiento and not v_op then
    raise exception 'Reprogramar una reunion va por crm.reprogramar_reunion()'
      using errcode = '22023';
  end if;

  if new.estado = 'cancelada' then
    v_asesor := (not v_sistema) and v_op and v_uid is not null;
    new.cancelada_por    := case when v_asesor then 'asesor' else 'sistema' end;
    new.cancelada_por_id := case when v_asesor then v_uid else null end;
  else
    new.cancelada_por    := old.cancelada_por;
    new.cancelada_por_id := old.cancelada_por_id;
  end if;

  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.lead_id := old.lead_id;
  new.perfil_id := old.perfil_id;
  new.reagendada_de := old.reagendada_de;
  new.tipo := old.tipo;
  new.modalidad_reunion := old.modalidad_reunion;
  new.ubicacion_reunion := old.ubicacion_reunion;
  new.enlace_reunion := old.enlace_reunion;

  if v_cambio_vencimiento then
    new.reprogramaciones := old.reprogramaciones + 1;
  else
    new.reprogramaciones := old.reprogramaciones;
  end if;
  return new;
end;
$function$
