-- ============================================================================
-- C1 — Reparto de la cola de leads desde el CRM (rol `coordinador`)
--
-- Qué habilita: Rosa (rol nuevo `coordinador`, mínimo privilegio) ve la cola de
-- leads recién nacidos (vendedor_id NULL AND asignado_supervisor_id NULL) y los
-- reparte a la BANDEJA de un supervisor (setea asignado_supervisor_id, deja
-- vendedor_id NULL). El supervisor los baja a sus vendedores (fuera de C1).
--
-- Principio de diseño (mínimo privilegio): el coordinador tiene visibilidad ∅
-- sobre crm.leads por RLS. NO se añade `coordinador` a leads_select /
-- leads_update / es_lector_global. TODO el reparto vive en RPCs SECURITY
-- DEFINER con gate propio y proyección sin PII de contacto.
--
-- Plan: vault "Fase C1 — Reparto de la cola (plan build-ready)" (2026-07-21),
-- verificado por workflow de 15 agentes / 5 lentes adversariales.
--
-- Bloques: (a) CHECK de rol · (b) visibilidad ∅ · (c) [no-op documentado] ·
--          (d) RPC cola · (d-bis) RPC supervisores · (e) RPC reparto ·
--          (f) endurecimiento de superficies adyacentes.
-- ============================================================================

begin;
set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- (a) Rol 'coordinador' en el CHECK de crm.equipo
--     Hoy: vendedor|supervisor|gerencia (verificado en prod 2026-07-22).
--     PRERREQUISITO BLOQUEANTE: sin esto private.rol_crm nunca devuelve
--     'coordinador', el gate de las RPC falla 100% y enrolar a Rosa viola el
--     CHECK (23514). Va antes que todo lo demás.
--     El CHECK equipo_capacidad_leads_solo_analista NO se toca: la fila de Rosa
--     nace con capacidad_leads_objetivo = NULL y lo satisface.
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname = 'equipo_rol_crm_check' and conrelid = 'crm.equipo'::regclass
  ) then
    alter table crm.equipo drop constraint equipo_rol_crm_check;
  end if;
end $$;

alter table crm.equipo add constraint equipo_rol_crm_check
  check (rol_crm in ('vendedor','supervisor','gerencia','coordinador'));

-- ---------------------------------------------------------------------------
-- (b) private.vendedor_ids_visibles — rama `coordinador` explícita (→ ∅)
--     Cuerpo copiado VERBATIM de producción (2026-07-22) + la rama nueva.
--     Endurece la intención: sin ella el coordinador caería al `else -- vendedor`
--     devolviéndose a sí mismo (∅ efectivo hoy, pero implícito y frágil).
-- ---------------------------------------------------------------------------
create or replace function private.vendedor_ids_visibles(p_perfil_id uuid)
returns setof uuid
language plpgsql stable security definer
set search_path = crm, public
as $$
declare
  v_rol text;
begin
  if p_perfil_id is distinct from (select auth.uid())
     and not private.es_lector_global() then
    return; -- defensa en profundidad: no enumerar equipos ajenos
  end if;

  select rol_crm into v_rol
  from crm.equipo where perfil_id = p_perfil_id and activo = true;

  if v_rol is null then
    return;
  elsif v_rol = 'gerencia' then
    return query select perfil_id from crm.equipo; -- todos (activos o no)
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select perfil_id from crm.equipo where perfil_id = p_perfil_id
        union            -- UNION (no ALL): corta ciclos accidentales A↔B
        select e.perfil_id
        from crm.equipo e
        join subarbol s on e.supervisor_id = s.perfil_id
      )
      select perfil_id from subarbol;
  elsif v_rol = 'coordinador' then
    return; -- ∅: el coordinador NO posee cartera ni ve leads por RLS; su
            -- reparto vive SOLO en RPCs SECURITY DEFINER (mínimo privilegio).
            -- NO ampliar esto: hacerlo filtraría PII de la cola y de clientes.
  else -- vendedor
    return next p_perfil_id;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- (c) Policies RLS de crm.leads — SIN CAMBIOS (decisión, no omisión)
