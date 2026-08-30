-- Registra 20260830223000 CON su cuerpo - fail-closed, etiqueta propia.
-- Candados heredados de F5.d: "existe SIN cuerpo" revienta; RELECTURA tras el
-- insert (ON CONFLICT DO NOTHING puede ceder ante un insert concurrente).
do $reg_atr1$
declare v_a text[]; v_nombre text;
begin
  select statements into v_a from supabase_migrations.schema_migrations where version='20260830223000';
  if found and v_a is null then
    raise exception 'La version 20260830223000 existe SIN cuerpo (statements NULL): repararla con UPDATE, no re-insertar'; end if;
  if found and v_a <> array[$mig_atr1$-- P-055 ATR-1 - EL UPGRADE CUENTA A QUIEN LO HACE (y agosto queda bien antes del sello).
--
-- DECISION DE MIGUEL (30/08, 4 respuestas firmadas; contrato tecnico en el vault:
-- "Contrato de la atribucion por cadena de upgrade (2026-08-30)"):
--   * upgrade -> cuenta al analista del selector (contratos.analista_cierre_id), no al dueno;
--   * la renovacion de ESE upgrade -> al mismo analista (adopcion por LINEA; la cadena
--     sigue al CONTRATO y relee el analista VIVO de la cabeza);
--   * asesor_perfil_id del cliente JAMAS cambia por un upgrade;
--   * incluye agosto (mes abierto; se re-atribuye POR LECTURA, ni una fila del ledger se toca);
--   * el Directorio del Portal SE QUEDA con la regla vieja (dos podios, a proposito).
--
-- DONDE VIVE LA REGLA: en la LECTURA. Una pieza nueva -private.analista_atribuido_cadena-
-- y dos nucleos que la preguntan con coalesce a su regla vieja:
--   * private.conversion_episodios, pierna 'operacion' (columna analista_id + filtro visibles);
--   * private.metricas_cartera_por_vendedor, bloque economia (select + group by).
-- El ledger crm.operaciones_cartera NO cambia: vendedor_id pasa a significar "quien ERA
-- el dueno al registrar" (HECHO); "a quien cuenta" es POLITICA del resolutor.
--
-- QUE NO SE TOCA (y el postflight lo pinnea por md5): crm.operaciones_cartera (ni una fila),
-- public.crear_contrato, private.capital_episodios, private.produccion_mes_por_vendedor,
-- crm.cerrar_periodo, private.registrar_ajuste_si_mes_cerrado,
-- crm.cumplimiento_metas_sin_cartera_fn, public.directorio_ranking_analistas,
-- perfiles.asesor_perfil_id. El capital de los upgrades YA iba al analista (F3.5b):
-- esta fase mueve SOLO conversion y economia de cartera. El capital por cadena de
-- renovaciones-de-upgrade es la ATR-2 (tras el sello del 10/09).
--
-- MEDIDO EL 30/08 CONTRA PRODUCCION: 46 upgrades en agosto, TODOS con analista = dueno
-- (delta VACIO -> el oraculo de hoy exige PARIDAD BYTE A BYTE; la lista de delta se
-- re-mide aqui por si nace un upgrade de un no-dueno antes del publish), 0 renovaciones
-- de cadena de upgrade, 0 upgrades sin analista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines, invariantes y la foto de ANTES.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    -- las DOS que se tocan (cuerpo VIEJO exacto):
    array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '34acbfa8f6838b5f0ca6d5aa17d85d2a'],
    array['private.metricas_cartera_por_vendedor(date)',                                       'eeebe4e1385263dbdb6f3fdda81b1b93'],
    -- las SEIS que NO deben moverse (se re-verifican identicas en el postflight):
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
    array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
  ];
  v_fila text[]; v_h text; v_n integer;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- El resolutor aun no existe (este guion lo crea; si existe, alguien se adelanto).
  if to_regprocedure('private.analista_atribuido_cadena(uuid)') is not null then
    raise exception 'ATR-1 preflight: private.analista_atribuido_cadena ya existe';
  end if;

  -- Invariantes de agosto/mes abierto (el contrato tecnico las declara):
  --  a) 0 renovaciones cuya cadena termine en upgrade (nada que heredar todavia;
  --     si aparece una, la ATR-2 va primero o se re-mide a mano).
  select count(*) into v_n
    from crm.operaciones_cartera r
    join public.contratos co on co.id = r.contrato_origen_id
   where r.tipo = 'renovacion' and co.categoria = 'upgrade';
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % renovaciones de cadena de upgrade (se esperaba 0)', v_n;
  end if;
  --  a2) tipo del ledger = categoria del contrato, HOY sin divergencias (0 el
  --      30/08). Si un dia divergen (la puerta de edicion PUEDE corregir la
  --      categoria), la adopcion sigue a contratos.categoria POR DISENO
  --      (contrato tecnico): esto solo exige partir de un mundo limpio.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo is distinct from c.categoria;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % operaciones con tipo <> categoria del contrato (se esperaba 0)', v_n;
  end if;

  --  b) 0 upgrades sin analista (la puerta F3.7 lo garantiza desde el 29/08).
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade' and c.analista_cierre_id is null;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % upgrades sin analista_cierre (se esperaba 0)', v_n;
  end if;

  -- CANDADO TEMPORAL (auditoria RLS, P2-4): la promesa "incluye agosto" solo
  -- vale ANTES del sello. Si agosto ya se sello y quedo algun upgrade de un
  -- no-dueno dentro, este publish llega TARDE y no debe fingir que no paso.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01')
     and exists (
       select 1 from crm.operaciones_cartera o
       join public.contratos c on c.id = o.contrato_nuevo_id
       where o.periodo = date '2026-08-01' and o.tipo = 'upgrade'
         and c.analista_cierre_id is distinct from o.vendedor_id) then
    raise exception 'ATR-1 preflight: agosto YA esta sellado y contiene upgrades de no-duenos — el publish llego tarde; decidir con Miguel antes de aplicar';
  end if;

  -- La LISTA DELTA: upgrades de meses NO sellados con analista <> dueno. Son las
  -- UNICAS filas cuya atribucion puede moverse; el oraculo lo exige exacto.
  create temp table _atr1_delta on commit drop as
    select o.id as operacion_id, o.periodo,
           o.vendedor_id as dueno_id, c.analista_cierre_id as analista_id,
           o.elegible_conversion
      from crm.operaciones_cartera o
      join public.contratos c on c.id = o.contrato_nuevo_id
     where o.tipo = 'upgrade'
       and c.analista_cierre_id is distinct from o.vendedor_id
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  -- La foto de ANTES, por cada mes NO sellado con operaciones:
  create temp table _atr1_meses on commit drop as
    select distinct o.periodo from crm.operaciones_cartera o
     where not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  create temp table _atr1_ce_antes on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_antes on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;
end $$;

-- =====================================================================
-- 1) EL RESOLUTOR: una sola pieza semantica. La cadena sigue al CONTRATO
--    (relee el analista VIVO de la cabeza); sin cadena de upgrade -> NULL
--    y el consumidor cae a su regla vieja. Ciclos imposibles por esquema
--    (contrato_nuevo_id UNIQUE + indice unico sobre contrato_origen_id);
--    tope 100 de cinturon. SIN conteos: no entra al censo F6.a.
-- =====================================================================
create function private.analista_atribuido_cadena(p_contrato_id uuid)
returns uuid
language sql
stable
security invoker
set search_path to ''
as $resolutor$
  -- La ADOPCION MAS RECIENTE manda (auditoria Codex P1-1): se camina hacia
  -- atras y gana el PRIMER ancestro (o el propio contrato) con categoria
  -- 'upgrade' — asi una correccion de categoria por la puerta de edicion
  -- corrige tambien la adopcion de sus descendientes, en vez de saltarsela.
  -- Anti-ciclo por lista de visitados (dos filas cruzadas A<->B satisfacen
  -- los UNIQUE del esquema: el tope de nivel NO basta) + tope 100 de cinturon.
  with recursive cadena as (
    select p_contrato_id as contrato_id, 0 as nivel, array[p_contrato_id] as visitados
    union all
    select o.contrato_origen_id, c.nivel + 1, c.visitados || o.contrato_origen_id
      from cadena c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.contrato_id
     where o.contrato_origen_id is not null
       and not (o.contrato_origen_id = any(c.visitados))
       and c.nivel < 100
  )
  select con.analista_cierre_id
    from cadena cd
    join public.contratos con on con.id = cd.contrato_id
   where con.categoria = 'upgrade'
   order by cd.nivel asc
   limit 1
$resolutor$;

revoke execute on function private.analista_atribuido_cadena(uuid) from public, anon, authenticated;

