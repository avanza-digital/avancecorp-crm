-- Conversión y Cartera comparten preparar/revisar/confirmar.
-- Producción: pendiente de autorización. Ensayo en banco sintético propio.
begin;
set local lock_timeout='5s';


do $anclas$ declare a record; begin
  for a in select * from jsonb_to_recordset($datos$[{"firma":"crm.acceso_inversion_fn(uuid,text,jsonb)","huella":"02cf922aff3aa75e86a09d2c53d328fc"},{"firma":"crm.confirmar_inversion_revisada_fn(uuid,integer)","huella":"eb671aa677a9ba63fa995510e4f48192"},{"firma":"crm.convertir_lead(uuid,uuid)","huella":"a7bcf658afd76cbe02ed1fca781e34c3"},{"firma":"crm.convertir_lead_externo(uuid,text,numeric,text,text,text,text,text,text,date,text,integer,numeric)","huella":"f1759833df86b0a7e6f08d21ec2260c4"},{"firma":"crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)","huella":"fe210a25d8a08cfbce923d3ac12ab199"},{"firma":"crm.preparar_inversion_fn(uuid,jsonb)","huella":"ae1611fabfeb20c665b370c160abecf6"},{"firma":"crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text)","huella":"7132ea4a4e4bf5edfd07ccfa191a3cb5"},{"firma":"crm.solicitud_inversion_fn(uuid)","huella":"e049912bb20453eaf019363c2c09d95a"},{"firma":"private.enlazar_tasa_lead(uuid,uuid)","huella":"aa2cea0d964bad5a50ae68344f830a53"},{"firma":"private.inversion_datos_portal(jsonb)","huella":"170faaab19c7cc78e187909ffe039adb"},{"firma":"private.inversion_persona_autorizada(uuid)","huella":"215503bf4d84c10e0662c014dddd9780"},{"firma":"private.inversion_persona_contexto(uuid)","huella":"3b950c0ed8f4faa07695bc8ea05d3f17"},{"firma":"private.inversion_solicitud_resultado(uuid,jsonb)","huella":"5f561ade14f05b43ce04edee2c8bc53f"},{"firma":"private.inversion_validar_datos(uuid,jsonb,jsonb)","huella":"7c7f4bb5d77a7834571af850585f505f"},{"firma":"private.inversion_vincular_fuente(uuid,uuid,uuid,uuid,boolean)","huella":"a05cc3b655d508fa1831b101632bd1f7"},{"firma":"private.validar_tasa_conversion_lead(uuid,uuid,jsonb,boolean)","huella":"c8e51fc0bcebf9d5f9c7c85fce76134f"},{"firma":"private.f4_comprobante_autorizado(text)","huella":"d7b02ff3ce4806ecb370aa9eaebb5bac"},{"firma":"private.f4_comprobante_visible(text)","huella":"37e470aecbb449ee51bd380d88ee0b17"}]$datos$::jsonb) as x(firma text,huella text) loop
    if md5(pg_get_functiondef(to_regprocedure(a.firma))) is distinct from a.huella then
      raise exception 'La base cambió: %. Revisa el cambio antes de instalarlo.',a.firma;
    end if;
  end loop;
end $anclas$;

-- Corte coordinado: ninguna conversión antigua abierta puede quedar a medias.
-- La tabla bloqueada impide que una reserva entre entre el diagnóstico y el
-- guard. Las reservas históricas de leads cerrados se conservan íntegramente.
lock table crm.conversion_reservas in access exclusive mode;
do $$ begin
  if exists(select 1 from crm.conversion_reservas r join crm.leads l on l.id=r.lead_id
    where l.etapa not in ('convertido','descartado')
      and (r.efectos_iniciados_en is not null or r.expira_en>now())) then
    raise exception 'Termina las conversiones anteriores de leads abiertos antes de instalar este cambio';
  end if;
end $$;
create or replace function private.conversion_reserva_legacy_cerrada() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  -- Las RPC antiguas reservan antes de crear Auth: fallar aquí evita accesos
  -- huérfanos de una pestaña que aún tenga el bundle anterior.
  raise exception 'Actualiza el CRM y registra la inversión desde Convertir a cliente'
    using errcode='P0409';
end $$;
revoke all on function private.conversion_reserva_legacy_cerrada() from public,anon,authenticated,service_role;
create trigger conversion_reserva_legacy_cerrada before insert on crm.conversion_reservas
  for each row execute function private.conversion_reserva_legacy_cerrada();

-- El origen de la conversión es persistente e inmutable. Una única solicitud
-- preparada/confirmada por lead arbitra pestañas y claves diferentes.
alter table crm.inversion_solicitudes add column lead_origen_id uuid references crm.leads(id);
alter table crm.inversion_solicitudes add constraint inversion_solicitud_origen_coherente check (
  (lead_origen_id is null and not (datos ? 'lead_id')) or
  (lead_origen_id is not null and datos->>'lead_id' is not null and datos->>'lead_id'=lead_origen_id::text)
);
create unique index inversion_solicitud_conversion_unica on crm.inversion_solicitudes(lead_origen_id)
  where lead_origen_id is not null and estado in ('preparada','confirmada');
comment on column crm.inversion_solicitudes.lead_origen_id is
  'Conversión inicial explícita; NULL conserva el registro de Cartera. Nunca cambia al corregir datos.';

create or replace function private.inversion_origen_inmutable() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.lead_origen_id is distinct from old.lead_origen_id then
    raise exception 'El origen de una solicitud es inmutable' using errcode='22023';
  end if;
  return new;
end $$;
revoke all on function private.inversion_origen_inmutable() from public,anon,authenticated,service_role;
create trigger inversion_solicitud_origen_inmutable before update on crm.inversion_solicitudes
  for each row execute function private.inversion_origen_inmutable();

-- Sólo reconoce identidad/documento y asignación. No crea ningún hecho económico,
-- no cambia la etapa, no enlaza un perfil al lead ni cierra su episodio comercial.
create or replace function crm.preparar_persona_lead_inversion_fn(
  p_lead uuid,p_tipo_documento text,p_documento text,p_nombre text
) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
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
end $$;
revoke all on function crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) from public,anon,service_role;
grant execute on function crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) to authenticated;

-- Lector mínimo para el mismo formulario: antes de convertir todavía no existe
-- una ficha económica que justifique abrir todas las capacidades de Cartera.
create or replace function crm.contexto_conversion_inversion_fn(p_lead uuid,p_persona uuid default null)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare v_ctx jsonb; v_l crm.leads%rowtype; v_motivo text; v_persona uuid;
begin
  select * into v_l from crm.leads where id=p_lead and activo;
  if not found or not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
    v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
    raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
  end if;
  v_ctx:=private.inversion_persona_lectura(coalesce(p_persona,v_l.inversionista_id));
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  if private.inversionista_canonica(v_l.inversionista_id) is distinct from v_persona then
    raise exception 'El lead no corresponde a la persona consultada' using errcode='42501';
  end if;
  v_ctx:=v_ctx||jsonb_build_object('nombre',coalesce(
    (select nombre_completo from public.perfiles where id=(v_ctx->>'perfil_id')::uuid),v_l.nombre_completo));
  if v_l.etapa='convertido' and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=p_lead and estado='confirmada') then
    -- Consultar el resultado confirmado no habilita otra inversión ni exige
    -- que la persona conserve hoy la capacidad de operar.
    v_motivo:='La inversión inicial ya está confirmada.';
  else
    begin
      v_ctx:=private.inversion_contexto_lectura(v_persona,p_lead);
    exception when sqlstate 'P0409' or sqlstate 'P0429' then
      get stacked diagnostics v_motivo=message_text;
    end;
  end if;
  return jsonb_build_object(
    'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado in ('preparada','confirmada')),
    'documento_tipo',(select tipo_documento from crm.inversionista_identificadores
      where inversionista_id=v_persona and estado='vigente' and verificado
      order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1),
    'persona',jsonb_build_object(
    'inversionista_id',v_ctx->>'inversionista_id','perfil_id',v_ctx->>'perfil_id',
    'nombre',v_ctx->>'nombre','correo',v_l.correo,'telefono',v_l.telefono,
    'responsable_id',v_ctx->>'responsable_id','responsable_nombre',
      (select nombre_completo from public.perfiles where id=(v_ctx->>'responsable_id')::uuid)),
    'capacidades',jsonb_build_object('nueva_inversion',v_motivo is null,
      'motivo_no_operable',v_motivo));
end $$;
revoke all on function crm.contexto_conversion_inversion_fn(uuid,uuid) from public,anon,service_role;
grant execute on function crm.contexto_conversion_inversion_fn(uuid,uuid) to authenticated;


