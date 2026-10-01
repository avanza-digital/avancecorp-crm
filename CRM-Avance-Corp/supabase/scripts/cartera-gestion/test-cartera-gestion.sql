-- Oráculo del filtro `p_gestion` de crm.cartera_filtrada_fn (firma de 13 argumentos).
-- Solo en un BANCO aislado con la migración 20261001154153 instalada. Datos sintéticos dentro
-- de la transacción y ROLLBACK total: no deja nada. Correr como `postgres` (el rol que aplica
-- las migraciones), sentencia a sentencia (psql -f / stdin): la cadena real de triggers del
-- final necesita que `statement_timestamp()` avance entre sentencias.
--
-- No se detiene en la primera falla: cuenta, y al final dice «N FALLAS de M» o
-- «CARTERA_GESTION_OK M/M». Así un mutante enseña cuántas aserciones lo cazan.
--
-- ⚠️ `anon` y `service_role` NO se prueban llamando: en este Postgres (17.6 con plan_filter)
-- llamar a una función sin EXECUTE bajo `set role` tumba el servidor. Se leen del catálogo.
begin;
set local search_path = '';

-- ── Ayudantes del oráculo (temporales) ───────────────────────────────────────
create function pg_temp.actor(n integer) returns uuid language sql immutable as
  $f$ select ('f3aa1000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
create function pg_temp.lead(n integer) returns uuid language sql immutable as
  $f$ select ('f3aa2000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
-- Identidad del actor: el auth.uid() de esta imagen solo lee `request.jwt.claim.sub`; el de
-- producción también `request.jwt.claims`. Se fijan las dos. n nulo = sin sesión.
create function pg_temp.soy(n integer) returns void language sql as $f$
  select set_config('request.jwt.claim.sub', coalesce(pg_temp.actor(n)::text, ''), true),
         set_config('request.jwt.claims', case when n is null then ''
           else json_build_object('sub', pg_temp.actor(n), 'role', 'authenticated')::text end, true);
$f$;
-- Los casos que trae una respuesta, por su número de fixture: '01,02,09'.
create function pg_temp.casos(p jsonb) returns text language sql stable as $f$
  select coalesce(string_agg(right(i ->> 'nombre_completo', 2), ',' order by right(i ->> 'nombre_completo', 2)), '')
  from jsonb_array_elements(p -> 'items') i;
$f$;
create function pg_temp.vivos(p jsonb) returns integer language sql immutable as
  $f$ select (p #>> '{resumen,totales,vivos}')::integer $f$;
create function pg_temp.afirmar(p_ok boolean, p_que text) returns void language plpgsql as $f$
begin
  if p_ok is true then
    perform set_config('oraculo.ok', (current_setting('oraculo.ok')::integer + 1)::text, true);
  else
    perform set_config('oraculo.fallas', (current_setting('oraculo.fallas')::integer + 1)::text, true);
    perform set_config('oraculo.detalle', left(current_setting('oraculo.detalle') || ' · ' || p_que, 3000), true);
  end if;
end;
$f$;
select set_config('oraculo.ok', '0', true), set_config('oraculo.fallas', '0', true),
       set_config('oraculo.detalle', '', true);
grant execute on function pg_temp.actor(integer), pg_temp.lead(integer), pg_temp.soy(integer),
  pg_temp.casos(jsonb), pg_temp.vivos(jsonb), pg_temp.afirmar(boolean, text) to authenticated;
do $guarda$
begin
  -- Antes de cambiar de rol: todo lo que `authenticated` va a llamar tiene EXECUTE (ver ⚠️).
  if (
    has_function_privilege('authenticated', 'pg_temp.afirmar(boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.soy(integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.casos(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.vivos(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.lead(integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.actor(integer)', 'EXECUTE')
    and has_function_privilege('authenticated',
      'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.resumen_cartera_fn()', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.deshacer_resultado_llamada(uuid)', 'EXECUTE')
  ) is not true then
    raise exception 'ORACULO GESTION: falta EXECUTE para authenticated; no se llama a ciegas';
  end if;
  if exists (select 1 from crm.leads) or exists (select 1 from public.perfiles) then
    raise exception 'ORACULO GESTION: el banco tiene leads o perfiles; este oraculo cuenta sobre un banco sin datos';
  end if;
end;
$guarda$;

-- ── Fixtures ─────────────────────────────────────────────────────────────────
set local session_replication_role = replica;
-- 1 supervisor S1 · 2 analista A · 3 analista B · 4 gerencia · 5 analista C (equipo de S2)
-- 6 supervisor S2 · 7 directorio (lector global) · 8 analista revocado · 9 solo portal.
insert into public.perfiles (id, nombre_completo, rol, activo)
select pg_temp.actor(n), 'GESTION ACTOR ' || n,
  case n when 7 then 'directorio' when 9 then 'cliente' else 'comercial' end, true
from generate_series(1, 9) n;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select pg_temp.actor(n),
  case when n in (1, 6) then 'supervisor' when n = 4 then 'gerencia' when n = 7 then 'directorio' else 'vendedor' end,
  case when n in (2, 3, 8) then pg_temp.actor(1) when n = 5 then pg_temp.actor(6) end,
  n <> 8
from generate_series(1, 8) n;
-- Configuración que un banco vacío no trae (sembrar antes que parchear): la cadena real del
-- final abre un episodio en el libro de asignaciones y reabre un descarte: necesita una política
-- de plazos vigente con sus etapas; el consumidor `resumen_cartera_fn` necesita un peso de conversión.
insert into crm.sla_politicas (id, version, vigente_desde, zona_horaria, tipo_reloj,
  primera_gestion_minutos, primer_contacto_minutos)
values ('f3aa3000-0000-4000-8000-000000000001', 1, '2020-01-01T00:00:00Z', 'America/Lima', 'corrido', 60, 120);
insert into crm.sla_politica_etapas (politica_id, etapa, maximo_minutos)
select 'f3aa3000-0000-4000-8000-000000000001', e, 1440
from unnest(array['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']) e;
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
values ('2026-01-01', 0.5, 'sintetico: oraculo cartera-gestion');

-- Un caso por lead. `ten` = días desde que el titular ACTUAL lo recibió (null = sin tenencia).
--  n  titular  etapa               ten   lo que tiene                                   veredicto
--  01 A        nuevo               5     llamada sin respuesta hace 4 días              CON
--  02 A        nuevo               5     WhatsApp enviado ayer                          CON
--  03 A        nuevo               5     nada                                           SIN
--  04 A        nuevo               5     solo una nota                                  SIN
--  05 B        nuevo (reasignado)  2     intento de A hace 4 días (ANTES de la tenencia) SIN
--  06 B        nuevo (reasignado)  2     intento de A hace 4 días + WhatsApp de B ayer  CON
--  07 —        nuevo, bandeja S1   —     intento viejo de quien lo tuvo                 SIN (sin titular)
--  08 A        nuevo               null  intento ayer, pero sin tenencia_desde          SIN (sin tenencia)
--  09 A        nuevo               5     WhatsApp en el INSTANTE exacto de la tenencia  CON (borde >=)
--  10 A        nuevo               5     WhatsApp 1 microsegundo ANTES de la tenencia   SIN (borde)
--  11 A        contactado          5     llamada realizada hace 3 días                  CON
--  12 A        contactado          5     llamada realizada hace 9 días (antes)          SIN
--  13 C        nuevo               3     llamada sin respuesta hace 2 días              CON
--  14 C        nuevo               3     nada                                           SIN
--  15 A        descartado          null  intento ayer                                   SIN (etapa terminal)
--  16 A        convertido          null  reunión hace 4 días                            SIN (etapa terminal)
--  17 A        nuevo, dado de baja 5     intento ayer                                   fuera de la base
--  18 A        nuevo               5     cambio de etapa, reasignación y conversión     SIN (no son contacto)
--  19 A        nuevo               5     WhatsApp recibido ayer                         CON
--  20 A        nuevo               5     reunión realizada ayer                         CON
--  21 A        nuevo               5     llamada realizada ayer                         CON
--  22 —        nuevo, bolsa libre  —     nada                                           SIN (sin titular)
--  24 A        reunion_agendada    5     reunión realizada hace 2 días                  CON
--  25 B        propuesta_enviada   2     nada                                           SIN
--  26 —        nuevo, bandeja S1   5(!)  intento ayer y una tenencia_desde huérfana     SIN (sin titular)
--  27 A        nuevo               5     intento de ayer hecho por su SUPERVISOR        CON (la regla es por fecha, no por autor)
--  28 A        nuevo               5     SOLO una llamada cuyo resultado se DESHIZO      SIN (lo deshecho no ocurrió)
--  29 A        nuevo               5     una llamada deshecha + un WhatsApp válido ayer  CON (basta un intento vigente)
--  30 A        nuevo               5     intento válido de ANTES de la tenencia + uno deshecho dentro   SIN (ninguno cuenta)
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte,
  monto_estimado, moneda, vendedor_id, asignado_supervisor_id, creado_en, actualizado_en,
  convertido_en, tenencia_desde, activo)
select pg_temp.lead(n), 'GESTION LEAD ' || lpad(n::text, 2, '0'), '+5199933' || lpad(n::text, 4, '0'),
  case when n = 2 then 'referido' else 'landing' end,
  case when n in (11, 12) then 'contactado' when n = 15 then 'descartado' when n = 16 then 'convertido'
    when n = 24 then 'reunion_agendada' when n = 25 then 'propuesta_enviada' else 'nuevo' end,
  case when n = 15 then 'no_responde' end,
  n * 100, case when n in (2, 13) then 'USD' else 'PEN' end,
  case when n in (5, 6, 25) then pg_temp.actor(3) when n in (13, 14) then pg_temp.actor(5)
    when n in (7, 22, 26) then null else pg_temp.actor(2) end,
  case when n in (7, 26) then pg_temp.actor(1) end,
  now() - interval '10 days',
  -- Empate de sello entre 01, 02, 03 y 09: el cursor desempata por id.
  case when n in (1, 2, 3, 9) then now() - interval '1 minute' else now() - make_interval(mins => n) end,
  case when n = 16 then now() - interval '3 days' end,
  case when n in (7, 8, 15, 16, 22) then null
    when n in (5, 6, 25) then now() - interval '2 days'
    when n in (13, 14) then now() - interval '3 days'
    else now() - interval '5 days' end,
  n <> 17
from generate_series(1, 30) n where n <> 23;

insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
values
  (pg_temp.lead(1),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(2),  'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(4),  'nota',                  '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(5),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(5),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', pg_temp.actor(3)), null, now() - interval '2 days'),
  (pg_temp.lead(6),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(6),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', pg_temp.actor(3)), null, now() - interval '2 days'),
  (pg_temp.lead(6),  'whatsapp_enviado',      '{}', pg_temp.actor(3), now() - interval '1 day'),
  (pg_temp.lead(7),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '6 days'),
  (pg_temp.lead(7),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', null), null, now() - interval '5 days'),
  (pg_temp.lead(8),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(9),  'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '5 days'),
  (pg_temp.lead(10), 'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '5 days' - interval '1 microsecond'),
  (pg_temp.lead(11), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '3 days'),
  (pg_temp.lead(12), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '9 days'),
  (pg_temp.lead(13), 'llamada_no_contestada', '{}', pg_temp.actor(5), now() - interval '2 days'),
  (pg_temp.lead(15), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(16), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(17), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(18), 'cambio_etapa',          '{}', null,             now() - interval '1 day'),
  (pg_temp.lead(18), 'reasignacion', jsonb_build_object('vendedor_anterior', null, 'vendedor_nuevo', pg_temp.actor(2)), null, now() - interval '1 day'),
  (pg_temp.lead(18), 'conversion',            '{}', null,             now() - interval '1 day'),
  (pg_temp.lead(19), 'whatsapp_recibido',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(20), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(21), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(24), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '2 days'),
  (pg_temp.lead(26), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(27), 'llamada_no_contestada', '{}', pg_temp.actor(1), now() - interval '1 day'),
  -- Resultados de llamada DESHECHOS: el estado exacto que deja crm.deshacer_resultado_llamada
  -- (la fila se queda; gana `deshecho_en` y `deshecho_por`). La puerta real se ejerce al final.
  (pg_temp.lead(28), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '23 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(29), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '47 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '2 days'),
  (pg_temp.lead(29), 'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(30), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '8 days'),
  (pg_temp.lead(30), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '23 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '1 day');

-- Recepción (para componer con p_desde/p_hasta): A recibió 01..04 ayer (día de Lima).
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
  asignado_en, sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en,
  primer_contacto_limite_en, moneda, origen, finalizado_en, motivo_cierre, aproximado)
select pg_temp.lead(n), 1, 1, pg_temp.actor(2), 'asignado', t.sello, t.sello,
  'f3aa3000-0000-4000-8000-000000000001', t.sello + interval '1 hour', t.sello + interval '2 hours',
  'PEN', 'oraculo_gestion', t.sello + interval '1 second', 'desactivado', false
from generate_series(1, 4) n
cross join lateral (select (((now() at time zone 'America/Lima')::date - 1)::timestamp at time zone 'America/Lima')
  + interval '12 hours' as sello) t;
-- El lead de la cadena real del final: nace en la bandeja de S1 y de baja, para que no cuente
-- en ninguna cifra de arriba; se activa al llegar a ese bloque.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, creado_en, actualizado_en, activo)
values (pg_temp.lead(99), 'GESTION CADENA REAL 99', '+51999330099', 'landing', 'nuevo', 1000, 'PEN',
  null, pg_temp.actor(1), now() - interval '3 days', now() - interval '3 days', false);

set local session_replication_role = origin;
set local role authenticated;

-- ── A · analista: la regla de negocio, caso por caso ─────────────────────────
select pg_temp.soy(2);
do $a$
declare
  t jsonb; c jsonb; s jsonb; r jsonb; p jsonb;
  ids uuid[] := '{}'; fila jsonb; cursor_fecha timestamptz; cursor_id uuid; paginas integer := 0;
  ayer date := (now() at time zone 'America/Lima')::date - 1;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(t) = '01,02,03,04,08,09,10,11,12,15,16,18,19,20,21,24,27,28,29,30', 'A sin filtro: sus 20 leads vivos (el dado de baja no entra)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,09,11,19,20,21,24,27,29', 'A con_gestion: exactamente los 10 gestionados en la tenencia vigente');
  perform pg_temp.afirmar(pg_temp.casos(s) = '03,04,08,10,12,15,16,18,28,30', 'A sin_gestion: exactamente los otros 10');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(1))), 'intento sin respuesta (llamada no contestada) => con_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(2))), 'WhatsApp enviado => con_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(3))), 'lead sin actividad => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(4))), 'solo una nota => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(8))), 'titular sin tenencia_desde => sin_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(9))), 'contacto en el instante exacto de la tenencia => con_gestion (>=)');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(10))), 'contacto un microsegundo antes de la tenencia => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(18))), 'cambio de etapa, reasignacion y conversion no son gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(19)), jsonb_build_object('id', pg_temp.lead(20)), jsonb_build_object('id', pg_temp.lead(21))),
    'los otros tres tipos de contacto (WhatsApp recibido, reunion y llamada realizadas) cuentan');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(15)), jsonb_build_object('id', pg_temp.lead(16))),
    'descartado y convertido (sin tenencia) => sin_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(27))), 'intento hecho por el supervisor dentro de la tenencia => con_gestion (cuenta la fecha, no el autor)');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(28))), 'solo un intento deshecho => sin_gestion (lo deshecho no cuenta)');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(29))), 'un intento deshecho + otro valido en la tenencia => con_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(30))), 'un intento deshecho en la tenencia + uno valido de antes => sin_gestion (ninguno cuenta)');

  -- Partición exacta: sin solapes, sin huecos, y en TODAS las cifras del resumen.
  perform pg_temp.afirmar(pg_temp.vivos(c) = 10 and pg_temp.vivos(s) = 10 and pg_temp.vivos(t) = 20, 'A: totales.vivos 10 + 10 = 20');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(c -> 'items') x
    join jsonb_array_elements(s -> 'items') y on x ->> 'id' = y ->> 'id'), 'A: ningun lead en las dos mitades');
  perform pg_temp.afirmar((select bool_and((t #>> array['resumen','totales',k])::integer
      = (c #>> array['resumen','totales',k])::integer + (s #>> array['resumen','totales',k])::integer)
    from jsonb_object_keys(t #> '{resumen,totales}') k), 'A: cada cifra de resumen.totales = con + sin');
  perform pg_temp.afirmar((select bool_and((te ->> 'n')::integer = (ce ->> 'n')::integer + (se ->> 'n')::integer and te ->> 'etapa' = ce ->> 'etapa' and te ->> 'etapa' = se ->> 'etapa')
    from jsonb_array_elements(t #> '{resumen,embudo}') with ordinality a(te, o)
    join jsonb_array_elements(c #> '{resumen,embudo}') with ordinality b(ce, o) using (o)
    join jsonb_array_elements(s #> '{resumen,embudo}') with ordinality d(se, o) using (o)), 'A: embudo etapa por etapa = con + sin');
  perform pg_temp.afirmar((select string_agg(e ->> 'n', ',' order by o) from jsonb_array_elements(c #> '{resumen,embudo}') with ordinality x(e, o)) = '8,1,1,0,0,0', 'A con_gestion: embudo 8 nuevo, 1 contactado, 1 reunion');
  perform pg_temp.afirmar((select string_agg(e ->> 'n', ',' order by o) from jsonb_array_elements(s #> '{resumen,embudo}') with ordinality x(e, o)) = '7,1,0,0,1,1', 'A sin_gestion: embudo 7 nuevo, 1 contactado, 1 convertido, 1 descartado');
  perform pg_temp.afirmar((select bool_and((t #>> array['resumen','capital',tipo,mon])::numeric
      = (c #>> array['resumen','capital',tipo,mon])::numeric + (s #>> array['resumen','capital',tipo,mon])::numeric)
    from (values ('asignado'), ('parkeado'), ('ganado')) a(tipo) cross join (values ('pen'), ('usd')) b(mon)), 'A: capital por tipo y moneda = con + sin');
  perform pg_temp.afirmar((c #>> '{resumen,capital,asignado,pen}')::numeric = 100 + 900 + 1100 + 1900 + 2000 + 2100 + 2400 + 2700 + 2900
    and (c #>> '{resumen,capital,asignado,usd}')::numeric = 200, 'A con_gestion: capital asignado solo de los gestionados (PEN y USD aparte)');
  perform pg_temp.afirmar((t #>> '{resumen,conversion,base}')::integer = (c #>> '{resumen,conversion,base}')::integer + (s #>> '{resumen,conversion,base}')::integer
    and (t #>> '{resumen,descartes,total}')::integer = (c #>> '{resumen,descartes,total}')::integer + (s #>> '{resumen,descartes,total}')::integer, 'A: conversion.base y descartes.total = con + sin');
  perform pg_temp.afirmar((c #>> '{resumen,sin_tocar}')::integer = 0 and (s #>> '{resumen,sin_tocar}')::integer = 3
    and (t #>> '{resumen,sin_tocar}')::integer = 3, 'A: sin_tocar (nunca contactados: 03, 04, 18) cae entero en sin_gestion; no cambia: una llamada deshecha sigue siendo «tocado»');

  -- La pantalla: Pipeline con p_etapa = 'nuevo'.
  c := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,09,19,20,21,27,29' and pg_temp.vivos(c) = 8, 'A Pipeline «Gestionado»: nuevo + con_gestion = 8');
  perform pg_temp.afirmar(pg_temp.casos(s) = '03,04,08,10,18,28,30' and pg_temp.vivos(s) = 7, 'A Pipeline «Nuevo»: nuevo + sin_gestion = 7');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'contactado', p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '11', 'el filtro es independiente de la etapa (contactado + con_gestion)');

  -- La forma del payload no cambia: mismas claves arriba, en el resumen y por fila; sin eco.
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c) k)
    = array['desde','generado_en','hasta','items','origen','procedencia','reasignados','resumen','version'], 'claves de arriba: las de siempre, sin eco «gestion»');
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c -> 'resumen') k)
    = (select array_agg(k order by k) from jsonb_object_keys(t -> 'resumen') k), 'claves del resumen: iguales con y sin filtro');
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c #> '{items,0}') k)
    = array['activo','actualizado_en','asignado_supervisor_id','cargado_por','categoria_interes','contrato_id','convertido_en','correo','creado_en','distrito','dni','etapa','fecha_nacimiento','genero','id','moneda','monto_estimado','motivo_descarte','no_contactar','nombre_completo','nota','origen','procedencia','reasignado','recepcion_aproximada','recibido_en','telefono','telefono_alternativo','telefono_alternativo_crudo','tenencia_desde','ultimo_contacto_en','vendedor_id'],
    'claves por fila: las 32 de siempre, ninguna nueva');
  -- La fila permite comprobar el veredicto en UN sentido: con gestión ⇒ último contacto >=
  -- tenencia. El recíproco ya no vale: `ultimo_contacto_en` (comportamiento existente) sigue
  -- viendo una llamada deshecha, que para el filtro no ocurrió.
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(c -> 'items') i
    where ((i ->> 'ultimo_contacto_en')::timestamptz >= (i ->> 'tenencia_desde')::timestamptz) is not true
       or i -> 'vendedor_id' = 'null'::jsonb), 'toda fila con_gestion: titular y ultimo_contacto_en >= tenencia_desde');
  perform pg_temp.afirmar((select coalesce(string_agg(right(i ->> 'nombre_completo', 2), ',' order by right(i ->> 'nombre_completo', 2)), '')
    from jsonb_array_elements(s -> 'items') i
    where i -> 'vendedor_id' <> 'null'::jsonb
      and (i ->> 'ultimo_contacto_en')::timestamptz >= (i ->> 'tenencia_desde')::timestamptz) = '28,30',
    'en sin_gestion, las unicas filas con un contacto dentro de su tenencia son las de intentos deshechos (28 y 30)');

  -- Compone con los demás filtros sobre la MISMA base.
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_texto => 'LEAD 02');
  perform pg_temp.afirmar(pg_temp.casos(r) = '02' and pg_temp.vivos(r) = 1, 'compone con la busqueda (con)');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_texto => 'LEAD 02');
  perform pg_temp.afirmar(pg_temp.casos(r) = '' and pg_temp.vivos(r) = 0 and r -> 'items' = '[]'::jsonb, 'vacio honesto: el lead existe pero no esta en esa mitad');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_origen => 'referido');
  perform pg_temp.afirmar(pg_temp.casos(r) = '02', 'compone con el origen');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_procedencia => 'sistema', p_etapa => 'nuevo');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 8, 'compone con la procedencia');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_desde => ayer, p_hasta => ayer);
  perform pg_temp.afirmar(pg_temp.casos(r) = '01,02' and r ->> 'desde' = ayer::text, 'compone con la recepcion (recibidos ayer y ya intentados)');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_desde => ayer, p_hasta => ayer);
  perform pg_temp.afirmar(pg_temp.casos(r) = '03,04', 'compone con la recepcion (recibidos ayer sin intentar)');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_vendedor_id => pg_temp.actor(5));
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'A no alcanza la cartera de otro equipo ni con el filtro');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_vendedor_id => pg_temp.actor(3));
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'A no alcanza la cartera de un companero de equipo');

  -- Paginación por cursor con el filtro puesto: sin repetir ni perder, total estable.
  loop
    p := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_limite => 3, p_antes_de => cursor_fecha, p_antes_id => cursor_id);
    perform pg_temp.afirmar(pg_temp.vivos(p) = 10, 'cursor: el total no cambia entre paginas');
    exit when jsonb_array_length(p -> 'items') = 0;
    paginas := paginas + 1;
    for fila in select value from jsonb_array_elements(p -> 'items') loop
      perform pg_temp.afirmar(not (fila ->> 'id')::uuid = any (ids), 'cursor: ninguna fila repetida');
      ids := array_append(ids, (fila ->> 'id')::uuid);
      cursor_fecha := (fila ->> 'actualizado_en')::timestamptz; cursor_id := (fila ->> 'id')::uuid;
    end loop;
  end loop;
  perform pg_temp.afirmar(cardinality(ids) = 10 and paginas = 4, 'cursor: 4 paginas (3, 3, 3 y 1) reconstruyen los 10 sin perdidas');
  perform pg_temp.afirmar(ids[1:3] = array[pg_temp.lead(1), pg_temp.lead(2), pg_temp.lead(9)], 'cursor: el empate de sello (01, 02, 09) se resuelve por id');
  perform pg_temp.afirmar((select array_agg(x order by x) from unnest(ids) x)
    = (select array_agg((i ->> 'id')::uuid order by (i ->> 'id')::uuid) from jsonb_array_elements(c -> 'items') i), 'cursor: las paginas juntas = la respuesta sin paginar');

  -- Validación: fuera de dominio se rechaza; nunca un «cero resultados» silencioso.
  begin perform crm.cartera_filtrada_fn(p_gestion => 'gestionado'); perform pg_temp.afirmar(false, 'valor desconocido debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(sqlerrm = 'Filtros de cartera inválidos', 'valor desconocido => 22023 con el mensaje del bloque existente'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => ''); perform pg_temp.afirmar(false, 'cadena vacia debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'cadena vacia => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'CON_GESTION'); perform pg_temp.afirmar(false, 'mayusculas debieron rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'mayusculas => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion '); perform pg_temp.afirmar(false, 'espacio final debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'espacio final => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_origen => 'facebook'); perform pg_temp.afirmar(false, 'las guardas previas debieron seguir');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'las guardas previas siguen (origen fuera de dominio)'); end;

  -- Compatibilidad: la llamada de siempre (12 argumentos, sin p_gestion) sigue resolviendo.
  r := crm.cartera_filtrada_fn(p_limite => 200, p_antes_de => null, p_antes_id => null, p_etapa => null,
    p_vendedor_id => null, p_sin_asignar => false, p_texto => null, p_desde => null, p_hasta => null,
    p_origen => null, p_procedencia => null, p_reasignados => false);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'los 12 argumentos por nombre, sin p_gestion: misma respuesta que sin filtro');
  r := crm.cartera_filtrada_fn(200, null, null, null, null, false, null, null, null, null, null, false);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'los 12 argumentos por posicion: misma respuesta');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => null);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'p_gestion nulo explicito = omitido');
  perform pg_temp.afirmar((crm.resumen_cartera_fn() #>> '{totales,vivos}')::integer = 20, 'el consumidor resumen_cartera_fn sigue resolviendo la firma ampliada');
end;
$a$;

-- ── A · negativas de FALSIFICACIÓN: nadie fabrica, reescribe ni borra una gestión ──
-- Sigue siendo A (authenticated, bajo RLS). Son escrituras sobre TABLAS: sin permiso dan un
-- error normal (lo que tumba este Postgres es llamar a una FUNCIÓN sin EXECUTE; eso se lee del
-- catálogo). Si alguna «colara», los bloques de C, S1 y gerencia de abajo también fallarían.
do $falsificar$
begin
  -- 1) Un contacto en un lead AJENO (el 14, de C, sin gestión): lo rechaza el sello de la
  --    actividad, que revalida el ámbito. Tampoco firmándolo a nombre de su titular.
  begin
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (pg_temp.lead(14), 'llamada_no_contestada', 'falsificacion', pg_temp.actor(2));
    perform pg_temp.afirmar(false, 'falsificacion: un contacto en un lead ajeno debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: contacto en un lead ajeno => 42501');
  end;
  begin
    insert into crm.actividades (lead_id, tipo, detalle, creado_por)
    values (pg_temp.lead(14), 'whatsapp_enviado', 'falsificacion', pg_temp.actor(5));
    perform pg_temp.afirmar(false, 'falsificacion: un contacto a nombre de otro debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: contacto en un lead ajeno a nombre de su titular => 42501');
  end;
  -- 2) Escribir `deshecho_en` a mano: es clave reservada del núcleo del resultado de llamada.
  begin
    insert into crm.actividades (lead_id, tipo, detalle, metadata, creado_por)
    values (pg_temp.lead(3), 'llamada_no_contestada', 'falsificacion', jsonb_build_object('deshecho_en', now()), pg_temp.actor(2));
    perform pg_temp.afirmar(false, 'falsificacion: escribir deshecho_en a mano debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: escribir deshecho_en a mano => 42501');
  end;
  -- 3) Quitar `deshecho_en` o mover la fecha de un contacto: authenticated no tiene UPDATE.
  begin
    update crm.actividades set metadata = metadata - 'deshecho_en' where lead_id = pg_temp.lead(28);
    perform pg_temp.afirmar(false, 'falsificacion: quitar deshecho_en debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: quitar deshecho_en con UPDATE => sin permiso');
  end;
  begin
    update crm.actividades set creado_en = now() where lead_id = pg_temp.lead(10);
    perform pg_temp.afirmar(false, 'falsificacion: mover la fecha de un contacto debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: mover creado_en con UPDATE => sin permiso');
  end;
  -- 4) Borrar una gestión: authenticated no tiene DELETE.
  begin
    delete from crm.actividades where lead_id = pg_temp.lead(1);
    perform pg_temp.afirmar(false, 'falsificacion: borrar una actividad debio rechazarse');
  exception when insufficient_privilege then
    perform pg_temp.afirmar(true, 'falsificacion: borrar una actividad con DELETE => sin permiso');
  end;
  -- Nada cambió: las dos mitades de A son las mismas de antes.
  perform pg_temp.afirmar(pg_temp.casos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion')) = '01,02,09,11,19,20,21,24,27,29'
    and pg_temp.casos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion')) = '03,04,08,10,12,15,16,18,28,30',
    'falsificacion: tras los seis intentos, las dos mitades de A no se movieron');
