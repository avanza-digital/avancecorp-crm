-- ============================================================================
-- F1 tanda 2 — Métricas al servidor (Plan de escalabilidad, fase F1)
-- ============================================================================
-- Cierra la superficie SERVIDOR de F1: las 3 RPC restantes del inventario.
-- El navegador NUNCA recibe filas para contarlas; la base devuelve agregados.
--
--   1. crm.resumen_tareas_fn()            — stats de agenda + señales de alertas
--   2. crm.resumen_cartera_clientes_fn()  — resumen de mi-cartera (clientes+contratos)
--   3. crm.resumen_reparto_fn()           — resumen de la cola global de reparto
--
-- Patrón canónico de la casa (20260803164348 / 20260807203740 / 20260809043802):
-- security definer + stable + search_path='' + guardia explícita ANTES de tocar
-- datos + revoke all/grant authenticated + payload jsonb con version:1.
-- Optimización de ámbito: vendedor_ids_visibles se captura UNA vez en un array
-- y se filtra con `= any(...)` (indexable) — estas 3 nacen ya con el patrón que
-- la migración hermana (20260809144920) lleva a la familia existente.
--
-- Reglas grabadas por la crítica del plan (no negociables):
--   - resumen_tareas_fn scoped al ámbito REAL de tareas (espejo de la RLS
--     tareas_select: dueño visible + bandeja + gerencia + lector). El
--     coordinador pasa la guardia y recibe agregados VACÍOS (su superficie es
--     el reparto; sus parkeados no llevan tareas).
--   - resumen_cartera_clientes_fn 100 % canónica: search_path='' y tablas base
--     calificadas — NO se apila sobre clientes_basicos_fn (heredaría su
--     search_path legacy 'private','public'). MISMO predicado que ella:
--     rol='cliente' AND (lector OR gerencia OR asesor ∈ visibles). El bucket
--     «sin_asesor» solo se llena para gerencia/lector (asesor NULL no entra al
--     ámbito de nadie más). SOLO LECTURA de public.perfiles/public.contratos
--     (sin DDL sobre public).
--   - resumen_reparto_fn gateada por private.puede_operar_reparto_crm()
--     (coordinador|gerencia activos): 42501 para vendedor, supervisor,
--     directorio y ajenos. Espejo EXACTO del predicado de la cola de
--     leads_por_repartir_implementacion (cola GLOBAL sin dueño; excluye
--     no_contactar por Ley 29571). Agregados sin PII: la premisa C1 del
--     coordinador ("enruta, no contacta") se mantiene.
--
-- Divergencias DELIBERADAS respecto del cálculo actual del navegador:
--   a. sin_accion usa el anti-join canónico del servidor (¿existe tarea
--      pendiente+activa del lead?), el MISMO criterio que ya usa
--      private.metricas_agenda_implementacion.sin_accion — el front solo ve las
--      tareas que su RLS le muestra, así que una tarea de otro dueño sobre su
--      lead podía inflar su "sin próxima acción" (falso amarillo).
--   b. Desempates por id (determinismo del servidor; precedente tanda 1).
--   c. Las listas van TECHADAS (tope 50, como `estancados` de cola_accion_fn):
--      son señales para alertas, no listados para recorrer.
-- ============================================================================

begin;
set local lock_timeout = '10s';

-- ============================================================================
-- 1. resumen_tareas_fn — stats de agenda + señales de alertas
-- ============================================================================
-- Sirve los mini-KPIs de la pantalla Agenda (statsDe: pendientes por tipo,
-- vencidas por HORA) y las señales que hoy derivan derivarAlertasVendedor/
-- Supervisor recorriendo ámbito+tareas completos:
--   - vencidas: la tarea vencida MÁS ANTIGUA por lead abierto (criterio HORA,
--     espejo de horasVencida/tareasVencidasPorLead de lib/alertas.ts; el front
--     decide severidad con `horas`: >=24 es crítica / umbral del supervisor).
--   - sin_accion: leads abiertos CON dueño y SIN tarea pendiente (el bucket
--     amarillo del semáforo, sinProximaAccion), con el conteo por vendedor que
--     necesita la alerta del supervisor (>=3 leads → alerta).
-- Los DOS criterios de "vencida" viajan por separado porque son preguntas
-- distintas (documentado en lib/plan-lead.ts): `vencidas_hora` (ya pasó la
-- hora — agenda) y `vencidas_dia` (el día Lima ya pasó — plan muerto de colaDe).