-- =====================================================================
-- 2) LOS DOS NUCLEOS, con la pregunta nueva (cuerpos completos, generados
--    a maquina desde el prosrc VIVO capturado el 30/08 + los 2 parches).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
-- Pierna RECIBIDO: un episodio por (analista, lead) con asignacion en la
-- ventana. El origen/motivo son los del PRIMER episodio dentro de la ventana
-- (semantica viva del nucleo); `aproximado` si algun episodio lo fue.
select
  'recibido'::text,
  r.analista_id,
  r.lead_id,
  null::uuid,
  r.fue_referido,
  r.aproximado,
  r.motivo,
  false,
  r.origen_primero,
  null::text,
  null::date,
  null::numeric,
  null::text,
  r.primera_asignacion,
  null::timestamptz,
  case when r.fue_referido then 0 else 1 end,
  0::numeric
from (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] as origen_primero,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado,
    min(la.asignado_en) as primera_asignacion
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
) r

union all

-- Pierna CIERRE: una fila por asignacion convertida con resultado en la
-- ventana. Los cierres ANULADOS (ambos canales, via cierre_externo_anulado)
-- VIAJAN marcados con aporte 0: el nucleo los filtra; Distribucion (F2)
-- podra contarlos sin recalcular nada. El origen aqui es el del EPISODIO
-- (no el primero): semantica viva del nucleo.
select
  'cierre'::text,
  c.analista_id,
  c.lead_id,
  null::uuid,
  c.fue_referido,
  null::boolean,
  null::text,
  c.anulado,
  c.origen,
  null::text,
  c.mes_origen,
  null::numeric,
  null::text,
  null::timestamptz,
  c.fecha_cierre,
  0,
  case when c.anulado then 0
       when c.fue_referido then p_factor
       else 1 end
from (
  select
    la.analista_id, la.lead_id,
    (la.origen = 'referido') as fue_referido,
    la.origen,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    coalesce(la.resultado_en, la.finalizado_en) as fecha_cierre,
    private.cierre_externo_anulado(la.lead_id) as anulado
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
) c

union all

-- Pierna OPERACION: cartera elegible del periodo, MAXIMO UNA por cliente/mes
-- (la primera por fecha_operacion, creado_en, id — criterio vivo). El orden
-- se calcula ANTES del filtro de visibles (semantica viva). Con p_periodo
-- NULL la pierna queda vacia: los rangos libres no tienen mes de cartera.
select
  'operacion'::text,
  -- ATR-1: la atribucion es POLITICA de lectura — la cadena de upgrade
  -- adopta (contrato tecnico 2026-08-30); sin cadena, la regla vieja.
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid,
  o.id,
  false,
  null::boolean,
  null::text,
  false,
  null::text,
  o.tipo,
  o.periodo,
  -- monto NULL a proposito (Codex P8): sumar capitales seria aritmetica que
  -- el nucleo vivo jamas ejecuto; nadie la consume en F1. F2 decidira su forma.
  null::numeric,
  o.moneda,
  null::timestamptz,
  (o.fecha_operacion::timestamp at time zone 'America/Lima'),
  0,
  1::numeric
from (
  select o0.*,
    row_number() over (
      partition by o0.cliente_id, o0.periodo
      order by o0.fecha_operacion, o0.creado_en, o0.id
    ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.periodo = p_periodo
    and o0.elegible_conversion
) o
where p_periodo is not null
  and o.orden_conversion = 1
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles));
end;
$function$
;

CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      -- ATR-1: mismo resolutor que el nucleo de conversion (una politica).
      coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) as vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$function$
;

-- =====================================================================
-- 3) ORACULO en la misma transaccion: la foto de DESPUES contra la de ANTES.
--    Con la lista delta VACIA (lo medido hoy): PARIDAD EXACTA fila a fila.
--    Con delta: SOLO se mueven esas operaciones, del dueno al analista.
-- =====================================================================
do $$
declare v_n integer; v_m integer;
begin
  create temp table _atr1_ce_despues on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_despues on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;

  -- 3a) CONVERSION: mismo numero de filas, por mes y por pierna.
  select count(*) into v_n from _atr1_ce_antes;
  select count(*) into v_m from _atr1_ce_despues;
  if v_n <> v_m then
    raise exception 'ATR-1 oraculo: el numero de episodios cambio (% -> %)', v_n, v_m;
  end if;

  -- 3b) Las filas que difieren, EXACTAMENTE las del delta (dueno -> analista).
  create temp table _atr1_perdidas on commit drop as
    select * from _atr1_ce_antes except select * from _atr1_ce_despues;
  create temp table _atr1_ganadas on commit drop as
    select * from _atr1_ce_despues except select * from _atr1_ce_antes;

  select count(*) into v_n from _atr1_perdidas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (perdidas)', v_n;
  end if;
  select count(*) into v_n from _atr1_ganadas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (ganadas)', v_n;
  end if;

  -- 3c) Y las movidas van del dueno al analista con TODO lo demas identico.
  select count(*) into v_n from _atr1_perdidas p
   where not exists (
     select 1 from _atr1_ganadas g
     join _atr1_delta d on d.operacion_id = p.operacion_id
     where g.operacion_id = p.operacion_id
       and p.analista_id = d.dueno_id
       and g.analista_id = d.analista_id
       and g._mes = p._mes and g.tipo = p.tipo and g.categoria = p.categoria
       and g.moneda is not distinct from p.moneda
       and g.origen is not distinct from p.origen
       and g.mes_origen is not distinct from p.mes_origen
       and g.fecha_numerador is not distinct from p.fecha_numerador
       and g.aporte_divisor = p.aporte_divisor
       and g.aporte_numerador = p.aporte_numerador
       and g.lead_id is not distinct from p.lead_id
       and g.fue_referido is not distinct from p.fue_referido
       and g.aproximado is not distinct from p.aproximado
       and g.motivo is not distinct from p.motivo
       and g.anulado is not distinct from p.anulado
       and g.monto is not distinct from p.monto
       and g.fecha_divisor is not distinct from p.fecha_divisor);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas movidas no emparejan dueno->analista al byte', v_n;
  end if;

  -- 3d) ECONOMIA DE CARTERA: el dinero de renovaciones NO se mueve NUNCA en
  --     esta fase (el desglose es de renovaciones; F2 decidira la cadena).
  select count(*) into v_n
    from _atr1_mc_antes a
    full outer join _atr1_mc_despues d
      on d._mes = a._mes and d.vendedor_id = a.vendedor_id
   where coalesce(a.operaciones_renovacion, 0)      <> coalesce(d.operaciones_renovacion, 0)
      or coalesce(a.renovaciones_sin_desglose, 0)   <> coalesce(d.renovaciones_sin_desglose, 0)
      or coalesce(a.conversiones_renovacion, 0)     <> coalesce(d.conversiones_renovacion, 0)
      or coalesce(a.capital_renovado_pen, 0)        <> coalesce(d.capital_renovado_pen, 0)
      or coalesce(a.capital_renovado_usd, 0)        <> coalesce(d.capital_renovado_usd, 0)
      or coalesce(a.capital_adicional_pen, 0)       <> coalesce(d.capital_adicional_pen, 0)
      or coalesce(a.capital_adicional_usd, 0)       <> coalesce(d.capital_adicional_usd, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: la economia de RENOVACIONES se movio en % filas (debia quedar intacta)', v_n;
  end if;

  -- 3e) Los totales de upgrade de la EMPRESA no cambian (solo el reparto).
  select abs(coalesce((select sum(operaciones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(operaciones_upgrade) from _atr1_mc_despues), 0))
       + abs(coalesce((select sum(conversiones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(conversiones_upgrade) from _atr1_mc_despues), 0))
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el TOTAL de upgrades de la empresa cambio (delta %)', v_n;
  end if;

  -- 3e-bis) El reparto de OPERACIONES de upgrade por analista se mueve
  --         EXACTAMENTE segun la lista delta: dueno -n, analista +n.
  select count(*) into v_n
    from (
      select coalesce(a._mes, d._mes) as _mes,
             coalesce(a.vendedor_id, d.vendedor_id) as vendedor_id,
             coalesce(d.operaciones_upgrade, 0) - coalesce(a.operaciones_upgrade, 0) as mov
        from _atr1_mc_antes a
        full outer join _atr1_mc_despues d
          on d._mes = a._mes and d.vendedor_id = a.vendedor_id
    ) x
    left join (
      select periodo as _mes, dueno_id as vendedor_id, -count(*)::int as esperado
        from _atr1_delta group by periodo, dueno_id
      union all
      select periodo, analista_id, count(*)::int
        from _atr1_delta group by periodo, analista_id
    ) e on e._mes = x._mes and e.vendedor_id = x.vendedor_id
   where x.mov <> coalesce(e.esperado, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el reparto de upgrades por analista no cuadra con el delta (% filas)', v_n;
  end if;

  -- 3e-tris) Ninguna persona aparece o desaparece de la foto fuera del delta.
  select count(*) into v_n
    from (
      (select _mes, vendedor_id from _atr1_mc_antes
       except select _mes, vendedor_id from _atr1_mc_despues)
      union all
      (select _mes, vendedor_id from _atr1_mc_despues
       except select _mes, vendedor_id from _atr1_mc_antes)
    ) x
   where x.vendedor_id not in (
     select dueno_id from _atr1_delta union select analista_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % personas entran/salen de la foto fuera del delta', v_n;
  end if;

  -- 3f) Con delta VACIO, la paridad es EXACTA tambien en cartera.
  if (select count(*) from _atr1_delta) = 0 then
    select (select count(*) from (select * from _atr1_mc_antes except select * from _atr1_mc_despues) x)
         + (select count(*) from (select * from _atr1_mc_despues except select * from _atr1_mc_antes) x)
      into v_n;
    if v_n <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero cartera difiere en % filas', v_n;
    end if;
    if (select count(*) from _atr1_perdidas) + (select count(*) from _atr1_ganadas) <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero conversion difiere';
    end if;
  end if;

  -- 3g) El resolutor, contra datos REALES (sin fabricar nada):
  --     un upgrade -> su propio analista; un contrato nuevo -> NULL.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade'
     and private.analista_atribuido_cadena(o.contrato_nuevo_id) is distinct from c.analista_cierre_id;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor falla en % upgrades reales', v_n;
  end if;
  select count(*) into v_n
    from public.contratos c
   where coalesce(c.categoria, 'nuevo') = 'nuevo'
     and private.analista_atribuido_cadena(c.id) is not null;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor adopta % contratos NUEVOS (debia dar NULL)', v_n;
  end if;
