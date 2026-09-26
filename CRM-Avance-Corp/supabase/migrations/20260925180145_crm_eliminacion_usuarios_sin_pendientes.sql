-- Baja definitiva autorizada: transferir pendientes y conservar autoría histórica.
begin;
do $pre$ begin
  if (select md5(prosrc) from pg_proc where oid='crm.usuarios_administrables_fn(text,integer,integer)'::regprocedure) is distinct from '4b2993035c1bfb6fc72f7c730ffcfd95'
    or (select md5(prosrc) from pg_proc where oid='crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamptz,uuid)'::regprocedure) is distinct from 'e0c85c169ac8a0a853cb03c3e0e769dc' then raise exception 'El directorio o la transferencia cambió; revisar antes de instalar'; end if;
end $pre$;
create table private.usuarios_retirados (
  perfil_id uuid primary key,
  nombre_completo text not null,
  rol_portal text not null,
  rol_crm text,
  retirado_por uuid not null,
  retirado_en timestamptz not null default clock_timestamp(),
  resultado text not null check (resultado in ('eliminado','historial_conservado'))
);
alter table private.usuarios_retirados enable row level security;
revoke all on private.usuarios_retirados from public,anon,authenticated,service_role;

create function private.proteger_usuario_retirado() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if tg_table_schema='private' then
    raise exception 'La auditoría de eliminación es inmutable' using errcode='42501';
  end if;
  v_id := (to_jsonb(old)->>case when tg_table_schema='crm' then 'perfil_id' else 'id' end)::uuid;
  if exists(select 1 from private.usuarios_retirados where perfil_id=v_id) then
    if tg_op='DELETE' then
      raise exception 'Se conserva la autoría histórica del usuario retirado';
    end if;
    if new.activo is true or (tg_table_schema='public'
      and to_jsonb(new)->>'nombre_completo' is distinct from to_jsonb(old)->>'nombre_completo') then
      raise exception 'El usuario fue retirado; su acceso y autoría están protegidos';
    end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.proteger_usuario_retirado() from public,anon,authenticated;
create trigger usuarios_retirados_inmutables before update or delete on private.usuarios_retirados
  for each row execute function private.proteger_usuario_retirado();
create trigger usuarios_retirados_audit after insert on private.usuarios_retirados
  for each row execute function private.log_audit_crm();
create trigger usuario_retirado_perfil before update or delete on public.perfiles
  for each row execute function private.proteger_usuario_retirado();
create trigger usuario_retirado_equipo before update or delete on crm.equipo
  for each row execute function private.proteger_usuario_retirado();

-- Cualquier FK de negocio obliga a conservar la identidad, incluso las que se
-- añadan después. Nunca dejamos que CASCADE/SET NULL borren o desatribuyan historia.
create function private.usuario_tiene_historial(p_id uuid) returns boolean
language plpgsql security definer set search_path='' set row_security=off as $$
declare v_fk record; v_existe boolean;
begin
  if exists(select 1 from pg_catalog.pg_constraint c
    where c.contype='f' and c.confrelid in ('public.perfiles'::regclass,'crm.equipo'::regclass,'auth.users'::regclass)
      and (array_length(c.conkey,1)<>1 or c.confkey<>array[(select attnum from pg_catalog.pg_attribute
        where attrelid=c.confrelid and attname=case when c.confrelid='crm.equipo'::regclass then 'perfil_id' else 'id' end)]::smallint[])) then
    raise exception 'Hay referencias nuevas de usuario; requiere revisión antes de eliminar';
  end if;
  for v_fk in
    select n.nspname esquema,t.relname tabla,a.attname columna
    from pg_catalog.pg_constraint c join pg_catalog.pg_class t on t.oid=c.conrelid
      join pg_catalog.pg_namespace n on n.oid=t.relnamespace
      join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
    where c.contype='f' and c.confrelid in ('public.perfiles'::regclass,'crm.equipo'::regclass,'auth.users'::regclass)
      and n.nspname<>'auth'
      and not (c.conrelid='public.perfiles'::regclass and a.attname='id')
      and not (c.conrelid='crm.equipo'::regclass and a.attname='perfil_id')
    order by n.nspname,t.relname,a.attname
  loop
    execute format('select exists(select 1 from %I.%I where %I=$1)',v_fk.esquema,v_fk.tabla,v_fk.columna)
      into v_existe using p_id;
    if v_existe then return true; end if;
  end loop;
  return exists(select 1 from storage.objects where owner_id=p_id::text);
