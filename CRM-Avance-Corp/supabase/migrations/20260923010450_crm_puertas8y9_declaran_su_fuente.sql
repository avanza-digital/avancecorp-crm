-- =========================================================================
-- CRM · Ola 2 · Las puertas #8 y #9 DECLARAN su fuente
-- =========================================================================
-- QUE HACE: anade las cuatro claves del contrato de la unificacion al payload
-- de `crm.cumplimiento_metas_sin_cartera_fn(date)` —en sus DOS ramas— y de
-- `crm.series_comerciales_fn(integer)`. Nada mas.
--
-- 🔑 NO CAMBIA NI UN NUMERO, y estas dos ademas NO NECESITAN DELEGAR: medido el
--    22/09 con 2 puntos de deuda plantados en produccion, la #8 baja el
--    numerador de 6 a 4 igual que la oficial (usa `conversion_con_ajuste`), y
--    la #9 ya pide su serie a la capa publicada
--    (`private.conversion_mensual_pct_para_series`). Lo unico que les faltaba
--    era DECIRLO.
--
-- POR QUE ENTRAN SIN PESTILLO, al contrario que la #5 y la #7: **ninguna de las
-- dos tiene consumidor en el front**. Comprobado el 22/09:
--   · `cumplimiento_metas_sin_cartera_fn` solo aparece en `database.types.ts`.
--   · `series_comerciales_fn` tampoco tiene consumidor: `series-comerciales.ts`
--     es un modulo HUERFANO a proposito (su propia cabecera lo dice) y el
--     unico otro match es un comentario en `demo.ts`.
-- Sin `strictObject` que las valide, una clave nueva no puede tumbar nada.
--
-- POR QUE LA #8 DICE `fuente: 'rango_vivo'` EN SU RAMA ABIERTA: porque no le
-- pregunta a `crm.conversion_mensual_fn`; calcula sobre
-- `private.conversion_mensual_por_vendedor` y aplica el ajuste ella misma.
-- Coincide con la oficial, pero decir 'mensual' seria mentir sobre de donde
-- salio la cifra, y toda esta unificacion trata precisamente de eso.
--
-- MEDIDO EN PRODUCCION EL 22/09/2026, y fijado en el preflight:
--   · #8 md5(pg_get_functiondef) = b7192138b237571c9955d021aff0920a
--        dueno postgres · NI declarada NI en el censo -> no hay huella que
--        re-sellar; el postflight exige que siga fuera.
--   · #9 md5(pg_get_functiondef) = 91ea3ad984ce63060e21d8da51b75255
--        dueno postgres · clase `mixta` y **SI en el censo** -> esta migracion
--        re-sella su declaracion y refresca el sello.
--
-- REVERSA: volver a declarar los dos cuerpos sin las cuatro claves; para la #9,
-- ademas, escribir su huella anterior en la exencion, quitar el texto anadido a
-- `razon` y refrescar `private.analitica_lc_sello`.
-- =========================================================================

begin;

set local statement_timeout = '180s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)');
  if v_md5 is distinct from 'b7192138b237571c9955d021aff0920a' then
    raise exception 'PREFLIGHT: la #8 no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.series_comerciales_fn(integer)');
  if v_md5 is distinct from '91ea3ad984ce63060e21d8da51b75255' then
    raise exception 'PREFLIGHT: la #9 no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid in (to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)'),
                                  to_regprocedure('crm.series_comerciales_fn(integer)'))
                    and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 's'
                 having count(*) = 2) then
    raise exception 'PREFLIGHT: dueno, definer o volatilidad inesperados';
  end if;
end;
$preflight$;

create temp table _p89_antes (puerta text, payload jsonb) on commit drop;

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
    insert into _p89_antes (puerta, payload)
    select 'p8', crm.cumplimiento_metas_sin_cartera_fn(
                   date_trunc('month', (now() at time zone 'America/Lima'))::date);
    insert into _p89_antes (puerta, payload)
    select 'p9', crm.series_comerciales_fn(6);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
