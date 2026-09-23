-- =========================================================================
-- CRM · La RENOVACION deja de compartir la palanca del REFERIDO
-- =========================================================================
-- QUE HACE: `crm.conversion_pesos` gana una columna propia para el peso de la
-- renovacion, con su lectora, y el nucleo la usa en vez de reutilizar el peso
-- del referido.
--
-- 🔑 NO CAMBIA NI UN NUMERO. La columna nace con `default 0.15`, que es lo que
--    la renovacion vale HOY por reutilizar el peso del referido. Separar la
--    palanca no es moverla: el valor se queda donde esta, y el postflight
--    exige que la cifra de conversion no se mueva ni un decimal.
--
-- EL PROBLEMA QUE RESUELVE. La rama 'operacion' del nucleo usaba `p_factor`,
-- que es el peso del REFERIDO, tambien para la RENOVACION. Un solo numero
-- servia a dos conceptos comerciales distintos: cambiar el incentivo del
-- referido —decision perfectamente razonable— movia el de la renovacion sin
-- que nadie se enterara. El UPGRADE nunca estuvo acoplado: su peso es el
-- literal 1.
--
-- POR QUE `default 0.15` Y NO NULL: `crm.conversion_pesos` esta VERSIONADA por
-- `vigente_desde`, y los meses pasados se calculan con el peso que tenian. Una
-- columna que naciera NULL reescribiria el pasado; una que nace con 0.15
-- reproduce exactamente el comportamiento actual para la unica fila que hay
-- (vigente_desde 2026-07-01) y para cualquier fila futura que se olvide de
-- fijarlo.
--
-- LO QUE NO SE TOCA, Y ES DELIBERADO:
--   · El VALOR sigue siendo 0,15. Separar no es cambiar; mover el peso es una
--     decision de Miguel, no de esta migracion.
--   · El peso del referido, que sigue viniendo de `peso_referido`.
--   · El upgrade, que conserva su 1.
--   · La FIRMA de `private.conversion_episodios`, que no cambia: por eso
--     NINGUN llamador hay que redeclararlo en cascada.
--
-- 🔑 POR QUE LA SUSTITUCION ES EQUIVALENTE, Y NO SOLO «HOY DA IGUAL».
--    La rama de mes calendario pasa de `p_factor` a
--    `private.peso_renovacion_conversion(p_periodo)`. Son dos meses distintos
--    en el papel: `p_factor` lo calcula cada llamador como
--    `peso_referido_conversion(date_trunc('month', p_hasta))`, y `p_periodo` es
--    el mes calendario. VERIFICADO el 23/09 en los tres llamadores que pasan
--    `p_periodo` no nulo (`metricas_conversiones_implementacion`,
--    `metricas_conversiones_equipo_fn`, `metricas_distribucion_leads_v3_core`):
--    los tres definen `v_mes := date_trunc('month', p_hasta)` y solo asignan
--    `v_periodo` cuando `date_trunc('month', p_hasta) = date_trunc('month', p_desde)`
--    y `p_desde` es el dia 1. Es decir: **cuando `p_periodo` no es nulo, es el
--    mismo mes que `v_mes` por construccion**, no por casualidad.
--    (Ademas, hoy la tabla tiene UNA fila, asi que cualquier fecha devuelve
--    0.150 y nada podria moverse aunque los meses difirieran. Pero eso es un
--    accidente del dato, no un argumento: el argumento es el de arriba.)
--
--    ⚠️ ESO ES UNA PROPIEDAD DE LOS LLAMADORES, no del nucleo. Un llamador
--    futuro que pase un `p_periodo` de un mes y un `p_factor` de otro romperia
--    la equivalencia. Si alguna vez se añade uno, comprueba esto.
--
-- MEDIDO EN PRODUCCION EL 23/09/2026, y fijado en el preflight:
--   · nucleo vivo: md5(pg_get_functiondef) = 851a5b9e70bc97b9664f5fd38a9c41c4
--   · `private.conversion_episodios` NO esta censada en
--     `private.analitica_leads_citas_exenciones`: no hay huella que re-sellar.
--   · `crm.conversion_pesos` tiene UNA sola fila (vigente_desde 2026-07-01,
--     peso_referido 0.150) y RLS ON sin policies, con grants solo a postgres:
--     se lee exclusivamente por la funcion definer, asi que no hay riesgo de
--     grant-por-columna.
--
-- 🔴 LO QUE ESTA MIGRACION **NO** RESUELVE, y hay que hacer ANTES DE SELLAR EL
--    PRIMER MES: `crm.periodos_cerrados` guarda solo `ponderacion_referido`. El
--    peso de renovacion de un mes sellado se RECONSTRUYE desde el del referido.
--    Hoy esa tabla esta VACIA, asi que la ventana esta abierta; en cuanto se
--    selle el primer mes, ese mes queda reconstruido mal para siempre. Va en la
--    migracion siguiente.
--
-- REVERSA: volver a declarar el cuerpo del nucleo con `p_factor` en la rama de
-- renovacion, borrar `private.peso_renovacion_conversion(date)` y quitar la
-- columna `peso_renovacion`. Mientras el valor sea 0.15 en las dos, la reversa
-- no mueve ninguna cifra tampoco.
-- =========================================================================

