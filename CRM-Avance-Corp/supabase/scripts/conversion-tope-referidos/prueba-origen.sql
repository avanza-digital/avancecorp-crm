-- Prueba de la FASE B del tope de referidos (migración 20261007203000). Banco con la Fase A y la B aplicadas, como postgres:
--   psql -v ON_ERROR_STOP=1 -qAt -f prueba-origen.sql        (sintética: todo se deshace)
-- Mundo: mundo-fase-b.sql. Octubre lleva tope 15 % de los cierres de leads asignados: A 15 asignados y 5 referidos ⇒ cuentan 3;
-- B 4 asignados y 2 referidos ⇒ cuenta 1. Septiembre NO lleva tope (A: 10 asignados y 3 referidos; B: 5 asignados y 1 referido).
begin;
\i mundo-fase-b.sql
\i anterior-origen.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);

-- ── O1 · «Resultados por origen»: el referido muestra cuántos CERRARON y cuánto APORTAN, y su porcentaje usa el aporte ─────────────
select pg_temp.exigir((select r.cierres = 5 and r.aporte = 3 and r.conversion_pct = 60.00
    from private.ranking_conversion_origen_mes('2026-10-01'::timestamptz at time zone 'America/Lima', '2026-11-01'::timestamptz at time zone 'America/Lima',
      '2026-10-01', 1) r where r.vendedor_id = (select a from ana) and r.origen = 'referido'),
  'O1a: A en octubre: referido con 5 cierres, aporte 3 y 60,00 % (3 de 5 llegadas)');
select pg_temp.exigir((select r.aporte = 10 and r.cierres = 10 from private.ranking_conversion_origen_mes('2026-10-01'::timestamptz at time zone 'America/Lima',
      '2026-11-01'::timestamptz at time zone 'America/Lima', '2026-10-01', 1) r where r.vendedor_id = (select a from ana) and r.origen = 'landing'),
  'O1b: los demás orígenes aportan 1 por cierre (landing: 10 cierres, aporte 10)');
select pg_temp.exigir((select r.cierres = 2 and r.aporte = 1 and r.conversion_pct = round(100.0 * 1 / 5, 2)
    from private.ranking_conversion_origen_mes('2026-10-01'::timestamptz at time zone 'America/Lima', '2026-11-01'::timestamptz at time zone 'America/Lima',
      '2026-10-01', 1) r where r.vendedor_id = (select b from ana) and r.origen = 'referido'),
  'O1c: B en octubre: 2 referidos cerrados, cuenta 1 (tope ceil(0,9) = 1) sobre 5 llegadas (2 que cerraron + 3 que no)');

-- ── O2 · septiembre NO cambia: idéntico a la función anterior, y los otros orígenes de octubre también ─────────────────────────────
select pg_temp.exigir(not exists (
  (select v.vendedor_id, v.origen, v.leads, v.cierres, v.conversion_pct
     from private.ranking_conversion_origen_mes('2026-09-01'::timestamptz at time zone 'America/Lima', '2026-10-01'::timestamptz at time zone 'America/Lima', '2026-09-01', 0.15) v
   except select o.* from pg_temp.ranking_conversion_origen_mes_anterior('2026-09-01'::timestamptz at time zone 'America/Lima', '2026-10-01'::timestamptz at time zone 'America/Lima', '2026-09-01', 0.15) o)
  union all
  (select o.* from pg_temp.ranking_conversion_origen_mes_anterior('2026-09-01'::timestamptz at time zone 'America/Lima', '2026-10-01'::timestamptz at time zone 'America/Lima', '2026-09-01', 0.15) o
   except select v.vendedor_id, v.origen, v.leads, v.cierres, v.conversion_pct
     from private.ranking_conversion_origen_mes('2026-09-01'::timestamptz at time zone 'America/Lima', '2026-10-01'::timestamptz at time zone 'America/Lima', '2026-09-01', 0.15) v)),
  'O2a: septiembre da EXACTAMENTE lo mismo que la función anterior (mismas filas y mismos porcentajes)');
select pg_temp.exigir((select count(*) from private.ranking_conversion_origen_mes('2026-09-01'::timestamptz at time zone 'America/Lima', '2026-10-01'::timestamptz at time zone 'America/Lima', '2026-09-01', 0.15) r
    where r.origen = 'referido' and r.aporte = r.cierres * 0.15) = 2, 'O2b: en septiembre el aporte del referido es p_factor × cierres (0,15 × cierres)');
