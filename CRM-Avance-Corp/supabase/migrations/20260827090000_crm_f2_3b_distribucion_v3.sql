-- F2.3b del plan «Conversion unica en todo el CRM»: Distribucion SIRVE sus
-- porcentajes ya calculados, en una RPC **v3 que el bundle vivo jamas llama**.
--
-- POR QUE UNA VERSION NUEVA Y NO CLAVES EN LA VIEJA:
-- el bundle VIVO (`b3f6e98`) valida la respuesta de esta pantalla a CIERRE
-- HERMETICO — `v.strictObject` en TODOS los niveles (22 apariciones en
-- `app/src/lib/metricas-distribucion.ts`). Con `strictObject` una clave NUEVA
-- rompe la pantalla igual que renombrar una, y el front esta BLOQUEADO hasta
-- integrar las dos ramas, asi que no se podria arreglar publicando. Por eso
-- F2.3 fue en dos tiempos: 2.3a cambio el VALOR sin tocar la forma; esto es
-- 2.3b y añade la forma nueva **en otra puerta**. El bundle viejo sigue
-- llamando a `crm.metricas_distribucion_leads_v2_fn` y recibe exactamente lo
-- de siempre; nadie llama a v3 hasta que el front nuevo exista (F3).
--
-- QUE APORTA (lo que hoy divide el NAVEGADOR y pasa al servidor):
--   · `distribucion-lecturas.ts:206` `conversionLegible`  → analista, PEN y USD
--   · `distribucion-leads-gerencia.tsx:344-345`           → resumen PEN y USD
--       (incluida la suma de USD que hoy se hace en el cliente)
--   · `distribucion-leads-gerencia.tsx:1120`              → cada rango
--   · `distribucion-leads-gerencia.tsx:1257`              → la tabla completa
--   · `distribucion-lecturas.ts:254` `pctNumerico`        → el ORDEN «cierres»
-- Y ademas la cifra del NUCLEO (la misma que HOY, Metas, Conversiones y el
-- Ranking) para que esta pantalla deje de contradecir a Rendimiento (H8/H18),
-- mas el bloque `sondas` que F3 necesita para poder ocultar un numero en vez
-- de fabricar un cero.
--
-- DOS LECTURAS, CADA UNA CON SU NOMBRE (decision D3 de Miguel: se conservan
-- las dos, ya no compiten a escondidas):
--   · `punteria`  = cerrados ÷ resueltos  → «de lo que termino de trabajar,
--     gano el X %». Es EXACTAMENTE lo que la pantalla pinta hoy: se calcula
--     con las mismas cifras del payload, solo que en el servidor. El numero
--     NO cambia; cambia quien lo divide.
--   · `nucleo_*`  = la aritmetica del nucleo (referidos al 15 % y FUERA del
--     divisor, arrastre, operaciones de cartera, anulados excluidos). Es el
--     numero que ya sirven las otras cinco pantallas tras F2.
--
-- ESTA MIGRACION NO CAMBIA NI UN NUMERO DE LO QUE EL EQUIPO VE HOY: solo
-- abre una puerta nueva. El unico objeto vivo que se toca es el despachador
-- `private.metricas_distribucion_leads_autorizada`, y de forma ADITIVA (una
-- rama `elsif p_version=3`); el postflight comprueba que las ramas 1 y 2
-- siguen enrutando a los mismos motores.

-- ---------------------------------------------------------------------------
-- 0. Preflight: lo vivo es lo esperado y quien va a ejecutar puede hacerlo
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_owner_autorizada name;
  v_fn record;
