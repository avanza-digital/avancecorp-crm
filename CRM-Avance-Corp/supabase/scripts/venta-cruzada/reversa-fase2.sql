-- Venta cruzada · reversa de la Fase 2 (20260924032042_crm_inversion_autorizacion_core).
-- Restaura los cuatro cuerpos de antes AL BYTE (cuerpos vivos del 23/09) y retira los
-- núcleos _para y la llave. Falla cerrada si:
--   · alguna función de fases posteriores usa los núcleos o la llave (retirarlas antes);
--   · alguna de las 9 funciones ya no es exactamente la de la Fase 2 (un cambio
--     posterior se perdería en silencio).
-- El veredicto viaja como FILA al final.
begin;
set local lock_timeout = '5s';

do $pre$ declare a record; begin
  if to_regprocedure('private.inversion_persona_autorizada_para(uuid,uuid,uuid)') is null then
    raise exception 'REVERSA: la Fase 2 no está aplicada';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('crm','private','public')
               and (p.prosrc ~ 'inversion_(persona_autorizada|persona_lectura|persona_contexto|contexto_lectura)_para"?\s*\('
                    or p.prosrc ~ 'inversion_analista_por_llave"?\s*\(')
               and p.proname not in ('inversion_persona_autorizada','inversion_persona_lectura','inversion_persona_contexto',
                 'inversion_contexto_lectura','inversion_persona_autorizada_para','inversion_persona_lectura_para',
                 'inversion_persona_contexto_para','inversion_contexto_lectura_para','inversion_analista_por_llave')) then
    raise exception 'REVERSA: hay funciones de fases posteriores que usan los núcleos o la llave; retíralas antes';
  end if;
  for a in select * from (values
    ('private.inversion_analista_por_llave(uuid,uuid,uuid,uuid)','70cf015d6a3d55595ec8fd6c898dd52d'),
    ('private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid)','477d0e80266faa6add30929337f00701'),
    ('private.inversion_contexto_lectura(uuid,uuid)','7ae71408f49ecd1eb2a05ed746746dde'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)','c91e82b30558d121782f94aefab39d6e'),
    ('private.inversion_persona_autorizada(uuid)','46d4fa1e4138326e45492661fadda0b1'),
    ('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)','dcc540a48b7f252c783f814f6a184144'),
    ('private.inversion_persona_contexto(uuid,uuid)','a7ce8164838edc6b64cdc3f933c5a276'),
    ('private.inversion_persona_lectura_para(uuid,uuid,uuid)','6539960f2d9b7896e2c4083f80361f57'),
    ('private.inversion_persona_lectura(uuid)','ff8aa305cb7b265454666bff99d5552e')
  ) x(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'REVERSA: % ya no es la de la Fase 2; revisa ese cambio antes de retirar nada', a.firma;
    end if;
  end loop;
end $pre$;

-- Cuerpos de antes, tal como los devolvía pg_get_functiondef en producción el 23/09.
CREATE OR REPLACE FUNCTION private.inversion_persona_autorizada(p_persona uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_i crm.inversionistas%rowtype;
  v_docs text[];
  v_docs_actuales text[];
  v_persona uuid;
  v_global boolean;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  if not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro multiempresa todavía no está habilitado' using errcode='P0409';
  end if;
  select coalesce(activo,false) into v_global from crm.multiempresa_flags
  where nombre='inversiones_escritura';
  if not v_global then
    if not private.piloto_f8_actor_activo(v_uid) then
      raise exception 'El registro multiempresa está limitado al equipo piloto'
        using errcode='42501';
    end if;
    perform private.cartera_f5_exigir();
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol := private.rol_crm(v_uid);
  if v_rol is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  v_persona := private.inversionista_canonica(p_persona);
  v_docs := private.identidad_bloquear_documentos_de(array[v_persona]);
  select * into v_i from crm.inversionistas where id=v_persona for update;
  if not found or not coalesce((
    v_rol='gerencia' or v_i.responsable_relacion_id in (select private.vendedor_ids_visibles(v_uid))
  ),false) then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501';
  end if;
  if private.inversionista_canonica(p_persona) is distinct from v_persona then
    raise exception 'La identidad cambió mientras se esperaba; vuelve a cargar la persona' using errcode='40001';
  end if;
  select coalesce(array_agg(k order by k),'{}') into v_docs_actuales
  from (select distinct tipo_documento||':'||documento_normalizado as k
        from crm.inversionista_identificadores where inversionista_id=v_persona and estado='vigente') d;
  if v_docs is distinct from v_docs_actuales then
    raise exception 'El documento cambió durante la operación; vuelve a cargar la persona' using errcode='40001';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id);
end;
$function$;


CREATE OR REPLACE FUNCTION private.inversion_persona_lectura(p_persona uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_i crm.inversionistas%rowtype;
  v_docs text[];
  v_docs_actuales text[];
  v_persona uuid;
  v_global boolean;
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  if not private.inversiones_escritura_bajo_candado() then
    raise exception 'El registro multiempresa todavía no está habilitado' using errcode='P0409';
  end if;
  select coalesce(activo,false) into v_global from crm.multiempresa_flags
  where nombre='inversiones_escritura';
  if not v_global then
    if not private.piloto_f8_actor_activo(v_uid) then
      raise exception 'El registro multiempresa está limitado al equipo piloto'
        using errcode='42501';
    end if;
    perform private.cartera_f5_exigir();
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia',0));
  v_rol := private.rol_crm(v_uid);
  if v_rol is null or v_rol not in ('vendedor','supervisor','gerencia') then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  v_persona := private.inversionista_canonica(p_persona);
  select * into v_i from crm.inversionistas where id=v_persona;
  if not found or not coalesce((
    v_rol='gerencia' or v_i.responsable_relacion_id in (select private.vendedor_ids_visibles(v_uid))
  ),false) then
    raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501';
  end if;
  if private.inversionista_canonica(p_persona) is distinct from v_persona then
    raise exception 'La identidad cambió mientras se esperaba; vuelve a cargar la persona' using errcode='40001';
  end if;
  return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
    'responsable_id',v_i.responsable_relacion_id);
end;
$function$;


CREATE OR REPLACE FUNCTION private.inversion_persona_contexto(p_persona uuid, p_lead uuid)
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
  v_persona := (private.inversion_persona_autorizada(p_persona)->>'inversionista_id')::uuid;
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
$function$;


CREATE OR REPLACE FUNCTION private.inversion_contexto_lectura(p_persona uuid, p_lead uuid)
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
  v_persona := (private.inversion_persona_lectura(p_persona)->>'inversionista_id')::uuid;
  select * into v_i from crm.inversionistas where id=v_persona;
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
    select * into v_p from public.perfiles where id=v_i.perfil_id;
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
    select * into v_l from crm.leads where id=v_leads[1];
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
      (r.efectos_iniciados_en is not null or r.expira_en>now())) then
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
$function$;


