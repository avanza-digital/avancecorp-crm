-- =========================================================================
-- CRM · REVERSION · La declaracion de la puerta #8 se deshace
-- =========================================================================
-- 🔴 QUE PASO, SIN ADORNOS. La migracion `20260923010450` anadio las cuatro
--    claves del contrato al payload de `crm.cumplimiento_metas_sin_cartera_fn`.
--    Se comprobo antes que esa funcion NO tiene consumidor en el front —solo
--    aparece en `database.types.ts`— y era cierto.
--
--    Lo que NO se comprobo: **`crm.cumplimiento_metas_fn` (la puerta #7)
--    construye su payload SOBRE el de la #8**. Al declarar la #8 quedo
--    declarada tambien la #7, que SI tiene consumidor: y el bundle vivo
--    (`build-20260922T221442353Z` = `7d65fcdb484f`) valida
--    `CumplimientoMetasSchema` con **`v.strictObject`** sin esas cuatro claves
--    (`app/src/lib/objetivos.ts:346` de ese commit).
--
--    Cuatro claves desconocidas -> valibot rechaza el payload ENTERO ->
--    **Metas y Ranking de gerencia se quedaron sin datos en produccion**,
--    entre las 01:05 y las 01:18 UTC del 23/09/2026 (unos 13 minutos).
--
--    Se detecto haciendo el censo final de declaraciones: la #7 aparecio
--    declarando sin que nadie la hubiera tocado. Esa sorpresa era el sintoma.
--
-- 🔑 LA LECCION, para que no se repita: «no tiene consumidor en el front» se
--    comprueba sobre la funcion QUE SE TOCA **y sobre todas las que la
--    envuelven**. Un `grep` del nombre en `app/src` no ve la herencia dentro
--    de la base. Antes de declarar, preguntar a `pg_proc` quien mas construye
--    su payload a partir de este.
--
-- QUE HACE ESTA MIGRACION: devuelve `crm.cumplimiento_metas_sin_cartera_fn` a
-- su cuerpo anterior, byte a byte (md5 b7192138b237571c9955d021aff0920a). Ya se
-- aplico en caliente para cortar el incidente; esta migracion deja constancia y
-- hace que el arbol y produccion digan lo mismo.
--
-- LO QUE SE QUEDA: la declaracion de la #9 (`crm.series_comerciales_fn`), que
-- no tiene consumidor ni directo ni heredado, sigue puesta y con su huella
-- re-sellada. No se revierte.
--
-- CUANDO VUELVE LA DECLARACION DE LA #8: con el mismo release que desbloquea la
-- #5 y la #7. `objetivos.ts` en `main` (commit `c2c9274b`) ya lleva las cuatro
-- claves como `v.optional`; en cuanto ese bundle este vivo, las dos entran
-- juntas y con pestillo.
-- =========================================================================

begin;

set local statement_timeout = '60s';

do $preflight$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)');
  if v_md5 = 'b7192138b237571c9955d021aff0920a' then
    raise notice 'La reversion ya estaba aplicada en caliente; esta migracion es idempotente.';
  end if;
end;
$preflight$;

CREATE OR REPLACE FUNCTION crm.cumplimiento_metas_sin_cartera_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_periodo_id uuid;
  v_revision integer := 0;
  v_publicada_en timestamptz;
  v_ini timestamptz;
  v_fin timestamptz;
  v_payload jsonb;
  v_factor numeric;
  v_cierre crm.periodos_cerrados%rowtype;