begin
  -- 0.1 Anclas de texto vivo. Si algo cambio bajo los pies, esta migracion se
  --     construyo sobre una foto vieja y NO debe aplicarse.
  for v_fn in
    select * from (values
      ('private', 'metricas_distribucion_leads_core',
       'p_desde date, p_hasta date, p_ahora timestamp with time zone',
       'f8748197c550484ae59b6257397a5013'),
      ('private', 'metricas_distribucion_leads_v2_core',
       'p_desde date, p_hasta date, p_ahora timestamp with time zone',
       '7408cb964af34dfb091108c5a7062cc4'),
      ('private', 'metricas_distribucion_leads_autorizada',
       'p_desde date, p_hasta date, p_version smallint',
       'a45b00eb7beca4cf80dea2c138d65848'),
      ('private', 'sanitizar_sujetos_distribucion_crm',
       'p_payload jsonb',
       '3bb8707046c61864c2b028b47231c544'),
      ('private', 'conversion_episodios',
       'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric',
       '9195e57220155384e16281bbbc91de32'),
      ('private', 'conversion_mensual_por_vendedor',
       'p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[], p_factor numeric',
       '7d2940a0f3368bacf3a5e719c76bfff5'),
      ('crm', 'metricas_distribucion_leads_v2_fn',
       'p_desde date, p_hasta date',
       '4f9186ab5d73f9f4e9114f271aa78a15')
    ) as t(esquema, nombre, args, md5_esperado)
  loop
    if (select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
          from pg_catalog.pg_proc p
          join pg_catalog.pg_namespace n on n.oid = p.pronamespace
         where n.nspname = v_fn.esquema
           and p.proname = v_fn.nombre
           and pg_catalog.pg_get_function_identity_arguments(p.oid) = v_fn.args)
       is distinct from v_fn.md5_esperado then
      raise exception '%.% viva NO es la esperada; re-capturar antes de F2.3b',
        v_fn.esquema, v_fn.nombre;
    end if;
  end loop;

  -- 0.2 La puerta nueva no puede existir ya (si existe, alguien la creo a
  --     mano y este fichero la pisaria sin saber que habia dentro).
  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn'
  ) then
    raise exception 'crm.metricas_distribucion_leads_v3_fn ya existe; revisar antes de F2.3b';
  end if;

  -- 0.3 QUIEN EJECUTA DE VERDAD el motor (mapeado, no supuesto — en F2.3a la
  --     primera version de este candado miraba el eslabon equivocado y aborto
  --     la migracion, que es justo para lo que esta):
  --       crm.metricas_distribucion_leads_v*_fn  DEFINER, owner crm_metricas_bridge
  --         └─ private.metricas_distribucion_leads_autorizada  DEFINER, owner postgres
  --              └─ private.metricas_distribucion_leads_*_core  NO definer
  --     El motor corre con la identidad del DEFINER mas interno: el owner de
  --     `..._autorizada`. Es ESE rol el que tiene que poder ejecutar todo lo
  --     que el motor v3 llama.
  if not (select p.prosecdef
            from pg_catalog.pg_proc p
            join pg_catalog.pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'private'
             and p.proname = 'metricas_distribucion_leads_autorizada') then
    raise exception 'metricas_distribucion_leads_autorizada dejo de ser DEFINER: cambio quien ejecuta el motor';
  end if;

  select pg_catalog.pg_get_userbyid(p.proowner) into v_owner_autorizada
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private'
     and p.proname = 'metricas_distribucion_leads_autorizada';

  -- NUNCA `select fn()` para comprobar permisos: llamar sin EXECUTE
  -- segfaultea el backend en la imagen Supabase 17.6.1.105.
  for v_fn in
    select * from (values
      ('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'),
      ('private.conversion_mensual_por_vendedor(timestamptz,timestamptz,boolean,uuid[],numeric)'),
      ('private.peso_referido_conversion(date)'),
      ('private.metricas_distribucion_leads_v2_core(date,date,timestamptz)')
    ) as t(firma)
  loop
    if not pg_catalog.has_function_privilege(v_owner_autorizada, v_fn.firma, 'EXECUTE') then
      raise exception 'el rol % no puede ejecutar %: el motor v3 fallaria en caliente',
        v_owner_autorizada, v_fn.firma;
    end if;
  end loop;

  if not exists (select 1 from pg_catalog.pg_roles where rolname = 'crm_metricas_bridge') then
    raise exception 'falta el rol crm_metricas_bridge; la puerta v3 no tendria dueño';
  end if;

  -- (auditor RLS, objecion 8) La puerta nueva HEREDA todo lo que el puente
  -- tenga: se exige que siga siendo el rol pelado que se acuño en julio.
  if exists (
    select 1 from pg_catalog.pg_roles r
    where r.rolname = 'crm_metricas_bridge'
      and (r.rolsuper or r.rolcreatedb or r.rolcreaterole
           or r.rolreplication or r.rolbypassrls or r.rolcanlogin)
  ) then
    raise exception 'crm_metricas_bridge dejo de ser un rol pelado; revisar antes de darle otra funcion';
  end if;
  if exists (
    select 1 from pg_catalog.pg_auth_members m
    where m.roleid = (select oid from pg_catalog.pg_roles where rolname='crm_metricas_bridge')
      and pg_catalog.pg_get_userbyid(m.member) <> 'postgres'
  ) then
    raise exception 'crm_metricas_bridge tiene miembros inesperados; revisar antes de F2.3b';
  end if;

  -- La puerta v3 (DEFINER, owner crm_metricas_bridge) llama al despachador:
  -- sin este grant fallaria en caliente igual que fallaria la v2.
  if not pg_catalog.has_function_privilege(
    'crm_metricas_bridge',
    'private.metricas_distribucion_leads_autorizada(date,date,smallint)',
    'EXECUTE'
  ) then
    raise exception 'crm_metricas_bridge no puede ejecutar el despachador; la puerta v3 naceria muerta';
  end if;
  -- EXECUTE no basta: sin USAGE sobre el esquema, la llamada muere antes de
  -- mirar la funcion (lo cazo el banco local, no una suposicion).
  if not pg_catalog.has_schema_privilege('crm_metricas_bridge', 'private', 'USAGE') then
    raise exception 'crm_metricas_bridge no tiene USAGE sobre private; la puerta v3 naceria muerta';
  end if;

  -- (Codex d4) La danza del cambio de dueño necesita que el ejecutor pueda
  -- concederse SET sobre el puente: superusuario, SET ya concedido, o ADMIN
  -- sobre el rol. Si no, mejor abortar aqui que reventar a mitad de fichero.
  if not (
    coalesce((select r.rolsuper from pg_catalog.pg_roles r where r.rolname = current_user), false)
    or pg_catalog.pg_has_role(current_user, 'crm_metricas_bridge', 'SET')
    or exists (
      select 1 from pg_catalog.pg_auth_members m
      where m.roleid = (select oid from pg_catalog.pg_roles where rolname = 'crm_metricas_bridge')
        and m.member = (select oid from pg_catalog.pg_roles where rolname = current_user)
        and m.admin_option
    )
  ) then
    raise exception 'el ejecutor no puede asumir crm_metricas_bridge (ni SET ni ADMIN): el cambio de dueño fallaria';
  end if;
end $preflight$;

