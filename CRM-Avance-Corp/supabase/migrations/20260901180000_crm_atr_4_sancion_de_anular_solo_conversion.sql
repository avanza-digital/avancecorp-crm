-- P-055 ATR-4 — LA SANCION DE ANULAR ES SOLO DE CONVERSION, SIEMPRE.
--
-- Regla firmada por Miguel el 2026-08-31 (contrato tecnico en el vault:
-- «Contrato de la sancion de anulacion (ATR-4, 2026-08-31)»): una anulacion
-- baja la CONVERSION del analista — por igual con mes abierto o sellado — y
-- el CAPITAL no se toca jamas: ni la produccion del analista ni el AUM de la
-- empresa. Anular es una sancion al vendedor, no un agujero en el dinero.
--
-- CUATRO BISTURIS, todo en la LECTURA (ningun trigger, ninguna tabla nueva):
--   1. private.produccion_mes_por_vendedor — deja de neutralizar el capital
--      de anulados (fuera las CTE `anulados`/`neutralizados`; las coops se
--      filtran por MEDIDA del nucleo, no por el flag).
--   2. private.registrar_ajuste_si_mes_cerrado — la deuda de mes sellado ya
--      no carga capital: solo el numerador de conversion.
--   3. private.capital_episodios — la coop anulada REAL vuelve a
--      medida='stock' con su monto (el capital existe); conserva
--      estado='anulado' y el flag. UNICA excepcion DECLARADA: la fila demo
--      qorilazo (id sellado en el cuerpo) jamas es dinero.
--   4. private.contratos_afectados_por_anulacion — queda SOLO informativa y
--      compara por la ATRIBUCION EFECTIVA de la cadena, no por creado_por.
--   5. LAS LENTES DEL DINERO (refutacion 01/09: el contrato del vault decia
--      «sin tocar lentes» y era FALSO): metricas_vencimientos_fn,
--      directorio_ranking_analistas y metricas_directorio filtraban la pierna
--      coop por estado='vigente' — borraban a la anulada aunque el nucleo la
--      conservara —, y cierres_externos_fn llevaba contabilidad paralela con
--      «anulado_en is null». Las cuatro pasan a la MEDIDA del nucleo (o a la
--      exclusion declarada de la demo, en la paralela).
--
-- EFECTO EN NUMEROS DE HOY: CERO — el preflight lo exige como candado del
-- mundo (0 anulaciones de Avance, 0 deudas, la unica coop anulada es la demo)
-- y el postflight lo demuestra con TRES paridades al byte: capital global,
-- conversion global y produccion de agosto, ANTES = DESPUES.
--
-- Publicacion (Miguel, con `!`): esta migracion → registrar-atr4-version.sql
-- → gates → advisors. Sera el registro 193. Si se revierte:
-- scripts/rollback-atr4-p055.sql y retirar A MANO la fila 20260901180000.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT: pines, el candado del mundo y las fotos de ANTES.
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    array['private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])', '90f1d8c2342becb94cc3d3e023227078'],
    array['private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)', 'af6794c36951ad53dcb413db90c26070'],
    array['private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)',           'aae02eba8b8c6fa666b0a9b212e3c5a0'],
    array['private.contratos_afectados_por_anulacion(uuid)',                   '2df41b523f953048184070d66d37cda4'],
    array['private.analista_atribuido_cadena(uuid)',                           'e39016e2913cce47faabee29c2c38fe2'],
    array['private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)', '71213ac03eb32e333723399538d35d83'],
    array['crm.cerrar_periodo(date)',                                          'cefe29a119f40efe257f851a6ae2a162'],
    array['crm.cumplimiento_metas_sin_cartera_fn(date)',                       '5c12bcdfa74becd5294cb6071ee34a6d'],
    -- las 4 lentes del bisturi 5 (cuerpo viejo exacto):
    array['crm.metricas_vencimientos_fn(integer)',                             '54a9bf11bb4e0bbf0fc4d7c12bed7fcb'],
    array['public.directorio_ranking_analistas()',                             '0ba94108dc8612a42535ab89c14d1728'],
    array['public.metricas_directorio()',                                      '1802e44a4f8b304df19b1e15cd3934a6'],
    array['crm.cierres_externos_fn(date)',                                     '31af3945063d671e3d181332df60750b']
  ];
  v_fila text[]; v_h text; v_n int; v_motivo text; v_id uuid;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'ATR-4 preflight: % cambio desde la medicion (huella %)', v_fila[1], v_h;
    end if;
  end loop;

  -- EL CANDADO DEL MUNDO: esta migracion se escribio con EXACTAMENTE este
  -- estado. Si al publicar hay una anulacion REAL nueva, se ABORTA y se
  -- decide con Miguel (seria la primera aplicacion de la regla y merece
  -- mirarse con nombre y apellido).
  select count(*) into v_n from crm.cierres_avance_anulados;
  if v_n <> 0 then
    raise exception 'ATR-4 preflight: hay % anulaciones de Avance (se escribio con 0) — decidir con Miguel', v_n;
  end if;
  select count(*) into v_n from crm.ajustes_mes_cerrado;
  if v_n <> 0 then
    raise exception 'ATR-4 preflight: hay % deudas en ajustes_mes_cerrado (se escribio con 0) — decidir con Miguel', v_n;
  end if;
  select count(*) into v_n from crm.cierres_externos where anulado_en is not null;
  if v_n <> 1 then
    raise exception 'ATR-4 preflight: hay % coops anuladas (se escribio con 1: la demo) — decidir con Miguel', v_n;
  end if;
  select ce.id, ce.motivo_anulacion into v_id, v_motivo
  from crm.cierres_externos ce where ce.anulado_en is not null;
  if v_id is distinct from 'a112aead-184a-4979-9041-943978fadae4'::uuid or v_motivo is distinct from 'DEMO' then
    raise exception 'ATR-4 preflight: la coop anulada NO es la demo declarada (id %, motivo %)', v_id, v_motivo;
  end if;

  -- FOTOS DE ANTES (rango total, global): el postflight exige identidad al byte.
  create temp table _atr4_cap_antes on commit drop as
    select * from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]);
  create temp table _atr4_conv_antes on commit drop as
    select * from private.conversion_episodios('1900-01-01'::timestamptz, '2100-01-01'::timestamptz, null::date, true, '{}'::uuid[], 1);
  create temp table _atr4_prod_antes on commit drop as
    select r.* from private.produccion_mes_por_vendedor(
      date '2026-08-01'::timestamp at time zone 'America/Lima',
      date '2026-09-01'::timestamp at time zone 'America/Lima',
      (select mp.id from crm.meta_periodos mp where mp.periodo = date '2026-08-01' order by mp.revision desc limit 1)) r;
