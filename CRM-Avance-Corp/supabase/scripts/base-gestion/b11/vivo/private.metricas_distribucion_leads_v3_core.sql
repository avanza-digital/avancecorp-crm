CREATE OR REPLACE FUNCTION private.metricas_distribucion_leads_v3_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_oficial jsonb;
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

  -- El núcleo admite también rangos parciales y aplica su ventana a cartera.
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
      coalesce(sum(e.aporte_divisor), 0)::int as divisor,
      count(*) filter (where e.tipo = 'recibido' and e.fue_referido)::int as referidos_recibidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and not e.fue_referido)::int as cierres_no_referidos,
      count(distinct e.lead_id) filter (
        where e.tipo = 'cierre' and not e.anulado and e.origen in ('landing', 'formulario', 'referido') and e.fue_referido)::int as cierres_referidos,
      count(*) filter (where e.tipo = 'operacion')::int as operaciones,
      coalesce(sum(e.aporte_numerador), 0)::numeric as numerador
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
            nv.numerador,
          'nucleo_conversion_pct', case when nv.divisor > 0
            then round(100.0 * nv.numerador / nv.divisor, 2) end
        )
      ) filter (where nv.analista_id is not null), '{}'::jsonb) as mapa,
      coalesce(sum(nv.divisor), 0)::int as div_total,
      coalesce(sum(nv.numerador), 0) as num_total,
      coalesce(sum(nv.referidos_recibidos), 0)::int as ref_total,
      coalesce(sum(nv.divisor) filter (where nv.analista_id is null), 0)::int as div_sin,
      coalesce(sum(
        nv.numerador
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
          nv.numerador, 0)
        - coalesce(cm.numerador, 0)) as delta
    from nv
    -- `=` y no `is not distinct from`: PG no admite este ultimo en un FULL
    -- JOIN (no es hash/merge-joinable). Es seguro porque ninguna de las dos
    -- relaciones puede traer `analista_id` NULL en el lado que importa; si eso
    -- cambiara, la sonda gritaria (paridad <> 0) en vez de callarse.
    full outer join private.conversion_mensual_por_vendedor(
      v_ini, v_fin, true, '{}'::uuid[], v_factor
    ) cm on coalesce(cm.analista_id, '00000000-0000-0000-0000-000000000000'::uuid) = coalesce(nv.analista_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ),
  sonda as (
    select
      coalesce(sum(c.delta), 0) as desvio,
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
          then round(100.0 * v_num_total / v_div_total, 2) end,
        -- DECLARACION (Ola 1a, 22/09/2026). Cuatro claves que NO cambian
        -- ninguna cifra: dicen de donde sale la que ya se publicaba.
        --   es_mes_calendario: `v_periodo is not null` — la MISMA prueba que
        --     esta funcion ya usaba mas arriba para pedirle la cartera al
        --     nucleo. Es la condicion de Miguel (21/09) para poder delegar.
        --   fuente: 'rango_vivo' SIEMPRE: esta puerta calcula por su cuenta
        --     sobre `ep`. El dia que delegue en crm.conversion_mensual_fn
        --     dira 'mensual'.
        --   sellado: null = «no se delego en la foto oficial».
        --   ajuste_aplicado: false = NO resta la deuda de anulacion de un mes
        --     ya sellado. Ese es el hecho que puede hacerla discrepar de la
        --     cifra oficial, y declararlo es lo que lo vuelve visible.
        -- Van SOLO en el resumen, no en la ficha de cada analista: describen
        -- el calculo entero, no a un analista. El front las lee opcionales en
        -- los dos sitios (`ConversionNucleoEntries`), asi que su ausencia en
        -- la ficha no rompe nada.
        'es_mes_calendario', v_periodo is not null,
        'fuente', 'rango_vivo',
        'sellado', null,
        'ajuste_aplicado', false
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
      'conversion_nucleo', 'LLEGADAS_UNICAS_PRIMER_ANALISTA',
      'conversion_incluye_cartera', true
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

  -- ══ OLA 1b · LA SUSTITUCION ════════════════════════════════════════════
  -- REGLA DE MIGUEL (21/09/2026): mes calendario completo y sin filtro de
  -- fuente -> la cifra la sirve `crm.conversion_mensual_fn`. Este motor no
  -- recibe filtro de fuente, asi que la condicion es `v_periodo is not null`,
  -- la misma prueba que ya usaba para pedirle la cartera al nucleo.
  --
  -- Se sustituyen las TRES claves de la cifra en los DOS sitios donde viajan:
  -- el resumen y la ficha de cada analista. Si solo se hiciera el resumen, la
  -- ficha de un analista aqui y la misma ficha en Gestion de equipo dirian
  -- cosas distintas el dia que haya deuda — justo lo que esta ola viene a
  -- matar.
  --
  -- `nucleo_referidos_recibidos` NO se delega: es un recuento descriptivo que
  -- la oficial no publica por vendedor, y fabricar un 0 seria mentir.
  --
  -- Si un analista NO tiene fila en la oficial, su `nucleo_conversion_pct`
  -- queda en `null` —«no se sabe»— y nunca en 0. El postflight lo cuenta y
  -- exige que hoy no le pase a ninguno. La cuenta NO viaja en `sondas`: el
  -- front las valida con `v.strictObject` y una clave nueva tumbaria el
  -- payload entero. Entrara con su front, no antes.
  --
  -- Y nada de `set_config` aqui: esta funcion es STABLE.
  -- 🔴 LA GUARDA DE IDENTIDAD, Y POR QUE EXISTE. Este motor NO es
  -- `security definer` y no tiene gate propio: el gate vive aguas arriba, en
  -- `private.metricas_distribucion_leads_autorizada`. Pero
  -- `crm.conversion_mensual_fn` SI exige identidad y responde 42501 sin ella.
  -- Medido el 22/09: el unico llamante en la base es esa funcion autorizada
  -- (que siempre trae actor), pero en el repo hay scripts de gate que llaman a
  -- este motor DIRECTAMENTE, en una sesion de operador sin claims
  -- (`supabase/scripts/test-f2-distribucion-v3.sql`,
  --  `supabase/scripts/test-conversion-llegadas.sql`). Sin esta guarda,
  -- esos gates pasarian a morir con «No autorizado».
  --
  -- Sin identidad no se puede preguntar a la oficial, asi que se sigue
  -- calculando en vivo Y SE DECLARA como tal (`fuente: rango_vivo` con
  -- `es_mes_calendario: true`, que es justo «era delegable y no se delego»).
  -- Ninguna pantalla puede caer aqui: para llegar a este motor desde una
  -- pantalla hay que pasar antes por el gate, que exige actor.
  if v_periodo is not null and (select auth.uid()) is not null then
    v_oficial := crm.conversion_mensual_fn(v_periodo);

    v_base := jsonb_set(v_base, '{resumen,conversion}',
      (v_base #> '{resumen,conversion}') || jsonb_build_object(
        'fuente', 'mensual',
        'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
        'ajuste_aplicado', true,
        'nucleo_divisor', v_oficial #> '{total,divisor}',
        'nucleo_numerador', v_oficial #> '{total,numerador}',
        'nucleo_conversion_pct', v_oficial #> '{total,conversion_pct}'
      ), false);

    v_base := jsonb_set(v_base, '{analistas}',
      coalesce((
        select jsonb_agg(
          -- 🔴 A quien la oficial NO tiene, NO se le toca la cifra. Medido el
          -- 22/09: 3 de 21 analistas no tienen fila en la oficial (18
          -- responsables) y uno de ellos, un SUPERVISOR ACTIVO, llevaba
          -- `nucleo_numerador = 2`. Sobrescribirlo con el coalesce a 0 le
          -- habria borrado dos puntos de la pantalla en silencio. Su cifra se
          -- queda como la calculo esta funcion: ni se fabrica ni se pierde.
          -- El TOTAL sigue siendo el de la oficial, que si los cuenta.
          jsonb_set(f.e, '{conversion}',
            case when o.v is null then (f.e -> 'conversion')
                 else (f.e -> 'conversion') || jsonb_build_object(
                   'nucleo_divisor', (o.v -> 'divisor'),
                   'nucleo_numerador', (o.v -> 'numerador'),
                   'nucleo_conversion_pct', (o.v -> 'conversion_pct'))
            end, false)
          order by f.ord)
          from jsonb_array_elements(coalesce(v_base -> 'analistas', '[]'::jsonb))
               with ordinality f(e, ord)
          left join lateral (
            select r.v from jsonb_array_elements(coalesce(v_oficial -> 'responsables', '[]'::jsonb)) r(v)
             where (r.v ->> 'vendedor_id') = (f.e ->> 'analista_id') limit 1
          ) o on true
      ), '[]'::jsonb), false);
  end if;

  return v_base;
end;
$function$

