-- =========================================================================
-- CRM · Ola 1a · La puerta #5 (distribucion de leads v3) DECLARA su fuente
-- =========================================================================
-- QUE HACE: anade cuatro claves informativas al bloque `resumen.conversion` de
-- `private.metricas_distribucion_leads_v3_core(date,date,timestamptz)`, el
-- motor detras de `crm.metricas_distribucion_leads_v3_fn`. Nada mas.
--
-- 🔑 ESTA MIGRACION NO CAMBIA NI UN NUMERO. Solo DECLARA con que criterio se
--    calculo la cifra que ya se publicaba.
--
-- DONDE SE INTERVIENE, Y POR QUE AQUI: el gate de autorizacion vive AGUAS
-- ARRIBA, en `private.metricas_distribucion_leads_autorizada` y en
-- `crm.metricas_distribucion_leads_v3_fn` (SECURITY DEFINER, dueno
-- `crm_metricas_bridge`). Tocar el motor `_core` deja ese borde intacto: no se
-- redeclara ninguna funcion del puente ni ninguna que decida quien ve que.
--
-- MEDIDO EN PRODUCCION EL 22/09/2026, y fijado en el preflight:
--   · cuerpo vivo: md5(pg_get_functiondef) = be2290576ef7f8947f3b4d3a9db846a7
--   · dueno: postgres · STABLE, SIN security definer
--   · NO esta declarada en `private.analitica_leads_citas_exenciones` y NO
--     esta en el censo de contadores crudos. No hay huella que re-sellar; el
--     postflight exige que siga FUERA del censo (si entrara sin declaracion,
--     el trinquete se pondria rojo).
--
-- 🔴 ESTA ES LA UNICA DE LA OLA 1a QUE EL FRONT VIVO NO TOLERA. MEDIDO:
--    En el bundle publicado hoy (`build-20260922T221442353Z`, commit
--    `7d65fcdb484f`), `resumen.conversion` se valida con **`v.strictObject`**
--    (`metricas-distribucion.ts:316` de ese commit) y sus entradas NO incluyen
--    las cuatro claves. Cuatro claves desconocidas -> valibot rechaza el
--    payload ENTERO -> la pantalla de distribucion de gerencia se queda SIN
--    DATOS. (Las puertas #4 y #6 usan `v.object`, que ignora lo que no conoce:
--    por eso ellas si pueden entrar antes que el front.)
--
--    `git merge-base --is-ancestor c2c9274b 7d65fcdb484f` -> **NO**: el commit
--    que vuelve opcionales esas claves todavia no esta publicado.
--
--    POR ESO ESTA MIGRACION LLEVA PESTILLO. No se aplica sin declarar a mano,
--    en la MISMA sesion, que el front ya esta vivo:
--        set local crm.ola1_front_publicado = 'si';
--    Antes de escribir eso hay que comprobarlo de verdad, en este orden:
--      1. `curl -s https://crm.miavance.com/version.json` -> buildId
--      2. el manifiesto de ese buildId en `releases/` -> commit publicado
--      3. `git merge-base --is-ancestor c2c9274b <ese commit>`
--
-- REVERSA: volver a declarar el cuerpo sin las cuatro claves. El front las lee
-- opcionales (`app/src/lib/metricas-distribucion.ts`, `ConversionNucleoEntries`).
-- =========================================================================

begin;

set local statement_timeout = '180s';

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: acreditar el cuerpo por IDENTIDAD, no por fragmentos.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_md5 text; v_dueno text; v_secdef boolean;
begin
  -- EL PESTILLO. Sin esta declaracion explicita, la migracion no entra.
  if coalesce(current_setting('crm.ola1_front_publicado', true), '') <> 'si' then
    raise exception 'PREFLIGHT: falta declarar que el front ya esta publicado. Comprueba version.json -> manifiesto -> merge-base c2c9274b, y si es cierto ejecuta en la misma sesion: set local crm.ola1_front_publicado = ''si'';';
  end if;

  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef
    into v_md5, v_dueno, v_secdef
    from pg_proc p
   where p.oid = to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)');

  if v_md5 is null then
    raise exception 'PREFLIGHT: private.metricas_distribucion_leads_v3_core no existe';
  end if;
  if v_md5 <> 'be2290576ef7f8947f3b4d3a9db846a7' then
    raise exception 'PREFLIGHT: el cuerpo vivo NO es el revisado (md5 %). Alguien lo cambio despues del 22/09.', v_md5;
  end if;
  if v_dueno <> 'postgres' or v_secdef then
    raise exception 'PREFLIGHT: dueno o security inesperados (% · secdef %)', v_dueno, v_secdef;
  end if;
end;
$preflight$;

-- Foto de referencia ANTES de tocar nada. El motor NO es security definer: se
-- puede llamar tal cual, sin tomar prestada ninguna identidad.
create temp table _p5_antes (payload jsonb) on commit drop;

insert into _p5_antes (payload)
select private.metricas_distribucion_leads_v3_core(
         date_trunc('month', (now() at time zone 'America/Lima'))::date,
         (now() at time zone 'America/Lima')::date,
         now());

