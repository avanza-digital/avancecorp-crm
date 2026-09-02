-- G0 multiempresa · el reloj: «hoy» es el de LIMA, no el del servidor.
--
-- QUE, en una linea: en CUATRO funciones de lectura, `current_date` (la fecha del
-- servidor, que vive en UTC) pasa a ser la fecha civil de Lima. Nada mas cambia:
-- ni firmas, ni permisos, ni `search_path`, ni una coma del resto del cuerpo.
--
-- POR QUE. Lima va 5 horas por detras de UTC. De 19:00 a 23:59 de Lima el
-- servidor ya esta en «manana», y esas funciones calculaban «hoy» con su reloj.
-- El oraculo de borde R3 (02/09/2026, READ ONLY, un ano dia a dia con cd = D y
-- cd = D+1, fidelidad 0 contra el nucleo) midio la consecuencia:
--   * metricas_vencimientos_fn: fallo DIARIO, 282 de 365 dias con p_dias=90.
--     Un contrato que vence HOY desaparece de «por vencer» a las 19:00 (el
--     23/09: 150.000 PEN) y los de D+p_dias entran un dia antes.
--   * metricas_capital_mes_fn: el dinero NUNCA cambia de mes, pero el mes mas
--     antiguo de la ventana de 12 se cae 5 h antes el ultimo dia de cada mes
--     (primer fallo visible: 31/12/2026, 2026-01 PEN nuevo, 3 contratos, 120.000).
--   * metricas_pagos_mes_fn: mismo borde de ventana (Codex demostro que Hoy la
--     llama siempre). Su search_path NO es vacio y aqui NO se toca: es otra
--     decision y otra migracion.
--   * dashboard_admin_metricas (Portal, OK de Miguel 02/09 para tocar public):
--     un contrato que vence HOY figura como vencido desde las 19:00.
--
-- COMO. Los cuatro cuerpos se generaron a partir de `pg_get_functiondef` de las
-- funciones VIVAS, con la UNICA sustitucion `current_date` ->
-- `(now() at time zone 'America/Lima')::date`. `create or replace` conserva OID,
-- grants y dependencias. El preflight exige que el cuerpo vivo sea EXACTAMENTE
-- el que se leyo al generar esto (md5 de prosrc): si alguien lo cambio entre
-- medias, esta migracion aborta en vez de pisarlo. El postflight cuenta lo que
-- quedo, no lo que se quiso.
--
-- LO QUE NO HACE: no toca el nucleo (`capital_episodios`), ni la cuota, ni los
-- rankings, ni ningun trigger. `assert_f7_piezas_cerradas()` tiene el mismo
-- defecto por separado y va con la F7 (Olas 2/2b), no aqui.

begin;

-- Exclusion con cualquier otro despliegue en curso: el preflight lee el cuerpo y
-- el DDL lo reemplaza; entre medias no puede colarse otro `create or replace`.
select pg_advisory_xact_lock(hashtext('crm_migracion_funciones'));

-- ── Preflight: ¿son las funciones que lei? ────────────────────────────────────
do $$
declare v_md5 text; v_fn text; v_esperado text;
begin
  for v_fn, v_esperado in values
    ('crm.metricas_capital_mes_fn(integer)', 'b21f9a7a134f76f9f2eabfe75578cbca'),
    ('crm.metricas_pagos_mes_fn(integer)', '59946d1023223eba77e936394edb709f'),
    ('crm.metricas_vencimientos_fn(integer)', '4e7751a6c644a9c120ae155035e70561'),
    ('public.dashboard_admin_metricas()', 'a08433337d53728bbf295cb292dd8794')
  loop
    select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = v_fn::regprocedure;
    if v_md5 is null then
      raise exception 'No existe %: ABORTA', v_fn;
    end if;
    if v_md5 <> v_esperado then
      raise exception '% cambio desde que se genero esta migracion (md5 % <> %): ABORTA', v_fn, v_md5, v_esperado;
    end if;
  end loop;
end;
$$;

