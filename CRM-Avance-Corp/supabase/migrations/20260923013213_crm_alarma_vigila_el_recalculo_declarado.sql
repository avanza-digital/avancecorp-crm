-- =========================================================================
-- CRM · El oraculo vuelve a vigilar el RECALCULO, no solo la cifra publicada
-- =========================================================================
-- QUE PROBLEMA ARREGLA. La Ola 1b hizo que la puerta #4 DELEGUE su cifra en
-- `crm.conversion_mensual_fn`. Efecto colateral en la alarma: el camino
-- `rango` paso a ser, POR CONSTRUCCION, identico a `mensual`. Esa comparacion
-- dejo de tener dientes, y con ella se perdio lo unico que vigilaba si el
-- calculo propio de esa puerta derivaba.
--
-- Dicho de otro modo: el oraculo seguia en verde, pero una de sus cuatro
-- comparaciones ya no podia fallar nunca. Un gate que no puede ponerse rojo no
-- es un gate.
--
-- QUE HACE:
--   1. Anade un quinto camino, `rango_recalculo`, leido de
--      `nucleo.recalculo_vivo` —lo que la puerta #4 HABRIA publicado— y exige
--      que siga dando el BRUTO, igual que `nucleo_directo`. Ahi vuelven los
--      dientes.
--   2. Exige que las puertas que deben delegar lo **DECLAREN**
--      (`nucleo.fuente = 'mensual'`). Publicar la cifra buena sin decir de
--      donde sale es un acierto por casualidad, y esta unificacion vino a
--      matar exactamente eso. Es el «el oraculo distingue cifra oficial de
--      recalculo declarado» del objetivo, hecho comprobacion.
--   3. Publica en el paquete `declaran`, con lo que dice cada puerta, para que
--      un rojo se pueda leer sin abrir la base.
--
-- LA DISTRIBUCION SE TOLERA SIN DECLARAR (`is null`) a proposito: su Ola 1a
-- sigue parada a la espera del release del front. En cuanto entre, empezara a
-- decir 'mensual' y esta misma comprobacion la cubrira sin tocar nada.
--
-- SIN RIESGO PARA NINGUNA PANTALLA: `crm.alarma_conversion_fn` solo la puede
-- llamar el rol de servicio (los gates) o una sesion de operador sin claims;
-- un usuario del CRM, del rol que sea, recibe 42501. No tiene consumidor en el
-- front, ni directo ni heredado — comprobado con
-- `supabase/scripts/conversion/quien-me-envuelve.sql`.
--
-- MEDIDO, y fijado en el preflight:
--   · md5(pg_get_functiondef) = 26e96217f0b9d35cf14a43f996afb0ba
--   · dueno postgres · NI declarada NI en el censo: no hay huella que re-sellar.
--
-- REVERSA: volver a declarar el cuerpo anterior (cuatro caminos, sin
-- `declaraciones` ni `declaran`).
-- =========================================================================

begin;

set local statement_timeout = '180s';

do $preflight$
declare v_md5 text;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.alarma_conversion_fn(date)');
  if v_md5 is distinct from '26e96217f0b9d35cf14a43f996afb0ba' then
    raise exception 'PREFLIGHT: la alarma no es el cuerpo revisado (md5 %)', v_md5;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('crm','private','public')
                and p.prosrc like '%alarma_conversion_fn%'
                and p.proname <> 'alarma_conversion_fn') then
    raise exception 'PREFLIGHT: alguien envuelve la alarma; hay que mirar SU consumidor antes de tocarla';
  end if;
end;
$preflight$;

create temp table _al_antes (v jsonb) on commit drop;
insert into _al_antes (v) select crm.alarma_conversion_fn();