--     leads_select / leads_insert / leads_update y equipo_select quedan
--     intactas. Añadir `coordinador` filtraría la PII de la cola sin el shaping
--     de la RPC. NO añadir coordinador a las policies de leads.
--     Nota: leads_insert no niega por sí sola al coordinador; lo bloquea el
--     trigger private.trg_leads_guard_tenencia (destino debe ser vendedor o
--     supervisor activo). Cubierto por aserción en el gate.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- (d) RPC lectora — crm.leads_por_repartir()
--     Proyección SIN PII de contacto (Rosa enruta, no contacta: sin teléfono,
--     correo ni DNI). Excluye no_contactar = true (Ley 29571 "No Insista").
-- ---------------------------------------------------------------------------
create or replace function crm.leads_por_repartir()
returns table (
  id uuid, nombre_completo text, distrito text, origen text,
  categoria_interes text, monto_estimado numeric, moneda text,
  creado_en timestamptz
)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo actor_equipo
    join public.perfiles actor_perfil on actor_perfil.id = actor_equipo.perfil_id
    where actor_equipo.perfil_id = v_actor
      and actor_equipo.rol_crm in ('coordinador','gerencia')
      and actor_equipo.activo = true and actor_perfil.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver la cola de leads por repartir'
      using errcode = '42501';
  end if;

  return query
  select l.id, l.nombre_completo, l.distrito, l.origen,
         l.categoria_interes, l.monto_estimado, l.moneda, l.creado_en
  from crm.leads l
  where l.activo = true
    and l.vendedor_id is null
    and l.asignado_supervisor_id is null                     -- cola global (sin dueño)
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
    and l.no_contactar = false                               -- Ley 29571: nunca listar 'No Insista'
  order by l.creado_en asc;                                  -- FIFO justo
end;
$$;

comment on function crm.leads_por_repartir() is
  'Cola de leads nuevos sin dueño (vendedor_id y asignado_supervisor_id null) que el coordinador reparte. Sin PII de contacto. Excluye no_contactar=true (Ley 29571). Solo coordinador/gerencia activos.';

revoke all on function crm.leads_por_repartir() from public, anon;
grant execute on function crm.leads_por_repartir() to authenticated;

-- ---------------------------------------------------------------------------
-- (d-bis) RPC compañera — crm.supervisores_para_reparto()
--     Necesaria: el coordinador NO puede listar supervisores (equipo_select
--     solo lo muestra a sí mismo). Destino + carga de bandeja.
-- ---------------------------------------------------------------------------
create or replace function crm.supervisores_para_reparto()
returns table (perfil_id uuid, nombre text, activo boolean, bandeja_pendiente integer)
language plpgsql stable security definer set search_path = ''
as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede ver los supervisores de reparto'
      using errcode = '42501';
  end if;

  return query
  select e.perfil_id, p.nombre_completo, e.activo,
         (select count(*)::int from crm.leads l
           where l.asignado_supervisor_id = e.perfil_id
             and l.vendedor_id is null and l.activo = true
             and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
         ) as bandeja_pendiente
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.rol_crm = 'supervisor' and e.activo = true and p.activo = true
  order by p.nombre_completo;
end;
$$;

comment on function crm.supervisores_para_reparto() is
  'Supervisores activos elegibles como destino de reparto, con el conteo de su bandeja pendiente (leads en bandeja sin vendedor). Solo coordinador/gerencia activos.';

revoke all on function crm.supervisores_para_reparto() from public, anon;
grant execute on function crm.supervisores_para_reparto() to authenticated;