select pg_temp.exigir(not exists (
  select 1 from private.ranking_conversion_origen_mes('2026-10-01'::timestamptz at time zone 'America/Lima', '2026-11-01'::timestamptz at time zone 'America/Lima', '2026-10-01', 1) n
  full join pg_temp.ranking_conversion_origen_mes_anterior('2026-10-01'::timestamptz at time zone 'America/Lima', '2026-11-01'::timestamptz at time zone 'America/Lima', '2026-10-01', 1) v
    on v.vendedor_id = n.vendedor_id and v.origen = n.origen
  where coalesce(n.origen, v.origen) <> 'referido'
    and (n.leads is distinct from v.leads or n.cierres is distinct from v.cierres or n.conversion_pct is distinct from v.conversion_pct)),
  'O2c: en octubre los orígenes que no son referido no cambian');

-- ── O3 · la foto en vivo guarda el aporte de cada fila de origen ─────────────────────────────────────────────────────────────────
select pg_temp.exigir((select (select x ->> 'aporte' from jsonb_array_elements(j -> 'filas') x where x ->> 'origen' = 'referido')::numeric = 3
       and (select x ->> 'cierres' from jsonb_array_elements(j -> 'filas') x where x ->> 'origen' = 'referido')::int = 5
       and (select bool_and(x ? 'aporte') from jsonb_array_elements(j -> 'filas') x)
    from (select private.ranking_origen_live('2026-10-01', (select a from ana), '[]'::jsonb) j) q),
  'O3: ranking_origen_live: el referido de A guarda cierres 5 y aporte 3, y TODAS las filas traen `aporte`');

