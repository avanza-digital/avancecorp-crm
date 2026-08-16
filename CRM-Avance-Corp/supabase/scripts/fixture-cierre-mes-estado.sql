-- ---------------------------------------------------------------------------
-- Generador de fixtures: el payload REAL de `crm.cierre_mes_estado_fn`
-- ---------------------------------------------------------------------------
-- Escupe los CINCO payloads que el aviso del ciclo puede recibir, ejecutando la
-- funcion de verdad. Alimentan a `app/src/lib/cierre-de-mes.test.ts`.
--
-- Los cinco: `quieto` (nada pendiente, nada sellado — el estado de produccion
-- el dia del estreno), `atascado`, `en_ventana`, `hoy` y `sellado` (con
-- `ultimo_cerrado`). Leer la migracion no basta para enumerar claves y ramas:
-- asi se escaparon 2 de las 4 claves del apagon de metas del 2026-08-15.
--
-- ⏰ LA COSTURA DEL RELOJ. `en_ventana` y `hoy` solo existen del 1 al 10 del
-- mes: con el reloj real, un generador corrido cualquier otro dia no puede
-- ejecutarlas. La costura toma la fuente REAL con `pg_get_functiondef`, cambia
-- UNA linea (v_ahora deja de leer `now()` y lee `test.ahora` si esta puesto) y
-- la instala bajo OTRO nombre. La copia se construye a maquina desde la fuente
-- viva —no hay segundo cuerpo que pueda desviarse— y un control de fidelidad
-- exige que, sin reloj falso, real y copia devuelvan lo MISMO. Los fixtures
-- `quieto`, `atascado` y `sellado` salen de la funcion REAL, sin costura.
--
-- USO:
--   dropdb --if-exists estado_fixture && createdb estado_fixture
--   psql -q -v ON_ERROR_STOP=1 -d estado_fixture -f supabase/scripts/banco-local-cierre-mes.sql
--   # aplicar las 20260815* SIN sus bloques `do $preflight$` (anclan md5 de PROD)
--   psql -q -v ON_ERROR_STOP=1 -d estado_fixture \
--     -v quieto=/tmp/estado-quieto.json -v atascado=/tmp/estado-atascado.json \
--     -v en_ventana=/tmp/estado-en-ventana.json -v hoy=/tmp/estado-hoy.json \
--     -v sellado=/tmp/estado-sellado.json \
--     -f supabase/scripts/fixture-cierre-mes-estado.sql
--
-- ⛔ NUNCA contra producción ni una branch: SOLO la base desechable del banco.
-- El guard de la primera línea lo hace cumplir — detecta el banco por su
-- SEMÁNTICA (su auth.uid() lee test.uid), no por el nombre de la base.
--
-- Termina en ROLLBACK: no deja nada sembrado (la copia con costura tampoco:
-- el CREATE FUNCTION es transaccional).
--
-- El mes con metas es SIEMPRE «hace 2 meses»: su ventana (dia 10 del mes
-- siguiente) ya paso corras cuando corras, asi que `atascado` sale del reloj
-- real todo el año. Nada de fechas fijas: los fixtures con fecha fija caducan
-- por calendario (una suite entera murio exactamente el dia 45 de su ventana).
--
-- Se impersona al DIRECTORIO (lector global), como en el generador hermano.
-- El payload no varia por rol (no filtra nada); el gate si, y aqui se PRUEBA:
-- coordinador entra (es la excepcion comentada en la migracion) y un
-- desconocido recibe 42501.
-- ---------------------------------------------------------------------------
\set ON_ERROR_STOP on
begin;

-- 0) GUARD DE ENTORNO (hallazgo de la auditoría F2): hasta ahora la
--    no-ejecución contra prod era un accidente feliz (el 42501 de rebote).
--    Ahora es un diseño: si auth.uid() no responde al GUC del banco, se aborta
--    aquí, antes de la costura y de cualquier siembra.
select set_config('test.uid', '00000000-0000-4000-8000-00000000c0da', true);
do $guard$ begin
  if (select auth.uid()) is distinct from '00000000-0000-4000-8000-00000000c0da'::uuid then
    raise exception 'auth.uid() no responde a test.uid: esto NO es el banco local. Abortando antes de tocar nada.';
  end if;
end $guard$;
select set_config('test.uid', '', true);