-- Estado de entrega separado del resultado económico. Un error de correo no
-- revierte ni vuelve a confirmar una inversión. Sin credenciales en el payload.
alter table crm.inversion_solicitudes add column bienvenida jsonb;

create or replace function crm.bienvenida_inversion_estado_fn(p_solicitud uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s crm.inversion_solicitudes%rowtype;
begin
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  select * into s from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='42501'; end if;
  perform private.inversion_persona_autorizada(s.inversionista_id);
  if s.estado<>'confirmada' then
    raise exception 'La inversión todavía no está confirmada' using errcode='P0409';
  end if;
  return jsonb_build_object('estado',coalesce(s.bienvenida->>'estado','no_corresponde'));
end $$;
revoke all on function crm.bienvenida_inversion_estado_fn(uuid) from public,anon,service_role;
grant execute on function crm.bienvenida_inversion_estado_fn(uuid) to authenticated;

-- Sólo la Edge obtiene el destinatario congelado y registra la respuesta del
-- proveedor. El usuario no puede fingir un envío ni cambiar el destinatario.
create or replace function crm.bienvenida_inversion_entrega_fn(
  p_solicitud uuid,p_paso text,p_token uuid default null,p_proveedor_id text default null
) returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare s crm.inversion_solicitudes%rowtype; b jsonb; token uuid;
begin
  if (select auth.role()) is distinct from 'service_role' then
    raise exception 'Sólo el servicio registra la entrega' using errcode='42501';
  end if;
  select * into s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or s.estado<>'confirmada' or s.lead_origen_id is null then
    raise exception 'Inversión no confirmada' using errcode='P0409';
  end if;
  b:=s.bienvenida;
  if b is null then return jsonb_build_object('estado','no_corresponde'); end if;
  if p_paso='reclamar' then
    if b->>'estado' in ('enviada','verificar_entrega') then
      return jsonb_build_object('estado',b->>'estado');
    end if;
    -- Resend conserva su Idempotency-Key 24 h. Se corta a las 23 h desde
    -- ANTES de la primera llamada: nunca se reenvía con una clave vencida.
    if (b->>'primer_intento')::timestamptz < now()-interval '23 hours' then
      update crm.inversion_solicitudes set bienvenida=b||jsonb_build_object('estado','verificar_entrega') where id=s.id;
      return jsonb_build_object('estado','verificar_entrega');
    end if;
    if (b->>'lease_hasta')::timestamptz > now() then
      return jsonb_build_object('estado','en_proceso');
    end if;
    token:=gen_random_uuid();
    b:=b||jsonb_build_object('estado','en_proceso','token',token,
      'primer_intento',coalesce((b->>'primer_intento')::timestamptz,now()),
      'lease_hasta',now()+interval '1 minute');
    update crm.inversion_solicitudes set bienvenida=b where id=s.id;
    return jsonb_build_object('estado','enviar','token',token,
      'clave','conversion-bienvenida-v1/'||s.id::text,'correo',b->>'correo','nombre',b->>'nombre');
  elsif p_paso='confirmar' then
    if b->>'estado'='enviada' then return jsonb_build_object('estado','enviada'); end if;
    if p_token is null or p_token is distinct from (b->>'token')::uuid
      or nullif(btrim(p_proveedor_id),'') is null or length(p_proveedor_id)>180 then
      raise exception 'Confirmación de entrega inválida' using errcode='P0409';
    end if;
    update crm.inversion_solicitudes set bienvenida=(b-'token'-'lease_hasta')||
      jsonb_build_object('estado','enviada','proveedor_id',p_proveedor_id,'enviada_en',now()) where id=s.id;
    return jsonb_build_object('estado','enviada');
  end if;
  raise exception 'Paso de entrega inválido' using errcode='22023';
end $$;
revoke all on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) to service_role;


-- Cancelar una intención sin borrar antecedentes ni tocar el hecho económico.
-- La misma puerta sirve a Cartera y al lead, también después de un veto.
create or replace function crm.cancelar_solicitud_inversion_fn(p_solicitud uuid,p_revision_datos_esperada integer)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
declare s crm.inversion_solicitudes%rowtype; v_origen uuid; v_ctx jsonb; v_saga jsonb;
begin
  select inversionista_id into v_origen from crm.inversion_solicitudes where id=p_solicitud;
  v_ctx:=private.inversion_persona_autorizada(v_origen);
  select * into s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if s.estado in ('confirmada','cancelada') then
    return private.inversion_solicitud_resultado(s.id,v_ctx);
  end if;
  if p_revision_datos_esperada is null or s.revision_datos<>p_revision_datos_esperada then
    raise exception 'La solicitud cambió; revisa sus datos antes de cancelarla' using errcode='P0409';
  end if;
  if s.auth_claim_id is not null then
    select resultado into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
      coalesce(s.auth_contexto->>'inversionista_id',v_origen::text) for update;
    if v_saga->>'claim_id' is distinct from s.auth_claim_id::text or
      v_saga->>'estado' is distinct from 'enlazado' or v_ctx->>'perfil_id' is null or
      v_saga->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'Completa el acceso Avance pendiente antes de cancelar esta solicitud' using errcode='P0409';
    end if;
  end if;
  update crm.inversion_solicitudes set estado='cancelada',actualizado_en=statement_timestamp() where id=s.id;
  -- El trigger de auditoría conserva quién canceló y los datos originales.
  return private.inversion_solicitud_resultado(s.id,v_ctx);
end $$;
revoke all on function crm.cancelar_solicitud_inversion_fn(uuid,integer) from public,anon,service_role;
grant execute on function crm.cancelar_solicitud_inversion_fn(uuid,integer) to authenticated;


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

