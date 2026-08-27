-- F2.4 del plan «Conversion unica en todo el CRM»: la ventana de 45 dias deja
-- de ser una METRICA de conversion (decision D1 de Miguel, 2026-08-26).
--
-- QUE CAMBIA, en las TRES funciones de la cartera operativa:
--   · `crm.metricas_vendedores_fn`   — «Conversion · 45 dias» de Gestion de
--     equipo pasa al MES CALENDARIO del nucleo: la MISMA cifra que HOY,
--     Ranking, Metas y Conversiones. Antes era convertidos-de-la-cartera-
--     visible / cartera, con anulados dentro y poblacion distinta (H9/H19/H20).
--   · `crm.resumen_cartera_fn`       — el tile «Convertidos» pasa a contar los
--     cierres del mes del ledger, no los leads con etapa convertido dentro de
--     la ventana de la vista.
--   · `crm.series_comerciales_fn`    — la serie de clientes salia de
--     `crm.leads.contrato_id`, la columna que nadie rellena: era **0 para
--     siempre**. Ahora sale del ledger, con la fecha real del cierre.
--
-- ⚠️ LA VENTANA DE 45 DIAS NO DESAPARECE: sigue siendo la de la **VISTA**
-- operativa — que leads se ven en cartera, la regla que Miguel cerro el
-- 2026-08-08 («ya no son leads, desaparecen 45 dias despues de convertirse»).
-- Lo que cambia es el NUMERO. Las claves `ventana_convertidos_dias: 45` se
-- conservan (siguen siendo verdad sobre la vista) y se anade
-- `ventana_metrica: 'mes_calendario'` para que F3 pueda rotularlo sin
-- adivinar.
--
-- SOLO SE ANADEN CLAVES; `conversion_pct` conserva su TIPO (entero) y el valor
-- exacto viaja aparte en `nucleo_conversion_pct`. Los schemas del front de las
-- tres pantallas son `v.object` con `v.number()` (verificado en el bundle VIVO
-- `b3f6e98`), asi que toleran las claves nuevas y los decimales.
--
-- LOS NUMEROS DE ESTAS PANTALLAS CAMBIAN el dia del corte, bajo los rotulos
-- viejos, hasta F3 (decision D4).

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_esperado text[] := array[
    'crm|metricas_vendedores_fn||1b2b946e4a79878820ec3de1defe5529',
    'crm|resumen_cartera_fn||48e3a8f8ea1d655a129893463a96cea5',
    'crm|series_comerciales_fn|p_meses integer|6e31bd7d40c8c48e1167b64b6e50eb70',
    'private|conversion_episodios|p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric|9195e57220155384e16281bbbc91de32'
  ];
  v_fila text;
  v_p text[];
  v_vivo text;
begin
  foreach v_fila in array v_esperado loop
    v_p := string_to_array(v_fila, '|');
    select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid)) into v_vivo
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = v_p[1] and p.proname = v_p[2]
       and pg_catalog.pg_get_function_identity_arguments(p.oid) = v_p[3];
    if v_vivo is distinct from v_p[4] then
      raise exception '% .% viva NO es la esperada (% vs %); re-capturar antes de F2.4',
        v_p[1], v_p[2], coalesce(v_vivo, 'AUSENTE'), v_p[4];
    end if;
  end loop;

  -- Las tres son DEFINER: quien ejecuta es su owner, y tiene que poder llamar
  -- a la tabla-base. `has_function_privilege` NO ejecuta nada (un `select fn()`
  -- sin EXECUTE tumba el backend en esta imagen).
  foreach v_fila in array array['metricas_vendedores_fn','resumen_cartera_fn','series_comerciales_fn'] loop
    if not exists (
      select 1 from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = v_fila and p.prosecdef
    ) then
      raise exception 'crm.% dejo de ser DEFINER: cambio quien ejecuta', v_fila;
    end if;
    if not pg_catalog.has_function_privilege(
         (select p.proowner::regrole::text from pg_catalog.pg_proc p
            join pg_catalog.pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'crm' and p.proname = v_fila),
         'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
         'EXECUTE') then
      raise exception 'quien ejecuta crm.% no puede ejecutar la tabla-base', v_fila;
    end if;
    if not pg_catalog.has_function_privilege(
         (select p.proowner::regrole::text from pg_catalog.pg_proc p
            join pg_catalog.pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'crm' and p.proname = v_fila),
         'private.peso_referido_conversion(date)', 'EXECUTE') then
      raise exception 'quien ejecuta crm.% no puede ejecutar peso_referido_conversion', v_fila;
    end if;
  end loop;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Gestion de equipo
-- ---------------------------------------------------------------------------
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
      coalesce(nm.cierres_no_referidos, 0) + coalesce(nm.cierres_referidos, 0)
        + coalesce(nm.operaciones, 0) as convertidos,
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

