-- P-055 - La sancion de anular una cooperativa, empatada con el mes abierto.
--
-- QUE, en una linea: cuando gerencia anula un cierre en cooperativa y el mes YA
-- ESTA SELLADO, la deuda que se le anota al analista pasa a incluir tambien el
-- capital de ese cierre. Hasta hoy le devolvia la conversion y le regalaba el
-- capital.
--
-- REGLA DE NEGOCIO (Miguel, 2026-08-29): una anulacion NO elimina capital de la
-- empresa -la plata del cliente sigue ahi-. Es una SANCION al analista, para
-- cuando paso algo en la gestion. Este cambio no toca ni un sol del capital de
-- la empresa: `crm.ajustes_mes_cerrado` solo lo leen tres funciones y las tres
-- son la hoja del analista (`registrar_ajuste_si_mes_cerrado`, `saldar_ajustes`
-- y `ajuste_pendiente_por_vendedor`). Verificado por catalogo.
--
-- EL DEFECTO, MEDIDO CONTRA PRODUCCION EL 2026-08-29 (todo deshecho):
--   qorilazo, S/ 200 000, de una analista real.
--     - mes ABIERTO  -> se le quita la conversion Y el capital
--                       (produccion del mes 809 600 -> 609 600, exactamente -200 000)
--     - mes SELLADO  -> se le quita la conversion (numerador 1) y el capital
--                       se anota en CERO: PEN 0, USD 0, detalle []
--   Misma falta, misma sancion, dos resultados segun el dia en que se anule.
--
-- LA CAUSA: `registrar_ajuste_si_mes_cerrado` calcula el capital de la deuda
-- desde `private.contratos_afectados_por_anulacion`, que mira `public.contratos`
-- -y un cierre en cooperativa NO TIENE CONTRATO-. Los 7 cierres externos vivos
-- devuelven 0 contratos afectados. En cambio `private.produccion_mes_por_vendedor`
-- SI lee `crm.cierres_externos` y respeta `anulado_en`, que es por lo que el mes
-- abierto si lo descuenta.
--
-- EL ARREGLO: se copia la regla del mes abierto TAL CUAL, sin inventar una
-- segunda. La regla viva -bloque `externos_confirmados` de
-- `produccion_mes_por_vendedor`- dice: categoria 'nuevo', en SU moneda (PEN y
-- USD jamas se suman), atribuido al `vendedor_id` del cierre y SOLO si esa
-- persona estaba en el cuadro de metas de ese mes. Las cuatro condiciones se
-- reproducen aqui, una por una:
--   * `ce.anulado_en is not null` - solo lo anulado deja de pagar. Anular el
--     avance de un lead NO anula su cierre en cooperativa, ni aqui ni en el mes
--     abierto: son dos actos distintos y siguen siendolo.
--   * `ce.vendedor_id = v_acreditado` - solo se le puede quitar el merito a
--     quien lo tiene. Si el cierre acredito a otra persona, esa deuda no es de
--     este acreditado y no se le carga.
--   * ventana por `ce.creado_en` dentro del mes sellado - la misma que usa el
--     mes abierto; la fecha del cierre externo es automatica y no se retro-data.
--   * el vendedor, dentro del cuadro de metas de ese mes - si no estaba, el
--     cierre nunca le pago y no hay nada que devolver. Un mes sin metas
--     publicadas no tiene cuadro: entonces no hay capital de cooperativa que
--     descontar, exactamente como en el mes abierto.
--
-- DE PROPINA, UN FALLO LATENTE QUE SE CIERRA DE PASO: la version anterior
-- calculaba los totales (`v_pen`, `v_usd`) y el desglose (`v_detalle`) en DOS
-- consultas separadas sobre la misma fuente. Nada garantizaba que cuadraran, y
-- `private.saldar_ajustes` descuenta casilla a casilla leyendo el desglose. Aqui
-- salen de UNA sola consulta: no pueden divergir.
--
-- LO QUE ESTA MIGRACION NO CAMBIA: la firma, el dueno, `security definer`, el
-- `search_path` vacio, el cerrojo por periodo, las tres salidas tempranas
-- (lead inexistente o sin convertir / mes abierto / sin acreditado), la regla
-- del `on conflict (lead_id) do nothing` y el numerador. Solo cambia el calculo
-- del capital y del desglose.
--
-- CUANDO EMPIEZA A IMPORTAR: hoy no puede pasar -no hay ningun mes cerrado-.
-- La ventana se abre el 10/09, cuando el ciclo automatico selle agosto.
--
-- POR QUE ESTE NUMERO (antes era 20260829170000): la version nueva lee
-- `c.es_demo` (hallazgo A2 del auditor RLS: sin ese filtro, anular el cierre
-- de un lead con contrato DEMO generaba una deuda por capital que nunca
-- acredito — deuda fantasma). Esa columna nace en 20260829180000, asi que esta
-- migracion tiene que correr DESPUES. Renumerada el 29/08 ANTES de publicarse:
-- nunca existio en produccion con el numero viejo.

