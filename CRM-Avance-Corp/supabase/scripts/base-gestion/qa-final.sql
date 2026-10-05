-- QA final del SERVIDOR · Base para gestión (encargo P-0XX, §«QA final», puntos 1–8), en el banco LOCAL.
-- UNA transacción que termina SIEMPRE en ROLLBACK (o abortada por el `raise` final si hay un FAIL: tampoco se confirma).
-- Corre sobre un banco con B1…B6, B6b (20261004045038) y B6c (20261004123611) aplicadas y los actores de seed:demo (el banco
-- del gate: se buscan por correo). Siembra 12 leads transitorios a9a00000-… que se deshacen con el ROLLBACK.
-- Impersona con claims + `set local role authenticated` y llama a las PUERTAS reales (crm.obtener_base_gestion,
-- crm.registrar_intento_base, crm.reactivar_lead_base, crm.marcar_no_contactar, crm.actividades_de_lead_fn…). La
-- reasignación va por la vía real de la ficha (store.reasignar → actualizarLead: UPDATE de vendedor_id bajo la RLS del
-- supervisor). El paso del tiempo se simula moviendo HACIA ATRÁS todo el pasado de UN lead (descarte, actividades,
-- descanso y rellamada) N días, como postgres y sin usuario: equivale a que el reloj avance N días (now() no se toca).
-- Las decisiones D1–D13 de README.md mandan sobre el texto del encargo: D3/D9 (no hay «interesado»; Reactivar explícito;
-- la marca es reactivado_en y `origen` es inmutable), D12/D13 (enfriamiento), B6 (candado de seguimiento activo).
--
--   psql -X -h 127.0.0.1 -p <puerto del banco local> -U postgres -d postgres -f supabase/scripts/base-gestion/qa-final.sql
--
-- Salida: una línea por caso y, al final, UNA FILA POR PUNTO («QA n · PASS|FAIL · evidencia»).
\set ON_ERROR_STOP on
-- Solo banco LOCAL (mismo candado que b6b-vetados.sql): el secreto JWT de la base tiene que ser el valor de desarrollo
-- PÚBLICO del Supabase CLI (se compara su md5; un proyecto alojado tiene el suyo) y la conexión no va por SSL.
do $solo_banco_local$
begin
  if (md5(coalesce(current_setting('app.settings.jwt_secret', true), '')) = '2a60121f68a3f2b1fb7de7040cb89646'
      and (select not s.ssl from pg_stat_ssl s where s.pid = pg_backend_pid())) is not true then
    raise exception 'qa-final: solo corre en un banco LOCAL de Docker (Supabase CLI); esta base no lo es';
  end if;
end $solo_banco_local$;
\o /dev/null
begin;
set local lock_timeout = '10s';