end $$;
revoke all on function private.usuario_tiene_historial(uuid) from public,anon,authenticated;

create function crm.impacto_eliminacion_usuario_fn(p_perfil_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_impacto jsonb; v_rol text; v_personas bigint;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message='Solo Gerencia puede eliminar usuarios CRM';
  end if;
  select rol into v_rol from public.perfiles where id=p_perfil_id;
  if not found then raise exception 'Usuario no encontrado'; end if;
  if p_perfil_id=auth.uid() or v_rol is null or v_rol not in ('comercial','analista') then
    raise exception 'No puedes eliminar tu propia cuenta ni una cuenta protegida del Portal';
  end if;
  if exists(select 1 from private.usuarios_retirados where perfil_id=p_perfil_id) then
    raise exception 'El usuario ya fue retirado';
  end if;
  if exists(select 1 from crm.equipo where perfil_id=p_perfil_id) then
    v_impacto:=crm.impacto_desactivacion_usuario_fn(p_perfil_id);
  else
    v_impacto:=jsonb_build_object('perfil_id',p_perfil_id,
      'subordinados_activos',(select count(*) from crm.equipo where supervisor_id=p_perfil_id and activo),
      'leads_abiertos',(select count(*) from crm.leads where vendedor_id=p_perfil_id and activo and etapa not in ('convertido','descartado')),
      'leads_en_bandeja',(select count(*) from crm.leads where asignado_supervisor_id=p_perfil_id and activo and etapa not in ('convertido','descartado')),
      'tareas_pendientes',(select count(*) from crm.tareas where (vendedor_id=p_perfil_id or asignado_supervisor_id=p_perfil_id) and activo and estado='pendiente'),
      'clientes_activos',(select count(*) from public.perfiles where asesor_perfil_id=p_perfil_id and rol='cliente' and activo),
      'personas_a_cargo',(select count(*) from crm.inversionistas i where i.estado<>'fusionado' and
        (i.responsable_relacion_id=p_perfil_id or exists(select 1 from crm.inversionista_responsables r where r.inversionista_id=i.id and r.hasta is null and r.responsable_id=p_perfil_id))));
    v_impacto:=v_impacto||jsonb_build_object('requiere_reemplazo',exists(
      select 1 from jsonb_each_text(v_impacto) where key<>'perfil_id' and value::bigint>0));
  end if;
  -- Una bandera apagada no convierte responsabilidades existentes en historia.
  select count(*) into v_personas from crm.inversionistas i where i.estado<>'fusionado' and
    (i.responsable_relacion_id=p_perfil_id or exists(select 1 from crm.inversionista_responsables r
      where r.inversionista_id=i.id and r.hasta is null and r.responsable_id=p_perfil_id));
  v_impacto:=v_impacto||jsonb_build_object('personas_a_cargo',v_personas,'requiere_reemplazo',
    (v_impacto->>'requiere_reemplazo')::boolean or v_personas>0);
  return jsonb_build_object('pendientes',v_impacto,'conserva_historial',private.usuario_tiene_historial(p_perfil_id));
end $$;
revoke all on function crm.impacto_eliminacion_usuario_fn(uuid) from public,anon,authenticated;
grant execute on function crm.impacto_eliminacion_usuario_fn(uuid) to authenticated;

create function crm.eliminar_usuario_fn(p_perfil_id uuid,p_nombre_confirmacion text,
  p_version_perfil timestamptz,p_version_equipo timestamptz default null) returns jsonb
language plpgsql security definer set search_path='' set row_security=off as $$
declare v_p public.perfiles%rowtype; v_e crm.equipo%rowtype; v_impacto jsonb;
  v_historial boolean; v_resultado text; v_previa private.usuarios_retirados%rowtype;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message='Solo Gerencia puede eliminar usuarios CRM';
  end if;
  -- Mismo orden global que la transferencia existente: bandera → jerarquía → equipo.
  perform private.resolver_en_puertas_bajo_candado();
  perform pg_advisory_xact_lock(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  select * into v_previa from private.usuarios_retirados where perfil_id=p_perfil_id;
  if found then
    if p_nombre_confirmacion is distinct from v_previa.nombre_completo then
      raise exception 'Escribe el nombre completo exacto para confirmar';
    end if;
    return jsonb_build_object('perfil_id',p_perfil_id,'resultado',v_previa.resultado);
  end if;
  select * into v_e from crm.equipo where perfil_id=p_perfil_id for update;
  select * into v_p from public.perfiles where id=p_perfil_id for update;
  if not found then raise exception 'Usuario no encontrado'; end if;
  perform 1 from auth.users where id=p_perfil_id for update;
  if not found then raise exception 'La cuenta de acceso no existe; requiere revisión'; end if;
  if p_nombre_confirmacion is distinct from v_p.nombre_completo then
    raise exception 'Escribe el nombre completo exacto para confirmar';
  end if;
  if p_version_perfil is null or p_version_perfil is distinct from v_p.actualizado_en
    or p_version_equipo is distinct from v_e.actualizado_en then
    raise exception 'El usuario cambió; recarga antes de eliminar' using errcode='40001';
  end if;
  v_impacto:=crm.impacto_eliminacion_usuario_fn(p_perfil_id);
  if (v_impacto->'pendientes'->>'requiere_reemplazo')::boolean then
    raise exception 'Transfiere primero los seguimientos, tareas, clientes y personas a cargo';
  end if;
  if v_e.activo is true then
    perform crm.fijar_membresia_activa_fn(p_perfil_id,false,null,v_e.actualizado_en,gen_random_uuid());
  end if;
  -- Releer bajo los locks: el resultado mostrado en pantalla nunca autoriza el borrado.
  v_impacto:=crm.impacto_eliminacion_usuario_fn(p_perfil_id);
  if (v_impacto->'pendientes'->>'requiere_reemplazo')::boolean then
    raise exception 'Aparecieron pendientes nuevos; transfiérelos antes de eliminar';
  end if;
  v_historial:=(v_impacto->>'conserva_historial')::boolean;
  v_resultado:=case when v_historial then 'historial_conservado' else 'eliminado' end;
  -- Revocar refresh/sesiones en ambos caminos. Los JWT ya emitidos además quedan
  -- sin acceso operativo por perfil/equipo inactivos o inexistentes.
  delete from auth.sessions where user_id=p_perfil_id;
  delete from auth.refresh_tokens where user_id=p_perfil_id::text;
  if v_historial then
    update public.perfiles set activo=false where id=p_perfil_id;
    update auth.users set banned_until=clock_timestamp()+interval '100 years' where id=p_perfil_id;
  else
    if v_e.perfil_id is not null then
      perform crm.purgar_membresia_crm(p_perfil_id,'Eliminación desde CRM confirmada por Gerencia; sin pendientes ni referencias de negocio.');
    end if;
    delete from auth.users where id=p_perfil_id;
    if exists(select 1 from public.perfiles where id=p_perfil_id)
      or exists(select 1 from crm.equipo where perfil_id=p_perfil_id) then
      raise exception 'La eliminación de la identidad no quedó completa';
    end if;
  end if;
  insert into private.usuarios_retirados(perfil_id,nombre_completo,rol_portal,rol_crm,retirado_por,resultado)
    values(p_perfil_id,v_p.nombre_completo,v_p.rol,v_e.rol_crm,auth.uid(),v_resultado);
  return jsonb_build_object('perfil_id',p_perfil_id,'resultado',v_resultado);
end $$;
revoke all on function crm.eliminar_usuario_fn(uuid,text,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function crm.eliminar_usuario_fn(uuid,text,timestamptz,timestamptz) to authenticated;

-- Una asignación en vuelo debe terminar antes del censo o reintentarse después
-- de la baja. NOWAIT conserva el orden de locks de leads/personas y evita ciclos.
create function private.no_asignar_usuario_retirado() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_ids uuid[]; v_id uuid;
begin
  case tg_table_name
    when 'leads' then
      if not new.activo or new.etapa in ('convertido','descartado') then return new; end if;
      v_ids:=array[new.vendedor_id,new.asignado_supervisor_id];
    when 'tareas' then
      if not new.activo or new.estado<>'pendiente' then return new; end if;
      v_ids:=array[new.vendedor_id,new.asignado_supervisor_id];
    when 'perfiles' then
      if new.rol<>'cliente' or not new.activo then return new; end if;
      v_ids:=array[new.asesor_perfil_id];
    when 'equipo' then
      if not new.activo then return new; end if;
      v_ids:=array[new.supervisor_id];
    when 'inversionistas' then
      if new.estado='fusionado' then return new; end if;
      v_ids:=array[new.responsable_relacion_id];
    when 'inversionista_responsables' then
      if new.hasta is not null then return new; end if;
      v_ids:=array[new.responsable_id];
    else raise exception 'Tabla no contemplada en la protección de usuarios';
  end case;
  for v_id in select distinct x from unnest(v_ids) x where x is not null order by x loop
    perform 1 from crm.equipo where perfil_id=v_id for share nowait;
    perform 1 from public.perfiles where id=v_id for share nowait;
    if not found or exists(select 1 from private.usuarios_retirados where perfil_id=v_id) then
      raise exception 'El responsable fue eliminado; selecciona otro usuario activo';
    end if;
  end loop;
  return new;
exception when lock_not_available then
  raise exception 'El responsable está siendo actualizado; vuelve a intentar la asignación' using errcode='40001';
end $$;
revoke all on function private.no_asignar_usuario_retirado() from public,anon,authenticated;
create trigger trg_zzzz_usuario_retirado before insert or update on crm.leads
  for each row execute function private.no_asignar_usuario_retirado();
create trigger trg_zzzz_usuario_retirado before insert or update on crm.tareas
  for each row execute function private.no_asignar_usuario_retirado();
create trigger trg_zzzz_usuario_retirado before insert or update on public.perfiles
  for each row execute function private.no_asignar_usuario_retirado();
create trigger trg_zzzz_usuario_retirado before insert or update on crm.equipo
  for each row execute function private.no_asignar_usuario_retirado();
create trigger trg_zzzz_usuario_retirado before insert or update on crm.inversionistas
  for each row execute function private.no_asignar_usuario_retirado();
create trigger trg_zzzz_usuario_retirado before insert or update on crm.inversionista_responsables
  for each row execute function private.no_asignar_usuario_retirado();

-- Definiciones completas: ocultar retirados del directorio y permitir
-- transferencia de residuos en membresías inactivas. Autoría sin cambios.
CREATE OR REPLACE FUNCTION crm.usuarios_administrables_fn(p_busqueda text DEFAULT NULL::text, p_limite integer DEFAULT 50, p_desde integer DEFAULT 0)
 RETURNS TABLE(perfil_id uuid, nombre_completo text, tipo_documento text, documento text, correo text, telefono text, whatsapp text, cargo text, tipo_cuenta text, estado text, rol_crm text, supervisor_id uuid, activo_crm boolean, activo_portal boolean, version_perfil timestamp with time zone, version_equipo timestamp with time zone, total bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_es_gerencia boolean := private.es_gerencia_crm_activa();
  v_es_superadmin boolean := private.es_superadmin_portal_activo();
  v_es_directorio boolean := private.es_directorio_crm_activo();
  v_solo_directorio boolean;
  v_q text := nullif(lower(pg_catalog.btrim(p_busqueda)), '');
begin
  if not private.puede_listar_usuarios_crm() then
    raise insufficient_privilege using message = 'No autorizado para listar usuarios CRM';
  end if;

  if p_limite not between 1 and 100 or p_desde not between 0 and 100000 then
    raise exception 'Paginacion invalida';
  end if;

  v_solo_directorio := v_es_directorio
    and not v_es_gerencia
    and not v_es_superadmin;

  return query
  select
    p.id,
    case when v_solo_directorio then
      'Usuario CRM · '
        || upper(pg_catalog.right(pg_catalog.replace(p.id::text, '-', ''), 8))
    else p.nombre_completo end,
    case when v_es_gerencia then p.tipo_documento end,
    case when v_es_gerencia then p.dni end,
    case when v_es_gerencia then p.correo end,
    case when v_es_gerencia then p.telefono end,
    case when v_es_gerencia then p.whatsapp end,
    case when v_es_gerencia then p.cargo end,
    case when p.rol = 'comercial' then 'solo_crm' else 'compartida_portal' end,
    case
      when p.activo is not true then 'suspendido_portal'
      when e.perfil_id is null then 'pendiente_rol'
      when e.activo is not true then 'inactivo_crm'
      else 'activo'
    end,
    e.rol_crm,
    case when v_es_gerencia then e.supervisor_id end,
    e.activo,
    p.activo,
    case when v_es_gerencia then p.actualizado_en end,
    case when not v_solo_directorio then e.actualizado_en end,
    count(*) over ()
  from public.perfiles p
  left join crm.equipo e on e.perfil_id = p.id
  where not exists(select 1 from private.usuarios_retirados r where r.perfil_id=p.id) and (
    e.perfil_id is not null
    or p.rol in ('comercial', 'analista')
  )
    and (
      v_q is null
      or (
        not v_solo_directorio
        and lower(coalesce(p.nombre_completo, '')) like '%' || v_q || '%'
      )
      or (
        v_es_gerencia and (
          lower(coalesce(p.correo, '')) like '%' || v_q || '%'
          or lower(coalesce(p.dni, '')) like '%' || v_q || '%'
        )
      )
      or (
        v_solo_directorio and (
          lower(
            'Usuario CRM · '
              || upper(pg_catalog.right(
                pg_catalog.replace(p.id::text, '-', ''), 8
              ))
          ) like '%' || v_q || '%'
          or lower(coalesce(e.rol_crm, 'sin rol')) like '%' || v_q || '%'
          or lower(case
            when p.activo is not true then 'suspendido portal'
            when e.perfil_id is null then 'pendiente rol'
            when e.activo is not true then 'inactivo crm'
            else 'activo'
          end) like '%' || v_q || '%'
        )
      )
    )
  order by case when v_solo_directorio
    then p.id::text
    else lower(coalesce(p.nombre_completo, ''))
  end, p.id
  limit p_limite offset p_desde;
end;
$function$;

CREATE OR REPLACE FUNCTION crm.fijar_membresia_activa_fn(p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_activo_anterior boolean;
  v_version timestamptz;
  v_perfil_activo boolean;
  v_rol_portal text;
  v_rol_reemplazo text;
  v_reemplazo_activo boolean;
  v_reemplazo_portal_activo boolean;
  v_impacto jsonb;
  v_requiere_reemplazo boolean;
  v_evento_objetivo uuid;
  v_flag boolean;                          -- F2.b [D-2]
  v_personas uuid[] := array[]::uuid[];    -- F2.b [D-2]: identidades (no fusionadas) a cargo del saliente
  v_nuevas uuid[] := array[]::uuid[];      -- F2.b [D-2]: las que aparecieron entre el censo y el bloqueo de sus leads
  v_ahora timestamptz;                     -- F2.b [D-2]
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede activar o desactivar membresias CRM';
  end if;
  if p_activo is null or p_version_equipo is null or p_idempotencia is null then
    raise exception 'Estado, version e idempotencia requeridos';
  end if;
  if p_activo is false and p_perfil_id = v_actor then
    raise exception 'Gerencia no puede desactivar su propia membresia';
  end if;

  -- F2.b [D-19] (auditor M1): primero el candado de la BANDERA, después el interlock de jerarquía. El orden global
  -- es BANDERA → JERARQUÍA → documento → persona → lead; invertirlo aquí encolaba un ciclo blando con el encendido.
  v_flag := private.resolver_en_puertas_bajo_candado();
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );

  select e.rol_crm, e.activo, e.actualizado_en, p.activo, p.rol
    into v_rol, v_activo_anterior, v_version, v_perfil_activo, v_rol_portal
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_perfil_id
  for update of e;
  if not found then
    raise exception 'Membresia CRM no encontrada';
  end if;
  select ue.objetivo_id into v_evento_objetivo
  from crm.usuario_eventos ue
  where ue.actor_id = v_actor
    and ue.accion in ('membresia_activada','membresia_desactivada')
    and ue.idempotencia = p_idempotencia
  limit 1;
  if found then
    if v_evento_objetivo is distinct from p_perfil_id then
      raise exception 'La idempotencia ya fue usada para otro usuario';
    end if;
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;
  if v_version is distinct from p_version_equipo then
    raise exception using errcode = '40001', message = 'La membresia fue modificada por otra sesion';
  end if;

  if p_activo and v_rol_portal = 'superadmin' and v_rol <> 'gerencia' then
    raise exception 'Superadmin Portal solo puede activarse en CRM como Gerencia';
  end if;

  if v_activo_anterior is not distinct from p_activo
    and (p_activo or not (crm.impacto_desactivacion_usuario_fn(p_perfil_id)->>'requiere_reemplazo')::boolean) then
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id, 'activo_crm', v_activo_anterior,
      'version_equipo', v_version, 'idempotente', true
    );
  end if;

  if p_activo then
    if v_perfil_activo is not true then
      raise exception 'El perfil esta suspendido en Portal; Gerencia no puede reactivarlo';
    end if;

    update crm.equipo e set activo = true
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_activada', p_perfil_id,
      pg_catalog.jsonb_build_object('estado_nuevo', 'activo'),
      p_idempotencia
    );
  else
    v_impacto := crm.impacto_desactivacion_usuario_fn(p_perfil_id);
    v_requiere_reemplazo := (v_impacto->>'requiere_reemplazo')::boolean;

    if v_requiere_reemplazo and p_reemplazo_id is null then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;
    -- F2.b [D-2]: con la identidad encendida nadie se queda sin responsable: si el saliente tiene personas a cargo,
    -- la baja exige reemplazo (mismo mensaje), aunque la bandera cambiara entre la lectura del impacto y esta.
    if v_flag and p_reemplazo_id is null and exists (select 1 from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))) then
      raise exception 'La membresia conserva dependencias; selecciona un reemplazo activo del mismo rol';
    end if;

    if p_reemplazo_id is not null then
      if p_reemplazo_id = p_perfil_id then
        raise exception 'El reemplazo debe ser otro usuario';
      end if;

      select e.rol_crm, e.activo, p.activo
        into v_rol_reemplazo, v_reemplazo_activo, v_reemplazo_portal_activo
      from crm.equipo e
      join public.perfiles p on p.id = e.perfil_id
      where e.perfil_id = p_reemplazo_id
      for update of e;

      if not found
         or v_reemplazo_activo is not true
         or v_reemplazo_portal_activo is not true
         or v_rol_reemplazo is distinct from v_rol then
        raise exception 'El reemplazo no existe, no esta activo o no tiene el mismo rol CRM';
      end if;

      if exists (
        with recursive descendientes as (
          select e.perfil_id
          from crm.equipo e
          where e.supervisor_id = p_perfil_id
          union
          select e.perfil_id
          from crm.equipo e
          join descendientes d on e.supervisor_id = d.perfil_id
        )
        select 1 from descendientes where perfil_id = p_reemplazo_id
      ) then
        raise exception 'El reemplazo no puede pertenecer al subarbol del usuario saliente';
      end if;

      -- F2.b [D-2]: las PERSONAS del saliente (identidades activas con tramo abierto suyo o apuntándole) se bloquean
      -- ANTES que sus leads —la misma arista persona → lead de conversiones y veto; FOR NO KEY UPDATE, que serializa
      -- contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK— y sus tramos abiertos FOR UPDATE.
      if v_flag then
        -- (Codex N2) SIN ESPERAR: el alta de una tarea de cliente toma a la persona y luego a este mismo equipo; esperar
        -- aquí con equipo en la mano sería el abrazo. Si alguien tiene a una persona del saliente → 40001, se reintenta.
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_personas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una persona a cargo del saliente está siendo actualizada; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        perform 1 from crm.inversionista_responsables r
         where r.inversionista_id = any(v_personas) and r.hasta is null
         order by r.id
         for update;
        -- (auditor M5) y las tareas pendientes del saliente ANTES que sus leads (tareas → leads), la misma disciplina que
        -- el veto (b2/D-3), reasignar y cerrar_tarea: el offboarding iba leads → tareas y podía abrazarse con un veto en
        -- curso sobre una persona que no está «a cargo» del saliente. Solo con la identidad encendida (paridad OFF).
        perform 1 from crm.tareas t
         where t.activo is true and t.estado = 'pendiente'
           and (t.vendedor_id = p_perfil_id or t.asignado_supervisor_id = p_perfil_id
                or t.lead_id in (select l.id from crm.leads l
                                  where (l.vendedor_id = p_perfil_id or l.asignado_supervisor_id = p_perfil_id)
                                    and l.activo is true and l.etapa not in ('convertido', 'descartado')))
         order by t.id
         for update;
      end if;

      update crm.equipo e
      set supervisor_id = p_reemplazo_id
      where e.supervisor_id = p_perfil_id and e.activo is true;

      update crm.leads l
      set vendedor_id = p_reemplazo_id
      where l.vendedor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      update crm.leads l
      set asignado_supervisor_id = p_reemplazo_id
      where l.asignado_supervisor_id = p_perfil_id
        and l.activo is true and l.etapa not in ('convertido','descartado');

      -- F2.b [D-2] (Codex #3): una conversión en vuelo sobre un lead del saliente (no toma el interlock de jerarquía) pudo
      -- abrir un tramo al saliente DESPUÉS del censo. Con sus leads ya bloqueados por los dos UPDATE de arriba ninguna
      -- conversión suya sigue en vuelo: se repite el censo; lo que apareció se bloquea SIN esperar (persona tras lead es
      -- la arista inversa: si alguien la tiene → 40001, Gerencia reintenta) y se suma al traslado.
      if v_flag then
        begin
          select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_nuevas
          from (select i.id from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id))
                   and not (i.id = any(v_personas))
                 order by i.id
                 for no key update of i nowait) s;
        exception when lock_not_available then
          raise exception 'Una conversión de un lead del saliente sigue en curso; vuelve a intentar la baja'
            using errcode = '40001';
        end;
        if coalesce(pg_catalog.array_length(v_nuevas, 1), 0) > 0 then
          perform 1 from crm.inversionista_responsables r
           where r.inversionista_id = any(v_nuevas) and r.hasta is null
           order by r.id
           for update;
          v_personas := v_personas || v_nuevas;
        end if;
      end if;

      -- Los triggers de leads sincronizan la agenda normal. Este barrido cubre
      -- ademas tareas independientes y cualquier residuo historico pendiente.
      update crm.tareas t
      set vendedor_id = p_reemplazo_id
      where t.vendedor_id = p_perfil_id and t.inversionista_id is null
        and t.activo is true and t.estado = 'pendiente';

      update crm.tareas t
      set asignado_supervisor_id = p_reemplazo_id
      where t.asignado_supervisor_id = p_perfil_id and t.inversionista_id is null
        and t.activo is true and t.estado = 'pendiente';

      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;

      -- F2.b [D-2]: el responsable de relación pasa al reemplazo en la MISMA transacción: se cierra cada tramo abierto
      -- del saliente y se abre otro al reemplazo (motivo 'offboarding', por = Gerencia), y responsable_relacion_id lo
      -- acompaña. Un único v_ahora tomado DESPUÉS de los locks [E3-14]. Con la bandera apagada, nada (paridad).
      if v_flag and coalesce(pg_catalog.array_length(v_personas, 1), 0) > 0 then
        v_ahora := pg_catalog.clock_timestamp();
        update crm.inversionista_responsables r
           set hasta = v_ahora
         where r.inversionista_id = any(v_personas) and r.hasta is null;
        insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
        select s.id, p_reemplazo_id, v_ahora, 'offboarding', v_actor
        from pg_catalog.unnest(v_personas) as s(id);
        update crm.inversionistas i
           set responsable_relacion_id = p_reemplazo_id
         where i.id = any(v_personas);
      end if;
    end if;

    update crm.equipo e set activo = false
    where e.perfil_id = p_perfil_id;

    perform private.registrar_evento_usuario(
      'membresia_desactivada', p_perfil_id,
      pg_catalog.jsonb_build_object(
        'reemplazo_id', p_reemplazo_id,
        'subordinados_transferidos', (v_impacto->>'subordinados_activos')::integer,
        'leads_transferidos',
          (v_impacto->>'leads_abiertos')::integer
          + (v_impacto->>'leads_en_bandeja')::integer,
        'tareas_transferidas', (v_impacto->>'tareas_pendientes')::integer,
        'clientes_transferidos', (v_impacto->>'clientes_activos')::integer
      ) || case when v_flag then pg_catalog.jsonb_build_object('personas_transferidas', coalesce(pg_catalog.array_length(v_personas, 1), 0)) else '{}'::jsonb end,  -- F2.b [D-2]
      p_idempotencia
    );
  end if;

  select e.actualizado_en into v_version
  from crm.equipo e where e.perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id, 'activo_crm', p_activo,
    'version_equipo', v_version, 'idempotente', false
  );
end;
$function$;

notify pgrst,'reload schema';
commit;
