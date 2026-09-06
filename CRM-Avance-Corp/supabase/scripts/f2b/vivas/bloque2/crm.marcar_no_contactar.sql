CREATE OR REPLACE FUNCTION crm.marcar_no_contactar(p_lead_id uuid, p_motivo text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid  uuid := (select auth.uid());
  v_rol  text := private.rol_crm((select auth.uid()));
  v_inv  uuid;
  v_lead crm.leads%rowtype;
  v_n    integer := 0;
  v_flag boolean := coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false);
  v_dni_suelto text;
  v_suelto boolean := false;  -- F2.b (b2)
begin
  if v_uid is null or not coalesce(v_rol in ('vendedor','supervisor','gerencia'), false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- ORDEN: identidad PRIMERO (sin bloquear el lead aún), luego leads.
  -- Con bandera APAGADA la RPC actúa solo sobre el lead (como el UPDATE directo de hoy).
  select inversionista_id into v_inv from crm.leads where id = p_lead_id;
  if not v_flag then v_inv := null; end if;
  if v_flag and v_inv is null then
    -- F2.b (b2): lead suelto -> la persona se resuelve por documento exacto (no se enlaza).
    select l.dni into v_dni_suelto from crm.leads l where l.id = p_lead_id;
    perform private.identidad_bloquear_documento('DNI', v_dni_suelto);
    v_inv := private.inversionista_por_documento('DNI', v_dni_suelto);
    v_suelto := v_inv is not null;
  end if;
  if v_inv is not null then
    perform 1 from crm.inversionistas where id = v_inv for update;
  end if;

  -- F2.b (b2) [Codex E1 #2]: orden identidad -> TAREAS -> leads. crm.cerrar_tarea va
  -- tarea -> lead; cancelar las pendientes después de bloquear los leads formaría un ciclo.
  if v_flag then
    perform 1 from crm.tareas t
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv))
     order by t.id
     for update;
  end if;

  select * into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (select private.vendedor_ids_visibles(v_uid))
      or (vendedor_id is null and asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;
  -- Revalidar tras esperar: si la identidad cambió (fusión/corrección), reintentar.
  if v_flag and not v_suelto and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;
  if v_flag and v_suelto
     and (v_lead.inversionista_id is not null
          or private.inversionista_por_documento('DNI', v_lead.dni) is distinct from v_inv) then
    raise exception 'El documento del lead cambió mientras se marcaba; vuelve a intentarlo'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_inv is not null then
    update crm.inversionistas
       set no_contactar = true,
           no_contactar_en = coalesce(no_contactar_en, pg_catalog.now()),
           no_contactar_por = coalesce(no_contactar_por, v_uid)
     where id = v_inv and no_contactar = false;
    -- Todos los leads de la persona heredan el veto (id asc = orden determinista).
    for v_lead in
      select * from crm.leads where inversionista_id = v_inv order by id for update
    loop
      if not v_lead.no_contactar then
        update crm.leads set no_contactar = true where id = v_lead.id;
        v_n := v_n + 1;
      end if;
    end loop;
    -- F2.b (b2): el propio lead suelto también hereda el veto.
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    if found then v_n := v_n + 1; end if;
  else
    update crm.leads set no_contactar = true where id = p_lead_id and no_contactar = false;
    get diagnostics v_n = row_count;
  end if;
  -- F2.b (b2): con la bandera encendida se cancelan las tareas PENDIENTES de todos
  -- los leads de la persona (selladas como sistema). Levantar el veto NO las revive.
  if v_flag then
    perform pg_catalog.set_config('crm.cancela_sistema', 'on', true);
    update crm.tareas t
       set estado = 'cancelada'
     where t.estado = 'pendiente'
       and t.lead_id in (select l.id from crm.leads l
                          where l.id = p_lead_id or (v_inv is not null and l.inversionista_id = v_inv));
    perform pg_catalog.set_config('crm.cancela_sistema', 'off', true);
  end if;

  -- tipo 'nota' (el CHECK de actividades no admite un tipo nuevo; el evento va en metadata).
  -- La nota se inserta BAJO la válvula: el trigger de gestión exime la válvula del veto (F2.b b2).
  insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
  values (p_lead_id, 'nota',
          'Marcado como No contactar' || case when v_flag and v_inv is not null then ' (persona completa)' else '' end,
          pg_catalog.jsonb_build_object('evento', 'no_contactar', 'accion', 'marcar',
                                        'inversionista_id', v_inv, 'leads_afectados', v_n,
                                        'motivo', nullif(pg_catalog.btrim(coalesce(p_motivo,'')), '')),
          v_uid);
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

  return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id,
                                       'inversionista_id', v_inv, 'leads_afectados', v_n);
end;
$function$