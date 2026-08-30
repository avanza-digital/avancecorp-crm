begin;
-- P-055 ATR-2 - LA RENOVACION DEL UPGRADE HEREDA A SU ANALISTA (capital y metas).
--
-- Segunda fase del tren de atribucion por cadena (contrato tecnico 2026-08-30;
-- ATR-1 = registro 187 puso la regla en conversion y economia de cartera).
-- Aqui el NUCLEO DE CAPITAL pregunta la MISMA politica: en la pierna CONTRATO
-- y en la pierna DESGLOSE (6 parches + 1 comentario), el analista, su en_roster y el filtro de visibles
-- pasan JUNTOS (regla de los 3 puntos) a
--   coalesce(private.analista_atribuido_cadena(...), <regla vieja>).
-- La pierna COOPERATIVA queda intacta. Por transitividad y SIN tocarles el
-- cuerpo heredan: produccion_mes_por_vendedor -> cumplimiento_metas -> el SELLO
-- (cerrar_periodo), metricas_capital/vencimientos, y el bloque dinero de
-- metricas_cartera_por_vendedor.
--
-- EFECTO EN NUMEROS DE HOY: CERO. Un upgrade ya atribuye su capital a su
-- analista (el resolutor devuelve su propio analista_cierre_id: no-op); solo
-- una RENOVACION DE CADENA DE UPGRADE se mueve, y hoy hay 0 (el preflight
-- re-mide y el oraculo exige que SOLO se muevan las que haya).
--
-- DOS LENTES QUE RECORTAN POR CARTERA (P1-1 de Codex, DECLARADO): las RPC
-- metricas_capital_mes_fn y metricas_vencimientos_fn agregan del nucleo pero
-- recortan la VISIBILIDAD del que mira por cli.asesor_perfil_id (cartera),
-- igual que el Directorio. Con una cadena adoptada, el capital CUENTA al
-- analista de la cadena (columna) pero esas dos lentes lo ENSEÑAN en la vista
-- de la cartera del dueno. Es la misma familia que la lente del Directorio;
-- si Miguel quiere alinearlas al analista resuelto, es decision de pantalla
-- (candidata a ATR-3), no efecto colateral de esta migracion.
--
-- CALENDARIO: publicar 11-12/09, CON AGOSTO YA SELLADO (el sello del 10/09
-- captura la conversion nueva de ATR-1; el capital no cambia con delta vacio,
-- pero el nucleo del sello no se toca la vispera POR DISCIPLINA).


set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines, delta y la foto de ANTES.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    -- LA que se toca (cuerpo viejo exacto):
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '872f5ad4362f66a18f4a3806453f78a0'],
    -- el resolutor DEBE existir y ser el de ATR-1:
    array['private.analista_atribuido_cadena(uuid)',                           'e39016e2913cce47faabee29c2c38fe2'],
    -- el mundo alrededor, INTACTO (se re-verifica identico en el postflight):
    array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '71213ac03eb32e333723399538d35d83'],
    array['private.metricas_cartera_por_vendedor(date)',                       'f968879ae7f354a4165f1aebedc685b9'],
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
    array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366'],
    array['private.capital_autorizada(date,date,text)',                        'dc499b1f12693e6e724ef93848dda1ac'],
    array['private.metricas_conversiones_implementacion(date,date,text)',      '4642129507df5a0effe69c94e51b10bf']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-2 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- La LISTA DELTA de la pierna CONTRATO: contratos cuya atribucion resuelta
  -- difiere de la vieja (= renovaciones de cadena de upgrade; hoy 0).
  create temp table _atr2_delta_c on commit drop as
    select c.id as contrato_id,
           c.analista_cierre_id as viejo_id,
           private.analista_atribuido_cadena(c.id) as nuevo_id
      from public.contratos c
     where not c.es_demo
       and private.analista_atribuido_cadena(c.id) is distinct from c.analista_cierre_id
       and private.analista_atribuido_cadena(c.id) is not null;

  -- Y la de la pierna DESGLOSE (operaciones con desglose cuya atribucion cambia).
  create temp table _atr2_delta_d on commit drop as
    select o.contrato_nuevo_id as contrato_id,
           o.vendedor_id as viejo_id,
           private.analista_atribuido_cadena(o.contrato_nuevo_id) as nuevo_id
      from crm.operaciones_cartera o
     where (o.capital_renovado is not null or o.capital_adicional is not null)
       and private.analista_atribuido_cadena(o.contrato_nuevo_id) is distinct from o.vendedor_id
       and private.analista_atribuido_cadena(o.contrato_nuevo_id) is not null;

  -- Las filas de un mes YA SELLADO no deben moverse NI EN LA LECTURA CRUDA del
  -- nucleo sin que quede dicho: si una renovacion de cadena cayera en mes
  -- sellado, la foto del sello no cambia (es foto), pero la lectura viva si.
  -- Se declara: hoy ambas listas se esperan vacias; si no lo estan, el oraculo
  -- exige que el movimiento sea EXACTAMENTE ese.

  -- CANDADO DE CALENDARIO (auditor RLS, P2-1; espejo del de ATR-1): esta fase
  -- se publica CON agosto sellado. Si agosto sigue abierto y ya existiera una
  -- renovacion-de-cadena con mes agosto, publicar ahora moveria capital/metas
  -- la vispera del sello: se ABORTA y se decide con Miguel.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01')
     and (exists (select 1 from _atr2_delta_c dc
                  join public.contratos c on c.id = dc.contrato_id
                  where date_trunc('month', c.fecha_cierre_comercial)::date = date '2026-08-01')
       or exists (select 1 from _atr2_delta_d dd
                  join crm.operaciones_cartera o on o.contrato_nuevo_id = dd.contrato_id
                  where o.periodo = date '2026-08-01')) then
    raise exception 'ATR-2 preflight: agosto sigue ABIERTO y hay renovaciones-de-cadena de agosto — no se publica la vispera del sello; decidir con Miguel';
  end if;

  -- FOTO DE ANTES: el nucleo entero, rango total, global.
  create temp table _atr2_cap_antes on commit drop as
    select * from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]);

  -- Y produccion de los meses NO sellados que tengan cuadro de metas.
  create temp table _atr2_prod_antes on commit drop as
    select mp.periodo as _mes, r.*
      from (select distinct mp0.periodo, mp0.id,
                   row_number() over (partition by mp0.periodo order by mp0.revision desc) as rn
              from crm.meta_periodos mp0) mp
      cross join lateral private.produccion_mes_por_vendedor(
        (mp.periodo::timestamp at time zone 'America/Lima'),
        ((mp.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        mp.id) r
     where mp.rn = 1
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo);
end $$;

-- =====================================================================
-- 1) EL NUCLEO DE CAPITAL, con la pregunta (cuerpo completo generado a
--    maquina desde el prosrc VIVO + los 6 parches de las dos piernas).
-- =====================================================================
CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    -- ATR-2: la cadena de upgrade adopta tambien el CAPITAL (contrato 2026-08-30).
    coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id),
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$function$
;

