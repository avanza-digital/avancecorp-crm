-- La alarma de la conversion deja de exigir igualdad y pasa a CONCILIAR
-- (Ola 0 del plan de las doce puertas · Miguel, 22/09/2026).
--
-- EL DEFECTO. `crm.alarma_conversion_fn` exigia que los CUATRO caminos fueran
-- identicos. Pero `nucleo_directo` es el BRUTO por construccion —suma los
-- episodios— y los caminos publicados sirven el NETO, con la deuda por cierres
-- anulados ya descontada. Mientras no hubo ninguna deuda los cuatro coincidian
-- y la regla parecia correcta. NO LO ERA:
--
--   🔴 EN CUANTO HAYA DEUDA, ESA REGLA PONE EN ROJO EL TRABAJO BIEN HECHO.
--
-- Lo levanto el revisor secundario (Codex, 22/09) reproduciendolo: nucleo bruto
-- 3, caminos correctamente delegados al neto 2 -> seis diferencias, gate rojo.
-- El plan iba a verificarse con el criterio «ni un numero movido», que es justo
-- el que la correccion haria fallar.
--
-- MEDIDO CONTRA PRODUCCION (22/09, deuda de 2 puntos plantada y deshecha):
--
--   mensual        1218 / 49,650  ->  4,08 %     <- sirve el NETO
--   rango          1218 / 51,650  ->  4,24 %     <- sirve el BRUTO
--   distribucion   1218 / 51,650  ->  4,24 %     <- sirve el BRUTO
--   nucleo_directo 1218 / 51,650  ->  4,24 %     <- el BRUTO, por definicion
--
-- Dos porcentajes del mismo mes en la misma pantalla. Eso es el problema que
-- las doce puertas existen para resolver, y ya no es teoria.
--
-- ⚠️ CORRECCION IMPORTANTE, levantada por el auditor: LA PRIMERA VERSION DE
-- ESTA CABECERA SE CONTRADECIA A SI MISMA. Media (y dejaba escrito arriba) que
-- `rango` y `distribucion` sirven el BRUTO, y a renglon seguido enunciaba como
-- regla «los publicados sirven el NETO». Las dos cosas no pueden ser ciertas.
--
-- 🔴 LA VERDAD, Y HAY QUE DECIRLA ENTERA: **esta migracion NO hace que la
-- alarma quede verde cuando haya deuda.** Mientras `rango` y `distribucion`
-- sigan publicando el bruto, los tres publicados no coincidiran entre si y el
-- veredicto sera ROJO. Lo sera con la regla vieja y tambien con esta.
--
-- Y ESE ROJO ES CORRECTO. No es ruido conocido que haya que silenciar: es
-- exactamente la discrepancia que las doce puertas existen para resolver —dos
-- pantallas, dos porcentajes del mismo mes—, cazada por fin por su causa real.
-- Si algun dia aparece, NO se descarta: se arreglan las puertas.
--
-- ENTONCES, ¿QUE GANA ESTA MIGRACION? Tres cosas, y ninguna es «ponerse verde»:
--   1. El veredicto pasa a medir algo VERDADERO. La regla vieja comparaba los
--      publicados contra el nucleo BRUTO, asi que el dia que las puertas esten
--      BIEN —los tres sirviendo el neto— seguiria en rojo PARA SIEMPRE. Con
--      esta, ese dia se pone verde. Es la unica que puede.
--   2. Publica la CONCILIACION (bruto, neto, deuda pendiente, deuda aplicada,
--      topados), asi que un rojo se puede leer y atribuir en vez de adivinar.
--   3. Ancla el reparto: el nucleo dice el bruto, y bruto - neto es exactamente
--      la deuda aplicada.
--
-- LA REGLA, enunciada con precision:
--   a) los TRES publicados coinciden ENTRE SI. Hoy se cumple (deuda 0); con
--      deuda NO se cumplira hasta que las puertas pasen al neto.
--   b) el nucleo dice el BRUTO, y su DIVISOR coincide con el de los publicados
--      (la deuda solo toca el numerador, nunca el divisor).
--   c) `mensual` sirve el NETO conciliado.
--   d) bruto - neto es la deuda aplicada; no se aplica mas de la pendiente; y
--      sin nadie topado, se aplica toda.
--
-- 🔑 EL TOPE SE APLICA POR VENDEDOR. `private.conversion_con_ajuste` es
-- `greatest(num - pend, 0)`: si la deuda de alguien supera su bruto, su neto es
-- 0 y la diferencia NO es la resta limpia. Conciliar sobre los totales daria
-- otro numero y seria un falso verde. Por eso `por_analista` agrupa por
-- analista y el tope se aplica fila a fila.
--
-- COMPATIBLE HACIA ATRAS, comprobado en ensayo: hoy la deuda pendiente es 0,
-- asi que neto = bruto y el veredicto no cambia. Antes y despues:
--   cuadra=true · caminos_leidos=4 · pct=4.24 · `detalle` IDENTICO.
-- Se conservan todas las claves que leen sus consumidores (`cuadra`, `motivo`,
-- `caminos_leidos`, `detalle`, `mes`, `hasta`) y se ANADE `conciliacion`.
-- Consumidores: supabase/scripts/gate-realidad.mjs y test-rls.mjs.
--
-- EL CUERPO NO SE RETECLEA: se genero por anclas sobre el cuerpo VIVO capturado
-- hoy (md5 de su functiondef: 100710104007adf309f8d01401b8d133), que es la
-- leccion de F4 y la que hoy evito un error en otra migracion.
--
-- COMO SE REVIERTE. Reponiendo el cuerpo anterior, que vive en
-- `20260921182011_crm_alarma_conversion_un_solo_nucleo.sql`. No hay datos que
-- deshacer: esta migracion solo redefine una funcion de lectura.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;

