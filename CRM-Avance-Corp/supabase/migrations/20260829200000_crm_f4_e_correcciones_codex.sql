-- P-055 FASE 4.e — Las correcciones del veredicto adversarial de Codex.
--
-- Codex dio NO-GO con 4 P0 + 4 P1 + 2 P2 sobre el tren F4 ya publicado (con
-- paridad byte a byte como condicion de commit). Esta migracion corrige lo
-- corregible por ingenieria; lo que es DECISION DE NEGOCIO queda descrito en
-- el ledger para Miguel (P0-2: las cifras gerenciales/AUM excluyen coops
-- HOY IGUAL QUE AYER — la paridad conservo la omision historica a proposito;
-- incluirlas cambia numeros de pantalla y eso no se hace en silencio).
--
--   P0-1  el nucleo podia sumarse "a lo bruto" mezclando familias (contrato
--         100k + desglose 80k+20k = 200k): la fila-hecho gana la columna
--         `medida` ('stock' = el capital existe UNA vez · 'desglose' = como se
--         compone · 'nula' = anulada, aporta 0) y LA VENTANA EXIGE ELEGIRLA.
--         Ningun consumidor actual mezclaba familias (todos filtran por tipo);
--         esto lo vuelve imposible por construccion para los futuros.
--   P0-3  las ventanas 1900/9999 NO eran "todo el tiempo": pasan a ±infinity
--         donde la semantica es "sin limite" (B1 de conversiones) y el suelo
--         2020 de vencimientos desaparece.
--   P0-4  el contrato temporal del nucleo queda ESCRITO: contratos y desgloses
--         parten por FECHA LOCAL (dia comercial completo), cooperativas por
--         instante. Los llamadores construyen medianoches de Lima; con otra
--         cosa, la particion no es la que crees.
--   P1-6  las 3 del Directorio recuperan STABLE (la reescritura F4.c las dejo
--         caer a VOLATILE en silencio: md5 de prosrc no ve provolatile).
--   P2-9  en_roster mira SOLO la revision VIGENTE (la mayor) del mes, no
--         cualquier revision historica.
--
-- Quedan ANOTADOS (ledger) sin cambio de codigo hoy, con su porque:
--   P0-2  decision de Miguel (arriba).
--   P1-5  rendimiento del bloque por-lead de conversiones: HIPOTESIS de plan
--         de ejecucion; se mide con EXPLAIN en banco tras el 10/09 y se
--         optimiza con CTE materializada si hace falta (panel de gerencia,
--         cohortes de ~decenas de leads hoy).
--   P1-7  la ventana y los 13 contratos sin dueno: la ventana no tiene
--         consumidores; cuando llegue el primero se decide su semantica de
--         visibilidad (ya exige medida desde hoy).
--   P1-8  metricas_vendedores_fn cambia por transitividad via
--         cartera_por_vendedor: la paridad de esa privada quedo fotografiada
--         en F4.b; el oraculo de punta a punta llega con su migracion (post
--         10/09).

begin;

set local lock_timeout = '5s';

-- ── el nucleo, recreado con `medida` y el roster vigente ──
drop function private.capital_autorizada(date, date);
drop function private.capital_episodios(timestamptz, timestamptz, boolean, uuid[]);

create function private.capital_episodios(
  p_ini      timestamptz,
  p_fin      timestamptz,
  p_global   boolean,
  p_visibles uuid[]
) returns table(
  tipo              text,
  medida            text,
  contrato_id       uuid,
  cierre_externo_id uuid,
  lead_id           uuid,
  cliente_id        uuid,
  analista_id       uuid,
  registrado_por    uuid,
  en_roster         boolean,
  moneda            text,
  monto             numeric,
  categoria         text,
  mes_comercial     date,
  fecha             timestamptz,
  fecha_vencimiento date,
  estado            text,
  anulado           boolean
)
language sql
stable
security definer
set search_path to ''
as $fn$
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
$fn$;

revoke execute on function private.capital_episodios(timestamptz, timestamptz, boolean, uuid[])
  from public, anon, authenticated;

