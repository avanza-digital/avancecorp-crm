-- F2.2 del plan «Conversion unica en todo el CRM»: el Ranking del equipo deja
-- de medir una columna muerta y pasa a leer la tabla-base.
--
-- QUE CAMBIA: `crm.metricas_conversiones_equipo_fn` contaba
-- `crm.leads.contrato_id is not null` — la MISMA columna que nadie rellena y
-- que tenia la pantalla Conversiones en 0 % (hallazgo H3, arreglado en F2.1).
-- Aqui el `clientes` del ranking valia 0 para todos y el orden del ranking se
-- decidia por `leads`, no por resultados. Pasa al LEDGER de cierres, leido de
-- `private.conversion_episodios` (F1).
--
-- Se anaden por responsable las cifras del NUCLEO (`nucleo_divisor`,
-- `nucleo_numerador`, `nucleo_conversion_pct`): la MISMA que HOY, Metas y la
-- pantalla Conversiones tras F2.1, ya con el ambito del que pregunta. Y un
-- bloque `sondas` con la paridad contra el nucleo real.
--
-- SOLO SE ANADEN CLAVES: el schema del front de esta pantalla es `v.object`
-- (verificado en el bundle VIVO b3f6e98: 0 strictObject) y descarta lo que no
-- conoce; los rotulos se corrigen en F3.
--
-- LOS NUMEROS DEL RANKING CAMBIAN el dia del corte, bajo los rotulos viejos
-- (transicion aceptada por Miguel, decision D4).

-- ---------------------------------------------------------------------------
-- 0. Preflight: lo vivo es lo esperado, la tabla-base es la de F1, y ambas
--    funciones comparten owner (si no, el DEFINER no podria llamarla y en la
--    imagen Supabase 17.6 eso tumba el backend).
-- ---------------------------------------------------------------------------
do $preflight$
begin
  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm'
         and p.proname = 'metricas_conversiones_equipo_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date')
     is distinct from '4c0cf65902ea5477b63d893e24e01e2b' then
    raise exception 'metricas_conversiones_equipo_fn viva NO es la esperada; re-capturar antes de F2.2';
  end if;

  if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private'
         and p.proname = 'conversion_episodios'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) =
             'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric')
     is distinct from '9195e57220155384e16281bbbc91de32' then
    raise exception 'conversion_episodios viva NO es la de F1; re-capturar antes de F2.2';
  end if;

  if (select p.proowner from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date')
     is distinct from
     (select p.proowner from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'conversion_episodios') then
    raise exception 'el ranking y la tabla-base tienen OWNERS DISTINTOS: el DEFINER no podria ejecutarla';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. El ranking, agrupando la tabla-base
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
  v_ini timestamptz;
  v_fin timestamptz;
  v_cosecha_fin timestamptz;
  v_mes date;
  v_factor numeric;
  v_periodo date;
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

  -- 3) Ambito capturado UNA vez en array para que `= any(...)` sea indexable.
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

  with roster as materialized (
    select e.perfil_id as vendedor_id
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
    where e.rol_crm = 'vendedor'
      and e.activo is true
      and p.activo is true
      and (v_global or e.perfil_id = any(v_visibles))
  ),
  -- ── TABLA-BASE, ya recortada al ambito del que pregunta ─────────────────
  ep_flujo as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, v_global, v_visibles, v_factor
    ) e
  ),
  ep_cosecha as materialized (
    select distinct e.lead_id
    from private.conversion_episodios(
      v_ini, v_cosecha_fin, null, v_global, v_visibles, v_factor
    ) e
    where e.tipo = 'cierre' and not e.anulado and e.lead_id is not null
  ),
  cohorte as materialized (
    -- `activo is true`: espejo de leads_select. Sin el, un supervisor que apaga
    -- un lead lo seguiria contando en su propio denominador.
    select l.id as lead_id,
           l.vendedor_id,
           -- ANTES esto miraba la columna de contrato enlazado, que nadie
           -- rellena: por eso el ranking daba 0 clientes a TODO el mundo y se
           -- ordenaba por leads. (El texto exacto de aquel predicado no se
           -- escribe aqui: el postflight lo busca para detectar regresiones.)
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
  -- ── NUCLEO por vendedor: la MISMA cifra que HOY, Metas y Conversiones ───
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
  -- Paridad contra el nucleo real: compara los cuatro terminos y declara
  -- cuantas filas comparo (sin filas, la sonda no prueba nada y lo dice).
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
      -- Divisor y numerador que NO apareceran en `responsables`: episodios de
      -- analistas fuera del roster de vendedores (supervisores, bajas).
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
          -- Cifra del NUCLEO (dos decimales, como el nucleo real, para que sea
          -- comparable byte a byte con el heroe de HOY).
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

  return private.filtrar_desglose_sujetos_crm(
    v_payload, 'responsables', 'vendedor_id', array['vendedor']
  );
end;
$function$;

comment on function crm.metricas_conversiones_equipo_fn(date,date) is
  'Ranking del equipo (F2.2): agrupa private.conversion_episodios con el ambito del que pregunta. `clientes` ya NO es crm.leads.contrato_id (columna que nadie rellena, por la que todo el ranking marcaba 0): son cierres del ledger, sin anulados, madurando hasta hoy. Cada responsable lleva ademas su cifra del NUCLEO (la misma que HOY/Metas/Conversiones) y el payload trae sondas de paridad y de lo que cae fuera del roster.';

-- ---------------------------------------------------------------------------
-- 2. Postflight estructural (misma transaccion)
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_src text;
begin
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date';

  if v_src is null then
    raise exception 'metricas_conversiones_equipo_fn desaparecio; rollback';
  end if;
  -- strpos, JAMAS like: el guion bajo es comodin en LIKE
  if strpos(v_src, 'conversion_episodios') = 0 then
    raise exception 'el ranking no consume la tabla-base; rollback';
  end if;
  if strpos(v_src, 'l.contrato_id is not null') > 0 then
    raise exception 'el numerador muerto (contrato_id) sigue vivo en el ranking; rollback';
  end if;
  if strpos(v_src, 'filtrar_desglose_sujetos_crm') = 0 then
    raise exception 'el ranking dejo de filtrar el desglose por rol; rollback';
  end if;
  if strpos(v_src, '''42501''') = 0 or strpos(v_src, '''22023''') = 0 then
    raise exception 'el ranking perdio el gate de rol o la validacion de periodo; rollback';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
       and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date'
       and p.prosecdef
       and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'el ranking perdio definer/search_path; rollback';
  end if;

  -- La ACL de una RPC publica NO debe ser NULL (privilegios por defecto =
  -- EXECUTE a PUBLIC) y `aclexplode(null)` devuelve cero filas, asi que el
  -- NULL se rechaza aparte antes de mirar los grantees.
  if (select p.proacl from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
         and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date')
     is null then
    raise exception 'el ranking quedo con ACL por defecto (EXECUTE a PUBLIC); rollback';
  end if;
  if exists (
    select 1 from pg_catalog.pg_proc p
      join pg_catalog.pg_namespace n on n.oid = p.pronamespace,
      lateral pg_catalog.aclexplode(p.proacl) a
     where n.nspname = 'crm' and p.proname = 'metricas_conversiones_equipo_fn'
       and pg_catalog.pg_get_function_identity_arguments(p.oid) = 'p_desde date, p_hasta date'
       and a.grantee <> p.proowner
       and a.grantee::regrole::text not in ('authenticated')
  ) then
    raise exception 'el ranking gano EXECUTE para un rol inesperado; rollback';
  end if;
end;
$postflight$;
