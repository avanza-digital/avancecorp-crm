-- Una reasignación autorizada de un lead en conversión lleva consigo la persona
-- y su borrador. No transfiere inversiones confirmadas ni amplía puertas públicas.
begin;
set local lock_timeout='5s';

do $anclas$ declare a record; begin
  for a in select * from (values
    ('private.es_destino_crm_activo(uuid,text[])','9d61642c1a3f6c8e32bea882d2877362'),
    ('private.identidad_bloquear_documento(text,text)','9c08b500af7bc11aeba5e0e7d3a63330'),
    ('private.inversionista_canonica(uuid)','34702897135078893b7d3a726b0c1816'),
    ('private.leads_de_identidades(uuid[])','2421b2b78b02b8e93fd01598e2f54128'),
    ('private.leads_de_personas(uuid[])','6eded477639796c1053f0190f6decc18'),
    ('crm.reasignar_responsable_relacion_fn(uuid,uuid,text)','8d5f2dc4630ba00bf5dc26d7cbef82a8'),
    ('private.resolver_en_puertas_bajo_candado()','5f74d26262fcc83e5975672da141be63'),
    ('private.vendedor_ids_visibles(uuid)','85544c70a0920f3a7a1b5da06935f236'),
    ('private.venta_cruzada_exigir_operador(uuid)','e45df9cbce235fadb20fa207aa690a62'),
    ('private.identidad_bloquear_documentos_de(uuid[])','81dffba49b46f2defc723e53a9a96d67'),
    ('crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)','9be9925a221e64119b21e0f6a299ceb9'),
    ('private.trg_leads_bloquear_reasignacion()','76ed8317146eb5f03886f6fadfbfba16'),
    ('private.trg_leads_guard_tenencia()','b365a550c4ae06034bbb559836d668d3'),
    ('crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)','dc622b938e8d8e9777a033cfa625b11a'),
    ('private.inversion_persona_contexto_para(uuid,uuid,uuid,uuid)','dcc540a48b7f252c783f814f6a184144'),
    ('private.inversion_persona_autorizada_para(uuid,uuid,uuid)','c91e82b30558d121782f94aefab39d6e')
  ) x(firma,huella) loop
    if to_regprocedure(a.firma) is null or md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'Cambió el contrato de %: revisar antes de instalar',a.firma;
    end if;
  end loop;
end $anclas$;

-- Contrato de unicidad ya existente: no crear índices sobre datos productivos.
do $unicidad$ begin
  if not exists(select 1 from pg_index where indexrelid=to_regclass('crm.inversion_solicitud_conversion_unica')
    and indisunique and indisvalid and indrelid='crm.inversion_solicitudes'::regclass
    and pg_get_indexdef(indexrelid) = 'CREATE UNIQUE INDEX inversion_solicitud_conversion_unica ON crm.inversion_solicitudes USING btree (lead_origen_id) WHERE ((lead_origen_id IS NOT NULL) AND (estado = ANY (ARRAY[''preparada''::text, ''confirmada''::text])))') then
    raise exception 'Cambió la unicidad de la conversión por lead: revisar antes de instalar';
  end if;
end $unicidad$;

create function private.trg_leads_sincronizar_conversion()
returns trigger language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_i crm.inversionistas%rowtype;
  v_tramo crm.inversionista_responsables%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_docs text[]; v_docs_actuales text[]; v_doc text;
  v_perfil uuid; v_revision integer; v_nuevo_tramo uuid;
  v_ahora timestamptz;
  v_paso text := 'ambito';
  v_motivo text := 'Sincronización de la conversión pendiente por reasignación autorizada del lead';