-- ---------------------------------------------------------------------------
-- 1. La division, en UN solo sitio
-- ---------------------------------------------------------------------------
-- Se sirve `pct` con SEIS decimales a proposito, no con dos: el front formatea
-- a un decimal con Intl (`porcentajeLegible`), y redondear dos veces (2 y
-- luego 1) puede dar un numero distinto del que la pantalla enseña hoy
-- (12,449 → 12,45 → «12,5 %» en vez de «12,4 %»). Con seis decimales el
-- formateo del front da el MISMO caracter que hoy. La cifra del nucleo si va
-- a dos decimales, como en las otras cinco pantallas.
create or replace function private.conversion_punteria(
  p_convertidos integer,
  p_descartados integer
) returns jsonb
language sql
immutable
set search_path = ''
as $fn$
  select jsonb_build_object(
    'convertidos', coalesce(p_convertidos, 0),
    'resueltos', coalesce(p_convertidos, 0) + coalesce(p_descartados, 0),
    -- null (no cero) cuando no hay nada resuelto: «todavia no se sabe» y
    -- «cerro el 0 %» son cosas distintas, y el front las pinta distinto.
    'pct', case when coalesce(p_convertidos, 0) + coalesce(p_descartados, 0) > 0
      then round(
        100.0 * coalesce(p_convertidos, 0)
        / (coalesce(p_convertidos, 0) + coalesce(p_descartados, 0)), 6)
    end
  )
$fn$;

-- (auditor RLS, objecion 1) Una funcion nueva nace con EXECUTE a PUBLIC, y
-- `authenticated` tiene USAGE sobre `private`: se cierra aqui mismo, como
-- hizo F1 con la tabla-base. Llamar sin EXECUTE tumba el backend en esta
-- imagen, asi que esto tambien es un candado de disponibilidad.
revoke all on function private.conversion_punteria(integer, integer)
  from public, anon, authenticated, service_role;

comment on function private.conversion_punteria(integer, integer) is
  'Lectura de punteria (cerrados / resueltos) servida por el servidor, decision D3. Devuelve null en `pct` cuando no hay resueltos: «aun no se sabe» no es «0 %». Seis decimales para que el formateo a un decimal del front coincida con lo que pintaba dividiendo el mismo.';

-- ---------------------------------------------------------------------------
-- 2. El motor v3: v2 + los porcentajes servidos + el nucleo + sondas
-- ---------------------------------------------------------------------------
create or replace function private.metricas_distribucion_leads_v3_core(
  p_desde date,
  p_hasta date,
  p_ahora timestamp with time zone
) returns jsonb
language plpgsql
stable
set search_path = ''
as $fn$
declare
  v_base jsonb;
  v_hoy date := (p_ahora at time zone 'America/Lima')::date;
  v_ini timestamptz := p_desde::timestamp at time zone 'America/Lima';
  v_fin timestamptz := (p_hasta + 1)::timestamp at time zone 'America/Lima';
  v_mes date := date_trunc('month', p_hasta)::date;
  v_factor numeric;
  v_periodo date;
  v_nucleo jsonb;
  v_div_total integer;
  v_num_total numeric;
  v_ref_total integer;
  v_div_sin_analista integer;
  v_num_sin_analista numeric;
  v_anulados integer;
  v_sin_origen integer;
  v_paridad numeric;
  v_paridad_filas integer;
  v_analistas jsonb;
  v_usd_conv integer;
  v_usd_desc integer;
  v_sin_ficha integer;