revoke all on function private.inversion_persona_contexto(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function private.inversion_persona_contexto(p_persona uuid) returns jsonb
language sql security definer set search_path='' set lock_timeout='5s' as $$
select private.inversion_persona_contexto(p_persona,null::uuid) $$;

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

revoke all on function private.inversion_persona_lectura(uuid), private.inversion_contexto_lectura(uuid,uuid) from public,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION crm.preparar_inversion_fn(p_clave uuid, p_datos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_persona uuid;
  v_lead uuid;
  v_ctx jsonb;
  v_e crm.empresas%rowtype;
  v_s crm.inversion_solicitudes%rowtype;
  v_monto numeric;
  v_fecha date;
  v_vence date;
  v_ruta text;
  v_hash text;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','lead_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  begin v_persona := (p_datos->>'inversionista_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Identificador de persona inválido' using errcode='22023';
  end;
  begin v_lead := (p_datos->>'lead_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'Origen de inversión inválido' using errcode='22023';
  end;
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_hash := private.idem_hash(p_datos);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('f4_solicitud:'||p_clave::text,0));
  select * into v_s from crm.inversion_solicitudes where id=p_clave for update;
  if found then
    if v_s.hash_payload<>v_hash or v_s.inversionista_id<>v_persona then
      raise exception 'La misma clave llegó con datos distintos' using errcode='P0409';
    end if;
    if v_s.estado<>'confirmada' then
      v_ctx := private.inversion_persona_contexto(v_persona,v_lead);
    end if;
    return private.inversion_solicitud_resultado(v_s.id,v_ctx);
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona,v_lead);
  if v_lead is not null and exists(select 1 from crm.inversion_solicitudes
    where lead_origen_id=v_lead and estado in ('preparada','confirmada')) then
    raise exception 'Este lead ya tiene una solicitud: retómala antes de crear otra' using errcode='P0409';
  end if;
  v_e.id:=private.inversion_validar_datos(p_clave,p_datos,v_ctx);
  insert into crm.inversion_solicitudes(id,inversionista_id,empresa_id,responsable_esperado_id,hash_payload,datos,creado_por,lead_origen_id)
  values(p_clave,v_persona,v_e.id,(v_ctx->>'responsable_id')::uuid,v_hash,p_datos,(select auth.uid()),v_lead);
  return private.inversion_solicitud_resultado(p_clave,v_ctx);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_validar_datos(p_clave uuid, p_datos jsonb, p_contexto jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_persona uuid:=(p_datos->>'inversionista_id')::uuid;
  v_ctx jsonb:=p_contexto;
  v_e crm.empresas%rowtype;
  v_monto numeric; v_fecha date; v_vence date; v_ruta text;
begin
  if p_clave is null or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Falta la clave o el contenido de la inversión' using errcode='22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_datos) k where k not in (
    'inversionista_id','lead_id','empresa','monto','moneda','fecha_comercial','vence_en','numero_transaccion',
    'referencia','evidencia','producto_condicion_id','contrato','cronograma','cuenta','alta_portal','plazo_meses','tasa_anual'
  )) then
    raise exception 'La solicitud contiene campos no admitidos' using errcode='22023';
  end if;
  select * into v_e from crm.empresas where clave=p_datos->>'empresa' and activa for share;
  if not found or v_e.clave not in ('avance','qorilazo','prodelco') then
    raise exception 'Empresa no disponible para invertir' using errcode='22023';
  end if;
  if v_e.fuente_capital='cierres_externos' then
    begin
      v_monto := (p_datos->>'monto')::numeric;
      v_fecha := (p_datos->>'fecha_comercial')::date;
      v_vence := (p_datos->>'vence_en')::date;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'Revisa el monto y las fechas de la inversión' using errcode='22023';
    end;
    if v_monto is null or v_monto in ('NaN'::numeric,'Infinity'::numeric,'-Infinity'::numeric)
       or v_monto<=0 or v_monto>999999999999.99 or v_monto<>trunc(v_monto,2) then
      raise exception 'El monto debe ser positivo y tener como máximo dos decimales' using errcode='22023';
    end if;
    -- La moneda sale del catálogo de la empresa (v_e ya viene de una fila
    -- activa, con `for share`): Prodelco admite PEN y USD desde el 17/09/2026.
    -- `coalesce` sobre monedas: hoy la columna es NOT NULL (F1), pero si algún
    -- día se relajara, `= any(null)` daría NULL y este candado se abriría solo
    -- mientras los de las cooperativas siguen cerrados. Un array vacío no
    -- admite nada, que es el lado correcto del que fallar.
    if p_datos->>'moneda' is null
       or not (p_datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'Esta cooperativa no registra inversiones en %',
        coalesce(p_datos->>'moneda','la moneda enviada') using errcode='22023';
    end if;
    if v_fecha is null or not isfinite(v_fecha) or v_fecha>(statement_timestamp() at time zone 'America/Lima')::date
       or v_vence is null or not isfinite(v_vence) or v_vence<=v_fecha then
      raise exception 'La fecha comercial no puede ser futura y el vencimiento debe ser posterior' using errcode='22023';
    end if;
    if p_datos ? 'plazo_meses' or p_datos ? 'tasa_anual' then
      if jsonb_typeof(p_datos->'plazo_meses') is distinct from 'number'
        or jsonb_typeof(p_datos->'tasa_anual') is distinct from 'number'
        or (p_datos->>'plazo_meses')::numeric<>trunc((p_datos->>'plazo_meses')::numeric) then
        raise exception 'Completa el plazo en meses enteros y la rentabilidad anual' using errcode='22023';
      end if;
      if private.coopac_validar_condiciones(v_fecha,(p_datos->>'plazo_meses')::integer,
        (p_datos->>'tasa_anual')::numeric) is distinct from v_vence then
        raise exception 'El vencimiento debe corresponder a la fecha de inicio y al plazo' using errcode='22023';
      end if;
    end if;
    if length(btrim(coalesce(p_datos->>'numero_transaccion',''))) not between 1 and 64
       or length(btrim(coalesce(p_datos->>'referencia',''))) not between 1 and 64 then
      raise exception 'El depósito y la referencia son obligatorios, con un máximo de 64 caracteres' using errcode='22023';
    end if;
    v_ruta := p_datos#>>'{evidencia,ruta}';
    if v_ruta is null or v_ruta !~ ('^'||v_persona::text||'/'||p_clave::text||'/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$') then
      raise exception 'El comprobante debe pertenecer a esta persona y solicitud' using errcode='22023';
    end if;
  else
    if jsonb_typeof(p_datos->'contrato') is distinct from 'object'
       or jsonb_typeof(p_datos->'cronograma') is distinct from 'array'
       or jsonb_typeof(p_datos->'cuenta') is distinct from 'object' then
      raise exception 'Avance requiere contrato, cronograma y cuenta de pago' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,moneda}' is null
       or not (p_datos#>>'{contrato,moneda}'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'Moneda no admitida por Avance' using errcode='22023';
    end if;
    if p_datos#>>'{contrato,cliente_id}' is not null
       and p_datos#>>'{contrato,cliente_id}' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato debe pertenecer a esta persona' using errcode='P0409';
    end if;
    if v_ctx->>'perfil_id' is null or p_datos ? 'alta_portal' then
      perform private.inversion_datos_portal(p_datos->'alta_portal');
    end if;
    if p_datos#>>'{contrato,analista_cierre_id}' is not null
       and p_datos#>>'{contrato,analista_cierre_id}' is distinct from v_ctx->>'responsable_id' then
      raise exception 'El analista debe corresponder al responsable de la persona al preparar la inversión' using errcode='P0409';
    end if;
  end if;
  return v_e.id;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.corregir_solicitud_inversion_fn(p_solicitud uuid, p_clave uuid, p_revision_datos_esperada integer, p_datos jsonb, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid; v_ctx jsonb; v_validacion jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_r crm.inversion_solicitud_correcciones%rowtype;
  v_hash text; v_inicial uuid; v_empresa uuid;
begin
  if p_clave is null or p_revision_datos_esperada is null or p_revision_datos_esperada<0
    or p_datos is null or jsonb_typeof(p_datos)<>'object' then
    raise exception 'Indica clave, versión y contenido de la corrección' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  -- Siempre ámbito/membresía actuales, también al recuperar una corrección.
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  perform private.motivo_sin_documento(p_motivo,(select array_agg(documento_normalizado)
    from crm.inversionista_identificadores where inversionista_id=private.inversionista_canonica(v_persona)));
  v_hash:=private.idem_hash(jsonb_build_object('solicitud',p_solicitud,'revision',p_revision_datos_esperada,
    'datos',p_datos,'motivo',btrim(p_motivo)));
  perform pg_advisory_xact_lock(hashtextextended('f4_correccion:'||p_clave::text,0));
  select * into v_r from crm.inversion_solicitud_correcciones where id=p_clave;
  if found then
    if v_r.hash_peticion is distinct from v_hash then
      raise exception 'La clave de corrección ya se usó con otros datos' using errcode='P0409';
    end if;
    return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
      jsonb_build_object('correccion_id',v_r.id,'revision_aplicada',v_r.revision,'reintento',true);
  end if;
  v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud));
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if v_s.estado<>'preparada' then
    raise exception 'Sólo se corrigen solicitudes todavía preparadas' using errcode='P0409';
  end if;
  if v_s.revision_datos is distinct from p_revision_datos_esperada then
    raise exception 'Los datos cambiaron; vuelve a revisar la solicitud' using errcode='PT409';
  end if;
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'Revisa primero el cambio de responsable de esta solicitud' using errcode='P0409';
  end if;
  -- La MONEDA entra en esta lista el 17/09/2026, al abrir dólares en Prodelco.
  -- Motivo concreto: un bundle anterior manda `moneda:'PEN'` fijo, así que al
  -- corregir cualquier otro campo de una solicitud en USD la habría reescrito
  -- como soles, con el mismo importe y sin avisar. La moneda es parte de lo que
  -- el comprobante acredita, no un texto corregible: si está mal, se cancela la
  -- solicitud y se prepara otra.
  if p_datos->'inversionista_id' is distinct from v_s.datos->'inversionista_id'
    or p_datos->'lead_id' is distinct from v_s.datos->'lead_id'
    or p_datos->'empresa' is distinct from v_s.datos->'empresa'
    or p_datos->'moneda' is distinct from v_s.datos->'moneda'
    or p_datos#>'{contrato,cliente_id}' is distinct from v_s.datos#>'{contrato,cliente_id}'
    or p_datos#>'{contrato,analista_cierre_id}' is distinct from v_s.datos#>'{contrato,analista_cierre_id}' then
    raise exception 'La corrección conserva la persona, empresa, moneda y referencias originales del contrato' using errcode='22023';
  end if;
  if p_datos->'evidencia' is distinct from v_s.datos->'evidencia' then
    raise exception 'La corrección conserva la ruta del comprobante de esta solicitud' using errcode='22023';
  end if;
  if v_s.auth_claim_id is not null and p_datos->'alta_portal' is distinct from v_s.datos->'alta_portal' then
    raise exception 'El acceso Avance ya está reservado; conserva sus datos de alta' using errcode='P0409';
  end if;
  select responsable_anterior_id into v_inicial from crm.inversion_solicitud_revisiones
    where solicitud_id=p_solicitud order by revision limit 1;
  v_validacion:=v_ctx||jsonb_build_object('responsable_id',coalesce(v_inicial,v_s.responsable_esperado_id));
  v_empresa:=private.inversion_validar_datos(p_solicitud,p_datos,v_validacion);
  if v_empresa is distinct from v_s.empresa_id then
    raise exception 'La empresa cambió; revisa la solicitud' using errcode='PT409';
  end if;
  if p_datos=v_s.datos then raise exception 'No hay datos distintos que corregir' using errcode='22023'; end if;
  insert into crm.inversion_solicitud_correcciones(id,solicitud_id,revision_anterior,revision,
    hash_peticion,hash_anterior,hash_nuevo,datos_anteriores,datos_nuevos,motivo,corregido_por)
    values(p_clave,p_solicitud,v_s.revision_datos,v_s.revision_datos+1,v_hash,
    private.idem_hash(v_s.datos),private.idem_hash(p_datos),v_s.datos,p_datos,btrim(p_motivo),(select auth.uid()));
  -- La huella original permanece: repetir preparar con su petición original
  -- recupera esta misma solicitud, nunca crea otra ni revierte una corrección.
  update crm.inversion_solicitudes set datos=p_datos,revision_datos=revision_datos+1,
    actualizado_en=statement_timestamp() where id=p_solicitud;
  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||
    jsonb_build_object('correccion_id',p_clave,'revision_aplicada',v_s.revision_datos+1,'reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.revisar_solicitud_inversion_fn(p_solicitud uuid, p_responsable_revisado uuid, p_revision_esperada integer, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_revision crm.inversion_solicitud_revisiones%rowtype;
  v_num integer;
  v_motivo text:=btrim(p_motivo);
  v_perfil uuid;
  v_p public.perfiles%rowtype;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_config text:=current_setting('crm.f4_revision_solicitud',true);
begin
  if p_solicitud is null or p_responsable_revisado is null or p_revision_esperada is null or p_revision_esperada<0 then
    raise exception 'Falta la solicitud, el responsable revisado o su versión' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud));
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'preparada' then
    raise exception 'Solo se revisa el responsable de una solicitud pendiente; las inversiones confirmadas conservan su atribución' using errcode='P0409';
  end if;
  if p_responsable_revisado is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable actual ya no coincide con el que revisaste' using errcode='40001';
  end if;
  perform private.motivo_sin_documento(v_motivo,
    (select array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id=v_persona));
  select * into v_revision from crm.inversion_solicitud_revisiones r
    where r.solicitud_id=v_s.id order by r.revision desc limit 1;
  v_num:=coalesce(v_revision.revision,0);
  if p_revision_esperada<>v_num then
    if p_revision_esperada=v_num-1 and v_revision.responsable_nuevo_id=p_responsable_revisado
       and v_s.responsable_esperado_id=p_responsable_revisado and v_revision.motivo=v_motivo then
      return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',true);
    end if;
    raise exception 'La revisión cambió; vuelve a cargar la solicitud' using errcode='40001';
  end if;
  if v_s.responsable_esperado_id=p_responsable_revisado then
    return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('sin_cambios',true);
  end if;
  v_perfil:=(v_ctx->>'perfil_id')::uuid;
  if v_s.auth_claim_id is not null then
    select * into v_saga from crm.multiempresa_idempotencia m
      where m.clave='auth_persona:'||coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text)
        and m.resultado->>'claim_id'=v_s.auth_claim_id::text for update;
    if not found then raise exception 'El proceso de acceso requiere conciliación' using errcode='P0409'; end if;
    -- La corrección canónica solo se permite una vez enlazado el acceso. Su
    -- contexto original queda histórico y no impide revisar al nuevo equipo.
    if v_saga.resultado->>'estado'<>'enlazado' and not private.documento_es_de_identidad(
      v_persona,v_s.auth_contexto->>'documento_tipo',v_s.auth_contexto->>'documento') then
      raise exception 'El documento también cambió; revisa primero el acceso pendiente' using errcode='P0409';
    end if;
    if v_saga.resultado->>'auth_user_id' is not null then
      if not exists(select 1 from auth.users u where u.id=(v_saga.resultado->>'auth_user_id')::uuid
        and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
        raise exception 'El acceso pendiente no tiene la procedencia esperada' using errcode='P0409';
      end if;
      if v_perfil is not null and v_perfil is distinct from (v_saga.resultado->>'auth_user_id')::uuid then
        raise exception 'El perfil y el acceso pertenecen a procesos diferentes' using errcode='P0409';
      end if;
      select id into v_perfil from public.perfiles where id=(v_saga.resultado->>'auth_user_id')::uuid;
      if v_perfil is null and v_saga.resultado->>'estado' in ('perfil_creado','enlazado') then
        raise exception 'El perfil del proceso ya no existe; requiere revisión' using errcode='P0409';
      end if;
    end if;
  end if;
  if v_perfil is not null then
    -- La gestión de tareas puede tener ya una tarea/perfil. No esperar bajo el
    -- candado de persona: el intento se revierte entero y se puede repetir.
    begin
      perform 1 from crm.tareas t where t.perfil_id=v_perfil and t.estado='pendiente'
        order by t.id for update nowait;
      select * into v_p from public.perfiles where id=v_perfil for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando la ficha o sus tareas; vuelve a revisar' using errcode='40001';
    end;
    if not found or v_p.rol<>'cliente' or v_p.activo is not true
       or not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
      raise exception 'El perfil requiere conciliación con esta persona' using errcode='P0409';
    end if;
  end if;

  insert into crm.inversion_solicitud_revisiones(solicitud_id,revision,responsable_anterior_id,
    responsable_nuevo_id,motivo,revisado_por)
  values(v_s.id,v_num+1,v_s.responsable_esperado_id,p_responsable_revisado,v_motivo,(select auth.uid()));
  update crm.inversion_solicitudes set responsable_esperado_id=p_responsable_revisado,
    actualizado_en=statement_timestamp() where id=v_s.id;
  if v_perfil is not null and v_p.asesor_perfil_id is distinct from p_responsable_revisado then
    perform set_config('crm.f4_revision_solicitud',v_s.id::text,true);
    begin
      update public.perfiles set asesor_perfil_id=p_responsable_revisado where id=v_perfil;
      if (select asesor_perfil_id from public.perfiles where id=v_perfil) is distinct from p_responsable_revisado then
        raise exception 'El perfil no pudo alinearse con su responsable actual' using errcode='P0409';
      end if;
    exception when others then
      perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
      raise;
    end;
    perform set_config('crm.f4_revision_solicitud',coalesce(v_config,''),true);
  end if;
  -- No cambia datos/hash/auth_contexto ni token/versión/lease de la saga.
  return private.inversion_solicitud_resultado(v_s.id,v_ctx)||jsonb_build_object('reintento',false);
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.acceso_inversion_fn(p_solicitud uuid, p_paso text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_datos jsonb;
  v_auth_ctx jsonb;
  v_hash_payload jsonb;
  v_saga crm.multiempresa_idempotencia%rowtype;
  v_r jsonb;
  v_p public.perfiles%rowtype;
  v_auth uuid;
  v_version integer;
  v_token text;
  v_otras uuid[];
begin
  if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
     or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_object_keys(p_payload) k where
    k<>'token' and not (p_paso<>'reclamar' and k='version')
    and not (p_paso='registrar_auth' and k='auth_user_id')) then
    raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
  end if;
  v_token:=p_payload->>'token';
  if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
    raise exception 'Token de recuperación inválido' using errcode='22023';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  v_origen:=v_persona;
  v_ctx:=private.inversion_persona_autorizada(v_persona);
  v_persona:=(v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
  end if;
  if v_s.estado<>'confirmada' then
    v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud));
  end if;
  if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
     or v_s.estado='cancelada' then
    raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
  end if;
  if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
  end if;

  -- Un claim terminal conserva su clave de origen después de una fusión.
  -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
  select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
    case when v_s.auth_claim_id is null then v_persona::text
      else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
  if v_s.auth_claim_id is not null and
    (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
    raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
  end if;
  -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
  -- Auth ni reescribe el perfil, su clave o su responsable.
  if v_ctx->>'perfil_id' is not null and
     (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
    if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
    end if;
    return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
      'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
  end if;
  if v_s.estado='confirmada' then
    raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
  end if;
  v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
  v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
    'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
  if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
     or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
    raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
  end if;
  -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
  -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
  v_hash_payload:=jsonb_build_object('v',1,'inv',v_persona,'correo',v_datos->>'correo',
    'nombre',v_datos->>'nombre_completo','apellidos',coalesce(v_datos->>'apellidos',''),
    'nombres',coalesce(v_datos->>'nombres',''),'telefono',coalesce(v_datos->>'telefono',''),
    'domicilio',v_datos->'domicilio','bancarios','null'::jsonb,'asesor',v_auth_ctx->>'responsable_id');

  if p_paso='reclamar' then
    -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
    -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
    if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
      if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
        and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
        raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
      end if;
      if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
        raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
      end if;
    end if;
    if v_saga.clave is null then
      select array_agg(p.id order by p.id) into v_otras from public.perfiles p
      where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
        and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
      if coalesce(cardinality(v_otras),0)>1 then
        raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
      elsif cardinality(v_otras)=1 then
        perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
        v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud));
        if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
          raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
        end if;
        return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
          'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
      end if;
    end if;
    v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
    if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
       or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
      raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
    end if;
    if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
      raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
    end if;
    -- El formulario guarda su token ANTES del primer envío. La saga general
    -- emite otro token; aquí conservamos el ya conocido para poder recuperar
    -- también una respuesta perdida del primer reclamo (sin esperar el lease).
    -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
    -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
    if v_token is not null and v_r->>'estado'<>'enlazado' then
      update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
        to_jsonb(private.saga_token_hash(v_token)))
        where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
      if not found then
        raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
      end if;
      v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
    end if;
    update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
      auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
    return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
      'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
  end if;

  if v_s.auth_claim_id is null or v_saga.clave is null
     or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
    raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
  end if;
  -- El perfil y el avance de estado se confirman juntos. Una versión antigua
  -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
  select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
  if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
    raise exception 'Token de recuperación inválido' using errcode='42501';
  end if;
  begin v_version:=(p_payload->>'version')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'Versión del acceso inválida' using errcode='22023';
  end;
  if v_version is null or v_saga.version is distinct from v_version then
    raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
  end if;
  if p_paso='registrar_auth' then
    begin v_auth:=(p_payload->>'auth_user_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'Identificador de acceso inválido' using errcode='22023';
    end;
  else
    v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
  end if;
  if not exists(select 1 from auth.users u where u.id=v_auth
    and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
    and lower(u.email)=v_datos->>'correo') then
    raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
  end if;
  if p_paso='registrar_auth' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
  end if;
  if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
    raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
  end if;
  select * into v_p from public.perfiles where id=v_auth for update;
  if not found and p_paso='crear_perfil' then
    insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
      correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
    values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
      v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
      v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
    returning * into v_p;
  end if;
  if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
     or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
     or v_p.dni is distinct from v_auth_ctx->>'documento'
     or lower(v_p.correo) is distinct from v_datos->>'correo'
     or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
  end if;
  if p_paso='crear_perfil' then
    return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
  end if;
  v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
  if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
    raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
  end if;
  return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
    ||jsonb_build_object('solicitud_id',v_s.id);
end;
$function$;

CREATE OR REPLACE FUNCTION private.inversion_solicitud_resultado(p_id uuid, p_contexto jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('solicitud_id',s.id,'lead_id',s.lead_origen_id,'estado',s.estado,'inversion_id',s.inversion_id,
    'inversionista_id',p_contexto->>'inversionista_id','inversionista_origen_id',s.inversionista_id,
    'identidad_fusionada',s.inversionista_id::text is distinct from p_contexto->>'inversionista_id',
    'responsable_esperado_id',s.responsable_esperado_id,'responsable_actual_id',p_contexto->>'responsable_id',
    'requiere_revision_responsable',s.estado='preparada' and s.responsable_esperado_id::text is distinct from p_contexto->>'responsable_id',
    'revision_datos',s.revision_datos,'hash_datos',private.idem_hash(s.datos),
    'revision_responsable',coalesce((select max(r.revision) from crm.inversion_solicitud_revisiones r where r.solicitud_id=s.id),0),
    'resultado',case when s.resultado is not null then s.resultado||jsonb_build_object('inversionista_id',p_contexto->>'inversionista_id') end,
    'necesita_portal',e.requiere_portal and p_contexto->>'perfil_id' is null,
    'comprobante_bucket',case when e.fuente_capital='cierres_externos' then 'f4-comprobantes' else null end,
    'comprobante_ruta',s.datos#>>'{evidencia,ruta}',
    'reinversion_origen_id',(select o.fuente_id from crm.inversion_solicitud_origenes o where o.solicitud_id=s.id))
  from crm.inversion_solicitudes s join crm.empresas e on e.id=s.empresa_id where s.id=p_id;
$function$;

CREATE OR REPLACE FUNCTION private.f4_comprobante_autorizado(p_ruta text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare v_persona uuid; v_solicitud uuid; v_ctx jsonb; v_s crm.inversion_solicitudes%rowtype;
begin
  if p_ruta is null or p_ruta !~ '^[a-f0-9-]{36}/[a-f0-9-]{36}/[a-zA-Z0-9_-]+\.(pdf|jpg|jpeg|png)$' then return false; end if;
  begin v_persona:=split_part(p_ruta,'/',1)::uuid; v_solicitud:=split_part(p_ruta,'/',2)::uuid;
  exception when invalid_text_representation then return false; end;
  v_ctx:=private.inversion_persona_contexto(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=v_solicitud));
  select * into v_s from crm.inversion_solicitudes where id=v_solicitud for share;
  return found and v_s.inversionista_id=v_persona and v_s.estado='preparada'
    and v_s.responsable_esperado_id=(v_ctx->>'responsable_id')::uuid
    and v_s.datos#>>'{evidencia,ruta}'=p_ruta;
exception when insufficient_privilege or lock_not_available or sqlstate 'P0409' or sqlstate 'P0429' then return false;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$begin

declare
  v_uid uuid := (select auth.uid());
  v_persona uuid;
  v_origen uuid;
  v_ctx jsonb;
  v_s crm.inversion_solicitudes%rowtype;
  v_e crm.empresas%rowtype;
  v_obj storage.objects%rowtype;
  v_cierre uuid;
  v_contrato uuid;
  v_inversion uuid;
  v_fecha date;
  v_imputacion date;
  v_periodo date;
  v_ahora timestamptz := statement_timestamp();
  v_ajuste boolean := false;
  v_fuente jsonb;
  v_payload_contrato jsonb;
  v_condicion uuid;
  v_config_producto text := current_setting('crm.producto_condicion_id',true);
  v_responsable_inicial uuid;
  v_res jsonb;
  v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
begin
  if v_uid is null or not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para registrar inversiones' using errcode='42501';
  end if;
  select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
  if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
  v_origen := v_persona;
  v_ctx := private.inversion_persona_autorizada(v_persona);
  v_persona := (v_ctx->>'inversionista_id')::uuid;
  select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
  if not found or v_s.inversionista_id is distinct from v_origen then
    raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
  end if;
  if v_s.estado='confirmada' then
    v_res:=v_s.resultado;
    select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
    if v_contrato is not null then
      if private.contrato_en_eliminacion(v_contrato) then
        raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
      end if;
      v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
    end if;
    return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
  end if;
  if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
  if p_revision_datos_esperada is distinct from v_s.revision_datos then
    raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
  end if;
  v_ctx := private.inversion_persona_contexto(v_persona,v_s.lead_origen_id);
  if v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
    raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
  end if;
  select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
  if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
  if v_e.fuente_capital='cierres_externos' then
    -- Se revalida contra el catálogo VIVO: una solicitud preparada cuando la
    -- cooperativa admitía una moneda no se confirma si entretanto se retiró.
    -- `coalesce` por el mismo motivo que en private.inversion_validar_datos.
    if v_s.datos->>'moneda' is null
       or not (v_s.datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
      raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
    end if;
    -- Revalida el contenido guardado, también al retomar una solicitud anterior.
    perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
    select * into v_obj from storage.objects
    where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
    if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
      raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
    end if;
    v_fecha := (v_s.datos->>'fecha_comercial')::date;
    v_periodo := date_trunc('month',v_fecha)::date;
    -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
    -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
    v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
    if v_ajuste then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
        (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
      if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
        raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
      end if;
    end if;
    begin
      insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
        nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
        inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
        plazo_meses,tasa_anual)
      values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',
        v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
        upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
        (v_s.datos->>'vence_en')::date,(v_ctx->>'responsable_id')::uuid,v_uid,v_persona,
        v_ahora,v_s.lead_origen_id is not null,v_fecha,v_imputacion,v_obj.id,
        (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
      -- La reclamación histórica del depósito es global para ambas cooperativas.
      insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
      values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
    exception when unique_violation then
      raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
    end;
    v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
      'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
      'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
      'vence_en',(v_s.datos->>'vence_en')::date);
  elsif v_e.clave='avance' then
    if v_ctx->>'perfil_id' is null then
      raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
    end if;
    v_payload_contrato := v_s.datos->'contrato';
    if v_s.lead_origen_id is not null then
      if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
        raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
      end if;
      perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
      perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
    end if;
    select r.responsable_anterior_id into v_responsable_inicial
      from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
    v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
    if v_payload_contrato->>'cliente_id' is not null
       and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
      raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
    end if;
    if v_payload_contrato->>'analista_cierre_id' is not null
       and v_payload_contrato->>'analista_cierre_id' is distinct from v_responsable_inicial::text then
      raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
    end if;
    -- El contenido original conserva su huella. Una revisión explícita cambia
    -- el responsable con quien se confirma, sin reescribir las condiciones.
    v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
      'analista_cierre_id',v_ctx->>'responsable_id');
    -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
    -- documental y operaciones de cartera. Todo participa de esta transacción.
    -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
    -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
    -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
    -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
    perform pg_catalog.set_config('crm.producto_condicion_id',
      coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
    begin
      v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
        v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
        v_s.datos->'cronograma',v_s.datos->'cuenta');
    exception when others then
      perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
      raise;
    end;
    perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
    v_contrato := (v_fuente->>'id')::uuid;
    if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
    select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
    v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
  else
    raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
  end if;
  v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null);
  if v_ajuste then
    insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
    values(v_inversion,v_periodo,v_imputacion,v_uid);
  end if;
  insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
  v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
    'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
    'revision_datos',v_s.revision_datos);
  update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
    resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
  if v_s.lead_origen_id is not null then
    -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
    -- ESTA inversión como inicial, conservando un único hecho y titular.
    update crm.inversiones set es_primera_conversion=true where id=v_inversion;
    perform set_config('crm.op_privilegiada','on',true);
    update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
      perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
      contrato_id=coalesce(v_contrato,contrato_id)
      where id=v_s.lead_origen_id;
    perform set_config('crm.op_privilegiada',v_config_conversion,true);
    insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
      values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
        jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
          'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
    if v_e.clave='avance' and v_s.auth_claim_id is not null then
      update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
        'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
        'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
    end if;
  end if;
  return v_res;
