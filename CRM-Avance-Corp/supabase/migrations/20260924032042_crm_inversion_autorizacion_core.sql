-- Venta cruzada · Fase 2: la regla de «quién puede operar a esta persona», separada
-- por dentro SIN cambiar ninguna conducta, y con UNA llave para la venta cruzada.
--
-- QUÉ HACE. Las cuatro reglas que deciden si un miembro del CRM puede registrar o
-- consultar inversiones de una persona pasan a núcleos nuevos con dos argumentos
-- más, p_solicitud y p_busqueda (LLAVES, nunca un analista suelto):
--   private.inversion_persona_autorizada_para(p_persona, p_solicitud, p_busqueda)
--   private.inversion_persona_lectura_para(p_persona, p_solicitud, p_busqueda)
--   private.inversion_persona_contexto_para(p_persona, p_lead, p_solicitud, p_busqueda)
--   private.inversion_contexto_lectura_para(p_persona, p_lead, p_solicitud, p_busqueda)
-- El ámbito de autorizada y lectura suma una sola cosa: «o la llave es de ESTA
-- persona y su analista está en mi ámbito». La llave la resuelve
-- private.inversion_analista_por_llave, siempre atada a la persona canónica:
--   · solicitud → solo una venta cruzada ('cliente_existente') de esta persona,
--     y el analista es el congelado en la solicitud (lo pone el servidor);
--   · búsqueda  → solo la llave vigente de quien pregunta
--     (private.busqueda_cliente_es_llave, la misma regla que usa la base).
-- Los contextos solo pasan las llaves a la autorización; su ámbito del LEAD no se
-- amplía, a propósito: la venta cruzada nunca entra por el lead de otro. Las
-- cuatro funciones de siempre quedan como envoltorios SIN llaves (null::uuid), y
-- sin llaves la rama nueva es siempre falsa.
--
-- POR QUÉ. Venta cruzada (decisiones D1–D7 de Miguel, 23/09): autorizar a B sobre
-- UNA persona a través de UNA solicitud o búsqueda suya, sin abrir la cartera de A.
-- La auditoría del 23/09 y Codex (F2) pidieron no parchear
-- private.inversion_persona_autorizada (12 consumidores), extraer un núcleo y
-- propagar la llave a TODAS las llamadas anidadas. La auditoría RLS de esta fase
-- pidió además que la excepción no fuera un analista suelto (abriría a cualquier
-- persona) sino una llave atada a la persona: eso es este diseño. Nadie llama
-- todavía a los núcleos con llaves: eso llega en las Fases 3 y 4.
--
-- CONDUCTA. NINGUNA cambia. Prueba: supabase/scripts/venta-cruzada/paridad-permisos.sql
-- fotografía las cuatro reglas (y la variante de un argumento del contexto) para
-- 11 actores × 11 personas × leads (1.089 casos) antes y después: fotos idénticas.
--
-- PERMISOS. Núcleos y llave nacen como las funciones de siempre: dueño postgres y
-- sin EXECUTE para public, anon, authenticated ni service_role. Los núcleos son
-- security definer con search_path vacío y lock_timeout 5s; la llave es invoker
-- (solo la llaman los núcleos).
--
-- REQUIERE. La Fase 1 (20260924005126 y 20260924005127) ya aplicada.
--
-- REVERSA. supabase/scripts/venta-cruzada/reversa-fase2.sql: restaura los cuatro
-- cuerpos de antes al byte (mismas huellas md5) y retira núcleos y llave.
begin;
set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 0. Anclas: la Fase 1 está y los cuerpos vivos son los que se transcribieron (23/09).
-- ---------------------------------------------------------------------------
do $anclas$ declare a record; begin
  if to_regprocedure('private.inversion_persona_autorizada_para(uuid,uuid,uuid)') is not null then
    raise exception 'La Fase 2 ya está aplicada';
  end if;
  if to_regprocedure('private.busqueda_cliente_es_llave(uuid,uuid,uuid)') is null
     or not exists (select 1 from information_schema.columns
                    where table_schema = 'crm' and table_name = 'inversion_solicitudes' and column_name = 'puerta') then
    raise exception 'Falta la Fase 1 (20260924005126 y 20260924005127): aplícala antes';
  end if;
  for a in select * from (values
    ('private.inversion_persona_autorizada(uuid)','215503bf4d84c10e0662c014dddd9780'),
    ('private.inversion_persona_lectura(uuid)','556d25a969bc1103b9a00a4943c2df35'),
    ('private.inversion_persona_contexto(uuid,uuid)','b1c3ea787df3540596c4eda98070ac2f'),
    ('private.inversion_contexto_lectura(uuid,uuid)','7634f3a511e1573140ee52d31d8c4ba3'),
    ('private.inversion_persona_contexto(uuid)','335fa43d5eed5d0d8010d9d0716483ce')
  ) x(firma, huella) loop
    if to_regprocedure(a.firma) is null
       or md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'La base cambió: %. Revisa el cambio antes de instalar la Fase 2.', a.firma;
    end if;
  end loop;
