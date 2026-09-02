-- El ranking por mes calendario debe conservar la poblacion de ESE mes.
--
-- Antes, crm.metricas_conversiones_equipo_fn siempre partia del roster activo
-- de hoy y terminaba filtrando otra vez por el rol actual. Dos consecuencias:
--   * durante la ventana de ajuste (dias 1-9), agosto podia incorporar a una
--     persona que recien entro en septiembre y borrar a quien tenia meta en
--     agosto;
--   * una vez sellado el mes, el ranking ignoraba el supervisor y la poblacion
--     guardados en crm.cierre_mes_vendedor, aunque cumplimiento_metas_fn si los
--     respetaba mediante private.cierre_mes_visible.
--
-- Este cambio NO crea otro motor comercial. Reemplaza las dos RPC existentes
-- que alimentan el ranking y usa las mismas fuentes mensuales que
-- cumplimiento_metas_fn:
--   * mes historico abierto: ultima revision publicada en meta_periodos /
--     metas_vendedor, recortada por el ambito vigente (igual que cumplimiento);
--   * mes cerrado: private.cierre_mes_visible, que aplica el supervisor SELLADO;
--   * mes actual o rango libre: conserva exactamente el roster activo vigente.
--
-- La cosecha sigue madurando hasta hoy, que es su contrato propio. Lo que se
-- corrige aqui es quien pertenece a la comparacion mensual y quien puede verlo.

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight: no pisar una version distinta y comprobar las fuentes comunes.
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_owner text;
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'metricas_conversiones_equipo_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_desde date, p_hasta date')
     is distinct from '32e186d9753704250a17dadd6bbda34f' then
    raise exception 'metricas_conversiones_equipo_fn viva no es la version F2.2 esperada; re-capturar antes de reemplazar';
  end if;

  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'conversion_mensual_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_periodo date')
     is distinct from 'e448b17faa58a20c38c4c5c67802adc7' then
    raise exception 'conversion_mensual_fn viva no es la version con cartera esperada; re-capturar antes de reemplazar';
  end if;

  if pg_catalog.to_regclass('crm.meta_periodos') is null
     or pg_catalog.to_regclass('crm.metas_vendedor') is null
     or pg_catalog.to_regclass('crm.periodos_cerrados') is null
     or pg_catalog.to_regclass('crm.cierre_mes_vendedor') is null
     or pg_catalog.to_regprocedure('private.cierre_mes_visible(date,uuid)') is null then
    raise exception 'faltan las fuentes mensuales compartidas con cumplimiento_metas_fn';
  end if;

  select p.proowner::regrole::text into v_owner
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'metricas_conversiones_equipo_fn'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
        'p_desde date, p_hasta date';

  if not pg_catalog.has_function_privilege(
    v_owner, 'private.cierre_mes_visible(date,uuid)', 'EXECUTE'
  ) then
    raise exception 'el owner del ranking no puede ejecutar cierre_mes_visible';
  end if;

  select p.proowner::regrole::text into v_owner
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'conversion_mensual_fn'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
        'p_periodo date';

  if not pg_catalog.has_function_privilege(
       v_owner,
       'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)',
       'EXECUTE')
     or not pg_catalog.has_function_privilege(
       v_owner, 'private.ajuste_pendiente_por_vendedor()', 'EXECUTE')
     or not pg_catalog.has_function_privilege(
       v_owner, 'private.metricas_cartera_por_vendedor(date)', 'EXECUTE') then
    raise exception 'el owner de conversion_mensual_fn no puede ejecutar sus nucleos privados';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. Misma RPC, con poblacion mensual para meses calendario historicos.