end;
$antes$;

-- ---------------------------------------------------------------------------
-- (b) Los dos cuerpos, generados POR ANCLAS sobre los vivos acreditados arriba.
-- ---------------------------------------------------------------------------
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
      -- DECLARACION (Ola 2, 22/09/2026). RAMA DEL MES SELLADO: lo que se
      -- publica sale de la FOTO de `crm.periodos_cerrados`, no de un recalculo.
      --   es_mes_calendario: `p_periodo` es siempre el dia 1 de un mes, asi que
      --     por construccion esta puerta solo habla de meses completos.
      --   fuente: 'mensual' — la foto oficial.
      --   sellado: true — es justo la rama del `if found`.
      --   ajuste_aplicado: true — la deuda se descuenta al sellar.
      'es_mes_calendario', true,
      'fuente', 'mensual',
      'sellado', true,
      'ajuste_aplicado', true,
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
    -- DECLARACION (Ola 2, 22/09/2026). RAMA DEL MES ABIERTO: la cifra se
    -- CALCULA aqui, sobre `private.conversion_mensual_por_vendedor`, pero
    -- SI resta la deuda con `private.conversion_con_ajuste`.
    --   fuente: 'rango_vivo' — no se le pidio a `crm.conversion_mensual_fn`;
    --     decir 'mensual' seria mentir sobre de donde salio.
    --   ajuste_aplicado: true — y eso es lo que la hace coincidir con la
    --     oficial. Medido el 22/09 con 2 puntos de deuda plantados: esta
    --     puerta bajo el numerador de 6 a 4, igual que la oficial.
    'es_mes_calendario', true,
    'fuente', 'rango_vivo',
    'sellado', false,
    'ajuste_aplicado', true,
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
$function$;

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
  -- F6.c (v2, tras el P0 de Codex): la conversion OFICIAL de cada mes se pide
  -- A LA CAPA PUBLICADA (`crm.conversion_mensual_fn`, la de las pantallas), que sabe
  -- servir la FOTO SELLADA de un mes cerrado, restar los ajustes pendientes del
  -- mes abierto y redondear a DOS decimales. Recalcular aqui del nucleo habria
  -- creado la tercera copia de esa regla - lo que esta fase vino a matar.
  -- El rol sin permiso sobre la oficial (coordinador) recibe NULL, no un error:
  -- su serie de cohorte sigue viajando entera.
  serie_mensual_oficial as materialized (
    select m2.mes,
           (select private.conversion_mensual_pct_para_series(m2.mes)) as pct
    from (select (date_trunc('month', (now() at time zone 'America/Lima'))::date
                  - make_interval(months => (p_meses - 1 - g.n)))::date as mes
            from generate_series(0, p_meses - 1) as g(n)) m2
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
    -- DECLARACION (Ola 2, 22/09/2026). Esta puerta publica DOS series y solo
    -- una es «la conversion»:
    --   `conversion_mensual_pct` sale de `private.conversion_mensual_pct_para_series`,
    --     que pregunta a la CAPA PUBLICADA. Por eso `fuente: 'mensual'`.
    --   `conversion_cohorte_pct` es OTRA medida (clientes entre leads
    --     recibidos del mes) y queda fuera de la unificacion por decision
    --     expresa: no es la conversion ponderada del nucleo.
    --   es_mes_calendario: true — la serie son meses completos, uno por punto.
    --   sellado: null — no hay UN mes del que hablar; la serie cruza meses
    --     sellados y abiertos. `null` es «no aplica», no `false`.
    --   ajuste_aplicado: true — la capa publicada resta la deuda.
    'es_mes_calendario', true,
    'fuente', 'mensual',
    'sellado', null,
    'ajuste_aplicado', true,
    'version', 2,
    'conversion_mensual_pct', (select jsonb_agg(nm.pct order by nm.mes) from serie_mensual_oficial nm),
    'generado_en', v_ahora,
    'zona', 'America/Lima',
    'meses', jsonb_agg(s.clave order by s.orden),
    'nuevos', jsonb_agg(s.nuevos order by s.orden),
    'cohorte_clientes', jsonb_agg(s.cohorte order by s.orden),
    'cierres', jsonb_agg(s.n_cierres order by s.orden),
    'capital_pen', jsonb_agg(s.capital_pen order by s.orden),
    'capital_usd', jsonb_agg(s.capital_usd order by s.orden),
    -- Espejo exacto del redondeo del front: Math.round(x*1000)/10 (1 decimal).
    'conversion_cohorte_pct', jsonb_agg(
      case when s.nuevos > 0 then round(1000.0 * s.cohorte / s.nuevos) / 10.0 else 0 end
      order by s.orden)
  )
  into v_payload
  from serie s;

  return v_payload;
