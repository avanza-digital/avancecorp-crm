-- Reversa de 20261012220959. Solo antes de sellar octubre o meses posteriores.
-- Restauración de los tres cuerpos productivos capturados antes del cambio.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
set local search_path='';
select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
lock table crm.conversion_pesos in access exclusive mode;
lock table crm.periodos_cerrados in share row exclusive mode;
lock table crm.conversion_acreditaciones in access exclusive mode;
do $guardas$
declare r record; v_nota text := '
Miguel 2026-10-12: sustituye la base anterior del tope. El límite exacto es el 15 % del total de cierres referidos válidos del analista/mes; sin redondear hacia arriba. Se admite por el orden vigente, con último aporte parcial. Anular un referido sellado descuenta la reducción marginal del límite (0,15), sin depender de la posición. Renovaciones 0, divisor y meses históricos intactos.';
begin
  if exists(select 1 from crm.periodos_cerrados where periodo>=date '2026-10-01')
    or exists(select 1 from crm.conversion_acreditaciones where ajuste_anulacion_en_sello is not null)
    or (select count(*) from crm.conversion_pesos)<>2
    or not exists(select 1 from crm.conversion_pesos where vigente_desde='2026-10-01'
      and peso_referido=1 and peso_renovacion=0 and tope_referidos_pct=15
      and right(nota,length(v_nota))=v_nota) then
    raise exception 'REVERSA REFERIDOS: hay aportes sellados o cambió configuración' using errcode='P0409';
  end if;
  for r in select * from (values ('private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric)','ed15fbd034c636e4897c7600002ee8cf'),('private.conversion_fijar_sello_trg()','f682c7a79ec49c35d30da890ac476944'),('private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid)','6635dd1b4776fb10dab9d202805e92e9')) v(firma,huella) loop
    if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(r.firma)
      and md5(p.prosrc)=r.huella and p.prosecdef and p.proowner='postgres'::regrole
      and p.proacl::text='{postgres=X/postgres}') then
      raise exception 'REVERSA REFERIDOS: cambió %',r.firma using errcode='P0409';
    end if;
  end loop;
  update crm.conversion_pesos set nota=left(nota,length(nota)-length(v_nota))
  where vigente_desde='2026-10-01';
end;
$guardas$;
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  -- Los meses COMPLETOS que toca la ventana: el tope de referidos es por analista y por mes de cierre, y su base son
  -- todos los cierres de leads asignados de ESE analista en ese mes, no solo los de un rango parcial. Como cada analista
  -- tiene su propia base, el ámbito (p_global/p_visibles) se aplica antes de calcular el tope sin cambiar su resultado.
  v_ini_mes timestamptz := date_trunc('month', p_ini at time zone 'America/Lima') at time zone 'America/Lima';
  v_mes_ult date := date_trunc('month', (p_fin - interval '1 microsecond') at time zone 'America/Lima')::date;
  v_fin_mes timestamptz := (v_mes_ult::timestamp + interval '1 month') at time zone 'America/Lima';
begin
return query
with marcados as (
  -- El índice único del ledger garantiza un cierre por lead. El cierre queda
  -- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
  -- siguen disponibles para consumidores operativos/capital, con aporte CERO.
  select c.*,
    -- El mes de CIERRE: el de la fecha comercial del cierre del lead.
    date_trunc('month', c.fecha_numerador at time zone 'America/Lima')::date as mes_cierre,
    -- Un cierre cuenta para la base del tope solo si NO está anulado y es el cierre de un lead que el sistema asigna
    -- (private.conversion_origen_base_tope: landing y formulario) y que no es un registro manual (alta_manual: regla
    -- cerrada, el registro manual queda fuera de la base, como queda fuera del divisor). Los referidos y la base cargada
    -- no entran en la base. Solo la BASE excluye el alta manual: su aporte al numerador sigue entero.
    (not c.anulado and private.conversion_origen_base_tope(c.origen) and not coalesce(lm.alta_manual, false)) as en_base,
    (c.fue_referido and not c.anulado) as es_referido,
    -- Desempate de dos cierres de la MISMA fecha comercial (es un día, sin hora): el que se acreditó antes cuenta antes.
    (select ca.acreditado_en from crm.conversion_acreditaciones ca where ca.lead_id = c.lead_id) as registrado_en
  from private.conversion_cierres(
    v_ini_mes, v_fin_mes, p_periodo, p_global, p_visibles, p_factor, null::uuid[]) c
  left join crm.leads lm on lm.id = c.lead_id
), con_tope as (
  select m.*,
    -- Un cierre sin analista (analista_id NULL) comparte UNA sola partición con los demás sin analista: un solo tope para todos.
    count(*) filter (where m.en_base) over (partition by m.analista_id, m.mes_cierre) as base_cierres,
    -- Los referidos de cada analista y mes, del más antiguo al más reciente: cuentan los primeros.
    row_number() over (partition by m.analista_id, m.mes_cierre, m.es_referido
                       order by m.fecha_numerador, m.registrado_en, m.lead_id) as orden_referido,
    private.tope_referidos_conversion(m.mes_cierre) as tope_pct
  from marcados m
)
-- Una llegada por id, por su alta ORIGINAL en Lima. No depende del estado
-- actual ni de cuántas veces se asigne, descarte, rescate o cambie de dueño.
-- La primera asignación se busca en toda la historia ANTES de aplicar ámbito.
-- Sin asignación aún: cuenta en empresa, nunca se inventa un responsable.
select 'recibido'::text, primera.analista_id, l.id, null::uuid,
  l.origen = 'referido', coalesce(primera.aproximado, false),
  'llegada'::text, false, l.origen, null::text,
  date_trunc('month', l.creado_en at time zone 'America/Lima')::date,
  null::numeric, null::text, l.creado_en, null::timestamptz,
  case when l.origen in ('landing', 'formulario') and not l.alta_manual
    then 1 else 0 end, 0::numeric
