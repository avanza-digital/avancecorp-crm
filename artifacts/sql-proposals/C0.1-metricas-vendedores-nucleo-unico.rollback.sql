-- Rollback exacto de C0.1 · nucleo unico en metricas_vendedores_fn.
--
-- Restaura las dos definiciones capturadas en produccion el 2026-08-28 antes
-- de C0.1, junto con owner, COST, comentarios y ACL directas. Es fail-closed:
-- solo corre si ambas funciones conservan exactamente los cuerpos candidatos
-- aprobados. Cualquier deriva aborta la transaccion completa.
--
-- Baseline md5(prosrc):
--   crm.metricas_vendedores_fn()
--     87998c3b195d8f5e7197c579e71e5da9
--   private.metricas_cartera_por_vendedor(date)
--     8ac031c77f340328336df1c58cafa464
-- Candidato C0.1 md5(prosrc):
--   crm.metricas_vendedores_fn()
--     d8226991aba1783b042eaf087568ba49
--   private.metricas_cartera_por_vendedor(date)
--     a5ec29bd68511a286a3d2ea4d316a9be

begin;

set local lock_timeout = '10s';
set local statement_timeout = '5min';
set local search_path = pg_catalog;

do $rollback_preflight$
declare
  v_target record;
  v_oid oid;
  v_hash text;
  v_cost real;
  v_owner text;
  v_language text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
  v_xmin text;
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'avancecorp.c0.1.metricas_vendedores_nucleo_unico',
      0
    )
  );

  for v_target in
    select *
    from (values
      (
        'crm.metricas_vendedores_fn()',
        'd8226991aba1783b042eaf087568ba49',
        'plpgsql'
      ),
      (
        'private.metricas_cartera_por_vendedor(date)',
        'a5ec29bd68511a286a3d2ea4d316a9be',
        'sql'
      )
    ) as t(firma, hash_candidato, lenguaje)
  loop
    v_oid := pg_catalog.to_regprocedure(v_target.firma);
    if v_oid is null then
      raise exception 'ABORT rollback C0.1: falta %', v_target.firma;
    end if;

    select
      pg_catalog.md5(p.prosrc),
      p.procost,
      r.rolname,
      l.lanname,
      p.prosecdef,
      p.provolatile,
      p.proconfig
    into
      v_hash,
      v_cost,
      v_owner,
      v_language,
      v_secdef,
      v_volatility,
      v_config
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    join pg_catalog.pg_language l on l.oid = p.prolang
    where p.oid = v_oid;

    if v_hash is distinct from v_target.hash_candidato then
      raise exception
        'ABORT rollback C0.1: % no conserva el candidato aprobado (% vs %)',
        v_target.firma,
        v_hash,
        v_target.hash_candidato;
    end if;

    if v_owner is distinct from 'postgres'
       or v_language is distinct from v_target.lenguaje
       or not v_secdef
       or v_volatility is distinct from 's'
       or v_config is distinct from array['search_path=""']::text[]
       or v_cost is distinct from 100::real then
      raise exception
        'ABORT rollback C0.1: catalogo inesperado en %',
        v_target.firma;
    end if;

    -- Conserva el COST pero fuerza una actualizacion de la tupla pg_proc; así
    -- la fila queda excluida hasta COMMIT/ROLLBACK sin requerir privilegios de
    -- LOCK sobre catalogos del sistema en Supabase administrado.
    execute pg_catalog.format(
      'alter function %s cost %s',
      v_oid::pg_catalog.regprocedure,
      v_cost
    );

    select p.xmin::text
      into v_xmin
    from pg_catalog.pg_proc p
    where p.oid = v_oid;

    if v_xmin is distinct from pg_catalog.pg_current_xact_id()::text then
      raise exception
        'ABORT rollback C0.1: no se materializo el lock de %',
        v_target.firma;
    end if;
  end loop;
end
$rollback_preflight$;

CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), elegibles as (
    select o.*,
           row_number() over (
             partition by o.cliente_id, o.periodo
             order by o.fecha_operacion, o.creado_en, o.id
           ) as orden_conversion
    from ops o
    where o.elegible_conversion
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (where e.tipo = 'renovacion')::int as conversiones_renovacion,
      count(*) filter (where e.tipo = 'upgrade')::int as conversiones_upgrade
    from elegibles e
    where e.orden_conversion = 1
    group by e.vendedor_id
  ), economia as (
    select
      o.vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int as operaciones_upgrade,
      coalesce(sum(o.capital_renovado) filter (
        where o.tipo = 'renovacion' and o.moneda = 'PEN'), 0) as capital_renovado_pen,
      coalesce(sum(o.capital_renovado) filter (
        where o.tipo = 'renovacion' and o.moneda = 'USD'), 0) as capital_renovado_usd,
      coalesce(sum(o.capital_adicional) filter (
        where o.tipo = 'renovacion' and o.moneda = 'PEN'), 0) as capital_adicional_pen,
      coalesce(sum(o.capital_adicional) filter (
        where o.tipo = 'renovacion' and o.moneda = 'USD'), 0) as capital_adicional_usd,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo)::int
        as renovaciones_sin_desglose
    from ops o
    group by o.vendedor_id
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(e.capital_renovado_pen, 0),
    coalesce(e.capital_renovado_usd, 0),
    coalesce(e.capital_adicional_pen, 0),
    coalesce(e.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join economia e using (vendedor_id)
$function$;

alter function private.metricas_cartera_por_vendedor(date)
  owner to postgres;
alter function private.metricas_cartera_por_vendedor(date)
  cost 100;
revoke all on function private.metricas_cartera_por_vendedor(date)
  from public, anon, authenticated, service_role, postgres;
grant execute on function private.metricas_cartera_por_vendedor(date)
  to postgres;
comment on function private.metricas_cartera_por_vendedor(date) is
  'Conversión deduplicada por cliente/mes y economía completa de renovaciones por asesor. El adicional solo vive en las columnas de dinero.';

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

alter function crm.metricas_vendedores_fn()
  owner to postgres;
alter function crm.metricas_vendedores_fn()
  cost 100;
revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role, postgres;
grant execute on function crm.metricas_vendedores_fn()
  to postgres, authenticated;
comment on function crm.metricas_vendedores_fn() is
  'Gestion de equipo (F2.4/D1): la conversion por vendedor es la del NUCLEO del MES CALENDARIO — la misma que HOY/Ranking/Metas/Conversiones. La ventana de 45 dias sigue viva pero SOLO como filtro de la VISTA (que leads se ven en cartera, regla del 08/08); el payload lo declara en `ventana_metrica`.';

do $rollback_postflight$
declare
  v_target record;
  v_oid oid;
  v_hash text;
  v_owner text;
  v_language text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
  v_cost real;
  v_result text;
  v_comment text;
  v_exec_count integer;
  v_owner_exec integer;
  v_authenticated_exec integer;
  v_xmin text;
begin
  for v_target in
    select *
    from (values
      (
        'crm.metricas_vendedores_fn()',
        '87998c3b195d8f5e7197c579e71e5da9',
        'plpgsql',
        'jsonb',
        'Gestion de equipo (F2.4/D1): la conversion por vendedor es la del NUCLEO del MES CALENDARIO — la misma que HOY/Ranking/Metas/Conversiones. La ventana de 45 dias sigue viva pero SOLO como filtro de la VISTA (que leads se ven en cartera, regla del 08/08); el payload lo declara en `ventana_metrica`.',
        2
      ),
      (
        'private.metricas_cartera_por_vendedor(date)',
        '8ac031c77f340328336df1c58cafa464',
        'sql',
        'TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)',
        'Conversión deduplicada por cliente/mes y economía completa de renovaciones por asesor. El adicional solo vive en las columnas de dinero.',
        1
      )
    ) as t(
      firma,
      hash_baseline,
      lenguaje,
      resultado,
      comentario,
      ejecutores_esperados
    )
  loop
    v_oid := pg_catalog.to_regprocedure(v_target.firma);
    if v_oid is null then
      raise exception
        'POSTFLIGHT rollback C0.1: falta %',
        v_target.firma;
    end if;

    select
      pg_catalog.md5(p.prosrc),
      r.rolname,
      l.lanname,
      p.prosecdef,
      p.provolatile,
      p.proconfig,
      p.procost,
      pg_catalog.pg_get_function_result(p.oid),
      pg_catalog.obj_description(p.oid, 'pg_proc')
    into
      v_hash,
      v_owner,
      v_language,
      v_secdef,
      v_volatility,
      v_config,
      v_cost,
      v_result,
      v_comment
    from pg_catalog.pg_proc p
    join pg_catalog.pg_roles r on r.oid = p.proowner
    join pg_catalog.pg_language l on l.oid = p.prolang
    where p.oid = v_oid;

    if v_hash is distinct from v_target.hash_baseline
       or v_owner is distinct from 'postgres'
       or v_language is distinct from v_target.lenguaje
       or not v_secdef
       or v_volatility is distinct from 's'
       or v_config is distinct from array['search_path=""']::text[]
       or v_cost is distinct from 100::real
       or v_result is distinct from v_target.resultado
       or v_comment is distinct from v_target.comentario then
      raise exception
        'POSTFLIGHT rollback C0.1: cuerpo o catalogo inesperado en %',
        v_target.firma;
    end if;

    select
      count(*)::int,
      count(*) filter (
        where a.grantee = p.proowner
          and a.grantor = p.proowner
          and not a.is_grantable
      )::int,
      count(*) filter (
        where a.grantee = pg_catalog.to_regrole('authenticated')
          and a.grantor = p.proowner
          and not a.is_grantable
      )::int
    into
      v_exec_count,
      v_owner_exec,
      v_authenticated_exec
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) a
    where p.oid = v_oid
      and a.privilege_type = 'EXECUTE';

    if v_exec_count is distinct from v_target.ejecutores_esperados
       or v_owner_exec is distinct from 1
       or (
         v_target.firma = 'crm.metricas_vendedores_fn()'
         and v_authenticated_exec is distinct from 1
       )
       or (
         v_target.firma <> 'crm.metricas_vendedores_fn()'
         and v_authenticated_exec is distinct from 0
       ) then
      raise exception
        'POSTFLIGHT rollback C0.1: ACL directa inesperada en %',
        v_target.firma;
    end if;

    select p.xmin::text
      into v_xmin
    from pg_catalog.pg_proc p
    where p.oid = v_oid;

    if v_xmin is distinct from pg_catalog.pg_current_xact_id()::text then
      raise exception
        'POSTFLIGHT rollback C0.1: se perdio el lock de %',
        v_target.firma;
    end if;
  end loop;
end
$rollback_postflight$;

commit;
