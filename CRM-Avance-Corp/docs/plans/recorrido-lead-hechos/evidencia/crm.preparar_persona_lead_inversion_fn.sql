CREATE OR REPLACE FUNCTION crm.preparar_persona_lead_inversion_fn(p_lead uuid, p_tipo_documento text, p_documento text, p_nombre text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid:=(select auth.uid()); v_rol text;
  v_l crm.leads%rowtype; v_pre crm.leads%rowtype; v_i crm.inversionistas%rowtype;
  v_persona uuid; v_doc text:=upper(btrim(p_documento));
  v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads' using errcode='42501';
  end if;
  if not private.resolver_en_puertas_bajo_candado() or not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro compartido de inversiones no está habilitado' using errcode='P0409';
  end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol:=private.rol_crm(v_uid);
  select * into v_pre from crm.leads where id=p_lead and activo and
    (v_rol='gerencia' or vendedor_id in (select private.vendedor_ids_visibles(v_uid)));
  if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501'; end if;
  if length(btrim(coalesce(p_nombre,''))) not between 2 and 180
    or p_tipo_documento is null or p_tipo_documento not in ('DNI','CE','PASAPORTE')
    or v_doc is null
    or (p_tipo_documento='DNI' and v_doc !~ '^[0-9]{8}$')
    or (p_tipo_documento='CE' and v_doc !~ '^[0-9]{9,12}$')
    or (p_tipo_documento='PASAPORTE' and v_doc !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Completa el nombre y un documento válido' using errcode='22023';
  end if;
  -- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.
  if nullif(btrim(v_pre.dni),'') is not null and v_pre.dni is distinct from v_doc then
    raise exception 'El documento no coincide con el lead; corrige su identidad antes de invertir' using errcode='P0409';
  end if;
  perform private.identidad_bloquear_documento(p_tipo_documento,v_doc);
  v_persona:=private.inversionista_resolver(p_tipo_documento,v_doc,true,'conversion_inversion');
  perform private.identidad_bloquear_documentos_de(array[v_persona]);
  select * into v_i from crm.inversionistas where id=v_persona for update;
  -- NOWAIT: una reasignación que tomó antes el lead no invierte el orden de locks.
  select * into v_l from crm.leads where id=p_lead for update nowait;
  if v_l.activo is not true or not coalesce((v_rol='gerencia' or
    v_l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))),false) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
  end if;
  if v_l.dni is distinct from v_pre.dni or v_l.inversionista_id is distinct from v_pre.inversionista_id then
    raise exception 'La identidad del lead cambió; vuelve a cargarlo' using errcode='PT409';
  end if;
  -- También recupera una confirmación cuyo HTTP se perdió: no se vuelve a
  -- preparar ni se modifica la persona o el lead ya convertido.
  if v_l.etapa='convertido' and v_l.inversionista_id=v_persona and exists(
    select 1 from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada') then
    perform private.inversion_persona_autorizada(v_persona);
    return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
      'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada'));
  end if;
  if v_l.etapa in ('convertido','descartado') then
    raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
  end if;
  if v_i.estado<>'activo' or v_i.no_contactar then
    raise exception 'La persona no permite nuevas inversiones' using errcode='P0429';
  end if;
  if v_l.no_contactar then raise exception 'El lead tiene No insistir' using errcode='P0429'; end if;
  if v_l.vendedor_id is null or not exists(select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=v_l.vendedor_id and e.activo and p.activo and e.rol_crm in ('vendedor','supervisor')) then
    raise exception 'Asigna el lead a un analista activo antes de invertir' using errcode='P0409';
  end if;
  if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
    or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
      and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
    or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
    or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
    raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
  end if;
  if v_i.responsable_relacion_id is not null and v_i.responsable_relacion_id<>v_l.vendedor_id then
    raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
  end if;
  if exists(select 1 from crm.conversion_reservas r where
    (r.lead_id=p_lead or r.inversionista_id=v_persona) and
    (r.efectos_iniciados_en is not null or r.expira_en>now()) for update) then
    raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de iniciar otra solicitud' using errcode='P0409';
  end if;
  if v_i.responsable_relacion_id is null then
    if exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null) then
      raise exception 'La asignación de la persona requiere conciliación' using errcode='P0409';
    end if;
    insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por)
      values(v_persona,v_l.vendedor_id,'preparar_conversion_inversion',v_uid);
    update crm.inversionistas set responsable_relacion_id=v_l.vendedor_id where id=v_persona;
  end if;
  perform set_config('crm.op_privilegiada','on',true);
  update crm.leads set inversionista_id=v_persona,nombre_completo=btrim(p_nombre),
    dni=case when p_tipo_documento='DNI' then v_doc else dni end where id=p_lead;
  perform set_config('crm.op_privilegiada',v_config,true);
  -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
  perform private.inversion_persona_contexto(v_persona,p_lead);
  return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
    'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
      and estado in ('preparada','confirmada')));
end $function$