end $$;

-- =====================================================================
-- 4) POSTFLIGHT: huellas nuevas, lo intocado intacto, ACL, firma y guardianes.
-- =====================================================================
do $$
declare v_h text; v_n integer;
begin
  -- Las dos tocadas quedaron EXACTAMENTE como este guion las trae:
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure;
  if v_h is distinct from '71213ac03eb32e333723399538d35d83' then
    raise exception 'ATR-1 postflight: conversion_episodios quedo con huella %', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h is distinct from 'f968879ae7f354a4165f1aebedc685b9' then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor quedo con huella %', v_h;
  end if;

  -- La firma de conversion_episodios es IDENTICA (su exclusion del censo F6.a es por firma).
  if (select pg_get_function_identity_arguments('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure))
     is distinct from 'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric' then
    raise exception 'ATR-1 postflight: la FIRMA de conversion_episodios cambio';
  end if;

  -- Ni un conteo nuevo en los cuerpos (el censo F6.a mide llamadas de conteo).
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure)
     <> 0 * length('count(') then
    raise exception 'ATR-1 postflight: conversion_episodios cambio sus conteos';
  end if;
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure)
     <> 6 * length('count(') then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor cambio sus conteos';
  end if;
  if exists (select 1 from pg_proc p
    where p.oid = 'private.analista_atribuido_cadena(uuid)'::regprocedure
      and (strpos(p.prosrc, 'count(') > 0 or strpos(p.prosrc, 'crm.leads') > 0)) then
    raise exception 'ATR-1 postflight: el resolutor trae conteos o leads (censo F6.a)';
  end if;

  -- Las SEIS intocadas, INTACTAS al byte:
  declare
    v_fn constant text[][] := array[
      array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
      array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
      array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
      array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
      array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
      array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
      array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
    ];
    v_fila text[];
  begin
    foreach v_fila slice 1 in array v_fn loop
      select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
      if v_h is distinct from v_fila[2] then
        raise exception 'ATR-1 postflight: % se movio y NO debia (huella %)', v_fila[1], v_h;
      end if;
    end loop;
  end;

  -- ACL literal de las 3 privates: solo postgres.
  foreach v_h in array array[
    'private.analista_atribuido_cadena(uuid)',
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
    'private.metricas_cartera_por_vendedor(date)'
  ] loop
    if (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure)
       is distinct from '{postgres=X/postgres}' then
      raise exception 'ATR-1 postflight: proacl de % no es {postgres=X/postgres} (%)', v_h,
        (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure);
    end if;
  end loop;

  -- El ledger, intacto en numero (ni una fila escrita por esta migracion).
  -- (la comparacion fina la dieron los oraculos; esto es el cinturon)
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_atr1$] then
    raise exception 'La version 20260830223000 ya existe con OTRO cuerpo'; end if;
  insert into supabase_migrations.schema_migrations (version, name, statements)
  values ('20260830223000','crm_atr_1_upgrade_cuenta_a_quien_lo_hace', array[$mig_atr1$-- P-055 ATR-1 - EL UPGRADE CUENTA A QUIEN LO HACE (y agosto queda bien antes del sello).
--
-- DECISION DE MIGUEL (30/08, 4 respuestas firmadas; contrato tecnico en el vault:
-- "Contrato de la atribucion por cadena de upgrade (2026-08-30)"):
--   * upgrade -> cuenta al analista del selector (contratos.analista_cierre_id), no al dueno;
--   * la renovacion de ESE upgrade -> al mismo analista (adopcion por LINEA; la cadena
--     sigue al CONTRATO y relee el analista VIVO de la cabeza);
--   * asesor_perfil_id del cliente JAMAS cambia por un upgrade;
--   * incluye agosto (mes abierto; se re-atribuye POR LECTURA, ni una fila del ledger se toca);
--   * el Directorio del Portal SE QUEDA con la regla vieja (dos podios, a proposito).
--
-- DONDE VIVE LA REGLA: en la LECTURA. Una pieza nueva -private.analista_atribuido_cadena-
-- y dos nucleos que la preguntan con coalesce a su regla vieja:
--   * private.conversion_episodios, pierna 'operacion' (columna analista_id + filtro visibles);
--   * private.metricas_cartera_por_vendedor, bloque economia (select + group by).
-- El ledger crm.operaciones_cartera NO cambia: vendedor_id pasa a significar "quien ERA
-- el dueno al registrar" (HECHO); "a quien cuenta" es POLITICA del resolutor.
--
-- QUE NO SE TOCA (y el postflight lo pinnea por md5): crm.operaciones_cartera (ni una fila),
-- public.crear_contrato, private.capital_episodios, private.produccion_mes_por_vendedor,
-- crm.cerrar_periodo, private.registrar_ajuste_si_mes_cerrado,
-- crm.cumplimiento_metas_sin_cartera_fn, public.directorio_ranking_analistas,
-- perfiles.asesor_perfil_id. El capital de los upgrades YA iba al analista (F3.5b):
-- esta fase mueve SOLO conversion y economia de cartera. El capital por cadena de
-- renovaciones-de-upgrade es la ATR-2 (tras el sello del 10/09).
--
-- MEDIDO EL 30/08 CONTRA PRODUCCION: 46 upgrades en agosto, TODOS con analista = dueno
-- (delta VACIO -> el oraculo de hoy exige PARIDAD BYTE A BYTE; la lista de delta se
-- re-mide aqui por si nace un upgrade de un no-dueno antes del publish), 0 renovaciones
-- de cadena de upgrade, 0 upgrades sin analista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines, invariantes y la foto de ANTES.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    -- las DOS que se tocan (cuerpo VIEJO exacto):
    array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '34acbfa8f6838b5f0ca6d5aa17d85d2a'],
    array['private.metricas_cartera_por_vendedor(date)',                                       'eeebe4e1385263dbdb6f3fdda81b1b93'],
    -- las SEIS que NO deben moverse (se re-verifican identicas en el postflight):
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
    array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
  ];
  v_fila text[]; v_h text; v_n integer;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- El resolutor aun no existe (este guion lo crea; si existe, alguien se adelanto).
  if to_regprocedure('private.analista_atribuido_cadena(uuid)') is not null then
    raise exception 'ATR-1 preflight: private.analista_atribuido_cadena ya existe';
  end if;

  -- Invariantes de agosto/mes abierto (el contrato tecnico las declara):
  --  a) 0 renovaciones cuya cadena termine en upgrade (nada que heredar todavia;
  --     si aparece una, la ATR-2 va primero o se re-mide a mano).
  select count(*) into v_n
    from crm.operaciones_cartera r
    join public.contratos co on co.id = r.contrato_origen_id
   where r.tipo = 'renovacion' and co.categoria = 'upgrade';
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % renovaciones de cadena de upgrade (se esperaba 0)', v_n;
  end if;
  --  a2) tipo del ledger = categoria del contrato, HOY sin divergencias (0 el
  --      30/08). Si un dia divergen (la puerta de edicion PUEDE corregir la
  --      categoria), la adopcion sigue a contratos.categoria POR DISENO
  --      (contrato tecnico): esto solo exige partir de un mundo limpio.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo is distinct from c.categoria;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % operaciones con tipo <> categoria del contrato (se esperaba 0)', v_n;
  end if;

  --  b) 0 upgrades sin analista (la puerta F3.7 lo garantiza desde el 29/08).
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade' and c.analista_cierre_id is null;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % upgrades sin analista_cierre (se esperaba 0)', v_n;
  end if;

  -- CANDADO TEMPORAL (auditoria RLS, P2-4): la promesa "incluye agosto" solo
  -- vale ANTES del sello. Si agosto ya se sello y quedo algun upgrade de un
  -- no-dueno dentro, este publish llega TARDE y no debe fingir que no paso.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01')
     and exists (
       select 1 from crm.operaciones_cartera o
       join public.contratos c on c.id = o.contrato_nuevo_id
       where o.periodo = date '2026-08-01' and o.tipo = 'upgrade'
         and c.analista_cierre_id is distinct from o.vendedor_id) then
    raise exception 'ATR-1 preflight: agosto YA esta sellado y contiene upgrades de no-duenos — el publish llego tarde; decidir con Miguel antes de aplicar';
  end if;

  -- La LISTA DELTA: upgrades de meses NO sellados con analista <> dueno. Son las
  -- UNICAS filas cuya atribucion puede moverse; el oraculo lo exige exacto.
  create temp table _atr1_delta on commit drop as
    select o.id as operacion_id, o.periodo,
           o.vendedor_id as dueno_id, c.analista_cierre_id as analista_id,
           o.elegible_conversion
      from crm.operaciones_cartera o
      join public.contratos c on c.id = o.contrato_nuevo_id
     where o.tipo = 'upgrade'
       and c.analista_cierre_id is distinct from o.vendedor_id
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  -- La foto de ANTES, por cada mes NO sellado con operaciones:
  create temp table _atr1_meses on commit drop as
    select distinct o.periodo from crm.operaciones_cartera o
     where not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  create temp table _atr1_ce_antes on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_antes on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;
