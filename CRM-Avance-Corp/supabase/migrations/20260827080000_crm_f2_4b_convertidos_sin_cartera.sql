-- F2.4b · corrige una incoherencia que introdujo F2.4 (20260827070000).
--
-- QUE PASO: al pasar la metrica al nucleo, `convertidos` empezo a sumar
-- **cierres de lead + operaciones de cartera** (43 en produccion), mientras la
-- serie comercial contaba solo cierres de lead (14). Dos pantallas recien
-- migradas discrepando entre si: exactamente la enfermedad que esta fase
-- existe para eliminar. Se detecto comparando la foto de las tres funciones
-- justo despues de aplicar.
--
-- QUE HACE: `convertidos` cuenta CIERRES DE LEAD en Gestion de equipo y en el
-- tile de cartera — el mismo criterio que la serie. Las operaciones de cartera
-- viajan en su propia clave `operaciones_cartera` (aditiva, schemas `v.object`).
-- El `conversion_pct` NO cambia: sigue siendo el del nucleo, que SI incluye las
-- renovaciones en el numerador, porque esa es la definicion acordada.
--
-- La migracion 20260827070000 NO se edita (regla de la casa): esto es una
-- migracion NUEVA sobre el texto que quedo vivo.

do $preflight$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'metricas_vendedores_fn')
     is distinct from '973dfaa7e459df080f3d8ff6ef73f001' then
    raise exception 'metricas_vendedores_fn viva NO es la que dejo F2.4; re-capturar';
  end if;
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'resumen_cartera_fn')
     is distinct from '063c5efbd2a86f0fd667fa4893679105' then
    raise exception 'resumen_cartera_fn viva NO es la que dejo F2.4; re-capturar';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION crm.metricas_vendedores_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_mes date;
  v_mes_ini timestamptz;
  v_mes_fin timestamptz;
  v_factor numeric;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_corte := v_ahora - interval '45 days'; -- ventana de la VISTA, no de la metrica
  v_mes := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_mes_ini := (v_mes::timestamp at time zone 'America/Lima');
  v_mes_fin := ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima');
  v_factor := private.peso_referido_conversion(v_mes);

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
  -- F2.4 (decision D1): la METRICA de conversion pasa al mes calendario del
  -- NUCLEO. La ventana de 45 dias NO desaparece: sigue siendo la de la VISTA
  -- operativa (que leads se ven en cartera), que es de lo que hablaba la regla
  -- del 08/08. Lo que cambia es el NUMERO, que ahora es el mismo que HOY,
  -- Ranking, Metas y Conversiones.
  -- Va GLOBAL a proposito y se recorta al unir con `roster` (ya recortado):
  -- asi el mismo vendedor da el mismo numero lo mire gerencia o su supervisor
  -- — el cierre lo atribuye el ledger, no el dueno actual del lead.
  nucleo_mes as materialized (
    select e.analista_id,
      count(*) filter (where e.tipo = 'recibido' and not e.fue_referido)::int as divisor,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones
    from private.conversion_episodios(
      v_mes_ini, v_mes_fin, v_mes, true, '{}'::uuid[], v_factor
    ) e
    group by e.analista_id
  ),
  por_vendedor as (
    select r.perfil_id, r.rol_crm, r.activo,
      count(a.id) filter (where a.abierto)::int as activos,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda is distinct from 'USD'), 0) as capital_pen,
      coalesce(sum(a.monto) filter (where a.abierto and a.moneda = 'USD'), 0) as capital_usd,
      -- ANTES: conteo de leads con etapa convertido dentro de la ventana de la
      -- VISTA (45 dias, con anulados). AHORA: cierres del MES del ledger.
      -- `convertidos` cuenta CIERRES DE LEAD, no operaciones de cartera: la
      -- serie comercial y el tile de cartera cuentan lo mismo, y si aqui se
      -- sumaran las renovaciones las tres pantallas volverian a discrepar
      -- (justo lo que esta fase existe para eliminar). Las operaciones viajan
      -- en su propia clave; el % SI las incluye, porque es el del nucleo.
      coalesce(nm.cierres_no_referidos, 0) + coalesce(nm.cierres_referidos, 0)
        as convertidos,
      coalesce(nm.operaciones, 0) as operaciones_cartera,
      coalesce(nm.divisor, 0) as nucleo_divisor,
      coalesce((nm.cierres_no_referidos + v_factor * nm.cierres_referidos
                + nm.operaciones)::numeric, 0) as nucleo_numerador,
      count(a.id)::int as total
    from roster r
    left join ambito a on a.vendedor_id = r.perfil_id
    left join nucleo_mes nm on nm.analista_id = r.perfil_id
    group by r.perfil_id, r.rol_crm, r.activo,
             nm.cierres_no_referidos, nm.cierres_referidos, nm.operaciones, nm.divisor
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
    -- La ventana de 45 dias es la de la VISTA (que leads se ven). La METRICA
    -- de conversion es del mes calendario, como en el resto del CRM (D1).
    'ventana_metrica', 'mes_calendario',
    'mes_metrica', v_mes,
    'peso_referido', v_factor,
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
           'operaciones_cartera', pv.operaciones_cartera,
           -- El % pasa a ser el del NUCLEO (numerador ponderado / recibidos no
           -- referidos), no cierres/cartera-visible. Se conserva ENTERO para no
           -- cambiar el tipo del contrato; el valor exacto viaja aparte.
           'conversion_pct', case when pv.nucleo_divisor > 0
             then round(100.0 * pv.nucleo_numerador / pv.nucleo_divisor)::int else 0 end,
           'nucleo_divisor', pv.nucleo_divisor,
           'nucleo_numerador', pv.nucleo_numerador,
           'nucleo_conversion_pct', case when pv.nucleo_divisor > 0
             then round(100.0 * pv.nucleo_numerador / pv.nucleo_divisor, 2) end,
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