begin
  if v_uid is null
    or (private.rol_crm(v_uid) is null and not private.es_lector_global()) then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if p_periodo is null or p_periodo<>date_trunc('month',p_periodo)::date then
    raise exception 'El periodo debe ser el primer dia del mes' using errcode='22023';
  end if;

  -- MES CERRADO: se sirve la foto. Mismo recorte que la conversion, del mismo
  -- helper, para que las dos pantallas no puedan enseñar poblaciones distintas
  -- del mismo mes.
  select * into v_cierre from crm.periodos_cerrados pc where pc.periodo = p_periodo;
  if found then
    select mp.publicada_en into v_publicada_en
    from crm.meta_periodos mp
    where mp.periodo = p_periodo and mp.revision = v_cierre.meta_revision;

    select jsonb_build_object(
      'version', 1, 'periodo', p_periodo, 'revision', v_cierre.meta_revision,
      'publicada_en', v_publicada_en,
      'fuentes_reales', jsonb_build_object(
        'capital_y_contratos', 'contratos_confirmados',
        'conversion', 'leads_recibidos_ponderado'
      ),
      'ponderacion_referido', v_cierre.ponderacion_referido,
      'cierre', jsonb_build_object(
        'cerrado', true,
        'cerrado_en', v_cierre.cerrado_en,
        'automatico', v_cierre.automatico
      ),
      'vendedores', coalesce((
        select jsonb_agg(jsonb_build_object(
          'vendedor_id', v.vendedor_id, 'nombre', v.nombre_completo,
          'supervisor_id', v.supervisor_id, 'supervisor_nombre', v.supervisor_nombre,
          'conversion_objetivo', v.conversion_objetivo,
          'conversion_real', v.conversion_pct,
          'convertidos', v.cierres_no_referidos + v.cierres_referidos,
          'resueltos', v.divisor,
          'numerador', v.numerador,
          'cierres_no_referidos', v.cierres_no_referidos,
          'cierres_referidos', v.cierres_referidos,
          -- Lo que se le descontó al sellar por deudas de meses anteriores. El
          -- bruto se recupera sumándolo al numerador: la foto es auditable.
          'ajuste', jsonb_build_object(
            'aplicado', v.ajuste_numerador,
            'aplicado_pen', v.ajuste_pen,
            'aplicado_usd', v.ajuste_usd,
            'pendiente', 0),
          'detalles', v.detalles
        ) order by v.supervisor_nombre, v.nombre_completo)
        from private.cierre_mes_visible(p_periodo, v_uid) v
      ), '[]'::jsonb)
    ) into v_payload;
    return v_payload;
  end if;

  -- Mes ABIERTO: el comportamiento de siempre.
  v_ini:=p_periodo::timestamp at time zone 'America/Lima';
  v_fin:=(p_periodo+interval '1 month')::timestamp at time zone 'America/Lima';

  select mp.id,mp.revision,mp.publicada_en
    into v_periodo_id,v_revision,v_publicada_en
  from crm.meta_periodos mp where mp.periodo=p_periodo
  order by mp.revision desc limit 1;
  v_revision:=coalesce(v_revision,0);
  v_factor:=private.peso_referido_conversion(p_periodo);

  with reales as (
    select r.vendedor_id, r.categoria, r.moneda, r.contratos_real, r.capital_real
    from private.produccion_mes_por_vendedor(v_ini, v_fin, v_periodo_id) r
  ), conversiones as (
    -- El MISMO neto que publica crm.conversion_mensual_fn: si esta pantalla
    -- enseñara el bruto, el mismo asesor tendria dos porcentajes distintos otra
    -- vez — la deuda que la migracion 20260813212332 vino a borrar.
    select cm.analista_id as vendedor_id,
      (cm.cierres_no_referidos+cm.cierres_referidos)::integer as convertidos,
      cm.divisor::integer as resueltos,
      -- ⚠️ `pd.numerador`, NO `pd.pendiente`. Aqui `pd` es la FUNCION
      -- `private.ajuste_pendiente_por_vendedor()`, que devuelve
      -- (vendedor_id, numerador, capital_pen, capital_usd, origenes) — no tiene
      -- ninguna columna `pendiente`. El bloque de la conversion, mas arriba, si
      -- usa `pd.pendiente`, pero alli `pd` es una CTE que renombra
      -- `ap.numerador as pendiente`: mismo alias, dos cosas distintas.
      --
      -- 🔴 ESTO ESTUVO ROTO Y EN VERDE. plpgsql no valida el SQL de un cuerpo al
      -- crearlo, asi que la funcion se creaba sin protestar y reventaba con
      -- 42703 en la PRIMERA llamada, para TODOS los roles: la pantalla de metas
      -- entera. El oraculo daba 20/20 porque nunca la llamaba — solo la
      -- nombraba en un comentario. Lo cazo el gate de RLS en la branch.
      private.conversion_con_ajuste(cm.numerador, pd.numerador) as numerador,
      cm.cierres_no_referidos,
      cm.cierres_referidos,
      case when cm.divisor > 0
        then round(100.0 * private.conversion_con_ajuste(cm.numerador, pd.numerador)
                   / cm.divisor, 2) end as conversion_real,
      coalesce(pd.numerador, 0::numeric) as ajuste_pendiente
    from private.conversion_mensual_por_vendedor(
      v_ini,v_fin,true,'{}'::uuid[],v_factor) cm
    left join private.ajuste_pendiente_por_vendedor() pd
      on pd.vendedor_id = cm.analista_id
  ), visibles as (
    select mv.*,p.nombre_completo,s.nombre_completo as supervisor_nombre
    from crm.metas_vendedor mv
    join public.perfiles p on p.id=mv.vendedor_id
    join public.perfiles s on s.id=mv.supervisor_id
    where mv.meta_periodo_id=v_periodo_id
      and (private.es_lector_global()
        or mv.vendedor_id in (select private.vendedor_ids_visibles(v_uid)))
  )
  select jsonb_build_object(
    'version',1,'periodo',p_periodo,'revision',v_revision,
    'publicada_en',v_publicada_en,
    'fuentes_reales',jsonb_build_object(
      'capital_y_contratos','contratos_confirmados',
      'conversion','leads_recibidos_ponderado'
    ),
    'ponderacion_referido',v_factor,
    'cierre', jsonb_build_object('cerrado', false),
    'vendedores',coalesce((select jsonb_agg(jsonb_build_object(
      'vendedor_id',mv.vendedor_id,'nombre',mv.nombre_completo,
      'supervisor_id',mv.supervisor_id,'supervisor_nombre',mv.supervisor_nombre,
      'conversion_objetivo',mv.conversion_objetivo,
      'conversion_real',cv.conversion_real,
      'convertidos',coalesce(cv.convertidos,0),'resueltos',coalesce(cv.resueltos,0),
      'numerador',coalesce(cv.numerador,0),
      'cierres_no_referidos',coalesce(cv.cierres_no_referidos,0),
      'cierres_referidos',coalesce(cv.cierres_referidos,0),
      'ajuste',jsonb_build_object('pendiente',coalesce(cv.ajuste_pendiente,0)),
      'detalles',(select jsonb_agg(jsonb_build_object(
        'categoria',d.categoria,'moneda',d.moneda,
        'capital_objetivo',d.capital_objetivo,
        'capital_real',coalesce(r.capital_real,0),
        'capital_cumplimiento_pct',case when d.capital_objetivo>0
          then round(100.0*coalesce(r.capital_real,0)/d.capital_objetivo,2) end,
        'contratos_objetivo',d.contratos_objetivo,
        'contratos_real',coalesce(r.contratos_real,0),
        'contratos_cumplimiento_pct',case when d.contratos_objetivo>0
          then round(100.0*coalesce(r.contratos_real,0)/d.contratos_objetivo,2) end
      ) order by array_position(array['nuevo','renovacion','upgrade'],d.categoria),d.moneda)
      from crm.metas_vendedor_detalle d
      left join reales r on r.vendedor_id=mv.vendedor_id
        and r.categoria=d.categoria and r.moneda=d.moneda
      where d.meta_vendedor_id=mv.id)
    ) order by mv.supervisor_nombre,mv.nombre_completo) from visibles mv
    left join conversiones cv on cv.vendedor_id=mv.vendedor_id),'[]'::jsonb)
  ) into v_payload;
  return v_payload;
