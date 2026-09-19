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