comment on function crm.metricas_vendedores_fn() is
  'Gestion de equipo (F2.4/D1): la conversion por vendedor es la del NUCLEO del MES CALENDARIO — la misma que HOY/Ranking/Metas/Conversiones. La ventana de 45 dias sigue viva pero SOLO como filtro de la VISTA (que leads se ven en cartera, regla del 08/08); el payload lo declara en `ventana_metrica`.';

-- ---------------------------------------------------------------------------
-- 2. Resumen de cartera (tile «Convertidos»)
-- ---------------------------------------------------------------------------
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
      'convertidos', (select coalesce(sum(
           nm.cierres_no_referidos + nm.cierres_referidos + nm.operaciones), 0)
         from nucleo_mes nm),
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
  'Resumen de cartera (F2.4/D1): el tile «Convertidos» cuenta los cierres del MES del ledger, no los leads con etapa convertido dentro de la ventana de la vista (que incluia anulados). La ventana de 45 dias sigue siendo la de la VISTA.';

-- ---------------------------------------------------------------------------
-- 3. Series comerciales
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.series_comerciales_fn(p_meses integer DEFAULT 6)
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

  with cierres_del_nucleo as materialized (
    -- F2.4: `es_cliente` y el mes de cierre salian de `crm.leads.contrato_id`,
    -- la columna que nadie rellena — la serie de clientes era 0 para siempre.
    -- Ahora salen del LEDGER: un cierre real, sin anular, con su fecha.
    select e.lead_id, min(e.fecha_numerador) as cerrado_en
    from private.conversion_episodios(
      v_ini, now(), null::date, true, '{}'::uuid[],
      private.peso_referido_conversion(v_mes_fin)
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
    group by e.lead_id
  ),
  meses as materialized (
    select (v_mes_fin - make_interval(months => (p_meses - 1 - g.n)))::date as mes,
           g.n as orden
    from generate_series(0, p_meses - 1) as g(n)
  ),
  ambito as materialized (
    select date_trunc('month', (l.creado_en at time zone 'America/Lima'))::date as mes_alta,
           case when cn.lead_id is not null then
             date_trunc('month', (cn.cerrado_en at time zone 'America/Lima'))::date
           end as mes_cierre,
           (cn.lead_id is not null) as es_cliente,
           l.moneda,
           coalesce(l.monto_estimado, 0) as monto
    from crm.leads l
    left join cierres_del_nucleo cn on cn.lead_id = l.id
    where l.activo is true
      and (l.creado_en >= v_ini or cn.lead_id is not null)
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
  'Series comerciales (F2.4): la serie de clientes salia de crm.leads.contrato_id, columna que nadie rellena — era 0 para siempre. Ahora sale del LEDGER de cierres, con la fecha real del cierre y sin anulados.';

-- ---------------------------------------------------------------------------
-- 4. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare v_fn text; v_src text; v_norm text;
begin
  foreach v_fn in array array['metricas_vendedores_fn','resumen_cartera_fn','series_comerciales_fn'] loop
    select p.prosrc into v_src
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'crm' and p.proname = v_fn;
    if v_src is null then
      raise exception 'crm.% desaparecio; rollback', v_fn;
    end if;
    v_norm := lower(regexp_replace(v_src, '\s+', ' ', 'g'));
    if strpos(v_norm, 'private.conversion_episodios(') = 0 then
      raise exception 'crm.% no consume la tabla-base; rollback', v_fn;
    end if;
    if strpos(v_norm, '''42501''') = 0 then
      raise exception 'crm.% perdio el gate de rol; rollback', v_fn;
    end if;
    if not exists (
      select 1 from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = v_fn
         and p.prosecdef and p.proconfig @> array['search_path=""']::text[]
    ) then
      raise exception 'crm.% perdio definer/search_path; rollback', v_fn;
    end if;
    if (select p.proacl from pg_catalog.pg_proc p
          join pg_catalog.pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = v_fn) is null then
      raise exception 'crm.% quedo con ACL por defecto (EXECUTE a PUBLIC); rollback', v_fn;
    end if;
  end loop;

  -- La columna muerta no puede seguir decidiendo quien es cliente en series.
  select p.prosrc into v_src from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'series_comerciales_fn';
  if strpos(lower(regexp_replace(v_src, '\s+', ' ', 'g')),
            '(l.contrato_id is not null) as es_cliente') > 0 then
    raise exception 'series_comerciales_fn sigue decidiendo cliente por la columna muerta; rollback';
  end if;

  -- La ventana de la VISTA (45 dias) NO puede haberse borrado: es la regla de
  -- cartera del 08/08, y D1 solo cambio la METRICA.
  foreach v_fn in array array['metricas_vendedores_fn','resumen_cartera_fn'] loop
    select p.prosrc into v_src from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'crm' and p.proname = v_fn;
    if strpos(v_src, 'interval ''45 days''') = 0 then
      raise exception 'crm.% perdio la ventana de 45 dias de la VISTA; rollback', v_fn;
    end if;
  end loop;
end;
$postflight$;