from crm.leads l
left join lateral (
  select la.analista_id, la.aproximado
  from crm.lead_asignaciones la
  where la.lead_id = l.id
  order by la.asignado_en, la.ciclo_n, la.episodio_n, la.id
  limit 1
) primera on true
where l.creado_en >= p_ini and l.creado_en < p_fin
  and l.origen in ('landing', 'formulario', 'referido')
  and (p_global or primera.analista_id = any(p_visibles))

union all

-- TOPE DE REFERIDOS (Miguel, 07/10/2026, desde octubre): por analista y mes de cierre, los referidos cuentan hasta el
-- tope % de sus cierres de leads asignados por el sistema (en_base; sin referidos, base cargada, registros manuales ni
-- operaciones; redondeado hacia arriba); los más recientes pasan a valer 0. Sin cierres asignados la base es 0 y todos sus referidos valen 0.
-- Sin tope vigente para el mes (agosto, septiembre) el aporte queda como siempre.
select t.tipo, t.analista_id, t.lead_id, t.operacion_id, t.fue_referido, t.aproximado, t.motivo, t.anulado, t.origen,
  t.categoria, t.mes_origen, t.monto, t.moneda, t.fecha_divisor, t.fecha_numerador, t.aporte_divisor,
  case when t.es_referido and t.tope_pct is not null
         and t.orden_referido > ceil(t.base_cierres * t.tope_pct / 100.0)
       then 0::numeric else t.aporte_numerador end
from con_tope t
where t.fecha_numerador >= p_ini and t.fecha_numerador < p_fin
  and (p_global or t.analista_id = any(p_visibles))

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa su propio peso; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
-- Las operaciones no entran en la base del tope: salen como siempre.
select 'operacion'::text,
  private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    case when p_periodo is not null then private.peso_renovacion_conversion(p_periodo)
      else private.peso_renovacion_conversion(o.periodo) end
    when o.tipo = 'upgrade' then 1 else 0 end
from (
  select o0.*, row_number() over (
    partition by o0.cliente_id, o0.periodo
    order by o0.fecha_operacion, o0.creado_en, o0.id
  ) as orden_conversion
  from crm.operaciones_cartera o0
  where o0.elegible_conversion
    and o0.periodo >= date_trunc('month', p_ini at time zone 'America/Lima')::date
    and o0.periodo <= date_trunc('month', p_fin at time zone 'America/Lima')::date
) o
where o.orden_conversion = 1
  and o.fecha_operacion::timestamp at time zone 'America/Lima' >= p_ini
  and o.fecha_operacion::timestamp at time zone 'America/Lima' < p_fin
  and (p_global or private.analista_efectivo_contrato(o.contrato_nuevo_id, o.vendedor_id) = any(p_visibles));
end;
$function$;

