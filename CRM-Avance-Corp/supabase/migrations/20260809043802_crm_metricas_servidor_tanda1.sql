-- ============================================================================
-- F1 tanda 1 — Métricas al servidor (Plan de escalabilidad, fase F1)
-- ============================================================================
-- El navegador NUNCA recibe filas para contarlas; la base devuelve agregados.
-- Cuatro RPC nuevas que replican en SQL los cálculos que hoy hace el front
-- sobre el ámbito completo del store (lib/inteligencia.ts, series-comerciales.ts):
--
--   1. crm.resumen_cartera_fn()                — capital/embudo/conteos/descartes
--   2. crm.cola_accion_fn(p_limite)            — cola de acción con buckets + estancados
--   3. crm.metricas_vendedores_fn()            — ranking por vendedor + comparativa de equipos
--   4. crm.series_comerciales_fn(p_meses)      — series mensuales (Lima) de 6 meses
--
-- Patrón canónico de la casa (20260803164348 / 20260807203740 / 20260807203757):
-- security definer + stable + search_path='' + guardia explícita ANTES de tocar
-- datos + revoke all/grant authenticated + payload jsonb con version:1.
--
-- Predicado de visibilidad = espejo EXACTO de la RLS leads_select, el mismo que
-- crm.estado_sla_leads_fn (20260807203757:1408) y crm.actividades_del_ambito_fn:
-- visibles + rama de parkeados por bandeja + gerencia + lector global. El
-- coordinador pasa la guardia y recibe agregados VACÍOS (ámbito ∅ por diseño,
-- fixtures.mjs; su superficie de reparto llega en la tanda 2 con
-- resumen_reparto_fn gateada por private.puede_operar_reparto_crm()).
--
-- VENTANA DE CONVERTIDOS (decisión de Miguel 2026-08-08, plan F0§5): el ámbito
-- operativo excluye convertidos con más de 45 días
-- (etapa <> 'convertido' OR convertido_en >= now() - 45d). Aplica a
-- resumen_cartera_fn y metricas_vendedores_fn; NO aplica a series_comerciales_fn
-- (histórico: un cierre viejo debe seguir contando en su mes) ni afecta a
-- cola_accion_fn (solo trabaja abiertos). El payload expone
-- ventana_convertidos_dias para que el front certifique el mismo corte.
--
-- Divergencias DELIBERADAS respecto del cálculo actual del navegador
-- (documentadas también en MIGRACIONES.md):
--   a. El mes de cierre de las series usa el sello canónico
--      coalesce(convertido_en, actualizado_en, creado_en) (cierres-del-mes.ts),
--      no el orden accidental de series-comerciales.ts (actualizado_en primero,
--      que movía el cierre de mes con cualquier edición del lead).
--   b. "Sin contacto jamás" se evalúa sobre TODO el historial de actividades;
--      el front solo veía la ventana de 365d/10000 del ámbito.
--   c. conversión por origen NO viaja aquí: ya existe server-side en
--      crm.metricas_conversiones_fn.origenes.
-- ============================================================================

begin;
set local lock_timeout = '10s';

-- ============================================================================
-- 1. resumen_cartera_fn — el resumen agregado del ámbito visible
-- ============================================================================
-- Sirve los tiles que hoy cuentan/suman arrays del store: capital por moneda
-- (asignado/parkeado/ganado por separado: Cartera suma todos los abiertos,
-- Pipeline/Hoy/Equipo solo los que tienen vendedor), embudo de 6 etapas (las 4
-- activas para el donut de directorio, las 6 para la distribución de Cartera),
-- conversión global, descartes por motivo y "sin tocar". PEN y USD JAMÁS se
-- suman: espejo de capitalPorMoneda (USD estricto; cualquier otra moneda cae a
-- PEN, lib/inteligencia.ts:25-33).

