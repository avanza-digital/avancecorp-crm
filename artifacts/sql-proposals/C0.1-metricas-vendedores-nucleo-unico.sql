-- C0.1 · metricas_vendedores_fn usa el mismo nucleo mensual que
-- HOY / Ranking / Metas, tambien en equipos.
--
-- ARTEFACTO DE PROPUESTA: NO ES UNA MIGRACION.
-- NO EJECUTAR sin aprobacion expresa de Miguel, captura live autorizada y
-- sustitucion de TODOS los placeholders fail-closed __CAPTURAR_*__.
-- No crea tablas, policies, funciones auxiliares ni privilegios nuevos.

begin;

set local lock_timeout = '10s';

do $preflight$
declare
  v_dep record;
  v_oid oid;
  v_actual text;
  v_src text;
  v_owner text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
begin
  -- Todas estas anclas deben capturarse en la base autorizada inmediatamente
  -- antes de aprobar/aplicar. Los hashes del repositorio se documentan en el
  -- README, pero no se presumen iguales a produccion.
  for v_dep in
    select *
    from (values
      (
        'crm.metricas_vendedores_fn()',
        '__CAPTURAR_LIVE_MD5_PROSRC_METRICAS_VENDEDORES__'
      ),
      (
        'crm.conversion_mensual_fn(date)',
        '__CAPTURAR_LIVE_MD5_PROSRC_CONVERSION_MENSUAL_WRAPPER__'
      ),
      (
        'crm.conversion_mensual_sin_cartera_fn(date)',
        '__CAPTURAR_LIVE_MD5_PROSRC_CONVERSION_MENSUAL_BASE__'
      ),
      (
        'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)',
        '__CAPTURAR_LIVE_MD5_PROSRC_CONVERSION_POR_VENDEDOR__'
      ),
      (
        'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
        '__CAPTURAR_LIVE_MD5_PROSRC_CONVERSION_EPISODIOS__'
      ),
      (
        'private.metricas_cartera_por_vendedor(date)',
        '__CAPTURAR_LIVE_MD5_PROSRC_METRICAS_CARTERA_POR_VENDEDOR__'
      ),
      (
        'private.roster_metas_vendedores()',
        '__CAPTURAR_LIVE_MD5_PROSRC_ROSTER_METAS__'
      ),
      (
        'private.peso_referido_conversion(date)',
        '__CAPTURAR_LIVE_MD5_PROSRC_PESO_REFERIDO__'
      ),
      (
        'private.ajuste_pendiente_por_vendedor()',
        '__CAPTURAR_LIVE_MD5_PROSRC_AJUSTE_PENDIENTE__'
      ),
      (
        'private.conversion_con_ajuste(numeric,numeric)',
        '__CAPTURAR_LIVE_MD5_PROSRC_CONVERSION_CON_AJUSTE__'
      ),
      (
        'private.filtrar_desglose_sujetos_crm(jsonb,text,text,text[])',
        '__CAPTURAR_LIVE_MD5_PROSRC_FILTRAR_SUJETOS__'
      )
    ) as d(firma, md5_esperado)
  loop
    if v_dep.md5_esperado like '__CAPTURAR_%' then
      raise exception
        'ABORT C0.1: falta capturar/aprobar el hash vivo de %',
        v_dep.firma;
    end if;

    v_oid := pg_catalog.to_regprocedure(v_dep.firma);
    if v_oid is null then
      raise exception 'ABORT C0.1: falta %', v_dep.firma;
    end if;

    select pg_catalog.md5(p.prosrc)
      into v_actual
    from pg_catalog.pg_proc p
    where p.oid = v_oid;

    if v_actual is distinct from v_dep.md5_esperado then
      raise exception
        'ABORT C0.1: % cambio (% vs %)',
        v_dep.firma, v_actual, v_dep.md5_esperado;
    end if;
  end loop;

  select
    r.rolname,
    p.prosecdef,
    p.provolatile,
    p.proconfig
  into
    v_owner,
    v_secdef,
    v_volatility,
    v_config
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure;

  if v_owner is distinct from 'postgres'
     or not v_secdef
     or v_volatility is distinct from 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception
      'ABORT C0.1: catalogo inesperado en metricas_vendedores_fn (%/%/%/%)',
      v_owner, v_secdef, v_volatility, v_config;
  end if;

  -- ACL viva esperada: owner postgres + authenticated; ningun otro rol.
  if not exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        p.proacl,
        pg_catalog.acldefault('f', p.proowner)
      )
    ) a
    join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and g.rolname = 'authenticated'
      and a.privilege_type = 'EXECUTE'
      and not a.is_grantable
  ) or exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        p.proacl,
        pg_catalog.acldefault('f', p.proowner)
      )
    ) a
    left join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and a.privilege_type = 'EXECUTE'
      and coalesce(g.rolname, 'PUBLIC')
          not in ('postgres', 'authenticated')
  ) then
    raise exception
      'ABORT C0.1: ACL viva de metricas_vendedores_fn no es la allowlist esperada';
  end if;

  -- Vigia de la cadena canonica.
  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid = 'crm.conversion_mensual_fn(date)'::regprocedure;

  if pg_catalog.strpos(
       v_src,
       'crm.conversion_mensual_sin_cartera_fn'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'private.metricas_cartera_por_vendedor'
     ) = 0 then
    raise exception
      'ABORT C0.1: el wrapper mensual ya no encadena base y cartera';
  end if;

  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid =
    'crm.conversion_mensual_sin_cartera_fn(date)'::regprocedure;

  if pg_catalog.strpos(
       v_src,
       'private.conversion_mensual_por_vendedor'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'private.conversion_con_ajuste'
     ) = 0 then
    raise exception
      'ABORT C0.1: la base mensual ya no encadena nucleo y ajuste';
  end if;

  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  where p.oid =
    'private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'::regprocedure;

  if pg_catalog.strpos(v_src, 'private.conversion_episodios') = 0 then
    raise exception
      'ABORT C0.1: el nucleo por vendedor ya no consume conversion_episodios';
  end if;