end;
$function$

;

do $postflight$
declare
  v_md5 text; v_claves text;
  v_claims text := current_setting('request.jwt.claims', true);
  v_ger uuid;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)');
  if v_md5 is distinct from 'b7192138b237571c9955d021aff0920a' then
    raise exception 'POSTFLIGHT: el cuerpo restaurado no es el original (md5 %)', v_md5;
  end if;

  -- Y LO QUE DE VERDAD IMPORTA: que la puerta #7 vuelva a publicar EXACTAMENTE
  -- las nueve claves que el bundle vivo conoce, ni una mas.
  select e.perfil_id into v_ger from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_ger, 'role', 'authenticated')::text, true);
  begin
    select string_agg(k, ',' order by k) into v_claves
      from jsonb_object_keys(crm.cumplimiento_metas_fn(
             date_trunc('month', (now() at time zone 'America/Lima'))::date)) k;
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  if v_claves is distinct from 'cierre,fuentes_reales,fuera_ranking,periodo,ponderacion_referido,publicada_en,revision,vendedores,version' then
    raise exception 'POSTFLIGHT: la puerta #7 publica %, y el bundle vivo solo acepta las nueve del contrato anterior', v_claves;
  end if;

  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo';
  end if;
end;
$postflight$;

select 'puerta8-revierte-su-declaracion' as migracion,
       private.assert_analitica_leads_citas() as trinquete;

commit;
