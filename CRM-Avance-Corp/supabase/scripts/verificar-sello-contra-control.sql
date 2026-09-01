-- =====================================================================
-- EL 10/09: comparar el sello REAL contra la linea base del ensayo
-- =====================================================================
-- Se corre DESPUES de que el cron de las 09:20 (Lima) selle agosto.
-- No escribe nada: es un SELECT.
--
-- ⚠️ QUE NO ES: no es un oraculo de «tiene que salir identico». Agosto sigue
-- ABIERTO hasta el sello (anulaciones, republicacion de metas, operaciones de
-- cartera con periodo de agosto, cambios de atribucion), asi que una huella
-- distinta puede ser perfectamente legitima. Lo que esto hace es DISTINGUIR
-- por que cambio.
--
-- COMO SE LEE:
--   'IDENTICO'          -> el sello es exactamente el ensayado. Fase 2 cerrada.
--   'DIFIERE-POR-DATO'  -> la foto cambio Y las entradas tambien: entraron
--                          correcciones legitimas de agosto. Mirar `que_cambio`
--                          y explicar cada una. NO es un fallo.
--   'DIFIERE-SIN-DATO'  -> ROJO: la foto cambio con las MISMAS entradas. Eso es
--                          un cambio de logica y hay que pararlo todo.
--   'SIN-RELLENAR'      -> faltan pegar las constantes del ensayo.
--   'AUN-NO-SELLADO'    -> el cron todavia no ha corrido.
--
-- ⚠️ Correrlo con las MISMAS marcas que el ensayo, o las huellas no comparan:
--   set local TimeZone = 'UTC'; set local DateStyle = 'ISO, MDY';
-- (ya van incluidas abajo)
-- =====================================================================

set local TimeZone = 'UTC';
set local DateStyle = 'ISO, MDY';