begin
  v_base := private.metricas_distribucion_leads_v2_core(p_desde, p_hasta, p_ahora);
  v_factor := private.peso_referido_conversion(v_mes);

  -- (auditor RLS, objecion 10) Si el motor v2 renombrara las claves de las
  -- que esta funcion LEE, el coalesce de la punteria fabricaria ceros en
  -- silencio — exactamente lo que este plan vino a matar. Falla ruidosa.
  if exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento)
    where (fila.elemento#>'{pen,cohorte}' ? 'convertidos') is distinct from true
       or (fila.elemento#>'{pen,cohorte}' ? 'descartados') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'convertidos') is distinct from true
       or (fila.elemento->'usd_no_segmentado' ? 'descartados') is distinct from true
  ) or exists (
    select 1 from jsonb_array_elements(v_base->'analistas') fila(elemento),
                  jsonb_array_elements(fila.elemento#>'{pen,rangos}') rango(elemento)
    where (rango.elemento->'cohorte' ? 'convertidos') is distinct from true
       or (rango.elemento->'cohorte' ? 'descartados') is distinct from true
  ) or (v_base->'resumen' ? 'convertidos_pen') is distinct from true
    or (v_base->'resumen' ? 'descartados_pen') is distinct from true then
    raise exception 'Contrato interno v2 inesperado: faltan las claves de conversion'
      using errcode = '55000';
  end if;

  -- La pierna de cartera solo con el mes ENTERO o todo lo que va del mes en
  -- curso: la tabla-base filtra cartera por MES, no por la ventana, asi que un
  -- recorte del mes sumaria operaciones fuera del rango. Misma regla que F2.1
  -- y F2.2 — si cambia, cambia en las tres.
  v_periodo := case
    when p_desde = date_trunc('month', p_desde)::date
     and date_trunc('month', p_hasta)::date = date_trunc('month', p_desde)::date
     and (p_hasta = (date_trunc('month', p_desde) + interval '1 month' - interval '1 day')::date
          or p_hasta = v_hoy)
    then p_desde
  end;

  -- Esta pantalla solo la ve gerencia o un lector global (el gate vive en
  -- `..._autorizada`, aguas arriba), asi que la tabla-base va SIEMPRE global.
  with ep as materialized (
    select e.* from private.conversion_episodios(
      v_ini, v_fin, v_periodo, true, '{}'::uuid[], v_factor
    ) e
  ),
  nv as (
    select e.analista_id,
      count(*) filter (where e.tipo = 'recibido' and not e.fue_referido)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones
    from ep e
    group by e.analista_id
  ),
  agg as (
    select
      coalesce(jsonb_object_agg(
        nv.analista_id::text,
        jsonb_build_object(
          'nucleo_divisor', nv.divisor,
          'nucleo_referidos_recibidos', nv.referidos_recibidos,
          'nucleo_numerador',
            (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric,
          'nucleo_conversion_pct', case when nv.divisor > 0
            then round(100.0 * (nv.cierres_no_referidos + v_factor * nv.cierres_referidos
                                + nv.operaciones) / nv.divisor, 2) end
        )
      ) filter (where nv.analista_id is not null), '{}'::jsonb) as mapa,
      coalesce(sum(nv.divisor) filter (where nv.analista_id is not null), 0)::int as div_total,
      coalesce(sum(
        (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric
      ) filter (where nv.analista_id is not null), 0) as num_total,
      coalesce(sum(nv.referidos_recibidos) filter (where nv.analista_id is not null), 0)::int as ref_total,
      coalesce(sum(nv.divisor) filter (where nv.analista_id is null), 0)::int as div_sin,
      coalesce(sum(
        (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric
      ) filter (where nv.analista_id is null), 0) as num_sin
    from nv
  ),
  extras as (
    select
      count(*) filter (where e.tipo = 'cierre' and e.anulado)::int as anulados,
      count(*) filter (where e.tipo = 'recibido' and e.origen is null)::int as sin_origen
    from ep e
  ),
  -- Sonda de paridad contra el nucleo REAL (el que sirve HOY/Metas). Solo se
  -- calcula cuando va a valer algo: con `v_periodo` NULL el resultado se
  -- descarta y esta pierna es la mas cara.
  comparacion as (
    select
      abs(coalesce(nv.divisor, 0) - coalesce(cm.divisor, 0))
      + abs(coalesce(nv.cierres_no_referidos, 0) - coalesce(cm.cierres_no_referidos, 0))
      + abs(coalesce(nv.cierres_referidos, 0) - coalesce(cm.cierres_referidos, 0))
      + abs(coalesce(
          (nv.cierres_no_referidos + v_factor * nv.cierres_referidos + nv.operaciones)::numeric, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nv
    -- `=` y no `is not distinct from`: PG no admite este ultimo en un FULL
    -- JOIN (no es hash/merge-joinable). Es seguro porque ninguna de las dos
    -- relaciones puede traer `analista_id` NULL en el lado que importa; si eso
    -- cambiara, la sonda gritaria (paridad <> 0) en vez de callarse.
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm on cm.analista_id = nv.analista_id
    where v_periodo is not null
  ),
  sonda as (
    select
      case when v_periodo is null then null else coalesce(sum(c.delta), 0) end as desvio,
      count(*)::int as filas
    from comparacion c
  )
  select agg.mapa, agg.div_total, agg.num_total, agg.ref_total, agg.div_sin, agg.num_sin,
         extras.anulados, extras.sin_origen, sonda.desvio, sonda.filas
    into v_nucleo, v_div_total, v_num_total, v_ref_total, v_div_sin_analista, v_num_sin_analista,
         v_anulados, v_sin_origen, v_paridad, v_paridad_filas
    from agg cross join extras cross join sonda;

  -- ── Por analista: punteria PEN/USD, sus rangos, y su cifra del nucleo ─────
  select coalesce(jsonb_agg(
    jsonb_set(
      fila.elemento || jsonb_build_object(
        'conversion',
        jsonb_build_object(
          'pen', private.conversion_punteria(
            (fila.elemento#>>'{pen,cohorte,convertidos}')::int,
            (fila.elemento#>>'{pen,cohorte,descartados}')::int),
          'usd', private.conversion_punteria(
            (fila.elemento#>>'{usd_no_segmentado,convertidos}')::int,
            (fila.elemento#>>'{usd_no_segmentado,descartados}')::int)
        )
        || coalesce(v_nucleo->(fila.elemento->>'analista_id'), jsonb_build_object(
             'nucleo_divisor', 0,
             'nucleo_referidos_recibidos', 0,
             'nucleo_numerador', 0::numeric,
             'nucleo_conversion_pct', null
           ))
      ),
      '{pen,rangos}',
      rr.rangos,
      false
    ) order by fila.orden
  ), '[]'::jsonb)
  into v_analistas
  from jsonb_array_elements(v_base->'analistas') with ordinality as fila(elemento, orden)
  cross join lateral (
    select coalesce(jsonb_agg(
      rango.elemento || jsonb_build_object(
        'conversion', private.conversion_punteria(
          (rango.elemento#>>'{cohorte,convertidos}')::int,
          (rango.elemento#>>'{cohorte,descartados}')::int)
      ) order by rango.orden
    ), '[]'::jsonb) as rangos
    from jsonb_array_elements(fila.elemento#>'{pen,rangos}') with ordinality as rango(elemento, orden)
  ) rr;

  v_base := jsonb_set(v_base, '{analistas}', v_analistas, false);

  -- (auditor RLS, objecion 9) Los totales nucleo_* del resumen suman TODOS
  -- los analistas del ledger; el array `analistas` solo trae a quien sigue en
  -- el roster de vendedores/supervisores. Un ex-vendedor reenrolado conserva
  -- su historia: cuenta en el resumen y no tiene ficha. Esta sonda lo dice.
  select count(*) into v_sin_ficha
    from jsonb_object_keys(v_nucleo) k
   where k not in (
     select fila.elemento->>'analista_id'
       from jsonb_array_elements(v_base->'analistas') fila(elemento));

  -- ── Resumen: lo mismo, a nivel de toda la casa ────────────────────────────
  -- El USD del resumen lo suma HOY el navegador (`cierresUsd`, la suma en
  -- cliente de `distribucion-leads-gerencia.tsx:341-345`). Se suma aqui, de los
  -- MISMOS elementos, para que el numero sea identico y el front deje de
  -- hacerlo.
  select
    coalesce(sum((elemento#>>'{usd_no_segmentado,convertidos}')::int), 0),
    coalesce(sum((elemento#>>'{usd_no_segmentado,descartados}')::int), 0)
  into v_usd_conv, v_usd_desc
  from jsonb_array_elements(v_base->'analistas') as fila(elemento);

  v_base := jsonb_set(
    v_base,
    '{resumen}',
    (v_base->'resumen') || jsonb_build_object(
      'conversion', jsonb_build_object(
        'pen', private.conversion_punteria(
          (v_base#>>'{resumen,convertidos_pen}')::int,
          (v_base#>>'{resumen,descartados_pen}')::int),
        'usd', private.conversion_punteria(v_usd_conv, v_usd_desc),
        'nucleo_divisor', v_div_total,
        'nucleo_referidos_recibidos', v_ref_total,
        'nucleo_numerador', v_num_total,
        'nucleo_conversion_pct', case when v_div_total > 0
          then round(100.0 * v_num_total / v_div_total, 2) end
      )
    ),
    false
  );

  v_base := jsonb_set(v_base, '{version}', '3'::jsonb, false);
  v_base := jsonb_set(
    v_base,
    '{alcances}',
    (v_base->'alcances') || jsonb_build_object(
      'conversion_punteria', 'CERRADOS_ENTRE_RESUELTOS',
      'conversion_nucleo', 'COHORTE_POR_ASIGNACION_REFERIDOS_PONDERADOS',
      'conversion_incluye_cartera', v_periodo is not null
    ),
    false
  );

  -- ── Sondas: para que F3 pueda OCULTAR un numero en vez de fabricar un cero ─
  v_base := jsonb_set(
    v_base,
    '{sondas}',
    jsonb_build_object(
      'peso_referido', v_factor,
      'mes_peso', v_mes,
      'paridad_nucleo', v_paridad,
      'paridad_filas', v_paridad_filas,
      'cuadra', case when v_paridad is null or v_paridad_filas = 0 then null
                     else v_paridad = 0 end,
      -- Episodios que NO apareceran en `analistas` (analista nulo en la
      -- tabla-base): si esto crece, el resumen y la suma de fichas dejan de
      -- cuadrar y hay que saberlo.
      'divisor_sin_analista', v_div_sin_analista,
      'numerador_sin_analista', v_num_sin_analista,
      'cierres_anulados', v_anulados,
      'episodios_sin_origen', v_sin_origen,
      'nucleo_sin_ficha', v_sin_ficha
    ),
    true
  );

  return v_base;
end;
$fn$;

-- (auditor RLS, objecion 1) Mismo cierre que el helper: el motor no es
-- DEFINER y no tiene gate propio; nadie mas que su owner debe poder llamarlo.
revoke all on function private.metricas_distribucion_leads_v3_core(date, date, timestamp with time zone)
  from public, anon, authenticated, service_role;

comment on function private.metricas_distribucion_leads_v3_core(date, date, timestamp with time zone) is
  'Motor V3 de distribucion (F2.3b): el payload V2 mas los porcentajes YA CALCULADOS (punteria por analista, rango y resumen — las divisiones que hoy hace el navegador) mas la cifra del NUCLEO (la misma que HOY/Metas/Conversiones/Ranking) y un bloque `sondas`. No cambia ningun numero de V2: solo añade claves. El bundle vivo no llama a esta version.';

-- ---------------------------------------------------------------------------
-- 3. El despachador acepta la version 3 (cambio ADITIVO)
-- ---------------------------------------------------------------------------
-- Se reescribe entero porque `create or replace` lo exige, pero las ramas 1 y
-- 2 quedan IDENTICAS: el postflight lo comprueba. El gate de rol y la
-- validacion de periodo siguen viviendo aqui y en un solo sitio — duplicarlos
-- en una puerta nueva seria el error de «los cuatro espejos».
create or replace function private.metricas_distribucion_leads_autorizada(
  p_desde date,
  p_hasta date,
  p_version smallint
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_ahora timestamptz := statement_timestamp();
  v_hoy date := (v_ahora at time zone 'America/Lima')::date;
  v_payload jsonb;
begin
  if v_actor is null or not coalesce(
    private.rol_crm(v_actor)='gerencia' or private.es_lector_global(),
    false
  ) then
    raise exception 'Solo Gerencia o un lector global puede consultar estas metricas'
      using errcode='42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde>p_hasta
     or p_hasta>v_hoy or p_hasta-p_desde>365 then
    raise exception 'Periodo invalido: usa fechas hasta hoy y un maximo de 366 dias'
      using errcode='22023';
  end if;

  if p_version=1 then
    v_payload:=private.metricas_distribucion_leads_core(p_desde,p_hasta,v_ahora);
  elsif p_version=2 then
    v_payload:=private.metricas_distribucion_leads_v2_core(p_desde,p_hasta,v_ahora);
  elsif p_version=3 then
    v_payload:=private.metricas_distribucion_leads_v3_core(p_desde,p_hasta,v_ahora);
  else
    raise exception 'Version de metricas no soportada' using errcode='22023';
  end if;
  return private.sanitizar_sujetos_distribucion_crm(v_payload);
end;
$fn$;

-- ---------------------------------------------------------------------------
-- 4. La puerta v3 (misma forma que la v2: quita el SLA, deja lo demas)
-- ---------------------------------------------------------------------------
create or replace function crm.metricas_distribucion_leads_v3_fn(
  p_desde date,
  p_hasta date
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_payload jsonb;
  v_analistas jsonb;
begin
  v_payload := private.metricas_distribucion_leads_autorizada(
    p_desde,
    p_hasta,
    3::smallint
  );

  -- `is distinct from`, nunca `<>` (auditor RLS, objecion 2): con la clave
  -- AUSENTE, jsonb_typeof(NULL) es NULL y `NULL <> 'object'` no es ni verdad
  -- ni mentira — la guarda pasaria en vacio, que es el defecto que ya mordio
  -- dos veces en F2.
  if v_payload is null
     or jsonb_typeof(v_payload) is distinct from 'object'
     or jsonb_typeof(v_payload->'cohorte') is distinct from 'object'
     or jsonb_typeof(v_payload->'alcances') is distinct from 'object'
     or jsonb_typeof(v_payload->'resumen') is distinct from 'object'
     or jsonb_typeof(v_payload->'analistas') is distinct from 'array'
     or jsonb_typeof(v_payload->'calidad') is distinct from 'object'
     or jsonb_typeof(v_payload->'sondas') is distinct from 'object'
     or jsonb_typeof(v_payload#>'{resumen,conversion}') is distinct from 'object' then
    raise exception 'Contrato interno de distribucion V3 inesperado'
      using errcode = '55000';
  end if;

  -- Mismas sustracciones que la puerta V2: esta pantalla no transporta SLA.
  v_payload := jsonb_set(
    v_payload,
    '{cohorte}',
    (v_payload->'cohorte')
      - 'criterio_sla_global'
      - 'politica_pausas',
    false
  );
  v_payload := jsonb_set(
    v_payload,
    '{alcances}',
    (v_payload->'alcances')
      - 'operacion_sla'
      - 'sla_principal'
      - 'sla_operativo',
    false
  );
  v_payload := jsonb_set(
    v_payload,
    '{resumen}',
    (v_payload->'resumen')
      - 'sla_evaluables'
      - 'sla_en_24h'
      - 'sla_global_ciclos_cohorte'
      - 'sla_global_leads_unicos_cohorte'
      - 'sla_global_contactos'
      - 'sla_global_evaluables'
      - 'sla_global_en_24h'
      - 'primer_contacto_global_mediana_minutos'
      - 'sla_global_sin_contacto_vencidos_actuales',
    false
  );

  if exists (
    select 1
    from jsonb_array_elements(v_payload->'analistas') as fila(elemento)
    where jsonb_typeof(fila.elemento) is distinct from 'object'
       or jsonb_typeof(fila.elemento->'operacion') is distinct from 'object'
       or jsonb_typeof(fila.elemento->'conversion') is distinct from 'object'
  ) then
    raise exception 'Contrato interno de analistas V3 inesperado'
      using errcode = '55000';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_set(
        fila.elemento,
        '{operacion}',
        (fila.elemento->'operacion')
          - 'contactos'
          - 'contactos_asignacion'
          - 'sla_evaluables'
          - 'sla_en_24h'
          - 'sla_asignacion_evaluables'
          - 'sla_asignacion_en_24h'
          - 'primer_contacto_mediana_minutos'
          - 'primer_contacto_asignacion_mediana_minutos'
          - 'estancados_actual',
        false
      )
      order by fila.orden
    ),
    '[]'::jsonb
  )
  into v_analistas
  from jsonb_array_elements(v_payload->'analistas')
    with ordinality as fila(elemento, orden);

  v_payload := jsonb_set(v_payload, '{analistas}', v_analistas, false);
  v_payload := jsonb_set(
    v_payload,
    '{calidad}',
    (v_payload->'calidad') - 'ciclos_sla_global_aproximados_cohorte',
    false
  );

  return v_payload;
end;
$fn$;

-- (auditor RLS obj. 3 + Codex d4) Cambiar el dueño exige DOS cosas que en
-- produccion FALTAN y el banco (superusuario) no puede cazar:
--   1. poder hacer SET ROLE al rol destino — `postgres` es admin del puente
--      pero con set_option=false (verificado en pg_auth_members);
--   2. que el rol destino tenga CREATE sobre el esquema — se le revoco a
--      proposito al acuñar el puente (20260718152741:635) y sigue revocado
--      (verificado con has_schema_privilege).
-- La danza del patron probado: conceder lo justo, cambiar el dueño, devolver
-- cada cosa EXACTAMENTE como estaba.
do $owner$
declare
  v_tenia_set boolean;
  v_tenia_create boolean;
begin
  v_tenia_set := pg_catalog.pg_has_role(current_user, 'crm_metricas_bridge', 'SET');
  v_tenia_create := pg_catalog.has_schema_privilege('crm_metricas_bridge', 'crm', 'CREATE');
  if not v_tenia_set then
    execute pg_catalog.format('grant crm_metricas_bridge to %I with set true', current_user);
  end if;
  if not v_tenia_create then
    grant create on schema crm to crm_metricas_bridge;
  end if;
  alter function crm.metricas_distribucion_leads_v3_fn(date, date)
    owner to crm_metricas_bridge;
  if not v_tenia_create then
    revoke create on schema crm from crm_metricas_bridge;
  end if;
  if not v_tenia_set then
    execute pg_catalog.format('revoke set option for crm_metricas_bridge from %I', current_user);
  end if;
end $owner$;

-- (auditor RLS, objecion 7) El mismo barrido que hizo la puerta v2 al nacer:
-- se revoca de TODOS los roles de plataforma y se concede solo a authenticated.
revoke all on function crm.metricas_distribucion_leads_v3_fn(date, date) from public, anon, authenticated, service_role;
grant execute on function crm.metricas_distribucion_leads_v3_fn(date, date) to authenticated;

comment on function crm.metricas_distribucion_leads_v3_fn(date, date) is
  'JSON V3 de distribucion (F2.3b): lo de V2 mas los porcentajes servidos (punteria y nucleo) y el bloque `sondas`; no transporta SLA. Autorizacion private fail-closed mediante crm_metricas_bridge. El bundle vivo b3f6e98 llama a la V2 y no ve nada de esto: la V3 espera al front de F3.';

-- ---------------------------------------------------------------------------
-- 5. Postflight estructural + de contrato (misma transaccion)
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_src text;
  v_norm text;
  v_owner name;
  v_acl text;
  v_v2 jsonb;
  v_v3 jsonb;
  v_desde date;
  v_hasta date;
  v_claves_v2 text;
  v_claves_v3 text;
  v_n_analistas int;
  v_sin_conversion int;
  v_sin_rangos int;
  v_punteria jsonb;
  v_gerente uuid;
begin
  -- 5.1 El despachador sigue enrutando 1 y 2 a los MISMOS motores.
  select p.prosrc into v_src
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_autorizada';
  if v_src is null then
    raise exception 'metricas_distribucion_leads_autorizada desaparecio; rollback';
  end if;
  -- `strpos`, nunca LIKE: en LIKE el guion bajo es COMODIN y casaria prosa.
  v_norm := lower(regexp_replace(v_src, '\s+', ' ', 'g'));
  if pg_catalog.strpos(v_norm, 'p_version=1 then v_payload:=private.metricas_distribucion_leads_core(') = 0 then
    raise exception 'la rama v1 del despachador cambio de motor; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'p_version=2 then v_payload:=private.metricas_distribucion_leads_v2_core(') = 0 then
    raise exception 'la rama v2 del despachador cambio de motor; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'p_version=3 then v_payload:=private.metricas_distribucion_leads_v3_core(') = 0 then
    raise exception 'la rama v3 no quedo registrada; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'sanitizar_sujetos_distribucion_crm') = 0 then
    raise exception 'el despachador dejo de sanitizar sujetos; rollback';
  end if;
  if pg_catalog.strpos(v_norm, 'errcode=''42501''') = 0 then
    raise exception 'el gate de rol desaparecio del despachador; rollback';
  end if;

  -- 5.2 La puerta nueva: dueño, DEFINER, search_path y permisos.
  select pg_catalog.pg_get_userbyid(p.proowner),
         pg_catalog.array_to_string(p.proacl, ' | ')
    into v_owner, v_acl
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn';
  if v_owner is distinct from 'crm_metricas_bridge' then
    raise exception 'la puerta v3 quedo con dueño % (esperado crm_metricas_bridge); rollback', v_owner;
  end if;
  -- Un `proacl` NULL significa PRIVILEGIOS POR DEFECTO — es decir EXECUTE a
  -- PUBLIC — y `aclexplode(NULL)` devuelve CERO filas, asi que hay que
  -- rechazarlo aparte o la comprobacion pasaria en vacio.
  if v_acl is null then
    raise exception 'la puerta v3 quedo con privilegios por defecto (EXECUTE a PUBLIC); rollback';
  end if;
  if pg_catalog.has_function_privilege('public', 'crm.metricas_distribucion_leads_v3_fn(date,date)', 'EXECUTE') then
    raise exception 'PUBLIC puede ejecutar la puerta v3; rollback';
  end if;
  if not pg_catalog.has_function_privilege('authenticated', 'crm.metricas_distribucion_leads_v3_fn(date,date)', 'EXECUTE') then
    raise exception 'authenticated NO puede ejecutar la puerta v3; rollback';
  end if;
  -- (auditor RLS, objecion 7) Barrido EXHAUSTIVO de grantees, como F2.2: la
  -- allowlist es {dueño, authenticated} y nadie mas — un grant colado a
  -- service_role pasaria las dos comprobaciones puntuales de arriba.
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    cross join lateral pg_catalog.aclexplode(p.proacl) a
    where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn'
      and a.grantee <> p.proowner
      and pg_catalog.pg_get_userbyid(a.grantee) <> 'authenticated'
  ) then
    raise exception 'la puerta v3 tiene grantees fuera de la allowlist; rollback';
  end if;
  -- (auditor RLS, objecion 6) Lo que el comentario prometia y el codigo no
  -- miraba: la puerta es DEFINER con search_path fijado; el motor NO es
  -- DEFINER, es STABLE y lleva search_path; el helper es IMMUTABLE.
  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'crm' and p.proname = 'metricas_distribucion_leads_v3_fn'
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'la puerta v3 no es DEFINER+STABLE con search_path vacio; rollback';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'metricas_distribucion_leads_v3_core'
      and not p.prosecdef and p.provolatile = 's'
      and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'el motor v3 debia ser NO-definer STABLE con search_path vacio; rollback';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname = 'conversion_punteria'
      and not p.prosecdef and p.provolatile = 'i'
      and p.proconfig @> array['search_path=""']::text[]
  ) then
    raise exception 'conversion_punteria debia ser NO-definer IMMUTABLE con search_path vacio; rollback';
  end if;
  -- (auditor RLS, objecion 1) Las dos funciones private nuevas: ACL
  -- materializado (no por defecto) y ningun grantee fuera del dueño.
  if exists (
    select 1
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in ('metricas_distribucion_leads_v3_core', 'conversion_punteria')
      and (p.proacl is null
           or exists (select 1 from pg_catalog.aclexplode(p.proacl) a
                       where a.grantee <> p.proowner))
  ) then
    raise exception 'una funcion private nueva quedo ejecutable por alguien mas que su dueño; rollback';
  end if;
  -- (Codex d4) La danza devolvio cada cosa a su sitio: el puente sigue SIN
  -- CREATE sobre crm (el candado de julio queda intacto).
  if pg_catalog.has_schema_privilege('crm_metricas_bridge', 'crm', 'CREATE') then
    raise exception 'crm_metricas_bridge quedo con CREATE sobre crm tras la danza; rollback';
  end if;

  -- 5.3 La division en un solo sitio se comporta: sin resueltos, `pct` es
  --     NULL (no 0), y con resueltos redondea a seis decimales.
  v_punteria := private.conversion_punteria(0, 0);
  -- GUARDA ANTI-VACUIDAD: si la clave no existiera, `-> 'pct'` daria SQL NULL
  -- y la comparacion de abajo no seria ni verdad ni mentira.
  if v_punteria is null or not v_punteria ? 'pct' then
    raise exception 'conversion_punteria no devuelve la clave pct; rollback';
  end if;
  if v_punteria->'pct' <> 'null'::jsonb then
    raise exception 'conversion_punteria(0,0) deberia dar pct NULL y dio %; rollback', v_punteria;
  end if;
  v_punteria := private.conversion_punteria(1, 2);
  if (v_punteria->>'pct')::numeric <> round(100.0/3, 6) then
    raise exception 'conversion_punteria(1,2) dio % (esperado %); rollback',
      v_punteria->>'pct', round(100.0/3, 6);
  end if;
  if (v_punteria->>'resueltos')::int <> 3 then
    raise exception 'conversion_punteria(1,2) no suma resueltos; rollback';
  end if;

  -- 5.4 CONTRATO: v3 = v2 + exactamente las claves nuevas, sobre datos REALES.
  --     Ventana de un dia para que el postflight no cueste una eternidad.
  v_hasta := (statement_timestamp() at time zone 'America/Lima')::date;
  v_desde := v_hasta;
  v_v2 := private.metricas_distribucion_leads_v2_core(v_desde, v_hasta, statement_timestamp());
  v_v3 := private.metricas_distribucion_leads_v3_core(v_desde, v_hasta, statement_timestamp());

  select string_agg(k, ',' order by k) into v_claves_v2
    from jsonb_object_keys(v_v2) k;
  select string_agg(k, ',' order by k) into v_claves_v3
    from jsonb_object_keys(v_v3) k;
  if v_claves_v2 is null or v_claves_v3 is null then
    raise exception 'POSTFLIGHT VACUO: uno de los motores no devolvio un objeto; rollback';
  end if;
  if v_claves_v3 is distinct from (
       select string_agg(k, ',' order by k)
         from (select k from jsonb_object_keys(v_v2) k union select 'sondas') u(k)
     ) then
    raise exception 'v3 no es v2 + `sondas` a primer nivel. v2=[%] v3=[%]; rollback',
      v_claves_v2, v_claves_v3;
  end if;
  if (v_v3->>'version') is distinct from '3' then
    raise exception 'v3 no se rotula como version 3; rollback';
  end if;
  if jsonb_typeof(v_v3#>'{resumen,conversion}') is distinct from 'object' then
    raise exception 'falta resumen.conversion en v3; rollback';
  end if;

  -- GUARDA ANTI-VACUIDAD: sin analistas, las dos comprobaciones de abajo
  -- pasarian sin comprobar nada. Ya paso dos veces en F2.
  select count(*) into v_n_analistas from jsonb_array_elements(v_v3->'analistas');
  if v_n_analistas = 0 then
    raise exception 'POSTFLIGHT VACUO: cero analistas en la ventana; rollback';
  end if;
  -- `is distinct from`, nunca `<>` (auditor RLS, objecion 2): con la clave
  -- ausente jsonb_typeof da NULL y el predicado no contaria la fila — el
  -- bloque podria faltar ENTERO y el contador saldria 0.
  select count(*) into v_sin_conversion
    from jsonb_array_elements(v_v3->'analistas') a
   where jsonb_typeof(a.value->'conversion') is distinct from 'object'
      or jsonb_typeof(a.value#>'{conversion,pen}') is distinct from 'object'
      or jsonb_typeof(a.value#>'{conversion,usd}') is distinct from 'object'
      or (a.value->'conversion' ? 'nucleo_conversion_pct') is distinct from true;
  if v_sin_conversion > 0 then
    raise exception '% analistas sin el bloque `conversion` completo; rollback', v_sin_conversion;
  end if;
  select count(*) into v_sin_rangos
    from jsonb_array_elements(v_v3->'analistas') a,
         jsonb_array_elements(a.value#>'{pen,rangos}') r
   where jsonb_typeof(r.value->'conversion') is distinct from 'object';
  if v_sin_rangos > 0 then
    raise exception '% rangos sin `conversion`; rollback', v_sin_rangos;
  end if;

  -- 5.5 (auditor RLS, objecion 11) LA CADENA REAL, no solo los motores:
  -- puente → despachador rama 3 → puerta, con una gerencia de verdad, en solo
  -- lectura y dentro de esta misma transaccion (patron del guion de F2.2).
  select e.perfil_id into v_gerente
    from crm.equipo e
    join public.perfiles p on p.id = e.perfil_id
   where e.rol_crm = 'gerencia' and e.activo and p.activo
   limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT VACUO: sin gerencia activa no se puede probar la cadena; rollback';
  end if;
  perform pg_catalog.set_config(
    'request.jwt.claims',
    pg_catalog.json_build_object('sub', v_gerente, 'role', 'authenticated')::text,
    true);
  v_v3 := crm.metricas_distribucion_leads_v3_fn(v_desde, v_hasta);
  perform pg_catalog.set_config('request.jwt.claims', '', true);
  if jsonb_typeof(v_v3->'sondas') is distinct from 'object'
     or jsonb_typeof(v_v3#>'{resumen,conversion}') is distinct from 'object' then
    raise exception 'la CADENA REAL no sirve las claves nuevas; rollback';
  end if;
  if (v_v3->'resumen' ? 'sla_global_contactos')
     or (v_v3->'resumen' ? 'sla_global_en_24h') then
    raise exception 'la puerta v3 transporta SLA por la cadena real; rollback';
  end if;

  raise notice 'F2.3b OK · v3 = v2 + sondas · % analistas con conversion servida · cadena real probada', v_n_analistas;
end $postflight$;