end;

exception when serialization_failure then
  if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
  raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
end;
$function$;

CREATE OR REPLACE FUNCTION crm.convertir_lead_externo(p_lead_id uuid, p_cooperativa text, p_monto numeric, p_moneda text, p_documento_tipo text, p_documento text, p_nombre text, p_numero_transaccion text, p_referencia text DEFAULT NULL::text, p_vence_en date DEFAULT NULL::date, p_nota text DEFAULT NULL::text, p_plazo_meses integer DEFAULT NULL::integer, p_tasa_anual numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid         uuid := (select auth.uid());
  v_rol         text := private.rol_crm((select auth.uid()));
  v_lead        crm.leads%rowtype;
  v_documento   text := upper(btrim(p_documento));
  v_nombre      text := btrim(p_nombre);
  v_transaccion text := btrim(p_numero_transaccion);
  v_referencia  text := nullif(btrim(p_referencia), '');
  v_reserva     timestamptz;
  v_efectos     timestamptz;
  v_cierre_id   uuid;
  v_vence       date := p_vence_en;
  v_flag        boolean;
  v_monedas     text[];
  v_escribe_inversion boolean;
  v_inv         uuid;
  v_lead_canon  uuid;
  v_clave       text;
  v_hash        text;
  v_prev        jsonb;
  v_res         jsonb;
begin
  -- La autoridad no se reinterpreta en esta puerta. El helper canónico
  -- resuelve identidad, vigencia y membresía CRM activa, incluido el caso NULL.
  if not private.puede_gestionar_contratos_crm() then
    raise exception 'No autorizado para convertir leads'
      using errcode = '42501';
  end if;
  -- F2.b [D-17] (Codex, 3.ª ronda del bloque 4): la bandera se lee con READ COMMITTED y bajo el candado
  -- COMPARTIDO por bandera; el UPDATE de crm.multiempresa_flags toma el EXCLUSIVO en su trigger (D-5).
  -- Así una llamada que entró APAGADA termina apagada aunque espere por una fila, y una que entra después
  -- del encendido lo ve: sin esto, una llamada en vuelo podía escribir con la bandera cambiada a medias.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'La identidad unificada requiere READ COMMITTED (aislamiento actual: %)', pg_catalog.current_setting('transaction_isolation') using errcode = '0A000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtext('crm_flag_resolver_en_puertas'));
  v_flag := coalesce((select activo from crm.multiempresa_flags where nombre = 'resolver_en_puertas'), false);
  v_escribe_inversion := private.inversiones_escritura_bajo_candado();

  -- IDEMPOTENCIA (contrato §8.3, Codex #5): misma clave + mismo payload -> mismo
  -- resultado; misma clave con otro payload -> P0409. Se evalúa ANTES de validar
  -- para que un reintento idéntico ni siquiera toque el lead.
  -- (Gateada por la bandera: APAGADA = comportamiento previo exacto.) El hash cubre
  -- TODO lo que se persiste (Codex), con el número de operación en MAYÚSCULAS como
  -- se compara y reclama.
  if v_flag then
    v_clave := 'conversion_coop:' || p_lead_id::text;
    v_hash  := private.idem_hash(pg_catalog.jsonb_build_object(
                 'lead', p_lead_id, 'coop', p_cooperativa, 'monto', p_monto, 'moneda', p_moneda,
                 'tipo', p_documento_tipo, 'doc', v_documento, 'trx', upper(v_transaccion),
                 'nombre', v_nombre, 'ref', v_referencia, 'vence', p_vence_en,
                 'nota', nullif(btrim(coalesce(p_nota,'')), ''))
                 || case when p_plazo_meses is not null or p_tasa_anual is not null then
                   jsonb_build_object('plazo_meses',p_plazo_meses,'tasa_anual',p_tasa_anual)
                   else '{}'::jsonb end);
    v_prev  := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;

  raise exception 'Actualiza el CRM y confirma la inversión desde el formulario compartido'
    using errcode='P0409';
  -- Validaciones de entrada ANTES de tocar el lead: un payload inválido no
  -- debe dejar ni un lock tomado.
  if p_cooperativa is null or p_cooperativa not in ('qorilazo', 'prodelco') then
    raise exception 'Cooperativa invalida: debe ser qorilazo o prodelco'
      using errcode = '22023';
  end if;
  -- El NaN se rechaza EXPLÍCITAMENTE y primero: `NaN <= 0` es false y
  -- `NaN <> round(NaN,2)` también, así que sin esta línea se cuela por las dos
  -- validaciones de abajo y acaba envenenando la suma de la cuota.
  if p_monto is null or p_monto = 'NaN'::numeric or p_monto <= 0 then
    raise exception 'El monto invertido debe ser mayor que cero'
      using errcode = '22023';
  end if;
  if p_monto <> round(p_monto, 2) then
    -- numeric(14,2) redondearía en silencio; con dinero, mejor rechazar.
    raise exception 'El monto admite como maximo 2 decimales'
      using errcode = '22023';
  end if;
  -- Qué monedas admite cada cooperativa lo dice el CATÁLOGO
  -- (`crm.empresas.monedas`), no esta función: desde el 17/09/2026 Prodelco
  -- registra PEN y USD, y Qorilazo sigue solo en soles. Abrir o cerrar una
  -- moneda es una fila, no un despliegue.
  -- Se valida en vez de forzar: un bundle viejo que mande una moneda que esa
  -- cooperativa no admite merece un rechazo claro, no que le cambiemos la
  -- moneda por debajo y le contemos el monto en la que no es.
  -- `for share` porque la decisión debe valer hasta el commit: si alguien
  -- retira una moneda a mitad de esta transacción, no se cuela por el hueco.
  select e.monedas into v_monedas
  from crm.empresas e
  where e.clave = p_cooperativa
  for share;
  -- FAIL-CLOSED explícito: sin fila, `= any(null)` da NULL y el `if` sería
  -- falso, o sea el candado se abriría solo. El null se rechaza a mano.
  if v_monedas is null then
    raise exception 'Esa cooperativa no esta registrada: no se puede saber en que monedas invierte'
      using errcode = '22023';
  end if;
  if p_moneda is null or not (p_moneda = any (v_monedas)) then
    raise exception 'Esa cooperativa no registra inversiones en %',
      coalesce(p_moneda, 'la moneda enviada')
      using errcode = '22023';
  end if;
  if p_documento_tipo is null
     or p_documento_tipo not in ('DNI', 'CE', 'PASAPORTE') then
    raise exception 'Tipo de documento invalido: DNI, CE o PASAPORTE'
      using errcode = '22023';
  end if;
  -- Mismas reglas que src/lib/documento.ts y el CHECK de la tabla; el error
  -- aquí habla el idioma del formulario, no el del constraint.
  if (p_documento_tipo = 'DNI'       and v_documento !~ '^[0-9]{8}$')
     or (p_documento_tipo = 'CE'        and v_documento !~ '^[0-9]{9,12}$')
     or (p_documento_tipo = 'PASAPORTE' and v_documento !~ '^[A-Z0-9]{6,12}$') then
    raise exception 'Documento invalido para el tipo %', p_documento_tipo
      using errcode = '22023';
  end if;
  if v_nombre is null or v_nombre = '' then
    raise exception 'El nombre completo es obligatorio'
      using errcode = '22023';
  end if;
  -- El número de operación es OBLIGATORIO (y único por cooperativa, ver el
  -- índice): es lo único que impide cobrar dos veces un mismo cierre real.
  if v_transaccion is null or v_transaccion = '' then
    raise exception 'El numero de operacion del deposito es obligatorio'
      using errcode = '22023';
  end if;
  if length(v_transaccion) > 64 then
    raise exception 'El numero de operacion admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  if v_referencia is not null and length(v_referencia) > 64 then
    raise exception 'El numero de certificado admite como maximo 64 caracteres'
      using errcode = '22023';
  end if;
  -- La fecha del cierre es HOY (automática): el vencimiento de una inversión
  -- recién cerrada solo puede ser futuro. En corregir_cierre_externo este
  -- check NO existe a propósito: una corrección tardía de otro campo debe
  -- poder reenviar un vencimiento que ya pasó.
  if p_vence_en is not null and p_vence_en <= (now() at time zone 'America/Lima')::date then
    raise exception 'El vencimiento de la inversion debe ser una fecha futura'
      using errcode = '22023';
  end if;

  if p_plazo_meses is not null or p_tasa_anual is not null then
    v_vence:=private.coopac_validar_condiciones((now() at time zone 'America/Lima')::date,
      p_plazo_meses,p_tasa_anual);
    if p_vence_en is not null and p_vence_en is distinct from v_vence then
      raise exception 'El vencimiento debe corresponder a la fecha de inicio y al plazo' using errcode='22023';
    end if;
  end if;

  -- ── PUERTA DE IDENTIDAD (solo con la bandera encendida) ──────────────────
  -- Resolver ANTES del lock del lead (orden identidad->lead, comparte orden con
  -- la fusión y mata el deadlock). El documento ya se validó arriba. Con bandera
  -- APAGADA nada de esto corre (comportamiento idéntico a hoy).
  if v_flag then
    v_inv := private.inversionista_resolver(p_documento_tipo, v_documento, true, 'conversion');
    perform 1 from crm.inversionistas where id = v_inv for update;
    -- F2.b (b4): la PERSONA (no solo este lead) puede tener una conversión Avance en curso en OTRO
    -- lead: reserva viva o sellada con su inversionista_id. Lectura bajo el lock de la identidad
    -- (el sellado también lo toma desde b4): orden identidad -> lead -> reserva, sin cambios.
    if exists (select 1 from crm.conversion_reservas r
                where r.inversionista_id = v_inv and r.lead_id <> p_lead_id
                  and (r.efectos_iniciados_en is not null or r.expira_en > now())) then
      raise exception using
        errcode = 'P0409',
        message = 'Esta persona tiene una conversion a cliente de Avance en curso en otro lead',
        hint    = 'Quien la empezo tiene que terminarla o dejar que caduque.';
    end if;
  end if;

  -- Ámbito y lock: copiados VERBATIM de crm.convertir_lead para que los dos
  -- caminos de conversión signifiquen lo mismo.
  select *
    into v_lead
  from crm.leads
  where id = p_lead_id
    and activo = true
    and (
      v_rol = 'gerencia'
      or vendedor_id in (
        select private.vendedor_ids_visibles((select auth.uid()))
      )
      or (
        vendedor_id is null
        and asignado_supervisor_id in (
          select private.vendedor_ids_visibles((select auth.uid()))
        )
      )
    )
  for update;
  if not found then
    raise exception 'Lead no encontrado o fuera de tu ambito';
  end if;

  -- Reintento tras éxito: el lead ya se convirtió y su cierre lleva ESTE número de
  -- operación -> mismo resultado, sin efectos (idempotente).
  if v_flag and v_lead.etapa = 'convertido' then
    -- Revalidar TRAS el lock (Codex): la clave guardada manda; payload distinto → P0409.
    v_prev := private.idem_leer(v_clave, v_hash);
    if v_prev is not null then
      return v_prev || pg_catalog.jsonb_build_object('reintento', true);
    end if;
    -- Sin clave guardada (p.ej. conversión previa a este lote): mismo número de
    -- operación en su cierre = mismo hecho.
    select ce.id into v_cierre_id
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id and ce.es_cierre_inicial
      and upper(ce.numero_transaccion) = upper(v_transaccion)
      and ce.plazo_meses is not distinct from p_plazo_meses
      and ce.tasa_anual is not distinct from p_tasa_anual
    limit 1;
    if v_cierre_id is not null then
      v_res := pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'cierre_id', v_cierre_id,
                                             'cooperativa', p_cooperativa);
      perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
      return v_res || pg_catalog.jsonb_build_object('reintento', true);
    end if;
  end if;
  if v_lead.etapa in ('convertido', 'descartado') then
    raise exception 'El lead ya esta cerrado';
  end if;
  if v_lead.vendedor_id is null then
    raise exception 'Asigna el lead a un analista antes de convertirlo'
      using errcode = '22023';
  end if;

  -- Un solo lead total (invariante #6, decisión Miguel 03/09): un 2.º lead de la
  -- misma persona no se convierte aquí; la nueva inversión sobre el cliente
  -- existente es F5. Mensaje de negocio en vez del choque con leads_inversionista_uidx.
  if v_flag and v_inv is not null then
    select l2.id into v_lead_canon from crm.leads l2
    where l2.inversionista_id = v_inv and l2.id <> p_lead_id limit 1;
    if v_lead_canon is not null then
      raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
        using errcode = 'P0409';
    end if;
  end if;
  -- F2.b (b5) [Codex B2]: «un solo lead» cuenta también el PUENTE (históricos del backfill sin enlace vivo).
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_identidades(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex #1): también los leads SUELTOS vivos que llevan un documento vigente de la persona (nacieron antes
  -- de que existiera la persona) cuentan en «un solo lead».
  if v_flag and v_inv is not null
     and exists (select 1 from private.leads_de_personas(array[v_inv]) x where x <> p_lead_id) then
    raise exception 'Esta persona ya tiene un lead; registra la nueva inversion sobre ese lead, no conviertas otro'
      using errcode = 'P0409';
  end if;
  -- F2.b (b5) [E3-11]: la persona YA reconocida de este lead manda; el documento del cierre
  -- no se lo lleva a otra identidad (eso es corrección o fusión de Gerencia).
  if v_flag and v_lead.inversionista_id is not null and v_lead.inversionista_id is distinct from v_inv then
    raise exception 'La persona de este lead no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;
  -- F2.b [D-13] (Codex D-10 #2): el PUENTE del propio lead también manda (por la canónica), como en la reserva por persona (D-10).
  if v_flag and v_inv is not null
     and exists (select 1 from crm.inversionista_leads il
                  where il.lead_id = p_lead_id and private.inversionista_canonica(il.inversionista_id) is distinct from v_inv) then
    raise exception 'La persona de este lead (según su puente) no es la del documento del cierre: corrección o fusión de Gerencia'
      using errcode = 'P0409';
  end if;

  -- LA CARRERA (ver sección 1-bis): si hay una conversión Avance en vuelo, sus
  -- efectos irreversibles —usuario de Auth, perfil, correo de bienvenida— ya
  -- pueden haber ocurrido, y cerrar aquí dejaría a un inversionista de
  -- cooperativa con cuenta de portal. Se rechaza SIN MIRAR QUIÉN reservó: lo que
  -- importa no es el actor, es que el correo quizá ya salió.
  -- Dos casos, y solo uno se cura esperando.
  --
  -- ⚠️ `for update` y NO una lectura suelta. En READ COMMITTED un SELECT normal
  -- ve la última versión CONFIRMADA: si la edge está sellando la reserva en ese
  -- mismo instante (su UPDATE aún sin confirmar), este cierre vería la versión
  -- vieja —caducada y sin efectos—, entraría, y acto seguido la edge crearía la
  -- cuenta de portal. Ventana de milisegundos, pero es EXACTAMENTE el fallo que
  -- toda esta tabla existe para impedir. Con el lock, este cierre espera al
  -- sellado y decide DESPUÉS, sobre el estado real.
  --
  -- El orden de bloqueo es el mismo en los dos caminos —primero `crm.leads`
  -- (arriba), luego `crm.conversion_reservas`— para que no puedan abrazarse.
  -- Sin `and (expira_en > now() …)` en el WHERE: primero se toma la fila, y la
  -- vigencia se juzga con lo que haya tras esperar.
  select r.expira_en, r.efectos_iniciados_en into v_reserva, v_efectos
  from crm.conversion_reservas r
  where r.lead_id = p_lead_id
  for update;
  if v_efectos is null and coalesce(v_reserva, '-infinity'::timestamptz) <= now() then
    -- Caducada y sin efectos: no manda.
    v_reserva := null;
  end if;
  if v_efectos is not null then
    -- Ya existe una cuenta de portal a nombre de esta persona. Este cierre NO
    -- puede entrar nunca: sería justo el inversionista de cooperativa con
    -- portal que toda esta función existe para impedir.
    raise exception using
      errcode = 'P0409',
      message = 'Esta persona ya tiene una cuenta de cliente de Avance en proceso',
      hint    = 'Se le creo (o se le esta creando) su acceso al portal. Termina esa conversion; este lead ya no se puede cerrar en una cooperativa.';
  end if;
  if v_reserva is not null then
    raise exception using
      errcode = 'P0409',
      message = 'Hay una conversion a cliente de Avance en curso para este lead',
      hint    = pg_catalog.format(
        'Vuelve a intentarlo despues de las %s (hora de Lima). Si esa conversion no debia hacerse, avisa antes de cerrar en la cooperativa.',
        pg_catalog.to_char(v_reserva at time zone 'America/Lima', 'HH24:MI'));
  end if;

  -- La FOTO primero: así, cuando el UPDATE de etapa dispare el BEFORE trigger,
  -- la P4 relajada ya encuentra el cierre y deja pasar el convertido sin
  -- perfil. El UNIQUE(lead_id) es el cinturón contra un doble cierre que el
  -- gate de etapa no haya visto (el FOR UPDATE ya serializa el camino normal).
  begin
    insert into crm.cierres_externos (
      lead_id, cooperativa, monto, moneda,
      documento_tipo, documento, nombre_completo,
      numero_transaccion, referencia_externa, vence_en, nota,
      vendedor_id, creado_por, inversionista_id, plazo_meses, tasa_anual
    ) values (
      p_lead_id, p_cooperativa, p_monto, p_moneda,
      p_documento_tipo, v_documento, v_nombre,
      v_transaccion, v_referencia, v_vence, nullif(btrim(p_nota), ''),
      v_lead.vendedor_id, v_uid, v_inv, p_plazo_meses, p_tasa_anual
    )
    returning id into v_cierre_id;

    -- La reclamación es PARTE del mismo insert: si el número ya se declaró
    -- alguna vez —aunque su cierre se haya corregido después y el índice vivo
    -- lo haya soltado— este insert choca y el cierre entero se deshace.
    insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
    values (upper(v_transaccion), v_cierre_id, v_uid);
  exception when unique_violation then
    -- El índice habla en idioma de constraint; el vendedor merece saber QUÉ
    -- pasó. El UNIQUE del lead ya lo cazó el gate de etapa más arriba, así que
    -- aquí el choque es el del depósito (vivo o histórico).
    raise exception using
      errcode = 'P0409',
      message = 'Ese numero de operacion ya esta registrado',
      hint    = 'Ese deposito ya se declaro antes, aqui o en la otra cooperativa. Si lo escribiste mal, corrigelo; si es otro cierre, usa su propio numero de operacion.';
  end;

  -- El cierre del lead, IDÉNTICO al de convertir_lead salvo que perfil_id
  -- queda NULL (no hay portal). El AFTER trg_leads_asignaciones cierra el
  -- episodio con resultado='convertido' — por eso la conversión mensual cuenta
  -- este cierre sin tocar su fórmula.
  -- Inversión (colgada de la identidad) + titular principal (solo bandera).
  -- F2.b (b4) [Codex v2 #17]: los HECHOS de inversión son de F4: solo con `inversiones_escritura`.
  if v_flag and v_inv is not null and v_escribe_inversion then
    perform private.inversion_vincular_fuente(v_inv,null,v_cierre_id,v_uid,true);
  end if;

  -- El cierre del lead. inversionista_id viaja en el MISMO UPDATE bajo la válvula.
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads
     set etapa = 'convertido',
         convertido_en = now(),
         inversionista_id = coalesce(v_inv, inversionista_id)
   where id = p_lead_id;
  perform set_config('crm.op_privilegiada', 'off', true);

  -- Reconocimiento de identidad (reemplaza al trigger 200000 para coop).
  if v_flag and v_inv is not null then
    insert into crm.inversionista_leads (inversionista_id, lead_id, rol)
    select v_inv, p_lead_id, 'canonico'
    where not exists (select 1 from crm.inversionista_leads il where il.lead_id = p_lead_id);
    -- Responsable de relación = vendedor del cierre (si activo y sin tramo abierto).
    if v_lead.vendedor_id is not null
       and exists (select 1 from crm.equipo e where e.perfil_id = v_lead.vendedor_id and e.activo)
       and not exists (select 1 from crm.inversionista_responsables ir where ir.inversionista_id = v_inv and ir.hasta is null) then
      insert into crm.inversionista_responsables (inversionista_id, responsable_id, motivo)
      values (v_inv, v_lead.vendedor_id, 'conversion');
      update crm.inversionistas set responsable_relacion_id = v_lead.vendedor_id
        where id = v_inv and responsable_relacion_id is null;
    end if;
    -- no_contactar del lead se centraliza en la persona.
    if v_lead.no_contactar then
      update crm.inversionistas set no_contactar = true, no_contactar_en = coalesce(no_contactar_en, pg_catalog.now())
      where id = v_inv and no_contactar = false;
    end if;
  end if;

  insert into crm.actividades (
    lead_id, tipo, detalle, metadata, creado_por
  ) values (
    p_lead_id,
    'conversion',
    'Convertido en ' || case p_cooperativa
      when 'qorilazo' then 'COOPAC Qorilazo'
      else 'COOPAC Prodelco'
    end,
    jsonb_build_object(
      'cooperativa', p_cooperativa,
      'monto', p_monto,
      'moneda', p_moneda,
      'cierre_externo_id', v_cierre_id
    ),
    v_uid
  );

  v_res := jsonb_build_object(
    'ok', true,
    'lead_id', p_lead_id,
    'cierre_id', v_cierre_id,
    'cooperativa', p_cooperativa
  );
  if v_flag then
    perform private.idem_guardar(v_clave, 'conversion_coop', v_hash, v_res, v_uid);
  end if;
  return v_res;
end;
$function$;

-- No se modifica ningún trigger ni tabla de public. Este control de CRM
-- evita que un bundle anterior cierre el lead mientras su solicitud sigue abierta.
create or replace function private.conversion_lead_con_inversion() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.etapa='convertido' and old.etapa<>'convertido' then
    if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
      raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
    end if;
    if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
      where s.lead_origen_id=new.id and s.estado='confirmada'
        and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
      raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
    end if;
  end if;
  return new;
end $$;
revoke all on function private.conversion_lead_con_inversion() from public,anon,authenticated,service_role;
create trigger trg_leads_conversion_con_inversion before update of etapa on crm.leads
  for each row execute function private.conversion_lead_con_inversion();
alter function private.conversion_reserva_legacy_cerrada() owner to postgres;
alter function private.inversion_origen_inmutable() owner to postgres;
alter function private.conversion_lead_con_inversion() owner to postgres;
alter function private.inversion_persona_contexto(uuid,uuid) owner to postgres;
alter function private.inversion_persona_lectura(uuid) owner to postgres;
alter function private.inversion_contexto_lectura(uuid,uuid) owner to postgres;
alter function crm.cancelar_solicitud_inversion_fn(uuid,integer) owner to postgres;
alter function crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) owner to postgres;
alter function crm.contexto_conversion_inversion_fn(uuid,uuid) owner to postgres;
alter function crm.bienvenida_inversion_estado_fn(uuid) owner to postgres;
alter function crm.bienvenida_inversion_entrega_fn(uuid,text,uuid,text) owner to postgres;
notify pgrst,'reload schema';
commit;
