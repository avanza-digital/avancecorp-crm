CREATE OR REPLACE FUNCTION private.deshacer_descarte_implementacion(p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := (select auth.uid());
  v_ventana interval := interval '24 hours';
  v_lead    crm.leads%rowtype;
  v_veredicto jsonb;
  v_bloqueo jsonb;
  v_previo_reab text;
  v_flag_d13 boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede deshacer un descarte'
      using errcode = '42501';
  end if;

  if p_lead is null then
    raise exception 'El lead es obligatorio' using errcode = '22023';
  end if;

  -- F2.b [D-13]: candados de PERSONA antes de la fila (documento -> persona -> lead); inerte con la bandera apagada.
  v_bloqueo := private.bloquear_personas_de_leads(array[p_lead], null);
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa = 'descartado'
    and l.descartado_por = v_actor
    and l.descartado_en > (statement_timestamp() - v_ventana)
  for update;
  if not found then
    raise exception 'Solo puedes deshacer tus propios descartes de las últimas 24 horas, y solo si el lead sigue sin dueño'
      using errcode = 'P0002';
  end if;
  -- F2.b (b2): gemela de rescatar_descartes: una persona vetada no se reabre.
  if private.persona_vetada(v_lead.id) then
    raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»'
      using errcode = 'P0429';
  end if;
  -- F2.b [D-13] (auditor M1 / Codex #6): gemela de rescatar_descartes: el JUICIO único de reapertura con la identidad encendida.
  if v_flag_d13 then
    if not private.lead_dentro_de_bloqueo(v_lead.id, v_bloqueo) then
      raise exception 'El documento o la persona de este lead cambió mientras se bloqueaba; vuelve a intentarlo' using errcode = '40001';
    end if;
    v_veredicto := private.juicio_reapertura(v_lead.id, v_lead.telefono, null);
    if v_veredicto->>'estado' = 'no_contactar' then
      raise exception '%: no se puede reabrir', 'La persona tiene la restricción «No insistir»' using errcode = 'P0429';
    end if;
    if v_veredicto is not null then
      raise exception 'La persona ya es cliente o ya tiene su lead: no se puede reabrir'
        using errcode = 'P0409', detail = pg_catalog.jsonb_build_object('estado', 'ya_es_cliente', 'via', 'identidad', 'lead_id', v_lead.id)::text;
    end if;
  end if;

  v_previo_reab := coalesce(pg_catalog.current_setting('crm.reapertura_identidad', true), 'off');
  perform pg_catalog.set_config('crm.reapertura_identidad', 'on', true);
  begin
    update crm.leads
       set etapa = 'nuevo', motivo_descarte = null
     where id = p_lead and activo = true and etapa = 'descartado'
       and vendedor_id is null and asignado_supervisor_id is null;
    if not found then
      raise exception 'El descarte ya no se puede deshacer (carrera)'
        using errcode = 'P0002';
    end if;
  exception
    when unique_violation then
      raise exception 'Ya existe otro lead vivo con ese mismo teléfono o documento: no se puede reabrir'
        using errcode = '22023';
  end;

  perform pg_catalog.set_config('crm.reapertura_identidad', v_previo_reab, true);
  -- F2.b [D-13]: el lead reabierto queda ENLAZADO a su persona (como al nacer), ya bloqueada FOR SHARE.
  if v_flag_d13 and v_lead.inversionista_id is null then
    perform private.enlazar_lead_reabierto(p_lead, private.lead_persona_reabrir(p_lead));
  end if;
  select * into v_lead from crm.leads where id = p_lead;

  return jsonb_build_object(
    'lead_id', p_lead,
    'etapa', v_lead.etapa,
    'ciclo_actual', v_lead.ciclo_actual,
    'reabierto_por', v_actor,
    'reabierto_en', statement_timestamp());
end;
$function$

