-- FRAGMENTO (sin transacción propia): RENDIMIENTO de la llamada típica del Pipeline
-- (`p_etapa = 'nuevo'`, página de 200) sobre los datos de `volumen.sql`, para un analista y
-- para gerencia, con cuatro variantes en la MISMA sesión y sobre los MISMOS datos:
--   vieja (12 argumentos) · nueva sin filtro · nueva con_gestion · nueva sin_gestion.
-- Lo compone `ensayar.mjs` como `supabase_admin` (auto_explain exige superusuario; la función
-- se llama igualmente como `authenticated`, bajo RLS).
--   1) Tiempos: 21 rondas; la primera calienta y no cuenta. En cada ronda el orden de las
--      variantes rota, para que ninguna se beneficie siempre de la caché de la anterior. Se
--      reporta la mediana y, ronda a ronda, la diferencia «nueva sin filtro − vieja».
--   2) Planes: auto_explain (analyze + buffers) de la sentencia interna de la función, que
--      llega por stderr tras cada `MARCA`. Sirve para ver QUÉ índice usa el `exists` del filtro;
--      sus tiempos llevan la sobrecarga de la instrumentación y no se usan como medida.
set local session_replication_role = origin;
set local statement_timeout = 0;
create temporary table muestras (actor integer, variante text, ronda integer, ms numeric, vivos integer) on commit drop;
grant select, insert on muestras to authenticated;
do $guarda$
begin
  if (
    has_function_privilege('authenticated', 'pg_temp.cartera_filtrada_anterior(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.vactor(integer)', 'EXECUTE')
  ) is not true then
    raise exception 'RENDIMIENTO: falta EXECUTE para authenticated; no se llama a ciegas';
  end if;
end;
$guarda$;

set local role authenticated;
do $tiempos$
declare
  actores constant integer[] := array[101, 1];
  nombres constant text[] := array['vieja', 'nueva_sin_filtro', 'nueva_con_gestion', 'nueva_sin_gestion'];
  consultas constant text[] := array[
    $q$select pg_temp.cartera_filtrada_anterior(p_limite => 200, p_etapa => 'nuevo')$q$,
    $q$select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo')$q$,
    $q$select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion')$q$,
    $q$select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion')$q$];
  a integer; i integer; j integer; ronda integer; t0 timestamptz; r jsonb;
begin
  foreach a in array actores loop
    perform set_config('request.jwt.claim.sub', pg_temp.vactor(a)::text, true),
            set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(a), 'role', 'authenticated')::text, true);
    for ronda in 0..20 loop
      for j in 0..3 loop
        i := 1 + (j + ronda) % 4;
        t0 := clock_timestamp();
        execute consultas[i] into r;
        insert into pg_temp.muestras values (a, nombres[i], ronda,
          extract(epoch from clock_timestamp() - t0) * 1000, (r #>> '{resumen,totales,vivos}')::integer);
      end loop;
    end loop;
  end loop;
end;
$tiempos$;
reset role;
select 'TIEMPOS ' || jsonb_agg(to_jsonb(x) order by x.actor desc, x.orden)::text
from (
  select m.actor, case m.actor when 1 then 'gerencia' else 'analista' end as rol, m.variante,
    array_position(array['vieja', 'nueva_sin_filtro', 'nueva_con_gestion', 'nueva_sin_gestion'], m.variante) as orden,
    round((percentile_cont(0.5) within group (order by m.ms))::numeric, 2) as mediana_ms,
    round(min(m.ms), 2) as min_ms, round(max(m.ms), 2) as max_ms, count(*) as pasadas, max(m.vivos) as leads_en_la_base
  from pg_temp.muestras m where m.ronda > 0 group by m.actor, m.variante
) x;
-- Antes/después de verdad: misma ronda, mismos datos, misma sesión.
select 'PAREADA ' || jsonb_agg(to_jsonb(y) order by y.actor desc)::text
from (
  select n.actor, case n.actor when 1 then 'gerencia' else 'analista' end as rol,
    round((percentile_cont(0.5) within group (order by n.ms - v.ms))::numeric, 2) as mediana_nueva_sin_filtro_menos_vieja_ms,
    count(*) as rondas
  from pg_temp.muestras n
  join pg_temp.muestras v on v.actor = n.actor and v.ronda = n.ronda and v.variante = 'vieja'
  where n.variante = 'nueva_sin_filtro' and n.ronda > 0
  group by n.actor
) y;

-- Las cuatro primeras rondas medidas, aparte: ahí las dos funciones se planifican en cada
-- llamada (plan a medida). Después Postgres puede pasar la VIEJA a un plan genérico guardado
-- (sin coste de planificar, con peor plan) y dejar la NUEVA a medida, porque su plan genérico
-- carga con el `exists` del filtro. La mediana de arriba mezcla ya ese efecto.
select 'PRIMERAS ' || jsonb_agg(to_jsonb(z) order by z.actor desc, z.variante desc)::text
from (
  select m.actor, case m.actor when 1 then 'gerencia' else 'analista' end as rol, m.variante,
    round((percentile_cont(0.5) within group (order by m.ms))::numeric, 2) as mediana_ms, count(*) as pasadas
  from pg_temp.muestras m
  where m.ronda between 1 and 4 and m.variante in ('vieja', 'nueva_sin_filtro')
  group by m.actor, m.variante
) z;

-- Planes. Los ajustes de auto_explain son de superusuario: se fijan ANTES de cambiar de rol.
load 'auto_explain';
set local auto_explain.log_min_duration = 0;
set local auto_explain.log_analyze = on;
set local auto_explain.log_buffers = on;
set local auto_explain.log_timing = on;
set local auto_explain.log_nested_statements = on;
set local auto_explain.log_format = 'text';
set local client_min_messages = log;
set local role authenticated;
select set_config('request.jwt.claim.sub', pg_temp.vactor(101)::text, true),
       set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(101), 'role', 'authenticated')::text, true);
do $m$ begin raise log 'MARCA analista vieja'; end $m$;
select pg_temp.cartera_filtrada_anterior(p_limite => 200, p_etapa => 'nuevo') is not null;
do $m$ begin raise log 'MARCA analista nueva_sin_filtro'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo') is not null;
do $m$ begin raise log 'MARCA analista nueva_con_gestion'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') is not null;
do $m$ begin raise log 'MARCA analista nueva_sin_gestion'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') is not null;
select set_config('request.jwt.claim.sub', pg_temp.vactor(1)::text, true),
       set_config('request.jwt.claims', json_build_object('sub', pg_temp.vactor(1), 'role', 'authenticated')::text, true);
do $m$ begin raise log 'MARCA gerencia vieja'; end $m$;
select pg_temp.cartera_filtrada_anterior(p_limite => 200, p_etapa => 'nuevo') is not null;
do $m$ begin raise log 'MARCA gerencia nueva_sin_filtro'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo') is not null;
do $m$ begin raise log 'MARCA gerencia nueva_con_gestion'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') is not null;
do $m$ begin raise log 'MARCA gerencia nueva_sin_gestion'; end $m$;
select crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') is not null;
do $m$ begin raise log 'MARCA fin'; end $m$;
reset role;
set local client_min_messages = notice;
set local auto_explain.log_min_duration = -1;