end;
$falsificar$;

-- ── B · analista que RECIBIÓ leads reasignados ───────────────────────────────
select pg_temp.soy(3);
do $b$
declare c jsonb; s jsonb; r jsonb;
begin
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(s) = '05,25', 'reasignado: lo que intento el analista ANTERIOR no cuenta => sin_gestion para el actual');
  perform pg_temp.afirmar(pg_temp.casos(c) = '06', 'reasignado y vuelto a intentar por el nuevo titular => con_gestion');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '05' and (r #>> '{items,0,reasignado}')::boolean, 'B Pipeline «Nuevo»: el reasignado sin intento propio, marcado como reasignado');
  r := crm.cartera_filtrada_fn(p_reasignados => true, p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '06', 'compone con reasignados (con)');
  r := crm.cartera_filtrada_fn(p_reasignados => true, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '05', 'compone con reasignados (sin)');
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200)) = 3, 'B solo ve lo suyo');
end;
$b$;

-- ── S1 · supervisor: su equipo y su bandeja, nada más ────────────────────────
select pg_temp.soy(1);
do $s1$
declare t jsonb; c jsonb; s jsonb; r jsonb;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(t) = 25 and pg_temp.vivos(c) = 11 and pg_temp.vivos(s) = 14, 'supervisor: 11 + 14 = 25 (A, B y su bandeja)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,06,09,11,19,20,21,24,27,29', 'supervisor con_gestion: los de A y el de B; ninguno del otro equipo');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(7))), 'sin titular (bandeja) => sin_gestion aunque tenga intentos viejos');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(26))), 'sin titular => sin_gestion aunque conserve una tenencia_desde y un intento posterior');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements((c -> 'items') || (s -> 'items')) i
    where right(i ->> 'nombre_completo', 2) in ('13', '14', '22')), 'supervisor: el filtro no trae leads de otro equipo ni la bolsa libre');
  r := crm.cartera_filtrada_fn(p_sin_asignar => true, p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'pendientes de repartir + con_gestion = vacio (sin titular no hay gestion)');
  r := crm.cartera_filtrada_fn(p_sin_asignar => true, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '07,26', 'pendientes de repartir + sin_gestion = su bandeja');
  r := crm.cartera_filtrada_fn(p_vendedor_id => pg_temp.actor(3), p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '06', 'supervisor acota por analista de su equipo');
  r := crm.cartera_filtrada_fn(p_vendedor_id => pg_temp.actor(5), p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'supervisor no alcanza a un analista de otro equipo');
