-- Fase F de la agenda comercial (plan v2): métricas de EJECUCIÓN de la agenda
-- por vendedor, para la vista de equipo de supervisor/gerencia.
--
-- Una sola RPC de LECTURA (jsonb), sin tablas nuevas, sin policies nuevas y
-- sin tocar grants de tablas: cero superficie RLS adicional. El recorte de
-- ámbito es el de la casa: private.vendedor_ids_visibles(uid) (vendedor = él;
-- supervisor = su subárbol recursivo; gerencia = todos) y
-- private.es_lector_global() da lectura total a directorio/admin.
--
-- Definiciones de las métricas (documentadas aquí porque el JSON es contrato):
--  * toques        = actividades de CONTACTO manual creadas POR el miembro en
--                    el periodo (llamada_realizada, llamada_no_contestada,
--                    whatsapp_enviado, whatsapp_recibido, reunion_realizada).
--                    'nota' es manual pero NO es contacto con el cliente.
--                    Atribución por creado_por (mismo criterio que la métrica
--                    de distribución: a.creado_por = analista).
--  * completadas / no_asistio / canceladas = tareas cerradas EN el periodo.
--                    Las tareas cerradas son inmutables (trigger), así que
--                    actualizado_en ES el instante del cierre.
--  * pct_completadas = completadas / cerradas del periodo (completadas +
--                    no_asistio + canceladas); null sin muestra.
--  * reprogramaciones = suma del contador de sistema sobre tareas TOCADAS en
--                    el periodo (actualizado_en) — aproximación honesta: el
--                    contador vive en la tarea, no hay log por movida.
--  * pendientes / vencidas / leads_sin_accion = FOTO ACTUAL (no periodo):
--                    la carga viva del vendedor. vencida se DERIVA
--                    (pendiente + vence_en < now()), jamás se guarda.
--  * El día se computa en America/Lima (regla de la casa).
--
-- PEN/USD: esta RPC no agrega dinero — no hay riesgo de mezcla de monedas.

begin;

set local lock_timeout = '10s';

create or replace function crm.metricas_agenda_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
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

  -- Gate fail-closed: miembro ACTIVO de crm.equipo (con perfil activo) o
  -- lector global. Igual semántica que las RPC de métricas existentes.
  select exists (
    select 1
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.perfil_id = v_uid and e.activo and p.activo
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

-- Grants: patrón de la casa para RPCs de métricas — nadie por default, solo
-- authenticated (la autorización real vive DENTRO de la función). El WARN de
-- advisors "authenticated_security_definer_function_executable" es la clase
-- ACEPTADA documentada (mismo criterio que cerrar_tarea/metricas_*).
revoke all on function crm.metricas_agenda_fn(date, date) from public, anon, authenticated, service_role;
grant execute on function crm.metricas_agenda_fn(date, date) to authenticated;

comment on function crm.metricas_agenda_fn(date, date) is
  'Fase F agenda: métricas de ejecución por vendedor (toques, cierres, no asistió, reprogramaciones, carga viva) recortadas por vendedor_ids_visibles/es_lector_global. Periodo en días calendario de America/Lima.';

commit;
