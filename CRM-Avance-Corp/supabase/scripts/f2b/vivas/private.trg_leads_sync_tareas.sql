CREATE OR REPLACE FUNCTION private.trg_leads_sync_tareas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'private', 'public'
AS $function$
declare
  -- «Quien lo enciende, lo apaga» — el mismo invariante que sostiene
  -- private.retroceso_por_anular_reunion. Apagar a ciegas dejaría a un llamador
  -- externo sin su flag a media operación. Hoy es inalcanzable (los tres
  -- escritores de crm.avance_auto mueven la etapa, nunca la tenencia, así que
  -- no llegan hasta aquí), pero el contrato no debe depender de eso.
  v_avance_previo text := coalesce(current_setting('crm.avance_auto', true), 'off');
begin
  if (new.vendedor_id is distinct from old.vendedor_id)
     or (new.asignado_supervisor_id is distinct from old.asignado_supervisor_id) then
    if new.vendedor_id is null and new.asignado_supervisor_id is null then
      -- RE-ENCOLADO (2026-08-09, opción B de Miguel): el lead vuelve a la cola
      -- global y se queda SIN dueño. Espejar esa tenencia nula sobre la tarea
      -- pendiente disparaba 23514 en trg_tareas_destino_efectivo y abortaba el
      -- re-encolado entero. Se cancela por sistema, igual que en
      -- convertido/descartado; la tarea conserva su bandeja anterior como
      -- historia y `cancelada_por` queda sellado en 'sistema'.
      perform set_config('crm.cancela_sistema', 'on', true);
      update crm.tareas t
         set estado = 'cancelada'
       where t.lead_id = new.id and t.estado = 'pendiente';
      perform set_config('crm.cancela_sistema', 'off', true);

      -- Y el lead no puede volver a la cola SOSTENIENDO una reunión que se
      -- acaba de cancelar: sería el «hecho falso más caro» de la doctrina de
      -- 20260726151751. Misma regla que anular una reunión —`contactado` si hay
      -- contacto en el ciclo, `nuevo` si no— porque
      -- private.retroceso_por_anular_reunion no sirve aquí: solo la llaman las
      -- RPC humanas y exige tenencia no nula, que a esta altura ya es NULL.
      -- `crm.avance_auto` hace que trg_leads_cambio_etapa lo registre como
      -- automatico en vez de imputárselo a la persona que re-encoló.
      --
      -- DOS CASOS QUE A PROPOSITO NO RETROCEDEN (auditor-rls, 2026-08-09):
      --  · si YA hubo `reunion_realizada` en el ciclo, la etapa se sostiene en
      --    un hecho verdadero y la doctrina manda conservarla. Queda el residuo
      --    de que el lead llega a la cola global en `reunion_agendada` sin cita
      --    viva; cambiarlo seria cambiar la doctrina, y eso pasa por Miguel.
      --  · un lead YA inactivo que se re-encola despues (solo alcanzable por
      --    service_role sobre un soft-borrado): el filtro `l.activo = true`
      --    lo deja quieto, igual que en anular reunion.
      if new.etapa = 'reunion_agendada'
         and new.activo = true
         and not exists (
           select 1
           from crm.actividades a
           where a.lead_id = new.id
             and a.tipo = 'reunion_realizada'
             and a.creado_en >= private.inicio_ciclo_lead(new.id)
         ) then
        perform set_config('crm.avance_auto', 'on', true);
        update crm.leads l
           set etapa = case
                 when exists (
                   select 1
                   from crm.actividades a
                   where a.lead_id = l.id
                     and a.tipo in ('llamada_realizada','llamada_no_contestada',
                                    'whatsapp_enviado','whatsapp_recibido',
                                    'reunion_realizada')
                     and a.creado_en >= private.inicio_ciclo_lead(l.id)
                 ) then 'contactado'
                 else 'nuevo'
               end
         where l.id = new.id
           and l.activo = true
           and l.etapa = 'reunion_agendada';
        perform set_config('crm.avance_auto', v_avance_previo, true);
      end if;
    else
      -- Reasignacion / reparto de parkeado: propaga tenencia a las PENDIENTES.
      -- Cubre bajar a un vendedor, subir a la bandeja del supervisor y cambiar
      -- de bandeja. La tarea SIGUE al lead; no muere.
      update crm.tareas t
         set vendedor_id = new.vendedor_id,
             asignado_supervisor_id = new.asignado_supervisor_id
       where t.lead_id = new.id and t.estado = 'pendiente';
    end if;
  end if;
  -- Cierre o soft-delete del lead: cancela las pendientes. Esto NO es gestión
  -- del asesor, por eso va sellado como sistema.
  if (new.etapa in ('convertido','descartado') and old.etapa not in ('convertido','descartado'))
     or (old.activo = true and new.activo = false) then
    perform set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.lead_id = new.id and t.estado = 'pendiente';
    perform set_config('crm.cancela_sistema', 'off', true);
  end if;
  return null;
end;
$function$