begin;

set local statement_timeout = '180s';

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT: acreditar por IDENTIDAD lo que se va a tocar.
-- ---------------------------------------------------------------------------
do $preflight$
declare v_md5 text; v_filas int;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)');
  if v_md5 is distinct from '851a5b9e70bc97b9664f5fd38a9c41c4' then
    raise exception 'PREFLIGHT: el nucleo no es el cuerpo revisado (md5 %)', v_md5;
  end if;

  -- La columna no puede existir ya.
  if exists (select 1 from information_schema.columns
              where table_schema = 'crm' and table_name = 'conversion_pesos'
                and column_name = 'peso_renovacion') then
    raise exception 'PREFLIGHT: crm.conversion_pesos.peso_renovacion ya existe';
  end if;

  -- 🔑 EL SUPUESTO HISTORICO, FIJADO DE VERDAD (reparo P2 de Codex, 23/09).
  -- La cabecera prometia «fijado en el preflight» y esto solo comprobaba que la
  -- tabla no estuviera vacia. El contraejemplo de Codex es valido: con versiones
  -- julio=0.10, agosto=0.20, septiembre=0.15 y una renovacion en cada mes, la
  -- migracion las aplanaria TODAS a 0.15; el agregado seguiria sumando 0.45 y
  -- ni el postflight ni la prueba del 0.9 lo notarian. Julio y agosto habrian
  -- cambiado en silencio. Asi que se exige el estado exacto que se midio.
  select count(*) into v_filas from crm.conversion_pesos;
  if v_filas <> 1 then
    raise exception 'PREFLIGHT: crm.conversion_pesos tiene % filas y se reviso con UNA. Con varias versiones de peso, el default 0.15 reescribiria el pasado de los meses cuyo peso NO fuera 0.15: hay que fijar el default por fila antes de seguir.', v_filas;
  end if;
  if not exists (select 1 from crm.conversion_pesos
                  where vigente_desde = '2026-07-01'::date and peso_referido = 0.150) then
    raise exception 'PREFLIGHT: la unica fila no es la revisada (vigente_desde 2026-07-01, peso_referido 0.150)';
  end if;
end;
$preflight$;

-- Foto de referencia ANTES de tocar nada: la cifra del mes y la suma del aporte
-- de las renovaciones, que es justo lo que esta migracion podria mover.
create temp table _pr_antes (nucleo jsonb, aporte_renov numeric, n_renov int) on commit drop;
-- Y el aporte de renovacion POR MES, no solo el agregado: un agregado puede
-- quedarse igual mientras dos meses se compensan (reparo P2 de Codex).
create temp table _pr_antes_mes (periodo date, aporte numeric, n int) on commit drop;

