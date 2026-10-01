-- Prueba sintética de 20260930235917_crm_potencial_lead_caducidad (fase 2).
-- SOLO en un banco, como supabase_admin, en UNA transacción que termina en raise (no deja nada).
-- Calendario simulado (hora de Lima): lunes 2026-10-05 10:00 se marcan los leads. Fechas clave:
-- sáb 10-10, dom 10-11, lun 10-12, vie 10-16, sáb 10-17, lun 10-19. Los domingos no cuentan como
-- día, pero la tarea corre a diario. La tarea se llama COMO postgres (así corre en pg_cron).
begin;
set local lock_timeout = '5s';

create temp table act (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into act (k) values ('S1'), ('V1');
create temp table lds (k text primary key, id uuid not null default gen_random_uuid()) on commit drop;
insert into lds (k) values ('A'), ('B'), ('C'), ('D'), ('E'), ('F'), ('G'), ('H'), ('I'), ('J'), ('K'), ('L'), ('M'), ('N'), ('O');
create temp table res (n serial, caso text, esperado text, obtenido text) on commit drop;

create function pg_temp.a(p_k text) returns uuid language sql as $$ select id from act where k = p_k $$;
create function pg_temp.l(p_k text) returns uuid language sql as $$ select id from lds where k = p_k $$;
create function pg_temp.esperar(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$
  insert into res (caso, esperado, obtenido) values (p_caso, p_esperado, coalesce(p_obtenido, '(null)'))
$$;
create function pg_temp.nivel(p_k text) returns text language sql as $$
  select p.nivel::text || '/' || p.origen from crm.lead_potencial p where p.lead_id = pg_temp.l(p_k)
$$;
create function pg_temp.historial(p_k text) returns text language sql as $$
  select string_agg(coalesce(e.nivel_anterior::text, 'null') || '>' || e.nivel_nuevo || ':' || e.motivo
                    || ':' || coalesce((select k from act where id = e.por), 'sistema'), ',' order by e.orden)
  from crm.lead_potencial_eventos e where e.lead_id = pg_temp.l(p_k)
$$;
create function pg_temp.lima(p_texto text) returns timestamptz language sql as $$
  select (p_texto::timestamp at time zone 'America/Lima')
$$;
-- La tarea, como la corre pg_cron: con el rol postgres (BYPASSRLS), a las 05:10 Lima de p_hoy.
create function pg_temp.caducar(p_hoy date, p_limite integer default 200) returns integer language plpgsql as $f$
declare v integer;
begin
  set local role postgres;
  v := private.potencial_caducar(p_hoy, (p_hoy::timestamp + time '05:10') at time zone 'America/Lima', p_limite);
  reset role;
  return v;
end $f$;

-- Mundo sin disparadores: un supervisor, un analista y 9 leads marcados el lunes 10-05 10:00 Lima.
set local session_replication_role = replica;
insert into auth.users (id, email) select id, lower(k) || '@caducidad.banco' from act;
insert into public.perfiles (id, nombre_completo, rol, activo) select id, 'CADUCIDAD ' || k, 'analista', true from act;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo) values
  (pg_temp.a('S1'), 'supervisor', null, true),
  (pg_temp.a('V1'), 'vendedor', pg_temp.a('S1'), true);
insert into crm.leads (id, nombre_completo, telefono, origen, monto_estimado, moneda, etapa, vendedor_id, activo, motivo_descarte)
select pg_temp.l(k), 'CADUCIDAD ' || k, '+5198766' || lpad((row_number() over (order by k))::text, 4, '0'), 'landing', 10000, 'PEN',
       case k when 'G' then 'convertido' else 'contactado' end, pg_temp.a('V1'), k <> 'H', null
from lds;
insert into crm.lead_potencial (lead_id, nivel, origen, marcado_por, marcado_en)
select pg_temp.l(k), (case k when 'E' then 'tibio' when 'F' then 'frio' else 'estrella' end)::crm.nivel_potencial,
       'manual', pg_temp.a('V1'), pg_temp.lima('2026-10-05 10:00')
from lds;
-- B: un CONTACTO el jueves 10-08 reinicia el reloj. C: una NOTA el jueves no lo reinicia.
insert into crm.actividades (lead_id, tipo, detalle, creado_por, creado_en) values
  (pg_temp.l('B'), 'llamada_no_contestada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-08 15:00')),
  (pg_temp.l('C'), 'nota', 'nota de sistema de prueba', null, pg_temp.lima('2026-10-08 15:00')),
  (pg_temp.l('J'), 'whatsapp_enviado', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-09 18:00')),
  -- K: contacto el viernes 10-09 a las 21:00 Lima (en UTC ya es sábado 10-10): prueba la zona.
  (pg_temp.l('K'), 'llamada_realizada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-09 21:00')),
  -- L: un contacto con fecha FUTURA no congela el reloj.
  (pg_temp.l('L'), 'reunion_realizada', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2099-01-01 10:00')),
  -- M, N, O (Codex f2 r2 P1): contactos del DOMINGO 10-11 alrededor de la corrida de las 05:10.
  (pg_temp.l('M'), 'whatsapp_recibido', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-11 00:30')),
  (pg_temp.l('N'), 'whatsapp_recibido', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-11 06:00')),
  (pg_temp.l('O'), 'whatsapp_recibido', 'prueba de caducidad', pg_temp.a('V1'), pg_temp.lima('2026-10-11 00:00'));
set local session_replication_role = origin;

do $prueba$
declare
  v_n integer;
  v_estado text;
begin
  -- ── El reloj (contrato acordado) ──
  perform pg_temp.esperar('lun → lun siguiente = 5 días (mar-sáb)', '5', private.dias_lunes_a_sabado('2026-10-05', '2026-10-12')::text);
  perform pg_temp.esperar('vie → lun = 1 (solo sábado)', '1', private.dias_lunes_a_sabado('2026-10-09', '2026-10-12')::text);
  perform pg_temp.esperar('sáb → lun = 0 (domingo no cuenta)', '0', private.dias_lunes_a_sabado('2026-10-10', '2026-10-12')::text);
  perform pg_temp.esperar('lun → sáb de la otra semana = 10', '10', private.dias_lunes_a_sabado('2026-10-05', '2026-10-17')::text);
  perform pg_temp.esperar('regla: estrella con 4 días sigue', 'estrella', private.potencial_nivel_tras('estrella', 4)::text);
  perform pg_temp.esperar('regla: estrella con 5 → tibio', 'tibio', private.potencial_nivel_tras('estrella', 5)::text);
  perform pg_temp.esperar('regla: estrella con 10 → frío', 'frio', private.potencial_nivel_tras('estrella', 10)::text);
  perform pg_temp.esperar('regla: tibio con 9 sigue', 'tibio', private.potencial_nivel_tras('tibio', 9)::text);
  perform pg_temp.esperar('regla: tibio con 10 → frío', 'frio', private.potencial_nivel_tras('tibio', 10)::text);
  perform pg_temp.esperar('reloj de J: el WhatsApp del viernes', '2026-10-09 18:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 05:10')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('J')));
  perform pg_temp.esperar('reloj de C: la nota NO lo mueve', '2026-10-05 10:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 05:10')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('C')));
  perform pg_temp.esperar('reloj de L: el contacto de 2099 aún no cuenta', '2026-10-05 10:00', (
    select to_char(private.potencial_reloj(p.lead_id, p.marcado_en, pg_temp.lima('2026-10-12 05:10')) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('L')));
  perform pg_temp.esperar('dom 10-11: 5 días completos ya (mar-sáb)', '5', private.dias_lunes_a_sabado('2026-10-05', '2026-10-11')::text);
  perform pg_temp.esperar('hasta antes que desde = 0', '0', private.dias_lunes_a_sabado('2026-10-12', '2026-10-05')::text);
  begin
    perform private.potencial_caducar(null, now(), 200);
    perform pg_temp.esperar('fecha nula', '22023', 'ok');
  exception when others then
    perform pg_temp.esperar('fecha nula', '22023', sqlstate);
  end;

  -- ── Sábado 10-10: 4 días completos (mar-vie) → nadie baja ──
  v_n := pg_temp.caducar('2026-10-10');
  perform pg_temp.esperar('sáb 10-10: no baja nadie', '0', v_n::text);
  perform pg_temp.esperar('A sigue estrella el sábado', 'estrella/manual', pg_temp.nivel('A'));

  -- ── Domingo 10-11: ya hay 5 días completos (mar-sáb): baja el domingo de madrugada ──
  -- Primera pasada con límite 2 (la segunda recoge el resto): el lote está acotado.
  v_n := pg_temp.caducar('2026-10-11', 2);
  perform pg_temp.esperar('dom 10-11, pasada con límite 2: baja 2', '2', v_n::text);
  v_n := pg_temp.caducar('2026-10-11');
  perform pg_temp.esperar('dom 10-11, segunda pasada: bajan las 4 restantes de A, C, D, I, L y N', '4', v_n::text);
  perform pg_temp.esperar('M: WhatsApp del domingo 00:30, antes de la corrida, cuenta (no baja)', 'estrella/manual', pg_temp.nivel('M'));
  perform pg_temp.esperar('O: WhatsApp del domingo a las 00:00 en punto cuenta (no baja)', 'estrella/manual', pg_temp.nivel('O'));
  perform pg_temp.esperar('N: WhatsApp del domingo 06:00, DESPUÉS de la corrida, no la salva', 'tibio/caducidad', pg_temp.nivel('N'));
  perform pg_temp.esperar('L: el contacto de 2099 no la congeló', 'tibio/caducidad', pg_temp.nivel('L'));
  -- ── Lunes 10-12: nada nuevo (ya se aplicó el domingo) ──
  v_n := pg_temp.caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12: 0 (lo del sábado ya se aplicó el domingo)', '0', v_n::text);
  perform pg_temp.esperar('A baja a tibio por caducidad', 'tibio/caducidad', pg_temp.nivel('A'));
  perform pg_temp.esperar('A: evento de sistema estrella>tibio', 'estrella>tibio:caducidad:sistema', pg_temp.historial('A'));
  perform pg_temp.esperar('A: marcado_por y marcado_en intactos', 'V1|2026-10-05 10:00', (
    select (select k from act where id = p.marcado_por) || '|' || to_char(p.marcado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
    from crm.lead_potencial p where p.lead_id = pg_temp.l('A')));
  perform pg_temp.esperar('B: el contacto del jueves reinicia el reloj (sigue estrella)', 'estrella/manual', pg_temp.nivel('B'));
  perform pg_temp.esperar('C: una nota no es gestión (baja)', 'tibio/caducidad', pg_temp.nivel('C'));
  perform pg_temp.esperar('E: un tibio no baja con 5 días', 'tibio/manual', pg_temp.nivel('E'));
  perform pg_temp.esperar('F: frío no cambia', 'frio/manual', pg_temp.nivel('F'));
  perform pg_temp.esperar('G: lead convertido no se toca', 'estrella/manual', pg_temp.nivel('G'));
  perform pg_temp.esperar('H: lead inactivo no se toca', 'estrella/manual', pg_temp.nivel('H'));

  -- ── Idempotente: correr dos veces el mismo día no hace nada más ──
  v_n := pg_temp.caducar('2026-10-12');
  perform pg_temp.esperar('lun 10-12 otra vez: 0', '0', v_n::text);
  perform pg_temp.esperar('A: un solo evento', 'estrella>tibio:caducidad:sistema', pg_temp.historial('A'));

  -- ── I: el analista vuelve a marcar estrella el martes 10-13: el reloj arranca de nuevo ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-13 10:00')
   where lead_id = pg_temp.l('I');

  -- ── Viernes 10-16: B lleva 6 días desde su contacto (vie, sáb, lun-jue) ──
  v_n := pg_temp.caducar('2026-10-16');
  perform pg_temp.esperar('vie 10-16: bajan B, J y K', '3', v_n::text);
  perform pg_temp.esperar('K (llamada del viernes 21:00 Lima) baja el viernes 10-16: el día es de Lima, no de UTC', 'tibio/caducidad', pg_temp.nivel('K'));
  perform pg_temp.esperar('J (WhatsApp del viernes 10-09: 5 días) baja a tibio', 'estrella>tibio:caducidad:sistema', pg_temp.historial('J'));
  perform pg_temp.esperar('B baja a tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I re-marcado el martes sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Sábado 10-17: 10 días desde el lunes 10-05 ──
  v_n := pg_temp.caducar('2026-10-17');
  perform pg_temp.esperar('sáb 10-17: bajan a frío A, C, D, E y L, y M y O a tibio', '7', v_n::text);
  perform pg_temp.esperar('M: 5 días desde su WhatsApp del domingo → tibio el sábado', 'tibio/caducidad', pg_temp.nivel('M'));
  perform pg_temp.esperar('J sigue tibio el sábado (6 días desde su contacto; con el reloj de la marca serían 10)', 'tibio/caducidad', pg_temp.nivel('J'));
  perform pg_temp.esperar('A: tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('A'));
  perform pg_temp.esperar('D: estrella → tibio → frío', 'estrella>tibio:caducidad:sistema,tibio>frio:caducidad:sistema', pg_temp.historial('D'));
  perform pg_temp.esperar('E: tibio manual → frío', 'tibio>frio:caducidad:sistema', pg_temp.historial('E'));
  perform pg_temp.esperar('B (tibio desde el viernes, reloj del jueves 10-08) sigue tibio', 'tibio/caducidad', pg_temp.nivel('B'));
  perform pg_temp.esperar('I (re-marcado 10-13) sigue estrella', 'estrella/manual', pg_temp.nivel('I'));

  -- ── Un apagón de la tarea: estrella sin tocar 11 días baja DE GOLPE a frío, con un solo evento ──
  update crm.lead_potencial set nivel = 'estrella', origen = 'manual', marcado_en = pg_temp.lima('2026-10-05 10:00')
   where lead_id = pg_temp.l('F');
  v_n := pg_temp.caducar('2026-10-19');
  perform pg_temp.esperar('lun 10-19: F estrella de 11 días va directo a frío', 'frio/caducidad', pg_temp.nivel('F'));
  perform pg_temp.esperar('F: un solo evento estrella>frio', 'estrella>frio:caducidad:sistema', pg_temp.historial('F'));

  -- ── Auditoría: las bajadas dejaron rastro sin autor humano ──
  perform pg_temp.esperar('bitácora de caducidad en public.audit_log', 'true', (
    select (count(*) > 0)::text from public.audit_log a
    where a.tabla = 'crm.lead_potencial_eventos' and a.usuario_id is null
      and (a.data_despues ->> 'lead_id')::uuid in (select id from lds)));

  -- ── Veredicto (el raise deshace todo) ──
  select count(*) into v_n from res where esperado is distinct from obtenido;
  if v_n = 0 then
    raise exception 'CADUCIDAD potencial_lead: % de % OK', (select count(*) from res), (select count(*) from res) using errcode = 'P0001';
  else
    raise exception 'CADUCIDAD potencial_lead: % FALLAS de %: %', v_n, (select count(*) from res),
      (select string_agg(n || ' ' || caso || ' → esperado ' || esperado || ', obtenido ' || obtenido, ' | ' order by n)
       from res where esperado is distinct from obtenido) using errcode = 'P0001';
  end if;
end;
$prueba$;
rollback;