end $$;

-- =====================================================================
-- 1) EL RESOLUTOR: una sola pieza semantica. La cadena sigue al CONTRATO
--    (relee el analista VIVO de la cabeza); sin cadena de upgrade -> NULL
--    y el consumidor cae a su regla vieja. Ciclos imposibles por esquema
--    (contrato_nuevo_id UNIQUE + indice unico sobre contrato_origen_id);
--    tope 100 de cinturon. SIN conteos: no entra al censo F6.a.
-- =====================================================================
create function private.analista_atribuido_cadena(p_contrato_id uuid)
returns uuid
language sql
stable
security invoker
set search_path to ''
as $resolutor$
  -- La ADOPCION MAS RECIENTE manda (auditoria Codex P1-1): se camina hacia
  -- atras y gana el PRIMER ancestro (o el propio contrato) con categoria
  -- 'upgrade' — asi una correccion de categoria por la puerta de edicion
  -- corrige tambien la adopcion de sus descendientes, en vez de saltarsela.
  -- Anti-ciclo por lista de visitados (dos filas cruzadas A<->B satisfacen
  -- los UNIQUE del esquema: el tope de nivel NO basta) + tope 100 de cinturon.
  with recursive cadena as (
    select p_contrato_id as contrato_id, 0 as nivel, array[p_contrato_id] as visitados
    union all
    select o.contrato_origen_id, c.nivel + 1, c.visitados || o.contrato_origen_id
      from cadena c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.contrato_id
     where o.contrato_origen_id is not null
       and not (o.contrato_origen_id = any(c.visitados))
       and c.nivel < 100
  )
  select con.analista_cierre_id
    from cadena cd
    join public.contratos con on con.id = cd.contrato_id
   where con.categoria = 'upgrade'
   order by cd.nivel asc
   limit 1
$resolutor$;

revoke execute on function private.analista_atribuido_cadena(uuid) from public, anon, authenticated;

-- =====================================================================
-- 2) LOS DOS NUCLEOS, con la pregunta nueva (cuerpos completos, generados
--    a maquina desde el prosrc VIVO capturado el 30/08 + los 2 parches).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
-- Pierna RECIBIDO: un episodio por (analista, lead) con asignacion en la
-- ventana. El origen/motivo son los del PRIMER episodio dentro de la ventana
-- (semantica viva del nucleo); `aproximado` si algun episodio lo fue.
select
  'recibido'::text,
  r.analista_id,
  r.lead_id,
  null::uuid,
  r.fue_referido,
  r.aproximado,
  r.motivo,
  false,
  r.origen_primero,
  null::text,
  null::date,
  null::numeric,
  null::text,
  r.primera_asignacion,
  null::timestamptz,
  case when r.fue_referido then 0 else 1 end,
  0::numeric
from (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] as origen_primero,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado,
    min(la.asignado_en) as primera_asignacion
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
) r

union all

-- Pierna CIERRE: una fila por asignacion convertida con resultado en la
-- ventana. Los cierres ANULADOS (ambos canales, via cierre_externo_anulado)
-- VIAJAN marcados con aporte 0: el nucleo los filtra; Distribucion (F2)
-- podra contarlos sin recalcular nada. El origen aqui es el del EPISODIO
-- (no el primero): semantica viva del nucleo.
select
  'cierre'::text,
  c.analista_id,
  c.lead_id,
  null::uuid,
  c.fue_referido,
  null::boolean,
  null::text,
  c.anulado,
  c.origen,
  null::text,
  c.mes_origen,
  null::numeric,
  null::text,
  null::timestamptz,
  c.fecha_cierre,
  0,
  case when c.anulado then 0
       when c.fue_referido then p_factor
       else 1 end
from (
  select
    la.analista_id, la.lead_id,
    (la.origen = 'referido') as fue_referido,
    la.origen,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    coalesce(la.resultado_en, la.finalizado_en) as fecha_cierre,
    private.cierre_externo_anulado(la.lead_id) as anulado
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
) c

union all

-- Pierna OPERACION: cartera elegible del periodo, MAXIMO UNA por cliente/mes
-- (la primera por fecha_operacion, creado_en, id — criterio vivo). El orden
-- se calcula ANTES del filtro de visibles (semantica viva). Con p_periodo
-- NULL la pierna queda vacia: los rangos libres no tienen mes de cartera.
select
  'operacion'::text,
  -- ATR-1: la atribucion es POLITICA de lectura — la cadena de upgrade
  -- adopta (contrato tecnico 2026-08-30); sin cadena, la regla vieja.
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid,
  o.id,
  false,
  null::boolean,
  null::text,
  false,
  null::text,
  o.tipo,
  o.periodo,
  -- monto NULL a proposito (Codex P8): sumar capitales seria aritmetica que
  -- el nucleo vivo jamas ejecuto; nadie la consume en F1. F2 decidira su forma.
  null::numeric,
  o.moneda,
  null::timestamptz,
  (o.fecha_operacion::timestamp at time zone 'America/Lima'),
  0,
  1::numeric
from (
  select o0.*,
    row_number() over (
      partition by o0.cliente_id, o0.periodo
      order by o0.fecha_operacion, o0.creado_en, o0.id
    ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.periodo = p_periodo
    and o0.elegible_conversion
) o
where p_periodo is not null
  and o.orden_conversion = 1
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles));
end;
$function$
;

CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      -- ATR-1: mismo resolutor que el nucleo de conversion (una politica).
      coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) as vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$function$
;