insert into _pr_antes_mes (periodo, aporte, n)
select e.categoria_periodo, round(sum(e.aporte_numerador), 4), count(*)::int
  from (select o.periodo as categoria_periodo, e2.aporte_numerador
          from private.conversion_episodios(
                 '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
                 null::date, true, null, private.peso_referido_conversion(current_date)) e2
          join crm.operaciones_cartera o on o.id = e2.lead_id
         where e2.tipo = 'operacion' and e2.categoria = 'renovacion') e
 group by e.categoria_periodo;

insert into _pr_antes (nucleo, aporte_renov, n_renov)
select (select jsonb_build_object(
          'divisor', coalesce(sum(e.aporte_divisor), 0),
          'numerador', round(coalesce(sum(e.aporte_numerador), 0), 4))
        from private.conversion_episodios(
               date_trunc('month', (now() at time zone 'America/Lima'))::timestamptz,
               (date_trunc('month', (now() at time zone 'America/Lima')) + interval '1 month')::timestamptz,
               date_trunc('month', (now() at time zone 'America/Lima'))::date,
               true, null, private.peso_referido_conversion(
                 date_trunc('month', (now() at time zone 'America/Lima'))::date)) e),
       (select round(coalesce(sum(e.aporte_numerador), 0), 4)
        from private.conversion_episodios(
               '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
               null::date, true, null, private.peso_referido_conversion(current_date)) e
        where e.tipo = 'operacion' and e.categoria = 'renovacion'),
       (select count(*)::int
        from private.conversion_episodios(
               '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
               null::date, true, null, private.peso_referido_conversion(current_date)) e
        where e.tipo = 'operacion' and e.categoria = 'renovacion');

-- ---------------------------------------------------------------------------
-- (b) La columna. `not null default 0.15` = lo que la renovacion vale hoy.
-- ---------------------------------------------------------------------------
alter table crm.conversion_pesos
  add column peso_renovacion numeric not null default 0.15;

alter table crm.conversion_pesos
  add constraint conversion_pesos_peso_renovacion_rango
  check (peso_renovacion >= 0 and peso_renovacion <= 1);

comment on column crm.conversion_pesos.peso_renovacion is
  'Peso de una RENOVACION de cartera en el numerador de la conversion. Separado del '
  'peso del referido el 23/09/2026: hasta entonces la renovacion reutilizaba '
  'peso_referido, asi que mover el incentivo del referido movia tambien el de la '
  'renovacion. Nace en 0.15, que es lo que valia por esa reutilizacion, para no '
  'reescribir el pasado. Cambiarlo es una decision comercial, igual que el del referido.';

-- ---------------------------------------------------------------------------
-- (c) La lectora, calcada de la del referido (misma forma, mismo respaldo).
-- ---------------------------------------------------------------------------
create or replace function private.peso_renovacion_conversion(p_mes date)
returns numeric
language plpgsql
stable security definer
set search_path = ''
as $peso$
declare
  v_peso numeric;
begin
  select cp.peso_renovacion
    into v_peso
  from crm.conversion_pesos cp
  where cp.vigente_desde <= p_mes
  order by cp.vigente_desde desc
  limit 1;

  -- Fallback al mas antiguo: un mes anterior a la primera version del peso se
  -- calcula con esa primera version, que es la unica regla que existio. Es el
  -- mismo criterio que private.peso_referido_conversion.
  if v_peso is null then
    select cp.peso_renovacion
      into v_peso
    from crm.conversion_pesos cp
    order by cp.vigente_desde asc
    limit 1;
  end if;

  if v_peso is null then
    raise exception 'crm.conversion_pesos esta vacia: no hay peso de la renovacion con el que calcular la conversion'
      using errcode = '55000';
  end if;

  return v_peso;
end;
$peso$;