begin
  -- AFTER diferido al fin de la transacción: RLS/BEFORE ya autorizaron el cambio,
  -- y las puertas compuestas (offboarding) ya trasladaron su historial canónico.
  -- El vendedor NULL representa bandeja/cola, no un nuevo responsable comercial:
  -- conserva el último tramo hasta que otra puerta entregue el lead a un analista.
  if tg_op<>'UPDATE' or new.vendedor_id is not distinct from old.vendedor_id
    or new.vendedor_id is null or new.inversionista_id is null
    or new.activo is not true or new.etapa not in ('nuevo','contactado','reunion_agendada','propuesta_enviada') then
    return null;
  end if;
  -- Puede haber varios movimientos en la misma transacción. Procesar solo el
  -- estado final: no revivir asignaciones intermedias ni dejar avisos espurios.
  if not exists(select 1 from crm.leads l where l.id=new.id and l.activo
    and l.vendedor_id=new.vendedor_id and l.inversionista_id=new.inversionista_id
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')) then
    return null;
  end if;
  -- El UPDATE ya posee el lead. NO esperar documentos/persona/solicitud con el
  -- orden invertido de la conversión: conflicto -> rollback íntegro y 40001,
  -- el código de reintento que la cartera publicada ya interpreta.
  if not pg_try_advisory_xact_lock_shared(hashtext('crm_flag_resolver_en_puertas')) then
    raise lock_not_available;
  end if;
  if not private.resolver_en_puertas_bajo_candado() then return null; end if;
  if not pg_try_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0)) then
    raise lock_not_available;
  end if;
  v_rol:=private.rol_crm(v_actor);
  if v_actor is null or v_rol is null or v_rol not in ('vendedor','supervisor','gerencia')
    or not private.es_destino_crm_activo(new.vendedor_id,array['vendedor','supervisor'])
    or not coalesce((v_rol='gerencia' or new.vendedor_id in (select private.vendedor_ids_visibles(v_actor))),false)
    or (v_rol='supervisor' and not coalesce((
      old.vendedor_id in (select private.vendedor_ids_visibles(v_actor)) or
      (old.vendedor_id is null and old.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_actor)))),false))
    -- El BEFORE anclado ya comprobó crm.toma_directa durante el UPDATE. La
    -- puerta lo restaura antes de COMMIT: aquí se revalida el destino propio.
    or (v_rol='vendedor' and new.vendedor_id is distinct from v_actor) then
    raise exception 'La sincronización requiere una reasignación autorizada en tu ámbito' using errcode='42501';
  end if;
  if new.inversionista_id is distinct from old.inversionista_id then
    raise exception 'Corrige la identidad y reasigna el lead en operaciones separadas' using errcode='P0409';
  end if;
  v_paso := 'identidad';
  select coalesce(array_agg(k order by k),'{}') into v_docs
  from (select distinct tipo_documento||':'||documento_normalizado as k
    from crm.inversionista_identificadores where inversionista_id=new.inversionista_id and estado='vigente') d;
  foreach v_doc in array v_docs loop
    -- Misma clave de private.identidad_bloquear_documento, adquisición sin espera.
    if not pg_try_advisory_xact_lock(hashtext('inv_resolver:'||split_part(v_doc,':',1)||':'||
      upper(regexp_replace(split_part(v_doc,':',2),'[^A-Za-z0-9]','','g')))) then
      raise lock_not_available;
    end if;
  end loop;
  select * into v_i from crm.inversionistas where id=new.inversionista_id for update nowait;
  if not found or v_i.estado is distinct from 'activo'
    or private.inversionista_canonica(v_i.id) is distinct from v_i.id then
    raise exception 'La identidad requiere conciliación antes de reasignar' using errcode='P0409';
  end if;
  select coalesce(array_agg(k order by k),'{}') into v_docs_actuales
  from (select distinct tipo_documento||':'||documento_normalizado as k
    from crm.inversionista_identificadores where inversionista_id=v_i.id and estado='vigente') d;
  if v_docs is distinct from v_docs_actuales then raise serialization_failure; end if;
  -- Una puerta canónica puede haber terminado ya el traslado (incluida la
  -- baja). Sin un borrador propio desalineado no queda nada que sincronizar.
  if v_i.responsable_relacion_id=new.vendedor_id and not exists(
    select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada'
      and responsable_esperado_id is distinct from new.vendedor_id) then
    return null;
  end if;
  if exists(select 1 from private.leads_de_personas(array[v_i.id]) x where x<>new.id)
    or exists(select 1 from private.leads_de_identidades(array[v_i.id]) x where x<>new.id) then
    raise exception 'La persona tiene otro lead: requiere conciliación antes de reasignar' using errcode='P0409';
  end if;
  if exists(select 1 from crm.inversiones where inversionista_id=v_i.id)
    or exists(select 1 from public.contratos where cliente_id=v_i.perfil_id)
    or exists(select 1 from crm.cierres_externos where inversionista_id=v_i.id or lead_id=new.id) then
    -- La puerta gerencial de relación actualiza la persona ANTES de los leads.
    if v_i.responsable_relacion_id=new.vendedor_id then return null; end if;
    raise exception 'La persona ya tiene inversiones: reasigna su responsable desde la ficha de persona' using errcode='P0409';
  end if;
  v_paso := 'conversion_pendiente';
  if exists(select 1 from crm.conversion_reservas where
    (lead_id=new.id or inversionista_id=v_i.id) and
    (efectos_iniciados_en is not null or expira_en>now()) for update nowait) then
    raise exception 'Hay una conversión anterior en curso: resuélvela antes de reasignar' using errcode='P0409';
  end if;
  if exists(select 1 from crm.inversion_solicitudes where inversionista_id=v_i.id and estado='preparada'
    and (lead_origen_id is distinct from new.id or puerta<>'cartera')) then
    raise exception 'La persona tiene otra solicitud pendiente: requiere conciliación antes de reasignar' using errcode='P0409';
  end if;
  select * into v_s from crm.inversion_solicitudes
    where inversionista_id=v_i.id and lead_origen_id=new.id and estado='preparada' for update nowait;
  if v_i.perfil_id is not null and v_s.id is null and v_i.responsable_relacion_id is distinct from new.vendedor_id then
    raise exception 'La persona ya tiene acceso Avance: reasigna su responsable desde su ficha' using errcode='P0409';
  end if;
  -- Si hay borrador, la revisión existente valida acceso, saga y perfil. Tomar
  -- primero SIN ESPERAR todo lo que esa puerta puede bloquear bajo el lead.
  if v_s.id is not null then
    if not pg_try_advisory_xact_lock_shared(hashtext('crm_flag_inversiones_escritura')) then raise lock_not_available; end if;
    v_perfil:=v_i.perfil_id;
    if v_s.auth_claim_id is not null then
      select * into v_saga from crm.multiempresa_idempotencia
      where clave='auth_persona:'||coalesce(v_s.auth_contexto->>'inversionista_id',v_i.id::text)
        and resultado->>'claim_id'=v_s.auth_claim_id::text for update nowait;
      if v_perfil is null and v_saga.resultado->>'auth_user_id' is not null then
        select id into v_perfil from public.perfiles where id=(v_saga.resultado->>'auth_user_id')::uuid;
      end if;
    end if;
    if v_perfil is not null then
      perform 1 from crm.tareas where perfil_id=v_perfil and estado='pendiente' order by id for update nowait;
      perform 1 from public.perfiles where id=v_perfil for update nowait;
    end if;
  end if;
  select * into v_tramo from crm.inversionista_responsables where inversionista_id=v_i.id and hasta is null for update nowait;
  if (v_i.responsable_relacion_id is null and v_tramo.id is not null)
    or (v_i.responsable_relacion_id is not null and
      (v_tramo.id is null or v_tramo.responsable_id is distinct from v_i.responsable_relacion_id)) then
    raise exception 'El historial del responsable requiere conciliación' using errcode='P0409';
  end if;
  if v_i.responsable_relacion_id is distinct from new.vendedor_id then
    v_ahora:=clock_timestamp();
    if v_tramo.id is not null then
      update crm.inversionista_responsables set hasta=v_ahora where id=v_tramo.id;
    end if;
    insert into crm.inversionista_responsables(inversionista_id,responsable_id,desde,motivo,por)
      values(v_i.id,new.vendedor_id,v_ahora,v_motivo,v_actor) returning id into v_nuevo_tramo;
    update crm.inversionistas set responsable_relacion_id=new.vendedor_id where id=v_i.id;
    insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
      values(new.id,'nota','Responsable de la conversión sincronizado con la reasignación del lead',
        jsonb_build_object('evento','reasignacion_responsable_conversion','inversionista_id',v_i.id,
          'anterior',v_i.responsable_relacion_id,'nuevo',new.vendedor_id,'tramo_id',v_nuevo_tramo),v_actor);
  end if;
  if v_s.id is not null and v_s.responsable_esperado_id is distinct from new.vendedor_id then
    v_paso := 'revision_solicitud';
    select coalesce(max(revision),0) into v_revision from crm.inversion_solicitud_revisiones where solicitud_id=v_s.id;
    -- No duplicar la escritura/revisión del borrador ni sus reglas de acceso:
    -- la puerta vigente conserva datos, hash, autoría, saga y atribución.
    perform crm.revisar_solicitud_inversion_fn(v_s.id,new.vendedor_id,v_revision,v_motivo);
  end if;
  return null;