-- =====================================================================
-- 3) ORACULO en la misma transaccion: la foto de DESPUES contra la de ANTES.
--    Con la lista delta VACIA (lo medido hoy): PARIDAD EXACTA fila a fila.
--    Con delta: SOLO se mueven esas operaciones, del dueno al analista.
-- =====================================================================
do $$
declare v_n integer; v_m integer;
begin
  create temp table _atr1_ce_despues on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_despues on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;

  -- 3a) CONVERSION: mismo numero de filas, por mes y por pierna.
  select count(*) into v_n from _atr1_ce_antes;
  select count(*) into v_m from _atr1_ce_despues;
  if v_n <> v_m then
    raise exception 'ATR-1 oraculo: el numero de episodios cambio (% -> %)', v_n, v_m;
  end if;

  -- 3b) Las filas que difieren, EXACTAMENTE las del delta (dueno -> analista).
  create temp table _atr1_perdidas on commit drop as
    select * from _atr1_ce_antes except select * from _atr1_ce_despues;
  create temp table _atr1_ganadas on commit drop as
    select * from _atr1_ce_despues except select * from _atr1_ce_antes;

  select count(*) into v_n from _atr1_perdidas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (perdidas)', v_n;
  end if;
  select count(*) into v_n from _atr1_ganadas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (ganadas)', v_n;
  end if;

  -- 3c) Y las movidas van del dueno al analista con TODO lo demas identico.
  select count(*) into v_n from _atr1_perdidas p
   where not exists (
     select 1 from _atr1_ganadas g
     join _atr1_delta d on d.operacion_id = p.operacion_id
     where g.operacion_id = p.operacion_id
       and p.analista_id = d.dueno_id
       and g.analista_id = d.analista_id
       and g._mes = p._mes and g.tipo = p.tipo and g.categoria = p.categoria
       and g.moneda is not distinct from p.moneda
       and g.origen is not distinct from p.origen
       and g.mes_origen is not distinct from p.mes_origen
       and g.fecha_numerador is not distinct from p.fecha_numerador
       and g.aporte_divisor = p.aporte_divisor
       and g.aporte_numerador = p.aporte_numerador
       and g.lead_id is not distinct from p.lead_id
       and g.fue_referido is not distinct from p.fue_referido
       and g.aproximado is not distinct from p.aproximado
       and g.motivo is not distinct from p.motivo
       and g.anulado is not distinct from p.anulado
       and g.monto is not distinct from p.monto
       and g.fecha_divisor is not distinct from p.fecha_divisor);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas movidas no emparejan dueno->analista al byte', v_n;
  end if;

  -- 3d) ECONOMIA DE CARTERA: el dinero de renovaciones NO se mueve NUNCA en
  --     esta fase (el desglose es de renovaciones; F2 decidira la cadena).
  select count(*) into v_n
    from _atr1_mc_antes a
    full outer join _atr1_mc_despues d
      on d._mes = a._mes and d.vendedor_id = a.vendedor_id
   where coalesce(a.operaciones_renovacion, 0)      <> coalesce(d.operaciones_renovacion, 0)
      or coalesce(a.renovaciones_sin_desglose, 0)   <> coalesce(d.renovaciones_sin_desglose, 0)
      or coalesce(a.conversiones_renovacion, 0)     <> coalesce(d.conversiones_renovacion, 0)
      or coalesce(a.capital_renovado_pen, 0)        <> coalesce(d.capital_renovado_pen, 0)
      or coalesce(a.capital_renovado_usd, 0)        <> coalesce(d.capital_renovado_usd, 0)
      or coalesce(a.capital_adicional_pen, 0)       <> coalesce(d.capital_adicional_pen, 0)
      or coalesce(a.capital_adicional_usd, 0)       <> coalesce(d.capital_adicional_usd, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: la economia de RENOVACIONES se movio en % filas (debia quedar intacta)', v_n;
  end if;

  -- 3e) Los totales de upgrade de la EMPRESA no cambian (solo el reparto).
  select abs(coalesce((select sum(operaciones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(operaciones_upgrade) from _atr1_mc_despues), 0))
       + abs(coalesce((select sum(conversiones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(conversiones_upgrade) from _atr1_mc_despues), 0))
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el TOTAL de upgrades de la empresa cambio (delta %)', v_n;
  end if;

  -- 3e-bis) El reparto de OPERACIONES de upgrade por analista se mueve
  --         EXACTAMENTE segun la lista delta: dueno -n, analista +n.
  select count(*) into v_n
    from (
      select coalesce(a._mes, d._mes) as _mes,
             coalesce(a.vendedor_id, d.vendedor_id) as vendedor_id,
             coalesce(d.operaciones_upgrade, 0) - coalesce(a.operaciones_upgrade, 0) as mov
        from _atr1_mc_antes a
        full outer join _atr1_mc_despues d
          on d._mes = a._mes and d.vendedor_id = a.vendedor_id
    ) x
    left join (
      select periodo as _mes, dueno_id as vendedor_id, -count(*)::int as esperado
        from _atr1_delta group by periodo, dueno_id
      union all
      select periodo, analista_id, count(*)::int
        from _atr1_delta group by periodo, analista_id
    ) e on e._mes = x._mes and e.vendedor_id = x.vendedor_id
   where x.mov <> coalesce(e.esperado, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el reparto de upgrades por analista no cuadra con el delta (% filas)', v_n;
  end if;

  -- 3e-tris) Ninguna persona aparece o desaparece de la foto fuera del delta.
  select count(*) into v_n
    from (
      (select _mes, vendedor_id from _atr1_mc_antes
       except select _mes, vendedor_id from _atr1_mc_despues)
      union all
      (select _mes, vendedor_id from _atr1_mc_despues
       except select _mes, vendedor_id from _atr1_mc_antes)
    ) x
   where x.vendedor_id not in (
     select dueno_id from _atr1_delta union select analista_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % personas entran/salen de la foto fuera del delta', v_n;
  end if;

  -- 3f) Con delta VACIO, la paridad es EXACTA tambien en cartera.
  if (select count(*) from _atr1_delta) = 0 then
    select (select count(*) from (select * from _atr1_mc_antes except select * from _atr1_mc_despues) x)
         + (select count(*) from (select * from _atr1_mc_despues except select * from _atr1_mc_antes) x)
      into v_n;
    if v_n <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero cartera difiere en % filas', v_n;
    end if;
    if (select count(*) from _atr1_perdidas) + (select count(*) from _atr1_ganadas) <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero conversion difiere';
    end if;
  end if;

  -- 3g) El resolutor, contra datos REALES (sin fabricar nada):
  --     un upgrade -> su propio analista; un contrato nuevo -> NULL.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade'
     and private.analista_atribuido_cadena(o.contrato_nuevo_id) is distinct from c.analista_cierre_id;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor falla en % upgrades reales', v_n;
  end if;
  select count(*) into v_n
    from public.contratos c
   where coalesce(c.categoria, 'nuevo') = 'nuevo'
     and private.analista_atribuido_cadena(c.id) is not null;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor adopta % contratos NUEVOS (debia dar NULL)', v_n;
  end if;
end $$;