-- ── O4 · la cifra oficial del mes (puerta): «aporta» sale del aporte real y el tope se declara ──────────────────────────────────
create temp table pq as select crm.conversion_mensual_sin_cartera_fn('2026-10-01') j_oct, crm.conversion_mensual_sin_cartera_fn('2026-09-01') j_sep;
select pg_temp.exigir((select (j_oct #>> '{ponderacion,tope_referidos_pct}')::numeric = 15 and (j_oct #>> '{ponderacion,referido}')::numeric = 1 from pq),
  'O4a: octubre declara peso 1 y tope 15');
select pg_temp.exigir((select (j_oct #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 4 / 110, 2) from pq),
  'O4b: total.referidos_aporta_pct de octubre = 100 × 4 referidos que cuentan / 110 de divisor = 3,64; salió ' || (select j_oct #>> '{total,referidos_aporta_pct}' from pq));
select pg_temp.exigir((select (r #>> '{referidos,aporta_pct}')::numeric = round(100.0 * 3 / 80, 2) from pq, jsonb_array_elements(j_oct -> 'responsables') r
                        where (r ->> 'vendedor_id')::uuid = (select a from ana)), 'O4c: A aporta 100 × 3 / 80 = 3,75');
select pg_temp.exigir((select (r #>> '{referidos,aporta_pct}')::numeric = round(100.0 * 1 / 30, 2) from pq, jsonb_array_elements(j_oct -> 'responsables') r
                        where (r ->> 'vendedor_id')::uuid = (select b from ana)), 'O4d: B aporta 100 × 1 / 30 = 3,33');
-- La defensa del front: con tope, «aporta» nunca supera peso × cierres_referidos / divisor, ni en el total ni por responsable.
select pg_temp.exigir((select (j_oct #>> '{total,referidos_aporta_pct}')::numeric <= 100 * (j_oct #>> '{ponderacion,referido}')::numeric * (j_oct #>> '{total,cierres_referidos}')::numeric / (j_oct #>> '{total,divisor}')::numeric + 0.005
       and (select bool_and((r #>> '{referidos,aporta_pct}')::numeric <= 100 * (j_oct #>> '{ponderacion,referido}')::numeric * (r ->> 'cierres_referidos')::numeric / (r ->> 'divisor')::numeric + 0.005)
              from jsonb_array_elements(j_oct -> 'responsables') r) from pq),
  'O4e: con tope, el aporte publicado nunca supera peso × referidos / divisor (la cota que valida el front)');
select pg_temp.exigir((select j_sep #>> '{ponderacion,tope_referidos_pct}' is null
       and (j_sep #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 0.15 * (j_sep #>> '{total,cierres_referidos}')::numeric / (j_sep #>> '{total,divisor}')::numeric, 2) from pq),
  'O4f: septiembre sin tope: la fórmula de siempre (100 × 0,15 × cierres_referidos / divisor), sin la clave del tope');

-- ── O5 · Coordinación en vivo ya sumaba el aporte del núcleo: se comprueba que sigue así y que el tope se declara ──────────────────
select pg_temp.exigir((select t.cierres_referido = 7 and t.cierres_referido_aporte = 4 from private.conversion_divisor_empresa_totales('2026-10-01', '2026-10-31') t),
  'O5a: octubre: 7 referidos cerraron y aportan 4');
select pg_temp.exigir((crm.conversion_divisor_coordinacion_fn('2026-10-01') ->> 'tope_referidos_pct')::numeric = 15
   and (crm.conversion_divisor_coordinacion_fn('2026-09-01') -> 'tope_referidos_pct') = 'null'::jsonb,
  'O5b: la puerta de Coordinación declara el tope de octubre (15) y null en septiembre');

-- ── O6 · «Conversión ponderada» de la cohorte: el referido usa el aporte del núcleo con tope, y 0,15 × contratos sin tope ─────────
select pg_temp.exigir((select (o ->> 'conversion_ponderada_pct')::numeric = round(100.0 * 4 / (o ->> 'leads')::numeric, 1)
    from jsonb_array_elements(private.metricas_conversiones_implementacion('2026-10-01', least('2026-10-31'::date, (now() at time zone 'America/Lima')::date), null) -> 'origenes') o
    where o ->> 'origen' = 'referido'), 'O6a: octubre: cohorte referido = 4 cierres que cuentan sobre sus llegadas');
select pg_temp.exigir((select (o ->> 'conversion_ponderada_pct')::numeric = round(100.0 * (o ->> 'contratos')::numeric * 0.15 / (o ->> 'leads')::numeric, 1)
    from jsonb_array_elements(private.metricas_conversiones_implementacion('2026-09-01', '2026-09-30', null) -> 'origenes') o
    where o ->> 'origen' = 'referido'), 'O6b: septiembre sin tope: contratos × 0,15 / llegadas, como siempre');
select pg_temp.exigir((private.metricas_conversiones_implementacion('2026-10-01', least('2026-10-31'::date, (now() at time zone 'America/Lima')::date), null) #>> '{nucleo,tope_referidos_pct}')::numeric = 15
   and (private.metricas_conversiones_implementacion('2026-09-01', '2026-09-30', null) #> '{nucleo,tope_referidos_pct}') = 'null'::jsonb,
  'O6c: el paquete declara el tope en `nucleo`, junto a `peso_referido`');
rollback;

-- ═══════ PRODUCCIÓN FUERA DEL ROSTER: quien cerró pero ya no figura entre los vendedores suma al total con su aporte real ═══════
begin;
\i mundo-fase-b.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);
-- C (sin fila en crm.equipo): 4 landing + 2 referidos en octubre ⇒ base 4, tope ceil(0,6) = 1 ⇒ cuenta 1 referido.
do $$ declare c uuid := 'c0000000-0000-4000-8000-00000000000c'; i int; begin
  for i in 1..4 loop perform pg_temp.cierre(c, 'landing', '2026-10-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(c, 'referido', '2026-10-01', 1 + i); end loop;
end $$;
-- D (SÍ en el roster, con supervisor): solo referidos ⇒ divisor 0 y porcentaje NULL; sin cierres asignados su base es 0 y su tope es 0, así que ningún referido suyo aporta.
do $$ declare d uuid := 'f0000000-0000-4000-8000-00000000000f'; i int; begin
  insert into public.perfiles (id, nombre_completo) values (d, 'Analista D');
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id) select d, 'vendedor', s from ana;
  for i in 1..2 loop perform pg_temp.cierre(d, 'referido', '2026-10-01', 1 + i); end loop;
end $$;
create temp table pc as select crm.conversion_mensual_sin_cartera_fn('2026-10-01') j;
select pg_temp.exigir((select (j #>> '{cobertura,fuera_de_roster,divisor}')::int = 4 and (j #>> '{total,divisor}')::int = 114 and (j #>> '{total,cierres_referidos}')::int = 11 from pc),
  'O7a: C queda fuera del roster (divisor 4), D no suma divisor, y el total lo suma todo (114 de divisor, 11 referidos cerrados)');
select pg_temp.exigir((select (j #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 5 / 114, 2) from pc),
  'O7b: «aporta» del total incluye al fuera de roster (C) y no suma a quien solo tiene referidos (D, base 0, tope 0): 100 × (3 + 1 + 1 + 0) / 114 = 4,39; salió ' || (select j #>> '{total,referidos_aporta_pct}' from pc));
select pg_temp.exigir((select r #>> '{referidos,aporta_pct}' is null and (r ->> 'divisor')::int = 0 and (r ->> 'cierres_referidos')::int = 2
    from pc, jsonb_array_elements(j -> 'responsables') r where (r ->> 'vendedor_id')::uuid = 'f0000000-0000-4000-8000-00000000000f'),
  'O7c: D (solo referidos) sigue con porcentaje NULL por fila: el total NO depende de él');
rollback;

-- ═══════ MES SELLADO: septiembre sellado con la puerta REAL (crm.cerrar_periodo), con tope solo dentro de esta transacción ═══════
begin;
\i mundo-fase-b.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);
insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion, tope_referidos_pct, nota) values ('2026-09-01', 1.000, 0.15, 15.00, 'sintetico: septiembre con tope solo en la prueba');
create or replace function private.cierre_mes_ventana_desde(p_periodo date) returns timestamptz language sql stable set search_path = '' as $$ select '2026-01-01'::timestamptz $$;
-- C (fuera de roster: 4 landing + 2 referidos) y D (en el roster, solo 2 referidos ⇒ divisor 0, base 0 y tope 0) también producen en septiembre.
do $$ declare c uuid := 'c0000000-0000-4000-8000-00000000000c'; d uuid := 'f0000000-0000-4000-8000-00000000000f'; i int; begin
  insert into public.perfiles (id, nombre_completo) values (d, 'Analista D');
  insert into crm.equipo (perfil_id, rol_crm, supervisor_id) select d, 'vendedor', s from ana;
  for i in 1..4 loop perform pg_temp.cierre(c, 'landing', '2026-09-01', i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(c, 'referido', '2026-09-01', 1 + i); end loop;
  for i in 1..2 loop perform pg_temp.cierre(d, 'referido', '2026-09-01', 1 + i); end loop;
end $$;
-- Septiembre ABIERTO (ya con el tope de prueba): lo que debe decir también el mes sellado.
create temp table abierto as select crm.conversion_mensual_sin_cartera_fn('2026-09-01') j;
set local session_replication_role = origin;
create temp table sello_res as select crm.cerrar_periodo('2026-09-01') j;
set local session_replication_role = replica;
select pg_temp.exigir((select (j ->> 'ok')::boolean from sello_res), 'M0: el sello real de septiembre (con tope de prueba) terminó bien');
select pg_temp.exigir((select pc.tope_referidos_pct = 15 and pc.ponderacion_referido = 1 from crm.periodos_cerrados pc where pc.periodo = '2026-09-01'), 'M1: la foto guarda peso 1 y tope 15');
-- Septiembre en vivo (antes del sello) habría dado: A 3 referidos con base 10 ⇒ tope ceil(1,5) = 2; B 1 con base 5 ⇒ tope ceil(0,75) = 1.
select pg_temp.exigir((select (x ->> 'aporte')::numeric = 2 and (x ->> 'cierres')::int = 3
    from crm.cierre_mes_vendedor f, jsonb_array_elements(f.origenes_ranking -> 'filas') x
    where f.periodo = '2026-09-01' and f.vendedor_id = (select a from ana) and x ->> 'origen' = 'referido'),
  'M2: la foto de A guarda en su fila Referido cierres 3 y aporte 2');
select pg_temp.exigir((select (x ->> 'aporte')::numeric = 1 and (x ->> 'cierres')::int = 1
    from crm.cierre_mes_vendedor f, jsonb_array_elements(f.origenes_ranking -> 'filas') x
    where f.periodo = '2026-09-01' and f.vendedor_id = (select b from ana) and x ->> 'origen' = 'referido'),
  'M3: la foto de B guarda en su fila Referido cierres 1 y aporte 1');
-- La puerta sirve la foto: «aporta» = 100 × 3 / 75, y declara el tope.
create temp table gp as select crm.conversion_mensual_sin_cartera_fn('2026-09-01') j;
select pg_temp.exigir((select (j #>> '{ponderacion,tope_referidos_pct}')::numeric = 15
       and (j #>> '{total,divisor}')::int = 79
       and (j #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 4 / 79, 2) from gp),
  'M4: mes sellado: tope de la foto y «aporta» = 100 × (A 2 + B 1 + C fuera de roster 1 + D solo referidos 0) / 79 = 5,06; salió ' || (select j #>> '{total,referidos_aporta_pct}' from gp));
select pg_temp.exigir((select (a.j #>> '{total,referidos_aporta_pct}') = (g.j #>> '{total,referidos_aporta_pct}') and (a.j #>> '{total,divisor}') = (g.j #>> '{total,divisor}') from abierto a, gp g),
  'M4b: el mes abierto y su foto sellada dicen lo MISMO en «aporta» y divisor');
-- Un supervisor ve solo a su equipo (A, B y D): el total sellado suma solo a los visibles (2 + 1 + 0 = 3 sobre el divisor del equipo).
select set_config('request.jwt.claim.sub', (select s::text from ana), true);
select pg_temp.exigir((select (j #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 3 / (j #>> '{total,divisor}')::numeric, 2)
    from (select crm.conversion_mensual_sin_cartera_fn('2026-09-01') j) q),
  'M4c: el supervisor ve «aporta» de su equipo con el aporte exacto de sus visibles (A, B y D), sin C');
select set_config('request.jwt.claim.sub', (select g::text from ana), true);
select pg_temp.exigir((select bool_and(case when (r ->> 'divisor')::numeric = 0 then r #>> '{referidos,aporta_pct}' is null
    else (r #>> '{referidos,aporta_pct}')::numeric <= 100 * 1 * (r ->> 'cierres_referidos')::numeric / (r ->> 'divisor')::numeric + 0.005 end) from gp, jsonb_array_elements(j -> 'responsables') r),
  'M5: mes sellado: ningún responsable supera la cota peso × referidos / divisor');
-- Coordinación sirve el aporte de la foto, no peso × cierres.
select pg_temp.exigir((select f.cierres_referido = 3 and f.cierres_referido_aporte = 2 from private.conversion_divisor_empresa('2026-09-01', '2026-09-30') f where f.analista_id = (select a from ana)),
  'M6a: Coordinación (sellado): A cierres_referido 3, aporte 2 (no 3 × 1)');
select pg_temp.exigir((select f.cierres_referido = 1 and f.cierres_referido_aporte = 1 from private.conversion_divisor_empresa('2026-09-01', '2026-09-30') f where f.analista_id = (select b from ana)),
  'M6b: Coordinación (sellado): B cierres_referido 1, aporte 1');
select pg_temp.exigir((select f.cierres_referido = 2 and f.cierres_referido_aporte = 0 from private.conversion_divisor_empresa('2026-09-01', '2026-09-30') f where f.analista_id = 'f0000000-0000-4000-8000-00000000000f'),
  'M6c: Coordinación (sellado): D (solo referidos, base 0) 2 cerrados, aporte 0');
-- Con producción fuera del roster congelada en la foto (C) el desglose de la empresa NO se publica (no suma sus partes): es la regla de siempre.
select pg_temp.exigir((select t.desglose_disponible is false and t.cierres_referido_aporte is null from private.conversion_divisor_empresa_totales('2026-09-01', '2026-09-30') t),
  'M6c2: con producción fuera del ranking en la foto, el total sellado no publica desglose');
select pg_temp.exigir((crm.conversion_divisor_coordinacion_fn('2026-09-01') ->> 'tope_referidos_pct')::numeric = 15, 'M6d: la puerta de Coordinación declara el tope de la foto');
rollback;

-- ═══════ MES SELLADO SIN TOPE: septiembre sellado como en producción (peso 0,15): el desglose sigue siendo peso × cierres ═══════
begin;
\i mundo-fase-b.sql
select set_config('request.jwt.claim.sub', (select g::text from ana), true);
create or replace function private.cierre_mes_ventana_desde(p_periodo date) returns timestamptz language sql stable set search_path = '' as $$ select '2026-01-01'::timestamptz $$;
set local session_replication_role = origin;
create temp table sello_res as select crm.cerrar_periodo('2026-09-01') j;
set local session_replication_role = replica;
select pg_temp.exigir((select pc.tope_referidos_pct is null and pc.ponderacion_referido = 0.150 from crm.periodos_cerrados pc where pc.periodo = '2026-09-01'), 'N1: la foto de septiembre real no lleva tope y guarda 0,15');
select pg_temp.exigir((select f.cierres_referido = 3 and f.cierres_referido_aporte = 0.45 from private.conversion_divisor_empresa('2026-09-01', '2026-09-30') f where f.analista_id = (select a from ana)),
  'N2: Coordinación (sellado, sin tope): A aporta 3 × 0,15 = 0,45, igual que antes');
select pg_temp.exigir((select (crm.conversion_mensual_sin_cartera_fn('2026-09-01') #>> '{total,referidos_aporta_pct}')::numeric = round(100.0 * 0.15 * 4 / 75, 2)
       and (crm.conversion_mensual_sin_cartera_fn('2026-09-01') -> 'ponderacion' -> 'tope_referidos_pct') = 'null'::jsonb),
  'N3: la puerta sirve septiembre sellado con la fórmula de siempre y tope null');
rollback;
select 'PRUEBA-ORIGEN: OK';