end $$;

-- =====================================================================
-- 1) BISTURI 3 primero — el nucleo; los demas beben de el.
--    (cabecera VERBATIM de pg_get_functiondef: nada cambia salvo el cuerpo)
-- =====================================================================
CREATE OR REPLACE FUNCTION private.capital_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_global boolean, p_visibles uuid[])
 RETURNS TABLE(tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid, cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean, moneda text, monto numeric, categoria text, mes_comercial date, fecha timestamp with time zone, fecha_vencimiento date, estado text, anulado boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $atr4_capital$

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
    -- ATR-4 (Miguel 31/08): la sancion de anular es SOLO de conversion. El
    -- capital de una coop anulada EXISTE y se queda: vuelve a 'stock'. UNICA
    -- excepcion DECLARADA: la fila DEMO de Miguel (qorilazo S/100.000, creada
    -- 19/08 y anulada 20/08 con motivo 'DEMO'; vault «Cierre Qorilazo S 100000
    -- es dato demo») — su lead es REAL y el filtro de demos no la caza, asi
    -- que se excluye por id, sellado por la huella de este cuerpo.
    case when ce.anulado_en is null then 'stock'
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 'nula'
         else 'stock' end,
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
    case when ce.anulado_en is null then ce.monto
         when ce.id = 'a112aead-184a-4979-9041-943978fadae4'::uuid then 0::numeric
         else ce.monto end,
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

$atr4_capital$;

-- =====================================================================
-- 2) BISTURI 1: produccion sin neutralizacion.
-- =====================================================================
CREATE OR REPLACE FUNCTION private.produccion_mes_por_vendedor(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo_id uuid)
 RETURNS TABLE(vendedor_id uuid, categoria text, moneda text, contratos_real integer, capital_real numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $atr4_produccion$

  with contratos_base as materialized (
    -- public.contratos es la confirmación canónica. El lateral resume todos los
    -- enlaces explícitos sin duplicar el contrato y detecta los legacy ambiguos
    -- que apuntan a vendedores distintos: esos quedan sin atribuir.
    select
      c.id,
      c.categoria,
      c.moneda,
      c.capital,
      c.creado_por,
      c.analista_cierre_id,
      coalesce(enlaces.tiene_vendedor_explicito,false)
        as tiene_vendedor_explicito,
      coalesce(enlaces.vendedores_distintos,0) as vendedores_distintos,
      enlaces.vendedor_unico
    from (select k.contrato_id as id, k.categoria, k.moneda,
                 k.monto as capital, k.registrado_por as creado_por,
                 k.analista_id as analista_cierre_id,
                 (k.fecha at time zone 'America/Lima')::date as fecha_cierre_comercial
          from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
          where k.tipo like 'contrato_%' and k.medida = 'stock') c
    left join lateral (
      select
        count(*) filter(where lead.vendedor_id is not null)>0
          as tiene_vendedor_explicito,
        count(distinct lead.vendedor_id)
          filter(where lead.vendedor_id is not null)::integer
          as vendedores_distintos,
        case
          when count(distinct lead.vendedor_id)
            filter(where lead.vendedor_id is not null)=1
          then min(lead.vendedor_id::text)
            filter(where lead.vendedor_id is not null)::uuid
        end as vendedor_unico
      from crm.leads lead
      where lead.contrato_id=c.id
    ) enlaces on true
    where c.fecha_cierre_comercial >= (p_ini at time zone 'America/Lima')::date
      and c.fecha_cierre_comercial < (p_fin at time zone 'America/Lima')::date
      and c.categoria in ('nuevo','renovacion','upgrade')
      and c.moneda in ('PEN','USD')
  ), atribuidos as materialized (
    -- La atribución explícita es autoritativa: si existe pero no pertenece al
    -- snapshot del mes, no cae silenciosamente al autor. El autor inmutable se
    -- usa solo cuando el contrato no tiene vendedor explícito. metas_vendedor
    -- impide que supervisores u otros actores se apropien de la producción.
    select
      base.id,
      case
        -- P-055 F3.5b: si la venta tiene analista, es SUYA — validada contra el
        -- cuadro de metas del mes, igual que todo lo demas. Fuera del cuadro,
        -- sin atribucion: NUNCA cae a otro actor.
        when base.analista_cierre_id is not null then meta_analista.vendedor_id
        when base.vendedores_distintos>1 then null
        when base.tiene_vendedor_explicito then meta_lead.vendedor_id
        else meta_autor.vendedor_id
      end as vendedor_id,
      base.categoria,
      base.moneda,
      base.capital
    from contratos_base base
    left join crm.metas_vendedor meta_lead
      on meta_lead.meta_periodo_id=p_periodo_id
     and meta_lead.vendedor_id=base.vendedor_unico
    left join crm.metas_vendedor meta_autor
      on meta_autor.meta_periodo_id=p_periodo_id
     and meta_autor.vendedor_id=base.creado_por
    left join crm.metas_vendedor meta_analista
      on meta_analista.meta_periodo_id=p_periodo_id
     and meta_analista.vendedor_id=base.analista_cierre_id
  ), contratos_confirmados as materialized (
    -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La anulacion ya NO
    -- neutraliza el capital del analista: su produccion queda como este. La
    -- sancion vive integra en la CONVERSION (conversion_episodios ya la
    -- aplica). La leccion del 2026-08-13 («solo se le puede quitar el merito
    -- a quien lo tiene») sigue viva donde corresponde: en la conversion.
    select a.id, a.vendedor_id, a.categoria, a.moneda, a.capital
    from atribuidos a
  ), externos_confirmados as materialized (
    -- Cierres en cooperativas (Qorilazo/Prodelco): suman a la cuota del mes
    -- como categoría 'nuevo', en SU moneda (PEN/USD jamás se suman), atribuidos
    -- al vendedor_id FOTO del cierre y validados contra el snapshot de metas
    -- del mes — el MISMO contrato que un contrato Avance: fuera del snapshot ⇒
    -- sin atribución, nunca cae a otro actor (el JOIN hace ambas cosas).
    -- Ventana por creado_en: la fecha del cierre es automática y no se
    -- retro-data, así que el mes del cierre es el mes real.
    select
      mv.vendedor_id,
      'nuevo'::text as categoria,
      ce.moneda,
      ce.monto as capital
    from (select k.cierre_externo_id as id, k.analista_id as vendedor_id,
                 k.moneda, k.monto, k.anulado, k.medida,
                 k.fecha as creado_en
          from private.capital_episodios(p_ini, p_fin, true, '{}'::uuid[]) k
          where k.tipo = 'cooperativa') ce
    join crm.metas_vendedor mv
      on mv.meta_periodo_id=p_periodo_id
     and mv.vendedor_id=ce.vendedor_id
    where ce.creado_en>=p_ini and ce.creado_en<p_fin
      -- ATR-4: la coop anulada REAL conserva su capital — el nucleo la emite
      -- con medida='stock' y aqui se filtra por MEDIDA (la verdad vive UNA
      -- vez, en el nucleo). La demo declarada sigue 'nula' alli y sigue fuera.
      -- La sancion vive en la conversion (conversion_mensual_por_vendedor).
      and ce.medida = 'stock'
  )
  select confirmados.vendedor_id, confirmados.categoria, confirmados.moneda,
    count(*)::integer as contratos_real,
    coalesce(sum(confirmados.capital),0) as capital_real
  from (
    select cc.vendedor_id, cc.categoria, cc.moneda, cc.capital
    from contratos_confirmados cc
    where cc.vendedor_id is not null
    union all
    select ec.vendedor_id, ec.categoria, ec.moneda, ec.capital
    from externos_confirmados ec
  ) confirmados
  group by confirmados.vendedor_id, confirmados.categoria, confirmados.moneda

$atr4_produccion$;

-- =====================================================================
-- 3) BISTURI 2: la deuda de mes sellado, solo conversion.
-- =====================================================================
CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $atr4_registrar$

declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_pen         numeric := 0;
  v_usd         numeric := 0;
  v_detalle     jsonb := '[]'::jsonb;
  v_id          uuid;
begin
  select * into v_lead from crm.leads where id = p_lead_id;
  if not found or v_lead.convertido_en is null then
    return null;
  end if;

  v_periodo := date_trunc('month', v_lead.convertido_en at time zone 'America/Lima')::date;

  -- ⚠️ EL CERROJO, antes de mirar si el mes esta cerrado. Sin el, una anulacion
  -- concurrente con el sellado de ESE mes lee «abierto» —porque el sello aun no
  -- ha commiteado—, devuelve NULL, y el cierre anulado se queda pagado para
  -- siempre. Misma clave que en `crm.cerrar_periodo`.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('crm.periodos_cerrados'),
    (v_periodo - date '2000-01-01')::integer
  );

  -- Mes ABIERTO: no hay deuda que registrar. El mes se recalcula y el cierre
  -- desaparece de el, que es el comportamiento de siempre.
  if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
    return null;
  end if;

  -- A quien se le descuenta: el mismo acreditado que usa la cuota.
  v_acreditado := coalesce(
    (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = p_lead_id),
    private.vendedor_acreditado_del_cierre(p_lead_id));
  if v_acreditado is null then
    -- Sin acreditado no hay a quien descontarle. No se inventa un deudor.
    return null;
  end if;

  -- Lo que valia el cierre en la conversion. El origen sale del LEDGER (la foto
  -- del episodio), no de `crm.leads.origen`, que es una columna viva.
  -- F6.c (v2, tras el P1 de Codex): EL EPISODIO MANDA. El cierre puede caer a
  -- caballo del mes (convertido_en usa now() de transaccion y el ledger
  -- statement_timestamp(), caso documentado): se localiza el episodio canonico
  -- del lead SIN depender del mes de leads.convertido_en, y de el salen el
  -- PERIODO real, el referido y el peso. Cero episodios => la sancion de
  -- conversion vale CERO (nunca 1 en silencio) y queda alerta; mas de uno =>
  -- excepcion de integridad (el ledger solo permite una conversion por lead).
  select count(*),
         coalesce(bool_or(e.fue_referido), false),
         min(date_trunc('month', (e.fecha_numerador at time zone 'America/Lima'))::date)
    into v_n_episodios, v_referido, v_periodo_episodio
  from private.conversion_episodios(
         '1900-01-01'::timestamptz, '2100-01-01'::timestamptz,
         null::date, true, '{}'::uuid[], 1) e
  where e.lead_id = p_lead_id and e.tipo = 'cierre';

  if v_n_episodios > 1 then
    raise exception 'Integridad: el lead % tiene % episodios de cierre en el ledger', p_lead_id, v_n_episodios;
  end if;
  if v_n_episodios = 1 and v_periodo_episodio is distinct from v_periodo then
    -- El mes REAL del cierre es el del episodio: el cerrojo y la foto del mes
    -- sellado se toman sobre ese periodo (se re-toma el candado por si acaso).
    v_periodo := v_periodo_episodio;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo - date '2000-01-01')::integer);
    if not exists (select 1 from crm.periodos_cerrados pc where pc.periodo = v_periodo) then
      return null;
    end if;
  end if;
  if v_n_episodios = 0 then
    insert into private.vigia_alertas (fase, motivo)
    values ('f6c_ajuste_sin_episodio',
            format('lead %s: sin episodio de cierre en el ledger; la sancion de conversion vale 0', p_lead_id));
  end if;

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_n_episodios = 0 then 0
                       when v_referido then v_peso else 1 end;

  -- ATR-4 (Miguel 31/08): «solo la conversion, siempre». La deuda de un mes
  -- sellado ya NO carga capital: el capital del analista se queda en su
  -- produccion y el de la empresa en el AUM. Solo se descuenta la conversion.
  v_pen := 0; v_usd := 0; v_detalle := '[]'::jsonb;

  -- Con capital siempre 0, la deuda existe SOLO si la conversion valia algo.
  -- numerador 0 (cierre sin episodio) => NULL POR DISENO declarado: el rastro
  -- queda en la alerta del vigia (f6c_ajuste_sin_episodio) y en la anulacion
  -- misma; no se fabrica una deuda vacia.
  if v_numerador <= 0 and v_pen = 0 and v_usd = 0 then
    return null;
  end if;

  insert into crm.ajustes_mes_cerrado (
    vendedor_id, periodo_origen, lead_id, motivo, creado_por,
    numerador, capital_pen, capital_usd, detalle,
    pendiente_numerador, pendiente_pen, pendiente_usd, pendiente_detalle
  ) values (
    v_acreditado, v_periodo, p_lead_id, p_motivo, p_por,
    v_numerador, v_pen, v_usd, v_detalle,
    v_numerador, v_pen, v_usd, v_detalle
  )
  on conflict (lead_id) do nothing
  returning id into v_id;

  return v_id;
