-- ============================================================================
-- P-055 · MULTIEMPRESA Contrato-F2 · F2.b prerrequisito de ACTIVACIÓN [D-2] — LA SALIDA DE UN ANALISTA NO DEJA
-- PERSONAS SIN RESPONSABLE, Y EL NUEVO RESPONSABLE RECIBE CAPACIDAD OPERATIVA (bloque 2 del plan, RETOMAR-60 §8)
-- ============================================================================
--
-- QUE (todo en la rama ON; con la bandera apagada las tres funciones responden byte a byte como hoy):
--  · crm.impacto_desactivacion_usuario_fn: cuenta las PERSONAS a cargo del saliente (identidades activas con tramo
--    abierto suyo en crm.inversionista_responsables o responsable_relacion_id) y las suma a requiere_reemplazo; la
--    clave personas_a_cargo aparece SOLO con ON (el front valida con un esquema estricto; bloque 4 la incorpora).
--  · crm.fijar_membresia_activa_fn (offboarding): con reemplazo, bloquea las personas del saliente ANTES que sus leads
--    (FOR NO KEY UPDATE: serializa contra el FOR UPDATE de reasignar/marcar/convertir sin chocar con las FK) y sus
--    tramos abiertos, y en la MISMA transacción cierra cada tramo abierto del saliente y abre otro al reemplazo
--    (motivo 'offboarding'), acompañado de responsable_relacion_id; el evento membresia_desactivada lleva
--    personas_transferidas. Sin reemplazo y con personas a cargo → se niega (mismo mensaje de hoy). Todo bajo el
--    interlock EXCLUSIVO de jerarquía que ya tomaba (las puertas de identidad de b5 lo toman compartido: no se cruzan).
--  · crm.reasignar_responsable_relacion_fn (b5): además del tramo, si el nuevo responsable puede tener cartera
--    (vendedor/supervisor), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su
--    documento, private.leads_de_personas de D-13) pasan a su cartera (vendedor_id, sin bandeja; los triggers de leads
--    llevan el ledger de asignaciones, la actividad «reasignacion», tenencia_desde y las tareas pendientes) y el
--    perfil cliente de la persona pasa a su cartera (asesor_perfil_id; el trigger del perfil mueve las tareas de
--    cliente y deja su actividad). Orden: persona → tramo → tareas → leads → perfil. Con Gerencia como nuevo
--    responsable solo cambia el tramo. La respuesta añade `tenencia` {estado, leads_movidos, perfil_movido}.
-- Transformadas desde el texto VIVO de producción (scripts/f2b/gen-d2.py + vivas/bloque2/, guardas md5 EXACTAS,
-- postflight byte a byte). Aterriza APAGADA. Ensayo: scripts/oraculo-f2b-d2.sh. Reversa: scripts/rollback-f2b-d2.sql.

begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('crm_f2b_d2_offboarding_atomico'));

do $guard$
declare v_h text;
begin
  if to_regprocedure('private.leads_de_personas(uuid[])') is null or to_regprocedure('crm.fusionar_inversionistas_fn(uuid,uuid,text,text)') is null then
    raise exception 'F2.b D-2: falta b5 (20260905120000) o D-13 (20260905160000)';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'F2.b D-2: la bandera resolver_en_puertas está ENCENDIDA; este cambio aterriza apagado';
  end if;
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
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure) is distinct from '6eded477639796c1053f0190f6decc18'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-2: private.leads_de_personas(uuid[]) no es el texto vivo de producción (D-13) o perdió definer/search_path';
  end if;
end
$guard$;

-- ============================================================================
-- 1. crm.impacto_desactivacion_usuario_fn(uuid): las personas a cargo exigen reemplazo (solo con ON)
-- ============================================================================
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
  v_personas integer := 0;  -- F2.b [D-2]
  v_flag boolean := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);  -- F2.b [D-2]
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

  -- F2.b [D-2]: con la identidad ENCENDIDA, las PERSONAS cuyo responsable de relación es el saliente (identidades
  -- activas con tramo abierto suyo o apuntándole) también exigen reemplazo: nadie se queda sin responsable. Con la
  -- bandera apagada la respuesta es byte a byte la de hoy (el front la valida con un esquema ESTRICTO: la clave
  -- personas_a_cargo solo aparece con ON, y el front la incorpora en el bloque 4, antes del encendido).
  if v_flag then
    select count(*)::integer into v_personas
    from crm.inversionistas i
               where i.estado <> 'fusionado'
                 and (i.responsable_relacion_id = p_perfil_id
                      or exists (select 1 from crm.inversionista_responsables r
                                 where r.inversionista_id = i.id and r.hasta is null and r.responsable_id = p_perfil_id));
    return pg_catalog.jsonb_build_object(
      'perfil_id', p_perfil_id,
      'subordinados_activos', v_subordinados,
      'leads_abiertos', v_leads,
      'leads_en_bandeja', v_bandeja,
      'tareas_pendientes', v_tareas,
      'clientes_activos', v_clientes,
      'personas_a_cargo', v_personas,
      'requiere_reemplazo',
        v_subordinados + v_leads + v_bandeja + v_tareas + v_clientes + v_personas > 0
    );
  end if;
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

