-- =========================================================================
-- CRM · Ola 1b · La puerta #5 DELEGA su cifra en crm.conversion_mensual_fn
-- =========================================================================
-- QUE HACE: cuando el rango es un mes calendario completo,
-- `private.metricas_distribucion_leads_v3_core` publica `nucleo_divisor`,
-- `nucleo_numerador` y `nucleo_conversion_pct` tal como los sirve la oficial,
-- en el RESUMEN y en la ficha de CADA ANALISTA. Fuera de esa condicion, igual
-- que hoy.
--
-- 🔴 DEPENDE DE LA OLA 1a DE ESTA MISMA PUERTA (`..._crm_puerta5_declara_su_
--    fuente.sql`). El preflight fija el md5 del cuerpo TRAS aquella, asi que
--    esta migracion NO puede entrar antes, ni sobre un cuerpo distinto.
--
-- 🔴 Y COMO AQUELLA, DEPENDE DEL FRONT: en el bundle vivo del 22/09
--    (`build-20260922T221442353Z` = `7d65fcdb484f`) `resumen.conversion` se
--    valida con `v.strictObject` sin las cuatro claves de la declaracion. El
--    pestillo de la 1a es el que guarda esa puerta; aqui basta el md5, porque
--    sin la 1a aplicada este preflight se niega.
--
-- POR QUE TAMBIEN LA FICHA DE CADA ANALISTA, y no solo el resumen: si solo se
-- delegara el resumen, la ficha de un analista en Distribucion y la misma
-- ficha en Gestion de equipo dirian cosas distintas el dia que haya deuda.
--
-- MEDIDO EN PRODUCCION (22/09, deuda de 2 puntos plantada y deshecha): con la
-- Ola 1b puesta, #6, la oficial, #7 y #8 publican los CUATRO el mismo
-- numerador (4) para el analista afectado; sin ella, #6 se quedaba en 6.
--
-- FIJADO EN EL PREFLIGHT:
--   · cuerpo tras la Ola 1a: md5(pg_get_functiondef) = f619805f958ba871a54162c81ef551b0
--   · dueno: postgres · STABLE, SIN security definer
--   · NI declarada NI en el censo de contadores crudos: no hay huella que
--     re-sellar. El postflight exige que siga fuera.
--
-- REVERSA: volver a declarar el cuerpo de la Ola 1a (sin el bloque de
-- sustitucion).
-- =========================================================================

begin;

set local statement_timeout = '180s';

do $preflight$
declare v_md5 text; v_dueno text; v_secdef boolean;
begin
  select md5(pg_get_functiondef(p.oid)), p.proowner::regrole::text, p.prosecdef
    into v_md5, v_dueno, v_secdef
    from pg_proc p
   where p.oid = to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)');
  if v_md5 is null then
    raise exception 'PREFLIGHT: el motor v3 no existe';
  end if;
  if v_md5 <> 'f619805f958ba871a54162c81ef551b0' then
    raise exception 'PREFLIGHT: el cuerpo vivo no es el de la Ola 1a (md5 %). ¿Falta aplicar la Ola 1a de esta puerta, o alguien la cambio?', v_md5;
  end if;
  if v_dueno <> 'postgres' or v_secdef then
    raise exception 'PREFLIGHT: dueno o security inesperados (% · secdef %)', v_dueno, v_secdef;
  end if;
  if to_regprocedure('crm.conversion_mensual_fn(date)') is null then
    raise exception 'PREFLIGHT: crm.conversion_mensual_fn(date) no existe';
  end if;
end;
$preflight$;

create temp table _p5b_antes (payload jsonb, oficial jsonb) on commit drop;

do $antes$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'PREFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    insert into _p5b_antes (payload, oficial)
    select private.metricas_distribucion_leads_v3_core(
             date_trunc('month', (now() at time zone 'America/Lima'))::date,
             (now() at time zone 'America/Lima')::date, now()),
           crm.conversion_mensual_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

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
$function$;

-- ---------------------------------------------------------------------------
-- POSTFLIGHT
-- ---------------------------------------------------------------------------
create temp table _p5b_despues (payload jsonb) on commit drop;