-- ---------------------------------------------------------------------------
create or replace function crm.metricas_conversiones_equipo_fn(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_mes_actual date := date_trunc('month', v_hoy)::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_mes date;
  v_factor numeric;
  v_periodo date;
  v_es_mes_historico boolean := false;
  v_cerrado boolean := false;
  v_meta_periodo_id uuid;
  v_payload jsonb;
begin
  -- 1) GATE EXPLICITO, ANTES DE TOCAR NINGUN DATO.
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  -- 2) Validacion de parametros (identica a la global).
  if p_desde is null or p_hasta is null or p_desde > p_hasta
     or p_hasta > v_hoy or p_hasta - p_desde > 365 then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;

  -- 3) Ambito vigente por defecto. Solo un mes CERRADO lo sustituye por el
  -- ambito sellado; un historico aun abierto usa el mismo recorte vigente que
  -- cumplimiento_metas_fn durante la ventana de ajuste.
  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_desde::timestamp at time zone 'America/Lima';
  v_fin := (p_hasta + 1)::timestamp at time zone 'America/Lima';

  -- La cosecha madura hasta hoy: un lead que entro en el rango puede cerrar
  -- despues, y esa maduracion es el sentido de la lectura por cosecha.
  v_cosecha_fin := greatest(v_fin, v_ahora);

  v_mes := date_trunc('month', p_hasta)::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- La pierna de cartera solo con el mes ENTERO o todo lo que va del mes en
  -- curso: la tabla-base filtra cartera por MES, no por la ventana, asi que
  -- un recorte del mes sumaria operaciones fuera del rango.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Solo un mes calendario ANTERIOR cambia de poblacion. Un rango libre y el
  -- mes actual conservan la semantica vigente de roster activo.
  v_es_mes_historico := v_periodo is not null and v_periodo < v_mes_actual;

  if v_es_mes_historico then
    select exists (
      select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo
    ) into v_cerrado;

    if v_cerrado and not v_global then
      -- El ambito de los episodios tambien debe ser el SELLADO. Cambiar solo
      -- las filas del roster mostraria al vendedor historico con ceros.
      select coalesce(
        array_agg(f.vendedor_id order by f.vendedor_id), '{}'::uuid[]
      ) into v_visibles
      from private.cierre_mes_visible(v_periodo, v_uid) f;
    elsif not v_cerrado then
      -- Misma seleccion de revision vigente que cumplimiento_metas_fn.
      select mp.id into v_meta_periodo_id
      from crm.meta_periodos mp
      where mp.periodo = v_periodo
      order by mp.revision desc
      limit 1;
    end if;
  end if;

  with roster as materialized (
    -- Mes sellado: quien estaba en la foto, con el supervisor de ese mes. No se
    -- vuelve a preguntar si hoy sigue activo o conserva rol de vendedor.
    select f.vendedor_id
    from private.cierre_mes_visible(v_periodo, v_uid) f
    where v_es_mes_historico and v_cerrado

    union all

    -- Mes historico aun abierto: ultima publicacion mensual, exactamente la
    -- poblacion que cumplimiento_metas_fn devuelve durante el ajuste.
    select mv.vendedor_id
    from crm.metas_vendedor mv
    where v_es_mes_historico
      and not v_cerrado
      and mv.meta_periodo_id = v_meta_periodo_id
      and (v_global or mv.vendedor_id = any(v_visibles))

    union all

    -- Mes actual y rangos libres: comportamiento anterior, sin cambios.
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where not v_es_mes_historico
      and e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  -- TABLA-BASE, ya recortada al ambito del que pregunta. Para un cierre, el
  -- array v_visibles fue sustituido por los vendedores de su foto.
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, v_global, v_visibles, v_factor
    ) e
  ),
  -- Esta pierna va GLOBAL a proposito. `cohorte` atribuye el lead a su dueno
  -- actual mientras el ledger lo atribuye a quien lo cerro. El conjunto no
  -- sale al payload; solo prueba cierres de leads ya recortados en `cohorte`.
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null::date, true, '{}'::uuid[], v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
  ),
  cohorte as materialized (
    select l.id as lead_id,
           l.vendedor_id,
           (l.id in (select ec.lead_id from ep_cosecha ec)) as contrato
    from crm.leads l
    where l.creado_en >= v_ini
      and l.creado_en < v_fin
      and l.activo is true
      and l.vendedor_id is not null
      and (v_global or l.vendedor_id = any(v_visibles))
  ),
  responsables_resumen as (
    select r.vendedor_id,
      count(c.lead_id)::int as leads,
      count(c.lead_id) filter (where c.contrato)::int as clientes
    from roster r
    left join cohorte c on c.vendedor_id = r.vendedor_id
    group by r.vendedor_id
  ),
  nucleo_vendedor as (
    select e.analista_id,
      count(*) filter (where e.tipo = 'recibido' and not e.fue_referido)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (where e.tipo = 'cierre' and not e.anulado and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones
    from ep_flujo e
    group by e.analista_id
  ),
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nucleo_vendedor nv
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, v_global, v_visibles, v_factor
    ) cm on cm.analista_id = nv.analista_id
    where v_periodo is not null
  ),
  sonda_paridad as (
    select
      case when v_periodo is null then null else coalesce(sum(c.delta), 0) end as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'alcance', case when v_global then 'global' else 'equipo' end,
    'periodo', jsonb_build_object(
      'desde', p_desde,
      'hasta', p_hasta,
      'dias', (p_hasta - p_desde) + 1,
      'zona', 'America/Lima'
    ),
    'nucleo', jsonb_build_object(
      'base', 'asignacion',
      'incluye_cartera', v_periodo is not null,
      'peso_referido', v_factor,
      'mes_peso', v_mes
    ),
    'sondas', jsonb_build_object(
      'paridad_nucleo', sp.desvio,
      'paridad_filas', sp.filas,
      'cuadra', case when sp.desvio is null or sp.filas = 0 then null
                     else sp.desvio = 0 end,
      'divisor_fuera_del_roster', (
        select coalesce(sum(nv2.divisor), 0)::int
        from nucleo_vendedor nv2
        where nv2.analista_id is null
           or nv2.analista_id not in (select r2.vendedor_id from roster r2)
      ),
      'numerador_fuera_del_roster', (
        select coalesce(sum(
          (nv3.cierres_no_referidos + v_factor * nv3.cierres_referidos + nv3.operaciones)::numeric
        ), 0)
        from nucleo_vendedor nv3
        where nv3.analista_id is null
           or nv3.analista_id not in (select r3.vendedor_id from roster r3)
      ),
      'cierres_anulados', (
        select count(*)::int from ep_flujo e where e.tipo = 'cierre' and e.anulado
      ),
      'clientes_acreditados_a_otro_dueno', (
        select count(*)::int
        from cohorte c
        join crm.lead_asignaciones la on la.lead_id = c.lead_id
        where c.contrato
          and la.resultado = 'convertido'
          and la.analista_id is distinct from c.vendedor_id
      )
    ),
    'responsables', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'vendedor_id', rr.vendedor_id,
          'leads', rr.leads,
          'clientes', rr.clientes,
          'conversion_pct', case when rr.leads > 0
            then round(100.0 * rr.clientes / rr.leads, 1) end,
          'nucleo_divisor', coalesce(nv.divisor, 0),
          'nucleo_numerador', coalesce(
            (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric, 0),
          'nucleo_conversion_pct', case when coalesce(nv.divisor, 0) > 0
            then round(100.0 * (nv.cierres_no_referidos + v_factor * nv.cierres_referidos
                                + nv.operaciones) / nv.divisor, 2) end
        )
        order by rr.clientes desc, rr.leads desc, rr.vendedor_id
      )
      from responsables_resumen rr
      left join nucleo_vendedor nv on nv.analista_id = rr.vendedor_id
    ), '[]'::jsonb)
  ) into v_payload
  from sonda_paridad sp;

  -- Un roster mensual ya fue validado por su propia fuente. Volver a filtrarlo
  -- por el rol ACTUAL borraria precisamente a las bajas historicas. Rangos
  -- libres y mes actual conservan la defensa previa.
  if v_es_mes_historico then
    return v_payload;
  end if;

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