end;
$s1$;

-- ── C y S2 · el otro equipo ──────────────────────────────────────────────────
select pg_temp.soy(5);
do $c$
begin
  perform pg_temp.afirmar(pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'con_gestion')) = '13'
    and pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'sin_gestion')) = '14', 'analista del otro equipo: solo lo suyo, partido en dos');
end;
$c$;
select pg_temp.soy(6);
do $s2$
begin
  perform pg_temp.afirmar(pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'con_gestion')) = '13'
    and pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'sin_gestion')) = '14', 'supervisor del otro equipo: solo su equipo');
end;
$s2$;

-- ── Gerencia y Directorio: todo ──────────────────────────────────────────────
select pg_temp.soy(4);
do $g$
declare t jsonb; c jsonb; s jsonb;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(t) = 28 and pg_temp.vivos(c) = 12 and pg_temp.vivos(s) = 16, 'gerencia: 12 + 16 = 28 (toda la empresa)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,06,09,11,13,19,20,21,24,27,29', 'gerencia con_gestion: los 12 gestionados de los tres analistas');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(22)), jsonb_build_object('id', pg_temp.lead(7))), 'gerencia: bolsa libre y bandeja => sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion')) = 10
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion')) = 12
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo')) = 22, 'gerencia Pipeline: nuevo 22 = Gestionado 10 + Nuevo 12');
end;
$g$;
select pg_temp.soy(7);
do $d$
begin
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion')) = 12
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion')) = 16, 'directorio (lector global): misma particion que gerencia');
end;
$d$;