CREATE OR REPLACE FUNCTION private.conversion_fijar_sello_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cuentan uuid[];
begin
  if new.periodo>=date '2026-09-01' and exists(
    select 1 from crm.conversion_politica where activada_en is not null) then
    perform pg_advisory_xact_lock(hashtext('crm.periodos_cerrados'),
      (new.periodo-date '2000-01-01')::integer);
    -- Tope de referidos (07/10/2026): un referido que pasó del tope no se pagó, así que no queda «incluido en el sello» y
    -- anularlo no genera deuda. Los que sí cuentan salen del mismo núcleo que acaba de calcular el mes.
    if new.tope_referidos_pct is not null then
      select coalesce(array_agg(e.lead_id), '{}'::uuid[]) into v_cuentan
        from private.conversion_episodios(
               new.periodo::timestamp at time zone 'America/Lima',
               (new.periodo + interval '1 month')::timestamp at time zone 'America/Lima',
               new.periodo, true, '{}'::uuid[], new.ponderacion_referido) e
       where e.tipo = 'cierre' and e.fue_referido and e.aporte_numerador > 0;
    end if;
    update crm.conversion_acreditaciones ca set sellado_en=new.cerrado_en,
      incluida_en_sello=(ca.estado='acreditada'
        and not private.cierre_externo_anulado(ca.lead_id)
        and private.conversion_exclusion_fuente(ca.fuente_tipo,ca.fuente_id)='elegible'
        and (new.tope_referidos_pct is null or ca.origen is distinct from 'referido' or ca.lead_id = any(v_cuentan))),
      actualizado_en=private.conversion_instante_servidor()
    where ca.periodo_comercial=new.periodo and ca.sellado_en is null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.registrar_ajuste_si_mes_cerrado(p_lead_id uuid, p_motivo text, p_por uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$

declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
  v_n_episodios integer;
  v_periodo_episodio date;
  v_acreditacion crm.conversion_acreditaciones%rowtype;
  v_acreditacion_actual crm.conversion_acreditaciones%rowtype;
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

  -- Desde septiembre, el reloj de crédito y la prueba de que SE ABONÓ salen
  -- del hecho de acreditación, no del mes de leads.convertido_en.
  if exists(select 1 from crm.conversion_politica where activada_en is not null)
    and exists(select 1 from crm.lead_asignaciones la where la.lead_id=p_lead_id
    and la.resultado='convertido' and coalesce(la.resultado_en,la.finalizado_en)
      >= '2026-09-01 00:00 America/Lima'::timestamptz) then
    select * into v_acreditacion
    from crm.conversion_acreditaciones ca where ca.lead_id=p_lead_id
      and ca.estado='acreditada' and ca.periodo_comercial>=date '2026-09-01';
    if not found then return null; end if;
    v_periodo:=v_acreditacion.periodo_comercial;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
      (v_periodo-date '2000-01-01')::integer);
    select * into v_acreditacion_actual from crm.conversion_acreditaciones where lead_id=p_lead_id;
    if v_acreditacion_actual is distinct from v_acreditacion then
      raise exception 'La acreditacion cambio durante la anulacion; vuelve a intentar' using errcode='PT409';
    end if;
    if not exists(select 1 from crm.periodos_cerrados pc where pc.periodo=v_periodo) then
      return null;
    end if;
    if v_acreditacion.incluida_en_sello is distinct from true then return null; end if;
    v_acreditado:=v_acreditacion.analista_id;
    v_numerador:=case when v_acreditacion.origen='referido' then
      private.peso_referido_conversion(v_periodo)
      when private.conversion_origen_con_cierre(v_acreditacion.origen) then 1 else 0 end;
    if v_acreditado is null or v_numerador<=0 then return null; end if;
    -- Para referidos prevalece el peso de la foto que efectivamente se pagó.
    if exists(select 1 from crm.conversion_acreditaciones ca
      where ca.lead_id=p_lead_id and ca.origen='referido') then
      select pc.ponderacion_referido into v_numerador from crm.periodos_cerrados pc
        where pc.periodo=v_periodo;
    end if;
    if v_numerador is null or v_numerador<=0 then return null; end if;
  else
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

  end if;

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

$function$;

alter table crm.conversion_acreditaciones drop column ajuste_anulacion_en_sello;
comment on function private.conversion_episodios(timestamp with time zone,timestamp with time zone,date,boolean,uuid[],numeric) is 'Núcleo único de la conversión: llegadas (divisor), cierres de leads y operaciones de cartera (numerador). Desde 2026-10 aplica el TOPE DE REFERIDOS (private.tope_referidos_conversion) por analista y mes de cierre; su base son los cierres de leads asignados por el sistema (private.conversion_origen_base_tope), calculada sobre el mes completo de cada analista y recortada después al rango pedido. BAJA DE ANALISTA (09/10/2026): la pierna de operaciones usa private.analista_efectivo_contrato; las piernas de leads (ledger) no cambian.';
comment on function private.conversion_fijar_sello_trg() is null;
comment on function private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid) is 'Si el cierre anulado pertenece a un mes YA CERRADO, registra la deuda que el vendedor arrastrara al mes vivo. Si el mes sigue abierto devuelve NULL: ese mes se recalcula solo. Toma el cerrojo del periodo, el mismo que crm.cerrar_periodo: sin el, anular a la vez que se sella pierde la deuda en silencio.';
comment on column crm.conversion_pesos.tope_referidos_pct is 'Tope de referidos: porcentaje de los cierres del mes de un analista de leads asignados por el sistema (origen landing o formulario; sin referidos, renovaciones, upgrades ni base cargada; redondeado hacia arriba) que los referidos pueden contar. Los referidos que pasan del tope, del más reciente al más antiguo, valen 0. NULL = sin tope (agosto y septiembre de 2026). Rige desde la versión que lo trae (2026-10-01, 15,00). Cambiarlo es una decisión comercial: se inserta una versión nueva, el pasado no se mueve.';
commit;