-- ───────── Utilidades (todo en pg_temp: se va con el ROLLBACK) ─────────
create temp table r (n serial, punto int, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
create function pg_temp.caso(p_punto int, p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into r(punto, caso, esperado, obtenido) values (p_punto, p_caso, p_esperado, p_obtenido); $$;
-- Ejecuta y anota «paso» o «<sqlstate> <mensaje>».
create function pg_temp.err(p_punto int, p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_punto, p_caso, p_esperado, 'paso');
exception when others then perform pg_temp.caso(p_punto, p_caso, p_esperado, sqlstate || ' ' || sqlerrm); end $$;
-- Igual, pero anota solo el SQLSTATE (para rechazos cuyo texto lleva fechas o varía).
create function pg_temp.cod(p_punto int, p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_punto, p_caso, p_esperado, 'paso');
exception when others then perform pg_temp.caso(p_punto, p_caso, p_esperado, sqlstate); end $$;
-- Filas afectadas por una sentencia (UPDATE bajo RLS: 0 = no vio la fila).
create function pg_temp.filas(p_sql text) returns text language plpgsql as $$
declare n bigint;
begin execute p_sql; get diagnostics n = row_count; return n::text;
exception when others then return sqlstate || ' ' || sqlerrm; end $$;
-- La base del actor en sesión, capturada con su orden (la llama el actor: corre con SU rol).
create temp table lista (actor text, ord bigint, lead_id uuid, vendedor_id uuid, rellamada_hoy boolean, intentos integer,
                         ultimo text, proxima timestamptz, no_contactar boolean, motivo text);
grant all on lista to authenticated;
create function pg_temp.captura(p_actor text, p_vend uuid default null, p_vet boolean default false) returns text language plpgsql as $$
declare n bigint;
begin
  delete from lista where actor = p_actor;
  insert into lista select p_actor, t.ordinality, t.lead_id, t.vendedor_id, t.rellamada_hoy, t.intentos, t.ultimo_resultado,
                           t.proxima_llamada_en, t.no_contactar, t.no_contactar_motivo
    from crm.obtener_base_gestion(p_vend, p_vet) with ordinality t;
  get diagnostics n = row_count;
  return n::text;
exception when others then return sqlstate || ' ' || sqlerrm;
end $$;
create function pg_temp.intento(p_lead uuid, p_res text, p_nota text default 'qa', p_prox timestamptz default null) returns jsonb language sql as $$
  select crm.registrar_intento_base(gen_random_uuid(), p_lead, p_res, p_nota, p_prox); $$;
-- Simulación de tiempo: el reloj avanza p_dias para UN lead = todo su pasado retrocede p_dias (descarte sellado, actividades,
-- descanso y rellamada). Solo como postgres y sin usuario; el sello del descarte se apaga SOLO para esa sentencia.
create function pg_temp.avanzar_reloj(p_lead uuid, p_dias int) returns void language plpgsql as $$
begin
  if current_user <> 'postgres' then raise exception 'avanzar_reloj: solo como postgres'; end if;
  perform pg_temp.sesion(null);  -- sin usuario: los sellos de la base y del descarte no juzgan a un actor
  alter table crm.leads disable trigger trg_leads_zz_sello_descarte;
  update crm.leads set descartado_en = descartado_en - make_interval(days => p_dias) where id = p_lead;
  alter table crm.leads enable trigger trg_leads_zz_sello_descarte;
  update crm.leads set enfriado_hasta = enfriado_hasta - p_dias,
                       proxima_llamada_en = proxima_llamada_en - make_interval(days => p_dias) where id = p_lead;
  update crm.actividades set creado_en = creado_en - make_interval(days => p_dias) where lead_id = p_lead;
  -- B9 r2: el candado de seguimiento activo lee la rellamada del último intento (su metadata), no de la columna del lead: el
  -- reloj simulado también la mueve (la de la actividad es una fecha absoluta, como la de la columna).
  update crm.actividades
     set metadata = metadata || jsonb_build_object('proxima_llamada_en', (metadata->>'proxima_llamada_en')::timestamptz - make_interval(days => p_dias))
   where lead_id = p_lead and metadata->>'evento' = 'intento_base' and metadata ? 'proxima_llamada_en';
end $$;
grant execute on function pg_temp.sesion(uuid), pg_temp.caso(int,text,text,text), pg_temp.err(int,text,text,text), pg_temp.cod(int,text,text,text),
  pg_temp.filas(text), pg_temp.captura(text,uuid,boolean), pg_temp.intento(uuid,text,text,timestamptz) to authenticated;  -- avanzar_reloj NO

-- ───────── Actores (seed:demo) y leads transitorios ─────────
create temp table f as select
  (select id from auth.users where email = 'vend1.crm@demo.avancecorp.pe') v1,   -- analista A (equipo de S1)
  (select id from auth.users where email = 'vend2.crm@demo.avancecorp.pe') v2,   -- analista B (equipo de S1)
  (select id from auth.users where email = 'vend3.crm@demo.avancecorp.pe') v3,   -- otro equipo (S2)
  (select id from auth.users where email = 'sup1.crm@demo.avancecorp.pe') s1,
  (select id from auth.users where email = 'sup2.crm@demo.avancecorp.pe') s2,
  (select id from auth.users where email = 'gerencia.crm@demo.avancecorp.pe') g,
  (now() at time zone 'America/Lima')::date hoy,
  'a9a00000-0000-4000-8000-000000000011'::uuid p1a,  -- V1 descartado (su base)
  'a9a00000-0000-4000-8000-000000000012'::uuid p1b,  -- V1 activo en el pipeline (contactado)
  'a9a00000-0000-4000-8000-000000000013'::uuid p1c,  -- V2 descartado (otro analista, mismo equipo)
  'a9a00000-0000-4000-8000-000000000014'::uuid p1d,  -- V3 descartado (otro equipo)
  'a9a00000-0000-4000-8000-000000000021'::uuid p2c,  -- V1 descartado tras llegar a contactado (etapa máxima mayor)
  'a9a00000-0000-4000-8000-0000000000ff'::uuid p2r,  -- V1 descartado; el uuid MAYOR: sin rellamada iría al final
  'a9a00000-0000-4000-8000-000000000031'::uuid p3,   -- V1, se reactiva (puntos 3 y 8)
  'a9a00000-0000-4000-8000-000000000041'::uuid p4,   -- V1, 3 intentos → descanso
  'a9a00000-0000-4000-8000-000000000051'::uuid p5,   -- V1, «No contactar»
  'a9a00000-0000-4000-8000-000000000061'::uuid p6,   -- V1 → V2 (seguimiento vencido)
  'a9a00000-0000-4000-8000-000000000062'::uuid p6c,  -- V1 → V2 (baja de V1, rellamada vigente)
  'a9a00000-0000-4000-8000-000000000081'::uuid p8;   -- V1, «agendó cita» reactiva (punto 8)
alter table f add column n_v1 text, add column n_v2 text, add column n_v3 text, add column n_s1 text;
update f set n_v1 = (select nombre_completo from public.perfiles where id = f.v1), n_v2 = (select nombre_completo from public.perfiles where id = f.v2),
             n_v3 = (select nombre_completo from public.perfiles where id = f.v3), n_s1 = (select nombre_completo from public.perfiles where id = f.s1);
grant select on f to authenticated;
do $$ begin
  if (select v1 is null or v2 is null or v3 is null or s1 is null or s2 is null or g is null from f) then
    raise exception 'qa-final: faltan actores de seed:demo en este banco (correr el gate o seed:demo antes)';
  end if;
  if exists (select 1 from crm.leads where id::text like 'a9a00000-%') then
    raise exception 'qa-final: ya hay leads a9a00000-… en el banco';
  end if;
  if to_regprocedure('crm.obtener_base_gestion(uuid,boolean)') is null
     or not exists (select 1 from pg_trigger where tgname = 'trg_00_actividades_no_contactar_solo_puerta')
     or not exists (select 1 from pg_trigger where tgname = 'trg_leads_00_seguimiento_activo') then
    raise exception 'qa-final: el banco no tiene B6 / B6b / B6c aplicadas';
  end if;
end $$;
select pg_temp.sesion(null);
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, vendedor_id, monto_estimado, moneda, creado_por, activo)
select x.id, x.nombre, x.tel, 'oficina', 'nuevo', x.v, 1000, 'PEN', x.v, true
  from f, lateral (values
    (f.p1a, 'QA P1 PROPIO',            '966700011', f.v1), (f.p1b, 'QA P1 PIPELINE',       '966700012', f.v1),
    (f.p1c, 'QA P1 OTRO ANALISTA',     '966700013', f.v2), (f.p1d, 'QA P1 OTRO EQUIPO',    '966700014', f.v3),
    (f.p2c, 'QA P2 COMPETIDOR',        '966700021', f.v1), (f.p2r, 'QA P2 RELLAMADA',      '966700022', f.v1),
    (f.p3,  'QA P3 REACTIVAR',         '966700031', f.v1), (f.p4,  'QA P4 ENFRIAR',        '966700041', f.v1),
    (f.p5,  'QA P5 NO CONTACTAR',      '966700051', f.v1), (f.p6,  'QA P6 REASIGNAR',      '966700061', f.v1),
    (f.p6c, 'QA P6 REASIGNAR POR BAJA', '966700062', f.v1), (f.p8, 'QA P8 AGENDO CITA',    '966700081', f.v1)) x(id, nombre, tel, v);
update crm.leads set etapa = 'contactado' where id in ((select p1b from f), (select p2c from f));
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id::text like 'a9a00000-%' and id <> (select p1b from f);
select pg_temp.caso(0, 'banco: 12 leads transitorios, 11 descartados y 1 en el pipeline', '12/11/contactado',
  (select count(*) || '/' || count(*) filter (where etapa = 'descartado') || '/' || max(etapa) filter (where id = f.p1b)
     from crm.leads, f where id::text like 'a9a00000-%' group by f.p1b));

-- ═════════ 1. Un analista ve solo su base ═════════
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(1, 'V1 captura su base sin error', 'ok', (select case when c ~ '^[0-9]+$' then 'ok' else c end from (select pg_temp.captura('v1') c) q));
select pg_temp.caso(1, 'V1 ve por RLS sus leads activos del pipeline (control: hay qué excluir)', 'ok',
  (select case when count(*) >= 2 then 'ok' else count(*)::text end from crm.leads l, f where l.vendedor_id = f.v1 and l.etapa <> 'descartado'));
select pg_temp.err(1, 'V1 pide la base de V2 → 42501', '42501 Un analista solo consulta su propia base',
  format('select count(*) from crm.obtener_base_gestion(%L)', (select v2 from f)));
reset role;
select pg_temp.caso(1, 'V1 ve su descartado P1A', 'si', (select case when exists (select 1 from lista, f where actor = 'v1' and lead_id = f.p1a) then 'si' else 'no' end));
select pg_temp.caso(1, 'V1: ninguna fila de su base es un lead activo del pipeline (P1B ni los de seed)', '0',
  (select count(*)::text from lista x join crm.leads l on l.id = x.lead_id where x.actor = 'v1' and (l.etapa <> 'descartado' or not l.activo)));
select pg_temp.caso(1, 'V1: no ve P1C (de V2) ni P1D (de V3); todas sus filas son suyas', '0|0',
  (select count(*) filter (where x.lead_id in (f.p1c, f.p1d)) || '|' || count(*) filter (where x.vendedor_id is distinct from f.v1) from lista x, f where x.actor = 'v1'));
select pg_temp.caso(1, 'V1: su base = exactamente sus descartados vivos sin veto ni descanso', 'ok',
  (select case when (select array_agg(lead_id order by lead_id) from lista where actor = 'v1')
                  = (select array_agg(l.id order by l.id) from crm.leads l, f where l.vendedor_id = f.v1 and l.activo and l.etapa = 'descartado' and not l.no_contactar and (l.enfriado_hasta is null or l.enfriado_hasta <= f.hoy))
               then 'ok' else 'distinta' end));
select pg_temp.sesion((select v2 from f)); set local role authenticated;
select pg_temp.captura('v2');
reset role;
select pg_temp.sesion((select v3 from f)); set local role authenticated;
select pg_temp.captura('v3');
reset role;
select pg_temp.caso(1, 'control: V2 ve P1C y V3 ve P1D (y no se cruzan)', 'si|si|0',
  (select (case when exists (select 1 from lista where actor = 'v2' and lead_id = f.p1c) then 'si' else 'no' end) || '|' ||
          (case when exists (select 1 from lista where actor = 'v3' and lead_id = f.p1d) then 'si' else 'no' end) || '|' ||
          (select count(*) from lista where (actor = 'v2' and vendedor_id <> f.v2) or (actor = 'v3' and vendedor_id <> f.v3)) from f));

-- ═════════ 2. «Volver a llamar»: sin fecha falla; con fecha de hoy, sale primero ═════════
select pg_temp.caso(2, 'antes: primero va P2C (etapa máxima contactado); P2R (uuid mayor) no es el primero', 'P2C|no',
  (select (case when x.lead_id = f.p2c then 'P2C' else x.lead_id::text end) || '|' ||
          (case when exists (select 1 from lista where actor = 'v1' and ord = 1 and lead_id = f.p2r) then 'si' else 'no' end)
     from lista x, f where x.actor = 'v1' and x.ord = 1));
select pg_temp.caso(2, 'segunda defensa en la tabla: CHECK actividades_intento_base_forma exige fecha en volver_a_llamar', 'ok',
  (select case when pg_get_constraintdef(c.oid) like '%volver_a_llamar%' and pg_get_constraintdef(c.oid) like '%proxima_llamada_en%' and c.convalidated then 'ok' else 'no' end
     from pg_constraint c where c.conrelid = 'crm.actividades'::regclass and c.conname = 'actividades_intento_base_forma'));
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.err(2, 'V1: volver_a_llamar SIN fecha → 22023', '22023 Indica cuando volver a llamar',
  format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, %L, null)', (select p2r from f), 'volver_a_llamar', 'sin fecha'));
select pg_temp.cod(2, 'V1: volver_a_llamar a 11 días (D11: máximo 10) → 22023', '22023',
  format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, %L, now() + interval %L)', (select p2r from f), 'volver_a_llamar', 'muy lejos', '11 days'));
reset role;
select pg_temp.caso(2, 'los rechazos no dejaron intento ni rellamada en P2R', '0|null',
  (select (select count(*) from crm.actividades a where a.lead_id = f.p2r and a.metadata->>'evento' = 'intento_base') || '|' || coalesce(l.proxima_llamada_en::text, 'null')
     from crm.leads l, f where l.id = f.p2r));
-- Rellamada HOY (Lima): dentro de una hora o, si no cabe, al último segundo del día.
create temp table t2 as select least(now() + interval '1 hour', ((select hoy from f) + 1)::timestamp at time zone 'America/Lima' - interval '1 second') as prox;
grant select on t2 to authenticated;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(2, 'V1: volver_a_llamar con fecha de HOY → ok, intento 1, rellamada guardada', 'true|1|true',
  (select concat_ws('|', j->>'ok', j->>'intento_n', ((j->>'proxima_llamada_en')::timestamptz = t2.prox)::text)
     from t2, lateral (select crm.registrar_intento_base(gen_random_uuid(), (select p2r from f), 'volver_a_llamar', 'pide que lo llamen hoy', t2.prox) j) q));
select pg_temp.captura('v1');
reset role;
select pg_temp.caso(2, 'V1: ahora P2R es el PRIMERO, con rellamada_hoy, 1 intento y último resultado volver_a_llamar; P2C pasa a 2.º', '1|true|1|volver_a_llamar|2',
  (select concat_ws('|', x.ord, x.rellamada_hoy::text, x.intentos, x.ultimo, (select y.ord from lista y where y.actor = 'v1' and y.lead_id = f.p2c))
     from lista x, f where x.actor = 'v1' and x.lead_id = f.p2r));
select pg_temp.caso(2, 'V1: el bloque «Llamar hoy» va arriba (ninguna fila con rellamada_hoy tras una sin ella)', 'ok',
  (select case when coalesce(max(ord) filter (where rellamada_hoy), 0) < coalesce(min(ord) filter (where not rellamada_hoy), 1e9) then 'ok' else 'mezclado' end from lista where actor = 'v1'));

-- ═════════ 3. Reactivar: Contactado, origen intacto (D9), reactivado_en, sale de la base ═════════
create temp table t3 as select l.origen as origen_antes, l.ciclo_actual as ciclo_antes, l.sla_global_iniciado_en as sla_antes,
                               clock_timestamp() as reloj_antes, null::timestamptz as reloj_despues, gen_random_uuid() as op
  from crm.leads l, f where l.id = f.p3;
grant all on t3 to authenticated;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
update t3 set reloj_antes = clock_timestamp();
select pg_temp.caso(3, 'V1 reactiva P3 por la puerta → contactado, replay false', 'true|contactado|false',
  (select concat_ws('|', j->>'ok', j->>'etapa', j->>'replay') from t3, lateral (select crm.reactivar_lead_base(t3.op, (select p3 from f), 'QA: quiere retomar la inversión') j) q));
update t3 set reloj_despues = clock_timestamp();
select pg_temp.caso(3, 'doble clic (misma operación) → replay true, sin segunda reactivación', 'true|contactado',
  (select concat_ws('|', j->>'replay', j->>'etapa') from t3, lateral (select crm.reactivar_lead_base(t3.op, (select p3 from f), 'QA: quiere retomar la inversión') j) q));
select pg_temp.caso(3, 'V1 sigue viendo P3 por RLS, ahora en el pipeline (contactado)', 'contactado',
  (select coalesce(max(l.etapa), 'no lo ve') from crm.leads l, f where l.id = f.p3));
select pg_temp.captura('v1');
reset role;
select pg_temp.caso(3, 'P3: etapa contactado, origen sin cambio (D9: inmutable), reactivado_en = now(), mismo dueño (D2), ciclo +1, sin rellamada ni descanso',
  (select format('contactado|%s|true|true|%s|null|null', t3.origen_antes, t3.ciclo_antes + 1) from t3),
  (select concat_ws('|', l.etapa, l.origen, (l.reactivado_en = now())::text, (l.vendedor_id = f.v1)::text, l.ciclo_actual,
                    coalesce(l.proxima_llamada_en::text, 'null'), coalesce(l.enfriado_hasta::text, 'null'))
     from crm.leads l, f where l.id = f.p3));
select pg_temp.caso(3, 'D9: `reactivacion_base` no existe como origen (CHECK de crm.leads.origen) → la marca es reactivado_en', 'no',
  (select case when bool_or(pg_get_constraintdef(c.oid) like '%reactivacion_base%') then 'si' else 'no' end
     from pg_constraint c where c.conrelid = 'crm.leads'::regclass and pg_get_constraintdef(c.oid) like '%origen%'));
select pg_temp.caso(3, 'P3 salió de la base de V1', '0', (select count(*)::text from lista, f where actor = 'v1' and lead_id = f.p3));
select pg_temp.caso(3, 'historial: 1 línea reactivacion_base de V1 + cambio_etapa descartado→nuevo y nuevo→contactado', '1|1|1',
  (select concat_ws('|',
     count(*) filter (where a.metadata->>'evento' = 'reactivacion_base' and a.metadata->>'via' = 'base_gestion' and a.creado_por = f.v1),
     count(*) filter (where a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'descartado' and a.metadata->>'etapa_nueva' = 'nuevo'),
     count(*) filter (where a.tipo = 'cambio_etapa' and a.metadata->>'etapa_anterior' = 'nuevo' and a.metadata->>'etapa_nueva' = 'contactado'))
     from crm.actividades a, f where a.lead_id = f.p3 group by f.v1));
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.cod(3, 'D9: V1 intenta poner origen = otro en P3 por la API → rechazado (origen inmutable)', 'P0409',
  format('update crm.leads set origen = %L where id = %L', 'otro', (select p3 from f)));
reset role;

-- ═════════ 4. 3 intentos fallidos lo ocultan; reaparece pasados 30 días ═════════
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(4, 'intentos 1 y 2 (no_contesto, numero_errado) no enfrían', 'null|null',
  coalesce((pg_temp.intento((select p4 from f), 'no_contesto'))->>'enfriado_hasta', 'null') || '|' ||
  coalesce((pg_temp.intento((select p4 from f), 'numero_errado'))->>'enfriado_hasta', 'null'));
select pg_temp.caso(4, 'intento 3 sin cita ni rellamada → enfriado_hasta = hoy + 30 (D4/D12)', (select (hoy + 30)::text from f),
  coalesce((pg_temp.intento((select p4 from f), 'no_contesto'))->>'enfriado_hasta', 'null'));
select pg_temp.captura('v1');
select pg_temp.cod(4, 'intento 4 durante el descanso → 22023', '22023', format('select pg_temp.intento(%L, %L)', (select p4 from f), 'no_contesto'));
reset role;
select pg_temp.caso(4, 'P4 oculto de la base de V1', '0', (select count(*)::text from lista, f where actor = 'v1' and lead_id = f.p4));
select pg_temp.avanzar_reloj((select p4 from f), 29);
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.captura('v1');
reset role;
select pg_temp.caso(4, 'día 29: sigue oculto (enfriado_hasta = mañana)', '0|' || (select (hoy + 1)::text from f),
  (select (select count(*) from lista where actor = 'v1' and lead_id = f.p4) || '|' || (select enfriado_hasta::text from crm.leads where id = f.p4) from f));
select pg_temp.avanzar_reloj((select p4 from f), 1);
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.captura('v1');
reset role;
select pg_temp.caso(4, 'día 30: P4 reaparece, contador en 0 (D13: tres intentos nuevos) y el historial íntegro (3 intento_base)', '1|0|3',
  (select concat_ws('|', (select count(*) from lista x where x.actor = 'v1' and x.lead_id = f.p4), (select max(x.intentos) from lista x where x.actor = 'v1' and x.lead_id = f.p4),
                    (select count(*) from crm.actividades a where a.lead_id = f.p4 and a.metadata->>'evento' = 'intento_base')) from f));
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(4, 'día 30: un intento nuevo se acepta, es el 1.º de la ventana y no enfría', 'true|1|' || (select (hoy)::text from f),
  (select concat_ws('|', j->>'ok', j->>'intento_n', coalesce(j->>'enfriado_hasta', 'null')) from (select pg_temp.intento((select p4 from f), 'no_interesado') j) q));
reset role;

-- ═════════ 5. «No contactar»: oculto para todos los analistas; Supervisión/Gerencia solo con p_incluir_vetados ═════════
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(5, 'V1 marca P5 «No contactar» por la puerta', 'ok',
  (select case when crm.marcar_no_contactar((select p5 from f), 'QA: pidió no ser llamado') is not null then 'ok' else 'null' end));
select pg_temp.err(5, 'V1 pide los vetados → 42501', '42501 Solo Supervision y Gerencia ven los leads marcados No contactar',
  'select count(*) from crm.obtener_base_gestion(null, true)');
select pg_temp.cod(5, 'V1 registra un intento en P5 → P0429 (no insistir)', 'P0429', format('select pg_temp.intento(%L, %L)', (select p5 from f), 'no_contesto'));
select pg_temp.cod(5, 'V1 reactiva P5 → P0429', 'P0429', format('select crm.reactivar_lead_base(gen_random_uuid(), %L, null)', (select p5 from f)));
select pg_temp.cod(5, 'V1 quita la marca → 42501 (solo Supervisión/Gerencia)', '42501', format('select crm.levantar_no_contactar(%L, %L)', (select p5 from f), 'intento'));
reset role;
select pg_temp.sesion(null);
select pg_temp.caso(5, 'P5 sigue marcado tras los intentos rechazados', 'true', (select no_contactar::text from crm.leads, f where id = f.p5));
-- TODOS los analistas activos del banco (rol vendedor): ninguno ve P5.
create temp table t5 (analista uuid, nombre text, captura text, ve_p5 boolean);
grant all on t5 to authenticated;
insert into t5 (analista, nombre) select u.id, u.email from auth.users u where private.rol_crm(u.id) = 'vendedor';
do $$
declare x record;
begin
  for x in select analista from t5 loop
    perform pg_temp.sesion(x.analista);
    set local role authenticated;
    update t5 set captura = pg_temp.captura('a:' || x.analista::text) where analista = x.analista;
    reset role;
  end loop;
  perform pg_temp.sesion(null);
end $$;
update t5 set ve_p5 = exists (select 1 from lista, f where actor = 'a:' || t5.analista::text and lead_id = f.p5);
select pg_temp.caso(5, 'ningún analista ve P5 (todos los de rol vendedor del banco)', '0 de ' || (select count(*) from t5) || ' · sin errores',
  (select count(*) filter (where ve_p5) || ' de ' || count(*) || ' · ' || case when bool_and(captura ~ '^[0-9]+$') then 'sin errores' else string_agg(captura, ';') end from t5));
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.captura('s1');
select pg_temp.captura('s1v', null, true);
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.captura('s2v', null, true);
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.captura('g');
select pg_temp.captura('gv', null, true);
reset role;
select pg_temp.caso(5, 'S1 sin pedirlos no ve P5; con p_incluir_vetados=true sí, con la marca (motivo)', '0|1|true|QA: pidió no ser llamado',
  (select concat_ws('|', (select count(*) from lista where actor = 's1' and lead_id = f.p5), count(*), bool_and(x.no_contactar)::text, max(x.motivo))
     from lista x, f where x.actor = 's1v' and x.lead_id = f.p5 group by f.p5));
select pg_temp.caso(5, 'Gerencia: sin pedirlos no; con true sí. S2 (otro equipo) no lo ve ni con true', '0|1|0',
  (select concat_ws('|', (select count(*) from lista where actor = 'g' and lead_id = f.p5), (select count(*) from lista where actor = 'gv' and lead_id = f.p5),
                    (select count(*) from lista where actor = 's2v' and lead_id = f.p5)) from f));

-- ═════════ 6. Reasignación A → B (vía real: la ficha, UPDATE de vendedor_id bajo la RLS del supervisor) ═════════
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(6, 'A registra en P6 «volver a llamar» en 2 días con nota', 'true|1',
  (select concat_ws('|', j->>'ok', j->>'intento_n') from (select pg_temp.intento((select p6 from f), 'volver_a_llamar', 'QA nota de A: pidió que lo llamen el jueves', now() + interval '2 days') j) q));
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.cod(6, 'B6: con seguimiento activo (intento de hoy + rellamada vigente) S1 no puede reasignar → P0409', 'P0409',
  format('update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L', (select v2 from f), (select p6 from f)));
reset role;
-- Pasan 8 días sin que A vuelva a llamar: el intento queda a 8 días y la rellamada vence hace 6 → ya no está «en gestión».
select pg_temp.avanzar_reloj((select p6 from f), 8);
create temp table t6 as select proxima_llamada_en as prox from crm.leads, f where id = f.p6;
grant select on t6 to authenticated;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso(6, 'día 8: S1 reasigna P6 de A a B por la ficha → 1 fila', '1',
  pg_temp.filas(format('update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L', (select v2 from f), (select p6 from f))));
reset role;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.captura('v1');
select pg_temp.caso(6, 'A ya no ve P6 por RLS', '0', (select count(*)::text from crm.leads l, f where l.id = f.p6));
select pg_temp.err(6, 'A pide el historial de P6 → 42501', '42501 Lead fuera de tu cartera', format('select crm.actividades_de_lead_fn(%L)', (select p6 from f)));
select pg_temp.cod(6, 'A registra un intento en P6 → P0002', 'P0002', format('select pg_temp.intento(%L, %L)', (select p6 from f), 'no_contesto'));
reset role;
select pg_temp.caso(6, 'P6 salió de la base de A', '0', (select count(*)::text from lista, f where actor = 'v1' and lead_id = f.p6));
select pg_temp.sesion((select v2 from f)); set local role authenticated;
select pg_temp.captura('v2');
create temp table h6 as select crm.actividades_de_lead_fn((select p6 from f), 500) as h;
reset role;
select pg_temp.caso(6, 'P6 está en la base de B: suyo, 1 intento, último volver_a_llamar, SU rellamada (vencida → «Llamar hoy», arriba)', 'true|1|volver_a_llamar|true|true|1',
  (select concat_ws('|', (x.vendedor_id = f.v2)::text, x.intentos, x.ultimo, (x.proxima = t6.prox)::text, x.rellamada_hoy::text, x.ord)
     from lista x, f, t6 where x.actor = 'v2' and x.lead_id = f.p6));
select pg_temp.caso(6, 'historial que ve B: el intento de A (nota y autor) y la reasignación «A → B» hecha por S1', 'ok|ok',
  (select (case when exists (select 1 from jsonb_array_elements(h6.h->'items') i where i->'metadata'->>'evento' = 'intento_base'
                               and i->>'detalle' = 'QA nota de A: pidió que lo llamen el jueves' and i->>'autor_nombre' = f.n_v1
                               and i->'metadata'->>'resultado' = 'volver_a_llamar') then 'ok' else 'falta intento' end) || '|' ||
          (case when exists (select 1 from jsonb_array_elements(h6.h->'items') i where i->>'tipo' = 'reasignacion'
                               and i->>'detalle' = f.n_v1 || ' → ' || f.n_v2 and i->>'autor_nombre' = f.n_s1) then 'ok' else 'falta reasignacion' end)
     from h6, f));
select pg_temp.caso(6, 'registro de la reasignación (actividad): vendedor anterior A, nuevo B, quién S1', 'ok',
  (select case when exists (select 1 from crm.actividades a where a.lead_id = f.p6 and a.tipo = 'reasignacion'
                              and (a.metadata->>'vendedor_anterior')::uuid = f.v1 and (a.metadata->>'vendedor_nuevo')::uuid = f.v2 and a.creado_por = f.s1) then 'ok' else 'no' end from f));
select pg_temp.sesion((select v2 from f)); set local role authenticated;
select pg_temp.caso(6, 'B trabaja P6: su intento es el 2.º del ciclo (el contador sigue con el historial)', 'true|2',
  (select concat_ws('|', j->>'ok', j->>'intento_n') from (select pg_temp.intento((select p6 from f), 'no_contesto') j) q));
reset role;
-- 6c · Rellamada VIGENTE: solo se reasigna si A está de baja (B6: «una baja libera»).
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.intento((select p6c from f), 'volver_a_llamar', 'QA nota de A antes de su baja', now() + interval '3 days');
reset role;
create temp table t6c as select proxima_llamada_en as prox from crm.leads, f where id = f.p6c;
grant select on t6c to authenticated;
select pg_temp.sesion(null);
alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
update crm.equipo set activo = false where perfil_id = (select v1 from f);   -- baja de A
alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso(6, 'baja de A: S1 reasigna P6C (rellamada vigente) a B por la ficha → 1 fila', '1',
  pg_temp.filas(format('update crm.leads set vendedor_id = %L, asignado_supervisor_id = null where id = %L', (select v2 from f), (select p6c from f))));
reset role;
select pg_temp.sesion(null);
alter table crm.equipo disable trigger trg_equipo_validar_usuarios_jerarquia;
update crm.equipo set activo = true where perfil_id = (select v1 from f);    -- A vuelve (para mirar su base)
alter table crm.equipo enable trigger trg_equipo_validar_usuarios_jerarquia;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.captura('v1');
reset role;
select pg_temp.sesion((select v2 from f)); set local role authenticated;
select pg_temp.captura('v2');
create temp table h6c as select crm.actividades_de_lead_fn((select p6c from f), 500) as h;
reset role;
select pg_temp.caso(6, 'P6C: fuera de la base de A; en la de B con 1 intento y la MISMA rellamada vigente (no es de hoy)', '0|true|1|true|false',
  (select concat_ws('|', (select count(*) from lista where actor = 'v1' and lead_id = f.p6c), (x.vendedor_id = f.v2)::text, x.intentos, (x.proxima = t6c.prox)::text, x.rellamada_hoy::text)
     from lista x, f, t6c where x.actor = 'v2' and x.lead_id = f.p6c));
select pg_temp.caso(6, 'P6C: B ve el intento de A y la reasignación en el historial', 'ok',
  (select case when exists (select 1 from jsonb_array_elements(h6c.h->'items') i where i->>'detalle' = 'QA nota de A antes de su baja' and i->>'autor_nombre' = f.n_v1)
                and exists (select 1 from jsonb_array_elements(h6c.h->'items') i where i->>'tipo' = 'reasignacion') then 'ok' else 'falta' end from h6c, f));

-- ═════════ 7. Lead ajeno vía SQL bajo rol analista: denegado ═════════
select pg_temp.caso(7, 'control (postgres): P1C y P1D existen y tienen historial', 'ok',
  (select case when (select count(*) from crm.leads l, f where l.id in (f.p1c, f.p1d)) = 2
                and (select count(*) from crm.actividades a, f where a.lead_id = f.p1c) > 0
                and (select count(*) from crm.actividades a, f where a.lead_id = f.p1d) > 0 then 'ok' else 'no' end));
create temp table t7 (msg text);
grant all on t7 to authenticated;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.caso(7, 'V1: select directo a crm.leads de P1C (mismo equipo) y P1D (otro equipo) → 0 filas', '0', (select count(*)::text from crm.leads l, f where l.id in (f.p1c, f.p1d)));
select pg_temp.caso(7, 'V1: select directo a crm.actividades de P1C y P1D → 0 filas', '0', (select count(*)::text from crm.actividades a, f where a.lead_id in (f.p1c, f.p1d)));
select pg_temp.caso(7, 'V1: UPDATE de crm.leads sobre P1C y P1D → 0 filas', '0',
  pg_temp.filas(format('update crm.leads set nombre_completo = %L where id in (%L, %L)', 'HACKEADO', (select p1c from f), (select p1d from f))));
select pg_temp.cod(7, 'V1: INSERT en crm.actividades sobre P1D → 42501 (RLS)', '42501',
  format('insert into crm.actividades (lead_id, tipo, detalle, creado_por) values (%L, %L, %L, %L)', (select p1d from f), 'nota', 'intruso', (select v1 from f)));
select pg_temp.err(7, 'V1: registrar_intento_base en P1D → P0002', 'P0002 Lead no encontrado o fuera de tu ambito',
  format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, null, null)', (select p1d from f), 'no_contesto'));
select pg_temp.err(7, 'V1: registrar_intento_base en P1C → P0002', 'P0002 Lead no encontrado o fuera de tu ambito',
  format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, null, null)', (select p1c from f), 'no_contesto'));
select pg_temp.err(7, 'V1: reactivar_lead_base en P1C → P0002', 'P0002 Lead no encontrado o fuera de tu ambito',
  format('select crm.reactivar_lead_base(gen_random_uuid(), %L, null)', (select p1c from f)));
-- marcar_no_contactar es la puerta previa del CRM (sellada por huella, no es de este módulo): rechaza con el SQLSTATE genérico
-- P0001 y el mismo texto que las puertas de la base, sin decir si el lead existe.
select pg_temp.err(7, 'V1: marcar_no_contactar en P1D → rechazado (P0001 genérico de la puerta sellada, mismo texto)', 'P0001 Lead no encontrado o fuera de tu ambito',
  format('select crm.marcar_no_contactar(%L, %L)', (select p1d from f), 'intruso'));
select pg_temp.err(7, 'V1: actividades_de_lead_fn de P1D → 42501', '42501 Lead fuera de tu cartera', format('select crm.actividades_de_lead_fn(%L)', (select p1d from f)));
select pg_temp.err(7, 'V1: obtener_base_gestion de V3 → 42501', '42501 Un analista solo consulta su propia base', format('select count(*) from crm.obtener_base_gestion(%L)', (select v3 from f)));
select pg_temp.cod(7, 'V1: base_gestion_resumen() → 42501', '42501', 'select count(*) from crm.base_gestion_resumen()');
select pg_temp.cod(7, 'V1: base_gestion_resumen_detalle de V3 → 42501', '42501', format('select count(*) from crm.base_gestion_resumen_detalle(%L, %L)', (select v3 from f), 'intentos_hoy'));
-- Mensajes de los rechazos: ni el nombre del lead ajeno ni el de su analista.
do $$
declare s text;
begin
  foreach s in array array[
    format('select crm.registrar_intento_base(gen_random_uuid(), %L, %L, null, null)', (select p1d from f), 'no_contesto'),
    format('select crm.reactivar_lead_base(gen_random_uuid(), %L, null)', (select p1d from f)),
    format('select crm.marcar_no_contactar(%L, %L)', (select p1d from f), 'intruso'),
    format('select crm.actividades_de_lead_fn(%L)', (select p1d from f))] loop
    begin execute s; insert into t7 values ('PASO: ' || s);
    exception when others then
      declare m text; d text; h text;
      begin get stacked diagnostics m = message_text, d = pg_exception_detail, h = pg_exception_hint; insert into t7 values (concat_ws(' / ', m, d, h)); end;
    end;
  end loop;
end $$;
reset role;
select pg_temp.caso(7, 'los mensajes de rechazo no filtran el nombre del lead ajeno ni de su analista', '0 de 4',
  (select count(*) filter (where position('QA P1' in msg) > 0 or position(f.n_v3 in msg) > 0 or msg like 'PASO:%') || ' de ' || count(*) from t7, f));
select pg_temp.caso(7, 'tras todo, P1C/P1D intactos (nombre, sin veto, sin intentos)', 'ok',
  (select case when bool_and(l.nombre_completo like 'QA P1 %' and not l.no_contactar)
                and not exists (select 1 from crm.actividades a, f where a.lead_id in (f.p1c, f.p1d) and (a.metadata->>'evento' in ('intento_base', 'no_contactar') or a.creado_por = f.v1)) then 'ok' else 'tocados' end
     from crm.leads l, f where l.id in (f.p1c, f.p1d)));

-- ═════════ 8. SLA al reactivar: el reloj arranca en la reactivación (encargo B4; B3/B4: lo hacen 01_sla_global y 02_sla_versionado) ═════════
select pg_temp.caso(8, 'P3: sla_global_iniciado_en reiniciado DENTRO de la llamada a reactivar (entre el reloj de antes y el de después)', 'true|true',
  (select concat_ws('|', (l.sla_global_iniciado_en between t3.reloj_antes and t3.reloj_despues)::text, (l.sla_global_iniciado_en > t3.sla_antes)::text)
     from crm.leads l, t3, f where l.id = f.p3));
select pg_temp.caso(8, 'P3: ciclo SLA nuevo con la política vigente, iniciado en la reactivación, límites desde ahí y sin gestión aún', 'true|true|true|true|null',
  (select concat_ws('|', (c.iniciado_en = l.sla_global_iniciado_en)::text, (c.politica_id = private.sla_politica_vigente(l.sla_global_iniciado_en))::text,
                    (c.primera_gestion_limite_en = c.iniciado_en + p.primera_gestion_minutos * interval '1 minute')::text,
                    (c.primer_contacto_limite_en = c.iniciado_en + p.primer_contacto_minutos * interval '1 minute')::text,
                    coalesce(c.primera_gestion_en::text, 'null'))
     from crm.leads l join crm.lead_sla_ciclos c on c.lead_id = l.id and c.ciclo_n = l.ciclo_actual join crm.sla_politicas p on p.id = c.politica_id, f where l.id = f.p3));
select pg_temp.caso(8, 'P3: episodios del ciclo nuevo = «nuevo» cerrado por cambio_etapa en el instante + «contactado» ABIERTO desde la reactivación con su plazo', '1:nuevo:cambio_etapa:0|2:contactado:abierto:true',
  (select string_agg(concat_ws(':', e.episodio_n, e.etapa, coalesce(e.motivo_cierre, 'abierto'),
                               case when e.finalizado_en is not null then extract(epoch from e.finalizado_en - e.iniciado_en)::int::text
                                    else (e.iniciado_en = l.sla_global_iniciado_en and e.limite_en = e.iniciado_en + pe.maximo_minutos * interval '1 minute')::text end), '|' order by e.episodio_n)
     from crm.leads l join crm.lead_sla_etapas e on e.lead_id = l.id and e.ciclo_n = l.ciclo_actual
     left join crm.sla_politica_etapas pe on pe.politica_id = e.politica_id and pe.etapa = e.etapa, f where l.id = f.p3));
select pg_temp.caso(8, 'P3: un solo episodio abierto en todo el lead; el ciclo anterior quedó cerrado (último motivo cierre_terminal del descarte)', '1|0|cierre_terminal',
  (select concat_ws('|', count(*) filter (where e.finalizado_en is null),
                    count(*) filter (where e.finalizado_en is null and e.ciclo_n < l.ciclo_actual),
                    (select e2.motivo_cierre from crm.lead_sla_etapas e2 where e2.lead_id = l.id and e2.ciclo_n = l.ciclo_actual - 1 order by e2.episodio_n desc limit 1))
     from crm.leads l join crm.lead_sla_etapas e on e.lead_id = l.id, f where l.id = f.p3 group by l.id, l.ciclo_actual));
-- Vía «agendó cita» (D3: reactiva sola) sobre P8.
create temp table t8 as select l.ciclo_actual as ciclo_antes, clock_timestamp() as reloj_antes, null::timestamptz as reloj_despues from crm.leads l, f where l.id = f.p8;
grant all on t8 to authenticated;
select pg_temp.sesion((select v1 from f)); set local role authenticated;
select pg_temp.intento((select p8 from f), 'no_contesto');
update t8 set reloj_antes = clock_timestamp();
select pg_temp.caso(8, 'P8: «agendó cita» desde la base → reactivado, contactado', 'true|true|contactado',
  (select concat_ws('|', j->>'ok', j->>'reactivado', j->>'etapa') from (select pg_temp.intento((select p8 from f), 'agendo_reunion', 'QA: agenda cita') j) q));
update t8 set reloj_despues = clock_timestamp();
select pg_temp.captura('v1');
reset role;
select pg_temp.caso(8, 'P8: ciclo +1, reactivado_en, SLA global reiniciado en la llamada y «contactado» abierto desde ahí; fuera de la base', 'true|true|true|true|0',
  (select concat_ws('|', (l.ciclo_actual = t8.ciclo_antes + 1)::text, (l.reactivado_en is not null)::text,
                    (l.sla_global_iniciado_en between t8.reloj_antes and t8.reloj_despues)::text,
                    (select (e.etapa = 'contactado' and e.iniciado_en = l.sla_global_iniciado_en)::text from crm.lead_sla_etapas e where e.lead_id = l.id and e.finalizado_en is null),
                    (select count(*) from lista x where x.actor = 'v1' and x.lead_id = l.id))
     from crm.leads l, t8, f where l.id = f.p8));
select pg_temp.caso(8, 'P8 (observación): la llamada que reactivó cuenta en el ciclo ANTERIOR; el ciclo nuevo arranca sin primera gestión', 'ok|null',
  (select concat_ws('|', case when (select c.primera_gestion_en from crm.lead_sla_ciclos c where c.lead_id = l.id and c.ciclo_n = l.ciclo_actual - 1) is not null then 'ok' else 'sin gestion' end,
                    coalesce((select c.primera_gestion_en::text from crm.lead_sla_ciclos c where c.lead_id = l.id and c.ciclo_n = l.ciclo_actual), 'null'))
     from crm.leads l, f where l.id = f.p8));

-- ───────── Resultado ─────────
\o
update r set ok = coalesce(obtenido = esperado, false);  -- un NULL no es PASS
select format('%s [%s] %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, punto, caso, esperado, left(obtenido, 220)) from r order by n;
select format('QA %s · %s · %s/%s casos · %s', punto, case when bool_and(ok) then 'PASS' else 'FAIL' end, count(*) filter (where ok), count(*),
              coalesce(string_agg(caso || ' → ' || left(obtenido, 80), ' ¦ ' order by n) filter (where ok is not true), 'todos en verde'))
  from r group by punto order by punto;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'qa-final: hay casos FAIL'; end if; end $$;
rollback;