-- =====================================================================
-- 2) ORACULO en la misma transaccion.
-- =====================================================================
do $$
declare v_n integer; v_m integer;
begin
  create temp table _atr2_cap_despues on commit drop as
    select * from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]);

  select count(*) into v_n from _atr2_cap_antes;
  select count(*) into v_m from _atr2_cap_despues;
  if v_n <> v_m then
    raise exception 'ATR-2 oraculo: el numero de episodios cambio (% -> %)', v_n, v_m;
  end if;

  create temp table _atr2_perdidas on commit drop as
    select * from _atr2_cap_antes except select * from _atr2_cap_despues;
  create temp table _atr2_ganadas on commit drop as
    select * from _atr2_cap_despues except select * from _atr2_cap_antes;

  -- Toda fila movida pertenece a un contrato del delta (de cualquiera de las
  -- dos listas) y es de las piernas contrato/desglose (cooperativa JAMAS).
  select count(*) into v_n from _atr2_perdidas p
   where p.tipo not like 'contrato_%' and p.tipo not like 'desglose_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas FUERA de las piernas contrato/desglose', v_n;
  end if;
  select count(*) into v_n from _atr2_perdidas p
   where p.contrato_id not in (select contrato_id from _atr2_delta_c
                               union select contrato_id from _atr2_delta_d);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas fuera del delta (perdidas)', v_n;
  end if;
  select count(*) into v_n from _atr2_ganadas g
   where g.contrato_id not in (select contrato_id from _atr2_delta_c
                               union select contrato_id from _atr2_delta_d);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas fuera del delta (ganadas)', v_n;
  end if;

  -- Emparejamiento viejo->nuevo al byte en TODO salvo analista y en_roster
  -- (en_roster es DERIVADO del analista: cambia con el, y su verdad la
  -- re-verifica 2c contra el cuadro de metas).
  select count(*) into v_n from _atr2_perdidas p
   where not exists (
     select 1 from _atr2_ganadas g
     join _atr2_delta_c dc on dc.contrato_id = p.contrato_id
     where g.contrato_id = p.contrato_id and g.tipo = p.tipo and g.medida = p.medida
       and p.analista_id is not distinct from dc.viejo_id
       and g.analista_id = dc.nuevo_id
       and g.moneda is not distinct from p.moneda
       and g.monto is not distinct from p.monto
       and g.categoria is not distinct from p.categoria
       and g.mes_comercial is not distinct from p.mes_comercial
       and g.fecha is not distinct from p.fecha
       and g.fecha_vencimiento is not distinct from p.fecha_vencimiento
       and g.estado is not distinct from p.estado
       and g.anulado = p.anulado
       and g.cliente_id is not distinct from p.cliente_id
       and g.registrado_por is not distinct from p.registrado_por
       and g.cierre_externo_id is not distinct from p.cierre_externo_id
       and g.lead_id is not distinct from p.lead_id)
     and p.tipo like 'contrato_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas contrato no emparejan viejo->nuevo', v_n;
  end if;
  select count(*) into v_n from _atr2_perdidas p
   where not exists (
     select 1 from _atr2_ganadas g
     join _atr2_delta_d dd on dd.contrato_id = p.contrato_id
     where g.contrato_id = p.contrato_id and g.tipo = p.tipo and g.medida = p.medida
       and p.analista_id is not distinct from dd.viejo_id
       and g.analista_id = dd.nuevo_id
       and g.moneda is not distinct from p.moneda
       and g.monto is not distinct from p.monto
       and g.categoria is not distinct from p.categoria
       and g.mes_comercial is not distinct from p.mes_comercial
       and g.fecha is not distinct from p.fecha
       and g.fecha_vencimiento is not distinct from p.fecha_vencimiento
       and g.estado is not distinct from p.estado
       and g.anulado = p.anulado
       and g.cliente_id is not distinct from p.cliente_id
       and g.registrado_por is not distinct from p.registrado_por
       and g.cierre_externo_id is not distinct from p.cierre_externo_id
       and g.lead_id is not distinct from p.lead_id)
     and p.tipo like 'desglose_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas desglose no emparejan viejo->nuevo', v_n;
  end if;

  -- 2b) El DINERO de la empresa, por tipo/medida/moneda, al centimo.
  select count(*) into v_n from (
    select tipo, medida, moneda, sum(monto) s from _atr2_cap_antes group by 1,2,3
    except
    select tipo, medida, moneda, sum(monto) from _atr2_cap_despues group by 1,2,3
  ) x;
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: los TOTALES de capital por tipo/medida/moneda cambiaron';
  end if;

  -- 2c) en_roster de las ganadas = la verdad del cuadro de metas del NUEVO analista.
  select count(*) into v_n from _atr2_ganadas g
   where g.tipo like 'contrato_%' or g.tipo like 'desglose_%';
  select count(*) into v_m from _atr2_ganadas g
   where (g.tipo like 'contrato_%' or g.tipo like 'desglose_%')
     and g.en_roster = exists (
       select 1 from crm.metas_vendedor mv
       where mv.meta_periodo_id = (select mp.id from crm.meta_periodos mp
                                   where mp.periodo = g.mes_comercial
                                   order by mp.revision desc limit 1)
         and mv.vendedor_id = g.analista_id);
  if v_n <> v_m then
    raise exception 'ATR-2 oraculo: en_roster de % filas ganadas no dice la verdad del cuadro', v_n - v_m;
  end if;

  -- 2d) Con deltas VACIOS (lo esperado hoy): PARIDAD EXACTA del nucleo entero.
  if (select count(*) from _atr2_delta_c) = 0 and (select count(*) from _atr2_delta_d) = 0 then
    if (select count(*) from _atr2_perdidas) + (select count(*) from _atr2_ganadas) <> 0 then
      raise exception 'ATR-2 oraculo: deltas vacios pero el nucleo difiere';
    end if;
  end if;

  -- 2e) PRODUCCION de los meses abiertos: identica salvo personas del delta.
  create temp table _atr2_prod_despues on commit drop as
    select mp.periodo as _mes, r.*
      from (select distinct mp0.periodo, mp0.id,
                   row_number() over (partition by mp0.periodo order by mp0.revision desc) as rn
              from crm.meta_periodos mp0) mp
      cross join lateral private.produccion_mes_por_vendedor(
        (mp.periodo::timestamp at time zone 'America/Lima'),
        ((mp.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        mp.id) r
     where mp.rn = 1
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo);

  select count(*) into v_n from (
    (select * from _atr2_prod_antes except select * from _atr2_prod_despues)
    union all
    (select * from _atr2_prod_despues except select * from _atr2_prod_antes)
  ) x
  where x.vendedor_id is null
     or x.vendedor_id not in (select viejo_id from _atr2_delta_c where viejo_id is not null
                              union select nuevo_id from _atr2_delta_c);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: produccion del mes abierto se movio fuera del delta (% filas)', v_n;
  end if;
end $$;

-- =====================================================================
-- 3) POSTFLIGHT: huella nueva, mundo intacto, ACL, firma y guardianes.
-- =====================================================================
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from '90f1d8c2342becb94cc3d3e023227078' then
    raise exception 'ATR-2 postflight: capital_episodios quedo con huella %', v_h;
  end if;
  if (select pg_get_function_identity_arguments('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure))
     is distinct from 'p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[]' then
    raise exception 'ATR-2 postflight: la FIRMA de capital_episodios cambio';
  end if;
  if exists (select 1 from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
        and (p.prosrc ~* 'count\s*\(' or p.prosrc ~* 'sum\s*\(\s*1\s*\)')) then
    raise exception 'ATR-2 postflight: capital_episodios gano un conteo (censo F6.a)';
  end if;

  declare
    v_fn constant text[][] := array[
      array['private.analista_atribuido_cadena(uuid)',                           'e39016e2913cce47faabee29c2c38fe2'],
      array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '71213ac03eb32e333723399538d35d83'],
      array['private.metricas_cartera_por_vendedor(date)',                       'f968879ae7f354a4165f1aebedc685b9'],
      array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
      array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
      array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
      array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
      array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
      array['public.crear_contrato(jsonb,jsonb)',                                '4c25cee5a36c2144c45a061eaddb5366'],
        array['private.capital_autorizada(date,date,text)',                        'dc499b1f12693e6e724ef93848dda1ac'],
      array['private.metricas_conversiones_implementacion(date,date,text)',      '4642129507df5a0effe69c94e51b10bf']
    ];
    v_fila text[];
  begin
    foreach v_fila slice 1 in array v_fn loop
      select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
      if v_h is distinct from v_fila[2] then
        raise exception 'ATR-2 postflight: % se movio y NO debia (huella %)', v_fila[1], v_h;
      end if;
    end loop;
  end;

  if (select p.proacl::text from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'ATR-2 postflight: proacl de capital_episodios no es {postgres=X/postgres}';
  end if;

  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;

-- ============================================================
-- SINTETICA (solo ensayo, TODO se deshace): cadena real fabricada
-- U(analista X, cliente de Y) <- R <- R2, mas R3 de cadena rota.
-- ============================================================
do $sint$
declare
  v_an uuid[]; vX uuid; vY uuid; vZ uuid; vW uuid; v_cli uuid;
  v_row public.contratos%rowtype;
  vU uuid := gen_random_uuid(); vR uuid := gen_random_uuid();
  vR2 uuid := gen_random_uuid(); vR3 uuid := gen_random_uuid();
  v_mesU date; v_a uuid; v_n integer;
begin
  select array_agg(perfil_id order by perfil_id) into v_an
    from (select e.perfil_id
            from crm.equipo e join public.perfiles p on p.id = e.perfil_id
           where e.activo and p.activo and e.rol_crm = 'vendedor'
           limit 4) t;
  if array_length(v_an, 1) < 4 then
    raise exception 'SINTETICA: hacen falta 4 analistas vigentes';
  end if;
  vX := v_an[1]; vY := v_an[2]; vZ := v_an[3]; vW := v_an[4];
  select p.id into strict v_cli from public.perfiles p
   where p.rol = 'cliente' and p.activo limit 1;

  select c.* into strict v_row from public.contratos c
   where not c.es_demo and c.moneda = 'PEN' limit 1;

  -- Con producto_condicion_id NULL, el trigger del catalogo fabrica un
  -- snapshot legacy PROPIO por cada contrato (camino declarado del trigger).
  v_row.producto_condicion_id := null;
  -- Y la fecha de cierre comercial LA PONE EL SERVIDOR (su trigger la
  -- calcula y prohibe enviarla en el alta): va NULL, igual que su fuente.
  v_row.fecha_cierre_comercial := null;
  v_row.fuente_cierre_comercial := null;

  -- U: el upgrade de X sobre el cliente (dueno Y)
  v_row.id := vU; v_row.numero_contrato := 'ATR2-ENSAYO-U';
  v_row.cliente_id := v_cli; v_row.categoria := 'upgrade';
  v_row.analista_cierre_id := vX; v_row.renovado_a_id := null;
  v_row.estado := 'activo'; v_row.es_demo := false; v_row.capital := 1000;
  insert into public.contratos select (v_row).*;
  select date_trunc('month', c.fecha_cierre_comercial)::date into v_mesU
    from public.contratos c where c.id = vU;
  insert into crm.operaciones_cartera
    (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
     fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
     elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_cli, vY, 'upgrade', null, vU,
     (select fecha_cierre_comercial from public.contratos where id = vU), v_mesU,
     'PEN', null, null, false, true, 'flujo_cartera', vY);

  -- R: renovacion de U, digitada/atribuida a Z en el hecho F3
  v_row.id := vR; v_row.numero_contrato := 'ATR2-ENSAYO-R';
  v_row.analista_cierre_id := vZ; v_row.categoria := 'renovacion';
  insert into public.contratos select (v_row).*;
  insert into crm.operaciones_cartera
    (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
     fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
     elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_cli, vY, 'renovacion', vU, vR,
     (select fecha_cierre_comercial from public.contratos where id = vR),
     (select date_trunc('month', fecha_cierre_comercial)::date from public.contratos where id = vR),
     'PEN', 800, 200, true, true, 'flujo_cartera', vZ);

  -- R2: renovacion de R (multi-salto)
  v_row.id := vR2; v_row.numero_contrato := 'ATR2-ENSAYO-R2';
  v_row.analista_cierre_id := vW;
  insert into public.contratos select (v_row).*;
  insert into crm.operaciones_cartera
    (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
     fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
     elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_cli, vY, 'renovacion', vR, vR2,
     (select fecha_cierre_comercial from public.contratos where id = vR2),
     (select date_trunc('month', fecha_cierre_comercial)::date from public.contratos where id = vR2),
     'PEN', 900, 100, true, true, 'flujo_cartera', vZ);

  -- R3: renovacion de cadena ROTA (backfill sin origen)
  v_row.id := vR3; v_row.numero_contrato := 'ATR2-ENSAYO-R3';
  v_row.analista_cierre_id := vW;
  insert into public.contratos select (v_row).*;
  insert into crm.operaciones_cartera
    (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
     fecha_operacion, periodo, moneda, capital_renovado, capital_adicional,
     elegible_conversion, desglose_completo, fuente, creado_por)
  values (v_cli, vY, 'renovacion', null, vR3,
     (select fecha_cierre_comercial from public.contratos where id = vR3),
     (select date_trunc('month', fecha_cierre_comercial)::date from public.contratos where id = vR3),
     'PEN', null, null, true, false, 'backfill_agosto_2026', vZ);

  -- ASSERTS de conducta sobre el nucleo YA PARCHEADO:
  -- a) U atribuye a su propio analista X (no-op del propio upgrade).
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = vU and k.tipo like 'contrato_%';
  if v_a is distinct from vX then raise exception 'SINTETICA: U no atribuye a X (%)', v_a; end if;
  -- b) R (pierna contrato) ADOPTA a X, no a Z.
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = vR and k.tipo like 'contrato_%';
  if v_a is distinct from vX then raise exception 'SINTETICA: R no adopta a X (%)', v_a; end if;
  -- c) R2 multi-salto tambien.
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = vR2 and k.tipo like 'contrato_%';
  if v_a is distinct from vX then raise exception 'SINTETICA: R2 no adopta a X (%)', v_a; end if;
  -- d) El DESGLOSE de R (renovado 800 + adicional 200) adopta a X.
  select count(*) into v_n from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = vR and k.tipo like 'desglose_%' and k.analista_id = vX;
  if v_n <> 2 then raise exception 'SINTETICA: desglose de R no adopta (% de 2)', v_n; end if;
  -- e) R3 (cadena rota) NO adopta: regla vieja = su propio analista W.
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = vR3 and k.tipo like 'contrato_%';
  if v_a is distinct from vW then raise exception 'SINTETICA: R3 rota no cae a regla vieja (%)', v_a; end if;
  -- f) Reasignar la CABEZA (valvula F3.4) mueve la cadena ENTERA.
  perform set_config('crm.reasignando_analista', 'on', true);
  update public.contratos set analista_cierre_id = vZ where id = vU;
  perform set_config('crm.reasignando_analista', 'off', true);
  if private.analista_atribuido_cadena(vR2) is distinct from vZ then
    raise exception 'SINTETICA: reasignar la cabeza no movio la cadena';
  end if;
  -- g) Reasignar un ESLABON no mueve nada.
  perform set_config('crm.reasignando_analista', 'on', true);
  update public.contratos set analista_cierre_id = vY where id = vR;
  perform set_config('crm.reasignando_analista', 'off', true);
  if private.analista_atribuido_cadena(vR2) is distinct from vZ then
    raise exception 'SINTETICA: reasignar un eslabon movio la cadena';
  end if;