end
$preflight$;

create or replace function crm.metricas_vendedores_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_mes date;
  v_factor numeric;
  v_mensual jsonb;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();

  if v_uid is null
     or (v_rol is null and not coalesce(v_lector, false)) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_visibles := array(
    select private.vendedor_ids_visibles(v_uid)
  );

  v_global := coalesce(v_rol = 'gerencia', false)
              or coalesce(v_lector, false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;

  v_corte := v_ahora - interval '45 days';
  v_mes := date_trunc(
    'month',
    v_ahora at time zone 'America/Lima'
  )::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- Compatibilidad historica M13e: el coordinador puede llamar esta RPC,
  -- pero su ambito de vendedores/equipos es vacio. No debe llamar al wrapper
  -- mensual, que correctamente lo deniega con 42501.
  if v_rol = 'coordinador' and not coalesce(v_lector, false) then
    return jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'ventana_convertidos_dias', 45,
      'ventana_metrica', 'mes_calendario',
      'mes_metrica', v_mes,
      'peso_referido', v_factor,
      'vendedores', '[]'::jsonb,
      'equipos', '[]'::jsonb
    );
  end if;

  -- La cobertura exacta de abajo es para el mes VIVO y su roster actual. La
  -- regla de cierre impide sellar este periodo; si el estado viola esa regla,
  -- no mezclar una foto historica con el equipo vivo aunque sus UUID coincidan.
  if exists (
    select 1
    from crm.periodos_cerrados pc
    where pc.periodo = v_mes
  ) then
    raise exception
      'El mes operativo actual aparece sellado inesperadamente'
      using errcode = '55000';
  end if;

  -- Un solo contrato para la conversion mostrada. Este payload ya contiene
  -- el ajuste pendiente aplicado por vendedor y la cartera deduplicada.
  v_mensual := crm.conversion_mensual_fn(v_mes);

  -- Fallar cerrado si el contrato canonico deriva. Nunca coalescear una clave
  -- ausente a cero porque convertiria un fallo del servidor en una cifra.
  if pg_catalog.jsonb_typeof(v_mensual) is distinct from 'object'
     or pg_catalog.jsonb_typeof(v_mensual -> 'version')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual -> 'alcance')
        is distinct from 'string'
     or pg_catalog.jsonb_typeof(v_mensual #> '{periodo,mes}')
        is distinct from 'string'
     or pg_catalog.jsonb_typeof(
          v_mensual #> '{ponderacion,referido}'
        ) is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual -> 'responsables')
        is distinct from 'array' then
    raise exception
      'Contrato interno de conversion mensual inesperado'
      using errcode = '55000';
  end if;

  if (v_mensual ->> 'version')::numeric <> 1
     or (v_mensual ->> 'alcance') is distinct from v_alcance
     or v_mensual #>> '{periodo,mes}'
        is distinct from pg_catalog.to_char(v_mes, 'YYYY-MM')
     or (v_mensual #>> '{ponderacion,referido}')::numeric
        is distinct from v_factor then
    raise exception
      'Contrato interno de conversion mensual inconsistente'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    where pg_catalog.jsonb_typeof(e.value) is distinct from 'object'
       or not (
         e.value ?& array[
           'vendedor_id',
           'supervisor_id',
           'divisor',
           'cierres_no_referidos',
           'cierres_referidos',
           'numerador',
           'conversion_pct',
           'cartera'
         ]::text[]
       )
       or pg_catalog.jsonb_typeof(e.value -> 'vendedor_id')
          is distinct from 'string'
       or (e.value ->> 'vendedor_id') !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or pg_catalog.jsonb_typeof(e.value -> 'supervisor_id')
          not in ('string', 'null')
       or (
         pg_catalog.jsonb_typeof(e.value -> 'supervisor_id') = 'string'
         and (e.value ->> 'supervisor_id') !~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )
       or pg_catalog.jsonb_typeof(e.value -> 'divisor')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'cierres_no_referidos')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'cierres_referidos')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'numerador')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
          not in ('number', 'null')
       or pg_catalog.jsonb_typeof(e.value -> 'cartera')
          is distinct from 'object'
       or not (
         (e.value -> 'cartera')
         ? 'conversiones_clientes'
       )
       or pg_catalog.jsonb_typeof(
         e.value #> '{cartera,conversiones_clientes}'
       ) is distinct from 'number'
  ) then
    raise exception
      'Fila interna de conversion mensual incompleta'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    where (e.value ->> 'divisor')::numeric < 0
       or (e.value ->> 'divisor')::numeric
          <> trunc((e.value ->> 'divisor')::numeric)
       or (e.value ->> 'cierres_no_referidos')::numeric < 0
       or (e.value ->> 'cierres_no_referidos')::numeric
          <> trunc((e.value ->> 'cierres_no_referidos')::numeric)
       or (e.value ->> 'cierres_referidos')::numeric < 0
       or (e.value ->> 'cierres_referidos')::numeric
          <> trunc((e.value ->> 'cierres_referidos')::numeric)
       or (e.value #>> '{cartera,conversiones_clientes}')::numeric < 0
       or (e.value #>> '{cartera,conversiones_clientes}')::numeric
          <> trunc(
            (e.value #>> '{cartera,conversiones_clientes}')::numeric
          )
       or (e.value ->> 'numerador')::numeric < 0
       or case
            when (e.value ->> 'divisor')::numeric = 0 then
              pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
                is distinct from 'null'
            else
              pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
                is distinct from 'number'
              or (e.value ->> 'conversion_pct')::numeric
                 is distinct from round(
                   100.0
                   * (e.value ->> 'numerador')::numeric
                   / (e.value ->> 'divisor')::numeric,
                   2
                 )
          end
  ) then
    raise exception
      'Aritmetica interna de conversion mensual inconsistente'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    -- UUID tipado, no texto: variantes de mayusculas/forma no eluden la
    -- unicidad y cualquier identidad invalida falla antes del coalesce.
    group by (e.value ->> 'vendedor_id')::uuid
    having count(*) > 1
  ) then
    raise exception
      'Conversion mensual duplico un responsable'
      using errcode = '55000';
  end if;

  -- Cobertura exacta ANTES de cualquier coalesce. Para el mes actual el
  -- wrapper abierto fabrica una fila incluso cuando el vendedor no produjo:
  -- exactamente una por cada vendedor del roster canonico visible. El mes en
  -- curso no puede estar sellado (cerrar_periodo exige p_periodo < mes actual),
  -- por lo que aqui no existe una excepcion historica legitima.
  --
  -- No se compara contra `roster` de esta RPC: ese roster tambien contiene
  -- supervisor/gerencia, inactivos visibles y vendedores fuera de roster. El
  -- contrato mensual representa solo vendedores activos con supervisor activo;
  -- la produccion fuera de roster queda unicamente en el agregado de cobertura.
  if exists (
    with esperados as materialized (
      select r.vendedor_id, r.supervisor_id
      from private.roster_metas_vendedores() r
      where v_global
         or r.vendedor_id = any(v_visibles)
    ),
    recibidos as materialized (
      select
        (e.value ->> 'vendedor_id')::uuid as vendedor_id,
        nullif(e.value ->> 'supervisor_id', '')::uuid
          as supervisor_id
      from pg_catalog.jsonb_array_elements(
        v_mensual -> 'responsables'
      ) as e(value)
    )
    select 1
    from esperados x
    full join recibidos r using (vendedor_id)
    where x.vendedor_id is null       -- fila extra / rol no vendedor / fuera
       or r.vendedor_id is null       -- vendedor canonico visible faltante
       or r.supervisor_id is distinct from x.supervisor_id
                                      -- equipo inesperado o contaminado
  ) then
    raise exception
      'Cobertura interna de conversion mensual no coincide con el roster visible'
      using errcode = '55000';
  end if;

  with roster as materialized (
    select e.perfil_id, e.rol_crm, e.activo
    from crm.equipo e
    where e.rol_crm in ('vendedor', 'supervisor', 'gerencia')
      and (
        e.perfil_id = any(v_visibles)
        or v_global
      )
  ),
  ambito as materialized (
    select
      l.id,
      l.moneda,
      coalesce(l.monto_estimado, 0) as monto,
      l.vendedor_id,
      l.asignado_supervisor_id,
      l.creado_en,
      (l.etapa not in ('convertido', 'descartado')) as abierto
    from crm.leads l
    where l.activo is true
      and (
        l.etapa <> 'convertido'
        or l.convertido_en >= v_corte
      )
      and (
        l.vendedor_id = any(v_visibles)
        or (
          l.vendedor_id is null
          and l.asignado_supervisor_id = any(v_visibles)
        )
        or v_global
      )
  ),
  nucleo_mes as materialized (
    select
      (e.value ->> 'vendedor_id')::uuid as analista_id,
      nullif(e.value ->> 'supervisor_id', '')::uuid
        as supervisor_id,
      (e.value ->> 'divisor')::int as divisor,
      (e.value ->> 'cierres_no_referidos')::int
        as cierres_no_referidos,
      (e.value ->> 'cierres_referidos')::int
        as cierres_referidos,
      (e.value ->> 'numerador')::numeric as numerador,
      case
        when pg_catalog.jsonb_typeof(
          e.value -> 'conversion_pct'
        ) = 'number'
        then (e.value ->> 'conversion_pct')::numeric
      end as conversion_pct,
      (e.value #>> '{cartera,conversiones_clientes}')::int
        as operaciones_cartera
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
  ),
  por_vendedor as (
    select
      r.perfil_id,
      r.rol_crm,
      r.activo,
      count(a.id) filter (where a.abierto)::int as activos,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda is distinct from 'USD'
        ),
        0
      ) as capital_pen,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda = 'USD'
        ),
        0
      ) as capital_usd,
      (
        coalesce(nm.cierres_no_referidos, 0)
        + coalesce(nm.cierres_referidos, 0)
      )::int as convertidos,
      coalesce(nm.operaciones_cartera, 0)::int
        as operaciones_cartera,
      coalesce(nm.divisor, 0)::int as nucleo_divisor,
      coalesce(nm.numerador, 0::numeric) as nucleo_numerador,
      nm.conversion_pct as nucleo_conversion_pct
    from roster r
    left join ambito a
      on a.vendedor_id = r.perfil_id
    left join nucleo_mes nm
      on nm.analista_id = r.perfil_id
    group by
      r.perfil_id,
      r.rol_crm,
      r.activo,
      nm.cierres_no_referidos,
      nm.cierres_referidos,
      nm.operaciones_cartera,
      nm.divisor,
      nm.numerador,
      nm.conversion_pct
  ),
  senales as (
    select
      r.perfil_id,
      count(*) filter (where uc.lead_id is null)::int
        as sin_tocar,
      coalesce(
        max(
          extract(
            epoch from (
              v_ahora
              - coalesce(ua.ultima, a.creado_en)
            )
          ) / 86400.0
        ),
        0
      ) as dias_max
    from roster r
    join ambito a
      on a.vendedor_id = r.perfil_id
     and a.abierto
    left join lateral (
      select act.lead_id
      from crm.actividades act
      where act.lead_id = a.id
        and act.tipo in (
          'llamada_realizada',
          'llamada_no_contestada',
          'whatsapp_enviado',
          'whatsapp_recibido',
          'reunion_realizada'
        )
      limit 1
    ) uc on true
    left join lateral (
      select max(act.creado_en) as ultima
      from crm.actividades act
      where act.lead_id = a.id
    ) ua on true
    group by r.perfil_id
  ),
  agg_duenio as (
    select
      a.vendedor_id,
      count(*) filter (where a.abierto)::int as activos,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda is distinct from 'USD'
        ),
        0
      ) as capital_pen,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda = 'USD'
        ),
        0
      ) as capital_usd
    from ambito a
    where a.vendedor_id is not null
    group by a.vendedor_id
  ),
  parkeados_bandeja as (
    select
      a.asignado_supervisor_id as supervisor_id,
      count(*)::int as n
    from ambito a
    where a.abierto
      and a.vendedor_id is null
      and a.asignado_supervisor_id is not null
    group by a.asignado_supervisor_id
  ),
  nucleo_equipos as (
    select
      nm.supervisor_id,
      sum(
        nm.cierres_no_referidos
        + nm.cierres_referidos
      )::int as convertidos,
      sum(nm.operaciones_cartera)::int
        as operaciones_cartera,
      sum(nm.divisor)::int as nucleo_divisor,
      sum(nm.numerador)::numeric as nucleo_numerador
    from nucleo_mes nm
    where nm.supervisor_id is not null
    group by nm.supervisor_id
  ),
  equipos_calc as (
    select
      s.perfil_id as supervisor_id,
      directos.n as vendedores,
      stats.activos,
      stats.capital_pen,
      stats.capital_usd,
      coalesce(ne.convertidos, 0)::int as convertidos,
      coalesce(ne.operaciones_cartera, 0)::int
        as operaciones_cartera,
      coalesce(ne.nucleo_divisor, 0)::int
        as nucleo_divisor,
      coalesce(ne.nucleo_numerador, 0::numeric)
        as nucleo_numerador,
      case
        when coalesce(ne.nucleo_divisor, 0) > 0
        then round(
          100.0
          * coalesce(ne.nucleo_numerador, 0::numeric)
          / ne.nucleo_divisor,
          2
        )
      end as nucleo_conversion_pct,
      coalesce(pb.n, 0)::int as parkeados
    from roster s
    cross join lateral (
      select count(*)::int as n
      from crm.equipo m
      where m.supervisor_id = s.perfil_id
        and m.activo is true
    ) directos
    cross join lateral (
      select
        coalesce(sum(ad.activos), 0)::int as activos,
        coalesce(sum(ad.capital_pen), 0) as capital_pen,
        coalesce(sum(ad.capital_usd), 0) as capital_usd
      from agg_duenio ad
      where ad.vendedor_id = s.perfil_id
         or ad.vendedor_id in (
           select m.perfil_id
           from crm.equipo m
           where m.supervisor_id = s.perfil_id
             and m.activo is true
         )
    ) stats
    left join nucleo_equipos ne
      on ne.supervisor_id = s.perfil_id
    left join parkeados_bandeja pb
      on pb.supervisor_id = s.perfil_id
    where s.rol_crm = 'supervisor'
      and s.activo is true
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'ventana_convertidos_dias', 45,
    'ventana_metrica', 'mes_calendario',
    'mes_metrica', v_mes,
    'peso_referido', v_factor,
    'vendedores', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', pv.perfil_id,
            'rol_crm', pv.rol_crm,
            'activo', pv.activo,
            'activos', pv.activos,
            'capital_pen', pv.capital_pen,
            'capital_usd', pv.capital_usd,
            'convertidos', pv.convertidos,
            'operaciones_cartera', pv.operaciones_cartera,
            'conversion_pct',
              case
                when pv.nucleo_divisor > 0
                then round(
                  100.0
                  * pv.nucleo_numerador
                  / pv.nucleo_divisor
                )::int
                else 0
              end,
            'nucleo_divisor', pv.nucleo_divisor,
            'nucleo_numerador', pv.nucleo_numerador,
            'nucleo_conversion_pct',
              pv.nucleo_conversion_pct,
            'sin_tocar', coalesce(sn.sin_tocar, 0),
            'dias_sin_actividad_max',
              round(coalesce(sn.dias_max, 0), 4)
          )
          order by
            pv.capital_pen desc,
            pv.perfil_id
        )
        from por_vendedor pv
        left join senales sn
          on sn.perfil_id = pv.perfil_id
      ),
      '[]'::jsonb
    ),
    'equipos', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'supervisor_id', ec.supervisor_id,
            'vendedores', ec.vendedores,
            'activos', ec.activos,
            'capital_pen', ec.capital_pen,
            'capital_usd', ec.capital_usd,
            'convertidos', ec.convertidos,
            'operaciones_cartera',
              ec.operaciones_cartera,
            'conversion_pct',
              case
                when ec.nucleo_divisor > 0
                then round(
                  100.0
                  * ec.nucleo_numerador
                  / ec.nucleo_divisor
                )::int
                else 0
              end,
            'nucleo_divisor', ec.nucleo_divisor,
            'nucleo_numerador', ec.nucleo_numerador,
            'nucleo_conversion_pct',
              ec.nucleo_conversion_pct,
            'parkeados', ec.parkeados
          )
          order by
            ec.capital_pen desc,
            ec.supervisor_id
        )
        from equipos_calc ec
      ),
      '[]'::jsonb
    )
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.metricas_vendedores_fn() is
  'Vista operativa de 45 dias para activos, capital y senales; conversion del mes calendario tomada del contrato canonico crm.conversion_mensual_fn. Por vendedor y equipo expone divisor, numerador neto, porcentaje exacto nullable y operaciones de cartera. Los equipos suman numeradores/divisores por supervisor_id y nunca promedian porcentajes. convertidos cuenta cierres de lead; operaciones_cartera viaja aparte. Coordinador conserva vendedores/equipos vacios.';

revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;

grant execute on function crm.metricas_vendedores_fn()
  to authenticated;

do $postflight$
declare
  v_src text;
  v_md5_actual text;
  v_md5_esperado text :=
    '__CAPTURAR_MD5_PROSRC_DEL_CUERPO_C0_1_APROBADO__';
  v_owner text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
  v_actor uuid;
  v_coord uuid;
  v_payload jsonb;
begin
  if v_md5_esperado like '__CAPTURAR_%' then
    raise exception
      'POSTFLIGHT C0.1: falta fijar el hash del cuerpo aprobado';
  end if;

  select
    p.prosrc,
    pg_catalog.md5(p.prosrc),
    r.rolname,
    p.prosecdef,
    p.provolatile,
    p.proconfig
  into
    v_src,
    v_md5_actual,
    v_owner,
    v_secdef,
    v_volatility,
    v_config
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure;

  if v_md5_actual is distinct from v_md5_esperado then
    raise exception
      'POSTFLIGHT C0.1: cuerpo inesperado (% vs %)',
      v_md5_actual, v_md5_esperado;
  end if;

  if v_owner is distinct from 'postgres'
     or not v_secdef
     or v_volatility is distinct from 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception
      'POSTFLIGHT C0.1: owner/secdef/stable/search_path inesperados';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        p.proacl,
        pg_catalog.acldefault('f', p.proowner)
      )
    ) a
    join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and g.rolname = 'authenticated'
      and a.privilege_type = 'EXECUTE'
      and not a.is_grantable
  ) or exists (
    select 1
    from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(
      coalesce(
        p.proacl,
        pg_catalog.acldefault('f', p.proowner)
      )
    ) a
    left join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and a.privilege_type = 'EXECUTE'
      and coalesce(g.rolname, 'PUBLIC')
          not in ('postgres', 'authenticated')
  ) then
    raise exception
      'POSTFLIGHT C0.1: ACL fuera de allowlist';
  end if;

  if pg_catalog.strpos(
       v_src,
       'v_mensual := crm.conversion_mensual_fn(v_mes)'
     ) = 0
     or pg_catalog.strpos(v_src, 'nucleo_equipos') = 0
     or pg_catalog.strpos(v_src, '''nucleo_divisor''') = 0
     or pg_catalog.strpos(v_src, '''nucleo_numerador''') = 0
     or pg_catalog.strpos(
       v_src,
       '''nucleo_conversion_pct'''
     ) = 0
     or pg_catalog.strpos(
       v_src,
       '''operaciones_cartera'''
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'private.roster_metas_vendedores()'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'full join recibidos r using (vendedor_id)'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'r.supervisor_id is distinct from x.supervisor_id'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'from crm.periodos_cerrados pc'
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'v_corte := v_ahora - interval ''45 days'''
     ) = 0
     or pg_catalog.strpos(
       v_src,
       'l.convertido_en >= v_corte'
     ) = 0 then
    raise exception
      'POSTFLIGHT C0.1: falta la cadena, el contrato o la cobertura exacta';
  end if;

  if pg_catalog.strpos(
       v_src,
       'private.conversion_episodios'
     ) > 0
     or pg_catalog.strpos(v_src, 'asignados_total') > 0
     or pg_catalog.strpos(
       v_src,
       '100.0 * ec.convertidos / ec.asignados_total'
     ) > 0
     or pg_catalog.strpos(
       v_src,
       'count(*) filter (where a.etapa = ''convertido'')'
     ) > 0 then
    raise exception
      'POSTFLIGHT C0.1: reaparecio una formula paralela';
  end if;

  if pg_catalog.strpos(
       v_src,
       'v_rol = ''coordinador'''
     ) = 0 then
    raise exception
      'POSTFLIGHT C0.1: se perdio la semantica vacia del coordinador';
  end if;

  -- Ejecucion real del cuerpo cuando el entorno tiene un actor operativo.
  -- Esto detecta errores tardios de PL/pgSQL que CREATE OR REPLACE no compila.
  select e.perfil_id
    into v_actor
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.activo
    and p.activo
    and e.rol_crm in (
      'gerencia',
      'supervisor',
      'vendedor',
      'directorio'
    )
    and (
      p.rol is distinct from 'superadmin'
      or e.rol_crm = 'gerencia'
    )
  order by case e.rol_crm
    when 'gerencia' then 1
    when 'directorio' then 2
    when 'supervisor' then 3
    else 4
  end,
  e.perfil_id
  limit 1;

  if v_actor is not null then
    perform pg_catalog.set_config(
      'request.jwt.claim.sub',
      v_actor::text,
      true
    );

    v_payload := crm.metricas_vendedores_fn();

    if pg_catalog.jsonb_typeof(v_payload) is distinct from 'object'
       or pg_catalog.jsonb_typeof(v_payload -> 'vendedores')
          is distinct from 'array'
       or pg_catalog.jsonb_typeof(v_payload -> 'equipos')
          is distinct from 'array' then
      raise exception
        'POSTFLIGHT C0.1: ejecucion devolvio forma invalida';
    end if;

    if exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        v_payload -> 'equipos'
      ) as e(value)
      where not (
        e.value ?& array[
          'supervisor_id',
          'convertidos',
          'operaciones_cartera',
          'conversion_pct',
          'nucleo_divisor',
          'nucleo_numerador',
          'nucleo_conversion_pct'
        ]::text[]
      )
    ) then
      raise exception
        'POSTFLIGHT C0.1: fila real de equipo incompleta';
    end if;
  else
    raise notice
      'POSTFLIGHT C0.1: sin actor operativo; ejecucion se cubre en banco transaccional';
  end if;

  -- Si existe coordinador, confirmar el contrato historico de arrays vacios.
  select e.perfil_id
    into v_coord
  from crm.equipo e
  join public.perfiles p on p.id = e.perfil_id
  where e.activo
    and p.activo
    and e.rol_crm = 'coordinador'
    and p.rol is distinct from 'superadmin'
  order by e.perfil_id
  limit 1;

  if v_coord is not null then
    perform pg_catalog.set_config(
      'request.jwt.claim.sub',
      v_coord::text,
      true
    );

    v_payload := crm.metricas_vendedores_fn();

    if pg_catalog.jsonb_array_length(
         v_payload -> 'vendedores'
       ) <> 0
       or pg_catalog.jsonb_array_length(
         v_payload -> 'equipos'
       ) <> 0 then
      raise exception
        'POSTFLIGHT C0.1: coordinador dejo de recibir arrays vacios';
    end if;
  end if;
end
$postflight$;

commit;
