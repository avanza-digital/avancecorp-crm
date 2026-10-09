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
$function$