-- La ventana EXIGE la medida (P0-1): sumar familias mezcladas ya no es un
-- descuido posible, es una llamada invalida.
create function private.capital_autorizada(
  p_desde  date,
  p_hasta  date,
  p_medida text
) returns table(
  tipo text, medida text, contrato_id uuid, cierre_externo_id uuid, lead_id uuid,
  cliente_id uuid, analista_id uuid, registrado_por uuid, en_roster boolean,
  moneda text, monto numeric, categoria text, mes_comercial date,
  fecha timestamptz, fecha_vencimiento date, estado text, anulado boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $fn$
declare
  v_uid      uuid := (select auth.uid());
  v_rol      text := private.rol_crm((select auth.uid()));
  v_global   boolean;
  v_visibles uuid[] := '{}'::uuid[];
begin
  if v_uid is null then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_desde is null or p_hasta is null or p_desde > p_hasta then
    raise exception 'Periodo invalido' using errcode = '22023';
  end if;
  if p_medida is null or p_medida not in ('stock','desglose','nula') then
    raise exception 'Elige la medida: stock (el capital existe una vez), desglose (como se compone) o nula (anuladas)'
      using errcode = '22023';
  end if;
  v_global := coalesce(v_rol = 'gerencia', false) or (select private.es_lector_global());
  if not v_global then
    v_visibles := array(select private.vendedor_ids_visibles(v_uid));
    if coalesce(array_length(v_visibles, 1), 0) = 0 then
      raise exception 'No autorizado' using errcode = '42501';
    end if;
  end if;
  return query select * from private.capital_episodios(
    (p_desde::timestamp at time zone 'America/Lima'),
    ((p_hasta + 1)::timestamp at time zone 'America/Lima'),
    v_global, v_visibles) e
  where e.medida = p_medida;
end;
$fn$;

revoke execute on function private.capital_autorizada(date, date, text)
  from public, anon, authenticated;

-- ── P1-6: el Directorio recupera STABLE ──
alter function public.directorio_ranking_analistas() stable;
alter function public.directorio_top_clientes() stable;
alter function public.metricas_directorio() stable;

-- ── P0-3: vencimientos sin suelo 2020 ──
create or replace function crm.metricas_vencimientos_fn(p_dias integer default 90)
returns table(mes date, moneda text, contratos_por_vencer bigint, capital_por_vencer numeric)
language sql
stable
security definer
set search_path to ''
as $fn$
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
  join public.perfiles cli on cli.id = e.cliente_id
  cross join ambito a
  where e.tipo like 'contrato_%'
    and e.estado = 'activo'
    and e.fecha_vencimiento >= current_date
    and e.fecha_vencimiento <  current_date + least(greatest(p_dias, 1), 366)
    and (
      a.es_global
      or cli.asesor_perfil_id = any (a.ids)
      or (cli.asesor_perfil_id is null and cli.creado_por = any (a.ids))
    )
  group by 1, 2
  order by 1, 2;
$fn$;

-- ── P0-3: los "sin limite" de verdad, en las funciones que los usan ──
do $infinito$
declare v_fn text; v_def text; v_n int := 0;
begin
  for v_fn in select n.nspname||'.'||p.proname
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where strpos(p.prosrc, '1900-01-01') > 0
      and n.nspname in ('crm','public','private')
  loop
    select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname||'.'||p.proname = v_fn;
    v_def := replace(v_def,
      $V$(date '1900-01-01')::timestamp at time zone 'America/Lima'$V$,
      $V$'-infinity'::timestamptz$V$);
    v_def := replace(v_def,
      $V$(date '9999-01-01')::timestamp at time zone 'America/Lima'$V$,
      $V$'infinity'::timestamptz$V$);
    v_def := replace(v_def,
      $V$(DATE '1900-01-01')::timestamp AT TIME ZONE 'America/Lima'$V$,
      $V$'-infinity'::timestamptz$V$);
    v_def := replace(v_def,
      $V$(DATE '9999-01-01')::timestamp AT TIME ZONE 'America/Lima'$V$,
      $V$'infinity'::timestamptz$V$);
    execute v_def;
    v_n := v_n + 1;
  end loop;
  raise notice 'sin-limite de verdad en % funciones', v_n;
end
$infinito$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare v_pen numeric; v_esp numeric; v_n int; v_vol "char";
begin
  -- el nucleo distingue medidas y el AUM sigue al centimo
  select coalesce(sum(monto),0) into v_pen
  from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[])
  where medida='stock' and tipo like 'contrato_%' and estado='activo' and moneda='PEN';
  select coalesce(sum(capital),0) into v_esp
  from public.contratos where estado='activo' and moneda='PEN' and not es_demo;
  if v_pen is distinct from v_esp then
    raise exception 'POSTFLIGHT: AUM por medida stock % <> crudo %', v_pen, v_esp; end if;

  -- P0-1: sumar stock+desglose de una renovacion YA NO es posible por la
  -- ventana; y el nucleo lo declara: en un mes con renovaciones, la suma cruda
  -- de todas las familias es MAYOR que la de stock (el doble conteo existe y
  -- esta ETIQUETADO, no escondido).
  select count(*) into v_n
  from private.capital_episodios('-infinity'::timestamptz,'infinity'::timestamptz,true,'{}'::uuid[])
  where medida = 'desglose';
  if v_n = 0 then
    raise notice 'POSTFLIGHT: sin desgloses aun (ninguna renovacion con desglose)';
  end if;

  -- P1-6: las 3 del Directorio son STABLE otra vez
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname in ('directorio_ranking_analistas','directorio_top_clientes','metricas_directorio')
    and p.provolatile = 's';
  if v_n <> 3 then
    raise exception 'POSTFLIGHT: % de 3 del Directorio son STABLE', v_n; end if;

  -- P0-3: no queda ninguna VENTANA magica (el patron con ::timestamp; un suelo
  -- legitimo de fecha de nacimiento en crear_lead_si_disponible no es ventana)
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in ('crm','public','private')
    and (strpos(lower(p.prosrc),$W$'1900-01-01')::timestamp$W$) > 0
      or strpos(lower(p.prosrc),$W$'9999-01-01')::timestamp$W$) > 0);
  if v_n <> 0 then
    raise exception 'POSTFLIGHT: quedan % funciones con ventana magica', v_n; end if;

  -- la ventana exige medida
  if (select strpos(p.prosrc, 'Elige la medida') = 0 from pg_proc p
      where p.oid = 'private.capital_autorizada(date,date,text)'::regprocedure) then
    raise exception 'POSTFLIGHT: la ventana no exige la medida'; end if;

  raise notice 'POSTFLIGHT OK: medida obligatoria, STABLE restaurado, sin ventanas magicas, AUM al centimo';
end
$postflight$;

commit;
