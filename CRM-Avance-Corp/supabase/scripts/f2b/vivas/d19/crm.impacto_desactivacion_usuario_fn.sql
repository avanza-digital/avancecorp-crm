CREATE OR REPLACE FUNCTION crm.impacto_desactivacion_usuario_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_subordinados integer;
  v_leads integer;
  v_bandeja integer;
  v_tareas integer;
  v_clientes integer;
  v_personas integer := 0;  -- F2.b [D-2]
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);  -- F2.b [D-2]
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede evaluar una baja CRM';
  end if;
  if not exists (select 1 from crm.equipo e where e.perfil_id = p_perfil_id) then
    raise exception 'Membresia CRM no encontrada';
  end if;

  select count(*)::integer into v_subordinados
  from crm.equipo e
  where e.supervisor_id = p_perfil_id and e.activo is true;

  select count(*)::integer into v_leads
  from crm.leads l
  where l.vendedor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_bandeja
  from crm.leads l
  where l.asignado_supervisor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_tareas
  from crm.tareas t
  where (t.vendedor_id = p_perfil_id
      or t.asignado_supervisor_id = p_perfil_id)
    and t.activo is true and t.estado = 'pendiente';

  select count(*)::integer into v_clientes
  from public.perfiles p
  where p.rol = 'cliente' and p.activo is true
    and p.asesor_perfil_id = p_perfil_id;

  -- F2.b [D-2]: con la identidad ENCENDIDA, las PERSONAS cuyo responsable de relación es el saliente (identidades
  -- activas con tramo abierto suyo o apuntándole) también exigen reemplazo: nadie se queda sin responsable. Con la
  -- bandera apagada la respuesta es byte a byte la de hoy (el front la valida con un esquema ESTRICTO: la clave
  -- personas_a_cargo solo aparece con ON, y el front la incorpora en el bloque 4, antes del encendido).
  if v_flag then
    select count(*)::integer into v_personas
    from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id));
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'subordinados_activos', v_subordinados,
      'leads_abiertos', v_leads,
      'leads_en_bandeja', v_bandeja,
      'tareas_pendientes', v_tareas,
      'clientes_activos', v_clientes,
      'personas_a_cargo', v_personas,
      'requiere_reemplazo',
        v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes + v_personas > 0
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id,
    'subordinados_activos', v_subordinados,
    'leads_abiertos', v_leads,
    'leads_en_bandeja', v_bandeja,
    'tareas_pendientes', v_tareas,
    'clientes_activos', v_clientes,
    'requiere_reemplazo',
      v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes > 0
  );
end;
$function$