comment on function crm.metricas_conversiones_equipo_fn(date,date) is
  'Ranking del equipo sobre private.conversion_episodios. En un mes calendario historico usa la misma poblacion mensual que cumplimiento_metas_fn: ultima revision de metas mientras esta abierto y cierre_mes_visible una vez sellado; mes actual y rangos libres conservan el roster activo. La cosecha madura hasta hoy.';

-- ---------------------------------------------------------------------------
-- 2. Conversion mensual: misma foto durante la ventana de ajuste (dias 1-9).
-- ---------------------------------------------------------------------------
-- `conversion_mensual_sin_cartera_fn` conserva intactas la validacion, la rama
-- de mes cerrado y la cobertura. Solo se reemplaza la poblacion de un mes
-- PASADO aun abierto; toda la aritmetica sigue saliendo de
-- private.conversion_mensual_por_vendedor y private.conversion_con_ajuste.
-- Despues se aplica el mismo wrapper de cartera que ya tenia la RPC publica.
create or replace function crm.conversion_mensual_fn(p_periodo date)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $conversion_function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text := private.rol_crm(v_uid);
  v_lector boolean := private.es_lector_global();
  v_global boolean;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_mes_actual date := date_trunc('month', v_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_meta_periodo_id uuid;
  v_es_historico boolean;
  v_es_historico_abierto boolean;
  v_base jsonb;
  v_total jsonb;
  v_total_conversion jsonb;
  v_cobertura jsonb;
  v_responsables jsonb;
begin
  -- Gate antes de cualquier lectura. La base vuelve a validarlo y valida el
  -- periodo; la duplicacion deliberada conserva el borde publico fail-closed.
  if v_uid is null or not coalesce(
    v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false
  ) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_base := crm.conversion_mensual_sin_cartera_fn(p_periodo);
  v_es_historico := p_periodo < v_mes_actual;
  v_es_historico_abierto := v_es_historico
    and coalesce((v_base #>> '{cierre,cerrado}')::boolean, false) is false;

  if v_es_historico_abierto then
    -- Igual que cumplimiento_metas_fn: gerencia/lector ven la publicacion
    -- completa; los demas la intersectan con su ambito vigente mientras el mes
    -- siga abierto. Al sellarlo manda supervisor_id de la foto de cierre.
    v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
    v_visibles := case when v_global then '{}'::uuid[]
                       else array(select private.vendedor_ids_visibles(v_uid)) end;
    v_ini := p_periodo::timestamp at time zone 'America/Lima';
    v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
    v_factor := (v_base #>> '{ponderacion,referido}')::numeric;

    select mp.id into v_meta_periodo_id
    from crm.meta_periodos mp
    where mp.periodo = p_periodo
    order by mp.revision desc
    limit 1;

    with roster as materialized (
      select mv.vendedor_id, mv.supervisor_id
      from crm.metas_vendedor mv
      where mv.meta_periodo_id = v_meta_periodo_id
        and (v_global or mv.vendedor_id = any(v_visibles))
    ), base as materialized (
      -- El nucleo se calcula una sola vez. Se conserva el ambito vigente para
      -- que `fuera_de_roster` siga denunciando actividad ajena a la foto.
      select cm.*
      from private.conversion_mensual_por_vendedor(
        v_ini, v_fin, v_global, v_visibles, v_factor
      ) cm
    ), alta_referidos as materialized (
      select l.creado_por as analista_id, count(*)::int as dados_de_alta
      from crm.leads l
      where l.origen = 'referido'
        and l.creado_en >= v_ini
        and l.creado_en < v_fin
        and l.creado_por is not null
        and (v_global or l.creado_por = any(v_visibles))
      group by l.creado_por
    ), pendientes as materialized (
      select ap.vendedor_id, ap.numerador as pendiente, ap.origenes
      from private.ajuste_pendiente_por_vendedor() ap
    ), filas as materialized (
      select
        r.vendedor_id,
        r.supervisor_id,
        coalesce(b.divisor, 0) as divisor,
        coalesce(b.divisor_aproximado, 0) as divisor_aproximado,
        coalesce(b.divisor_por_motivo, '{}'::jsonb) as divisor_por_motivo,
        coalesce(b.cierres_no_referidos, 0) as cierres_no_referidos,
        coalesce(b.cierres_referidos, 0) as cierres_referidos,
        coalesce(b.cierres_de_arrastre, 0) as cierres_de_arrastre,
        private.conversion_con_ajuste(b.numerador, pd.pendiente) as numerador,
        case when coalesce(b.divisor, 0) > 0 then round(
          100.0 * private.conversion_con_ajuste(b.numerador, pd.pendiente)
          / coalesce(b.divisor, 0), 2
        ) end as conversion_pct,
        coalesce(pd.pendiente, 0::numeric) as ajuste_pendiente,
        coalesce(pd.origenes, '[]'::jsonb) as ajuste_origenes,
        coalesce(b.procedencia, '[]'::jsonb) as procedencia,
        coalesce(b.referidos_recibidos, 0) as referidos_recibidos,
        b.referidos_aporta_pct,
        coalesce(a.dados_de_alta, 0) as dados_de_alta
      from roster r
      left join base b on b.analista_id = r.vendedor_id
      left join alta_referidos a on a.analista_id = r.vendedor_id
      left join pendientes pd on pd.vendedor_id = r.vendedor_id
    ), fuera as (
      -- Conserva F2.6: la produccion del ambito que no pertenece a la foto se
      -- publica solo como agregado y tambien forma parte del total.
      select
        count(*)::int as analistas,
        coalesce(sum(b.divisor), 0)::int as divisor,
        coalesce(sum(b.cierres_no_referidos + b.cierres_referidos), 0)::int as cierres,
        coalesce(sum(b.numerador), 0::numeric) as numerador,
        coalesce(sum(b.divisor_aproximado), 0)::int as divisor_aproximado,
        coalesce(sum(b.cierres_no_referidos), 0)::int as cierres_no_referidos,
        coalesce(sum(b.cierres_referidos), 0)::int as cierres_referidos,
        coalesce(sum(b.cierres_de_arrastre), 0)::int as cierres_de_arrastre,
        coalesce(sum(b.referidos_recibidos), 0)::int as referidos_recibidos
      from base b
      where not exists (
        select 1 from roster r where r.vendedor_id = b.analista_id
      )
    ), motivos_totales as (
      select e.key as motivo, sum(e.value::int)::int as n
      from (
        select f.divisor_por_motivo from filas f
        union all
        select coalesce(b.divisor_por_motivo, '{}'::jsonb)
        from base b
        where not exists (
          select 1 from roster r where r.vendedor_id = b.analista_id
        )
      ) dm, jsonb_each_text(dm.divisor_por_motivo) e
      group by e.key
    ), resumen as (
      select
        (count(*) + (select fr.analistas from fuera fr))::int as analistas,
        (coalesce(sum(f.divisor), 0)
          + (select fr.divisor from fuera fr))::int as divisor,
        (coalesce(sum(f.divisor_aproximado), 0)
          + (select fr.divisor_aproximado from fuera fr))::int as divisor_aproximado,
        (coalesce(sum(f.cierres_no_referidos), 0)
          + (select fr.cierres_no_referidos from fuera fr))::int as cierres_no_referidos,
        (coalesce(sum(f.cierres_referidos), 0)
          + (select fr.cierres_referidos from fuera fr))::int as cierres_referidos,
        (coalesce(sum(f.cierres_de_arrastre), 0)
          + (select fr.cierres_de_arrastre from fuera fr))::int as cierres_de_arrastre,
        (coalesce(sum(f.referidos_recibidos), 0)
          + (select fr.referidos_recibidos from fuera fr))::int as referidos_recibidos,
        (coalesce(sum(f.numerador), 0::numeric)
          + (select fr.numerador from fuera fr)) as numerador
      from filas f
    )
    select
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'vendedor_id', f.vendedor_id,
          'supervisor_id', f.supervisor_id,
          'divisor', f.divisor,
          'cierres_no_referidos', f.cierres_no_referidos,
          'cierres_referidos', f.cierres_referidos,
          'cierres_de_arrastre', f.cierres_de_arrastre,
          'numerador', f.numerador,
          'conversion_pct', f.conversion_pct,
          'estado', case
            when f.divisor > 0 then 'medible'
            when f.referidos_recibidos > 0 then 'solo_referidos'
            when (f.cierres_no_referidos + f.cierres_referidos) > 0
              then 'solo_arrastre'
            else 'sin_actividad'
          end,
          'procedencia', f.procedencia,
          'referidos', jsonb_build_object(
            'recibidos', f.referidos_recibidos,
            'cerrados', f.cierres_referidos,
            'dados_de_alta', f.dados_de_alta,
            'aporta_pct', f.referidos_aporta_pct
          ),
          'ajuste', jsonb_build_object(
            'pendiente', f.ajuste_pendiente,
            'origenes', f.ajuste_origenes
          )
        ) order by f.conversion_pct desc nulls last,
                   f.numerador desc, f.divisor desc, f.vendedor_id)
        from filas f
      ), '[]'::jsonb),
      (select jsonb_build_object(
        'analistas', r.analistas,
        'divisor', r.divisor,
        'cierres_no_referidos', r.cierres_no_referidos,
        'cierres_referidos', r.cierres_referidos,
        'cierres_de_arrastre', r.cierres_de_arrastre,
        'referidos_recibidos', r.referidos_recibidos,
        'numerador', r.numerador,
        'conversion_pct', case when r.divisor > 0
          then round(100.0 * r.numerador / r.divisor, 2) end,
        'referidos_aporta_pct', case when r.divisor > 0
          then round(100.0 * v_factor * r.cierres_referidos / r.divisor, 2) end
      ) from resumen r),
      coalesce(v_base->'cobertura', '{}'::jsonb) || jsonb_build_object(
        'divisor_aproximado', (select r.divisor_aproximado from resumen r),
        'divisor_por_motivo', coalesce((
          select jsonb_object_agg(mt.motivo, mt.n) from motivos_totales mt
        ), '{}'::jsonb),
        'fuera_de_roster', (select jsonb_build_object(
          'analistas', fr.analistas,
          'divisor', fr.divisor,
          'cierres', fr.cierres,
          'numerador', fr.numerador
        ) from fuera fr)
      )
    into v_responsables, v_total_conversion, v_cobertura;

    v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
    v_base := jsonb_set(v_base, '{total}', v_total_conversion, true);
    v_base := jsonb_set(v_base, '{cobertura}', v_cobertura, true);
  end if;

  -- Wrapper de cartera PREVIO, al literal: su total conserva el ambito vivo
  -- de metricas_cartera_fn y no se redefine por la foto rankeable.
  v_total := crm.metricas_cartera_fn(p_periodo)->'total';

  with m as materialized (
    select x.* from private.metricas_cartera_por_vendedor(p_periodo) x
  )
  select coalesce(jsonb_agg(
    e.value
    || jsonb_build_object('cartera', jsonb_build_object(
      'conversiones_clientes', coalesce(m.conversiones_clientes, 0),
      'conversiones_renovacion', coalesce(m.conversiones_renovacion, 0),
      'conversiones_upgrade', coalesce(m.conversiones_upgrade, 0),
      'capital_renovado_pen', coalesce(m.capital_renovado_pen, 0),
      'capital_renovado_usd', coalesce(m.capital_renovado_usd, 0),
      'capital_adicional_pen', coalesce(m.capital_adicional_pen, 0),
      'capital_adicional_usd', coalesce(m.capital_adicional_usd, 0),
      'renovaciones_sin_desglose', coalesce(m.renovaciones_sin_desglose, 0)
    ))
    || case
      when coalesce(m.conversiones_clientes, 0) > 0
       and coalesce((e.value->>'divisor')::int, 0) = 0
       and e.value->>'estado' = 'sin_actividad'
      then jsonb_build_object('estado', 'solo_arrastre')
      else '{}'::jsonb end
    order by e.ord
  ), '[]'::jsonb) into v_responsables
  from jsonb_array_elements(coalesce(v_base->'responsables', '[]'::jsonb))
       with ordinality e(value, ord)
  left join m on m.vendedor_id = (e.value->>'vendedor_id')::uuid;

  v_base := jsonb_set(v_base, '{responsables}', v_responsables, true);
  v_base := jsonb_set(v_base, '{cartera}', coalesce(v_total, '{}'::jsonb), true);
  v_base := jsonb_set(v_base, '{total,cartera}', coalesce(v_total, '{}'::jsonb), true);
  return v_base;