-- Los MISMOS revokes que su gemela `private.peso_referido_conversion`
-- (20260811154434:477). Revocar solo PUBLIC no quita concesiones individuales
-- que la funcion pudiera recibir: reparo P2 de Codex.
revoke all on function private.peso_renovacion_conversion(date) from public;
revoke all on function private.peso_renovacion_conversion(date) from anon, authenticated, service_role;

comment on function private.peso_renovacion_conversion(date) is
  'Peso de la renovacion vigente para un mes, leido de crm.conversion_pesos. Gemela de '
  'private.peso_referido_conversion: mismo criterio de vigencia por fecha y mismo '
  'respaldo a la version mas antigua. Existe desde el 23/09/2026 para que la renovacion '
  'deje de compartir palanca con el referido.';

-- ---------------------------------------------------------------------------
-- (d) El nucleo, generado POR ANCLAS sobre el vivo acreditado arriba. El unico
--     cambio es de donde sale el peso de la renovacion. La FIRMA no cambia.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.conversion_episodios(p_ini timestamp with time zone, p_fin timestamp with time zone, p_periodo date, p_global boolean, p_visibles uuid[], p_factor numeric)
 RETURNS TABLE(tipo text, analista_id uuid, lead_id uuid, operacion_id uuid, fue_referido boolean, aproximado boolean, motivo text, anulado boolean, origen text, categoria text, mes_origen date, monto numeric, moneda text, fecha_divisor timestamp with time zone, fecha_numerador timestamp with time zone, aporte_divisor integer, aporte_numerador numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
return query
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

-- El índice único del ledger garantiza un cierre por lead. El cierre queda
-- en quien lo consiguió, no en quien recibió la llegada. Los otros canales
-- siguen disponibles para consumidores operativos/capital, con aporte CERO.
select * from private.conversion_cierres(
  p_ini,p_fin,p_periodo,p_global,p_visibles,p_factor,null::uuid[])

union all

-- La primera operación ELEGIBLE por cliente/mes, antes de filtrar el rango
-- o el ámbito. Renovación usa el mismo peso que Referido; Upgrade conserva 1.
-- Un rango parcial incluye solo las operaciones efectivamente ocurridas allí.
select 'operacion'::text,
  coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id), o.vendedor_id),
  null::uuid, o.id, false, null::boolean, null::text, false,
  null::text, o.tipo, o.periodo, null::numeric, o.moneda,
  null::timestamptz, o.fecha_operacion::timestamp at time zone 'America/Lima', 0,
  case when o.tipo = 'renovacion' then
    -- La RENOVACION tiene su propio peso desde el 23/09/2026. Antes reutilizaba
    -- `p_factor`, que es el peso del REFERIDO: una sola palanca movia las dos
    -- cosas, y cambiar el incentivo del referido movia el de la renovacion sin
    -- que nadie se enterara. La estructura se conserva intacta —mes calendario
    -- usa el peso del periodo, rango libre el del mes de cada operacion— y lo
    -- unico que cambia es DE DONDE sale el numero.
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
  and (p_global or coalesce(private.analista_atribuido_cadena(o.contrato_nuevo_id),
                           o.vendedor_id) = any(p_visibles));
end;
$function$;

-- ---------------------------------------------------------------------------
-- (e) POSTFLIGHT: la promesa es que NO SE MUEVE NI UN DECIMAL.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_a record; v_nucleo jsonb; v_renov numeric; v_n int; v_mes date;
  v_prueba numeric; v_prueba_mes numeric; v_renov_mes numeric;