-- ============================================================================
-- 2. crm.fijar_membresia_activa_fn(...): personas antes que leads; tramos al reemplazo en la misma transacción
-- ============================================================================
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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('crm.equipo.usuarios_jerarquia', 0)
  );
  -- F2.b [D-2]: la bandera se lee BAJO el interlock exclusivo (las puertas de identidad de b5 lo toman compartido).
  v_flag := coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false);

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
;

-- ============================================================================
-- 3. crm.reasignar_responsable_relacion_fn(uuid,uuid,text): capacidad operativa del nuevo responsable
-- ============================================================================
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
  v_rol_nuevo text; v_leads uuid[] := array[]::uuid[]; v_leads_movidos integer := 0; v_perfil_movido boolean := false; v_tenencia text := 'sin_cambios';  -- F2.b [D-2]
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
  -- F2.b [D-2] (Codex #12): el motivo se revalida contra los documentos BAJO el lock de la persona (la validación de
  -- arriba corre antes del lock y una corrección documental concurrente pudo cambiarlos).
  perform private.motivo_sin_documento(p_motivo, (select pg_catalog.array_agg(d.documento_normalizado) from crm.inversionista_identificadores d where d.inversionista_id = p_inversionista));
  select * into v_tramo from crm.inversionista_responsables where inversionista_id = p_inversionista and hasta is null for update;
  if v_tramo.id is not null and v_tramo.responsable_id = p_nuevo_responsable then
    return pg_catalog.jsonb_build_object('ok', true, 'estado', 'sin_cambios', 'inversionista_id', p_inversionista, 'tramo_id', v_tramo.id);
  end if;
  -- F2.b [D-2]: capacidad operativa del nuevo responsable. Si puede tener cartera (vendedor/supervisor activo, rol
  -- efectivo), los leads VIVOS en tenencia operativa de la persona (enlace ∪ puente ∪ sueltos con su documento, D-13)
  -- pasan a su cartera y el perfil cliente de la persona también. Orden: persona (ya) → tramo (ya) → tareas
  -- pendientes → leads → perfil, como el veto (b2) y la fusión (b5). Con Gerencia como nuevo responsable no hay
  -- cartera que mover: solo el tramo (tenencia = 'sin_cambios').
  v_rol_nuevo := private.rol_crm(p_nuevo_responsable);
  if v_rol_nuevo in ('vendedor', 'supervisor') then
    select coalesce(pg_catalog.array_agg(s.id), array[]::uuid[]) into v_leads
    from (select l.id from crm.leads l
           where l.id in (select x from private.leads_de_personas(array[p_inversionista]) x)
             and l.activo = true
             and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
             and (l.vendedor_id is distinct from p_nuevo_responsable or l.asignado_supervisor_id is not null)
           order by l.id) s;
    -- (Codex N1/N4) tampoco se espera por una TAREA ni por el PERFIL: cerrar_tarea tiene la tarea y va tarea → lead/perfil;
    -- el Portal actualiza el perfil y su trigger va perfil → tareas. Con la persona y el tramo en la mano, todo lo demás
    -- se toma SIN esperar → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.tareas t
       where t.estado = 'pendiente'
         and (t.lead_id = any(v_leads) or (v_inv.perfil_id is not null and t.perfil_id = v_inv.perfil_id))
       order by t.id
       for update nowait;
      if v_inv.perfil_id is not null then
        perform 1 from public.perfiles p where p.id = v_inv.perfil_id for no key update nowait;
      end if;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando una tarea o la ficha de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    -- (Codex #1) tareas → leads es el orden de b2/D-3 y de cerrar_tarea; derivar y repartir van lead → tareas (por el
    -- trigger de sincronización) bajo el mismo interlock compartido. Como la fusión (b5, E3-9): los leads se toman
    -- SIN esperar; si otra sesión tiene uno → 40001 y Gerencia reintenta.
    begin
      perform 1 from crm.leads l where l.id = any(v_leads) order by l.id for update nowait;
    exception when lock_not_available then
      raise exception 'Otra sesión está trabajando uno de los leads de la persona; vuelve a intentarlo'
        using errcode = '40001';
    end;
    v_tenencia := 'movida';
  end if;
  v_ahora := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  if v_tramo.id is not null then
    update crm.inversionista_responsables set hasta = v_ahora where id = v_tramo.id;
  end if;
  insert into crm.inversionista_responsables (inversionista_id, responsable_id, desde, motivo, por)
  values (p_inversionista, p_nuevo_responsable, v_ahora, p_motivo, v_uid) returning id into v_nuevo_id;
  update crm.inversionistas set responsable_relacion_id = p_nuevo_responsable where id = p_inversionista;
  -- F2.b [D-2]: la cartera sigue al responsable (los triggers de leads llevan el ledger de asignaciones, la actividad
  -- «reasignacion», tenencia_desde y las tareas pendientes; el del perfil mueve las tareas de cliente y deja su actividad).
  if v_tenencia = 'movida' then
    if coalesce(pg_catalog.array_length(v_leads, 1), 0) > 0 then
      -- (auditor M2) se REVALIDA bajo los locks: sigue vivo, en etapa abierta y sigue siendo de la persona (un descarte o una
      -- conversión concurrentes solo bloquean el lead; la puerta del DNI de D-13 puede llevarse un suelto a otra persona).
      update crm.leads l
         set vendedor_id = p_nuevo_responsable,
             asignado_supervisor_id = null
       where l.id = any(v_leads)
         and l.activo = true
         and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
         and l.id in (select x from private.leads_de_personas(array[p_inversionista]) x);
      get diagnostics v_leads_movidos = row_count;
    end if;
    if v_inv.perfil_id is not null then
      update public.perfiles p
         set asesor_perfil_id = p_nuevo_responsable,
             actualizado_en = pg_catalog.clock_timestamp()
       where p.id = v_inv.perfil_id and p.rol = 'cliente' and p.activo is true
         and p.asesor_perfil_id is distinct from p_nuevo_responsable;
      v_perfil_movido := found;
    end if;
    -- (auditor N5) «movida» solo si algo se movió de verdad.
    if v_leads_movidos = 0 and not v_perfil_movido then
      v_tenencia := 'sin_cambios';
    end if;
  end if;
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
    'tramo_anterior_id', v_tramo.id, 'tramo_nuevo_id', v_nuevo_id, 'responsable_anterior', v_tramo.responsable_id, 'responsable_nuevo', p_nuevo_responsable,
    'tenencia', pg_catalog.jsonb_build_object('estado', v_tenencia, 'leads_movidos', v_leads_movidos, 'perfil_movido', v_perfil_movido));  -- F2.b [D-2]
