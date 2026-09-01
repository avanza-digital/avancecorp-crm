begin;
-- =====================================================================
-- ENSAYO COMBINADO: EL 10/09 Y EL 11/09 EN LA MISMA TRANSACCION
-- =====================================================================
-- Responde la pregunta que el calendario no responde: ¿ATR-2 se aplica
-- limpiamente SOBRE agosto ya sellado, y el sello no se mueve?
--
-- ACTO 1: sellar agosto por el camino REAL (el ciclo del cron, con la ventana
--         de ajuste neutralizada) — igual que el ensayo de la F2.
-- ACTO 2: aplicar ATR-2 ENTERA con su preflight, sus oraculos y su postflight,
--         ahora con agosto SELLADO (la condicion que pide su calendario).
-- ACTO 3: comprobar que la FOTO SELLADA no se movio ni un byte.
-- Todo termina en ROLLBACK: no se escribe nada.
--
-- ⚠️ Retiene el candado global de cierre mientras corre: no publicar metas ni
-- anular contratos en ese minuto.
-- =====================================================================
set local lock_timeout = '5s';
set local statement_timeout = '600s';

-- ---------- ACTO 1: sellar agosto (camino del cron) ----------
do $sellar$
declare
  v_src text; v_cfg text[]; v_secdef boolean; v_nuevo text;
  v_src_c text; v_nuevo_c text;
  v_res jsonb; v_filas int;
  k_vent  constant text := 'if now() < v_ventana then';
  k_cvent constant text := 'exit when now() < private.cierre_mes_ventana_desde(v_periodo);';
  k_cllam constant text := 'crm.cerrar_periodo(v_periodo)';
begin
  if (select auth.uid()) is not null then
    raise exception 'ENSAYO ABORTADO: la sesion trae claims';
  end if;
  if exists (select 1 from crm.periodos_cerrados) then
    raise exception 'ENSAYO ABORTADO: ya hay un mes sellado';
  end if;

  select p.prosrc, p.proconfig, p.prosecdef into v_src, v_cfg, v_secdef
  from pg_proc p where p.oid = 'crm.cerrar_periodo(date)'::regprocedure;
  if v_cfg is distinct from array['search_path=""'] or not v_secdef then
    raise exception 'ENSAYO ABORTADO: cerrar_periodo cambio de forma';
  end if;
  if (length(v_src) - length(replace(v_src, k_vent, ''))) / length(k_vent) <> 1 then
    raise exception 'ENSAYO ABORTADO: el candado de ventana no aparece exactamente 1 vez';
  end if;
  v_nuevo := replace(v_src, k_vent, 'if false then /* ensayo */');

  select p.prosrc into v_src_c from pg_proc p where p.oid = 'crm.ciclo_cierre_mes()'::regprocedure;
  if (length(v_src_c) - length(replace(v_src_c, k_cvent, ''))) / length(k_cvent) <> 1
     or (length(v_src_c) - length(replace(v_src_c, k_cllam, ''))) / length(k_cllam) <> 1 then
    raise exception 'ENSAYO ABORTADO: el ciclo cambio de forma';
  end if;
  v_nuevo_c := replace(v_src_c, k_cvent, '-- ensayo');
  v_nuevo_c := replace(v_nuevo_c, k_cllam, 'crm.ensayo_c_cerrar(v_periodo)');

  execute format('create function crm.ensayo_c_cerrar(p_periodo date) returns jsonb language plpgsql security definer set search_path to %L as %s', '', quote_literal(v_nuevo));
  execute 'revoke execute on function crm.ensayo_c_cerrar(date) from public';
  execute format('create function crm.ensayo_c_ciclo() returns jsonb language plpgsql security definer set search_path to %L as %s', '', quote_literal(v_nuevo_c));
  execute 'revoke execute on function crm.ensayo_c_ciclo() from public';

  v_res := crm.ensayo_c_ciclo();
  select count(*) into v_filas from crm.cierre_mes_vendedor where periodo = date '2026-08-01';

  if not coalesce((v_res->>'ok')::boolean,false)
     or coalesce((v_res->>'cerrados')::int,0) <> 1 or v_filas = 0 then
    raise exception 'ENSAYO ABORTADO: el ciclo no sello agosto: %', v_res;
  end if;

  -- Los clones se retiran YA: si sobrevivieran, el postflight de ATR-2 podria
  -- verlos y no tienen nada que ver con la migracion que se esta probando.
  execute 'drop function crm.ensayo_c_ciclo()';
  execute 'drop function crm.ensayo_c_cerrar(date)';

  -- La foto sellada, congelada para el ACTO 3.
  create temp table _sello_antes on commit drop as
    select * from crm.cierre_mes_vendedor where periodo = date '2026-08-01';
  create temp table _sello_cab_antes on commit drop as
    select * from crm.periodos_cerrados where periodo = date '2026-08-01';

  raise notice 'ACTO 1 OK: agosto sellado, % personas', v_filas;
end $sellar$;

-- ---------- ACTO 2: ATR-2 entera, con agosto YA SELLADO ----------
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
-- [ensayo] begin propio retirado
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
-- [ensayo] commit propio retirado
-- ---------- ACTO 3: el sello NO se movio ----------
do $verificar$
declare
  v_a text; v_d text; v_ca text; v_cd text; v_n int;
begin
  select count(*), md5(coalesce(string_agg(md5(t::text), '|' order by t.vendedor_id), 'vacio'))
    into v_n, v_a from _sello_antes t;
  select md5(coalesce(string_agg(md5(f::text), '|' order by f.vendedor_id), 'vacio'))
    into v_d from crm.cierre_mes_vendedor f where f.periodo = date '2026-08-01';
  select md5(coalesce(string_agg(md5(t::text), '|' order by t.periodo), 'vacio'))
    into v_ca from _sello_cab_antes t;
  select md5(coalesce(string_agg(md5(pc::text), '|' order by pc.periodo), 'vacio'))
    into v_cd from crm.periodos_cerrados pc where pc.periodo = date '2026-08-01';

  if v_a is distinct from v_d then
    raise exception 'ROJO: la FOTO SELLADA de agosto cambio al aplicar ATR-2 (antes % / despues %)', v_a, v_d;
  end if;
  if v_ca is distinct from v_cd then
    raise exception 'ROJO: la cabecera del sello de agosto cambio al aplicar ATR-2';
  end if;
  raise notice 'ACTO 3 OK: sello intacto (% personas, huella %)', v_n, v_a;
end $verificar$;

select 'ENSAYO-COMBINADO-SELLO+ATR2-VERDE' as resultado,
       (select count(*) from crm.periodos_cerrados where periodo = date '2026-08-01') as agosto_sellado,
       (select count(*) from crm.cierre_mes_vendedor where periodo = date '2026-08-01') as personas_en_la_foto;
rollback;