end $sint$;

-- MUTANTE A: el resolutor devuelve NULL siempre — la sintetica DEBE detectarlo.
CREATE OR REPLACE FUNCTION private.analista_atribuido_cadena(p_contrato_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select null::uuid
$function$;
do $mutA$
declare v_a uuid;
begin
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = (select id from public.contratos where numero_contrato = 'ATR2-ENSAYO-R')
     and k.tipo like 'contrato_%';
  -- Con el mutante, R cae a la regla vieja (su analista propio, hoy vY tras g).
  if v_a is distinct from (select analista_cierre_id from public.contratos where numero_contrato = 'ATR2-ENSAYO-R') then
    raise exception 'MUTANTE A SOBREVIVIO: la adopcion siguio viva con el resolutor anulado';
  end if;
end $mutA$;
CREATE OR REPLACE FUNCTION private.analista_atribuido_cadena(p_contrato_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;

-- MUTANTE B: la recursion cortada — el multi-salto DEBE degradarse y detectarse.
CREATE OR REPLACE FUNCTION private.analista_atribuido_cadena(p_contrato_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
       and c.nivel < 0
  )
  select con.analista_cierre_id
    from cadena cd
    join public.contratos con on con.id = cd.contrato_id
   where con.categoria = 'upgrade'
   order by cd.nivel asc
   limit 1
$function$;
do $mutB$
declare v_a uuid;
begin
  select k.analista_id into strict v_a from private.capital_episodios('-infinity','infinity',true,'{}'::uuid[]) k
   where k.contrato_id = (select id from public.contratos where numero_contrato = 'ATR2-ENSAYO-R2')
     and k.tipo like 'contrato_%';
  if v_a is distinct from (select analista_cierre_id from public.contratos where numero_contrato = 'ATR2-ENSAYO-R2') then
    raise exception 'MUTANTE B SOBREVIVIO: el multi-salto siguio adoptando con la recursion cortada';
  end if;
end $mutB$;
CREATE OR REPLACE FUNCTION private.analista_atribuido_cadena(p_contrato_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
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
$function$;

-- Y tras restaurar, la cadena vuelve a funcionar (sanidad final):
do $fin$
begin
  if private.analista_atribuido_cadena(
       (select id from public.contratos where numero_contrato = 'ATR2-ENSAYO-R2'))
     is distinct from (select analista_cierre_id from public.contratos where numero_contrato = 'ATR2-ENSAYO-U') then
    raise exception 'SINTETICA: el resolutor restaurado no resuelve';
  end if;
end $fin$;


-- ============================================================
-- SEGUNDO PASE DEL ORACULO (auditor RLS, P1-1): con el mundo sintetico
-- presente el delta NO es vacio — se repone el nucleo VIEJO, se fotografia,
-- se re-aplica ATR-2 y el MISMO oraculo (temporales _atr2b_) debe emparejar
-- las filas movidas de la cadena fabricada, sin un solo abort espurio.
-- ============================================================
CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    c.analista_cierre_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = c.analista_cierre_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    o.vendedor_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = o.vendedor_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or o.vendedor_id = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$function$;

do $$
begin
  create temp table _atr2b_delta_c on commit drop as
    select c.id as contrato_id,
           c.analista_cierre_id as viejo_id,
           private.analista_atribuido_cadena(c.id) as nuevo_id
      from public.contratos c
     where not c.es_demo
       and private.analista_atribuido_cadena(c.id) is distinct from c.analista_cierre_id
       and private.analista_atribuido_cadena(c.id) is not null;
  create temp table _atr2b_delta_d on commit drop as
    select o.contrato_nuevo_id as contrato_id,
           o.vendedor_id as viejo_id,
           private.analista_atribuido_cadena(o.contrato_nuevo_id) as nuevo_id
      from crm.operaciones_cartera o
     where (o.capital_renovado is not null or o.capital_adicional is not null)
       and private.analista_atribuido_cadena(o.contrato_nuevo_id) is distinct from o.vendedor_id
       and private.analista_atribuido_cadena(o.contrato_nuevo_id) is not null;
  if (select count(*) from _atr2b_delta_c) < 2 then
    raise exception 'SEGUNDO PASE: se esperaban >=2 filas de delta contrato (R y R2 sinteticas)';
  end if;
  create temp table _atr2b_cap_antes on commit drop as
    select * from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]);
  create temp table _atr2b_prod_antes on commit drop as
    select mp.periodo as _mes, r.*
      from (select distinct mp0.periodo, mp0.id,
                   row_number() over (partition by mp0.periodo order by mp0.revision desc) as rn
              from crm.meta_periodos mp0) mp
      cross join lateral private.produccion_mes_por_vendedor(
        (mp.periodo::timestamp at time zone 'America/Lima'),
        ((mp.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        mp.id) r
     where mp.rn = 1
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo);
end $$;

CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    -- ATR-2: la cadena de upgrade adopta tambien el CAPITAL (contrato 2026-08-30).
    coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id),
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id)
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id)
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id) = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$function$;