-- ---------------------------------------------------------------------------
-- (b) El motor, declarando su fuente. Cuerpo generado POR ANCLAS sobre el vivo
--     acreditado arriba: el unico cambio es el bloque de cuatro claves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.metricas_distribucion_leads_v3_core(p_desde date, p_hasta date, p_ahora timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
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

  return v_base;
end;
$function$;

-- ---------------------------------------------------------------------------
-- (c) POSTFLIGHT: trinquete verde, las claves viajan, y NI UN NUMERO MOVIDO.
--     Se compara el payload ENTERO (quitando `generado_en`, que es un reloj, y
--     las cuatro claves nuevas): asi no se cuela un cambio en `analistas`, en
--     `rangos`, en `sondas` ni en `alcances`.
-- ---------------------------------------------------------------------------
create temp table _p5_despues (payload jsonb) on commit drop;

do $postflight$
declare
  v_ok text; v_antes jsonb; v_despues jsonb; v_parcial jsonb; v_conv jsonb;
  v_a jsonb; v_d jsonb; v_res jsonb;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into v_antes from _p5_antes;
  v_despues := private.metricas_distribucion_leads_v3_core(
                 date_trunc('month', (now() at time zone 'America/Lima'))::date,
                 (now() at time zone 'America/Lima')::date, now());
  -- 🔴 NO vale «el dia 1 a el dia 1»: el DIA 1 del mes ese rango SI es mes
  -- calendario por la regla de Miguel (`p_hasta = v_hoy`), y la migracion seria
  -- inaplicable justo ese dia. Un rango del mes ANTERIOR que no termina ni el
  -- ultimo dia ni hoy es parcial SIEMPRE.
  v_parcial := private.metricas_distribucion_leads_v3_core(
                 (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date,
                 (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date + 1,
                 now());
  insert into _p5_despues (payload) values (v_despues);

  v_conv := v_despues #> '{resumen,conversion}';

  -- 1) NI UN NUMERO MOVIDO.
  v_a := v_antes - 'generado_en';
  v_d := v_despues - 'generado_en';
  v_res := (v_d -> 'resumen');
  v_res := jsonb_set(v_res, '{conversion}',
             (v_res -> 'conversion') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado');
  v_d := jsonb_set(v_d, '{resumen}', v_res);
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: el payload SE MOVIO fuera de las cuatro claves nuevas. ANTES: % · DESPUES: %', v_a, v_d;
  end if;

  -- 2) Las cuatro claves viajan, con los valores que deben.
  if v_conv -> 'es_mes_calendario' is null then
    raise exception 'POSTFLIGHT: no publica es_mes_calendario en resumen.conversion';
  end if;
  if (v_conv ->> 'es_mes_calendario')::boolean is not true then
    raise exception 'POSTFLIGHT: del dia 1 a hoy ES mes calendario y dice %', v_conv ->> 'es_mes_calendario';
  end if;
  if (v_conv ->> 'fuente') is distinct from 'rango_vivo' then
    raise exception 'POSTFLIGHT: fuente = % (esta ola NO sustituye: siempre rango_vivo)', v_conv ->> 'fuente';
  end if;
  if v_conv -> 'sellado' <> 'null'::jsonb then
    raise exception 'POSTFLIGHT: sellado deberia ser null («no se delego»), y es %', v_conv -> 'sellado';
  end if;
  if (v_conv ->> 'ajuste_aplicado')::boolean is not false then
    raise exception 'POSTFLIGHT: ajuste_aplicado deberia ser false; esta puerta no resta la deuda';
  end if;

  -- 3) Un rango PARCIAL no puede declararse mes calendario.
  if (v_parcial #>> '{resumen,conversion,es_mes_calendario}')::boolean is not false then
    raise exception 'POSTFLIGHT: un rango de un solo dia se declara mes calendario; el test esta roto';
  end if;

  -- 4) Ni la ficha de cada analista ni el borde de privacidad se movieron: lo
  --    garantiza (1). Aqui solo se comprueba que las claves NO se colaron en
  --    las fichas (van solo en el resumen, por diseno).
  if exists (select 1 from jsonb_array_elements(v_despues -> 'analistas') f(e)
              where f.e #> '{conversion}' ? 'fuente') then
    raise exception 'POSTFLIGHT: las claves de declaracion se colaron en la ficha de un analista';
  end if;

  -- 5) Dueno y security, intactos.
  -- `create or replace` REESCRIBE definer, volatilidad y search_path desde el
  -- texto: se acreditan los cuatro, no solo el dueno.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)')
                    and p.proowner = 'postgres'::regrole
                    and not p.prosecdef
                    and p.provolatile = 's'
                    and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path del motor';
  end if;

  -- 6) Sigue FUERA del censo de contadores crudos. Si hubiera entrado sin
  --    declaracion, el trinquete se pondria rojo en el proximo gate.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'private.metricas_distribucion_leads_v3_core(date,date,timestamp with time zone)') then
    raise exception 'POSTFLIGHT: el motor ENTRO al censo de contadores crudos; hay que declararlo aqui mismo';
  end if;
end;
$postflight$;

-- (d) El contrato, tambien en el diccionario. `create or replace` CONSERVA el
--     comentario anterior; hay que refrescarlo a mano. No afecta a ninguna
--     huella: el comentario no vive en `prosrc`.
comment on function private.metricas_distribucion_leads_v3_core(date,date,timestamptz) is
  'Motor v3 de la distribucion de leads (lo publica crm.metricas_distribucion_leads_v3_fn, '
  'cuyo gate vive aguas arriba). Desde la Ola 1a (22/09/2026) su bloque '
  '`resumen.conversion` DECLARA de donde sale la cifra: `es_mes_calendario` (el rango es un '
  'mes calendario completo, la condicion de Miguel del 21/09 para poder delegar en '
  'crm.conversion_mensual_fn), `fuente` (hoy siempre `rango_vivo`), `sellado` (null = no se '
  'delego en la foto oficial) y `ajuste_aplicado` (false = NO resta la deuda de anulacion de '
  'un mes ya sellado). Van solo en el resumen, no en la ficha de cada analista. Declarar no '
  'es sustituir: da exactamente la misma cifra que antes de esa ola.';

select 'puerta5-declara-su-fuente' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       (select payload #> '{resumen,conversion}' from _p5_despues) as conversion;

commit;