-- ---------------------------------------------------------------------------
-- (a) PREFLIGHT
-- ---------------------------------------------------------------------------
do $preflight$
declare v_cuadra text; v_alarma jsonb;
begin
  -- El cuerpo vivo es EXACTAMENTE el que se leyo para generar este. Identidad
  -- por md5 del functiondef: comprobar fragmentos no acredita nada.
  if to_regprocedure('crm.alarma_conversion_fn(date)') is null then
    raise exception 'PREFLIGHT: no existe crm.alarma_conversion_fn(date)';
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.alarma_conversion_fn(date)')
                    and md5(pg_get_functiondef(p.oid)) = '100710104007adf309f8d01401b8d133') then
    raise exception 'PREFLIGHT: la alarma viva no es la que se leyo para generar esta migracion; releer antes de aplicar';
  end if;
  -- Las dos piezas de la conciliacion tienen que existir.
  if to_regprocedure('private.ajuste_pendiente_por_vendedor()') is null
     or to_regprocedure('private.conversion_con_ajuste(numeric,numeric)') is null then
    raise exception 'PREFLIGHT: falta ajuste_pendiente_por_vendedor o conversion_con_ajuste';
  end if;
  -- Y la alarma tiene que estar VERDE de partida: si ya estuviera roja, este
  -- cambio taparia un problema en vez de arreglarlo.
  -- Un banco sin sembrar no tiene perfil de gerencia y la alarma devuelve
  -- `cuadra: null` con ese motivo. Eso NO es un rojo: es «no evaluable», y
  -- abortar ahi haria la migracion inaplicable en branch y en Docker, que es
  -- justo donde manda el ciclo probarla. La migracion que creo la alarma ya
  -- preveia este caso y lo toleraba.
  select crm.alarma_conversion_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date) into v_alarma;
  v_cuadra := v_alarma ->> 'cuadra';
  if v_alarma ->> 'motivo' = 'sin_perfil_de_gerencia_activo' then
    raise notice 'PREFLIGHT: sin perfil de gerencia activo; quedan las anclas estructurales';
  elsif v_cuadra is distinct from 'true' then
    -- Un rojo POR DEUDA es justo lo que esta migracion viene a explicar mejor:
    -- no puede bloquearse a si misma. Cualquier otro rojo si se investiga.
    if (select count(*) from private.ajuste_pendiente_por_vendedor()) > 0 then
      raise notice 'PREFLIGHT: la alarma esta en % y hay deuda pendiente; es el caso que esta migracion explica', coalesce(v_cuadra,'null');
    else
      raise exception 'PREFLIGHT: la alarma esta en % SIN deuda pendiente; investigar antes de tocarla', coalesce(v_cuadra,'null');
    end if;
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- (b) La alarma, conciliando.
-- ---------------------------------------------------------------------------
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
    ), caminos_base as (
      select 'nucleo_directo' as camino, * from nucleo
      union all select 'mensual', * from mensual
      union all select 'rango', * from rango
      union all select 'distribucion', * from distribucion
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
         from caminos_base p where p.camino <> 'nucleo_directo')
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
$function$
;