end;
$function$;

-- ---------------------------------------------------------------------------
-- (c) Re-sellar la declaracion de la #9 (la unica de las dos que esta censada),
--     con la normalizacion DEL CENSO (cuerpo en `lower`, sin comentarios).
--     Huella anterior, para la reversa: 364a56f330309e57c903867b1ac990cd
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = e.razon || ' Ola 2 (22/09/2026): DECLARA su fuente sin cambiar ninguna cifra '
                        || '(es_mes_calendario=true, fuente=mensual porque su serie de conversion '
                        || 'sale de private.conversion_mensual_pct_para_series, sellado=null porque '
                        || 'la serie cruza varios meses, ajuste_aplicado=true). conversion_cohorte_pct '
                        || 'es otra medida y queda fuera de la unificacion.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'crm.series_comerciales_fn(integer)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- ---------------------------------------------------------------------------
-- (d) POSTFLIGHT
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok text; a8 jsonb; a9 jsonb; d8 jsonb; d9 jsonb; v_a jsonb; v_d jsonb;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select payload into a8 from _p89_antes where puerta = 'p8';
  select payload into a9 from _p89_antes where puerta = 'p9';

  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);
  begin
    d8 := crm.cumplimiento_metas_sin_cartera_fn(
            date_trunc('month', (now() at time zone 'America/Lima'))::date);
    d9 := crm.series_comerciales_fn(6);
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- 1) NI UN NUMERO MOVIDO, en ninguna de las dos.
  v_a := a8 - 'generado_en';
  v_d := (d8 - 'generado_en') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la #8 movio algo fuera de las cuatro claves. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;
  v_a := a9 - 'generado_en';
  v_d := (d9 - 'generado_en') - 'es_mes_calendario' - 'fuente' - 'sellado' - 'ajuste_aplicado';
  if v_a is distinct from v_d then
    raise exception 'POSTFLIGHT: la #9 movio algo fuera de las cuatro claves. Bloques distintos: %',
      (select string_agg(k, ', ' order by k) from jsonb_object_keys(v_a) k
        where (v_a -> k) is distinct from (v_d -> k));
  end if;

  -- 2) Las cuatro claves viajan, con los valores que manda cada caso.
  --    #8, mes ABIERTO (hoy no hay ningun mes sellado): calcula, pero ajusta.
  if (d8 ->> 'es_mes_calendario')::boolean is not true then
    raise exception 'POSTFLIGHT #8: es_mes_calendario deberia ser true siempre (p_periodo es un mes)';
  end if;
  if (d8 ->> 'ajuste_aplicado')::boolean is not true then
    raise exception 'POSTFLIGHT #8: usa conversion_con_ajuste, asi que ajuste_aplicado es true';
  end if;
  if (d8 ->> 'fuente') not in ('mensual', 'rango_vivo') then
    raise exception 'POSTFLIGHT #8: fuente fuera del contrato: %', d8 ->> 'fuente';
  end if;
  --    Y las dos ramas tienen que ser COHERENTES entre si.
  if (d8 #>> '{cierre,cerrado}')::boolean is true then
    if (d8 ->> 'fuente') is distinct from 'mensual' or (d8 ->> 'sellado')::boolean is not true then
      raise exception 'POSTFLIGHT #8: el mes esta sellado y la declaracion dice % / %',
        d8 ->> 'fuente', d8 ->> 'sellado';
    end if;
  else
    if (d8 ->> 'fuente') is distinct from 'rango_vivo' or (d8 ->> 'sellado')::boolean is not false then
      raise exception 'POSTFLIGHT #8: el mes esta abierto y la declaracion dice % / %',
        d8 ->> 'fuente', d8 ->> 'sellado';
    end if;
  end if;

  --    #9: pide su serie a la capa publicada.
  if (d9 ->> 'es_mes_calendario')::boolean is not true
     or (d9 ->> 'fuente') is distinct from 'mensual'
     or d9 -> 'sellado' <> 'null'::jsonb
     or (d9 ->> 'ajuste_aplicado')::boolean is not true then
    raise exception 'POSTFLIGHT #9: declaracion inesperada: %',
      jsonb_build_object('es_mes_calendario', d9 -> 'es_mes_calendario', 'fuente', d9 -> 'fuente',
                         'sellado', d9 -> 'sellado', 'ajuste_aplicado', d9 -> 'ajuste_aplicado');
  end if;
  --    Y su serie oficial sigue ahi: declarar no puede haberla vaciado.
  if d9 -> 'conversion_mensual_pct' is null then
    raise exception 'POSTFLIGHT #9: desaparecio conversion_mensual_pct';
  end if;

  -- 3) Dueno, definer, volatilidad y search_path, intactos en las dos.
  if (select count(*) from pg_proc p
       where p.oid in (to_regprocedure('crm.cumplimiento_metas_sin_cartera_fn(date)'),
                       to_regprocedure('crm.series_comerciales_fn(integer)'))
         and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 's'
         and p.proconfig @> array['search_path=""']) <> 2 then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;

  -- 4) La #8 sigue FUERA del censo; la #9 sigue DENTRO y con huella vigente
  --    (lo segundo ya lo garantiza el assert de arriba).
  if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto = 'crm.cumplimiento_metas_sin_cartera_fn(date)') then
    raise exception 'POSTFLIGHT: la #8 ENTRO al censo; hay que declararla aqui mismo';
  end if;
  if not exists (select 1 from private.contadores_crudos_leads_citas() c
                  where c.objeto = 'crm.series_comerciales_fn(integer)' and c.declarada and c.huella_ok) then
    raise exception 'POSTFLIGHT: la #9 salio del censo o su huella no cuadra';
  end if;