with control as (
  select
    -- Linea base medida por el ensayo del 2026-09-01 00:32 Lima
    -- (supabase/scripts/ensayo-cierre-agosto-definitivo.sql, v2).
    -- Si se vuelve a correr el ensayo la vispera (09/09), REEMPLAZAR por
    -- aquellos valores: seran un control mas proximo al sello.
    '656c6b6e00f2d2a6867eb184b9f5c02b'::text as huella_foto,
    'b0151ec6b43167fe0d9754971dcda1af'::text as huella_conversion,
    '0a74291df8d508b8e76ad8b5bb33420b'::text as huella_produccion,
    '278a52ed5ef8400885829e2451ff36c1'::text as huella_metas,
    'b31a363a809e49f7919c8d681c630acc'::text as huella_metas_detalle,
    'd0e143e39a5ddd361790b02f5197573d'::text as huella_nombres,
    '18f854b217d390ef7916cfeb407b8b74'::text as huella_deudas,
    18::int                                  as personas,
    '2026-09-01 00:32 Lima'::text            as ensayado_el
),
periodo as (select date '2026-08-01' as p),
ctx as (
  select p,
         p::timestamp at time zone 'America/Lima' as ini,
         (p + interval '1 month')::timestamp at time zone 'America/Lima' as fin,
         private.peso_referido_conversion(p) as factor,
         (select mp.id from crm.meta_periodos mp
           where mp.periodo = p order by mp.revision desc limit 1) as periodo_id,
         (select mp.revision from crm.meta_periodos mp
           where mp.periodo = p order by mp.revision desc limit 1) as revision
  from periodo
),
hoy as (
  select
    (select count(*)::int from crm.cierre_mes_vendedor f, periodo where f.periodo = periodo.p) as personas,
    (select md5(coalesce(string_agg(md5(f::text), '|' order by f.vendedor_id), 'vacio'))
       from crm.cierre_mes_vendedor f, periodo where f.periodo = periodo.p) as huella_foto,
    (select md5(coalesce(string_agg(md5(c::text), '|' order by c.analista_id), 'vacio'))
       from ctx, private.conversion_mensual_por_vendedor(ctx.ini, ctx.fin, true, '{}'::uuid[], ctx.factor) c) as huella_conversion,
    (select md5(coalesce(string_agg(md5(r::text), '|' order by r.vendedor_id, r.categoria, r.moneda), 'vacio'))
       from ctx, private.produccion_mes_por_vendedor(ctx.ini, ctx.fin, ctx.periodo_id) r) as huella_produccion,
    (select md5(coalesce(string_agg(md5((to_jsonb(mv) - 'creado_en' - 'actualizado_en')::text), '|' order by mv.id), 'vacio'))
       from ctx, crm.metas_vendedor mv where mv.meta_periodo_id = ctx.periodo_id) as huella_metas,
    (select md5(coalesce(string_agg(md5((to_jsonb(d) - 'creado_en' - 'actualizado_en')::text), '|' order by d.id), 'vacio'))
       from ctx, crm.metas_vendedor_detalle d
       join crm.metas_vendedor mv on mv.id = d.meta_vendedor_id
       where mv.meta_periodo_id = ctx.periodo_id) as huella_metas_detalle,
    (select md5(coalesce(string_agg(md5(pf.id::text || coalesce(pf.nombre_completo,'')), '|' order by pf.id), 'vacio'))
       from ctx, public.perfiles pf
       where pf.id in (select mv.vendedor_id from crm.metas_vendedor mv where mv.meta_periodo_id = ctx.periodo_id
                       union
                       select mv.supervisor_id from crm.metas_vendedor mv where mv.meta_periodo_id = ctx.periodo_id)) as huella_nombres,
    (select md5(coalesce(string_agg(md5((to_jsonb(a) - 'creado_en' - 'saldado_en')::text), '|' order by a.id), 'vacio'))
       from crm.ajustes_mes_cerrado a) as huella_deudas
),
sello as (
  select pc.periodo, pc.automatico, pc.cerrado_por, pc.cerrado_en,
         pc.ponderacion_referido, pc.meta_revision, pc.cobertura
  from crm.periodos_cerrados pc, periodo where pc.periodo = periodo.p
),
dx as (
  select c.*, h.personas as personas_hoy,
         h.huella_foto as foto_hoy,
         (h.huella_conversion    <> c.huella_conversion)    as d_conv,
         (h.huella_produccion    <> c.huella_produccion)    as d_prod,
         (h.huella_metas         <> c.huella_metas)         as d_metas,
         (h.huella_metas_detalle <> c.huella_metas_detalle) as d_det,
         (h.huella_nombres       <> c.huella_nombres)       as d_nom,
         (h.huella_deudas        <> c.huella_deudas)        as d_deu,
         (h.huella_foto = c.huella_foto)                    as foto_igual,
         c.huella_foto like 'PENDIENTE_%'                   as sin_rellenar
  from control c, hoy h
)
select jsonb_pretty(jsonb_build_object(
  'sellado', (select count(*) = 1 from sello),
  'sello', (select to_jsonb(s) from sello s),
  'meta_revision_hoy', (select revision from ctx),
  'personas', jsonb_build_object('linea_base', dx.personas, 'hoy', dx.personas_hoy),
  'foto_identica', dx.foto_igual,
  'que_cambio', jsonb_strip_nulls(jsonb_build_object(
     'conversion',    case when dx.d_conv  then 'CAMBIO — hubo anulaciones o conversiones nuevas con fecha de agosto' end,
     'produccion',    case when dx.d_prod  then 'CAMBIO — contratos/capital de agosto se movieron' end,
     'metas',         case when dx.d_metas then 'CAMBIO — se republicaron metas (revision nueva)' end,
     'metas_detalle', case when dx.d_det   then 'CAMBIO — cambiaron los objetivos por categoria/moneda' end,
     'nombres',       case when dx.d_nom   then 'CAMBIO — se corrigio el nombre de alguna ficha' end,
     'deudas',        case when dx.d_deu   then 'CAMBIO — nacieron o se saldaron ajustes de mes cerrado' end)),
  'veredicto', case
    when dx.sin_rellenar then 'SIN-RELLENAR: pega antes las huellas que imprimio el ensayo'
    when (select count(*) from sello) = 0 then 'AUN-NO-SELLADO'
    when dx.foto_igual then 'IDENTICO'
    when dx.d_conv or dx.d_prod or dx.d_metas or dx.d_det or dx.d_nom or dx.d_deu
      then 'DIFIERE-POR-DATO'
    else 'DIFIERE-SIN-DATO'
  end,
  'huellas', jsonb_build_object('foto_linea_base', dx.huella_foto, 'foto_hoy', dx.foto_hoy),
  'linea_base_del', dx.ensayado_el
)) as comparacion
from dx;