do $postflight$
declare
  v_ok text; v_antes jsonb; v_of jsonb; v_despues jsonb; v_parcial jsonb;
  v_conv jsonb; v_a jsonb; v_d jsonb; v_n int; v_sin_identidad jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload, oficial into v_antes, v_of from _p5b_antes;

  -- El motor ya no se puede leer sin identidad cuando el rango es delegable.
  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    v_despues := private.metricas_distribucion_leads_v3_core(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date,
                   (now() at time zone 'America/Lima')::date, now());
    v_parcial := private.metricas_distribucion_leads_v3_core(
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date,
                   (date_trunc('month', (now() at time zone 'America/Lima')) - interval '1 month')::date + 1,
                   now());
    -- Y la puerta de escape de la guarda: SIN identidad, sigue respondiendo.
    perform set_config('request.jwt.claims', '', true);
    v_sin_identidad := private.metricas_distribucion_leads_v3_core(
                         date_trunc('month', (now() at time zone 'America/Lima'))::date,
                         (now() at time zone 'America/Lima')::date, now()) #> '{resumen,conversion}';
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  insert into _p5b_despues (payload) values (v_despues);
  v_conv := v_despues #> '{resumen,conversion}';

  -- 1) El resumen publica, exactamente, la cifra oficial.
  if (v_conv -> 'nucleo_divisor')        is distinct from (v_of #> '{total,divisor}')
     or (v_conv -> 'nucleo_numerador')   is distinct from (v_of #> '{total,numerador}')
     or (v_conv -> 'nucleo_conversion_pct') is distinct from (v_of #> '{total,conversion_pct}') then
    raise exception 'POSTFLIGHT: el resumen NO publica la cifra oficial. resumen % · oficial %',
      v_conv, v_of #> '{total}';
  end if;

  -- 2) Y cada ficha de analista, tambien.
  select count(*)::int into v_n
    from jsonb_array_elements(v_despues -> 'analistas') f(e)
    join jsonb_array_elements(v_of -> 'responsables') r(v)
      on (r.v ->> 'vendedor_id') = (f.e ->> 'analista_id')
   where (f.e #> '{conversion,nucleo_divisor}')        is distinct from (r.v -> 'divisor')
      or (f.e #> '{conversion,nucleo_numerador}')      is distinct from (r.v -> 'numerador')
      or (f.e #> '{conversion,nucleo_conversion_pct}') is distinct from (r.v -> 'conversion_pct');
  if v_n <> 0 then
    raise exception 'POSTFLIGHT: % fichas de analista NO publican la cifra oficial', v_n;
  end if;

  -- 3) A quien la oficial NO tiene, no se le toco NI UN NUMERO. (Hoy son 3 de
  --    21, y uno es un supervisor activo con numerador 2.)
  select count(*)::int into v_n
    from jsonb_array_elements(v_antes -> 'analistas') a(e)
    join jsonb_array_elements(v_despues -> 'analistas') d(e)
      on (a.e ->> 'analista_id') = (d.e ->> 'analista_id')
   where not exists (select 1 from jsonb_array_elements(v_of -> 'responsables') r(v)
                      where (r.v ->> 'vendedor_id') = (a.e ->> 'analista_id'))
     and (a.e -> 'conversion') is distinct from (d.e -> 'conversion');
  if v_n <> 0 then
    raise exception 'POSTFLIGHT: % analistas que la oficial no tiene VIERON CAMBIAR su cifra; se les esta fabricando o borrando un numero', v_n;
  end if;

  -- 4) Declara que delego.
  if (v_conv ->> 'fuente') is distinct from 'mensual'
     or (v_conv -> 'sellado') is distinct from (v_of #> '{cierre,cerrado}')
     or (v_conv ->> 'ajuste_aplicado')::boolean is not true
     or (v_conv ->> 'es_mes_calendario')::boolean is not true then
    raise exception 'POSTFLIGHT: delego pero no lo declara: %', v_conv;
  end if;

  -- 5) HOY, sin deuda, ninguna cifra se mueve, ni arriba ni en las fichas.
  if (v_antes #> '{resumen,conversion,nucleo_divisor}') is distinct from (v_conv -> 'nucleo_divisor')
     or (v_antes #> '{resumen,conversion,nucleo_numerador}') is distinct from (v_conv -> 'nucleo_numerador')
     or (v_antes #> '{resumen,conversion,nucleo_conversion_pct}') is distinct from (v_conv -> 'nucleo_conversion_pct') then
    raise exception 'POSTFLIGHT: el resumen SE MOVIO HOY, y hoy no hay deuda. antes % · despues %',
      v_antes #> '{resumen,conversion}', v_conv;
  end if;
  select count(*)::int into v_n
    from jsonb_array_elements(v_antes -> 'analistas') a(e)
    join jsonb_array_elements(v_despues -> 'analistas') d(e)
      on (a.e ->> 'analista_id') = (d.e ->> 'analista_id')
   where (a.e #> '{conversion,nucleo_divisor}')        is distinct from (d.e #> '{conversion,nucleo_divisor}')
      or (a.e #> '{conversion,nucleo_numerador}')      is distinct from (d.e #> '{conversion,nucleo_numerador}')
      or (a.e #> '{conversion,nucleo_conversion_pct}') is distinct from (d.e #> '{conversion,nucleo_conversion_pct}');
  if v_n <> 0 then
    raise exception 'POSTFLIGHT: % fichas cambiaron HOY, y hoy no hay deuda que lo justifique', v_n;
  end if;
  if jsonb_array_length(v_antes -> 'analistas') <> jsonb_array_length(v_despues -> 'analistas') then
    raise exception 'POSTFLIGHT: cambio el numero de fichas';
  end if;

  -- 6) Nada mas del payload se movio.
  v_a := (v_antes - 'generado_en' - 'analistas')
           #- '{resumen,conversion}';
  v_d := (v_despues - 'generado_en' - 'analistas')
           #- '{resumen,conversion}';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: cambio algo fuera de la cifra y su declaracion. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 7) Un rango parcial NO delega.
  if (v_parcial #>> '{resumen,conversion,fuente}') is distinct from 'rango_vivo'
     or (v_parcial #>> '{resumen,conversion,es_mes_calendario}')::boolean is not false
     or (v_parcial #> '{resumen,conversion,sellado}') <> 'null'::jsonb
     or (v_parcial #>> '{resumen,conversion,ajuste_aplicado}')::boolean is not false then
    raise exception 'POSTFLIGHT: un rango parcial esta delegando, y no debe: %',
      v_parcial #> '{resumen,conversion}';
  end if;

  -- 8) Dueno, definer, volatilidad y search_path, intactos.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('private.metricas_distribucion_leads_v3_core(date,date,timestamptz)')
                    and p.proowner = 'postgres'::regrole
                    and not p.prosecdef and p.provolatile = 's'
                    and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 8b) Sin identidad NO revienta: sigue respondiendo, en vivo y declarandolo.
  if v_sin_identidad is null then
    raise exception 'POSTFLIGHT: sin identidad el motor dejo de responder; los gates que lo llaman directo se romperian';
  end if;
  if (v_sin_identidad ->> 'fuente') is distinct from 'rango_vivo' then
    raise exception 'POSTFLIGHT: sin identidad dice fuente %, y no puede haber delegado', v_sin_identidad ->> 'fuente';
  end if;
  if (v_sin_identidad ->> 'es_mes_calendario')::boolean is not true then
    raise exception 'POSTFLIGHT: sin identidad el rango sigue siendo mes calendario; lo que falta es el actor, no el rango';
  end if;

  -- 9) Sigue FUERA del censo de contadores crudos.
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'private.metricas_distribucion_leads_v3_core(date,date,timestamp with time zone)') then
    raise exception 'POSTFLIGHT: el motor ENTRO al censo; hay que declararlo aqui mismo';
  end if;
end;
$postflight$;

comment on function private.metricas_distribucion_leads_v3_core(date,date,timestamptz) is
  'Motor v3 de la distribucion de leads. Desde la Ola 1b (22/09/2026), cuando el rango es un '
  'mes calendario completo DELEGA nucleo_divisor, nucleo_numerador y nucleo_conversion_pct en '
  'crm.conversion_mensual_fn —en el resumen y en la ficha de cada analista, emparejando por '
  'analista_id— y lo declara en resumen.conversion (fuente=mensual, sellado=<lo que diga la '
  'oficial>, ajuste_aplicado=true). Fuera de esa condicion calcula en vivo y lo declara. '
  'nucleo_referidos_recibidos y la punteria PEN/USD no se delegan: son otras medidas.';

select 'puerta5-delega-en-la-mensual' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       (select payload #> '{resumen,conversion}' from _p5b_despues) as conversion;

commit;