end;

$atr4_registrar$;

-- =====================================================================
-- 4) BISTURI 4: el aviso, solo informativo y con la atribucion efectiva.
-- =====================================================================
CREATE OR REPLACE FUNCTION private.contratos_afectados_por_anulacion(p_lead_id uuid)
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $atr4_afectados$

  select c.id
  from crm.leads l
  cross join lateral (
    -- La FOTO manda. El calculo vivo solo sirve de respaldo: para cierres en
    -- cooperativa (que no pasan por esta tabla) y para responder ANTES de anular.
    select coalesce(
      (select ca.acreditado_a from crm.cierres_avance_anulados ca where ca.lead_id = l.id),
      private.vendedor_acreditado_del_cierre(l.id)
    ) as acreditado_a
  ) q
  join public.contratos c
    on (
      -- (a) enlace directo, cuando alguien lo rellena (legado o manual)
      c.id = l.contrato_id
      -- (b) el enlace del flujo REAL: el lead apunta al CLIENTE.
      or (l.perfil_id is not null
          and l.perfil_id = c.cliente_id
          and l.convertido_en is not null
          -- SUELO: un contrato ANTERIOR a la conversion no lo produjo este
          -- cierre. `crm.convertir_lead` admite un cliente que YA existia, asi
          -- que su cartera previa es de otra historia comercial y no se toca.
          and c.creado_en >= l.convertido_en
          -- TECHO: y deja de reclamar en cuanto ese mismo cliente vuelve a
          -- cerrarse. Sin esto un cierre anulado se quedaba con TODO el futuro
          -- del cliente para siempre — incluida la venta legitima que ese mismo
          -- vendedor le hiciera un ano despues.
          and not exists (
            select 1
            from crm.leads l_post
            where l_post.perfil_id = l.perfil_id
              and l_post.id <> l.id
              and l_post.convertido_en is not null
              -- Orden TOTAL, no parcial: `now()` es constante dentro de una
              -- transaccion, asi que dos conversiones del mismo cliente pueden
              -- empatar al microsegundo. Con `>` a secas ninguna cerraria el
              -- techo de la otra y AMBAS reclamarian los mismos contratos.
              and (l_post.convertido_en, l_post.id) > (l.convertido_en, l.id)
              and l_post.convertido_en <= c.creado_en
          ))
    )
   -- Y solo afecta a quien lo tiene. ATR-4: la verdad de la atribucion es la
   -- CADENA (ATR-1/2) con su caida a analista_cierre_id — `creado_por` era el
   -- REGISTRADOR, no el dueño del merito (leccion del 28/08). Esta funcion es
   -- SOLO INFORMATIVA desde ATR-4 (payload/afecta_cuota — que ahora significa
   -- «afecta la CONVERSION» — y retroceso de etapa): produccion y la deuda de
   -- mes sellado ya no le preguntan.
   and coalesce(private.analista_atribuido_cadena(c.id), c.analista_cierre_id) = q.acreditado_a
   -- Lo que la cuota NO mira, esto tampoco puede prometerlo: sin estos dos
   -- filtros, un contrato en otra moneda o de categoria no contable entraba en
   -- `contratos_afectados` y ponia `afecta_cuota` en true sin que bajara un sol.
   and c.categoria in ('nuevo','renovacion','upgrade')
   and c.moneda in ('PEN','USD')
   -- Y la MISMA regla de ambiguedad que aplica la cuota: un contrato enlazado a
   -- leads de vendedores DISTINTOS ya queda sin atribuir alli, asi que anular no
   -- movera un sol. Sin esto, `afecta_cuota` decia true y no bajaba nada.
   and not exists (
     select 1
     from crm.leads le
     where le.contrato_id = c.id
       and le.vendedor_id is not null
     having count(distinct le.vendedor_id) > 1
   )
  where l.id = p_lead_id

$atr4_afectados$;

