-- F2.3a del plan «Conversion unica en todo el CRM»: Distribucion deja de
-- contar los cierres ANULADOS.
--
-- ⛔ POR QUE ESTA MIGRACION NO ANADE NI UNA CLAVE AL PAYLOAD:
-- el bundle VIVO en produccion (`b3f6e98`) valida la respuesta de esta
-- pantalla a CIERRE HERMETICO — `v.strictObject` en TODOS los niveles
-- (`app/src/lib/metricas-distribucion.ts`, 22 apariciones; las otras cinco
-- pantallas usan `v.object` y toleran claves nuevas). Con `strictObject`, una
-- clave NUEVA rompe la pantalla igual que renombrar una. Y el front esta
-- BLOQUEADO hasta integrar las dos ramas, asi que no se podria arreglar
-- publicando. Leccion [[crm-orden-deploy-front-primero]]: clave nueva en la
-- RESPUESTA → front primero.
--
-- Por eso F2.3 va en DOS TIEMPOS. Esto es 2.3a: **la forma del payload no
-- cambia ni un byte**; cambia el VALOR de `convertidos`, que ahora excluye los
-- cierres anulados por gerencia — la misma regla del nucleo. Las claves
-- nuevas (`conversion_*_pct` servidos y sondas) esperan a 2.3b, con el front
-- integrado o en una RPC v3 que el bundle viejo jamas llama.
--
-- HALLAZGO QUE ARREGLA (H17 del informe): anular un cierre bajaba la
-- conversion de Rendimiento y NO bajaba el «cierra el X %» del panel de abajo,
-- en la misma pantalla y para el mismo vendedor.
--
-- LOS NUMEROS DE ESTA PANTALLA BAJAN el dia del corte si hay anulaciones,
-- bajo los rotulos viejos, hasta F3 (decision D4).