begin
  select * into v_a from _pr_antes;
  v_mes := date_trunc('month', (now() at time zone 'America/Lima'))::date;

  select jsonb_build_object('divisor', coalesce(sum(e.aporte_divisor), 0),
                            'numerador', round(coalesce(sum(e.aporte_numerador), 0), 4))
    into v_nucleo
    from private.conversion_episodios(
           v_mes::timestamptz, (v_mes + interval '1 month')::timestamptz, v_mes,
           true, null, private.peso_referido_conversion(v_mes)) e;

  select round(coalesce(sum(e.aporte_numerador), 0), 4), count(*)::int
    into v_renov, v_n
    from private.conversion_episodios(
           '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
           null::date, true, null, private.peso_referido_conversion(current_date)) e
   where e.tipo = 'operacion' and e.categoria = 'renovacion';

  -- El aporte de las renovaciones DEL MES, que es lo que ejerce la rama de mes
  -- calendario. Se mide aqui, con el peso vigente, para poder compararlo luego.
  select round(coalesce(sum(e.aporte_numerador), 0), 4) into v_renov_mes
    from private.conversion_episodios(
           v_mes::timestamptz, (v_mes + interval '1 month')::timestamptz, v_mes,
           true, null, private.peso_referido_conversion(v_mes)) e
   where e.tipo = 'operacion' and e.categoria = 'renovacion';

  -- 1) La cifra del mes, intacta.
  if v_nucleo is distinct from v_a.nucleo then
    raise exception 'POSTFLIGHT: la cifra del mes SE MOVIO. antes % · despues %', v_a.nucleo, v_nucleo;
  end if;

  -- 2) El aporte de TODAS las renovaciones del año, intacto. Es lo que esta
  --    migracion podria haber movido, asi que se mide aparte y entero.
  if v_renov is distinct from v_a.aporte_renov or v_n is distinct from v_a.n_renov then
    raise exception 'POSTFLIGHT: el aporte de las renovaciones SE MOVIO. antes % (% filas) · despues % (% filas)',
      v_a.aporte_renov, v_a.n_renov, v_renov, v_n;
  end if;

  -- 2b) Y el aporte MES A MES, intacto: el agregado puede cuadrar mientras dos
  --     meses se compensan entre si.
  if exists (
    select 1 from _pr_antes_mes a
    full outer join (
      select o.periodo, round(sum(e2.aporte_numerador), 4) as aporte, count(*)::int as n
        from private.conversion_episodios(
               '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
               null::date, true, null, private.peso_referido_conversion(current_date)) e2
        join crm.operaciones_cartera o on o.id = e2.lead_id
       where e2.tipo = 'operacion' and e2.categoria = 'renovacion'
       group by o.periodo) d on d.periodo = a.periodo
     where a.periodo is distinct from d.periodo
        or a.aporte is distinct from d.aporte
        or a.n is distinct from d.n) then
    raise exception 'POSTFLIGHT: el aporte de renovacion cambio en algun MES concreto, aunque el agregado cuadre';
  end if;

  -- 3) La lectora nueva devuelve hoy EXACTAMENTE lo mismo que la del referido:
  --    es lo que hace que separar no sea mover.
  if private.peso_renovacion_conversion(v_mes) is distinct from private.peso_referido_conversion(v_mes) then
    raise exception 'POSTFLIGHT: la lectora nueva (%) no coincide con la del referido (%) y hoy deberia',
      private.peso_renovacion_conversion(v_mes), private.peso_referido_conversion(v_mes);
  end if;

  -- 4) Y la palanca SEPARA DE VERDAD: se mueve el peso de la renovacion dentro
  --    de un savepoint, se comprueba que el del referido NO se inmuta y que el
  --    aporte de las renovaciones SI cambia, y se deshace.
  begin
    update crm.conversion_pesos set peso_renovacion = 0.9 where vigente_desde = (
      select max(vigente_desde) from crm.conversion_pesos);

    if private.peso_referido_conversion(v_mes) is distinct from 0.150 then
      raise exception 'POSTFLIGHT: mover la renovacion movio el peso del REFERIDO (%). No estan separados.',
        private.peso_referido_conversion(v_mes);
    end if;
    if private.peso_renovacion_conversion(v_mes) is distinct from 0.9 then
      raise exception 'POSTFLIGHT: la lectora de renovacion no ve el valor nuevo';
    end if;

    -- 🔑 LAS DOS RAMAS, no una (reparo P2 de Codex, 23/09). La prueba original
    -- solo llamaba con `p_periodo = null`: si la rama de MES CALENDARIO siguiera
    -- usando `p_factor` por accidente, el postflight habria pasado igual. Ahora
    -- se exige que el peso nuevo mueva el aporte en LAS DOS.

    -- (a) Rango libre: p_periodo NULL -> peso del mes de cada operacion.
    select round(coalesce(sum(e.aporte_numerador), 0), 4) into v_prueba
      from private.conversion_episodios(
             '2026-01-01'::timestamptz, (now() + interval '1 day')::timestamptz,
             null::date, true, null, private.peso_referido_conversion(current_date)) e
     where e.tipo = 'operacion' and e.categoria = 'renovacion';
    if v_prueba = v_renov then
      raise exception 'POSTFLIGHT (rango libre): se cambio el peso de la renovacion y el aporte NO se movio (%). Esa rama no usa la lectora nueva.', v_prueba;
    end if;

    -- (b) Mes calendario: p_periodo NO nulo. Se le pasa a proposito un
    --     `p_factor` DISTINTO del peso de renovacion (0.15 frente a 0.9): si la
    --     rama tomara el parametro en vez de su propia lectora, el aporte
    --     saldria con 0.15 y esta comprobacion lo cazaria.
    select round(coalesce(sum(e.aporte_numerador), 0), 4) into v_prueba_mes
      from private.conversion_episodios(
             v_mes::timestamptz, (v_mes + interval '1 month')::timestamptz, v_mes,
             true, null, 0.15::numeric) e
     where e.tipo = 'operacion' and e.categoria = 'renovacion';
    if v_renov_mes > 0 and v_prueba_mes = v_renov_mes then
      raise exception 'POSTFLIGHT (mes calendario): con peso 0.9 el aporte de renovacion del mes sigue siendo % — esa rama sigue usando el p_factor que se le pasa, no la lectora nueva.', v_prueba_mes;
    end if;
    if v_renov_mes > 0 and v_prueba_mes <> round(v_renov_mes / 0.15 * 0.9, 4) then
      raise exception 'POSTFLIGHT (mes calendario): el aporte con peso 0.9 es % y deberia ser % (= % renovaciones a 0.9)',
        v_prueba_mes, round(v_renov_mes / 0.15 * 0.9, 4), round(v_renov_mes / 0.15, 0);
    end if;

    raise exception 'DESHACIENDO_LA_PRUEBA';
  exception
    when others then
      if sqlerrm <> 'DESHACIENDO_LA_PRUEBA' then raise; end if;
  end;

  -- 5) Y tras deshacerla, el peso vuelve a ser el de siempre.
  if private.peso_renovacion_conversion(v_mes) is distinct from 0.150 then
    raise exception 'POSTFLIGHT: la prueba dejo el peso en % en vez de 0.150',
      private.peso_renovacion_conversion(v_mes);
  end if;

  -- 6) El upgrade sigue pesando 1 y NO depende de ninguna de las dos palancas.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)')
                    and p.prosrc like '%when o.tipo = ''upgrade'' then 1%') then
    raise exception 'POSTFLIGHT: el upgrade dejo de pesar 1 literal';
  end if;

  -- 7) La firma del nucleo NO cambio: por eso ningun llamador hay que tocarlo.
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'private' and p.proname = 'conversion_episodios') <> 1 then
    raise exception 'POSTFLIGHT: hay mas de un conversion_episodios: quedo un overload colgando';
  end if;

  -- 8) El trinquete, igual de verde que antes.
  if private.assert_analitica_leads_citas() not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo';
  end if;
end;
$postflight$;

select 'peso-renovacion-propio' as migracion,
       private.peso_referido_conversion(current_date) as peso_referido,
       private.peso_renovacion_conversion(current_date) as peso_renovacion,
       private.assert_analitica_leads_citas() as trinquete;

commit;