-- =====================================================================
-- 5) BISTURI 5: las lentes del dinero — la MEDIDA del nucleo es la autoridad.
-- =====================================================================
CREATE OR REPLACE FUNCTION crm.metricas_vencimientos_fn(p_dias integer DEFAULT 90)
 RETURNS TABLE(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $atr4_venc$
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
         ((current_date + 1)::timestamp at time zone 'America/Lima'),
         true, '{}'::uuid[]) e
  cross join ambito a
  where e.medida = 'stock'
    and ((e.tipo like 'contrato_%' and e.estado = 'activo')
         -- ATR-4: la coop anulada REAL sigue siendo dinero y sigue venciendo
         -- (la MEDIDA del nucleo manda; la demo es 'nula' y queda fuera sola).
         or e.tipo = 'cooperativa')
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
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
$atr4_venc$;

CREATE OR REPLACE FUNCTION public.directorio_ranking_analistas()
 RETURNS TABLE(analista_id uuid, nombre text, capital_pen numeric, capital_usd numeric, n_clientes bigint, n_contratos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $atr4_rank$
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
  -- DECISION A (30/08): los contratos acreditan al asesor del cliente (como
  -- siempre en esta pantalla); las cooperativas acreditan a SU analista.
  SELECT a.id, a.nombre_completo,
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0),
         COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='USD'),0),
         COUNT(DISTINCT e.cliente_id) FILTER (WHERE e.cliente_id IS NOT NULL),
         COUNT(e.contrato_id)
  FROM private.capital_episodios(
         '-infinity'::timestamptz, 'infinity'::timestamptz,
         true, '{}'::uuid[]) e
  LEFT JOIN perfiles cli ON cli.id = e.cliente_id
  JOIN perfiles a ON a.rol = 'analista'
    AND a.id = CASE WHEN e.tipo = 'cooperativa' THEN e.analista_id
                    ELSE cli.asesor_perfil_id END
  WHERE e.medida = 'stock'
    AND ((e.tipo LIKE 'contrato_%' AND e.estado='activo')
         -- ATR-4: la coop anulada REAL sigue siendo dinero (la MEDIDA manda).
         OR e.tipo = 'cooperativa')
  GROUP BY a.id, a.nombre_completo
  ORDER BY COALESCE(SUM(e.monto) FILTER (WHERE e.moneda='PEN'),0) DESC;
END;
$atr4_rank$;

CREATE OR REPLACE FUNCTION public.metricas_directorio()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $atr4_mdir$
DECLARE
  v jsonb;
  hoy date := (now() AT TIME ZONE 'America/Lima')::date;
  inicio_mes date := date_trunc('month', (now() AT TIME ZONE 'America/Lima'))::date;
BEGIN
  IF NOT (es_directorio() OR es_admin()) THEN
    RAISE EXCEPTION 'No autorizado' USING ERRCODE = '42501';
  END IF;

  WITH episodios AS (
    -- DECISION A (30/08): el Directorio ve el negocio COMPLETO — contratos
    -- Avance y cierres en cooperativas vigentes, de una sola calculadora.
    SELECT * FROM private.capital_episodios(
      '-infinity'::timestamptz, 'infinity'::timestamptz,
      true, '{}'::uuid[])
    WHERE medida = 'stock'
      AND (tipo LIKE 'contrato_%' OR tipo = 'cooperativa')
  ),
  activos AS (
    SELECT contrato_id AS id, cliente_id, moneda, monto AS capital,
           (fecha AT TIME ZONE 'America/Lima')::date AS fecha_cierre_comercial
    FROM episodios
    -- ATR-4: para contratos manda su estado; para coops manda la MEDIDA del
    -- nucleo (la anulada REAL conserva su capital; la demo es 'nula' y no llega).
    WHERE (tipo LIKE 'contrato_%' AND estado = 'activo')
       OR tipo = 'cooperativa'
  ),
  aum AS (
    SELECT moneda,
           COALESCE(SUM(capital),0) AS total,
           COALESCE(SUM(capital) FILTER (WHERE fecha_cierre_comercial >= inicio_mes),0) AS captado_mes
    FROM activos GROUP BY moneda
  ),
  cuotas AS (
    SELECT cp.*, c.moneda
    FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id = cp.contrato_id
    WHERE c.estado IN ('activo','vencido')
      AND cp.estado <> 'trasladado'
  ),
  vencidas AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado' AND fecha_programada < hoy
  ),
  pendientes AS (
    SELECT * FROM cuotas WHERE estado <> 'pagado'
  )
  SELECT jsonb_build_object(
    'generado_en', now(),
    'aum', (
      SELECT COALESCE(jsonb_object_agg(moneda, jsonb_build_object(
        'total', total,
        'captado_mes', captado_mes,
        'var_pct', CASE WHEN (total - captado_mes) > 0
                        THEN round((captado_mes / (total - captado_mes) * 100)::numeric, 1)
                        ELSE 0 END
      )), '{}'::jsonb) FROM aum
    ),
    'clientes', jsonb_build_object(
      'activos', (SELECT COUNT(DISTINCT cliente_id) FROM activos WHERE cliente_id IS NOT NULL),
      'nuevos_mes', (SELECT COUNT(*) FROM perfiles WHERE rol='cliente' AND creado_en >= inicio_mes)
    ),
    'contratos', jsonb_build_object(
      'activos', (SELECT COUNT(*) FROM activos),
      'ticket_promedio', (
        SELECT COALESCE(jsonb_object_agg(moneda, prom),'{}'::jsonb) FROM (
          SELECT moneda, round(AVG(capital)::numeric,2) AS prom FROM activos GROUP BY moneda
        ) t
      )
    ),
    'cobranza', jsonb_build_object(
      'pct_al_dia', (
        SELECT CASE WHEN COUNT(*)=0 THEN 100
               ELSE round((COUNT(*) FILTER (WHERE estado='pagado' OR fecha_programada >= hoy)::numeric
                           / COUNT(*) * 100), 1) END
        FROM cuotas WHERE fecha_programada <= hoy
      ),
      'cuotas_vencidas', (SELECT COUNT(*) FROM vencidas),
      'monto_vencido', (
        SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
          SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto FROM vencidas GROUP BY moneda
        ) t
      )
    ),
    'intereses_pagados', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT c.moneda, COALESCE(SUM(cp.monto_pagado),0) AS monto
        FROM cronograma_pagos cp JOIN (SELECT * FROM contratos WHERE NOT es_demo) c ON c.id=cp.contrato_id
        WHERE cp.tipo IN ('retorno','devolucion') AND cp.estado='pagado'
        GROUP BY c.moneda
      ) t
    ),
    'caja_90d', (
      SELECT COALESCE(jsonb_object_agg(moneda, monto),'{}'::jsonb) FROM (
        SELECT moneda, COALESCE(SUM(monto_programado),0) AS monto
        FROM pendientes WHERE fecha_programada BETWEEN hoy AND (hoy + 90)
        GROUP BY moneda
      ) t
    ),
    'crecimiento', (
      SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) FROM (
        SELECT jsonb_build_object(
          'mes', to_char(m, 'YYYY-MM'),
          'PEN', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='PEN' AND e.mes_comercial = m::date),0),
          'USD', COALESCE((SELECT SUM(e.monto) FROM episodios e
                           WHERE e.moneda='USD' AND e.mes_comercial = m::date),0)
        ) AS row
        FROM generate_series(date_trunc('month', hoy) - interval '11 months',
                             date_trunc('month', hoy), interval '1 month') m
      ) s
    )
  ) INTO v;

  RETURN v;
