-- ============================================================================
-- REVERSA de F2.b [D-2] (20260906120000): restaura byte a byte las 3 funciones vivas de producción y desregistra la versión.
-- Se NIEGA si la bandera está encendida. Repetible dos veces. No deshace tramos ya escritos (append-only con rastro).
-- ============================================================================
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d2_offboarding_atomico'));
do $flags$
begin
  if exists (select 1 from crm.multiempresa_flags where nombre = 'resolver_en_puertas' and activo) then
    raise exception 'REVERSA D-2: la bandera está ENCENDIDA; apágala a propósito antes de revertir';
  end if;
end
$flags$;
do $guard$
declare v_h text;
begin
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='impacto_desactivacion_usuario_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid');
  if v_h is null then
    raise exception 'F2.b D-2: falta crm.impacto_desactivacion_usuario_fn(uuid)';
  end if;
  if v_h is distinct from '571a5451889119434f651dd16e95e290' and v_h is distinct from 'b160ad28bb544275c30724f41a2789e2' then
    raise exception 'F2.b D-2: crm.impacto_desactivacion_usuario_fn(uuid) no es ni el texto vivo de producción ni el de D-2 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='fijar_membresia_activa_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid');
  if v_h is null then
    raise exception 'F2.b D-2: falta crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)';
  end if;
  if v_h is distinct from '073215fbaa8d03757181c7aed879673b' and v_h is distinct from '59aa0b103e102b9813e347582c978b63' then
    raise exception 'F2.b D-2: crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid) no es ni el texto vivo de producción ni el de D-2 (%)', v_h;
  end if;
  v_h := (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reasignar_responsable_relacion_fn' and pg_get_function_identity_arguments(p.oid)='p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text');
  if v_h is null then
    raise exception 'F2.b D-2: falta crm.reasignar_responsable_relacion_fn(uuid,uuid,text)';
  end if;
  if v_h is distinct from '3615c1c91bbf2e923634ef4cda1281ee' and v_h is distinct from '58fb9af195813b2361f40bb5517e0934' then
    raise exception 'F2.b D-2: crm.reasignar_responsable_relacion_fn(uuid,uuid,text) no es ni el texto vivo de producción ni el de D-2 (%)', v_h;
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION crm.impacto_desactivacion_usuario_fn(p_perfil_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_subordinados integer;
  v_leads integer;
  v_bandeja integer;
  v_tareas integer;
  v_clientes integer;
begin
  if not private.es_gerencia_crm_activa() then
    raise insufficient_privilege using message = 'Solo Gerencia puede evaluar una baja CRM';
  end if;
  if not exists (select 1 from crm.equipo e where e.perfil_id = p_perfil_id) then
    raise exception 'Membresia CRM no encontrada';
  end if;

  select count(*)::integer into v_subordinados
  from crm.equipo e
  where e.supervisor_id = p_perfil_id and e.activo is true;

  select count(*)::integer into v_leads
  from crm.leads l
  where l.vendedor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_bandeja
  from crm.leads l
  where l.asignado_supervisor_id = p_perfil_id
    and l.activo is true and l.etapa not in ('convertido','descartado');

  select count(*)::integer into v_tareas
  from crm.tareas t
  where (t.vendedor_id = p_perfil_id
      or t.asignado_supervisor_id = p_perfil_id)
    and t.activo is true and t.estado = 'pendiente';

  select count(*)::integer into v_clientes
  from public.perfiles p
  where p.rol = 'cliente' and p.activo is true
    and p.asesor_perfil_id = p_perfil_id;

  return pg_catalog.jsonb_build_object(
    'perfil_id', p_perfil_id,
    'subordinados_activos', v_subordinados,
    'leads_abiertos', v_leads,
    'leads_en_bandeja', v_bandeja,
    'tareas_pendientes', v_tareas,
    'clientes_activos', v_clientes,
    'requiere_reemplazo',
      v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes > 0
  );
end;
$function$
;
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

  if v_activo_anterior is not distinct from p_activo then
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

      -- Los triggers de leads sincronizan la agenda normal. Este barrido cubre
      -- ademas tareas independientes y cualquier residuo historico pendiente.
      update crm.tareas t
      set vendedor_id = p_reemplazo_id
      where t.vendedor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update crm.tareas t
      set asignado_supervisor_id = p_reemplazo_id
      where t.asignado_supervisor_id = p_perfil_id
        and t.activo is true and t.estado = 'pendiente';

      update public.perfiles p
      set asesor_perfil_id = p_reemplazo_id,
          actualizado_en = pg_catalog.clock_timestamp()
      where p.rol = 'cliente' and p.activo is true
        and p.asesor_perfil_id = p_perfil_id;
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
      ),
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
$function$
;
CREATE OR REPLACE FUNCTION crm.reasignar_responsable_relacion_fn(p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '5s'
AS $function$
declare
  v_uid uuid;
  v_inv crm.inversionistas%rowtype; v_tramo crm.inversionista_responsables%rowtype; v_nuevo_id uuid; v_ahora timestamptz; v_lead crm.leads%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación' using errcode = '42501';
  end if;
  v_uid := (select auth.uid());
  if p_inversionista is null or p_nuevo_responsable is null then
    raise exception 'Faltan la persona o el nuevo responsable' using errcode = '22023';
  end if;
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  -- jerarquía compartida (el offboarding la toma exclusiva) + Gerencia y destinatario revalidados bajo ella -> identidad FOR UPDATE
  perform pg_catalog.pg_advisory_xact_lock_shared(pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0));
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia reasigna el responsable de relación (membresía revalidada)' using errcode = '42501';
  end if;
  if not coalesce(private.rol_crm(p_nuevo_responsable) in ('vendedor', 'supervisor', 'gerencia'), false) then
    raise exception 'El nuevo responsable debe ser un miembro activo del equipo comercial (rol efectivo)' using errcode = '22023';
  end if;
  select * into v_inv from crm.inversionistas where id = p_inversionista for update;
  if not found then
    raise exception 'La persona no existe' using errcode = 'P0002';
  end if;
  if v_inv.estado = 'fusionado' then
    raise exception 'Esta identidad está fusionada: reasigna en su canónica %', private.inversionista_canonica(v_inv.id) using errcode = 'P0409';
  elsif v_inv.estado <> 'activo' then
    raise exception 'La persona no está activa (%): revisión de Gerencia', v_inv.estado using errcode = 'P0409';
  end if;
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  select * into v_lead from crm.leads where inversionista_id = p_inversionista and activo = true order by id limit 1;
  if v_lead.id is not null then
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (v_lead.id, 'nota', 'Responsable de relación reasignado (Gerencia)',
            pg_catalog.jsonb_build_object('evento', 'reasignacion_responsable', 'inversionista_id', p_inversionista,
                                          'anterior', v_tramo.responsable_id, 'nuevo', p_nuevo_responsable, 'tramo_id', v_nuevo_id),
            v_uid);
  end if;
  perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  return pg_catalog.jsonb_build_object('ok', true, 'estado', 'reasignado', 'inversionista_id', p_inversionista,
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable);
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='impacto_desactivacion_usuario_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid') is distinct from '571a5451889119434f651dd16e95e290' then
    raise exception 'REVERSA D-2: crm.impacto_desactivacion_usuario_fn(uuid) no volvió byte a byte al vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='fijar_membresia_activa_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid') is distinct from '073215fbaa8d03757181c7aed879673b' then
    raise exception 'REVERSA D-2: crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid) no volvió byte a byte al vivo de producción';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reasignar_responsable_relacion_fn' and pg_get_function_identity_arguments(p.oid)='p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text') is distinct from '3615c1c91bbf2e923634ef4cda1281ee' then
    raise exception 'REVERSA D-2: crm.reasignar_responsable_relacion_fn(uuid,uuid,text) no volvió byte a byte al vivo de producción';
  end if;
  if exists (select 1 from unnest(array['crm.impacto_desactivacion_usuario_fn(uuid)','crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)','crm.reasignar_responsable_relacion_fn(uuid,uuid,text)']) f(firma)
             where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
                or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0))
     or exists (select 1 from pg_proc p where p.oid in ('crm.impacto_desactivacion_usuario_fn(uuid)'::regprocedure,'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)'::regprocedure,'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'::regprocedure) and not (p.prosecdef and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT D-2: los grants (solo authenticated; ni anon, ni service_role, ni PUBLIC) o definer/search_path de las tres cambiaron';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'REVERSA D-2: la bandera se ENCENDIÓ mientras se revertía; no se confirma la reversa';
  end if;
  delete from supabase_migrations.schema_migrations where version = '20260906120000';
  raise notice 'REVERSA F2.b D-2 OK (versión 20260906120000 desregistrada de schema_migrations si estaba)';
end
$post$;
commit;