create function crm.resumen_tareas_fn()
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
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_hoy_lima := (v_ahora at time zone 'America/Lima')::date;

  with tareas_ambito as materialized (
    -- Espejo de la RLS tareas_select acotado a lo que lista el front
    -- (listarTareasDelAmbito: pendiente + activa). Las tareas de cliente
    -- (lead_id null) cuentan en los stats — la agenda las muestra — pero no
    -- gobiernan señales de leads (v1, lib/plan-lead.ts).
    select t.id, t.lead_id, t.tipo, t.titulo, t.vence_en
    from crm.tareas t
    where t.estado = 'pendiente'
      and t.activo is true
      and (
        t.vendedor_id = any(v_visibles)
        or (t.vendedor_id is null and t.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  leads_abiertos as materialized (
    -- Abiertos visibles (predicado canónico de leads con rama de bandeja).
    select l.id, l.nombre_completo, l.vendedor_id, l.moneda,
           coalesce(l.monto_estimado, 0) as monto
    from crm.leads l
    where l.activo is true
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and (
        l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
        or v_rol = 'gerencia'
        or v_lector
      )
  ),
  stats as (
    select count(*)::int as total,
      count(*) filter (where t.tipo = 'llamada')::int as n_llamada,
      count(*) filter (where t.tipo = 'whatsapp')::int as n_whatsapp,
      count(*) filter (where t.tipo = 'reunion')::int as n_reunion,
      count(*) filter (where t.tipo = 'tarea')::int as n_tarea,
      count(*) filter (where t.vence_en < v_ahora)::int as vencidas_hora,
      count(*) filter (where (t.vence_en at time zone 'America/Lima')::date < v_hoy_lima)::int as vencidas_dia,
      count(*) filter (where t.lead_id is null)::int as de_cliente
    from tareas_ambito t
  ),
  -- La vencida MÁS ANTIGUA por lead abierto (la que más avergüenza); empate
  -- por id menor — espejo exacto de tareasVencidasPorLead.
  vencida_por_lead as materialized (
    select distinct on (t.lead_id)
      t.lead_id, t.id as tarea_id, t.titulo, t.vence_en,
      l.nombre_completo, l.vendedor_id
    from tareas_ambito t
    join leads_abiertos l on l.id = t.lead_id
    where t.vence_en < v_ahora
    order by t.lead_id, t.vence_en asc, t.id asc
  ),
  sin_accion as materialized (
    -- Anti-join canónico del servidor (mismo criterio que
    -- metricas_agenda_implementacion.sin_accion): CUALQUIER pendiente activa
    -- del lead cuenta como "tiene algo escrito", viva o muerta.
    select l.*
    from leads_abiertos l
    where l.vendedor_id is not null
      and not exists (
        select 1 from crm.tareas t
        where t.lead_id = l.id and t.estado = 'pendiente' and t.activo
      )
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'zona', 'America/Lima',
    'pendientes', (
      select jsonb_build_object(
        'total', s.total,
        'por_tipo', jsonb_build_object(
          'llamada', s.n_llamada, 'whatsapp', s.n_whatsapp,
          'reunion', s.n_reunion, 'tarea', s.n_tarea),
        'vencidas_hora', s.vencidas_hora,
        'vencidas_dia', s.vencidas_dia,
        'de_cliente', s.de_cliente
      ) from stats s
    ),
    'vencidas', jsonb_build_object(
      'umbral_critico_horas', 24,
      'tope', 50,
      'leads_total', (select count(*) from vencida_por_lead),
      'leads_criticos', (select count(*) from vencida_por_lead v
                         where v_ahora - v.vence_en >= interval '24 hours'),
      'items', coalesce(
        (select jsonb_agg(
           jsonb_build_object(
             'lead_id', v.lead_id,
             'tarea_id', v.tarea_id,
             'titulo', v.titulo,
             'vence_en', v.vence_en,
             'horas', round(extract(epoch from (v_ahora - v.vence_en)) / 3600.0, 4),
             'nombre_completo', v.nombre_completo,
             'vendedor_id', v.vendedor_id)
           order by v.vence_en asc, v.lead_id
         )
         from (select * from vencida_por_lead order by vence_en asc, lead_id limit 50) v),
        '[]'::jsonb)
    ),
    'sin_accion', jsonb_build_object(
      'total', (select count(*) from sin_accion),
      'tope', 50,
      'por_vendedor', coalesce(
        (select jsonb_agg(jsonb_build_object('vendedor_id', x.vendedor_id, 'n', x.n)
                          order by x.n desc, x.vendedor_id)
         from (select sa.vendedor_id, count(*)::int as n
               from sin_accion sa group by sa.vendedor_id) x),
        '[]'::jsonb),
      'items', coalesce(
        (select jsonb_agg(
           jsonb_build_object(
             'lead_id', s.id,
             'nombre_completo', s.nombre_completo,
             'vendedor_id', s.vendedor_id,
             'moneda', s.moneda,
             'monto_estimado', s.monto)
           order by (s.moneda = 'PEN') desc, s.monto desc, s.id
         )
         from (select * from sin_accion
               order by (moneda = 'PEN') desc, monto desc, id limit 50) s),
        '[]'::jsonb)
    )
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.resumen_tareas_fn() is
  'Stats de la agenda (pendientes por tipo, vencidas por hora y por dia Lima) + senales de alertas: la vencida mas antigua por lead abierto (tope 50) y leads sin proxima accion con conteo por vendedor (tope 50). Ambito espejo de la RLS de tareas.';

revoke all on function crm.resumen_tareas_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.resumen_tareas_fn() to authenticated;

-- ============================================================================
-- 2. resumen_cartera_clientes_fn — resumen de mi-cartera
-- ============================================================================
-- Espejo de resumenCartera + agruparCartera (lib/cartera-vista.ts): dinero y
-- conteo de clientes SOLO de la cartera EN GESTIÓN (cliente.activo); la ALARMA
-- de renovación (<=30 d, HOY incluido) sobre TODOS los clientes visibles, con
-- el desglose de bajas para decirlo en vez de ocultarlo. PEN y USD jamás se
-- suman (USD estricto; cualquier otra moneda cae a PEN, espejo de la casa).
-- `por_estado` alimenta los chips/filtros de servidor que F2 llevará a la
-- pantalla (mi-cartera keyset).

create function crm.resumen_cartera_clientes_fn()
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
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_hoy_lima := (v_ahora at time zone 'America/Lima')::date;

  with clientes_ambito as materialized (
    -- MISMO predicado que crm.clientes_basicos_fn (asesor NULL solo entra al
    -- ámbito de gerencia/lector — el bucket sin_asesor queda en 0 para el
    -- resto por construcción, no por un `case` frágil).
    select p.id, p.activo, p.asesor_perfil_id
    from public.perfiles p
    where p.rol = 'cliente'
      and (
        v_lector
        or v_rol = 'gerencia'
        or p.asesor_perfil_id = any(v_visibles)
      )
  ),
  contratos_ambito as materialized (
    -- Contratos de los clientes visibles (los huérfanos de cliente no cargado
    -- se descartan igual que en agruparCartera).
    select c.id, c.estado, c.moneda, coalesce(c.capital, 0) as capital,
           c.fecha_vencimiento, cli.activo as cliente_activo, cli.id as cliente_id
    from public.contratos c
    join clientes_ambito cli on cli.id = c.cliente_id
  ),
  con_capital as (
    select count(distinct ca.cliente_id)::int as n
    from contratos_ambito ca
    where ca.estado = 'activo' and ca.cliente_activo
  ),
  por_estado as (
    select coalesce(jsonb_object_agg(x.estado, x.n), '{}'::jsonb) as j
    from (select ca.estado, count(*)::int as n
          from contratos_ambito ca group by ca.estado) x
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'zona', 'America/Lima',
    'dias_alarma_renovacion', 30,
    'clientes', jsonb_build_object(
      'en_gestion', count(*) filter (where cl.activo),
      'de_baja', count(*) filter (where not cl.activo),
      'con_capital', (select n from con_capital),
      'sin_asesor', count(*) filter (where cl.activo and cl.asesor_perfil_id is null)
    ),
    'capital_activo', jsonb_build_object(
      'pen', coalesce((select round(sum(ca.capital), 2) from contratos_ambito ca
                       where ca.estado = 'activo' and ca.cliente_activo
                         and ca.moneda is distinct from 'USD'), 0),
      'usd', coalesce((select round(sum(ca.capital), 2) from contratos_ambito ca
                       where ca.estado = 'activo' and ca.cliente_activo
                         and ca.moneda = 'USD'), 0)
    ),
    'contratos', jsonb_build_object(
      'por_estado', (select j from por_estado),
      -- Alarma sobre TODOS los visibles: activo y venciendo en [hoy, hoy+30]
      -- (HOY incluido, fecha pasada NO cuenta — espejo de esPorVencer).
      'por_vencer_30', coalesce((select count(*)::int from contratos_ambito ca
                                 where ca.estado = 'activo'
                                   and ca.fecha_vencimiento is not null
                                   and ca.fecha_vencimiento >= v_hoy_lima
                                   and ca.fecha_vencimiento <= v_hoy_lima + 30), 0),
      'por_vencer_30_de_baja', coalesce((select count(*)::int from contratos_ambito ca
                                         where ca.estado = 'activo'
                                           and not ca.cliente_activo
                                           and ca.fecha_vencimiento is not null
                                           and ca.fecha_vencimiento >= v_hoy_lima
                                           and ca.fecha_vencimiento <= v_hoy_lima + 30), 0)
    )
  )
  into v_payload
  from clientes_ambito cl;

  return v_payload;
end;
$function$;

comment on function crm.resumen_cartera_clientes_fn() is
  'Resumen de mi-cartera: clientes en gestion/de baja/con capital/sin asesor, capital activo por moneda (solo cartera en gestion) y alarma de renovacion <=30 dias sobre TODA la cartera con desglose de bajas. Mismo predicado que clientes_basicos_fn; 100% canonica (search_path vacio).';

revoke all on function crm.resumen_cartera_clientes_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.resumen_cartera_clientes_fn() to authenticated;

-- ============================================================================
-- 3. resumen_reparto_fn — resumen de la cola global de reparto
-- ============================================================================
-- Espejo del StatStrip de screens/repartir.tsx: total de la cola, capital en
-- juego por moneda, espera más larga (días enteros) y marcados "posible
-- crédito"; por_origen alimenta el filtro. Predicado IDÉNTICO al de
-- private.leads_por_repartir_implementacion (cola GLOBAL sin dueño, etapas
-- abiertas, sin no_contactar — Ley 29571). Sin PII: solo números.

create function crm.resumen_reparto_fn()
returns jsonb
language plpgsql
stable security definer
set search_path = ''
as $function$
declare
  v_ahora timestamptz := now();
  v_payload jsonb;
begin
  if not private.puede_operar_reparto_crm() then
    raise exception 'Solo Coordinacion o Gerencia puede ver el resumen de reparto'
      using errcode = '42501';
  end if;

  with cola as materialized (
    select l.origen, l.moneda, coalesce(l.monto_estimado, 0) as monto,
           l.creado_en, l.clasificacion_auto
    from crm.leads l
    where l.activo = true
      and l.vendedor_id is null
      and l.asignado_supervisor_id is null
      and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
      and l.no_contactar = false
  ),
  por_origen as (
    select coalesce(
             jsonb_agg(jsonb_build_object('origen', x.origen, 'n', x.n)
                       order by x.n desc, x.origen),
             '[]'::jsonb) as j
    from (select c.origen, count(*)::int as n from cola c group by c.origen) x
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'cola', jsonb_build_object(
      'total', count(*),
      'capital', jsonb_build_object(
        'pen', coalesce(sum(c.monto) filter (where c.moneda is distinct from 'USD'), 0),
        'usd', coalesce(sum(c.monto) filter (where c.moneda = 'USD'), 0)
      ),
      -- Días ENTEROS del lead más viejo (espejo de diasEnCola: floor, nunca
      -- negativo). 0 con cola vacía — el front pinta el vacío.
      'espera_max_dias', coalesce(
        (select greatest(floor(extract(epoch from (v_ahora - min(c2.creado_en))) / 86400.0), 0)::int
         from cola c2), 0),
      'posible_credito', count(*) filter (where c.clasificacion_auto = 'posible_credito'),
      'por_origen', (select j from por_origen)
    )
  )
  into v_payload
  from cola c;

  return v_payload;
end;
$function$;

comment on function crm.resumen_reparto_fn() is
  'Resumen agregado de la cola GLOBAL de reparto (total, capital por moneda, espera maxima en dias, posible_credito, por_origen). Gate puede_operar_reparto_crm (coordinador|gerencia); mismo predicado que leads_por_repartir. Sin PII.';

revoke all on function crm.resumen_reparto_fn()
  from public, anon, authenticated, service_role;
grant execute on function crm.resumen_reparto_fn() to authenticated;

commit;