END;
$atr4_mdir$;

CREATE OR REPLACE FUNCTION crm.cierres_externos_fn(p_periodo date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $atr4_cef$
declare
  v_uid        uuid := (select auth.uid());
  v_rol        text;
  v_lector     boolean;
  v_global     boolean;
  v_filas      boolean;
  v_alcance    text;
  v_visibles   uuid[];
  v_mes_actual date := date_trunc('month', now() at time zone 'America/Lima')::date;
  v_ini        timestamptz;
  v_fin        timestamptz;
  v_payload    jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null
     or not coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia') or v_lector, false) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  if p_periodo is null or p_periodo <> date_trunc('month', p_periodo)::date then
    raise exception 'Periodo invalido: debe ser el primer dia del mes'
      using errcode = '22023';
  end if;
  if p_periodo > v_mes_actual then
    raise exception 'Periodo invalido: el mes no puede ser futuro'
      using errcode = '22023';
  end if;

  v_global := coalesce(v_rol = 'gerencia', false) or v_lector;
  v_filas := coalesce(v_rol in ('vendedor', 'supervisor', 'gerencia'), false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;
  v_visibles := case when v_global then '{}'::uuid[]
                     else array(select private.vendedor_ids_visibles(v_uid)) end;

  v_ini := p_periodo::timestamp at time zone 'America/Lima';
  v_fin := (p_periodo + interval '1 month')::timestamp at time zone 'America/Lima';

  select jsonb_build_object(
    'version', 1,
    'periodo', p_periodo,
    'alcance', v_alcance,
    -- Filas para la sección «En cooperativas» de Mi cartera (todo el
    -- histórico del ámbito, más reciente primero). Tope de 200 con total al
    -- lado: sin tope sería la lista sin fin que F2 vino a matar; con tope
    -- mudo, el front sumaría filas truncadas y mentiría en los totales — por
    -- eso los mini-totales NO salen de las filas sino de `totales`.
    'cierres', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        -- Los anulados SÍ viajan en las filas (y NO en los totales): el asesor
        -- tiene que poder entender por qué le bajó el total, no encontrarse un
        -- hueco donde antes había un cierre.
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where v_global or ce0.vendedor_id = any(v_visibles)
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where v_global or ce.vendedor_id = any(v_visibles)
    ),
    -- Las filas DEL MES pedido: es la vista de revisión de supervisor y gerencia
    -- («Ver cierres del mes»), donde el número de operación se contrasta. NO se
    -- filtra en el cliente sobre `cierres`, que viene tope 200 por antigüedad y
    -- podría no alcanzar el mes entero.
    'cierres_mes', case when not v_filas then '[]'::jsonb else coalesce((
      select jsonb_agg(jsonb_build_object(
        'cierre_id', ce.id,
        'lead_id', ce.lead_id,
        'cooperativa', ce.cooperativa,
        'monto', ce.monto,
        'moneda', ce.moneda,
        'nombre_completo', ce.nombre_completo,
        'documento_tipo', ce.documento_tipo,
        'documento', ce.documento,
        -- El teléfono se lee VIVO del lead, pero el ámbito de esta fila lo pone
        -- `ce.vendedor_id`, que es una FOTO. Un lead convertido SÍ se puede
        -- reasignar (el guard de tenencia solo veta cambios de etapa), así que
        -- sin este recorte el vendedor original seguiría leyendo para siempre el
        -- teléfono ACTUAL de un lead que ya no es suyo. La foto del cierre es
        -- suya; los datos vivos del lead, no.
        'telefono', case when v_global or l.vendedor_id = any(v_visibles)
                         then l.telefono end,
        'numero_transaccion', ce.numero_transaccion,
        'referencia_externa', ce.referencia_externa,
        'vence_en', ce.vence_en,
        'nota', ce.nota,
        'vendedor_id', ce.vendedor_id,
        'vendedor_nombre', p.nombre_completo,
        'creado_en', ce.creado_en,
        'anulado_en', ce.anulado_en,
        'motivo_anulacion', ce.motivo_anulacion
      ) order by ce.creado_en desc)
      from (
        select *
        from crm.cierres_externos ce0
        where ce0.creado_en >= v_ini and ce0.creado_en < v_fin
          and (v_global or ce0.vendedor_id = any(v_visibles))
        order by ce0.creado_en desc
        limit 200
      ) ce
      join crm.leads l on l.id = ce.lead_id
      left join public.perfiles p on p.id = ce.vendedor_id
    ), '[]'::jsonb) end,
    'cierres_mes_total', (
      select count(*)::integer
      from crm.cierres_externos ce
      where ce.creado_en >= v_ini and ce.creado_en < v_fin
        and (v_global or ce.vendedor_id = any(v_visibles))
    ),
    -- Mini-totales de Mi cartera: TODO el histórico del ámbito, por
    -- cooperativa y moneda (PEN/USD jamás sumados). Servidos aquí para que el
    -- front no haga aritmética sobre una lista que puede venir truncada.
    'totales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'cooperativa', t.cooperativa,
        'moneda', t.moneda,
        'capital', t.capital,
        'cierres', t.cierres
      ) order by t.cooperativa, t.moneda)
      from (
        select ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        where (v_global or ce.vendedor_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.cooperativa, ce.moneda
      ) t
    ), '[]'::jsonb),
    -- Desglose por empresa del MES pedido, por vendedor × cooperativa ×
    -- moneda, para supervisor y gerencia. La parte «Avance» del desglose la
    -- pone cumplimiento_metas_fn (capital_real ya INCLUYE los externos tras
    -- esta migración): Avance = capital_real − estos agregados, resta de dos
    -- números servidos — no una división en cliente.
    'por_empresa', coalesce((
      select jsonb_agg(jsonb_build_object(
        'vendedor_id', x.vendedor_id,
        'vendedor_nombre', x.nombre,
        'cooperativa', x.cooperativa,
        'moneda', x.moneda,
        'capital', x.capital,
        'cierres', x.cierres
      ) order by x.nombre, x.cooperativa, x.moneda)
      from (
        select ce.vendedor_id, p.nombre_completo as nombre,
               ce.cooperativa, ce.moneda,
               sum(ce.monto) as capital,
               count(*)::integer as cierres
        from crm.cierres_externos ce
        left join public.perfiles p on p.id = ce.vendedor_id
        where ce.creado_en >= v_ini and ce.creado_en < v_fin
          and (v_global or ce.vendedor_id = any(v_visibles))
          -- ATR-4 (regla 31/08): los anulados REALES SIGUEN siendo dinero.
          -- Fuera SOLO la demo declarada (la misma exclusion por id que el
          -- nucleo; si algun dia nace otra demo, se tocan los dos JUNTOS).
          and ce.id <> 'a112aead-184a-4979-9041-943978fadae4'::uuid
        group by ce.vendedor_id, p.nombre_completo, ce.cooperativa, ce.moneda
      ) x
    ), '[]'::jsonb)
  ) into v_payload;

  return v_payload;