end;
$function$
;

do $post$
begin
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='impacto_desactivacion_usuario_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid') is distinct from 'b160ad28bb544275c30724f41a2789e2' then
    raise exception 'POSTFLIGHT D-2: crm.impacto_desactivacion_usuario_fn(uuid) no quedó byte a byte como la genera gen-d2.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='fijar_membresia_activa_fn' and pg_get_function_identity_arguments(p.oid)='p_perfil_id uuid, p_activo boolean, p_reemplazo_id uuid, p_version_equipo timestamp with time zone, p_idempotencia uuid') is distinct from '59aa0b103e102b9813e347582c978b63' then
    raise exception 'POSTFLIGHT D-2: crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid) no quedó byte a byte como la genera gen-d2.py';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='crm' and p.proname='reasignar_responsable_relacion_fn' and pg_get_function_identity_arguments(p.oid)='p_inversionista uuid, p_nuevo_responsable uuid, p_motivo text') is distinct from '58fb9af195813b2361f40bb5517e0934' then
    raise exception 'POSTFLIGHT D-2: crm.reasignar_responsable_relacion_fn(uuid,uuid,text) no quedó byte a byte como la genera gen-d2.py';
  end if;
  if exists (select 1 from unnest(array['crm.impacto_desactivacion_usuario_fn(uuid)','crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)','crm.reasignar_responsable_relacion_fn(uuid,uuid,text)']) f(firma)
             where has_function_privilege('anon', f.firma, 'EXECUTE') or has_function_privilege('service_role', f.firma, 'EXECUTE')
                or not has_function_privilege('authenticated', f.firma, 'EXECUTE')
                or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = f.firma::regprocedure and a.grantee = 0))
     or exists (select 1 from pg_proc p where p.oid in ('crm.impacto_desactivacion_usuario_fn(uuid)'::regprocedure,'crm.fijar_membresia_activa_fn(uuid,boolean,uuid,timestamp with time zone,uuid)'::regprocedure,'crm.reasignar_responsable_relacion_fn(uuid,uuid,text)'::regprocedure) and not (p.prosecdef and p.proconfig @> array['search_path=""'])) then
    raise exception 'POSTFLIGHT D-2: los grants (solo authenticated; ni anon, ni service_role, ni PUBLIC) o definer/search_path de las tres cambiaron';
  end if;
  if (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure) is distinct from '6eded477639796c1053f0190f6decc18'
     or not exists (select 1 from pg_proc p where p.oid = 'private.leads_de_personas(uuid[])'::regprocedure and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception 'F2.b D-2: private.leads_de_personas(uuid[]) no es el texto vivo de producción (D-13) o perdió definer/search_path';
  end if;
  if coalesce((select activo from crm.multiempresa_flags where nombre='resolver_en_puertas'), false) then
    raise exception 'POSTFLIGHT D-2: la bandera quedó encendida';
  end if;
  raise notice 'F2.b D-2 OK: offboarding atómico sobre los tramos y capacidad operativa del nuevo responsable (rama ON). Bandera APAGADA.';
end
$post$;
commit;