-- ── crm.metricas_capital_mes_fn: 2 sustituciones ──
CREATE OR REPLACE FUNCTION crm.metricas_capital_mes_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    e.mes_comercial as mes,
    e.moneda,
    case when e.tipo = 'cooperativa' then 'cooperativa' else e.categoria end as categoria,
    count(*)::bigint  as contratos,
    sum(e.monto)      as capital_colocado
  from private.capital_episodios(
         ((date_trunc('month', (now() at time zone 'America/Lima')::date)
            - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date::timestamp
           at time zone 'America/Lima'),
         (((now() at time zone 'America/Lima')::date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and (e.tipo like 'contrato_%' or e.tipo = 'cooperativa')
    and (
      a.es_global
      -- ATR-3 (decision de Miguel 31/08): la lente ENSEÑA por quien se lleva la
      -- produccion (el analista del episodio; con ATR-2 sera el de la cadena),
      -- no por el archivador del dueño. Sin analista -> no cuenta a nadie
      -- (invariante F3.5b); gerencia/lector global lo ve todo igual.
      or (e.tipo like 'contrato_%' and e.analista_id = any (a.ids))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2, 3
  order by 1, 2, 3;
$function$;

-- ── crm.metricas_pagos_mes_fn: 1 sustitucion ──
CREATE OR REPLACE FUNCTION crm.metricas_pagos_mes_fn(p_meses integer DEFAULT 12)
 RETURNS TABLE(mes date, moneda text, tipo text, estado text, cuotas bigint, monto_programado numeric, monto_pagado numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'private', 'public', 'crm'
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', cp.fecha_programada))::date as mes,
    ct.moneda,
    cp.tipo,
    cp.estado,
    count(*)::bigint                    as cuotas,
    sum(cp.monto_programado)            as monto_programado,
    sum(coalesce(cp.monto_pagado, 0))   as monto_pagado
  from public.cronograma_pagos cp
  join (select * from public.contratos where not es_demo) ct  on ct.id  = cp.contrato_id
  join public.perfiles  cli on cli.id = ct.cliente_id
  cross join ambito a
  where cp.fecha_programada >= (date_trunc('month', (now() at time zone 'America/Lima')::date)
        - make_interval(months => least(greatest(p_meses, 1), 60) - 1))::date
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2, 3, 4
  order by 1, 2, 3, 4;
$function$;

-- ── crm.metricas_vencimientos_fn: 3 sustituciones ──
CREATE OR REPLACE FUNCTION crm.metricas_vencimientos_fn(p_dias integer DEFAULT 90)
 RETURNS TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ambito as (
    select
      ((select private.es_lector_global())
        or (select private.rol_crm((select auth.uid()))) = 'gerencia') as es_global,
      array(select private.vendedor_ids_visibles((select auth.uid())))  as ids
  )
  select
    (date_trunc('month', e.fecha_vencimiento))::date as mes,
    e.moneda,
    count(*)::bigint as contratos_por_vencer,
    sum(e.monto)     as capital_por_vencer
  from private.capital_episodios(
         '-infinity'::timestamptz,
         (((now() at time zone 'America/Lima')::date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         -- ATR-4: la coop anulada REAL sigue siendo dinero y sigue venciendo
         -- (la MEDIDA del nucleo manda; la demo es 'nula' y queda fuera sola).
         or e.tipo = 'cooperativa')
    and e.fecha_vencimiento >= (now() at time zone 'America/Lima')::date
    and e.fecha_vencimiento <  (now() at time zone 'America/Lima')::date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      -- ATR-3 (decision de Miguel 31/08): la lente ENSEÑA por quien se lleva la
      -- produccion (el analista del episodio; con ATR-2 sera el de la cadena),
      -- no por el archivador del dueño. Sin analista -> no cuenta a nadie
      -- (invariante F3.5b); gerencia/lector global lo ve todo igual.
      or (e.tipo like 'contrato_%' and e.analista_id = any (a.ids))
      or (e.tipo = 'cooperativa' and e.analista_id = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$function$;

-- ── public.dashboard_admin_metricas: 2 sustituciones ──
CREATE OR REPLACE FUNCTION public.dashboard_admin_metricas()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  -- Antes era INVOKER y la RLS decidia: en la practica, solo el gestor de
  -- cartera (admin/superadmin/operaciones) veia el tablero completo. El gate
  -- explicito conserva EXACTAMENTE esa autoridad.
  if not (select public.es_gestor_cartera()) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  with contratos_norm as (
    select
      case
        when e.estado = 'vencido' then 'vencido'
        when e.fecha_vencimiento < (now() at time zone 'America/Lima')::date then 'vencido'
        else e.estado
      end as estado_real,
      e.fecha_vencimiento,
      e.monto as capital,
      e.moneda
    from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[]) e
    where e.tipo like 'contrato_%' and e.medida='stock'
      and e.estado in ('activo','vencido')
  ),
  metricas as (
    select
      count(*) filter (where estado_real = 'activo') as contratos_activos,
      count(*) filter (where estado_real = 'vencido') as vencidos,
      count(*) filter (where estado_real = 'activo' and fecha_vencimiento <= (now() at time zone 'America/Lima')::date + 30) as por_vencer,
      coalesce(sum(capital) filter (where estado_real = 'activo' and moneda = 'PEN'), 0) as capital_pen,
      coalesce(sum(capital) filter (where estado_real = 'activo' and moneda = 'USD'), 0) as capital_usd
    from contratos_norm
  ),
  total_clientes as (
    select count(*) as total from public.perfiles where rol = 'cliente'
  )
  select jsonb_build_object(
    'contratosActivos', m.contratos_activos,
    'capitalPEN',       m.capital_pen,
    'capitalUSD',       m.capital_usd,
    'totalClientes',    tc.total,
    'porVencer',        m.por_vencer,
    'vencidos',         m.vencidos
  ) into v
  from metricas m, total_clientes tc;
  return v;
end;
$function$;

-- ── Postflight EXACTO (Codex, A5): no «contiene tal substring», sino «es
-- EXACTAMENTE este cuerpo» y «TODA la metadata sigue igual». ────────────────
do $$
declare r record; v_n int := 0;
begin
  for r in
    select v.fn, v.md5_esperado, v.huella_esperada,
           md5(p.prosrc) as md5_real,
           concat_ws('|',
             pg_get_userbyid(p.proowner), l.lanname, p.provolatile, p.proparallel,
             p.proisstrict, p.proleakproof, p.prosecdef, p.procost, p.prorows, p.proretset,
             pg_get_function_result(p.oid),
             coalesce(array_to_string(p.proconfig, ','), '<sin config>'),
             (select string_agg(pg_get_userbyid(a.grantor)||'>'||pg_get_userbyid(a.grantee)||':'||a.privilege_type
                                ||case when a.is_grantable then '*' else '' end, ' ' order by a.grantee, a.privilege_type)
                from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a),
             coalesce(obj_description(p.oid, 'pg_proc'), '<sin comentario>'),
             (select count(*) from pg_depend d where d.refobjid = p.oid and d.deptype <> 'i')
           ) as huella_real
    from (values
      ('crm.metricas_capital_mes_fn(integer)', 'a25667f6df71944eac1501afaaa1334e',
       'postgres|sql|s|u|false|false|true|100|1000|true|TABLE(mes date, moneda text, categoria text, contratos bigint, capital_colocado numeric)|search_path=""|postgres>postgres:EXECUTE postgres>authenticated:EXECUTE|Capital colocado por periodo comercial, moneda y categoria. Sin PII; conserva el ambito CRM vigente.|0'),
      ('crm.metricas_pagos_mes_fn(integer)', '88c799019ada59f20ad4856824cf577a',
       'postgres|sql|s|u|false|false|true|100|1000|true|TABLE(mes date, moneda text, tipo text, estado text, cuotas bigint, monto_programado numeric, monto_pagado numeric)|search_path=private, public, crm|postgres>postgres:EXECUTE postgres>authenticated:EXECUTE|Agregado para gráfica de gerencia: PAGOS A INVERSIONISTAS del cronograma por mes/moneda/tipo/estado (pagado vs vencido). Sin PII. Mismo ámbito por rol que el resto de métricas.|0'),
      ('crm.metricas_vencimientos_fn(integer)', 'dbafa025bf23ce0e863226e0c211868c',
       'postgres|sql|s|u|false|false|true|100|1000|true|TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)|search_path=""|postgres>postgres:EXECUTE postgres>authenticated:EXECUTE|Agregado para gráfica de gerencia: contratos activos por vencer en los próximos p_dias, por mes y moneda. Sin PII. Mismo ámbito por rol.|0'),
      ('public.dashboard_admin_metricas()', 'df2c28bc163230fe9e923c9f4fddaf45',
       'postgres|plpgsql|s|u|false|false|true|100|0|false|jsonb|search_path=""|postgres>postgres:EXECUTE postgres>authenticated:EXECUTE postgres>service_role:EXECUTE|<sin comentario>|0')
    ) as v(fn, md5_esperado, huella_esperada)
    join pg_proc p on p.oid = v.fn::regprocedure
    join pg_language l on l.oid = p.prolang
  loop
    v_n := v_n + 1;
    if r.md5_real <> r.md5_esperado then
      raise exception '% no quedo con el cuerpo esperado (md5 % <> %)', r.fn, r.md5_real, r.md5_esperado;
    end if;
    if r.huella_real <> r.huella_esperada then
      raise exception '% cambio de metadata: % <> %', r.fn, r.huella_real, r.huella_esperada;
    end if;
  end loop;
  if v_n <> 4 then
    raise exception 'El postflight encontro % funciones, no 4', v_n;
  end if;
  -- Y las 4 son las UNICAS con esos nombres: sin sobrecargas nuevas.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where (n.nspname = 'crm' and p.proname in ('metricas_capital_mes_fn','metricas_vencimientos_fn','metricas_pagos_mes_fn'))
         or (n.nspname = 'public' and p.proname = 'dashboard_admin_metricas')) <> 4 then
    raise exception 'Aparecio una sobrecarga inesperada';
  end if;
end;
$$;

commit;