comment on function crm.alarma_conversion_fn(date) is
  'Oraculo de la conversion del mes: lee la cifra por CUATRO caminos (nucleo directo, mensual, rango y '
  'distribucion) y CONCILIA en vez de exigir igualdad. El nucleo directo es el BRUTO por construccion '
  '(suma episodios); `mensual` sirve el NETO, con la deuda por cierres anulados descontada. Devuelve '
  '{mes, hasta, cuadra, motivo, caminos_leidos, detalle, conciliacion}. '
  '`conciliacion` trae bruto_numerador, neto_numerador, deuda_pendiente, deuda_aplicada y '
  'vendedores_topados; el tope (`greatest(num - pend, 0)`) se aplica POR VENDEDOR, no sobre los totales. '
  '🔴 Mientras `rango` y `distribucion` sigan publicando el BRUTO, un mes CON deuda dara `cuadra: false`, '
  'y ese rojo es CORRECTO: es la discrepancia que las doce puertas existen para resolver. No se silencia. '
  'Solo `service_role` puede ejecutarla; impersona un perfil de gerencia dentro de la transaccion y '
  'restaura los claims en los dos caminos de salida.';

-- ---------------------------------------------------------------------------
-- (c) POSTFLIGHT: el veredicto no cambia hoy, la conciliacion viaja, y el
--     contrato de seguridad sigue en pie (anclas que la version anterior tenia
--     y esta habia perdido: lo levanto el auditor).
-- ---------------------------------------------------------------------------
do $postflight$
declare v jsonb;
begin
  select crm.alarma_conversion_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date) into v;
  if (v ->> 'cuadra') is distinct from 'true' then
    raise exception 'POSTFLIGHT: la alarma quedo en % (era true antes)', coalesce(v->>'cuadra','null');
  end if;
  if (v ->> 'caminos_leidos')::int <> 4 then
    raise exception 'POSTFLIGHT: caminos_leidos = % (sus consumidores exigen 4)', v->>'caminos_leidos';
  end if;
  if v -> 'conciliacion' is null then
    raise exception 'POSTFLIGHT: la alarma no publica la conciliacion';
  end if;
  if (v -> 'conciliacion' ->> 'bruto_numerador')::numeric
     - (v -> 'conciliacion' ->> 'neto_numerador')::numeric
     is distinct from (v -> 'conciliacion' ->> 'deuda_aplicada')::numeric then
    raise exception 'POSTFLIGHT: la conciliacion no cuadra consigo misma: %', v->'conciliacion';
  end if;
  if v -> 'detalle' -> 'nucleo_directo' is null then
    raise exception 'POSTFLIGHT: falta nucleo_directo en el detalle (gate-realidad lo lee)';
  end if;

  -- El contrato de seguridad, intacto. `create or replace` conserva dueno y ACL,
  -- pero eso se COMPRUEBA, no se da por sabido.
  if not exists (select 1 from pg_proc p
                  where p.oid = 'crm.alarma_conversion_fn(date)'::regprocedure
                    and p.proowner = 'postgres'::regrole
                    and p.prosecdef
                    and exists (select 1 from unnest(p.proconfig) c where c ~ '^search_path=(""|)$')) then
    raise exception 'POSTFLIGHT: la alarma perdio dueno postgres, security definer o el search_path vacio';
  end if;
  if exists (select 1 from pg_proc p
             cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid = 'crm.alarma_conversion_fn(date)'::regprocedure
                and a.grantee::regrole::text in ('anon','authenticated')) then
    raise exception 'POSTFLIGHT: la alarma quedo ejecutable por anon o authenticated';
  end if;
  if not exists (select 1 from pg_proc p
                 cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  where p.oid = 'crm.alarma_conversion_fn(date)'::regprocedure
                    and a.grantee::regrole::text = 'service_role' and a.privilege_type = 'EXECUTE') then
    raise exception 'POSTFLIGHT: service_role perdio el EXECUTE; sus consumidores dejarian de leerla';
  end if;
end;
$postflight$;

select 'alarma-concilia-bruto-neto' as migracion,
       crm.alarma_conversion_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date) as veredicto;

commit;