-- =====================================================================
-- 4) POSTFLIGHT: huellas nuevas, lo intocado intacto, ACL, firma y guardianes.
-- =====================================================================
do $$
declare v_h text; v_n integer;
begin
  -- Las dos tocadas quedaron EXACTAMENTE como este guion las trae:
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure;
  if v_h is distinct from '71213ac03eb32e333723399538d35d83' then
    raise exception 'ATR-1 postflight: conversion_episodios quedo con huella %', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h is distinct from 'f968879ae7f354a4165f1aebedc685b9' then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor quedo con huella %', v_h;
  end if;

  -- La firma de conversion_episodios es IDENTICA (su exclusion del censo F6.a es por firma).
  if (select pg_get_function_identity_arguments('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure))
     is distinct from 'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric' then
    raise exception 'ATR-1 postflight: la FIRMA de conversion_episodios cambio';
  end if;

  -- Ni un conteo nuevo en los cuerpos (el censo F6.a mide llamadas de conteo).
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure)
     <> 0 * length('count(') then
    raise exception 'ATR-1 postflight: conversion_episodios cambio sus conteos';
  end if;
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure)
     <> 6 * length('count(') then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor cambio sus conteos';
  end if;
  if exists (select 1 from pg_proc p
    where p.oid = 'private.analista_atribuido_cadena(uuid)'::regprocedure
      and (strpos(p.prosrc, 'count(') > 0 or strpos(p.prosrc, 'crm.leads') > 0)) then
    raise exception 'ATR-1 postflight: el resolutor trae conteos o leads (censo F6.a)';
  end if;

  -- Las SEIS intocadas, INTACTAS al byte:
  declare
    v_fn constant text[][] := array[
      array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
      array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
      array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
      array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
      array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
      array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
      array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
    ];
    v_fila text[];
  begin
    foreach v_fila slice 1 in array v_fn loop
      select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
      if v_h is distinct from v_fila[2] then
        raise exception 'ATR-1 postflight: % se movio y NO debia (huella %)', v_fila[1], v_h;
      end if;
    end loop;
  end;

  -- ACL literal de las 3 privates: solo postgres.
  foreach v_h in array array[
    'private.analista_atribuido_cadena(uuid)',
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
    'private.metricas_cartera_por_vendedor(date)'
  ] loop
    if (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure)
       is distinct from '{postgres=X/postgres}' then
      raise exception 'ATR-1 postflight: proacl de % no es {postgres=X/postgres} (%)', v_h,
        (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure);
    end if;
  end loop;

  -- El ledger, intacto en numero (ni una fila escrita por esta migracion).
  -- (la comparacion fina la dieron los oraculos; esto es el cinturon)
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_atr1$])
  on conflict (version) do nothing;

  select name, statements into v_nombre, v_a
    from supabase_migrations.schema_migrations where version='20260830223000';
  if not found then
    raise exception 'Registro ATR-1: la fila 20260830223000 no existe tras el insert'; end if;
  if v_nombre is distinct from 'crm_atr_1_upgrade_cuenta_a_quien_lo_hace' then
    raise exception 'Registro ATR-1: la fila quedo con OTRO nombre (%)', v_nombre; end if;
  if v_a is distinct from array[$mig_atr1$-- P-055 ATR-1 - EL UPGRADE CUENTA A QUIEN LO HACE (y agosto queda bien antes del sello).
--
-- DECISION DE MIGUEL (30/08, 4 respuestas firmadas; contrato tecnico en el vault:
-- "Contrato de la atribucion por cadena de upgrade (2026-08-30)"):
--   * upgrade -> cuenta al analista del selector (contratos.analista_cierre_id), no al dueno;
--   * la renovacion de ESE upgrade -> al mismo analista (adopcion por LINEA; la cadena
--     sigue al CONTRATO y relee el analista VIVO de la cabeza);
--   * asesor_perfil_id del cliente JAMAS cambia por un upgrade;
--   * incluye agosto (mes abierto; se re-atribuye POR LECTURA, ni una fila del ledger se toca);
--   * el Directorio del Portal SE QUEDA con la regla vieja (dos podios, a proposito).
--
-- DONDE VIVE LA REGLA: en la LECTURA. Una pieza nueva -private.analista_atribuido_cadena-
-- y dos nucleos que la preguntan con coalesce a su regla vieja:
--   * private.conversion_episodios, pierna 'operacion' (columna analista_id + filtro visibles);
--   * private.metricas_cartera_por_vendedor, bloque economia (select + group by).
-- El ledger crm.operaciones_cartera NO cambia: vendedor_id pasa a significar "quien ERA
-- el dueno al registrar" (HECHO); "a quien cuenta" es POLITICA del resolutor.
--
-- QUE NO SE TOCA (y el postflight lo pinnea por md5): crm.operaciones_cartera (ni una fila),
-- public.crear_contrato, private.capital_episodios, private.produccion_mes_por_vendedor,
-- crm.cerrar_periodo, private.registrar_ajuste_si_mes_cerrado,
-- crm.cumplimiento_metas_sin_cartera_fn, public.directorio_ranking_analistas,
-- perfiles.asesor_perfil_id. El capital de los upgrades YA iba al analista (F3.5b):
-- esta fase mueve SOLO conversion y economia de cartera. El capital por cadena de
-- renovaciones-de-upgrade es la ATR-2 (tras el sello del 10/09).
--
-- MEDIDO EL 30/08 CONTRA PRODUCCION: 46 upgrades en agosto, TODOS con analista = dueno
-- (delta VACIO -> el oraculo de hoy exige PARIDAD BYTE A BYTE; la lista de delta se
-- re-mide aqui por si nace un upgrade de un no-dueno antes del publish), 0 renovaciones
-- de cadena de upgrade, 0 upgrades sin analista.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines, invariantes y la foto de ANTES.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    -- las DOS que se tocan (cuerpo VIEJO exacto):
    array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '34acbfa8f6838b5f0ca6d5aa17d85d2a'],
    array['private.metricas_cartera_por_vendedor(date)',                                       'eeebe4e1385263dbdb6f3fdda81b1b93'],
    -- las SEIS que NO deben moverse (se re-verifican identicas en el postflight):
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
    array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
  ];
  v_fila text[]; v_h text; v_n integer;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-1 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- El resolutor aun no existe (este guion lo crea; si existe, alguien se adelanto).
  if to_regprocedure('private.analista_atribuido_cadena(uuid)') is not null then
    raise exception 'ATR-1 preflight: private.analista_atribuido_cadena ya existe';
  end if;

  -- Invariantes de agosto/mes abierto (el contrato tecnico las declara):
  --  a) 0 renovaciones cuya cadena termine en upgrade (nada que heredar todavia;
  --     si aparece una, la ATR-2 va primero o se re-mide a mano).
  select count(*) into v_n
    from crm.operaciones_cartera r
    join public.contratos co on co.id = r.contrato_origen_id
   where r.tipo = 'renovacion' and co.categoria = 'upgrade';
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % renovaciones de cadena de upgrade (se esperaba 0)', v_n;
  end if;
  --  a2) tipo del ledger = categoria del contrato, HOY sin divergencias (0 el
  --      30/08). Si un dia divergen (la puerta de edicion PUEDE corregir la
  --      categoria), la adopcion sigue a contratos.categoria POR DISENO
  --      (contrato tecnico): esto solo exige partir de un mundo limpio.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo is distinct from c.categoria;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % operaciones con tipo <> categoria del contrato (se esperaba 0)', v_n;
  end if;

  --  b) 0 upgrades sin analista (la puerta F3.7 lo garantiza desde el 29/08).
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade' and c.analista_cierre_id is null;
  if v_n <> 0 then
    raise exception 'ATR-1 preflight: % upgrades sin analista_cierre (se esperaba 0)', v_n;
  end if;

  -- CANDADO TEMPORAL (auditoria RLS, P2-4): la promesa "incluye agosto" solo
  -- vale ANTES del sello. Si agosto ya se sello y quedo algun upgrade de un
  -- no-dueno dentro, este publish llega TARDE y no debe fingir que no paso.
  if exists (select 1 from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01')
     and exists (
       select 1 from crm.operaciones_cartera o
       join public.contratos c on c.id = o.contrato_nuevo_id
       where o.periodo = date '2026-08-01' and o.tipo = 'upgrade'
         and c.analista_cierre_id is distinct from o.vendedor_id) then
    raise exception 'ATR-1 preflight: agosto YA esta sellado y contiene upgrades de no-duenos — el publish llego tarde; decidir con Miguel antes de aplicar';
  end if;

  -- La LISTA DELTA: upgrades de meses NO sellados con analista <> dueno. Son las
  -- UNICAS filas cuya atribucion puede moverse; el oraculo lo exige exacto.
  create temp table _atr1_delta on commit drop as
    select o.id as operacion_id, o.periodo,
           o.vendedor_id as dueno_id, c.analista_cierre_id as analista_id,
           o.elegible_conversion
      from crm.operaciones_cartera o
      join public.contratos c on c.id = o.contrato_nuevo_id
     where o.tipo = 'upgrade'
       and c.analista_cierre_id is distinct from o.vendedor_id
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  -- La foto de ANTES, por cada mes NO sellado con operaciones:
  create temp table _atr1_meses on commit drop as
    select distinct o.periodo from crm.operaciones_cartera o
     where not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = o.periodo);

  create temp table _atr1_ce_antes on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_antes on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;
end $$;

-- =====================================================================
-- 1) EL RESOLUTOR: una sola pieza semantica. La cadena sigue al CONTRATO
--    (relee el analista VIVO de la cabeza); sin cadena de upgrade -> NULL
--    y el consumidor cae a su regla vieja. Ciclos imposibles por esquema
--    (contrato_nuevo_id UNIQUE + indice unico sobre contrato_origen_id);
--    tope 100 de cinturon. SIN conteos: no entra al censo F6.a.
-- =====================================================================
create function private.analista_atribuido_cadena(p_contrato_id uuid)
returns uuid
language sql
stable
security invoker
set search_path to ''
as $resolutor$
  -- La ADOPCION MAS RECIENTE manda (auditoria Codex P1-1): se camina hacia
  -- atras y gana el PRIMER ancestro (o el propio contrato) con categoria
  -- 'upgrade' — asi una correccion de categoria por la puerta de edicion
  -- corrige tambien la adopcion de sus descendientes, en vez de saltarsela.
  -- Anti-ciclo por lista de visitados (dos filas cruzadas A<->B satisfacen
  -- los UNIQUE del esquema: el tope de nivel NO basta) + tope 100 de cinturon.
  with recursive cadena as (
    select p_contrato_id as contrato_id, 0 as nivel, array[p_contrato_id] as visitados
    union all
    select o.contrato_origen_id, c.nivel + 1, c.visitados || o.contrato_origen_id
      from cadena c
      join crm.operaciones_cartera o on o.contrato_nuevo_id = c.contrato_id
     where o.contrato_origen_id is not null
       and not (o.contrato_origen_id = any(c.visitados))
       and c.nivel < 100
  )
  select con.analista_cierre_id
    from cadena cd
    join public.contratos con on con.id = cd.contrato_id
   where con.categoria = 'upgrade'
   order by cd.nivel asc
   limit 1
$resolutor$;

revoke execute on function private.analista_atribuido_cadena(uuid) from public, anon, authenticated;

-- =====================================================================
-- 2) LOS DOS NUCLEOS, con la pregunta nueva (cuerpos completos, generados
--    a maquina desde el prosrc VIVO capturado el 30/08 + los 2 parches).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
-- Pierna RECIBIDO: un episodio por (analista, lead) con asignacion en la
-- ventana. El origen/motivo son los del PRIMER episodio dentro de la ventana
-- (semantica viva del nucleo); `aproximado` si algun episodio lo fue.
select
  'recibido'::text,
  r.analista_id,
  r.lead_id,
  null::uuid,
  r.fue_referido,
  r.aproximado,
  r.motivo,
  false,
  r.origen_primero,
  null::text,
  null::date,
  null::numeric,
  null::text,
  r.primera_asignacion,
  null::timestamptz,
  case when r.fue_referido then 0 else 1 end,
  0::numeric
from (
  select
    la.analista_id, la.lead_id,
    (array_agg(la.origen order by la.asignado_en asc))[1] as origen_primero,
    (array_agg(la.origen order by la.asignado_en asc))[1] = 'referido' as fue_referido,
    (array_agg(la.motivo_apertura order by la.asignado_en asc))[1] as motivo,
    bool_or(la.aproximado) as aproximado,
    min(la.asignado_en) as primera_asignacion
  from crm.lead_asignaciones la
  where la.asignado_en >= p_ini and la.asignado_en < p_fin
    and (p_global or la.analista_id = any(p_visibles))
  group by la.analista_id, la.lead_id
) r

union all