do $$
declare v_n integer; v_m integer;
begin
  create temp table _atr2b_cap_despues on commit drop as
    select * from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]);

  select count(*) into v_n from _atr2b_cap_antes;
  select count(*) into v_m from _atr2b_cap_despues;
  if v_n <> v_m then
    raise exception 'ATR-2 oraculo: el numero de episodios cambio (% -> %)', v_n, v_m;
  end if;

  create temp table _atr2b_perdidas on commit drop as
    select * from _atr2b_cap_antes except select * from _atr2b_cap_despues;
  create temp table _atr2b_ganadas on commit drop as
    select * from _atr2b_cap_despues except select * from _atr2b_cap_antes;

  -- Toda fila movida pertenece a un contrato del delta (de cualquiera de las
  -- dos listas) y es de las piernas contrato/desglose (cooperativa JAMAS).
  select count(*) into v_n from _atr2b_perdidas p
   where p.tipo not like 'contrato_%' and p.tipo not like 'desglose_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas FUERA de las piernas contrato/desglose', v_n;
  end if;
  select count(*) into v_n from _atr2b_perdidas p
   where p.contrato_id not in (select contrato_id from _atr2b_delta_c
                               union select contrato_id from _atr2b_delta_d);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas fuera del delta (perdidas)', v_n;
  end if;
  select count(*) into v_n from _atr2b_ganadas g
   where g.contrato_id not in (select contrato_id from _atr2b_delta_c
                               union select contrato_id from _atr2b_delta_d);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas movidas fuera del delta (ganadas)', v_n;
  end if;

  -- Emparejamiento viejo->nuevo al byte en TODO salvo analista y en_roster
  -- (en_roster es DERIVADO del analista: cambia con el, y su verdad la
  -- re-verifica 2c contra el cuadro de metas).
  select count(*) into v_n from _atr2b_perdidas p
   where not exists (
     select 1 from _atr2b_ganadas g
     join _atr2b_delta_c dc on dc.contrato_id = p.contrato_id
     where g.contrato_id = p.contrato_id and g.tipo = p.tipo and g.medida = p.medida
       and p.analista_id is not distinct from dc.viejo_id
       and g.analista_id = dc.nuevo_id
       and g.moneda is not distinct from p.moneda
       and g.monto is not distinct from p.monto
       and g.categoria is not distinct from p.categoria
       and g.mes_comercial is not distinct from p.mes_comercial
       and g.fecha is not distinct from p.fecha
       and g.fecha_vencimiento is not distinct from p.fecha_vencimiento
       and g.estado is not distinct from p.estado
       and g.anulado = p.anulado
       and g.cliente_id is not distinct from p.cliente_id
       and g.registrado_por is not distinct from p.registrado_por
       and g.cierre_externo_id is not distinct from p.cierre_externo_id
       and g.lead_id is not distinct from p.lead_id)
     and p.tipo like 'contrato_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas contrato no emparejan viejo->nuevo', v_n;
  end if;
  select count(*) into v_n from _atr2b_perdidas p
   where not exists (
     select 1 from _atr2b_ganadas g
     join _atr2b_delta_d dd on dd.contrato_id = p.contrato_id
     where g.contrato_id = p.contrato_id and g.tipo = p.tipo and g.medida = p.medida
       and p.analista_id is not distinct from dd.viejo_id
       and g.analista_id = dd.nuevo_id
       and g.moneda is not distinct from p.moneda
       and g.monto is not distinct from p.monto
       and g.categoria is not distinct from p.categoria
       and g.mes_comercial is not distinct from p.mes_comercial
       and g.fecha is not distinct from p.fecha
       and g.fecha_vencimiento is not distinct from p.fecha_vencimiento
       and g.estado is not distinct from p.estado
       and g.anulado = p.anulado
       and g.cliente_id is not distinct from p.cliente_id
       and g.registrado_por is not distinct from p.registrado_por
       and g.cierre_externo_id is not distinct from p.cierre_externo_id
       and g.lead_id is not distinct from p.lead_id)
     and p.tipo like 'desglose_%';
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: % filas desglose no emparejan viejo->nuevo', v_n;
  end if;

  -- 2b) El DINERO de la empresa, por tipo/medida/moneda, al centimo.
  select count(*) into v_n from (
    select tipo, medida, moneda, sum(monto) s from _atr2b_cap_antes group by 1,2,3
    except
    select tipo, medida, moneda, sum(monto) from _atr2b_cap_despues group by 1,2,3
  ) x;
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: los TOTALES de capital por tipo/medida/moneda cambiaron';
  end if;

  -- 2c) en_roster de las ganadas = la verdad del cuadro de metas del NUEVO analista.
  select count(*) into v_n from _atr2b_ganadas g
   where g.tipo like 'contrato_%' or g.tipo like 'desglose_%';
  select count(*) into v_m from _atr2b_ganadas g
   where (g.tipo like 'contrato_%' or g.tipo like 'desglose_%')
     and g.en_roster = exists (
       select 1 from crm.metas_vendedor mv
       where mv.meta_periodo_id = (select mp.id from crm.meta_periodos mp
                                   where mp.periodo = g.mes_comercial
                                   order by mp.revision desc limit 1)
         and mv.vendedor_id = g.analista_id);
  if v_n <> v_m then
    raise exception 'ATR-2 oraculo: en_roster de % filas ganadas no dice la verdad del cuadro', v_n - v_m;
  end if;

  -- 2d) Con deltas VACIOS (lo esperado hoy): PARIDAD EXACTA del nucleo entero.
  if (select count(*) from _atr2b_delta_c) = 0 and (select count(*) from _atr2b_delta_d) = 0 then
    if (select count(*) from _atr2b_perdidas) + (select count(*) from _atr2b_ganadas) <> 0 then
      raise exception 'ATR-2 oraculo: deltas vacios pero el nucleo difiere';
    end if;
  end if;

  -- 2e) PRODUCCION de los meses abiertos: identica salvo personas del delta.
  create temp table _atr2b_prod_despues on commit drop as
    select mp.periodo as _mes, r.*
      from (select distinct mp0.periodo, mp0.id,
                   row_number() over (partition by mp0.periodo order by mp0.revision desc) as rn
              from crm.meta_periodos mp0) mp
      cross join lateral private.produccion_mes_por_vendedor(
        (mp.periodo::timestamp at time zone 'America/Lima'),
        ((mp.periodo + interval '1 month')::timestamp at time zone 'America/Lima'),
        mp.id) r
     where mp.rn = 1
       and not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = mp.periodo);

  select count(*) into v_n from (
    (select * from _atr2b_prod_antes except select * from _atr2b_prod_despues)
    union all
    (select * from _atr2b_prod_despues except select * from _atr2b_prod_antes)
  ) x
  where x.vendedor_id is null
     or x.vendedor_id not in (select viejo_id from _atr2b_delta_c where viejo_id is not null
                              union select nuevo_id from _atr2b_delta_c);
  if v_n <> 0 then
    raise exception 'ATR-2 oraculo: produccion del mes abierto se movio fuera del delta (% filas)', v_n;
  end if;
