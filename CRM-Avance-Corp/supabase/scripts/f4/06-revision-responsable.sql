-- Prueba acotada para el trigger de perfiles: solo permite alinear el asesor
-- con la persona durante la misma sentencia que registró una revisión F4.
-- Es INVOKER. El trigger la consulta únicamente desde el escritor postgres;
-- un UPDATE directo authenticated no puede abrir esta excepción con un GUC.
create or replace function private.f4_alineacion_perfil_permitida(p_perfil uuid,p_responsable uuid)
returns boolean language sql stable security invoker set search_path='' as $$
  select exists(
    select 1 from crm.inversion_solicitudes s
    join crm.inversionistas i on i.id=private.inversionista_canonica(s.inversionista_id)
    join crm.inversion_solicitud_revisiones r on r.solicitud_id=s.id
    where s.id=case when current_setting('crm.f4_revision_solicitud',true)
      ~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
      then current_setting('crm.f4_revision_solicitud',true)::uuid else null end
      and s.estado='preparada' and s.responsable_esperado_id=p_responsable
      and i.estado='activo' and not i.no_contactar and i.responsable_relacion_id=p_responsable
      and r.revisado_por=(select auth.uid()) and r.transaccion=pg_current_xact_id()
      and r.responsable_nuevo_id=p_responsable
      and (i.perfil_id=p_perfil or (i.perfil_id is null and exists(
        select 1 from crm.multiempresa_idempotencia m join auth.users u
          on u.id=(m.resultado->>'auth_user_id')::uuid
        where m.clave='auth_persona:'||i.id::text
          and m.resultado->>'claim_id'=s.auth_claim_id::text
          and m.resultado->>'estado' in ('auth_creado','perfil_creado')
          and u.id=p_perfil and u.raw_app_meta_data->>'claim_id'=s.auth_claim_id::text
      )))
  );
$$;
revoke all on function private.f4_alineacion_perfil_permitida(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function crm.revisar_solicitud_inversion_fn(
  p_solicitud uuid,p_responsable_revisado uuid,p_revision_esperada integer,p_motivo text)
returns jsonb language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
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
  v_ctx:=private.inversion_persona_contexto(v_persona);
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
$$;
revoke all on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) from public,anon,authenticated,service_role;
grant execute on function crm.revisar_solicitud_inversion_fn(uuid,uuid,integer,text) to authenticated;