end;
$conversion_function$;

comment on function crm.conversion_mensual_fn(date) is
  'Conversion mensual publica sobre el nucleo unico y su wrapper de cartera. Mes pasado aun abierto: poblacion de la ultima revision de metas, recortada por el ambito vigente. Mes cerrado: foto sellada. Mes vigente: roster activo. No crea otra formula.';

-- ---------------------------------------------------------------------------
-- 3. Postflight: fuente mensual, ambito, seguridad y ACL sin regresiones.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_src text;
  v_norm text;
  v_conversion_src text;
  v_conversion_norm text;
begin
  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'metricas_conversiones_equipo_fn'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
        'p_desde date, p_hasta date';

  if v_src is null then
    raise exception 'metricas_conversiones_equipo_fn desaparecio; rollback';
  end if;
  v_norm := lower(pg_catalog.regexp_replace(v_src, '\s+', ' ', 'g'));

  if pg_catalog.strpos(v_norm, 'private.cierre_mes_visible(') = 0
     or pg_catalog.strpos(v_norm, 'from crm.metas_vendedor') = 0
     or pg_catalog.strpos(v_norm, 'order by mp.revision desc') = 0 then
    raise exception 'el ranking no comparte las fuentes mensuales de cumplimiento; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'v_periodo < v_mes_actual') = 0
     or pg_catalog.strpos(v_norm, 'if v_es_mes_historico then return v_payload;') = 0 then
    raise exception 'el corte historico o la preservacion de bajas desaparecio; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'array_agg(f.vendedor_id order by f.vendedor_id)') = 0 then
    raise exception 'el nucleo no usa el ambito sellado para los episodios; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'private.conversion_episodios(') = 0
     or pg_catalog.strpos(v_norm, 'private.filtrar_desglose_sujetos_crm(') = 0 then
    raise exception 'el ranking perdio su nucleo o la defensa del periodo vigente; rollback';
  end if;
  if pg_catalog.strpos(v_src, '''42501''') = 0
     or pg_catalog.strpos(v_src, '''22023''') = 0 then
    raise exception 'el ranking perdio el gate o la validacion del periodo; rollback';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname = 'metricas_conversiones_equipo_fn'
      and pg_catalog.pg_get_function_identity_arguments(p.oid) =
          'p_desde date, p_hasta date'
      and p.prosecdef
      and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'el ranking perdio security definer/search_path; rollback';
  end if;

  if (select p.proacl
      from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'crm'
        and p.proname = 'metricas_conversiones_equipo_fn'
        and pg_catalog.pg_get_function_identity_arguments(p.oid) =
            'p_desde date, p_hasta date') is null then
    raise exception 'el ranking quedo con EXECUTE por defecto para PUBLIC; rollback';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace,
         lateral pg_catalog.aclexplode(p.proacl) a
    where n.nspname = 'crm'
      and p.proname = 'metricas_conversiones_equipo_fn'
      and pg_catalog.pg_get_function_identity_arguments(p.oid) =
          'p_desde date, p_hasta date'
      and a.grantee <> p.proowner
      and a.grantee::regrole::text not in ('authenticated')
  ) then
    raise exception 'el ranking gano EXECUTE para un rol inesperado; rollback';
  end if;
  if not pg_catalog.has_function_privilege(
    'authenticated', 'crm.metricas_conversiones_equipo_fn(date,date)', 'EXECUTE'
  ) then
    raise exception 'authenticated perdio EXECUTE sobre el ranking; rollback';
  end if;

  select p.prosrc into v_conversion_src
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm'
    and p.proname = 'conversion_mensual_fn'
    and pg_catalog.pg_get_function_identity_arguments(p.oid) =
        'p_periodo date';
  if v_conversion_src is null then
    raise exception 'conversion_mensual_fn desaparecio; rollback';
  end if;
  v_conversion_norm := lower(pg_catalog.regexp_replace(
    v_conversion_src, '\s+', ' ', 'g'
  ));

  if pg_catalog.strpos(v_conversion_norm, 'from crm.meta_periodos') = 0
     or pg_catalog.strpos(v_conversion_norm, 'from crm.metas_vendedor') = 0
     or pg_catalog.strpos(v_conversion_norm, 'order by mp.revision desc') = 0
     or pg_catalog.strpos(v_conversion_norm, 'private.conversion_mensual_por_vendedor(') = 0 then
    raise exception 'conversion_mensual_fn no usa foto publicada y nucleo unico; rollback';
  end if;
  if pg_catalog.strpos(v_conversion_norm, 'crm.conversion_mensual_sin_cartera_fn(') = 0
     or pg_catalog.strpos(v_conversion_norm, 'crm.metricas_cartera_fn(') = 0
     or pg_catalog.strpos(v_conversion_norm, 'private.metricas_cartera_por_vendedor(') = 0
     or pg_catalog.strpos(v_conversion_norm, '''{total,cartera}''') = 0 then
    raise exception 'conversion_mensual_fn perdio su base o wrapper de cartera; rollback';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname = 'conversion_mensual_fn'
      and pg_catalog.pg_get_function_identity_arguments(p.oid) =
          'p_periodo date'
      and p.proowner::regrole::text = 'postgres'
      and p.prosecdef
      and p.provolatile = 's'
      and p.proconfig is not distinct from array['search_path=""']::text[]
      and p.proacl::text =
          '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
  ) then
    raise exception 'conversion_mensual_fn perdio owner/stable/definer/search_path/ACL exacta; rollback';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm'
      and p.proname = 'metricas_conversiones_equipo_fn'
      and pg_catalog.pg_get_function_identity_arguments(p.oid) =
          'p_desde date, p_hasta date'
      and p.proowner::regrole::text = 'postgres'
      and p.prosecdef
      and p.provolatile = 's'
      and p.proconfig is not distinct from array['search_path=""']::text[]
      and p.proacl::text = '{postgres=X/postgres,authenticated=X/postgres}'
  ) then
    raise exception 'metricas_conversiones_equipo_fn perdio owner/stable/definer/search_path/ACL exacta; rollback';
  end if;
end;
$postflight$;

commit;