end $$;;

-- ===== MARCHA ATRAS EN LA MISMA TX =====
-- MARCHA ATRAS de P-055 ATR-2 (capital por cadena de upgrade).
-- Repone el cuerpo ORIGINAL del nucleo de capital (literal de maquina del
-- prosrc vivo del 30/08). El resolutor NO se toca: es de ATR-1.


set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- 0) PREFLIGHT: solo se pisa el estado ATR-2. Si un hotfix posterior movio el
--    nucleo, esto ABORTA — regenerar el rollback, jamas pisar a ciegas.
do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from '90f1d8c2342becb94cc3d3e023227078' then
    raise exception 'rollback ATR-2: capital_episodios NO esta en el estado ATR-2 (huella %) — regenerar el rollback', v_h;
  end if;
  -- P1-4 de Codex: un ALTER FUNCTION (security/volatility/search_path) conserva
  -- prosrc — los atributos tambien se pinnean antes de pisar.
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig::text = '{"search_path=\"\""}') then
    raise exception 'rollback ATR-2: los ATRIBUTOS del nucleo no son los del estado ATR-2 — regenerar el rollback';
  end if;
end $$;

CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CONTRATO TEMPORAL (P0-4 de Codex, escrito): contratos y desgloses parten
  -- por FECHA LOCAL de Lima — el dia comercial entra COMPLETO o no entra;
  -- cooperativas parten por INSTANTE. Llamar con medianoches locales (o con
  -- ±infinity para "sin limite"); cualquier otra hora parte distinto.
  select
    'contrato_' || coalesce(c.categoria, 'nuevo'),
    'stock',
    c.id, null::uuid, null::uuid,
    c.cliente_id,
    c.analista_cierre_id,
    c.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', c.fecha_cierre_comercial)::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = c.analista_cierre_id
    ),
    c.moneda,
    c.capital,
    c.categoria,
    date_trunc('month', c.fecha_cierre_comercial)::date,
    (c.fecha_cierre_comercial::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from public.contratos c
  where not c.es_demo
    and c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
    and c.fecha_cierre_comercial <  (p_fin at time zone 'America/Lima')::date
    and (p_global or c.analista_cierre_id = any(p_visibles))

  union all

  select
    'desglose_' || parte.tipo,
    'desglose',
    o.contrato_nuevo_id, null::uuid, null::uuid,
    o.cliente_id,
    o.vendedor_id,
    o.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = o.periodo
        order by mp.revision desc limit 1)
        and mv.vendedor_id = o.vendedor_id
    ),
    o.moneda,
    parte.monto,
    o.tipo,
    o.periodo,
    (o.fecha_operacion::timestamp at time zone 'America/Lima'),
    c.fecha_vencimiento,
    c.estado,
    false
  from crm.operaciones_cartera o
  join public.contratos c on c.id = o.contrato_nuevo_id and not c.es_demo
  cross join lateral (values
    ('renovado',  o.capital_renovado),
    ('adicional', o.capital_adicional)
  ) as parte(tipo, monto)
  where parte.monto is not null
    and o.fecha_operacion >= (p_ini at time zone 'America/Lima')::date
    and o.fecha_operacion <  (p_fin at time zone 'America/Lima')::date
    and (p_global or o.vendedor_id = any(p_visibles))

  union all

  select
    'cooperativa',
    case when ce.anulado_en is null then 'stock' else 'nula' end,
    null::uuid, ce.id, ce.lead_id,
    l.perfil_id,
    ce.vendedor_id,
    ce.creado_por,
    exists (
      select 1 from crm.metas_vendedor mv
      where mv.meta_periodo_id = (
        select mp.id from crm.meta_periodos mp
        where mp.periodo = date_trunc('month', ce.creado_en at time zone 'America/Lima')::date
        order by mp.revision desc limit 1)
        and mv.vendedor_id = ce.vendedor_id
    ),
    ce.moneda,
    case when ce.anulado_en is null then ce.monto else 0::numeric end,
    'nuevo',
    date_trunc('month', ce.creado_en at time zone 'America/Lima')::date,
    ce.creado_en,
    ce.vence_en,
    case when ce.anulado_en is null then 'vigente' else 'anulado' end,
    ce.anulado_en is not null
  from crm.cierres_externos ce
  left join crm.leads l on l.id = ce.lead_id
  where ce.creado_en >= p_ini and ce.creado_en < p_fin
    and (p_global or ce.vendedor_id = any(p_visibles));
$function$
;

do $$
declare v_h text;
begin
  select md5(p.prosrc) into v_h from pg_proc p
   where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if v_h is distinct from '872f5ad4362f66a18f4a3806453f78a0' then
    raise exception 'rollback ATR-2: el nucleo no volvio al byte (huella %)', v_h;
  end if;
  if (select p.proacl::text from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'rollback ATR-2: proacl del nucleo no es el original';
  end if;
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig::text = '{"search_path=\"\""}') then
    raise exception 'rollback ATR-2: los ATRIBUTOS del nucleo no volvieron (definer/stable/search_path vacio)';
  end if;
  perform private.assert_analitica_leads_citas();
  perform private.assert_analista_vigencia();
end $$;


select 'ATR2-CICLO-VERDE-v2' as resultado;
rollback;