-- ---------------------------------------------------------------------------
-- 0. Preflight: lo vivo es lo esperado, la tabla-base es la de F1 y el DEFINER
--    que llamara puede ejecutar lo que necesita.
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'metricas_distribucion_leads_core'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_desde date, p_hasta date, p_ahora timestamp with time zone')
     is distinct from 'b7c4a63e509b58c39b6767d568332081' then
    raise exception 'metricas_distribucion_leads_core viva NO es la esperada; re-capturar antes de F2.3a';
  end if;

  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'conversion_episodios'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric')
     is distinct from '9195e57220155384e16281bbbc91de32' then
    raise exception 'conversion_episodios viva NO es la de F1; re-capturar antes de F2.3a';
  end if;

  -- QUIEN EJECUTA DE VERDAD ESTE MOTOR (mapeado, no supuesto — la primera
  -- version de este candado miraba el eslabon equivocado y aborto la migracion,
  -- que es justo para lo que esta):
  --   crm.metricas_distribucion_leads_v2_fn   DEFINER, owner crm_metricas_bridge
  --     └─ private.metricas_distribucion_leads_autorizada  DEFINER, owner postgres
  --          └─ private.metricas_distribucion_leads_core   NO definer
  -- Al no ser DEFINER, el motor corre con la identidad del DEFINER de ARRIBA,
  -- es decir el owner de `..._autorizada`. Es ESE rol el que tiene que poder
  -- ejecutar la tabla-base. `has_function_privilege` no ejecuta nada (un
  -- `select fn()` sin EXECUTE tumba el backend en esta imagen).
  if not exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_autorizada'
       and p.prosecdef
  ) then
    raise exception 'metricas_distribucion_leads_autorizada dejo de ser DEFINER: cambio quien ejecuta el motor';
  end if;
  if not pg_catalog.has_function_privilege(
       (select p.proowner::regrole::text from pg_catalog.pg_proc p
          join pg_catalog.pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_autorizada'),
       'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
       'EXECUTE') then
    raise exception 'quien ejecuta el motor de Distribucion no puede ejecutar la tabla-base';
  end if;
  if not pg_catalog.has_function_privilege(
       (select p.proowner::regrole::text from pg_catalog.pg_proc p
          join pg_catalog.pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_autorizada'),
       'private.peso_referido_conversion(date)', 'EXECUTE') then
    raise exception 'quien ejecuta el motor de Distribucion no puede ejecutar peso_referido_conversion';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El motor de Distribucion, con los cierres del nucleo
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.metricas_distribucion_leads_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with
parametros as (
  select
    (p_desde::timestamp at time zone 'America/Lima') as inicio,
    ((p_hasta + 1)::timestamp at time zone 'America/Lima') as fin,
    p_ahora as ahora
),
rangos(orden, rango_id, etiqueta, desde_exclusivo, hasta_inclusivo) as (
  values
    (1, 'pen_0_1000'::text, 'Hasta S/ 1 mil'::text, 0::numeric, 1000::numeric),
    (2, 'pen_1000_5000', 'S/ 1 mil a 5 mil', 1000::numeric, 5000::numeric),
    (3, 'pen_5000_10000', 'S/ 5 mil a 10 mil', 5000::numeric, 10000::numeric),
    (4, 'pen_10000_20000', 'S/ 10 mil a 20 mil', 10000::numeric, 20000::numeric),
    (5, 'pen_20000_50000', 'S/ 20 mil a 50 mil', 20000::numeric, 50000::numeric),
    (6, 'pen_50000_100000', 'S/ 50 mil a 100 mil', 50000::numeric, 100000::numeric),
    (7, 'pen_mas_100000', 'Mas de S/ 100 mil', 100000::numeric, null::numeric),
    (8, 'sin_monto', 'Sin monto valido', null::numeric, null::numeric)
),
episodios_relevantes as (
  select
    la.*,
    private.rango_capital_pen(la.monto_estimado) as rango_id
  from crm.lead_asignaciones la
  cross join parametros p
  where la.finalizado_en is null

  union all

  select
    la.*,
    private.rango_capital_pen(la.monto_estimado) as rango_id
  from crm.lead_asignaciones la
  cross join parametros p
  where la.finalizado_en is not null
    and la.asignado_en >= p.inicio
    and la.asignado_en < p.fin
),
contactos as (
  select
    er.id as episodio_id,
    min(a.creado_en) as primer_contacto_en,
    max(a.creado_en) as ultimo_contacto_en
  from episodios_relevantes er
  cross join parametros p
  left join crm.actividades a
    on a.lead_id = er.lead_id
   and a.creado_por = er.analista_id
   and a.tipo in (
     'llamada_realizada',
     'llamada_no_contestada',
     'whatsapp_enviado',
     'whatsapp_recibido',
     'reunion_realizada'
   )
   and a.creado_en >= er.asignado_en
   and (er.finalizado_en is null or a.creado_en < er.finalizado_en)
   and a.creado_en <= p.ahora
  group by er.id
),
episodios as (
  select
    er.*,
    c.primer_contacto_en,
    c.ultimo_contacto_en,
    case
      when c.primer_contacto_en is not null
        then extract(epoch from (c.primer_contacto_en - er.asignado_en)) / 60.0
      else null
    end as primer_contacto_minutos,
    (
      c.primer_contacto_en is not null
      or coalesce(er.finalizado_en, p.ahora) >= er.asignado_en + interval '24 hours'
    ) as sla_evaluable,
    (
      c.primer_contacto_en is not null
      and c.primer_contacto_en <= er.asignado_en + interval '24 hours'
    ) as sla_en_24h
  from episodios_relevantes er
  join contactos c on c.episodio_id = er.id
  cross join parametros p
),
cohorte as (
  select e.*
  from episodios e
  cross join parametros p
  where e.asignado_en >= p.inicio
    and e.asignado_en < p.fin
),
-- F2.3a: los cierres que el NUCLEO reconoce, leidos de la tabla-base. Un
-- cierre ANULADO por gerencia deja de contar aqui igual que en HOY, Ranking y
-- Conversiones (hallazgo H17: hasta ahora Distribucion los seguia contando y
-- por eso contradecia a Rendimiento con el mismo vendedor delante).
-- La ventana llega hasta `ahora`: un episodio asignado dentro del rango puede
-- cerrarse despues, y ese cierre sigue siendo suyo.
cierres_del_nucleo as (
  select distinct e.analista_id, e.lead_id
  from parametros p
  cross join lateral private.conversion_episodios(
    p.inicio, greatest(p.fin, p.ahora), null::date, true, '{}'::uuid[],
    private.peso_referido_conversion(date_trunc('month', p_hasta)::date)
  ) e
  where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
),
abiertos as (
  select e.*, l.etapa
  from episodios e
  join crm.leads l on l.id = e.lead_id
  where e.finalizado_en is null
),
equipo_base as (
  select
    e.perfil_id as analista_id,
    coalesce(nullif(trim(p.nombre_completo), ''), 'Analista sin nombre') as nombre,
    e.rol_crm as rol,
    e.supervisor_id,
    sp.nombre_completo as supervisor_nombre,
    coalesce(e.activo = true and p.activo = true, false) as activo,
    coalesce(e.activo = true and p.activo = true, false) as disponible_para_recibir,
    e.capacidad_leads_objetivo as capacidad_objetivo
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  left join public.perfiles sp on sp.id = e.supervisor_id
  where e.rol_crm in ('vendedor', 'supervisor')
    and (
      (e.rol_crm = 'vendedor' and e.activo = true and p.activo = true)
      or e.capacidad_leads_objetivo is not null
      or exists (
        select 1
        from crm.lead_asignaciones historia
        where historia.analista_id = e.perfil_id
      )
    )
),
cartera_total as (
  select
    a.analista_id,
    count(*) as carga_activa,
    count(*) filter (where a.moneda = 'PEN') as carga_pen,
    count(*) filter (where a.moneda = 'USD') as carga_usd,
    coalesce(sum(a.monto_estimado) filter (where a.moneda = 'PEN'), 0) as capital_pen,
    coalesce(sum(a.monto_estimado) filter (where a.moneda = 'USD'), 0) as capital_usd,
    count(*) filter (where a.primer_contacto_en is null) as sin_tocar_actual,
    count(*) filter (
      where private.umbral_estancamiento(a.etapa) is not null
        and p.ahora >= coalesce(a.ultimo_contacto_en, a.asignado_en)
          + private.umbral_estancamiento(a.etapa)
    ) as estancados_actual
  from abiertos a
  cross join parametros p
  group by a.analista_id
),
cartera_pen_rangos as (
  select
    a.analista_id,
    a.rango_id,
    count(*) as episodios,
    coalesce(sum(a.monto_estimado), 0) as capital
  from abiertos a
  where a.moneda = 'PEN'
  group by a.analista_id, a.rango_id
),
cohorte_pen_total as (
  select
    c.analista_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido'
      and (c.analista_id, c.lead_id) in
          (select cn.analista_id, cn.lead_id from cierres_del_nucleo cn)
    ) as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados,
    count(*) filter (where c.resultado in ('convertido', 'descartado')) as ciclos_resueltos,
    count(distinct c.lead_id) filter (
      where c.resultado in ('convertido', 'descartado')
    ) as leads_unicos_resueltos
  from cohorte c
  where c.moneda = 'PEN'
  group by c.analista_id
),
cohorte_pen_rangos as (
  select
    c.analista_id,
    c.rango_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido'
      and (c.analista_id, c.lead_id) in
          (select cn.analista_id, cn.lead_id from cierres_del_nucleo cn)
    ) as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados,
    count(distinct c.lead_id) filter (
      where c.resultado in ('convertido', 'descartado')
    ) as leads_unicos_resueltos
  from cohorte c
  where c.moneda = 'PEN'
  group by c.analista_id, c.rango_id
),
cohorte_usd as (
  select
    c.analista_id,
    count(*) as episodios_recibidos,
    count(distinct c.lead_id) as leads_unicos_recibidos,
    count(*) filter (where c.resultado = 'convertido'
      and (c.analista_id, c.lead_id) in
          (select cn.analista_id, cn.lead_id from cierres_del_nucleo cn)
    ) as convertidos,
    count(*) filter (where c.resultado = 'descartado') as descartados
  from cohorte c
  where c.moneda = 'USD'
  group by c.analista_id
),
operacion_cohorte as (
  select
    c.analista_id,
    count(*) as episodios,
    count(*) filter (where c.primer_contacto_en is not null) as contactos,
    count(*) filter (where c.sla_evaluable) as sla_evaluables,
    count(*) filter (where c.sla_en_24h) as sla_en_24h,
    round((percentile_cont(0.5) within group (
      order by c.primer_contacto_minutos
    ))::numeric, 1) as primer_contacto_mediana_minutos,
    count(*) filter (where c.motivo_cierre = 'transferido') as transferidos,
    count(*) filter (where c.motivo_cierre = 'parqueado') as parqueados,
    count(*) filter (where c.motivo_cierre = 'desactivado') as desactivados
  from cohorte c
  group by c.analista_id
),
cola_actual as (
  select
    l.*,
    private.rango_capital_pen(l.monto_estimado) as rango_id
  from crm.leads l
  where l.activo = true
    and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and l.vendedor_id is null
),
cola_total as (
  select
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
),
cola_pen_rangos as (
  select rango_id, count(*) as cantidad, coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where moneda = 'PEN'
  group by rango_id
),
cola_global_total as (
  select
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
  where asignado_supervisor_id is null
),
cola_global_pen_rangos as (
  select rango_id, count(*) as cantidad, coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where asignado_supervisor_id is null and moneda = 'PEN'
  group by rango_id
),
bandeja_totales as (
  select
    asignado_supervisor_id as supervisor_id,
    count(*) as carga_total,
    count(*) filter (where moneda = 'PEN') as pen_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'PEN'), 0) as pen_capital,
    count(*) filter (where moneda = 'USD') as usd_cantidad,
    coalesce(sum(monto_estimado) filter (where moneda = 'USD'), 0) as usd_capital
  from cola_actual
  where asignado_supervisor_id is not null
  group by asignado_supervisor_id
),
bandeja_pen_rangos as (
  select
    asignado_supervisor_id as supervisor_id,
    rango_id,
    count(*) as cantidad,
    coalesce(sum(monto_estimado), 0) as capital
  from cola_actual
  where asignado_supervisor_id is not null and moneda = 'PEN'
  group by asignado_supervisor_id, rango_id
),
analistas_json as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'analista_id', eb.analista_id,
      'nombre', eb.nombre,
      'rol', eb.rol,
      'supervisor_id', eb.supervisor_id,
      'supervisor_nombre', eb.supervisor_nombre,
      'activo', eb.activo,
      'disponible_para_recibir', eb.disponible_para_recibir,
      'capacidad', jsonb_build_object(
        'objetivo', eb.capacidad_objetivo,
        'carga_activa', coalesce(ct.carga_activa, 0),
        'carga_pen', coalesce(ct.carga_pen, 0),
        'carga_usd', coalesce(ct.carga_usd, 0)
      ),
      'pen', jsonb_build_object(
        'cartera_actual', jsonb_build_object(
          'episodios', coalesce(ct.carga_pen, 0),
          'capital', coalesce(ct.capital_pen, 0)
        ),
        'cohorte', jsonb_build_object(
          'episodios_recibidos', coalesce(cpt.episodios_recibidos, 0),
          'leads_unicos_recibidos', coalesce(cpt.leads_unicos_recibidos, 0),
          'convertidos', coalesce(cpt.convertidos, 0),
          'descartados', coalesce(cpt.descartados, 0),
          'ciclos_resueltos', coalesce(cpt.ciclos_resueltos, 0),
          'leads_unicos_resueltos', coalesce(cpt.leads_unicos_resueltos, 0)
        ),
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cartera_actual', jsonb_build_object(
              'episodios', coalesce(cpr.episodios, 0),
              'capital', coalesce(cpr.capital, 0)
            ),
            'cohorte', jsonb_build_object(
              'episodios_recibidos', coalesce(cr.episodios_recibidos, 0),
              'leads_unicos_recibidos', coalesce(cr.leads_unicos_recibidos, 0),
              'convertidos', coalesce(cr.convertidos, 0),
              'descartados', coalesce(cr.descartados, 0),
              'leads_unicos_resueltos', coalesce(cr.leads_unicos_resueltos, 0)
            )
          ) order by r.orden)
          from rangos r
          left join cartera_pen_rangos cpr
            on cpr.analista_id = eb.analista_id and cpr.rango_id = r.rango_id
          left join cohorte_pen_rangos cr
            on cr.analista_id = eb.analista_id and cr.rango_id = r.rango_id
        )
      ),
      'usd_no_segmentado', jsonb_build_object(
        'cartera_actual_episodios', coalesce(ct.carga_usd, 0),
        'cartera_actual_capital', coalesce(ct.capital_usd, 0),
        'cohorte_episodios_recibidos', coalesce(cu.episodios_recibidos, 0),
        'cohorte_leads_unicos', coalesce(cu.leads_unicos_recibidos, 0),
        'convertidos', coalesce(cu.convertidos, 0),
        'descartados', coalesce(cu.descartados, 0)
      ),
      'operacion', jsonb_build_object(
        'cohorte_episodios', coalesce(oc.episodios, 0),
        'contactos', coalesce(oc.contactos, 0),
        'sla_evaluables', coalesce(oc.sla_evaluables, 0),
        'sla_en_24h', coalesce(oc.sla_en_24h, 0),
        'primer_contacto_mediana_minutos', oc.primer_contacto_mediana_minutos,
        'transferidos', coalesce(oc.transferidos, 0),
        'parqueados', coalesce(oc.parqueados, 0),
        'desactivados', coalesce(oc.desactivados, 0),
        'sin_tocar_actual', coalesce(ct.sin_tocar_actual, 0),
        'estancados_actual', coalesce(ct.estancados_actual, 0)
      )
    ) order by coalesce(eb.supervisor_nombre, ''), eb.nombre, eb.analista_id), '[]'::jsonb) as valor
  from equipo_base eb
  left join cartera_total ct on ct.analista_id = eb.analista_id
  left join cohorte_pen_total cpt on cpt.analista_id = eb.analista_id
  left join cohorte_usd cu on cu.analista_id = eb.analista_id
  left join operacion_cohorte oc on oc.analista_id = eb.analista_id
),
bandejas_json as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'supervisor_id', bt.supervisor_id,
      'supervisor_nombre', coalesce(nullif(trim(p.nombre_completo), ''), 'Supervisor sin nombre'),
      'supervisor_activo', coalesce(e.activo = true and p.activo = true, false),
      'carga_total', bt.carga_total,
      'pen', jsonb_build_object(
        'cantidad', bt.pen_cantidad,
        'capital', bt.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(bpr.cantidad, 0),
            'capital', coalesce(bpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join bandeja_pen_rangos bpr
            on bpr.supervisor_id = bt.supervisor_id and bpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', bt.usd_cantidad, 'capital', bt.usd_capital)
    ) order by p.nombre_completo, bt.supervisor_id), '[]'::jsonb) as valor
  from bandeja_totales bt
  left join crm.equipo e on e.perfil_id = bt.supervisor_id and e.rol_crm = 'supervisor'
  left join public.perfiles p on p.id = bt.supervisor_id
),
resumen as (
  select jsonb_build_object(
    'leads_operativos_actuales', (
      select count(*) from crm.leads l
      where l.activo = true
        and l.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    ),
    'asignados_actuales', (select count(*) from abiertos),
    'por_repartir_actuales', (select count(*) from cola_actual),
    'capital_pen_asignado_actual', coalesce((select sum(monto_estimado) from abiertos where moneda = 'PEN'), 0),
    'capital_usd_asignado_actual', coalesce((select sum(monto_estimado) from abiertos where moneda = 'USD'), 0),
    'cohorte_episodios', (select count(*) from cohorte),
    'cohorte_leads_unicos', (select count(distinct lead_id) from cohorte),
    'convertidos_pen', (
      select count(*) from cohorte c
       where c.moneda = 'PEN' and c.resultado = 'convertido'
         and (c.analista_id, c.lead_id) in
             (select cn.analista_id, cn.lead_id from cierres_del_nucleo cn)),
    'descartados_pen', (select count(*) from cohorte where moneda = 'PEN' and resultado = 'descartado'),
    'sla_evaluables', (select count(*) from cohorte where sla_evaluable),
    'sla_en_24h', (select count(*) from cohorte where sla_en_24h)
  ) as valor
),
calidad as (
  select jsonb_build_object(
    'episodios_aproximados_actuales', (select count(*) from abiertos where aproximado),
    'episodios_aproximados_cohorte', (select count(*) from cohorte where aproximado),
    'episodios_sin_monto_actuales', (
      select count(*) from abiertos where monto_estimado is null or monto_estimado <= 0
    ),
    'episodios_sin_monto_cohorte', (
      select count(*) from cohorte where monto_estimado is null or monto_estimado <= 0
    )
  ) as valor
)
select jsonb_build_object(
  'version', 1,
  'generado_en', p_ahora,
  'cohorte', jsonb_build_object(
    'desde_inclusivo', p_desde,
    'hasta_inclusivo', p_hasta,
    'hasta_exclusivo', p_hasta + 1,
    'criterio', 'episodio_asignado_en',
    'zona_horaria', 'America/Lima'
  ),
  'alcances', jsonb_build_object(
    'matriz', 'PEN',
    'capacidad', 'TODAS_LAS_MONEDAS',
    'operacion_sla', 'TODAS_LAS_MONEDAS'
  ),
  'rangos', (
    select jsonb_agg(jsonb_build_object(
      'id', r.rango_id,
      'orden', r.orden,
      'etiqueta', r.etiqueta,
      'desde_exclusivo', r.desde_exclusivo,
      'hasta_inclusivo', r.hasta_inclusivo
    ) order by r.orden)
    from rangos r
  ),
  'resumen', resumen.valor,
  'analistas', analistas_json.valor,
  'por_repartir', jsonb_build_object(
    'total', jsonb_build_object(
      'carga_total', ct.carga_total,
      'pen', jsonb_build_object(
        'cantidad', ct.pen_cantidad,
        'capital', ct.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(cpr.cantidad, 0),
            'capital', coalesce(cpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join cola_pen_rangos cpr on cpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', ct.usd_cantidad, 'capital', ct.usd_capital)
    ),
    'global', jsonb_build_object(
      'responsabilidad', 'gerencia',
      'carga_total', cgt.carga_total,
      'pen', jsonb_build_object(
        'cantidad', cgt.pen_cantidad,
        'capital', cgt.pen_capital,
        'rangos', (
          select jsonb_agg(jsonb_build_object(
            'rango_id', r.rango_id,
            'cantidad', coalesce(cgpr.cantidad, 0),
            'capital', coalesce(cgpr.capital, 0)
          ) order by r.orden)
          from rangos r
          left join cola_global_pen_rangos cgpr on cgpr.rango_id = r.rango_id
        )
      ),
      'usd', jsonb_build_object('cantidad', cgt.usd_cantidad, 'capital', cgt.usd_capital)
    ),
    'bandejas', bandejas_json.valor
  ),
  'calidad', calidad.valor
)
from parametros p
cross join resumen
cross join calidad
cross join analistas_json
cross join cola_total ct
cross join cola_global_total cgt
cross join bandejas_json;
$function$;

comment on function private.metricas_distribucion_leads_core(date,date,timestamptz) is
  'Motor de Distribucion (F2.3a): la FORMA del payload es identica byte a byte a la anterior (el front la valida a cierre hermetico y esta bloqueado hasta integrar ramas), pero `convertidos` ya no cuenta los cierres ANULADOS: los toma de private.conversion_episodios, la misma verdad que HOY/Ranking/Conversiones (H17). Las claves nuevas y las sondas llegan en 2.3b.';

-- ---------------------------------------------------------------------------
-- 2. Postflight: la FORMA no puede haber cambiado, y el anulado no puede volver
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_src text;
  v_norm text;
begin
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_core'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) =
         'p_desde date, p_hasta date, p_ahora timestamp with time zone';

  if v_src is null then
    raise exception 'metricas_distribucion_leads_core desaparecio; rollback';
  end if;
  v_norm := lower(regexp_replace(v_src, '\s+', ' ', 'g'));

  if strpos(v_norm, 'private.conversion_episodios(') = 0 then
    raise exception 'Distribucion no consume la tabla-base; rollback';
  end if;
  if strpos(v_norm, 'cierres_del_nucleo') = 0 then
    raise exception 'Distribucion perdio el filtro de cierres del nucleo; rollback';
  end if;
  -- Las TRES agrupaciones (PEN total, PEN por rango, USD) tienen que pasar por
  -- la tabla-base: si una se queda contando cruda, la pantalla vuelve a
  -- contradecirse consigo misma.
  -- CUATRO sitios cuentan convertidos en esta funcion: las tres agrupaciones
  -- (PEN total, PEN por rango, USD) y el bloque `resumen`, que los cuenta por
  -- su cuenta desde `cohorte`. Si uno se queda sin filtrar, la pantalla vuelve
  -- a contradecirse consigo misma — el oraculo lo cazo justo asi.
  if (length(v_norm) - length(replace(v_norm, 'from cierres_del_nucleo cn', '')))
       / length('from cierres_del_nucleo cn') <> 4 then
    raise exception 'no son 4 los conteos que filtran anulados; rollback';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_core'
       and pg_catalog.pg_get_function_identity_arguments(p.oid) =
           'p_desde date, p_hasta date, p_ahora timestamp with time zone'
       and not p.prosecdef
       and p.provolatile = 's'
       and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'Distribucion perdio STABLE / search_path, o gano DEFINER; rollback';
  end if;
end;
$postflight$;