-- 1) La costura del reloj, a maquina desde la fuente viva.
do $costura$
declare
  v_def   text;
  v_ancla constant text := 'v_ahora      timestamptz := now();';
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'cierre_mes_estado_fn';
  if v_def is null then
    raise exception 'no existe crm.cierre_mes_estado_fn: aplica antes las migraciones 20260815*';
  end if;
  -- strpos, no LIKE: el guion bajo de snake_case es comodin en LIKE.
  if strpos(v_def, v_ancla) = 0 then
    raise exception 'la fuente ya no tiene el punto de costura (%). Revisar la migracion nueva antes de regenerar.', v_ancla;
  end if;
  v_def := replace(v_def, 'crm.cierre_mes_estado_fn()', 'crm.cierre_mes_estado_reloj_falso()');
  v_def := replace(v_def, v_ancla,
    'v_ahora      timestamptz := coalesce(nullif(current_setting(''test.ahora'', true), '''')::timestamptz, now());');
  execute v_def;
end $costura$;

-- 2) Perfiles minimos. Sin metas todavia: el primer volcado es el mundo VACIO.
do $siembra$
begin
  insert into public.perfiles (id, nombre_completo, rol, activo) values
    ('99999999-9999-4999-8999-999999999999', 'DIRECTORIO DE PRUEBA',  'admin',       true),
    ('88888888-8888-4888-8888-888888888888', 'COORDINADOR DE PRUEBA', 'coordinador', true),
    ('22222222-2222-4222-8222-222222222222', 'SUPERVISOR DE PRUEBA',  'comercial',   true),
    ('33333333-3333-4333-8333-333333333333', 'VENDEDOR DE PRUEBA',    'comercial',   true);
end $siembra$;

select set_config('test.uid', '99999999-9999-4999-8999-999999999999', true);
\pset tuples_only on
\pset format unaligned

-- 3) QUIETO: ni pendiente ni sellado. Exactamente lo que producira produccion
--    el dia que este front se estrene (solo agosto tiene metas y agosto corre).
\o :quieto
select jsonb_pretty(crm.cierre_mes_estado_fn());
\o

-- 4) Metas para «hace 2 meses» → ese mes debe un cierre y su ventana ya paso.
do $metas$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
begin
  insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
  values (v_mes, 0.150, 'fixture estado') on conflict do nothing;
  insert into crm.meta_periodos (id, periodo, revision, publicada_en)
  values ('55555555-5555-4555-8555-555555555550', v_mes, 1, now());
  insert into crm.metas_vendedor (id, meta_periodo_id, vendedor_id, supervisor_id, conversion_objetivo)
  values ('66666666-6666-4666-8666-666666666660', '55555555-5555-4555-8555-555555555550',
          '33333333-3333-4333-8333-333333333333', '22222222-2222-4222-8222-222222222222', 15);
  -- Las SEIS dimensiones, como exige el front y como las tiene produccion.
  insert into crm.metas_vendedor_detalle (meta_vendedor_id, categoria, moneda, capital_objetivo, contratos_objetivo)
  select '66666666-6666-4666-8666-666666666660', c, m,
         case when c = 'nuevo' and m = 'PEN' then 100000 else 0 end,
         case when c = 'nuevo' and m = 'PEN' then 5 else 0 end
  from (values ('nuevo'), ('renovacion'), ('upgrade')) as cat(c)
  cross join (values ('PEN'), ('USD')) as mon(m);
end $metas$;

-- 5) ATASCADO, de la funcion REAL con el reloj real: la ventana del mes
--    sembrado abrio hace mas de un dia y nadie lo sello.
\o :atascado
select jsonb_pretty(crm.cierre_mes_estado_fn());
\o

-- 6) Control de fidelidad de la costura: sin reloj falso, la copia dice
--    EXACTAMENTE lo que la funcion real (misma transaccion → mismo now()).
do $fidelidad$
begin
  if crm.cierre_mes_estado_fn() is distinct from crm.cierre_mes_estado_reloj_falso() then
    raise exception 'la copia con costura no es fiel a la funcion real';
  end if;
end $fidelidad$;

-- 7) El gate, probado en las dos direcciones: coordinador ENTRA (la excepcion
--    documentada en la migracion) y un uuid sin rol recibe 42501.
do $gate$
declare v_r jsonb;
begin
  perform set_config('test.uid', '88888888-8888-4888-8888-888888888888', true);
  v_r := crm.cierre_mes_estado_fn();
  if v_r->'pendiente'->>'estado' is distinct from 'atascado' then
    raise exception 'el coordinador tendria que ver el mismo estado: %', v_r;
  end if;
  perform set_config('test.uid', '44444444-4444-4444-8444-444444444444', true);
  begin
    perform crm.cierre_mes_estado_fn();
    raise exception 'un uuid sin rol CRM tendria que recibir 42501';
  exception when insufficient_privilege then null;
  end;
  perform set_config('test.uid', '99999999-9999-4999-8999-999999999999', true);
end $gate$;

-- 8) EN VENTANA y HOY, de la copia con costura. Dias relativos al mes sembrado:
--    el 5 del mes siguiente a mediodia (quedan 5 dias) y el propio dia 10 a las
--    09:20 de Lima, la hora real del cron, antes de que el ciclo pase.
select set_config('test.ahora',
  (((date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date
    + interval '1 month' + interval '4 days' + interval '12 hours')::timestamp
   at time zone 'America/Lima')::text, true);
\o :en_ventana
select jsonb_pretty(crm.cierre_mes_estado_reloj_falso());
\o

select set_config('test.ahora',
  (((date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date
    + interval '1 month' + interval '9 days' + interval '9 hours 20 minutes')::timestamp
   at time zone 'America/Lima')::text, true);
\o :hoy
select jsonb_pretty(crm.cierre_mes_estado_reloj_falso());
\o
select set_config('test.ahora', '', true);

-- 9) SELLADO: se cierra el mes (sin uid = automatico, como lo hara el cron) y
--    el aviso pasa a «nada pendiente + ultimo_cerrado».
do $sello$
declare
  v_mes date := (date_trunc('month', now() at time zone 'America/Lima') - interval '2 months')::date;
  v_r jsonb;
begin
  perform set_config('test.uid', '', true);
  v_r := crm.cerrar_periodo(v_mes);
  if (v_r->>'ok')::boolean is not true then
    raise exception 'la siembra no pudo sellar el mes: %', v_r;
  end if;
  perform set_config('test.uid', '99999999-9999-4999-8999-999999999999', true);
end $sello$;

\o :sellado
select jsonb_pretty(crm.cierre_mes_estado_fn());
\o

rollback;