end;
$postflight$;

comment on function crm.cumplimiento_metas_sin_cartera_fn(date) is
  'Cumplimiento de metas SIN cartera. Desde la Ola 2 (22/09/2026) declara de donde sale su '
  'cifra: en la rama del mes SELLADO, de la foto de crm.periodos_cerrados (fuente=mensual, '
  'sellado=true); en la del mes ABIERTO, de private.conversion_mensual_por_vendedor con '
  'private.conversion_con_ajuste aplicado (fuente=rango_vivo, sellado=false). En las dos, '
  'es_mes_calendario=true —p_periodo es siempre un mes— y ajuste_aplicado=true: esta puerta '
  'SI resta la deuda de los cierres anulados, y por eso no discrepa de la oficial.';

comment on function crm.series_comerciales_fn(integer) is
  'Series comerciales de los ultimos N meses. Desde la Ola 2 (22/09/2026) declara que su '
  'serie de conversion (conversion_mensual_pct) sale de la CAPA PUBLICADA, via '
  'private.conversion_mensual_pct_para_series (fuente=mensual, ajuste_aplicado=true), y que '
  'sellado es null porque la serie cruza meses sellados y abiertos: no hay UN mes del que '
  'hablar. conversion_cohorte_pct es otra medida —clientes entre leads recibidos del mes— y '
  'queda deliberadamente fuera de la unificacion.';

select 'puertas8y9-declaran-su-fuente' as migracion,
       private.assert_analitica_leads_citas() as trinquete;

commit;