create function crm.resumen_cartera_fn()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
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
        l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
        or (l.vendedor_id is null
            and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
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
  'Resumen agregado del ambito visible (capital por moneda, embudo, conversion, descartes, sin tocar). Ventana de convertidos de 45 dias. PEN y USD jamas se suman.';

revoke all on function crm.resumen_cartera_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.resumen_cartera_fn() to authenticated;

-- ============================================================================
-- 2. cola_accion_fn — la cola de acción con buckets, calculada en el servidor
-- ============================================================================
-- Réplica exacta de colaDe (lib/inteligencia.ts:299-471): a lo sumo UN bucket
-- por lead abierto, cascada en el mismo orden del front, severidad
-- critica<media<baja y días desc. El texto del motivo lo redacta el front; el
-- servidor manda los INGREDIENTES (datos_motivo). Cada item lleva
-- ultimo_contacto_en — el dato del semáforo del kanban (regla F1: decidirlo
-- aquí deja a F3 sin migraciones). El bloque `estancados` sirve la lista del
-- supervisor (abiertos sin plan VIGENTE y sin actividad de NINGÚN tipo ≥5 días).
--
-- Costo: clasificar exige recorrer TODOS los abiertos visibles (el orden por
-- severidad no se puede decidir sin mirar el conjunto); p_limite recorta el
-- payload, no el trabajo. Los laterales se apoyan en
-- actividades_contacto_episodio_idx / idx_actividades_lead /
-- tareas_lead_pendiente_idx / lead_sla_etapas_un_abierto_idx.

create function crm.cola_accion_fn(p_limite integer default 100)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
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
        l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
        or (l.vendedor_id is null
            and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
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
  'Cola de accion con buckets calculados en el servidor (espejo de colaDe): un bucket por lead abierto, ingredientes del motivo, ultimo_contacto_en para el semaforo del kanban, y lista de estancados. p_limite recorta el payload (1..500).';

revoke all on function crm.cola_accion_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.cola_accion_fn(integer) to authenticated;

-- ============================================================================
-- 3. metricas_vendedores_fn — ranking por vendedor + comparativa de equipos
-- ============================================================================
-- Espejo de metricasPorVendedor y comparativaEquipos (lib/inteligencia.ts:512,
-- 635). SIN nombres en el payload: el front une por id con el roster de
-- equipo_visible_fn (precedente metricas_conversiones_fn). Los dos índices NO
-- se fusionan: sin_tocar mide CONTACTO real; dias_sin_actividad_max mide
-- actividad a secas. La comparativa cuenta reportes DIRECTOS (no subárbol) de
-- cada supervisor activo, y sus parkeados no suman capital.

create function crm.metricas_vendedores_fn()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_corte := v_ahora - interval '45 days'; -- ventana_convertidos_dias

  with roster as materialized (
    select e.perfil_id, e.rol_crm, e.activo
    from crm.equipo e
    where e.rol_crm in ('vendedor', 'supervisor', 'gerencia')
      and (
        e.perfil_id in (select private.vendedor_ids_visibles(v_uid))
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
        l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
        or (l.vendedor_id is null
            and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
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
  'Ranking por vendedor (activos, capital por moneda, convertidos con ventana de 45 dias, sin_tocar, dias_sin_actividad_max) y comparativa de equipos por supervisor activo con sus parkeados. Sin nombres: el front une por id con su roster.';

revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.metricas_vendedores_fn() to authenticated;

-- ============================================================================
-- 4. series_comerciales_fn — series mensuales de Lima
-- ============================================================================
-- Espejo de seriesComerciales (lib/series-comerciales.ts:49) con dos
-- correcciones deliberadas: el mes de cierre usa el sello canónico
-- coalesce(convertido_en, actualizado_en, creado_en) (cierres-del-mes.ts), y
-- las series de capital van POR MONEDA separadas (jamás un punto suma PEN+USD).
-- SIN ventana de 45 días: es histórico — por esto la ventana del ámbito recién
-- puede aplicarse en el front cuando esta RPC esté disponible (plan F0§5).
-- capital_pen exige moneda='PEN' ESTRICTA (espejo de series-comerciales.ts:83).

create function crm.series_comerciales_fn(p_meses integer default 6)
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
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
        l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))
        or (l.vendedor_id is null
            and l.asignado_supervisor_id in (select private.vendedor_ids_visibles(v_uid)))
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
  'Series mensuales de Lima (ascendentes, mes vigente al final): altas, cohorte con contrato, cierres y capital POR MONEDA al mes de cierre (sello canonico convertido_en). Historico: sin ventana de convertidos. p_meses 1..24.';

revoke all on function crm.series_comerciales_fn(integer)
  from public, anon, authenticated, service_role;
grant execute on function crm.series_comerciales_fn(integer) to authenticated;

commit;