end;
$atr4_cef$;

-- =====================================================================
-- 6) RE-SELLOS del censo F6.a (las 3 exenciones cambiaron de cuerpo).
--    Si algun UPDATE no casara su fila, el assert del postflight caza la
--    huella vieja contra el cuerpo nuevo y la migracion entera aborta.
-- =====================================================================
update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure),
       razon = 'Cuenta contratos y capital por casilla (count/sum legitimos de produccion). Tras ATR-4 ya no neutraliza anulados: la sancion de anular vive SOLO en la conversion (regla de Miguel 31/08).'
 where objeto = 'private.produccion_mes_por_vendedor(timestamp with time zone,timestamp with time zone,uuid)';

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure),
       razon = 'El numerador del ajuste sale del EPISODIO del nucleo (F6.c). Tras ATR-4 la deuda de mes sellado es SOLO de conversion: capital_pen/usd/detalle van a cero por la regla firmada el 31/08 («solo la conversion, siempre»).'
 where objeto = 'private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)';

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'private.contratos_afectados_por_anulacion(uuid)'::regprocedure),
       razon = 'SOLO informativa tras ATR-4 (payload/afecta_cuota — que significa «afecta la conversion» — y retroceso de etapa); compara por la atribucion efectiva de la cadena. Produccion y la deuda de mes sellado ya no le preguntan.'
 where objeto = 'private.contratos_afectados_por_anulacion(uuid)';

update private.analitica_leads_citas_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(
                   lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'crm.cierres_externos_fn(date)'::regprocedure),
       razon = 'Lista las cooperativas del mes para gerencia: listado operativo con su conteo de apoyo, no una calculadora comercial. Tras ATR-4 sus totales excluyen SOLO la demo declarada (misma exclusion por id que el nucleo): los anulados reales SIGUEN siendo dinero (regla 31/08).'
 where objeto = 'crm.cierres_externos_fn(date)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- Y el censo de VIGENCIA (F5.a): el ranking del Directorio es puerta exenta