-- ── Quien no entra, no entra tampoco con el filtro (se llama CON EXECUTE: es la guarda
--    de la función la que rechaza, no el permiso) ──────────────────────────────
select pg_temp.soy(8);
do $r$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion'); perform pg_temp.afirmar(false, 'analista revocado debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'analista revocado => 42501'); end;
end;
$r$;
select pg_temp.soy(9);
do $p$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'sin_gestion'); perform pg_temp.afirmar(false, 'perfil solo-portal debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'perfil solo-portal => 42501'); end;
end;
$p$;
select pg_temp.soy(null);
do $n$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion'); perform pg_temp.afirmar(false, 'sin sesion debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'sin sesion => 42501'); end;
end;
$n$;
reset role;

-- ── Catálogo: firma única y permisos (leídos, nunca llamados) ────────────────
do $cat$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  p pg_proc%rowtype;
begin
  select * into p from pg_proc where oid = to_regprocedure(f13);
  perform pg_temp.afirmar(to_regprocedure(f12) is null and (select count(*) from pg_proc
    where proname = 'cartera_filtrada_fn' and pronamespace = 'crm'::regnamespace) = 1, 'una sola firma para PostgREST: la de 12 ya no existe');
  perform pg_temp.afirmar(not has_function_privilege('anon', f13, 'EXECUTE'), 'anon sin EXECUTE (catalogo)');
  perform pg_temp.afirmar(not has_function_privilege('service_role', f13, 'EXECUTE'), 'service_role sin EXECUTE (catalogo)');
  perform pg_temp.afirmar(has_function_privilege('authenticated', f13, 'EXECUTE'), 'authenticated con EXECUTE');
  perform pg_temp.afirmar((select array_agg(q.x order by q.x) from (
      select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || ':' || a.privilege_type as x
      from aclexplode(p.proacl) a) q) = array['authenticated:EXECUTE', 'postgres:EXECUTE'], 'ACL por lista blanca: solo postgres y authenticated (PUBLIC fuera)');
  perform pg_temp.afirmar(not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
    and p.proowner = 'postgres'::regrole, 'INVOKER, stable, search_path vacio, dueno postgres');
  perform pg_temp.afirmar(p.pronargs = 13 and p.pronargdefaults = 13 and p.proargnames[13] = 'p_gestion'
    and right(pg_get_function_arguments(p.oid), 35) = ', p_gestion text DEFAULT NULL::text', 'el 13.o argumento es p_gestion text default null, al final');
  perform pg_temp.afirmar(obj_description(p.oid, 'pg_proc') like '%p\_gestion%' escape '\', 'el comentario documenta el filtro');
end;
$cat$;

-- ── La cadena REAL (triggers y puertas del servidor, sin fechas fabricadas) ──
-- Va al final y con sentencias sueltas. El lead 99 sale de la bandeja de S1: se da de alta
-- sin triggers (la reactivación tiene su propia puerta) y desde ahí todo es el servidor real.
set local session_replication_role = replica;
update crm.leads set activo = true where id = pg_temp.lead(99);
set local session_replication_role = origin;
-- 1) El supervisor lo entrega a A: el trigger sella tenencia_desde.
update crm.leads set vendedor_id = pg_temp.actor(2), asignado_supervisor_id = null where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(2);
do $r1$
begin
  perform pg_temp.afirmar((select l.tenencia_desde is not null from crm.leads l where l.id = pg_temp.lead(99)), 'cadena real: al entregar, el trigger sella tenencia_desde');
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: recien entregado => «Nuevo» para A');
end;
$r1$;
-- 2) A llama y no le contestan: lo registra por la PUERTA REAL (crm.registrar_llamada_v4, el
--    escritor sellado del resultado de llamada), bajo su sesión y con el sello del servidor.
select 'registrar_llamada_v4 ok=' || (crm.registrar_llamada_v4('f3aa4000-0000-4000-8000-000000000001', pg_temp.lead(99), 'no_contesto') ->> 'ok');
do $r2$
begin
  perform pg_temp.afirmar((select l.etapa = 'nuevo' from crm.leads l where l.id = pg_temp.lead(99)), 'cadena real: un intento sin respuesta NO mueve la etapa (sigue en nuevo)');
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: tras el intento => «Gestionado» para A');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y deja de estar en «Nuevo»');
end;
$r2$;
-- 3) A lo DESHACE por la puerta real (crm.deshacer_resultado_llamada): la llamada no se borra,
--    queda marcada con `deshecho_en`; para el Pipeline no ocurrió y el lead vuelve a «Nuevo».
select 'deshacer_resultado_llamada ok=' || (crm.deshacer_resultado_llamada('f3aa4000-0000-4000-8000-000000000001') ->> 'ok');
do $r2b$
declare s jsonb;
begin
  perform pg_temp.afirmar((select a.tipo = 'llamada_no_contestada' and a.metadata ? 'deshecho_en' and a.metadata ->> 'evento' = 'resultado_llamada'
    from crm.actividades a where a.id = 'f3aa4000-0000-4000-8000-000000000001'), 'cadena real: deshacer conserva la llamada y la marca con deshecho_en');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: solo un intento deshecho => vuelve a «Nuevo»');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y deja de estar en «Gestionado»');
  perform pg_temp.afirmar((select i ->> 'ultimo_contacto_en' is not null from jsonb_array_elements(s -> 'items') i
    where i ->> 'id' = pg_temp.lead(99)::text), 'cadena real: ultimo_contacto_en sigue viendo la llamada deshecha (comportamiento existente, intacto)');