CREATE OR REPLACE FUNCTION crm.alarma_conversion_fn(p_mes date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_claims text := current_setting('request.jwt.claims', true);
  v_rol_llamante text;
  v_gerente uuid;
  v_mes date;
  v_hasta date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_resultado jsonb;
begin
  -- (1) Solo el rol de servicio (gates) o una sesion de operador sin claims.
  --     Un usuario del CRM, del rol que sea, recibe 42501.
  if v_claims is not null and v_claims <> '' then
    v_rol_llamante := (v_claims::jsonb) ->> 'role';
    if v_rol_llamante is distinct from 'service_role' then
      raise exception 'No autorizado' using errcode = '42501';
    end if;
  end if;

  v_mes := coalesce(p_mes, date_trunc('month', (now() at time zone 'America/Lima'))::date);
  if v_mes <> date_trunc('month', v_mes)::date then
    raise exception 'p_mes debe ser el dia 1 de un mes' using errcode = '22023';
  end if;
  -- Mes vigente: hasta hoy (Lima). Mes pasado: mes completo.
  v_hasta := least((now() at time zone 'America/Lima')::date,
                   (v_mes + interval '1 month - 1 day')::date);
  v_ini := v_mes::timestamp at time zone 'America/Lima';
  v_fin := (v_hasta + 1)::timestamp at time zone 'America/Lima';

  -- (2) Impersonacion transaccional de un perfil de gerencia activo, solo para
  --     que las RPC pasen su propio gate. Muere con la transaccion.
  -- Por crm.equipo y no por public.perfiles: `private.rol_crm` se evaluaria por
  -- cada perfil del portal. Misma semantica fail-closed, N mucho menor.
  select e.perfil_id into v_gerente from crm.equipo e
  where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
  order by e.perfil_id limit 1;
  if v_gerente is null then
    return jsonb_build_object('mes', v_mes, 'hasta', v_hasta, 'cuadra', null,
      'caminos_leidos', 0, 'motivo', 'sin_perfil_de_gerencia_activo');
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);

  -- Los claims de `set_config(..., true)` viven hasta el fin de la TRANSACCION,
  -- no hasta el `return`. Si no se restauran, una segunda llamada dentro de la
  -- misma transaccion entra como `authenticated` y se deniega a si misma (es
  -- justo lo que hace el mutante). Se restauran en los DOS caminos de salida,
  -- como ya hacen 20260905233000 y 20260902050000.
  begin
    with nucleo as (
      -- coalesce a 0: un mes sin episodios daba NULL y el veredicto salia rojo
      -- sin que nada estuviera roto (las primeras horas del dia 1 en Lima).
      select coalesce(sum(e.aporte_divisor), 0)::numeric as divisor,
             round(coalesce(sum(e.aporte_numerador), 0), 4) as numerador,
             round(100.0 * sum(e.aporte_numerador) / nullif(sum(e.aporte_divisor), 0), 2) as pct
      from private.conversion_episodios(v_ini, v_fin, v_mes, true, null, private.peso_referido_conversion(v_mes)) e
    ), mensual as (
      select (m.j -> 'total' ->> 'divisor')::numeric, (m.j -> 'total' ->> 'numerador')::numeric,
             (m.j -> 'total' ->> 'conversion_pct')::numeric
      from (select crm.conversion_mensual_fn(v_mes) as j) m
    ), rango as (
      select (r.j -> 'nucleo' ->> 'divisor')::numeric, (r.j -> 'nucleo' ->> 'numerador')::numeric,
             (r.j -> 'nucleo' ->> 'conversion_pct')::numeric
      from (select crm.metricas_conversiones_fn(v_mes, v_hasta, null) as j) r
    ), distribucion as (
      select (d.j -> 'resumen' -> 'conversion' ->> 'nucleo_divisor')::numeric,
             (d.j -> 'resumen' -> 'conversion' ->> 'nucleo_numerador')::numeric,
             (d.j -> 'resumen' -> 'conversion' ->> 'nucleo_conversion_pct')::numeric
      from (select crm.metricas_distribucion_leads_v3_fn(v_mes, v_hasta) as j) d
    ), rango_recalculo as (
      -- EL CAMINO QUE LA OLA 1b HABIA DEJADO CIEGO. Desde que la puerta #4
      -- DELEGA, `rango` es por construccion igual a `mensual`: esa comparacion
      -- dejo de tener dientes. Lo que ya no se vigilaba es lo que esa puerta
      -- CALCULARIA por su cuenta — justo lo que antes cazaba la deriva.
      -- `nucleo.recalculo_vivo` lo conserva, y aqui se vuelve a mirar.
      -- Si la puerta NO delego (no hay `recalculo_vivo`), lo publicado YA es el
      -- recalculo: se usa eso, y `fuente` dira que fue asi.
      select coalesce((r.j #> '{nucleo,recalculo_vivo}' ->> 'divisor')::numeric,
                      (r.j -> 'nucleo' ->> 'divisor')::numeric) as divisor,
             coalesce((r.j #> '{nucleo,recalculo_vivo}' ->> 'numerador')::numeric,
                      (r.j -> 'nucleo' ->> 'numerador')::numeric) as numerador,
             coalesce((r.j #> '{nucleo,recalculo_vivo}' ->> 'conversion_pct')::numeric,
                      (r.j -> 'nucleo' ->> 'conversion_pct')::numeric) as pct
      from (select crm.metricas_conversiones_fn(v_mes, v_hasta, null) as j) r
    ), declaraciones as (
      -- QUE DICE CADA PUERTA DE SI MISMA. El oraculo no solo compara numeros:
      -- comprueba que quien sirve la cifra oficial lo DECLARE. Una puerta que
      -- publique la cifra buena sin decir de donde sale es un acierto por
      -- casualidad, y esta unificacion vino a matar precisamente eso.
      select (select r.j #> '{nucleo,fuente}'
                from (select crm.metricas_conversiones_fn(v_mes, v_hasta, null) as j) r) as rango_fuente,
             (select d.j #> '{resumen,conversion,fuente}'
                from (select crm.metricas_distribucion_leads_v3_fn(v_mes, v_hasta) as j) d) as distribucion_fuente
    ), caminos_base as (
      select 'nucleo_directo' as camino, * from nucleo
      union all select 'mensual', * from mensual
      union all select 'rango', * from rango
      union all select 'distribucion', * from distribucion
      union all select 'rango_recalculo', * from rango_recalculo
    ), deuda as (
      select ap.vendedor_id, ap.numerador as pendiente
      from private.ajuste_pendiente_por_vendedor() ap
    ), por_analista as (
      select e.analista_id, sum(e.aporte_numerador) as bruto_v
      from private.conversion_episodios(v_ini, v_fin, v_mes, true, null,
             private.peso_referido_conversion(v_mes)) e
      where e.analista_id is not null
      group by e.analista_id
    ), conciliacion as (
      select round(coalesce(sum(pa.bruto_v), 0), 4) as bruto,
             round(coalesce(sum(private.conversion_con_ajuste(pa.bruto_v, d.pendiente)), 0), 4) as neto,
             round(coalesce(sum(d.pendiente), 0), 4) as deuda_pendiente,
             round(coalesce(sum(pa.bruto_v), 0)
                   - coalesce(sum(private.conversion_con_ajuste(pa.bruto_v, d.pendiente)), 0), 4) as deuda_aplicada,
             count(*) filter (where coalesce(d.pendiente, 0) > pa.bruto_v) as topados
      from por_analista pa left join deuda d on d.vendedor_id = pa.analista_id
    )
    select jsonb_build_object(
      'mes', v_mes, 'hasta', v_hasta,
      'cuadra',
        (select count(distinct p.divisor) = 1 and count(distinct p.numerador) = 1
                and count(distinct coalesce(p.pct, -1)) = 1
                and count(*) filter (where p.divisor is null or p.numerador is null) = 0
         from caminos_base p where p.camino not in ('nucleo_directo', 'rango_recalculo'))
        -- El recalculo de la puerta #4 tiene que seguir dando EL BRUTO, igual
        -- que el nucleo directo. Si deriva, la puerta estaria calculando otra
        -- cosa aunque publique la oficial — y nadie se enteraria.
        and (select p.numerador = (select c.bruto from conciliacion c)
             from caminos_base p where p.camino = 'rango_recalculo')
        and (select p.divisor = (select b.divisor from caminos_base b where b.camino = 'nucleo_directo')
             from caminos_base p where p.camino = 'rango_recalculo')
        -- Y las dos puertas que deben delegar, lo DECLARAN.
        and (select d.rango_fuente = '"mensual"'::jsonb from declaraciones d)
        and (select d.distribucion_fuente is null or d.distribucion_fuente = '"mensual"'::jsonb
               from declaraciones d)
        and (select p.numerador = (select c.neto from conciliacion c)
             from caminos_base p where p.camino = 'mensual')
        and (select b.numerador = (select c.bruto from conciliacion c)
             from caminos_base b where b.camino = 'nucleo_directo')
        -- El DIVISOR sigue anclado a los cuatro: la deuda solo toca el
        -- numerador (`greatest(num - pend, 0)`), nunca el divisor. Soltar esta
        -- comparacion habria dejado pasar en VERDE una deriva compartida del
        -- divisor entre los tres envoltorios. Lo levanto el auditor.
        and (select b.divisor = (select p.divisor from caminos_base p where p.camino = 'mensual')
             from caminos_base b where b.camino = 'nucleo_directo')
        and (select c.bruto - c.neto = c.deuda_aplicada from conciliacion c)
        and (select c.deuda_aplicada <= c.deuda_pendiente from conciliacion c)
        and (select c.topados > 0 or c.deuda_aplicada = c.deuda_pendiente from conciliacion c),
      'motivo', case when (select max(b.divisor) from caminos_base b) = 0 then 'sin_datos' end,
      'caminos_leidos', (select count(*) from caminos_base),
      'declaran', (select jsonb_build_object('rango', d.rango_fuente,
                                             'distribucion', d.distribucion_fuente)
                     from declaraciones d),
      'conciliacion', (select jsonb_build_object(
          'bruto_numerador', c.bruto, 'neto_numerador', c.neto,
          'deuda_pendiente', c.deuda_pendiente, 'deuda_aplicada', c.deuda_aplicada,
          'vendedores_topados', c.topados) from conciliacion c),
      'detalle', (select jsonb_object_agg(b.camino, jsonb_build_object(
          'divisor', b.divisor, 'numerador', b.numerador, 'pct', b.pct)) from caminos_base b))
    into v_resultado;
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  return v_resultado;
end;
$function$;

do $postflight$
declare v_a jsonb; v_d jsonb;
begin
  select v into v_a from _al_antes;
  v_d := crm.alarma_conversion_fn();

  -- 1) Sigue en VERDE: este cambio endurece el criterio, no rompe la realidad.
  if (v_d ->> 'cuadra')::boolean is not true then
    raise exception 'POSTFLIGHT: la alarma se puso en ROJO con el criterio nuevo: %', v_d;
  end if;

  -- 2) Ahora son CINCO caminos.
  if (v_d ->> 'caminos_leidos')::int <> 5 then
    raise exception 'POSTFLIGHT: caminos_leidos = %, y deberian ser 5', v_d ->> 'caminos_leidos';
  end if;

  -- 3) El camino nuevo existe y da el BRUTO, no el neto.
  if v_d #> '{detalle,rango_recalculo}' is null then
    raise exception 'POSTFLIGHT: falta el camino rango_recalculo en el detalle';
  end if;
  if (v_d #>> '{detalle,rango_recalculo,numerador}')::numeric
       is distinct from (v_d #>> '{conciliacion,bruto_numerador}')::numeric then
    raise exception 'POSTFLIGHT: rango_recalculo (%) no es el bruto (%)',
      v_d #>> '{detalle,rango_recalculo,numerador}', v_d #>> '{conciliacion,bruto_numerador}';
  end if;

  -- 4) Y la puerta #4 DECLARA que delego.
  if (v_d #> '{declaran,rango}') is distinct from '"mensual"'::jsonb then
    raise exception 'POSTFLIGHT: la puerta #4 no declara mensual: %', v_d -> 'declaran';
  end if;

  -- 5) Lo que ya vigilaba sigue vigilado: la conciliacion no se movio.
  if (v_a -> 'conciliacion') is distinct from (v_d -> 'conciliacion') then
    raise exception 'POSTFLIGHT: la conciliacion cambio. antes % · despues %',
      v_a -> 'conciliacion', v_d -> 'conciliacion';
  end if;

  -- 6) EL MUTANTE: si el recalculo de la #4 derivara del bruto, ¿se pondria
  --    roja? Se comprueba que la regla existe, leyendo el cuerpo. (Probarlo de
  --    verdad exigiria falsear `recalculo_vivo`, que es lo que este camino
  --    vigila; el gate `npm run test:mutantes` es el sitio de esa prueba.)
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.alarma_conversion_fn(date)')
                    and p.prosrc like '%rango_recalculo%'
                    and p.prosrc like '%declaraciones%') then
    raise exception 'POSTFLIGHT: el cuerpo no tiene la regla nueva';
  end if;
end;
$postflight$;

comment on function crm.alarma_conversion_fn(date) is
  'Oraculo de la conversion, solo para el rol de servicio. Lee CINCO caminos y exige tres '
  'cosas distintas: (1) que los que sirven la cifra oficial —mensual, rango, distribucion— '
  'coincidan entre si; (2) que los que calculan el BRUTO —nucleo_directo y rango_recalculo, '
  'este ultimo leido de nucleo.recalculo_vivo— coincidan con el bruto conciliado; y (3) que '
  'las puertas que deben delegar lo DECLAREN (fuente=mensual). El camino rango_recalculo '
  'existe porque, desde que la puerta #4 delega, comparar `rango` con `mensual` dejo de poder '
  'fallar: un gate que no puede ponerse rojo no es un gate.';

select 'alarma-vigila-el-recalculo' as migracion,
       crm.alarma_conversion_fn() -> 'cuadra' as cuadra,
       crm.alarma_conversion_fn() -> 'caminos_leidos' as caminos,
       crm.alarma_conversion_fn() -> 'declaran' as declaran;

commit;