begin;

-- ---------------------------------------------------------------- PREFLIGHT --
do $preflight$
declare
  v_huella  text;
  v_regla   text;
begin
  -- 1) Se reemplaza LO QUE CREEMOS que se reemplaza.
  select md5(p.prosrc) into v_huella
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'registrar_ajuste_si_mes_cerrado'
    and pg_get_function_identity_arguments(p.oid) = 'p_lead_id uuid, p_motivo text, p_por uuid';

  if v_huella is null then
    raise exception 'No existe private.registrar_ajuste_si_mes_cerrado(uuid,text,uuid): ABORTA';
  end if;
  if v_huella <> 'e07c89715b96ee2604ce435fea3e2c34' then
    raise exception 'private.registrar_ajuste_si_mes_cerrado cambio desde que se escribio esta migracion (huella viva %). ABORTA: revisar a mano antes de pisarla', v_huella;
  end if;

  -- 2) La regla que estamos COPIANDO sigue siendo la que creemos. Si el mes
  --    abierto cambia de criterio, esta migracion se entera en vez de fabricar
  --    una segunda regla divergente en silencio.
  select p.prosrc into v_regla
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'produccion_mes_por_vendedor';

  if v_regla is null then
    raise exception 'No existe private.produccion_mes_por_vendedor: ABORTA';
  end if;
  if strpos(v_regla, 'from crm.cierres_externos ce') = 0
     or strpos(v_regla, 'and ce.anulado_en is null') = 0
     or strpos(v_regla, '''nuevo''::text as categoria') = 0
     or strpos(v_regla, 'and mv.vendedor_id=ce.vendedor_id') = 0 then
    raise exception 'La regla viva del mes abierto para cooperativas ya no tiene la forma que esta migracion copia. ABORTA';
  end if;

  -- 3) La columna que filtra la deuda fantasma (A2) tiene que existir ya.
  if not exists (select 1 from pg_attribute
                 where attrelid = 'public.contratos'::regclass
                   and attname = 'es_demo' and not attisdropped) then
    raise exception 'Falta la migracion 20260829180000 (es_demo): esta corre DESPUES. ABORTA';
  end if;

  -- 4) La tabla de deudas sigue teniendo las casillas que se escriben.
  if not exists (
    select 1 from pg_attribute
    where attrelid = 'crm.ajustes_mes_cerrado'::regclass
      and attname in ('capital_pen','capital_usd','detalle','pendiente_detalle')
    group by attrelid having count(*) = 4
  ) then
    raise exception 'crm.ajustes_mes_cerrado no tiene las 4 casillas esperadas: ABORTA';
  end if;
end
$preflight$;

-- ------------------------------------------------------------------ CAMBIO --
create or replace function private.registrar_ajuste_si_mes_cerrado(
  p_lead_id uuid,
  p_motivo  text,
  p_por     uuid
) returns uuid
language plpgsql
security definer
set search_path to ''
as $fn$
declare
  v_lead        crm.leads%rowtype;
  v_periodo     date;
  v_ini         timestamptz;
  v_fin         timestamptz;
  v_meta_id     uuid;
  v_acreditado  uuid;
  v_referido    boolean;
  v_peso        numeric;
  v_numerador   numeric;
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
  select coalesce(bool_or(la.origen = 'referido'), false) into v_referido
  from crm.lead_asignaciones la
  where la.lead_id = p_lead_id and la.resultado = 'convertido';

  v_peso := private.peso_referido_conversion(v_periodo);
  v_numerador := case when v_referido then v_peso else 1 end;

  -- La ventana del mes sellado y su cuadro de metas: los dos los necesita la
  -- rama de cooperativas para reproducir la regla del mes abierto.
  v_ini := v_periodo::timestamp at time zone 'America/Lima';
  v_fin := (v_periodo + interval '1 month')::timestamp at time zone 'America/Lima';
  select mp.id into v_meta_id
  from crm.meta_periodos mp
  where mp.periodo = v_periodo
  order by mp.revision desc
  limit 1;

  -- Y lo que valia en capital: todo lo que deja de acreditar, con la MISMA
  -- regla que la cuota. PEN y USD por separado -una deuda en soles no se paga
  -- con produccion en dolares- y ademas desglosado por categoria, que es la
  -- casilla exacta de la que habra que descontarlo.
  --
  -- Los totales y el desglose salen de UNA sola consulta a proposito: antes
  -- eran dos y nada garantizaba que cuadraran, mientras `saldar_ajustes`
  -- descuenta casilla a casilla leyendo el desglose.
  with piezas as (
    -- (a) Los contratos Avance que dejan de acreditar. SIN los de prueba
    --     (hallazgo A2): un contrato demo nunca sumo capital -la migracion
    --     20260829182000 lo saca de produccion_mes_por_vendedor-, asi que
    --     anularlo no puede generar deuda. Sin este filtro renaceria la misma
    --     asimetria mes abierto/mes sellado que esta migracion vino a matar.
    select c.categoria::text as categoria, c.moneda::text as moneda, c.capital as capital
    from private.contratos_afectados_por_anulacion(p_lead_id) x
    join public.contratos c on c.id = x and not c.es_demo

    union all

    -- (b) 2026-08-29 · Los cierres en COOPERATIVA del mismo lead que ya estan
    --     anulados. No tienen fila en `public.contratos`, asi que sin esta rama
    --     la sancion se quedaba a medias: el mes abierto si le quitaba el
    --     capital al analista y el mes sellado no.
    --     Regla copiada de `private.produccion_mes_por_vendedor`, bloque
    --     `externos_confirmados`, condicion por condicion.
    select 'nuevo'::text, ce.moneda::text, ce.monto
    from crm.cierres_externos ce
    where ce.lead_id = p_lead_id
      and ce.anulado_en is not null
      and ce.vendedor_id = v_acreditado
      and ce.creado_en >= v_ini
      and ce.creado_en <  v_fin
      and exists (
        select 1 from crm.metas_vendedor mv
        where mv.meta_periodo_id = v_meta_id
          and mv.vendedor_id = ce.vendedor_id
      )
  ), agrupado as (
    select p.categoria, p.moneda,
           sum(p.capital)  as capital,
           count(*)::int   as contratos
    from piezas p
    group by p.categoria, p.moneda
  )
  select
    coalesce(sum(a.capital) filter (where a.moneda = 'PEN'), 0),
    coalesce(sum(a.capital) filter (where a.moneda = 'USD'), 0),
    coalesce(jsonb_agg(jsonb_build_object(
      'categoria',  a.categoria,
      'moneda',     a.moneda,
      'capital',    a.capital,
      'contratos',  a.contratos)), '[]'::jsonb)
  into v_pen, v_usd, v_detalle
  from agrupado a;

  -- Un cierre que no valia nada no genera deuda.
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
$fn$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_src       text;
  v_secdef    boolean;
  v_cfg       text[];
  v_args      text;
  v_duenyo    text;
  v_volatile  "char";
begin
  select p.prosrc, p.prosecdef, p.proconfig, p.provolatile,
         pg_get_function_identity_arguments(p.oid),
         (select rolname from pg_roles where oid = p.proowner)
    into v_src, v_secdef, v_cfg, v_volatile, v_args, v_duenyo
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'registrar_ajuste_si_mes_cerrado';

  if v_src is null then
    raise exception 'POSTFLIGHT: la funcion desaparecio';
  end if;

  -- La forma no se movio.
  if v_args <> 'p_lead_id uuid, p_motivo text, p_por uuid' then
    raise exception 'POSTFLIGHT: la firma cambio (%)', v_args;
  end if;
  if not v_secdef then
    raise exception 'POSTFLIGHT: dejo de ser SECURITY DEFINER';
  end if;
  if v_duenyo <> 'postgres' then
    raise exception 'POSTFLIGHT: cambio de dueno (%)', v_duenyo;
  end if;
  if v_volatile <> 'v' then
    raise exception 'POSTFLIGHT: dejo de ser VOLATILE (%)', v_volatile;
  end if;
  -- ⚠️ `search_path=""` se guarda CON las comillas. Comprobar por
  -- `array['search_path=']` falla SIEMPRE. Trampa ya pagada tres veces.
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: se quedo sin search_path vacio (%)', v_cfg;
  end if;

  -- La rama nueva esta, y las cuatro condiciones copiadas tambien.
  if strpos(v_src, 'from crm.cierres_externos ce') = 0 then
    raise exception 'POSTFLIGHT: no quedo la rama de cooperativas';
  end if;
  if strpos(v_src, 'ce.anulado_en is not null') = 0
     or strpos(v_src, 'ce.vendedor_id = v_acreditado') = 0
     or strpos(v_src, 'mv.meta_periodo_id = v_meta_id') = 0
     or strpos(v_src, 'ce.creado_en >= v_ini') = 0 then
    raise exception 'POSTFLIGHT: la rama de cooperativas perdio alguna de sus cuatro condiciones';
  end if;

  -- A2: el filtro de demos quedo en la rama de contratos.
  if strpos(v_src, 'and not c.es_demo') = 0 then
    raise exception 'POSTFLIGHT: la deuda sigue contando contratos de prueba (A2)';
  end if;

  -- Y lo de siempre sigue estando: el cerrojo y las tres salidas tempranas.
  if strpos(v_src, 'pg_advisory_xact_lock') = 0 then
    raise exception 'POSTFLIGHT: se perdio el cerrojo por periodo';
  end if;
  if strpos(v_src, 'on conflict (lead_id) do nothing') = 0 then
    raise exception 'POSTFLIGHT: se perdio el on conflict por lead';
  end if;

  raise notice 'POSTFLIGHT OK: la sancion del mes sellado ya incluye el capital de cooperativa';
end
$postflight$;

commit;