-- Pierna CIERRE: una fila por asignacion convertida con resultado en la
-- ventana. Los cierres ANULADOS (ambos canales, via cierre_externo_anulado)
-- VIAJAN marcados con aporte 0: el nucleo los filtra; Distribucion (F2)
-- podra contarlos sin recalcular nada. El origen aqui es el del EPISODIO
-- (no el primero): semantica viva del nucleo.
select
  'cierre'::text,
  c.analista_id,
  c.lead_id,
  null::uuid,
  c.fue_referido,
  null::boolean,
  null::text,
  c.anulado,
  c.origen,
  null::text,
  c.mes_origen,
  null::numeric,
  null::text,
  null::timestamptz,
  c.fecha_cierre,
  0,
  case when c.anulado then 0
       when c.fue_referido then p_factor
       else 1 end
from (
  select
    la.analista_id, la.lead_id,
    (la.origen = 'referido') as fue_referido,
    la.origen,
    date_trunc('month', la.asignado_en at time zone 'America/Lima')::date as mes_origen,
    coalesce(la.resultado_en, la.finalizado_en) as fecha_cierre,
    private.cierre_externo_anulado(la.lead_id) as anulado
  from crm.lead_asignaciones la
  where la.resultado = 'convertido'
    and coalesce(la.resultado_en, la.finalizado_en) >= p_ini
    and coalesce(la.resultado_en, la.finalizado_en) < p_fin
    and (p_global or la.analista_id = any(p_visibles))
) c

union all

-- Pierna OPERACION: cartera elegible del periodo, MAXIMO UNA por cliente/mes
-- (la primera por fecha_operacion, creado_en, id — criterio vivo). El orden
-- se calcula ANTES del filtro de visibles (semantica viva). Con p_periodo
-- NULL la pierna queda vacia: los rangos libres no tienen mes de cartera.
select
  'operacion'::text,
  -- ATR-1: la atribucion es POLITICA de lectura — la cadena de upgrade
  -- adopta (contrato tecnico 2026-08-30); sin cadena, la regla vieja.
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid,
  o.id,
  false,
  null::boolean,
  null::text,
  false,
  null::text,
  o.tipo,
  o.periodo,
  -- monto NULL a proposito (Codex P8): sumar capitales seria aritmetica que
  -- el nucleo vivo jamas ejecuto; nadie la consume en F1. F2 decidira su forma.
  null::numeric,
  o.moneda,
  null::timestamptz,
  (o.fecha_operacion::timestamp at time zone 'America/Lima'),
  0,
  1::numeric
from (
  select o0.*,
    row_number() over (
      partition by o0.cliente_id, o0.periodo
      order by o0.fecha_operacion, o0.creado_en, o0.id
    ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.periodo = p_periodo
    and o0.elegible_conversion
) o
where p_periodo is not null
  and o.orden_conversion = 1
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles));
end;
$function$
;

CREATE OR REPLACE FUNCTION private.metricas_cartera_por_vendedor(p_periodo date)
 RETURNS TABLE(vendedor_id uuid, conversiones_clientes integer, conversiones_renovacion integer, conversiones_upgrade integer, operaciones_renovacion integer, operaciones_upgrade integer, capital_renovado_pen numeric, capital_renovado_usd numeric, capital_adicional_pen numeric, capital_adicional_usd numeric, renovaciones_sin_desglose integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with ops as materialized (
    -- Los CONTEOS de operaciones siguen siendo del registro de operaciones
    -- (contar filas no es sumar capital); el DINERO sale del nucleo.
    select o.*
    from crm.operaciones_cartera o
    where o.periodo = p_periodo
  ), episodios_conversion as materialized (
    select
      e.analista_id as vendedor_id,
      e.categoria
    from private.conversion_episodios(
      p_ini => p_periodo::timestamp at time zone 'America/Lima',
      p_fin => (p_periodo + interval '1 month')::timestamp
        at time zone 'America/Lima',
      p_periodo => p_periodo,
      p_global => true,
      p_visibles => '{}'::uuid[],
      p_factor => 0::numeric
    ) e
    where e.tipo = 'operacion'
  ), conversion as (
    select
      e.vendedor_id,
      count(*)::int as conversiones_clientes,
      count(*) filter (
        where e.categoria = 'renovacion'
      )::int as conversiones_renovacion,
      count(*) filter (
        where e.categoria = 'upgrade'
      )::int as conversiones_upgrade
    from episodios_conversion e
    group by e.vendedor_id
  ), dinero as (
    -- El desglose renovado/adicional, del NUCLEO de capital (pierna desglose,
    -- solo renovaciones: los upgrades no llevan desglose por diseno).
    select
      k.analista_id as vendedor_id,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'PEN'), 0)
        as capital_renovado_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_renovado' and k.moneda = 'USD'), 0)
        as capital_renovado_usd,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'PEN'), 0)
        as capital_adicional_pen,
      coalesce(sum(k.monto) filter (
        where k.tipo = 'desglose_adicional' and k.moneda = 'USD'), 0)
        as capital_adicional_usd
    from private.capital_episodios(
           (p_periodo::timestamp at time zone 'America/Lima'),
           ((p_periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
           true, '{}'::uuid[]) k
    where k.tipo like 'desglose_%' and k.categoria = 'renovacion'
      and k.mes_comercial = p_periodo
    group by k.analista_id
  ), economia as (
    select
      -- ATR-1: mismo resolutor que el nucleo de conversion (una politica).
      coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) as vendedor_id,
      count(*) filter (where o.tipo = 'renovacion')::int
        as operaciones_renovacion,
      count(*) filter (where o.tipo = 'upgrade')::int
        as operaciones_upgrade,
      count(*) filter (
        where o.tipo = 'renovacion' and not o.desglose_completo
      )::int as renovaciones_sin_desglose
    from ops o
    group by coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
  ), personas as (
    select c.vendedor_id from conversion c
    union
    select e.vendedor_id from economia e
    union
    select d.vendedor_id from dinero d
  )
  select
    p.vendedor_id,
    coalesce(c.conversiones_clientes, 0),
    coalesce(c.conversiones_renovacion, 0),
    coalesce(c.conversiones_upgrade, 0),
    coalesce(e.operaciones_renovacion, 0),
    coalesce(e.operaciones_upgrade, 0),
    coalesce(d.capital_renovado_pen, 0),
    coalesce(d.capital_renovado_usd, 0),
    coalesce(d.capital_adicional_pen, 0),
    coalesce(d.capital_adicional_usd, 0),
    coalesce(e.renovaciones_sin_desglose, 0)
  from personas p
  left join conversion c using (vendedor_id)
  left join dinero d using (vendedor_id)
  left join economia e using (vendedor_id)
$function$
;