exception when lock_not_available or serialization_failure or deadlock_detected or sqlstate 'PT409' then
  raise exception 'La reasignación coincidió con otra operación. Vuelve a intentarlo.' using errcode='40001';
when insufficient_privilege or sqlstate 'P0409' or sqlstate 'P0429' or invalid_parameter_value then
  -- La reasignación ya fue autorizada por su puerta. No convertir una regla
  -- de inversión en un veto nuevo al reparto/offboarding. Este bloque revierte
  -- TODOS los efectos de sincronización (persona, tramos, borrador y perfil),
  -- conserva el UPDATE del lead y deja la conciliación pendiente auditable.
  -- Las puertas de invertir siguen rechazando la inconsistencia: sin bypass.
  insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
    values(new.id,'nota','Asignación actualizada. Gerencia debe revisar el responsable y el borrador antes de invertir',
      jsonb_build_object('evento','reasignacion_conversion_requiere_revision',
        'inversionista_id',new.inversionista_id,'nuevo',new.vendedor_id,
        'validacion',v_paso,'codigo',sqlstate),v_actor);
  return null;
end $$;
revoke all on function private.trg_leads_sincronizar_conversion() from public,anon,authenticated,service_role;
comment on function private.trg_leads_sincronizar_conversion() is
  'Efecto atómico de una reasignación ya autorizada: persona y solicitud de conversión pendiente, con historial. Sin ejecutores API ni atribución económica.';

create constraint trigger trg_leads_zzzz_conversion_responsable after update on crm.leads
deferrable initially deferred
for each row when (new.vendedor_id is distinct from old.vendedor_id and new.vendedor_id is not null
  and new.inversionista_id is not null and new.activo
  and new.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada'))
execute function private.trg_leads_sincronizar_conversion();

do $post$ begin
  if not exists(select 1 from pg_trigger where tgrelid='crm.leads'::regclass
    and tgname='trg_leads_zzzz_conversion_responsable' and tgenabled='O' and tgdeferrable and tginitdeferred)
    or has_function_privilege('authenticated','private.trg_leads_sincronizar_conversion()','execute')
    or has_function_privilege('anon','private.trg_leads_sincronizar_conversion()','execute')
    or has_function_privilege('service_role','private.trg_leads_sincronizar_conversion()','execute') then
    raise exception 'La sincronización no quedó instalada con permisos mínimos';
  end if;
end $post$;
commit;