CREATE OR REPLACE FUNCTION crm.resumen_cartera_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_reparto boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_mes date;
  v_mes_ini timestamptz;
  v_mes_fin timestamptz;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  v_reparto := private.puede_operar_reparto_crm();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_corte := v_ahora - interval '45 days'; -- ventana de la VISTA, no de la metrica
  v_mes := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_mes_ini := (v_mes::timestamp at time zone 'America/Lima');
  v_mes_fin := ((v_mes + interval '1 month')::timestamp at time zone 'America/Lima');

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
  -- F2.4 (decision D1): la METRICA pasa al mes calendario del NUCLEO. La
  -- ventana de 45 dias sigue siendo la de la VISTA (que leads se ven en
  -- cartera). Va GLOBAL y se recorta al unir con el ambito ya recortado.
  nucleo_mes as materialized (
    select e.analista_id,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones
    from private.conversion_episodios(
      v_mes_ini, v_mes_fin, v_mes, true, '{}'::uuid[],
      private.peso_referido_conversion(v_mes)
    ) e
    where e.analista_id = any(v_visibles) or v_rol = 'gerencia' or v_lector
    group by e.analista_id
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
    'ventana_metrica', 'mes_calendario',
    'mes_metrica', v_mes,
    'totales', jsonb_build_object(
      'vivos', count(*),
      'abiertos', count(*) filter (where a.abierto),
      'asignados', count(*) filter (where a.abierto and a.vendedor_id is not null),
      'parkeados', count(*) filter (where a.abierto and a.vendedor_id is null),
      -- F2.4/D1: los cierres del MES del ledger, no los leads con etapa
      -- convertido dentro de la ventana de la VISTA (que incluia anulados).
      -- CIERRES DE LEAD, sin las operaciones de cartera: el mismo criterio que
      -- la serie comercial y que Gestion de equipo. Las renovaciones no son
      -- «convertidos» de este tile; el % del nucleo si las cuenta.
      'convertidos', (select coalesce(sum(
           nm.cierres_no_referidos + nm.cierres_referidos), 0)
         from nucleo_mes nm),
      'operaciones_cartera', (select coalesce(sum(nm.operaciones), 0) from nucleo_mes nm),
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

do $postflight$
declare v_src text;
begin
  select p.prosrc into v_src from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'metricas_vendedores_fn';
  if strpos(v_src, '+ coalesce(nm.operaciones, 0) as convertidos') > 0 then
    raise exception 'convertidos vuelve a sumar la cartera; rollback';
  end if;
  if strpos(v_src, 'operaciones_cartera') = 0 then
    raise exception 'las operaciones de cartera dejaron de viajar aparte; rollback';
  end if;

  select p.prosrc into v_src from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'resumen_cartera_fn';
  if strpos(v_src, 'nm.cierres_referidos + nm.operaciones') > 0 then
    raise exception 'el tile de cartera vuelve a sumar las operaciones; rollback';
  end if;
end;
$postflight$;