-- =====================================================================
-- 3) ORACULO en la misma transaccion: la foto de DESPUES contra la de ANTES.
--    Con la lista delta VACIA (lo medido hoy): PARIDAD EXACTA fila a fila.
--    Con delta: SOLO se mueven esas operaciones, del dueno al analista.
-- =====================================================================
do $$
declare v_n integer; v_m integer;
begin
  create temp table _atr1_ce_despues on commit drop as
    select m.periodo as _mes, e.*
      from _atr1_meses m
      cross join lateral private.conversion_episodios(
        (m.periodo::timestamp at time zone 'America/Lima'),
        ((m.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        m.periodo, true, '{}'::uuid[], 1) e;

  create temp table _atr1_mc_despues on commit drop as
    select m.periodo as _mes, x.*
      from _atr1_meses m
      cross join lateral private.metricas_cartera_por_vendedor(m.periodo) x;

  -- 3a) CONVERSION: mismo numero de filas, por mes y por pierna.
  select count(*) into v_n from _atr1_ce_antes;
  select count(*) into v_m from _atr1_ce_despues;
  if v_n <> v_m then
    raise exception 'ATR-1 oraculo: el numero de episodios cambio (% -> %)', v_n, v_m;
  end if;

  -- 3b) Las filas que difieren, EXACTAMENTE las del delta (dueno -> analista).
  create temp table _atr1_perdidas on commit drop as
    select * from _atr1_ce_antes except select * from _atr1_ce_despues;
  create temp table _atr1_ganadas on commit drop as
    select * from _atr1_ce_despues except select * from _atr1_ce_antes;

  select count(*) into v_n from _atr1_perdidas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (perdidas)', v_n;
  end if;
  select count(*) into v_n from _atr1_ganadas
   where tipo <> 'operacion'
      or operacion_id not in (select operacion_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas se movieron FUERA del delta declarado (ganadas)', v_n;
  end if;

  -- 3c) Y las movidas van del dueno al analista con TODO lo demas identico.
  select count(*) into v_n from _atr1_perdidas p
   where not exists (
     select 1 from _atr1_ganadas g
     join _atr1_delta d on d.operacion_id = p.operacion_id
     where g.operacion_id = p.operacion_id
       and p.analista_id = d.dueno_id
       and g.analista_id = d.analista_id
       and g._mes = p._mes and g.tipo = p.tipo and g.categoria = p.categoria
       and g.moneda is not distinct from p.moneda
       and g.origen is not distinct from p.origen
       and g.mes_origen is not distinct from p.mes_origen
       and g.fecha_numerador is not distinct from p.fecha_numerador
       and g.aporte_divisor = p.aporte_divisor
       and g.aporte_numerador = p.aporte_numerador
       and g.lead_id is not distinct from p.lead_id
       and g.fue_referido is not distinct from p.fue_referido
       and g.aproximado is not distinct from p.aproximado
       and g.motivo is not distinct from p.motivo
       and g.anulado is not distinct from p.anulado
       and g.monto is not distinct from p.monto
       and g.fecha_divisor is not distinct from p.fecha_divisor);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % filas movidas no emparejan dueno->analista al byte', v_n;
  end if;

  -- 3d) ECONOMIA DE CARTERA: el dinero de renovaciones NO se mueve NUNCA en
  --     esta fase (el desglose es de renovaciones; F2 decidira la cadena).
  select count(*) into v_n
    from _atr1_mc_antes a
    full outer join _atr1_mc_despues d
      on d._mes = a._mes and d.vendedor_id = a.vendedor_id
   where coalesce(a.operaciones_renovacion, 0)      <> coalesce(d.operaciones_renovacion, 0)
      or coalesce(a.renovaciones_sin_desglose, 0)   <> coalesce(d.renovaciones_sin_desglose, 0)
      or coalesce(a.conversiones_renovacion, 0)     <> coalesce(d.conversiones_renovacion, 0)
      or coalesce(a.capital_renovado_pen, 0)        <> coalesce(d.capital_renovado_pen, 0)
      or coalesce(a.capital_renovado_usd, 0)        <> coalesce(d.capital_renovado_usd, 0)
      or coalesce(a.capital_adicional_pen, 0)       <> coalesce(d.capital_adicional_pen, 0)
      or coalesce(a.capital_adicional_usd, 0)       <> coalesce(d.capital_adicional_usd, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: la economia de RENOVACIONES se movio en % filas (debia quedar intacta)', v_n;
  end if;

  -- 3e) Los totales de upgrade de la EMPRESA no cambian (solo el reparto).
  select abs(coalesce((select sum(operaciones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(operaciones_upgrade) from _atr1_mc_despues), 0))
       + abs(coalesce((select sum(conversiones_upgrade) from _atr1_mc_antes), 0)
           - coalesce((select sum(conversiones_upgrade) from _atr1_mc_despues), 0))
    into v_n;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el TOTAL de upgrades de la empresa cambio (delta %)', v_n;
  end if;

  -- 3e-bis) El reparto de OPERACIONES de upgrade por analista se mueve
  --         EXACTAMENTE segun la lista delta: dueno -n, analista +n.
  select count(*) into v_n
    from (
      select coalesce(a._mes, d._mes) as _mes,
             coalesce(a.vendedor_id, d.vendedor_id) as vendedor_id,
             coalesce(d.operaciones_upgrade, 0) - coalesce(a.operaciones_upgrade, 0) as mov
        from _atr1_mc_antes a
        full outer join _atr1_mc_despues d
          on d._mes = a._mes and d.vendedor_id = a.vendedor_id
    ) x
    left join (
      select periodo as _mes, dueno_id as vendedor_id, -count(*)::int as esperado
        from _atr1_delta group by periodo, dueno_id
      union all
      select periodo, analista_id, count(*)::int
        from _atr1_delta group by periodo, analista_id
    ) e on e._mes = x._mes and e.vendedor_id = x.vendedor_id
   where x.mov <> coalesce(e.esperado, 0);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el reparto de upgrades por analista no cuadra con el delta (% filas)', v_n;
  end if;

  -- 3e-tris) Ninguna persona aparece o desaparece de la foto fuera del delta.
  select count(*) into v_n
    from (
      (select _mes, vendedor_id from _atr1_mc_antes
       except select _mes, vendedor_id from _atr1_mc_despues)
      union all
      (select _mes, vendedor_id from _atr1_mc_despues
       except select _mes, vendedor_id from _atr1_mc_antes)
    ) x
   where x.vendedor_id not in (
     select dueno_id from _atr1_delta union select analista_id from _atr1_delta);
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: % personas entran/salen de la foto fuera del delta', v_n;
  end if;

  -- 3f) Con delta VACIO, la paridad es EXACTA tambien en cartera.
  if (select count(*) from _atr1_delta) = 0 then
    select (select count(*) from (select * from _atr1_mc_antes except select * from _atr1_mc_despues) x)
         + (select count(*) from (select * from _atr1_mc_despues except select * from _atr1_mc_antes) x)
      into v_n;
    if v_n <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero cartera difiere en % filas', v_n;
    end if;
    if (select count(*) from _atr1_perdidas) + (select count(*) from _atr1_ganadas) <> 0 then
      raise exception 'ATR-1 oraculo: delta vacio pero conversion difiere';
    end if;
  end if;

  -- 3g) El resolutor, contra datos REALES (sin fabricar nada):
  --     un upgrade -> su propio analista; un contrato nuevo -> NULL.
  select count(*) into v_n
    from crm.operaciones_cartera o
    join public.contratos c on c.id = o.contrato_nuevo_id
   where o.tipo = 'upgrade'
     and private.analista_atribuido_cadena(o.contrato_nuevo_id) is distinct from c.analista_cierre_id;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor falla en % upgrades reales', v_n;
  end if;
  select count(*) into v_n
    from public.contratos c
   where coalesce(c.categoria, 'nuevo') = 'nuevo'
     and private.analista_atribuido_cadena(c.id) is not null;
  if v_n <> 0 then
    raise exception 'ATR-1 oraculo: el resolutor adopta % contratos NUEVOS (debia dar NULL)', v_n;
  end if;
end $$;

-- =====================================================================
-- 4) POSTFLIGHT: huellas nuevas, lo intocado intacto, ACL, firma y guardianes.
-- =====================================================================
do $$
declare v_h text; v_n integer;
begin
  -- Las dos tocadas quedaron EXACTAMENTE como este guion las trae:
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure;
  if v_h is distinct from '71213ac03eb32e333723399538d35d83' then
    raise exception 'ATR-1 postflight: conversion_episodios quedo con huella %', v_h;
  end if;
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure;
  if v_h is distinct from 'f968879ae7f354a4165f1aebedc685b9' then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor quedo con huella %', v_h;
  end if;

  -- La firma de conversion_episodios es IDENTICA (su exclusion del censo F6.a es por firma).
  if (select pg_get_function_identity_arguments('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure))
     is distinct from 'p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric' then
    raise exception 'ATR-1 postflight: la FIRMA de conversion_episodios cambio';
  end if;

  -- Ni un conteo nuevo en los cuerpos (el censo F6.a mide llamadas de conteo).
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)'::regprocedure)
     <> 0 * length('count(') then
    raise exception 'ATR-1 postflight: conversion_episodios cambio sus conteos';
  end if;
  if (select length(p.prosrc) - length(replace(p.prosrc, 'count(', '')) from pg_proc p
      where p.oid = 'private.metricas_cartera_por_vendedor(date)'::regprocedure)
     <> 6 * length('count(') then
    raise exception 'ATR-1 postflight: metricas_cartera_por_vendedor cambio sus conteos';
  end if;
  if exists (select 1 from pg_proc p
    where p.oid = 'private.analista_atribuido_cadena(uuid)'::regprocedure
      and (strpos(p.prosrc, 'count(') > 0 or strpos(p.prosrc, 'crm.leads') > 0)) then
    raise exception 'ATR-1 postflight: el resolutor trae conteos o leads (censo F6.a)';
  end if;

  -- Las SEIS intocadas, INTACTAS al byte:
  declare
    v_fn constant text[][] := array[
      array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
      array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
      array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
      array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
      array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
      array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
      array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366']
    ];
    v_fila text[];
  begin
    foreach v_fila slice 1 in array v_fn loop
      select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
      if v_h is distinct from v_fila[2] then
        raise exception 'ATR-1 postflight: % se movio y NO debia (huella %)', v_fila[1], v_h;
      end if;
    end loop;
  end;

  -- ACL literal de las 3 privates: solo postgres.
  foreach v_h in array array[
    'private.analista_atribuido_cadena(uuid)',
    'private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)',
    'private.metricas_cartera_por_vendedor(date)'
  ] loop
    if (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure)
       is distinct from '{postgres=X/postgres}' then
      raise exception 'ATR-1 postflight: proacl de % no es {postgres=X/postgres} (%)', v_h,
        (select p.proacl::text from pg_proc p where p.oid = v_h::regprocedure);
    end if;
  end loop;

  -- El ledger, intacto en numero (ni una fila escrita por esta migracion).
  -- (la comparacion fina la dieron los oraculos; esto es el cinturon)
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

commit;
$mig_atr1$] then
    raise exception 'Registro ATR-1: la fila quedo con OTRO cuerpo (posible insert concurrente)'; end if;
end $reg_atr1$;
