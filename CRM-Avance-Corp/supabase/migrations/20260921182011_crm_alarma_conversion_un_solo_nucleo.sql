-- Alarma de UN SOLO NUCLEO para la conversion (Miguel, 21/09/2026).
--
-- Problema: cuatro caminos calculan la conversion del mes vigente —el nucleo
-- directo (private.conversion_episodios), la lectura mensual
-- (crm.conversion_mensual_fn), el rango de ese mes (crm.metricas_conversiones_fn)
-- y la distribucion (crm.metricas_distribucion_leads_v3_fn)— y lo unico que se
-- comprobaba antes de pintar el porcentaje era una sonda que compara el nucleo
-- consigo mismo (`cuadra=true` siempre). Hoy coinciden por casualidad: no hay
-- ningun mes sellado ni deuda que viaje. El dia que dejen de coincidir, nadie
-- avisaria.
--
-- Que hace: crm.alarma_conversion_fn(p_mes) lee los cuatro caminos y devuelve
-- {cuadra, caminos_leidos, detalle}. Es la version permanente de
-- supabase/scripts/conversion/alarma.sql, para que gate-realidad.mjs la corra
-- sola contra la base con la clave de servicio.
--
-- JUSTIFICACION DEL SECURITY DEFINER Y DE LA IMPERSONACION (regla del proyecto:
-- definer solo con justificacion escrita). Las cuatro RPC exigen un usuario de
-- gerencia (auth.uid()). El gate de realidad no tiene usuario: habla con la
-- clave de servicio. Por eso esta funcion (1) SOLO puede ejecutarla el rol
-- service_role —o una sesion de operador sin claims JWT, como `db query`—,
-- nunca authenticated ni anon; (2) fija dentro de su propia transaccion los
-- claims de un perfil de gerencia activo, solo para que las RPC pasen su gate;
-- (3) devuelve UNICAMENTE agregados (divisor, numerador, porcentaje por
-- camino): ni identificadores ni PII; y (4) no escribe nada. La impersonacion
-- es transaccional (set_config ..., true): en una llamada por PostgREST muere
-- con la peticion. Es exactamente el patron que ya usan a mano las sondas de
-- produccion (supabase/scripts/sonda-paridad-conversion-prod.sql, y la version
-- de una sola sentencia supabase/scripts/conversion/alarma.sql).
--
-- Plan: «Una sola definicion de conversion», fase F3 (vault, 21/09/2026).
-- Mutante: supabase/scripts/conversion/mutante-alarma.sql (solo en branch)
-- demuestra que la alarma se pone en rojo ante una discrepancia inyectada.
-- Reversa: drop function crm.alarma_conversion_fn(date).
-- Requiere aprobacion expresa antes de instalar en produccion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;

do $preflight$
begin
  if to_regprocedure('crm.alarma_conversion_fn(date)') is not null then
    raise exception 'PREFLIGHT F3: crm.alarma_conversion_fn ya existe; no reinstalar sin revisar';
  end if;
  if to_regprocedure('crm.conversion_mensual_fn(date)') is null
     or to_regprocedure('crm.metricas_conversiones_fn(date,date,text)') is null
     or to_regprocedure('crm.metricas_distribucion_leads_v3_fn(date,date)') is null
     or to_regprocedure('private.conversion_episodios(timestamptz,timestamptz,date,boolean,uuid[],numeric)') is null then
    raise exception 'PREFLIGHT F3: falta alguno de los cuatro caminos que la alarma compara';
  end if;
end;
$preflight$;

create or replace function crm.alarma_conversion_fn(p_mes date default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $function$
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
    ), caminos as (
      select 'nucleo_directo' as camino, * from nucleo
      union all select 'mensual', * from mensual
      union all select 'rango', * from rango
      union all select 'distribucion', * from distribucion
    )
    select jsonb_build_object(
      'mes', v_mes, 'hasta', v_hasta,
      -- `coalesce(pct, -1)`: count(distinct) ignora los NULL, asi que cuatro
      -- caminos con pct NULL (mes vacio) contarian 0 y no 1.
      'cuadra', count(distinct divisor) = 1 and count(distinct numerador) = 1
                and count(distinct coalesce(pct, -1)) = 1
                and count(*) filter (where divisor is null or numerador is null) = 0,
      'motivo', case when max(divisor) = 0 then 'sin_datos' end,
      'caminos_leidos', count(*),
      'detalle', jsonb_object_agg(camino, jsonb_build_object('divisor', divisor, 'numerador', numerador, 'pct', pct)))
    into v_resultado
    from caminos;
  exception when others then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  return v_resultado;
end;
$function$;

comment on function crm.alarma_conversion_fn(date) is
  'Alarma de un solo nucleo: compara divisor, numerador y porcentaje de la conversion del mes por cuatro caminos distintos (nucleo directo, mensual, rango, distribucion) y devuelve {cuadra, caminos_leidos, detalle}. Solo service_role u operador sin claims; impersona gerencia de forma transaccional para que las RPC pasen su gate; devuelve solo agregados. La corre gate-realidad.mjs.';

revoke all on function crm.alarma_conversion_fn(date)
  from public, anon, authenticated, service_role;
grant execute on function crm.alarma_conversion_fn(date) to service_role;

do $postflight$
declare
  v_secdef boolean;
  v_config text[];
  v_owner text;
  v_r jsonb;
begin
  select p.prosecdef, p.proconfig, r.rolname into v_secdef, v_config, v_owner
  from pg_catalog.pg_proc p join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.alarma_conversion_fn(date)'::regprocedure;
  if v_owner is distinct from 'postgres' or not v_secdef
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT F3: owner/secdef/search_path inesperados';
  end if;
  if pg_catalog.has_function_privilege('authenticated', 'crm.alarma_conversion_fn(date)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.alarma_conversion_fn(date)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('service_role', 'crm.alarma_conversion_fn(date)', 'EXECUTE') then
    raise exception 'POSTFLIGHT F3: la alarma debe ser ejecutable SOLO por service_role';
  end if;
  -- Humo real: como operador sin claims, la alarma lee los cuatro caminos.
  v_r := crm.alarma_conversion_fn();
  if v_r ->> 'motivo' = 'sin_perfil_de_gerencia_activo' then
    -- Un branch sin sembrar no tiene gerencia. Las anclas de owner/secdef/ACL de
    -- arriba siguen bloqueando, y el humo real con fixture lo hace test-rls.mjs.
    raise notice 'POSTFLIGHT F3: sin perfil de gerencia activo; quedan las anclas estructurales';
  elsif (v_r ->> 'caminos_leidos')::int is distinct from 4 then
    raise exception 'POSTFLIGHT F3: la alarma no leyo los cuatro caminos: %', v_r;
  else
    raise notice 'POSTFLIGHT F3: alarma % · cuadra=% · %', v_r ->> 'mes', v_r ->> 'cuadra', v_r -> 'detalle';
  end if;
end;
$postflight$;

commit;