-- ---------------------------------------------------------------------------
-- (e) RPC de escritura — crm.repartir_lead(p_lead, p_supervisor)
--     Atómica: SELECT ... FOR UPDATE + UPDATE con predicado CAS.
--     Asume READ COMMITTED (default de PostgREST/Supabase): el perdedor de una
--     carrera re-evalúa el WHERE al desbloquear (EvalPlanQual), no encuentra
--     fila y recibe P0002. Bajo aislamiento mayor recibiría 40001 (también
--     seguro, sin doble-asignación); ambos mapeados en el frontend.
--
--     NO inserta actividad ni escribe el ledger: los triggers de crm.leads ya
--     hacen la actividad 'entra_bandeja' (autor = Rosa) y la auditoría.
-- ---------------------------------------------------------------------------
create or replace function crm.repartir_lead(p_lead uuid, p_supervisor uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_actor      uuid := (select auth.uid());
  v_lead       crm.leads%rowtype;
  v_sup_nombre text;
begin
  -- 1) Gate: coordinador|gerencia activos, con perfil de portal activo.
  if v_actor is null or not exists (
    select 1 from crm.equipo ae
    join public.perfiles ap on ap.id = ae.perfil_id
    where ae.perfil_id = v_actor
      and ae.rol_crm in ('coordinador','gerencia')
      and ae.activo = true and ap.activo = true
  ) then
    raise exception 'Solo el coordinador puede repartir leads' using errcode = '42501';
  end if;

  if p_lead is null or p_supervisor is null then
    raise exception 'Lead y supervisor destino son obligatorios' using errcode = '22023';
  end if;

  -- 2) Destino: supervisor ACTIVO. Mensaje humano antes de tocar la fila; el
  --    guard BEFORE lo revalida con la MISMA frase (defensa en profundidad).
  select p.nombre_completo into v_sup_nombre
  from crm.equipo e join public.perfiles p on p.id = e.perfil_id
  where e.perfil_id = p_supervisor
    and e.rol_crm = 'supervisor' and e.activo = true and p.activo = true;
  if not found then
    raise exception 'La bandeja destino no pertenece a un supervisor activo'
      using errcode = '22023';
  end if;

  -- 3) Toma el lead de la COLA GLOBAL y bloquéalo en la MISMA tx. Necesario
  --    para (a) leer no_contactar sobre la fila bloqueada y (b) dar el P0002
  --    con mensaje humano.
  select * into v_lead
  from crm.leads l
  where l.id = p_lead and l.activo = true
    and l.vendedor_id is null and l.asignado_supervisor_id is null
    and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  for update;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (tiene dueño, está cerrado o no existe)'
      using errcode = 'P0002';
  end if;

  -- 4) Re-validación legal server-side (Ley 29571 'No Insista').
  --    SQLSTATE PROPIO 'P0429' (NUNCA 42501): así el candado del gate no se
  --    satisface con un 42501 accidental de autorización, y el frontend
  --    distingue "veto legal" de "sin permiso". El RAISE revierte toda la tx.
  if v_lead.no_contactar then
    raise exception 'Lead marcado No Insista (Ley 29571): no se puede repartir'
      using errcode = 'P0429';
  end if;

  -- 5) UPDATE con CANDADO CAS: el predicado de tenencia va TAMBIÉN aquí (no
  --    solo en el SELECT del paso 3) → la mutación se auto-defiende de la
  --    carrera aunque un refactor futuro debilite el FOR UPDATE.
  update crm.leads
     set asignado_supervisor_id = p_supervisor
   where id = p_lead and activo = true
     and vendedor_id is null and asignado_supervisor_id is null;
  if not found then
    raise exception 'El lead ya no está en la cola por repartir (carrera de reparto)'
      using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'lead_id', p_lead,
    'asignado_supervisor_id', p_supervisor,
    'supervisor', v_sup_nombre,
    'repartido_por', v_actor,
    'repartido_en', statement_timestamp());
end;
$$;

comment on function crm.repartir_lead(uuid, uuid) is
  'El coordinador mueve un lead de la cola global a la bandeja de un supervisor activo (asignado_supervisor_id; vendedor_id sigue null). Re-valida no_contactar (Ley 29571) con SQLSTATE propio P0429. UPDATE con predicado CAS anti-carrera. Actividad y auditoría por trigger. Solo coordinador/gerencia activos. Asume READ COMMITTED.';

