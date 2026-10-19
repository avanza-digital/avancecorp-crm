CREATE OR REPLACE FUNCTION private.inversion_persona_contexto_para(p_persona uuid, p_lead uuid, p_solicitud uuid, p_busqueda uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_i crm.inversionistas%rowtype;
  v_p public.perfiles%rowtype;
  v_l crm.leads%rowtype;
  v_doc crm.inversionista_identificadores%rowtype;
  v_leads uuid[];
  v_nombre text;
  v_persona uuid;
begin
  v_persona := (private.inversion_persona_autorizada_para(p_persona,p_solicitud,p_busqueda)->>'inversionista_id')::uuid;
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if v_i.estado <> 'activo' or v_i.no_contactar then
    raise exception 'La persona no permite nuevas inversiones: revisa su estado o No insistir' using errcode='P0429';
  end if;
  if v_i.responsable_relacion_id is null or not exists (
    select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
    where e.perfil_id=v_i.responsable_relacion_id and e.activo and p.activo
      and e.rol_crm in ('vendedor','supervisor')
  ) then
    raise exception 'Asigna un responsable comercial activo antes de registrar la inversión' using errcode='P0409';
  end if;
  select * into v_doc from crm.inversionista_identificadores
  where inversionista_id=v_persona and estado='vigente' and verificado
  order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1;
  if not found then
    raise exception 'La inversión requiere un documento verificado' using errcode='P0409';
  end if;
  if v_i.perfil_id is not null then
    select * into v_p from public.perfiles where id=v_i.perfil_id for share;
    if not found or v_p.activo is not true or v_p.rol <> 'cliente' then
      raise exception 'El perfil Avance requiere revisión antes de operar' using errcode='P0409';
    end if;
    if not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El documento del perfil requiere conciliación con la persona' using errcode='P0409';
    end if;
  end if;
  select array_agg(distinct id order by id) into v_leads from (
    select l.id from crm.leads l where l.inversionista_id=v_persona
    union select il.lead_id from crm.inversionista_leads il
      where il.inversionista_id=v_persona and il.rol='canonico'
  ) l;
  if coalesce(cardinality(v_leads),0)>1 then
    raise exception 'Hay más de un lead canónico; corresponde conciliación de identidad' using errcode='P0409';
  end if;
  if cardinality(v_leads)=1 then
    -- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.
    select * into v_l from crm.leads where id=v_leads[1] for share nowait;
    if v_l.no_contactar then
      raise exception 'La persona tiene No insistir en su lead' using errcode='P0429';
    end if;
    if p_lead is null and v_l.etapa <> 'convertido' then
      raise exception 'Completa la conversión inicial antes de registrar otra inversión' using errcode='P0409';
    end if;
  end if;
  if p_lead is not null then
    if v_l.id is distinct from p_lead or v_l.activo is not true or
      not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
        v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
      raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
    end if;
    if v_l.etapa in ('convertido','descartado') then
      raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
    end if;
    if v_l.vendedor_id is distinct from v_i.responsable_relacion_id then
      raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
    end if;
    if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
      or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
      raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
    end if;
    if exists(select 1 from crm.conversion_reservas r where
      (r.lead_id=p_lead or r.inversionista_id=v_persona) and
      (r.efectos_iniciados_en is not null or r.expira_en>now()) for update nowait) then
      raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de continuar' using errcode='P0409';
    end if;
  end if;
  v_nombre := coalesce(nullif(btrim(v_p.nombre_completo),''),nullif(btrim(v_l.nombre_completo),''),
    (select ce.nombre_completo from crm.cierres_externos ce where ce.inversionista_id=v_persona order by ce.creado_en desc,ce.id desc limit 1));
  if v_nombre is null then
    raise exception 'La persona necesita un antecedente con su nombre completo' using errcode='P0409';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id,'lead_id',v_l.id,
    'documento_tipo',v_doc.tipo_documento,'documento',v_doc.documento_normalizado,'nombre',v_nombre);
end;
$function$