drop function private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid);
drop function private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid);
drop function private.inversion_persona_lectura_para(uuid,uuid,uuid);
drop function private.inversion_persona_autorizada_para(uuid,uuid,uuid);
drop function private.inversion_analista_por_llave(uuid,uuid,uuid,uuid);

comment on function private.inversion_persona_autorizada(uuid) is null;
comment on function private.inversion_persona_lectura(uuid) is null;
comment on function private.inversion_persona_contexto(uuid,uuid) is null;
comment on function private.inversion_contexto_lectura(uuid,uuid) is null;

do $post$ declare a record; begin
  for a in select * from (values
    ('private.inversion_persona_autorizada(uuid)','215503bf4d84c10e0662c014dddd9780'),
    ('private.inversion_persona_lectura(uuid)','556d25a969bc1103b9a00a4943c2df35'),
    ('private.inversion_persona_contexto(uuid,uuid)','b1c3ea787df3540596c4eda98070ac2f'),
    ('private.inversion_contexto_lectura(uuid,uuid)','7634f3a511e1573140ee52d31d8c4ba3'),
    ('private.inversion_persona_contexto(uuid)','335fa43d5eed5d0d8010d9d0716483ce')
  ) x(firma, huella) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'REVERSA: % no volvió a su huella de antes', a.firma;
    end if;
    if (select proacl::text from pg_proc where oid = to_regprocedure(a.firma)) is distinct from '{postgres=X/postgres}' then
      raise exception 'REVERSA: % no volvió a sus permisos de antes', a.firma;
    end if;
  end loop;
end $post$;

commit;
select 'REVERSA_FASE2_OK' as veredicto;