end;
$r2b$;
-- 4) A lo intenta otra vez, por WhatsApp (actividad real bajo RLS): un intento deshecho +
--    otro válido en la tenencia => «Gestionado». El cliente manda además un `creado_en`
--    FUTURO: el servidor lo re-sella con su reloj; si sobreviviera, el intento de A seguiría
--    contando para B tras la reasignación de abajo (y las aserciones de B fallarían).
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en)
values (pg_temp.lead(99), 'whatsapp_enviado', 'intento sintetico del oraculo', pg_temp.actor(2), now() + interval '30 days');
do $r2c$
begin
  perform pg_temp.afirmar((select a.creado_en <= clock_timestamp() from crm.actividades a
    where a.lead_id = pg_temp.lead(99) and a.tipo = 'whatsapp_enviado'), 'cadena real: un creado_en futuro enviado por el cliente se re-sella con la hora del servidor');
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: un intento deshecho + otro valido => «Gestionado» para A');
end;
$r2c$;
reset role;
select pg_temp.soy(null);
-- 5) Reasignación A → B: el trigger RENUEVA tenencia_desde y emite el evento.
update crm.leads set vendedor_id = pg_temp.actor(3) where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r3$
declare s jsonb;
begin
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99), 'reasignado', true)), 'cadena real: reasignado => «Nuevo» para B aunque A ya lo intento (decision de Miguel); la fecha futura que mando A no sobrevivio');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y NO aparece como «Gestionado» de B');
end;
$r3$;
-- 6) B lo intenta por WhatsApp.
insert into crm.actividades (lead_id, tipo, detalle, creado_por)
values (pg_temp.lead(99), 'whatsapp_enviado', 'intento sintetico del oraculo', pg_temp.actor(3));
do $r4$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: tras el intento de B => «Gestionado» para B');
end;
$r4$;
select pg_temp.soy(2);
do $r5$
begin
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200) -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: A ya no ve el lead que entrego');
end;
$r5$;
reset role;
select pg_temp.soy(null);
-- 7) Se descarta: sale de tenencia operativa y el trigger apaga el reloj.
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r6$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'descartado', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99), 'tenencia_desde', null)), 'cadena real: descartado => sin tenencia y por eso sin_gestion, aunque se intento');
end;
$r6$;
reset role;
select pg_temp.soy(null);
-- 8) Se reabre con el MISMO titular: el trigger estrena reloj y lo intentado antes ya no cuenta.
update crm.leads set etapa = 'nuevo', motivo_descarte = null where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r7$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: reabierto => vuelve a «Nuevo» aunque su mismo titular lo intento antes del descarte');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: reabierto => no aparece como «Gestionado»');
end;
$r7$;
reset role;

-- ── Veredicto ────────────────────────────────────────────────────────────────
do $fin$
declare
  ok integer := current_setting('oraculo.ok')::integer;
  fallas integer := current_setting('oraculo.fallas')::integer;
begin
  if fallas > 0 or ok = 0 then
    raise exception 'ORACULO GESTION: % FALLAS de %:%', fallas, ok + fallas, current_setting('oraculo.detalle');
  end if;
end;
$fin$;
select 'CARTERA_GESTION_OK ' || current_setting('oraculo.ok') || '/' || current_setting('oraculo.ok');
rollback;