end $anclas$;

-- ---------------------------------------------------------------------------
-- 1. Llave, núcleos y envoltorios
-- ---------------------------------------------------------------------------
-- (a) La llave y los núcleos nuevos. Los núcleos son los cuerpos vivos del 23/09 al byte,

--     salvo la cabecera, la línea del ámbito (autorizada y lectura) y la llamada anidada

--     (contextos). El ámbito del LEAD en los contextos NO se amplía, a propósito: la venta

--     cruzada nunca entra por el lead de otro.

-- Analista de la venta cruzada por LLAVE, atada a la persona canónica:
--   solicitud: una venta cruzada de ESTA persona → su analista congelado;
--   búsqueda: la llave vigente de quien pregunta (private.busqueda_cliente_es_llave)
--             → quien pregunta.
-- Cualquier otra cosa (sin llave, las dos llaves a la vez, otra persona, una
-- solicitud de cartera) → NULL, y NULL nunca abre el ámbito.
CREATE FUNCTION private.inversion_analista_por_llave(p_persona uuid, p_solicitud uuid, p_busqueda uuid, p_actor uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY INVOKER
 SET search_path TO ''
AS $function$
  select case
    when p_persona is null or p_actor is null or (p_solicitud is not null and p_busqueda is not null) then null
    when p_solicitud is not null then (
      select s.analista_cierre_id from crm.inversion_solicitudes s
       where s.id = p_solicitud and s.puerta = 'cliente_existente'
         and private.inversionista_canonica(s.inversionista_id) = private.inversionista_canonica(p_persona))
    when private.busqueda_cliente_es_llave(p_busqueda, p_actor, p_persona) then p_actor
  end
$function$;

CREATE FUNCTION private.inversion_persona_autorizada_para(p_persona uuid, p_solicitud uuid, p_busqueda uuid)
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
    or ((p_solicitud is not null or p_busqueda is not null)
      and private.inversion_analista_por_llave(v_persona, p_solicitud, p_busqueda, v_uid)
        in (select private.vendedor_ids_visibles(v_uid)))
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

CREATE FUNCTION private.inversion_persona_lectura_para(p_persona uuid, p_solicitud uuid, p_busqueda uuid)
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
    or ((p_solicitud is not null or p_busqueda is not null)
      and private.inversion_analista_por_llave(v_persona, p_solicitud, p_busqueda, v_uid)
        in (select private.vendedor_ids_visibles(v_uid)))
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

CREATE FUNCTION private.inversion_persona_contexto_para(p_persona uuid, p_lead uuid, p_solicitud uuid, p_busqueda uuid)
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
$function$;

CREATE FUNCTION private.inversion_contexto_lectura_para(p_persona uuid, p_lead uuid, p_solicitud uuid, p_busqueda uuid)
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
  v_persona := (private.inversion_persona_lectura_para(p_persona,p_solicitud,p_busqueda)->>'inversionista_id')::uuid;
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

-- (b) Las funciones de siempre pasan a envoltorios sin llaves.

CREATE OR REPLACE FUNCTION private.inversion_persona_autorizada(p_persona uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: la regla vive en el núcleo _para; sin llaves, conducta idéntica a la anterior.
  return private.inversion_persona_autorizada_para(p_persona, null::uuid, null::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_persona_lectura(p_persona uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: la regla vive en el núcleo _para; sin llaves, conducta idéntica a la anterior.
  return private.inversion_persona_lectura_para(p_persona, null::uuid, null::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_persona_contexto(p_persona uuid, p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: la regla vive en el núcleo _para; sin llaves, conducta idéntica a la anterior.
  return private.inversion_persona_contexto_para(p_persona, p_lead, null::uuid, null::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_contexto_lectura(p_persona uuid, p_lead uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
begin
  -- Envoltorio: la regla vive en el núcleo _para; sin llaves, conducta idéntica a la anterior.
  return private.inversion_contexto_lectura_para(p_persona, p_lead, null::uuid, null::uuid);
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Permisos: iguales a los de las funciones de siempre
-- ---------------------------------------------------------------------------
revoke all on function private.inversion_analista_por_llave(uuid,uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_persona_autorizada_para(uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_persona_lectura_para(uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid) from public, anon, authenticated, service_role;
revoke all on function private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid) from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Comentarios
-- ---------------------------------------------------------------------------
comment on function private.inversion_analista_por_llave(uuid,uuid,uuid,uuid) is
  'Venta cruzada: analista que abre el ámbito por LLAVE atada a la persona canónica. Solicitud cliente_existente de esta persona → su analista congelado; búsqueda vigente de quien pregunta → quien pregunta; cualquier otra cosa → NULL (nunca abre).';
comment on function private.inversion_persona_autorizada_para(uuid,uuid,uuid) is
  'Núcleo de la autorización por persona (F4): miembro activo, banderas, candados de documento y persona, ámbito. Con llave (solicitud o búsqueda de venta cruzada de ESTA persona) el ámbito suma a su analista; sin llaves, la regla de siempre.';
comment on function private.inversion_persona_lectura_para(uuid,uuid,uuid) is
  'Núcleo de la autorización por persona sin candados de fila (lecturas). Llaves como en inversion_persona_autorizada_para.';
comment on function private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid) is
  'Núcleo del contexto operativo de una persona (estado, No insistir, responsable activo, documento verificado, perfil, lead canónico, nombre). Pasa las llaves a la autorización; el ámbito del lead NO se amplía.';
comment on function private.inversion_contexto_lectura_para(uuid,uuid,uuid,uuid) is
  'Núcleo del contexto de una persona para lecturas, sin candados de fila. Pasa las llaves a la autorización de lectura; el ámbito del lead NO se amplía.';
comment on function private.inversion_persona_autorizada(uuid) is
  'Autorización por persona de siempre: envoltorio de inversion_persona_autorizada_para sin llaves.';
comment on function private.inversion_persona_lectura(uuid) is
  'Autorización de lectura de siempre: envoltorio de inversion_persona_lectura_para sin llaves.';
comment on function private.inversion_persona_contexto(uuid,uuid) is
  'Contexto operativo de siempre: envoltorio de inversion_persona_contexto_para sin llaves.';
comment on function private.inversion_contexto_lectura(uuid,uuid) is
  'Contexto de lectura de siempre: envoltorio de inversion_contexto_lectura_para sin llaves.';

-- ---------------------------------------------------------------------------
-- 4. Postflight
-- ---------------------------------------------------------------------------
do $post$ declare f record; begin
  for f in select p.oid::regprocedure::text firma, p.prosecdef, p.proconfig, p.proacl::text acl
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'private' and p.proname in ('inversion_persona_autorizada_para','inversion_persona_lectura_para',
              'inversion_persona_contexto_para','inversion_contexto_lectura_para','inversion_persona_autorizada',
              'inversion_persona_lectura','inversion_persona_contexto','inversion_contexto_lectura') loop
    if not f.prosecdef or f.proconfig is distinct from array['search_path=""','lock_timeout=5s']
       or f.acl is distinct from '{postgres=X/postgres}' then
      raise exception 'POSTFLIGHT: % quedó con atributos o permisos distintos (definer %, config %, acl %)',
        f.firma, f.prosecdef, f.proconfig, f.acl;
    end if;
  end loop;
  if (select p.prosecdef or p.proacl::text is distinct from '{postgres=X/postgres}'
        or p.proconfig is distinct from array['search_path=""']
        from pg_proc p where p.oid = 'private.inversion_analista_por_llave(uuid,uuid,uuid,uuid)'::regprocedure) then
    raise exception 'POSTFLIGHT: la llave quedó con atributos o permisos distintos';
  end if;
  -- La variante de un argumento del contexto no se toca: sigue llamando al envoltorio.
  if md5(pg_get_functiondef('private.inversion_persona_contexto(uuid)'::regprocedure)) <> '335fa43d5eed5d0d8010d9d0716483ce' then
    raise exception 'POSTFLIGHT: cambió private.inversion_persona_contexto(uuid)';
  end if;
  -- Sin sesión, el envoltorio sigue negando con el mismo código y mensaje de siempre.
  begin
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform private.inversion_persona_autorizada(null);
    raise exception 'POSTFLIGHT: el envoltorio autorizó sin sesión';
  exception when insufficient_privilege then
    if sqlerrm <> 'No autorizado para registrar inversiones' then raise; end if;
  end;
end $post$;

commit;