-- alli, sellada por md5 CRUDO del cuerpo — su bisturi 5 la caduco.
update private.analista_vigencia_exenciones
   set huella = (select md5(regexp_replace(regexp_replace(p.prosrc,
                   '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
                 from pg_proc p
                 where p.oid = 'public.directorio_ranking_analistas()'::regprocedure),
       razon = $razon_v$No es una puerta de analista: usa rol = analista para SELECCIONAR a quien se rankea, y el acceso esta gateado por es_directorio() o es_admin(). Tras ATR-4 su pierna coop corta por la MEDIDA del nucleo (la anulada real sigue siendo dinero, regla 31/08).$razon_v$
 where objeto = 'public.directorio_ranking_analistas()';

-- =====================================================================
-- 7) POSTFLIGHT: paridad al byte con el mundo de hoy + trinquetes.
-- =====================================================================
do $$
declare v_a text; v_d text; v_n int; v_src text; v_verd text;
begin
  if (select md5(prosrc) from pg_proc where oid='private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
     = '90f1d8c2342becb94cc3d3e023227078' then
    raise exception 'ATR-4 postflight: el nucleo no cambio';
  end if;
  if (select md5(prosrc) from pg_proc where oid='private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
     = 'af6794c36951ad53dcb413db90c26070' then
    raise exception 'ATR-4 postflight: produccion no cambio';
  end if;
  if (select md5(prosrc) from pg_proc where oid='private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)'::regprocedure)
     = 'aae02eba8b8c6fa666b0a9b212e3c5a0' then
    raise exception 'ATR-4 postflight: registrar_ajuste no cambio';
  end if;
  if (select md5(prosrc) from pg_proc where oid='private.contratos_afectados_por_anulacion(uuid)'::regprocedure)
     = '2df41b523f953048184070d66d37cda4' then
    raise exception 'ATR-4 postflight: contratos_afectados no cambio';
  end if;

  select prosrc into v_src from pg_proc
   where oid='private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure;
  if strpos(lower(v_src), 'count(') > 0 or strpos(lower(v_src), 'sum(1') > 0 then
    raise exception 'ATR-4 postflight: el nucleo gano un conteo crudo';
  end if;

  if not exists (select 1 from pg_proc p
    where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure
      and p.prosecdef and p.provolatile = 's'
      and p.proconfig::text = '{"search_path=\"\""}') then
    raise exception 'ATR-4 postflight: los atributos del nucleo no sobrevivieron';
  end if;
  if (select p.proacl::text from pg_proc p
      where p.oid = 'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
     is distinct from '{postgres=X/postgres}' then
    raise exception 'ATR-4 postflight: el ACL del nucleo cambio';
  end if;

  -- PARIDAD 1: capital global IDENTICO (hoy no hay anuladas reales y la demo
  -- sigue nula: si algo se movio, un bisturi corto de mas).
  select md5(coalesce(string_agg(md5(t::text), '|' order by md5(t::text)), 'vacio')) into v_a from _atr4_cap_antes t;
  select md5(coalesce(string_agg(md5(k::text), '|' order by md5(k::text)), 'vacio')) into v_d
    from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]) k;
  if v_a is distinct from v_d then
    raise exception 'ATR-4 postflight: el CAPITAL global cambio con el mundo de hoy (antes %, despues %)', v_a, v_d;
  end if;

  -- PARIDAD 2: conversion global IDENTICA (ATR-4 no la toca).
  select md5(coalesce(string_agg(md5(t::text), '|' order by md5(t::text)), 'vacio')) into v_a from _atr4_conv_antes t;
  select md5(coalesce(string_agg(md5(e::text), '|' order by md5(e::text)), 'vacio')) into v_d
    from private.conversion_episodios('1900-01-01'::timestamptz, '2100-01-01'::timestamptz, null::date, true, '{}'::uuid[], 1) e;
  if v_a is distinct from v_d then
    raise exception 'ATR-4 postflight: la CONVERSION cambio y esta migracion no debia tocarla';
  end if;

  -- PARIDAD 3: produccion de agosto IDENTICA al byte.
  select md5(coalesce(string_agg(md5(t::text), '|' order by md5(t::text)), 'vacio')) into v_a from _atr4_prod_antes t;
  select md5(coalesce(string_agg(md5(r::text), '|' order by md5(r::text)), 'vacio')) into v_d
    from private.produccion_mes_por_vendedor(
      date '2026-08-01'::timestamp at time zone 'America/Lima',
      date '2026-09-01'::timestamp at time zone 'America/Lima',
      (select mp.id from crm.meta_periodos mp where mp.periodo = date '2026-08-01' order by mp.revision desc limit 1)) r;
  if v_a is distinct from v_d then
    raise exception 'ATR-4 postflight: la PRODUCCION de agosto cambio con el mundo de hoy';
  end if;

  -- Las 4 lentes cambiaron de verdad y su filtro nuevo esta presente.
  if (select md5(prosrc) from pg_proc where oid='crm.metricas_vencimientos_fn(integer)'::regprocedure) = '54a9bf11bb4e0bbf0fc4d7c12bed7fcb'
     or (select md5(prosrc) from pg_proc where oid='public.directorio_ranking_analistas()'::regprocedure) = '0ba94108dc8612a42535ab89c14d1728'
     or (select md5(prosrc) from pg_proc where oid='public.metricas_directorio()'::regprocedure) = '1802e44a4f8b304df19b1e15cd3934a6'
     or (select md5(prosrc) from pg_proc where oid='crm.cierres_externos_fn(date)'::regprocedure) = '31af3945063d671e3d181332df60750b' then
    raise exception 'ATR-4 postflight: alguna lente del bisturi 5 no cambio';
  end if;
  if exists (select 1 from pg_proc p
             where p.oid in ('crm.metricas_vencimientos_fn(integer)'::regprocedure,
                             'public.directorio_ranking_analistas()'::regprocedure)
               and strpos(lower(p.prosrc), 'cooperativa'' and e.estado') > 0) then
    raise exception 'ATR-4 postflight: una lente conserva el filtro de estado en la pierna coop';
  end if;
  if (select strpos(prosrc, 'anulado_en is null') from pg_proc
      where oid='crm.cierres_externos_fn(date)'::regprocedure) > 0 then
    raise exception 'ATR-4 postflight: cierres_externos_fn conserva el filtro monetario viejo';
  end if;

  -- La demo sigue fuera del dinero, con nombre y apellido.
  select count(*) into v_n
    from private.capital_episodios('-infinity'::timestamptz, 'infinity'::timestamptz, true, '{}'::uuid[]) k
   where k.cierre_externo_id = 'a112aead-184a-4979-9041-943978fadae4'::uuid and (k.medida <> 'nula' or k.monto <> 0);
  if v_n <> 0 then
    raise exception 'ATR-4 postflight: la demo qorilazo reaparecio como dinero';
  end if;

  -- Los guardianes, en la misma transaccion (cazan tambien un re-sello fallido).
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'ATR-4 postflight: analitica en rojo: %', v_verd;
  end if;
  select private.assert_analista_vigencia() into v_verd;
  if v_verd not like 'OK%' then
    raise exception 'ATR-4 postflight: vigencia en rojo: %', v_verd;
  end if;
end $$;

commit;
