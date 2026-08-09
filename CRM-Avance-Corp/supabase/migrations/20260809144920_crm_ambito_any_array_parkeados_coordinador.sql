-- ============================================================================
-- F1 tanda 2 (hermana) — optimización = any(array) de la familia de ámbito
--                        + parkeados del coordinador en las métricas
-- ============================================================================
-- Dos notas del ledger de la tanda 1 (20260809043802) aprobadas por Miguel el
-- 2026-08-09:
--
-- (a) OPTIMIZACIÓN DE ÁMBITO: el patrón heredado `col in (select
--     private.vendedor_ids_visibles(uid))` se ejecuta como SubPlan por fila y
--     NUNCA usa índice sobre `col`. Se captura el resultado UNA vez en un
--     array (`v_visibles`) y se filtra con `col = any(v_visibles)`, que sí es
--     indexable (idx_leads_vendedor / idx_leads_parkeo / idx_actividades_lead).
--     ALCANCE DELIBERADO — solo las funciones que ESCANEAN leads/actividades,
--     donde el SubPlan escala con la data:
--       resumen_cartera_fn, cola_accion_fn, metricas_vendedores_fn,
--       series_comerciales_fn, estado_sla_leads_fn, actividades_del_ambito_fn.
--     Quedan FUERA a propósito:
--       - configuracion_metas_fn / cumplimiento_metas_fn /
--         metricas_agenda_implementacion: su `in (select ...)` filtra tablas
--         del tamaño del ROSTER (equipo, metas_vendedor) — regla de exclusión
--         del plan: no sobre-ingeniar conjuntos acotados por el roster.
--       - clientes_basicos_fn / contratos_cartera_fn: F2 las re-arquitectura
--         con keyset (mi-cartera); además la definición viva de
--         clientes_basicos_fn NO está versionada as-built en este repo (drift
--         documentado en el ledger de 20260721120000) y la regla F0 prohíbe
--         modificar funciones no versionadas.
--
-- (b) PARKEADOS DEL COORDINADOR: la tanda 1 dejó al coordinador con agregados
--     vacíos (predicado real de estado_sla_leads_fn). Miguel aprobó darle la
--     rama de parkeados del predicado canónico del plan F1: en las RPC de
--     AGREGADOS PUROS donde los sin-dueño LLEGAN al payload (resumen_cartera_fn
--     y series_comerciales_fn) la rama pasa a
--       (vendedor_id is null and (asignado_supervisor_id = any(visibles)
--                                 or puede_operar_reparto_crm()))
--     → el coordinador ve los números de TODOS los sin-dueño (cola global +
--     bandejas), que es exactamente su negocio. NO la reciben:
--       - cola_accion_fn — DELIBERADO: sus items llevan PII de contacto
--         (teléfono/correo) y la premisa C1 del coordinador es "enruta, no
--         contacta" (su cola, leads_por_repartir, redacta hasta el comentario).
--         Su superficie agregada es resumen_reparto_fn (20260809144912).
--       - metricas_vendedores_fn — hallazgo del auditor: TODO su payload se
--         agrega vía roster/agg_duenio (vendedor_id not null); la rama habría
--         sido código muerto (el coordinador pagaría el escaneo y recibiría
--         vacío igual). Sus números de parkeados viven en resumen_cartera_fn.
--       - estado_sla_leads_fn y actividades_del_ambito_fn — son filas
--         (SLA/timeline), no agregados; ampliarlas sería otra decisión.
--
-- Los cuerpos son los as-built de prod (paridad md5 verificada hoy 6/6 antes
-- de editar) con SOLO los cambios descritos. Sin cambio de payload ni de
-- firma; los grants se re-asientan idénticos (regla permanente #9).
-- ============================================================================

begin;
set local lock_timeout = '10s';

-- ============================================================================
-- 1. resumen_cartera_fn — = any(v_visibles) + parkeados del coordinador
-- ============================================================================

create or replace function crm.resumen_cartera_fn()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_reparto boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_reparto := private.puede_operar_reparto_crm();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_corte := v_ahora - interval '45 days'; -- ventana_convertidos_dias

  with ambito as materialized (
    select l.id, l.etapa, l.moneda,
           coalesce(l.monto_estimado, 0) as monto,
           l.vendedor_id, l.motivo_descarte,
           (l.etapa not in ('convertido', 'descartado')) as abierto
    from crm.leads l
    where l.activo is true
      and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
      and (
        l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null
            and (l.asignado_supervisor_id = any(v_visibles) or v_reparto))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  -- Abiertos ASIGNADOS que nadie ha CONTACTADO jamás (los 5 tipos de
  -- TIPOS_CONTACTO, espejo del índice parcial actividades_contacto_episodio_idx;
  -- una `reasignacion` del sistema no cuenta como trabajo comercial).
  sin_contacto as (
    select count(*)::int as n
    from ambito a
    where a.abierto
      and a.vendedor_id is not null
      and not exists (
        select 1 from crm.actividades act
        where act.lead_id = a.id
          and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                           'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
      )
  ),
  embudo as (
    select jsonb_agg(
             jsonb_build_object('etapa', e.etapa, 'n', coalesce(c.n, 0))
             order by e.orden
           ) as j
    from unnest(array['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada',
                      'convertido', 'descartado']) with ordinality as e(etapa, orden)
    left join (
      select a.etapa, count(*)::int as n from ambito a group by a.etapa
    ) c on c.etapa = e.etapa
  ),
  descartes_motivo as (
    select coalesce(
             jsonb_agg(jsonb_build_object('motivo', d.motivo_descarte, 'n', d.n)
                       order by d.n desc, d.motivo_descarte),
             '[]'::jsonb
           ) as j
    from (
      select a.motivo_descarte, count(*)::int as n
      from ambito a
      where a.etapa = 'descartado' and a.motivo_descarte is not null
      group by a.motivo_descarte
    ) d
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'ventana_convertidos_dias', 45,
    'totales', jsonb_build_object(
      'vivos', count(*),
      'abiertos', count(*) filter (where a.abierto),
      'asignados', count(*) filter (where a.abierto and a.vendedor_id is not null),
      'parkeados', count(*) filter (where a.abierto and a.vendedor_id is null),
      'convertidos', count(*) filter (where a.etapa = 'convertido'),
      'descartados', count(*) filter (where a.etapa = 'descartado'),
      -- El donut de directorio cuenta sobre ASIGNADOS (los parkeados no
      -- cuentan como activos ni suman capital) — el nombre no debe mentir.
      'asignados_pen', count(*) filter (where a.abierto and a.vendedor_id is not null and a.moneda is distinct from 'USD'),
      'asignados_usd', count(*) filter (where a.abierto and a.vendedor_id is not null and a.moneda = 'USD')
    ),
    'capital', jsonb_build_object(
      'asignado', jsonb_build_object(
        'pen', coalesce(sum(a.monto) filter (where a.abierto and a.vendedor_id is not null and a.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(a.monto) filter (where a.abierto and a.vendedor_id is not null and a.moneda = 'USD'), 0)
      ),
      'parkeado', jsonb_build_object(
        'pen', coalesce(sum(a.monto) filter (where a.abierto and a.vendedor_id is null and a.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(a.monto) filter (where a.abierto and a.vendedor_id is null and a.moneda = 'USD'), 0)
      ),
      'ganado', jsonb_build_object(
        'pen', coalesce(sum(a.monto) filter (where a.etapa = 'convertido' and a.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(a.monto) filter (where a.etapa = 'convertido' and a.moneda = 'USD'), 0)
      )
    ),
    -- Espejo de conversionGlobal: base = vivos CON vendedor (terminales
    -- incluidos; los parkeados no cuentan porque nadie los trabaja).
    'conversion', jsonb_build_object(
      'convertidos', count(*) filter (where a.etapa = 'convertido' and a.vendedor_id is not null),
      'base', count(*) filter (where a.vendedor_id is not null),
      'pct', case
        when count(*) filter (where a.vendedor_id is not null) > 0
        then round(100.0 * (count(*) filter (where a.etapa = 'convertido' and a.vendedor_id is not null))
                   / (count(*) filter (where a.vendedor_id is not null)))::int
        else 0
      end
    ),
    'descartes', jsonb_build_object(
      'total', count(*) filter (where a.etapa = 'descartado'),
      'sin_motivo', count(*) filter (where a.etapa = 'descartado' and a.motivo_descarte is null),
      'por_motivo', (select j from descartes_motivo)
    ),
    'embudo', (select j from embudo),
    'sin_tocar', (select n from sin_contacto)
  )
  into v_payload
  from ambito a;

  return v_payload;
end;
$function$;

comment on function crm.resumen_cartera_fn() is
  'Resumen agregado del ambito visible (capital por moneda, embudo, conversion, descartes, sin tocar). Ventana de convertidos de 45 dias. PEN y USD jamas se suman. El coordinador ve los agregados de TODOS los parkeados (rama puede_operar_reparto_crm).';

revoke all on function crm.resumen_cartera_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.resumen_cartera_fn() to authenticated;

-- ============================================================================
-- 2. cola_accion_fn — = any(v_visibles); SIN rama de coordinador (PII, C1)
-- ============================================================================

create or replace function crm.cola_accion_fn(p_limite integer default 100)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy_lima date;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 500 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_hoy_lima := (v_ahora at time zone 'America/Lima')::date;

  -- Tubería ESTRECHA: la clasificación viaja solo con id + señales; las
  -- columnas del lead (PII incluida) se unen AL FINAL, tras el LIMIT.
  -- Transportar filas anchas por toda la cadena de CTEs materializaba cientos
  -- de MB por llamada a escala 1M (hallazgo de la auditoría de rendimiento).
  with abiertos as (
    select l.id, l.etapa, l.creado_en, l.tenencia_desde, l.vendedor_id, l.ciclo_actual
    from crm.leads l
    where l.activo is true
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and (
        l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null
            and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  enriquecidos as (
    select a.*,
      uc.creado_en as ultimo_contacto_en,
      uc.tipo as ultimo_contacto_tipo,
      ua.creado_en as ultima_actividad_en,
      -- referenciaEspera: max(último CONTACTO ?? creado_en, tenencia_desde).
      -- greatest ignora NULL en SQL, así que la tenencia ausente degrada sola.
      greatest(coalesce(uc.creado_en, a.creado_en), a.tenencia_desde) as referencia_espera_en,
      (pv.tiene is true) as plan_vigente,
      tm.titulo as tarea_titulo,
      tm.vence_en as tarea_vence_en,
      c.primera_gestion_limite_en as ciclo_gestion_limite,
      c.primera_gestion_en as ciclo_gestion_en,
      c.primer_contacto_limite_en as ciclo_contacto_limite,
      c.primer_contacto_en as ciclo_contacto_en,
      asg.id as asignacion_id,
      asg.primera_gestion_limite_en as asg_gestion_limite,
      ah.primera_gestion_en as asg_gestion_en,
      asg.primer_contacto_limite_en as asg_contacto_limite,
      ah.primer_contacto_en as asg_contacto_en,
      e.iniciado_en as etapa_inicio,
      e.limite_en as etapa_limite,
      pe.version as etapa_politica_version
    from abiertos a
    -- Último CONTACTO real (¿el asesor TRABAJÓ el lead?): los 5 tipos de
    -- TIPOS_CONTACTO. Jamás cualquier fila del timeline (auditoría 2026-07-25).
    left join lateral (
      select act.creado_en, act.tipo
      from crm.actividades act
      where act.lead_id = a.id
        and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                         'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
      order by act.creado_en desc
      limit 1
    ) uc on true
    -- Última actividad de CUALQUIER tipo (rótulo "Última actividad" del front;
    -- alimenta `estancados`, que mide inactividad pura).
    left join lateral (
      select act.creado_en
      from crm.actividades act
      where act.lead_id = a.id
      order by act.creado_en desc
      limit 1
    ) ua on true
    -- Plan VIGENTE (plan-lead.ts): tarea pendiente+activa del lead cuyo día
    -- calendario de Lima aún no pasó. Una tarea vencida NO es un plan.
    left join lateral (
      select true as tiene
      from crm.tareas t
      where t.lead_id = a.id
        and t.estado = 'pendiente'
        and t.activo is true
        and (t.vence_en at time zone 'America/Lima')::date >= v_hoy_lima
      limit 1
    ) pv on true
    -- La tarea vencida MÁS VIEJA (bucket residual plan_vencido).
    left join lateral (
      select t.titulo, t.vence_en
      from crm.tareas t
      where t.lead_id = a.id
        and t.estado = 'pendiente'
        and t.activo is true
        and (t.vence_en at time zone 'America/Lima')::date < v_hoy_lima
      order by t.vence_en asc
      limit 1
    ) tm on true
    -- Fotografías SLA SELLADAS por episodio (jamás recalculadas de la política
    -- vigente): ciclo actual, asignación abierta con sus hitos, episodio de
    -- etapa abierto que coincida con la etapa actual del lead.
    left join crm.lead_sla_ciclos c
      on c.lead_id = a.id and c.ciclo_n = a.ciclo_actual
    left join lateral (
      select la.id, la.primera_gestion_limite_en, la.primer_contacto_limite_en
      from crm.lead_asignaciones la
      where la.lead_id = a.id and la.finalizado_en is null
      order by la.episodio_n desc
      limit 1
    ) asg on true
    left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id = asg.id
    left join crm.lead_sla_etapas e
      on e.lead_id = a.id and e.ciclo_n = a.ciclo_actual
      and e.finalizado_en is null and e.etapa = a.etapa
    left join crm.sla_politicas pe on pe.id = e.politica_id
  ),
  clasificados as (
    select en.*,
      greatest(extract(epoch from (v_ahora - en.referencia_espera_en)) / 86400.0, 0) as dias,
      -- Para el dueño actual manda la fotografía de SU asignación; sin
      -- asignación abierta, la del ciclo global (mismo criterio que colaDe).
      (case when en.asignacion_id is not null then en.asg_gestion_en else en.ciclo_gestion_en end) is null
        and (case when en.asignacion_id is not null then en.asg_gestion_limite else en.ciclo_gestion_limite end) is not null
        and v_ahora >= (case when en.asignacion_id is not null then en.asg_gestion_limite else en.ciclo_gestion_limite end)
        as gestion_vencida,
      (case when en.asignacion_id is not null then en.asg_contacto_en else en.ciclo_contacto_en end) is null
        and (case when en.asignacion_id is not null then en.asg_contacto_limite else en.ciclo_contacto_limite end) is not null
        and v_ahora >= (case when en.asignacion_id is not null then en.asg_contacto_limite else en.ciclo_contacto_limite end)
        as contacto_vencido,
      (en.etapa_inicio is not null and en.etapa_limite is not null
        and en.etapa_limite > en.etapa_inicio) as etapa_valida,
      case when en.etapa_inicio is not null
        then greatest(extract(epoch from (v_ahora - en.etapa_inicio)) / 86400.0, 0)
        else 0
      end as dias_en_etapa
    from enriquecidos en
  ),
  -- La cascada de colaDe, en su MISMO orden. NULL = el lead no está en la cola.
  bucketizados as materialized (
    select cl.*,
      case
        when cl.vendedor_id is null then 'por_repartir'
        when cl.etapa = 'nuevo' and cl.ultimo_contacto_en is null then 'sin_responder'
        when cl.etapa_valida and cl.ultimo_contacto_en is not null
             and v_ahora >= cl.etapa_limite + (cl.etapa_limite - cl.etapa_inicio) then 'sin_avance'
        when cl.plan_vigente then null -- su cola es la agenda, no esta
        when cl.etapa = 'nuevo' and cl.ultimo_contacto_en is not null and cl.dias >= 1 then 'insistir'
        when cl.etapa = 'propuesta_enviada' and cl.dias >= 5 then 'propuesta_sin_respuesta'
        when cl.etapa in ('contactado', 'reunion_agendada') and cl.dias >= 3 then 'seguimiento'
        when cl.tarea_titulo is not null then 'plan_vencido'
        else null
      end as bucket
    from clasificados cl
  ),
  items_full as materialized (
    select bz.*,
      case bz.bucket
        when 'por_repartir' then 'critica'
        when 'sin_responder' then
          case when bz.gestion_vencida or bz.contacto_vencido then 'critica' else 'media' end
        when 'seguimiento' then 'baja'
        when 'plan_vencido' then 'baja'
        else 'media'
      end as sev,
      case bz.bucket
        when 'sin_avance' then bz.dias_en_etapa
        when 'plan_vencido' then greatest(extract(epoch from (v_ahora - bz.tarea_vence_en)) / 86400.0, 0)
        else bz.dias
      end as dias_item
    from bucketizados bz
    where bz.bucket is not null
  ),
  ordenados as (
    select *
    from items_full
    order by case sev when 'critica' then 0 when 'media' then 1 else 2 end,
             dias_item desc, id
    limit p_limite
  ),
  -- Estancados del supervisor: inactividad PURA (cualquier tipo de actividad),
  -- excluyendo a quien tiene un plan vigente — tiene una fecha, no está solo.
  estancados_top as (
    select bz.id, bz.vendedor_id,
      greatest(extract(epoch from (v_ahora - coalesce(bz.ultima_actividad_en, bz.creado_en))) / 86400.0, 0) as dias
    from bucketizados bz
    where bz.plan_vigente is not true
      and greatest(extract(epoch from (v_ahora - coalesce(bz.ultima_actividad_en, bz.creado_en))) / 86400.0, 0) >= 5
    order by dias desc, bz.id
    limit 50
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'p_limite', p_limite,
    'resumen', jsonb_build_object(
      'total', (select count(*) from items_full),
      'por_bucket', coalesce(
        (select jsonb_object_agg(x.bucket, x.n)
         from (select f.bucket, count(*)::int as n from items_full f group by f.bucket) x),
        '{}'::jsonb),
      'por_sev', coalesce(
        (select jsonb_object_agg(y.sev, y.n)
         from (select f.sev, count(*)::int as n from items_full f group by f.sev) y),
        '{}'::jsonb)
    ),
    'items', coalesce(
      (select jsonb_agg(
        jsonb_build_object(
          'lead_id', o.id,
          'bucket', o.bucket,
          'sev', o.sev,
          'dias', round(o.dias_item, 4),
          'ultimo_contacto_en', o.ultimo_contacto_en,
          'datos_motivo', case o.bucket
            when 'sin_responder' then jsonb_build_object(
              'espera_cliente_dias',
                round(greatest(extract(epoch from (v_ahora - o.creado_en)) / 86400.0, 0), 4),
              'gestion_vencida', o.gestion_vencida,
              'contacto_vencido', o.contacto_vencido)
            when 'sin_avance' then jsonb_build_object(
              'dias_en_etapa', round(o.dias_en_etapa, 4),
              'etapa_politica_version', o.etapa_politica_version)
            when 'insistir' then jsonb_build_object(
              'ultimo_intento_dias',
                round(greatest(extract(epoch from (v_ahora - o.ultimo_contacto_en)) / 86400.0, 0), 4),
              'hablo', o.ultimo_contacto_tipo in ('llamada_realizada', 'whatsapp_recibido', 'reunion_realizada'),
              'dos_relojes',
                (greatest(extract(epoch from (v_ahora - o.ultimo_contacto_en)) / 86400.0, 0) - o.dias) >= 1)
            when 'plan_vencido' then jsonb_build_object(
              'tarea_titulo', o.tarea_titulo,
              'tarea_vence_en', o.tarea_vence_en)
            else '{}'::jsonb
          end,
          -- Las columnas del lead se leen AQUÍ, por PK y solo para las ≤500
          -- filas que sobrevivieron al LIMIT (misma foto: un solo statement).
          'lead', jsonb_build_object(
            'nombre_completo', l.nombre_completo,
            'telefono', l.telefono,
            'correo', l.correo,
            'genero', l.genero,
            'no_contactar', l.no_contactar,
            'etapa', l.etapa,
            'origen', l.origen,
            'categoria_interes', l.categoria_interes,
            'monto_estimado', coalesce(l.monto_estimado, 0),
            'moneda', l.moneda,
            'creado_en', l.creado_en,
            'tenencia_desde', l.tenencia_desde,
            'vendedor_id', l.vendedor_id,
            'asignado_supervisor_id', l.asignado_supervisor_id,
            'motivo_descarte', l.motivo_descarte)
        )
        order by case o.sev when 'critica' then 0 when 'media' then 1 else 2 end,
                 o.dias_item desc, o.id
      ) from ordenados o join crm.leads l on l.id = o.id),
      '[]'::jsonb),
    'estancados', jsonb_build_object(
      'umbral_dias', 5,
      'tope', 50,
      'items', coalesce(
        (select jsonb_agg(
           jsonb_build_object(
             'lead_id', et.id,
             'nombre_completo', l.nombre_completo,
             'vendedor_id', et.vendedor_id,
             'dias', round(et.dias, 4))
           order by et.dias desc, et.id
         ) from estancados_top et join crm.leads l on l.id = et.id),
        '[]'::jsonb)
    )
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.cola_accion_fn(integer) is
  'Cola de accion con buckets calculados en el servidor (espejo de colaDe): un bucket por lead abierto, ingredientes del motivo, ultimo_contacto_en para el semaforo del kanban, y lista de estancados. p_limite recorta el payload (1..500). SIN rama de coordinador: sus items llevan PII de contacto (premisa C1).';

revoke all on function crm.cola_accion_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.cola_accion_fn(integer) to authenticated;

-- ============================================================================
-- 3. metricas_vendedores_fn — = any(v_visibles), SIN rama de coordinador
-- ============================================================================
-- Todo su payload se agrega vía roster/agg_duenio (vendedor_id not null): la
-- rama de parkeados habría sido código muerto (hallazgo del auditor).

create or replace function crm.metricas_vendedores_fn()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_corte := v_ahora - interval '45 days'; -- ventana_convertidos_dias

  with roster as materialized (
    select e.perfil_id, e.rol_crm, e.activo
    from crm.equipo e
    where e.rol_crm in ('vendedor', 'supervisor', 'gerencia')
      and (
        e.perfil_id = any(v_visibles)
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  ambito as materialized (
    select l.id, l.etapa, l.moneda,
           coalesce(l.monto_estimado, 0) as monto,
           l.vendedor_id, l.asignado_supervisor_id, l.creado_en,
           (l.etapa not in ('convertido', 'descartado')) as abierto
    from crm.leads l
    where l.activo is true
      and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
      and (
        l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null
            and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  por_vendedor as (
    select r.perfil_id, r.rol_crm, r.activo,
      count(a.id) filter (where a.abierto)::int as activos,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda is distinct from 'USD'), 0) as capital_pen,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda = 'USD'), 0) as capital_usd,
      count(a.id) filter (where a.etapa = 'convertido')::int as convertidos,
      count(a.id)::int as total
    from roster r
    left join ambito a on a.vendedor_id = r.perfil_id
    group by r.perfil_id, r.rol_crm, r.activo
  ),
  -- Señales de trabajo sobre los ABIERTOS de cada miembro: contacto jamás
  -- hecho (sin_tocar) y el abierto más abandonado (cualquier actividad).
  senales as (
    select r.perfil_id,
      count(*) filter (where uc.lead_id is null)::int as sin_tocar,
      coalesce(max(extract(epoch from (v_ahora - coalesce(ua.ultima, a.creado_en))) / 86400.0), 0) as dias_max
    from roster r
    join ambito a on a.vendedor_id = r.perfil_id and a.abierto
    left join lateral (
      select act.lead_id
      from crm.actividades act
      where act.lead_id = a.id
        and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                         'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
      limit 1
    ) uc on true
    left join lateral (
      select max(act.creado_en) as ultima
      from crm.actividades act
      where act.lead_id = a.id
    ) ua on true
    group by r.perfil_id
  ),
  -- Una sola pasada por el ámbito para la comparativa (la versión por
  -- supervisor con laterales re-escaneaba el ámbito completo 2·S veces —
  -- hallazgo de la auditoría de rendimiento). agg_duenio y parkeados_bandeja
  -- son del tamaño del roster; los laterales de equipos_calc iteran sobre
  -- ellos y sobre crm.equipo (tabla minúscula), nunca sobre los leads.
  agg_duenio as (
    select a.vendedor_id,
      count(*) filter (where a.abierto)::int as activos,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda is distinct from 'USD'), 0) as capital_pen,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda = 'USD'), 0) as capital_usd,
      count(*) filter (where a.etapa = 'convertido')::int as convertidos,
      count(*)::int as total
    from ambito a
    where a.vendedor_id is not null
    group by a.vendedor_id
  ),
  parkeados_bandeja as (
    select a.asignado_supervisor_id as supervisor_id, count(*)::int as n
    from ambito a
    where a.abierto and a.vendedor_id is null and a.asignado_supervisor_id is not null
    group by a.asignado_supervisor_id
  ),
  -- Espejo de comparativaEquipos: reportes DIRECTOS activos de CUALQUIER rol
  -- (igual que el front, que no filtra rol) más el propio supervisor.
  equipos_calc as (
    select s.perfil_id as supervisor_id,
      directos.n as vendedores,
      stats.activos, stats.capital_pen, stats.capital_usd,
      stats.convertidos, stats.asignados_total,
      coalesce(pb.n, 0) as parkeados
    from roster s
    cross join lateral (
      select count(*)::int as n
      from crm.equipo m
      where m.supervisor_id = s.perfil_id and m.activo is true
    ) directos
    cross join lateral (
      select coalesce(sum(ad.activos), 0)::int as activos,
             coalesce(sum(ad.capital_pen), 0) as capital_pen,
             coalesce(sum(ad.capital_usd), 0) as capital_usd,
             coalesce(sum(ad.convertidos), 0)::int as convertidos,
             coalesce(sum(ad.total), 0)::int as asignados_total
      from agg_duenio ad
      where ad.vendedor_id = s.perfil_id
         or ad.vendedor_id in (
              select m.perfil_id from crm.equipo m
              where m.supervisor_id = s.perfil_id and m.activo is true
            )
    ) stats
    left join parkeados_bandeja pb on pb.supervisor_id = s.perfil_id
    where s.rol_crm = 'supervisor' and s.activo is true
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'ventana_convertidos_dias', 45,
    'vendedores', coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'vendedor_id', pv.perfil_id,
           'rol_crm', pv.rol_crm,
           'activo', pv.activo,
           'activos', pv.activos,
           'capital_pen', pv.capital_pen,
           'capital_usd', pv.capital_usd,
           'convertidos', pv.convertidos,
           'conversion_pct', case when pv.total > 0
             then round(100.0 * pv.convertidos / pv.total)::int else 0 end,
           'sin_tocar', coalesce(sn.sin_tocar, 0),
           'dias_sin_actividad_max', round(coalesce(sn.dias_max, 0), 4)
         )
         order by pv.capital_pen desc, pv.perfil_id
       )
       from por_vendedor pv
       left join senales sn on sn.perfil_id = pv.perfil_id),
      '[]'::jsonb),
    'equipos', coalesce(
      (select jsonb_agg(
         jsonb_build_object(
           'supervisor_id', ec.supervisor_id,
           'vendedores', ec.vendedores,
           'activos', ec.activos,
           'capital_pen', ec.capital_pen,
           'capital_usd', ec.capital_usd,
           'convertidos', ec.convertidos,
           'conversion_pct', case when ec.asignados_total > 0
             then round(100.0 * ec.convertidos / ec.asignados_total)::int else 0 end,
           'parkeados', ec.parkeados
         )
         order by ec.capital_pen desc, ec.supervisor_id
       )
       from equipos_calc ec),
      '[]'::jsonb)
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.metricas_vendedores_fn() is
  'Ranking por vendedor (activos, capital por moneda, convertidos con ventana de 45 dias, sin_tocar, dias_sin_actividad_max) y comparativa de equipos por supervisor activo con sus parkeados. Sin nombres: el front une por id con su roster. Sin rama de coordinador: su payload agrega solo duenos con vendedor.';

revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_vendedores_fn() to authenticated;

-- ============================================================================
-- 4. series_comerciales_fn — = any(v_visibles) + parkeados del coordinador
-- ============================================================================

create or replace function crm.series_comerciales_fn(p_meses integer default 6)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_reparto boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_fin date;
  v_ini timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_meses is null or p_meses < 1 or p_meses > 24 then
    raise exception 'Parametro p_meses invalido' using errcode = '22023';
  end if;
  v_reparto := private.puede_operar_reparto_crm();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_mes_fin := date_trunc('month', (v_ahora at time zone 'America/Lima'))::date;
  -- Primer instante (Lima) del mes inicial de la ventana: filtra el barrido a
  -- altas dentro de la ventana o leads con contrato (su cierre puede caer en
  -- la ventana aunque el alta sea anterior).
  v_ini := ((v_mes_fin - make_interval(months => p_meses - 1))::timestamp at time zone 'America/Lima');

  with meses as materialized (
    select (v_mes_fin - make_interval(months => (p_meses - 1 - g.n)))::date as mes,
           g.n as orden
    from generate_series(0, p_meses - 1) as g(n)
  ),
  ambito as materialized (
    select date_trunc('month', (l.creado_en at time zone 'America/Lima'))::date as mes_alta,
           case when l.contrato_id is not null then
             date_trunc('month', (coalesce(l.convertido_en, l.actualizado_en, l.creado_en)
                                  at time zone 'America/Lima'))::date
           end as mes_cierre,
           (l.contrato_id is not null) as es_cliente,
           l.moneda,
           coalesce(l.monto_estimado, 0) as monto
    from crm.leads l
    where l.activo is true
      and (l.creado_en >= v_ini or l.contrato_id is not null)
      and (
        l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null
            and (l.asignado_supervisor_id = any(v_visibles) or v_reparto))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  altas as (
    select a.mes_alta as mes,
           count(*)::int as nuevos,
           count(*) filter (where a.es_cliente)::int as cohorte
    from ambito a
    group by a.mes_alta
  ),
  cierres as (
    select a.mes_cierre as mes,
           count(*)::int as cierres,
           coalesce(sum(a.monto) filter (where a.moneda = 'PEN'), 0) as capital_pen,
           coalesce(sum(a.monto) filter (where a.moneda = 'USD'), 0) as capital_usd
    from ambito a
    where a.mes_cierre is not null
    group by a.mes_cierre
  ),
  serie as (
    select m.orden,
           to_char(m.mes, 'YYYY-MM') as clave,
           coalesce(al.nuevos, 0) as nuevos,
           coalesce(al.cohorte, 0) as cohorte,
           coalesce(ci.cierres, 0) as n_cierres,
           coalesce(ci.capital_pen, 0) as capital_pen,
           coalesce(ci.capital_usd, 0) as capital_usd
    from meses m
    left join altas al on al.mes = m.mes
    left join cierres ci on ci.mes = m.mes
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'zona', 'America/Lima',
    'meses', jsonb_agg(s.clave order by s.orden),
    'nuevos', jsonb_agg(s.nuevos order by s.orden),
    'cohorte_clientes', jsonb_agg(s.cohorte order by s.orden),
    'cierres', jsonb_agg(s.n_cierres order by s.orden),
    'capital_pen', jsonb_agg(s.capital_pen order by s.orden),
    'capital_usd', jsonb_agg(s.capital_usd order by s.orden),
    -- Espejo exacto del redondeo del front: Math.round(x*1000)/10 (1 decimal).
    'conversion_pct', jsonb_agg(
      case when s.nuevos > 0 then round(1000.0 * s.cohorte / s.nuevos) / 10.0 else 0 end
      order by s.orden)
  )
  into v_payload
  from serie s;

  return v_payload;
end;
$function$;

comment on function crm.series_comerciales_fn(integer) is
  'Series mensuales de Lima (ascendentes, mes vigente al final): altas, cohorte con contrato, cierres y capital POR MONEDA al mes de cierre (sello canonico convertido_en). Historico: sin ventana de convertidos. p_meses 1..24. El coordinador ve las series de los parkeados (rama puede_operar_reparto_crm).';

revoke all on function crm.series_comerciales_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.series_comerciales_fn(integer) to authenticated;

-- ============================================================================
-- 5. estado_sla_leads_fn — = any(v_visibles), sin cambio de visibilidad
-- ============================================================================
-- Cuerpo as-built de 20260807203757 con SOLO la captura del array. Devuelve
-- FILAS por lead (no agregados): la rama del coordinador NO se añade.

create or replace function crm.estado_sla_leads_fn()
returns table(
  lead_id uuid,
  ciclo_politica_id uuid,
  ciclo_politica_version integer,
  primera_gestion_limite_en timestamptz,
  primera_gestion_en timestamptz,
  primer_contacto_limite_en timestamptz,
  primer_contacto_en timestamptz,
  ciclo_aproximado boolean,
  asignacion_id uuid,
  asignacion_politica_id uuid,
  asignacion_politica_version integer,
  asignacion_primera_gestion_limite_en timestamptz,
  asignacion_primera_gestion_en timestamptz,
  asignacion_primer_contacto_limite_en timestamptz,
  asignacion_primer_contacto_en timestamptz,
  etapa_politica_id uuid,
  etapa_politica_version integer,
  etapa text,
  etapa_iniciada_en timestamptz,
  etapa_limite_en timestamptz,
  etapa_objetivo_minutos integer,
  etapa_aproximada boolean
)
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector_global boolean;
  v_visibles uuid[];
begin
  v_rol := private.rol_crm(v_uid);
  v_lector_global := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector_global) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  return query
  select
    l.id,
    c.politica_id,
    pc.version,
    c.primera_gestion_limite_en,
    c.primera_gestion_en,
    c.primer_contacto_limite_en,
    c.primer_contacto_en,
    c.aproximado,
    a.id,
    a.sla_politica_asignacion_id,
    pa.version,
    a.primera_gestion_limite_en,
    ah.primera_gestion_en,
    a.primer_contacto_limite_en,
    ah.primer_contacto_en,
    e.politica_id,
    pe.version,
    e.etapa,
    e.iniciado_en,
    e.limite_en,
    re.maximo_minutos,
    e.aproximado
  from crm.leads l
  join crm.lead_sla_ciclos c
    on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
  join crm.sla_politicas pc on pc.id=c.politica_id
  left join lateral (
    select la.*
    from crm.lead_asignaciones la
    where la.lead_id=l.id and la.finalizado_en is null
    order by la.episodio_n desc
    limit 1
  ) a on true
  left join crm.sla_politicas pa on pa.id=a.sla_politica_asignacion_id
  left join crm.lead_asignacion_sla_hitos ah on ah.lead_asignacion_id=a.id
  left join crm.lead_sla_etapas e
    on e.lead_id=l.id and e.ciclo_n=l.ciclo_actual and e.finalizado_en is null
  left join crm.sla_politicas pe on pe.id=e.politica_id
  left join crm.sla_politica_etapas re
    on re.politica_id=e.politica_id and re.etapa=e.etapa
  where l.activo is true
    and (
      l.vendedor_id = any(v_visibles)
      or (
        l.vendedor_id is null
        and l.asignado_supervisor_id = any(v_visibles)
      )
      or v_rol='gerencia'
      or v_lector_global
    )
  order by l.id;
end;
$function$;

revoke all on function crm.estado_sla_leads_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.estado_sla_leads_fn() to authenticated;

-- ============================================================================
-- 6. actividades_del_ambito_fn — = any(array(...)), sin cambio de visibilidad
-- ============================================================================
-- Cuerpo as-built de 20260808163638 (ventana 365 d + LIMIT 10000). LANGUAGE
-- sql: el array se materializa como InitPlan (una vez por statement) y el
-- EXISTS por actividad deja de pagar un SubPlan por fila. El search_path
-- legacy se conserva tal cual (as-built; cambiarlo sería otra decisión).

create or replace function crm.actividades_del_ambito_fn()
returns table(
  id uuid,
  lead_id uuid,
  tipo text,
  detalle text,
  autor_nombre text,
  creado_en timestamptz
)
language sql
stable security definer
set search_path to 'private', 'public', 'crm'
as $function$
  select a.id, a.lead_id, a.tipo, a.detalle,
         coalesce(p.nombre_completo, '—') as autor_nombre, a.creado_en
  from crm.actividades a
  left join public.perfiles p on p.id = a.creado_por
  where a.creado_en >= now() - interval '365 days'
    and exists (
      select 1 from crm.leads l
      where l.id = a.lead_id
        and (
          (l.activo = true and (
            l.vendedor_id = any (array(select private.vendedor_ids_visibles((select auth.uid()))))
            or (l.vendedor_id is null and l.asignado_supervisor_id = any (array(select private.vendedor_ids_visibles((select auth.uid())))))
            or (select private.rol_crm((select auth.uid()))) = 'gerencia'
          ))
          or (select private.es_lector_global())
        )
    )
  order by a.creado_en desc, a.id asc
  limit 10000;
$function$;

revoke all on function crm.actividades_del_ambito_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.actividades_del_ambito_fn() to authenticated;

commit;