revoke all on function crm.repartir_lead(uuid, uuid) from public, anon;
grant execute on function crm.repartir_lead(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- (f) Endurecimiento de superficies ADYACENTES
--
--     Enrolar a Rosa hace que private.rol_crm(uid) deje de ser NULL, y hay
--     superficies gateadas por `rol_crm IS NOT NULL` que la admitirían sin que
--     ninguna policy de leads intervenga. Se llevan a la allowlist operativa
--     IN ('vendedor','supervisor','gerencia') (deny-by-default: coordinador y
--     cualquier rol futuro no-operativo quedan fuera).
--     Regresión CERO para vendedor/supervisor/gerencia/lector global.
--
--     f.1 crm.clientes_basicos_fn — NO SE TOCA (corrección al plan).
--         El plan citaba el cuerpo de 20260711000003 (gate global), pero la
--         definición VIVA en prod es la de 20260711000004: scopeada POR CARTERA
--         (lector global / gerencia ven todos; el resto solo clientes cuyo
--         asesor_perfil_id ∈ vendedor_ids_visibles) y con 2 columnas añadidas
--         después (tipo_documento, creado_por). Con esa definición el
--         coordinador ya obtiene 0 filas (no es lector global, no es gerencia y
--         su vendedor_ids_visibles es ∅ por (b)). Reemplazar el cuerpo por el
--         del plan habría (a) fallado por cambio de tipo de retorno y (b) de
--         pasar, REVERTIDO el scoping de cartera = fuga masiva de PII.
--         Verificado como aserción en el gate (coordinador → 0 filas).
-- ---------------------------------------------------------------------------

-- f.2 crm.existe_cliente_por_dni — oráculo de enumeración de DNIs.
--     Gate real en prod: `rol_crm IS NOT NULL or es_lector_global`, con RAISE
--     SIN errcode (→ P0001). Pasa a allowlist + errcode ESTABLE 42501.
--     coalesce por lógica trivaluada: rol_crm NULL sigue bloqueado.
create or replace function crm.existe_cliente_por_dni(p_dni text)
returns boolean
language plpgsql stable security definer
set search_path = private, public
as $$
begin
  if not (
    coalesce(private.rol_crm((select auth.uid()))
             in ('vendedor','supervisor','gerencia'), false)
    or private.es_lector_global()
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  return exists (
    select 1 from public.perfiles
    where dni = p_dni and rol = 'cliente' and activo = true
  );
end;
$$;

-- f.3 crm.objetivos — metas comerciales de gerencia. Policy → allowlist.
--     No se toca la RPC de escritura crm.fijar_objetivos ni los grants.
alter policy objetivos_select on crm.objetivos
  using (
    coalesce((select private.rol_crm((select auth.uid())))
             in ('vendedor','supervisor','gerencia'), false)
    or (select private.es_lector_global())
  );

-- f.4 crm.metricas_agenda_fn(date,date) — agregados de agenda del equipo.
--     Cuerpo copiado VERBATIM de producción (2026-07-22); el ÚNICO cambio es
--     el gate de miembro activo, que añade el filtro de rol operativo.
--     (Sin el filtro el coordinador pasaba el gate; el CTE `visibles` ya lo
--     dejaba en ∅ → payload vacío, sin fuga, pero se bloquea de raíz.)
--     ACL preservada por CREATE OR REPLACE.
create or replace function crm.metricas_agenda_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_es_lector boolean;
  v_miembro_activo boolean;
  v_hoy_lima date := (pg_catalog.now() at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_ahora timestamptz := pg_catalog.now();
  v_dias integer;
  v_payload jsonb;
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Gate fail-closed: miembro ACTIVO de crm.equipo (con perfil activo) y con
  -- ROL OPERATIVO, o lector global. El coordinador (C1) queda excluido: no
  -- lleva cartera ni supervisa, su ámbito de agenda es ∅ por definición.
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo
      and e.rol_crm in ('vendedor','supervisor','gerencia')
  ) into v_miembro_activo;

  v_es_lector := private.es_lector_global();

  if not v_miembro_activo and not v_es_lector then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- Validación de periodo (mismas reglas que metricas_distribucion):
  if p_desde is null or p_hasta is null then
    raise exception 'Periodo invalido: desde y hasta son obligatorios' using errcode = '22023';
  end if;
  if p_desde > p_hasta then
    raise exception 'Periodo invalido: desde no puede ser posterior a hasta' using errcode = '22023';
  end if;
  if p_hasta > v_hoy_lima then
    raise exception 'Periodo invalido: hasta no puede ser futuro' using errcode = '22023';
  end if;
  if p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido: maximo 366 dias' using errcode = '22023';
  end if;

  v_ini := (p_desde::timestamp) at time zone 'America/Lima';
  v_fin := ((p_hasta + 1)::timestamp) at time zone 'America/Lima';
  v_dias := (p_hasta - p_desde) + 1;

  with visibles as (
    -- Miembros del ámbito del caller con cartera propia posible (vendedor o
    -- supervisor; gerencia no lleva cartera). Lector global ve a todos.
    select e.perfil_id, p.nombre_completo, e.rol_crm, e.activo
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm in ('vendedor', 'supervisor')
      and (
        v_es_lector
        or e.perfil_id in (select private.vendedor_ids_visibles(v_uid))
      )
  ),
  toques as (
    select
      a.creado_por as perfil_id,
      count(*) filter (
        where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      ) as n_toques,
      count(*) filter (where a.tipo = 'reunion_realizada') as n_reuniones_realizadas
    from crm.actividades a
    where a.creado_por is not null
      and a.creado_en >= v_ini and a.creado_en < v_fin
    group by a.creado_por
  ),
  cierres as (
    select
      t.vendedor_id as perfil_id,
      count(*) filter (where t.estado = 'completada') as n_completadas,
      count(*) filter (where t.estado = 'no_show') as n_no_asistio,
      count(*) filter (where t.estado = 'cancelada') as n_canceladas
    from crm.tareas t
    where t.vendedor_id is not null
      and t.estado in ('completada','no_show','cancelada')
      and t.actualizado_en >= v_ini and t.actualizado_en < v_fin
    group by t.vendedor_id
  ),
  creadas as (
    select
      t.vendedor_id as perfil_id,
      count(*) as n_creadas,
      count(*) filter (where t.tipo = 'reunion') as n_reuniones_agendadas
    from crm.tareas t
    where t.vendedor_id is not null
      and t.creado_en >= v_ini and t.creado_en < v_fin
    group by t.vendedor_id
  ),
  movidas as (
    select
      t.vendedor_id as perfil_id,
      coalesce(sum(t.reprogramaciones), 0) as n_reprogramaciones
    from crm.tareas t
    where t.vendedor_id is not null
      and t.reprogramaciones > 0
      and t.actualizado_en >= v_ini and t.actualizado_en < v_fin
    group by t.vendedor_id
  ),
  foto as (
    select
      t.vendedor_id as perfil_id,
      count(*) filter (where t.estado = 'pendiente' and t.activo) as n_pendientes,
      count(*) filter (where t.estado = 'pendiente' and t.activo and t.vence_en < v_ahora) as n_vencidas
    from crm.tareas t
    where t.vendedor_id is not null
    group by t.vendedor_id
  ),
  sin_accion as (
    -- El amarillo del semáforo, por vendedor: lead abierto con dueño y sin
    -- tarea pendiente (mismo criterio que sinProximaAccion del frontend).
    select l.vendedor_id as perfil_id, count(*) as n_sin_accion
    from crm.leads l
    where l.activo
      and l.vendedor_id is not null
      and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
      and not exists (
        select 1 from crm.tareas t
        where t.lead_id = l.id and t.estado = 'pendiente' and t.activo
      )
    group by l.vendedor_id
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'periodo', jsonb_build_object(
      'desde', p_desde, 'hasta', p_hasta, 'dias', v_dias, 'zona', 'America/Lima'
    ),
    'vendedores', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', v.perfil_id,
            'nombre', v.nombre_completo,
            'rol', v.rol_crm,
            'activo', v.activo,
            'toques', coalesce(tq.n_toques, 0),
            'toques_por_dia', round(coalesce(tq.n_toques, 0)::numeric / v_dias, 1),
            'reuniones_realizadas', coalesce(tq.n_reuniones_realizadas, 0),
            'completadas', coalesce(c.n_completadas, 0),
            'no_asistio', coalesce(c.n_no_asistio, 0),
            'canceladas', coalesce(c.n_canceladas, 0),
            'pct_completadas', case
              when coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas, 0) > 0
              then round(
                100.0 * coalesce(c.n_completadas, 0)
                / (coalesce(c.n_completadas, 0) + coalesce(c.n_no_asistio, 0) + coalesce(c.n_canceladas, 0))
              )
              else null
            end,
            'tareas_creadas', coalesce(cr.n_creadas, 0),
            'reuniones_agendadas', coalesce(cr.n_reuniones_agendadas, 0),
            'reprogramaciones', coalesce(m.n_reprogramaciones, 0),
            'pendientes', coalesce(f.n_pendientes, 0),
            'vencidas', coalesce(f.n_vencidas, 0),
            'leads_sin_accion', coalesce(sa.n_sin_accion, 0)
          )
          order by v.nombre_completo
        )
        from visibles v
        left join toques tq on tq.perfil_id = v.perfil_id
        left join cierres c on c.perfil_id = v.perfil_id
        left join creadas cr on cr.perfil_id = v.perfil_id
        left join movidas m on m.perfil_id = v.perfil_id
        left join foto f on f.perfil_id = v.perfil_id
        left join sin_accion sa on sa.perfil_id = v.perfil_id
      ),
      '[]'::jsonb
    )
  )
  into v_payload;

  return v_payload;
end;
$$;

-- crm.metricas_distribucion_leads_autorizada ya es gerencia/lector-gated
-- (20260718152741) → el coordinador queda bloqueado sin cambio de SQL; se
-- asevera en el gate.

commit;
