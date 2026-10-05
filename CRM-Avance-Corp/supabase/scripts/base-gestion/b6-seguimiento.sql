-- B6 · Seguimiento activo en el banco (una transacción, impersonación, ROLLBACK al final). Falla el proceso si hay FAIL.
-- El candado vive en el LEAD (trg_leads_00_seguimiento_activo): se prueba por el rescate, la ficha (PATCH) y «tomar lead libre».
-- Actores y leads: fixtures-b2.sql. S1 supervisa a A y B; S2 a C. LA (A), LB (B), LC (C): descartados con su episodio.
begin;
create temp table r (n serial, caso text, esperado text, obtenido text, ok boolean);
grant all on r to authenticated; grant usage, select on sequence r_n_seq to authenticated;
create function pg_temp.sesion(p uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p::text,''), true),
         set_config('request.jwt.claims', case when p is null then '' else json_build_object('sub', p, 'role', 'authenticated')::text end, true);
$$;
grant execute on function pg_temp.sesion(uuid) to authenticated;
create temp table f as select
  'b0000000-0000-4000-8000-000000000002'::uuid a, 'b0000000-0000-4000-8000-000000000012'::uuid b, 'b0000000-0000-4000-8000-000000000013'::uuid c,
  'b0000000-0000-4000-8000-000000000001'::uuid s1, 'b0000000-0000-4000-8000-000000000011'::uuid s2, 'b0000000-0000-4000-8000-000000000003'::uuid g,
  'b0000000-0000-4000-8000-0000000000a1'::uuid la, 'b0000000-0000-4000-8000-0000000000b1'::uuid lb, 'b0000000-0000-4000-8000-0000000000c1'::uuid lc,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000a1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_la,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000b1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_lb,
  (select la.id from crm.lead_asignaciones la join crm.leads l on l.id = la.lead_id where l.id = 'b0000000-0000-4000-8000-0000000000c1' and la.resultado = 'descartado' and la.resultado_en = l.descartado_en) ep_lc,
  (select date_trunc('month', descartado_en at time zone 'America/Lima')::date from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') mes,
  (now() at time zone 'America/Lima')::date hoy,
  -- Leídos como postgres: B (otro analista) no ve LA por RLS; «tomar lead libre» llega por el teléfono que le dicta la persona.
  (select telefono from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') tel_la,
  (select dni from crm.leads where id = 'b0000000-0000-4000-8000-0000000000a1') dni_la;
grant select on f to authenticated;
-- Los descartes del banco son de ayer: para probar «hace 7 u 8 días» el ciclo tiene que empezar antes. Se mueven 30 días
-- atrás el descarte de LA y LC y su episodio, juntos (el episodio sigue vigente), sin disparar sellos (solo en esta transacción).
set local session_replication_role = replica;
update crm.leads set descartado_en = descartado_en - interval '30 days' where id in ((select la from f), (select lc from f));
do $mover$ begin  -- TODAS las fechas del episodio, para que sus CHECK de orden sigan valiendo
  execute format('update crm.lead_asignaciones set %s where id = any(%L::uuid[])',
    (select string_agg(format('%1$I = %1$I - interval ''30 days''', attname), ', ') from pg_attribute
      where attrelid = 'crm.lead_asignaciones'::regclass and atttypid = 'timestamptz'::regtype and attnum > 0 and not attisdropped),
    (select array[ep_la, ep_lc] from f));
end $mover$;
set local session_replication_role = origin;
create temp table m as select l.id lead_id, date_trunc('month', l.descartado_en at time zone 'America/Lima')::date mes from crm.leads l, f where l.id in (f.la, f.lb, f.lc);
grant select on m to authenticated;
create function pg_temp.caso(p_caso text, p_esperado text, p_obtenido text) returns void language sql as $$ insert into r(caso, esperado, obtenido) values (p_caso, p_esperado, p_obtenido); $$;
grant execute on function pg_temp.caso(text,text,text) to authenticated;
create function pg_temp.err(p_caso text, p_esperado text, p_sql text) returns void language plpgsql as $$
begin execute p_sql; perform pg_temp.caso(p_caso, p_esperado, 'paso'); exception when others then perform pg_temp.caso(p_caso, p_esperado, sqlstate || ' ' || sqlerrm); end $$;
grant execute on function pg_temp.err(text,text,text) to authenticated;
-- Fila del Centro de rescate de un episodio, leída por el actor de la sesión: «puede|por|hasta|estado».
create function pg_temp.fila(p_ep uuid) returns text language sql as $$
  select coalesce((select format('%s|%s|%s|%s', x.puede_rescatar::text, coalesce(x.en_gestion_por, '-'), coalesce(x.en_gestion_hasta::text, '-'), x.estado)
                     from m, crm.rescate_descartes_mes(m.mes) x where x.episodio_id = p_ep and x.lead_id = m.lead_id), 'sin fila'); $$;
grant execute on function pg_temp.fila(uuid) to authenticated;
-- El detail del rechazo de un reparto (con la sesión vigente).
create function pg_temp.detalle_rechazo(p_ep uuid, p_dest uuid) returns jsonb language plpgsql as $$
declare d text;
begin
  perform crm.rescatar_descartes(array[p_ep], array[p_dest]);
  return '{"estado":"paso"}'::jsonb;
exception when sqlstate 'P0409' then
  get stacked diagnostics d = pg_exception_detail;
  return d::jsonb;
when others then
  return pg_catalog.jsonb_build_object('estado', 'otro_error', 'sqlstate', sqlstate);
end $$;

select pg_temp.caso('banco: los tres episodios existen', 'ok', case when (select ep_la is not null and ep_lb is not null and ep_lc is not null from f) then 'ok' else 'faltan' end);

-- ───────── Sin seguimiento: todo como antes ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: LA sin intentos → se puede elegir, sin gris', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;

-- ───────── A registra un intento en LA → 7 días en gestión ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), (select la from f), 'no_contesto', 'sin respuesta');
reset role;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: LA con intento de hoy → gris, por A, hasta hoy+7, estado sigue pendiente (bundle viejo)', (select format('false|BANCO VENDEDOR|%s|pendiente', hoy + 7) from f), pg_temp.fila((select ep_la from f)));
select pg_temp.caso('S1: LB (sin intentos) sigue elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lb from f)));
select pg_temp.err('S1: repartir LA → P0409 del candado, sin nombres', 'P0409 Este lead lo está trabajando su analista hasta el ' || (select to_char(hoy + 7, 'DD/MM/YYYY') from f) || ': no se le puede cambiar el responsable',
  format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[])', (select ep_la from f), (select b from f)));
select pg_temp.err('S1: lote LA + LB → P0409, todo o nada', 'P0409', format('select crm.rescatar_descartes(array[%L, %L]::uuid[], array[%L]::uuid[])', (select ep_la from f), (select ep_lb from f), (select b from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'S1: lote LA + LB%';
select pg_temp.caso('S1: tras el lote rechazado, LB sigue descartado y de B', 'descartado/B', (select etapa || '/' || case when vendedor_id = f.b then 'B' else 'otro' end from crm.leads, f where id = f.lb));
select pg_temp.caso('detail del rechazo: estado en_gestion y la fecha, SIN identificador del lead (Codex 03/10)', 'ok',
  (select case when d->>'estado' = 'en_gestion' and d->>'hasta' = (f.hoy + 7)::text and not (d ? 'lead_id') then 'ok' else d::text end
     from f, lateral (select pg_temp.detalle_rechazo(f.ep_la, f.b) d) q));

-- ───────── La ficha (PATCH de vendedor_id, lo que hace store.reasignar) ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.err('S1: la ficha le cambia el responsable a LA (en gestión) → P0409', 'P0409',
  format('update crm.leads set vendedor_id = %L where id = %L', (select b from f), (select la from f)));
select pg_temp.err('S1: la ficha le cambia el responsable a LB (sin seguimiento) → pasa', 'paso',
  format('update crm.leads set vendedor_id = %L where id = %L', (select a from f), (select lb from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso = 'S1: la ficha le cambia el responsable a LA (en gestión) → P0409';
select set_config('crm.op_base_gestion', 'off', true);
set local session_replication_role = replica;  -- deja LB como estaba (de B) para los casos siguientes
update crm.leads set vendedor_id = (select b from f) where id = (select lb from f);
set local session_replication_role = origin;

-- ───────── «Tomar lead libre»: otro analista no se lleva un lead en gestión ─────────
select pg_temp.sesion((select b from f)); set local role authenticated;
select pg_temp.err('B toma LA por su teléfono (en gestión de A) → P0409', 'P0409',
  format('select crm.tomar_lead_libre(%L, %L)', (select tel_la from f), (select dni_la from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'B toma LA%';
-- Lo que recibe B (que no ve LA): solo estado y fecha, ni el lead ni su analista.
create function pg_temp.detalle_toma(p_tel text, p_dni text) returns jsonb language plpgsql as $$
declare d text; m text;
begin
  perform crm.tomar_lead_libre(p_tel, p_dni);
  return '{"estado":"paso"}'::jsonb;
exception when others then
  get stacked diagnostics d = pg_exception_detail, m = message_text;
  return coalesce(nullif(d, '')::jsonb, '{}'::jsonb) || pg_catalog.jsonb_build_object('_sqlstate', sqlstate, '_mensaje', m);
end $$;
grant execute on function pg_temp.detalle_toma(text,text) to authenticated;
select pg_temp.sesion((select b from f)); set local role authenticated;
select pg_temp.caso('B por «tomar lead libre»: P0409 sin lead_id ni nombres en mensaje y detail', 'ok',
  (select case when j->>'_sqlstate' = 'P0409' and not (j ? 'lead_id') and j->>'estado' = 'en_gestion'
                    and position('BANCO' in j::text) = 0 and position((select la::text from f) in j::text) = 0 then 'ok' else j::text end
     from (select pg_temp.detalle_toma((select tel_la from f), (select dni_la from f)) j) q));
reset role;
select pg_temp.caso('tras el intento de B, LA sigue descartado y de A', 'descartado/A', (select etapa || '/' || case when vendedor_id = f.a then 'A' else 'otro' end from crm.leads, f where id = f.la));

-- ───────── Una baja libera: dueño inactivo → sin seguimiento ─────────
set local session_replication_role = replica;
update crm.equipo set activo = false where perfil_id = (select a from f);
set local session_replication_role = origin;
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: con A dado de baja, LA vuelve a ser elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;
set local session_replication_role = replica;
update crm.equipo set activo = true where perfil_id = (select a from f);
set local session_replication_role = origin;

-- ───────── Al día 8 sin otro intento, vuelve ─────────
update crm.actividades set creado_en = creado_en - interval '8 days' where lead_id = (select la from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: intento de hace 8 días → vuelve a ser elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_la from f)));
reset role;
update crm.actividades set creado_en = creado_en + interval '1 day' where lead_id = (select la from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: intento de hace 7 días → hoy es su último día en gestión', (select format('false|BANCO VENDEDOR|%s|pendiente', hoy) from f), pg_temp.fila((select ep_la from f)));
reset role;

-- ───────── Rellamada vigente (pregunta 1 de Miguel: también cuenta) ─────────
select pg_temp.sesion((select c from f)); set local role authenticated;
select crm.registrar_intento_base(gen_random_uuid(), (select lc from f), 'volver_a_llamar', 'llamar el lunes', now() + interval '9 days');
reset role;
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: LC con rellamada a 9 días → gris hasta el día de la rellamada (más lejos que +7)',
  (select format('false|BANCO VENDEDOR C|%s|pendiente', ((now() + interval '9 days') at time zone 'America/Lima')::date) from f), pg_temp.fila((select ep_lc from f)));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.caso('G: LC también en gris para gerencia', (select format('false|BANCO VENDEDOR C|%s|pendiente', ((now() + interval '9 days') at time zone 'America/Lima')::date) from f), pg_temp.fila((select ep_lc from f)));
reset role;
update crm.actividades set creado_en = creado_en - interval '20 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select set_config('crm.op_base_gestion', 'on', true);  -- el sello solo deja escribir la rellamada al núcleo
update crm.leads set proxima_llamada_en = now() - interval '2 days' where id = (select lc from f);
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: rellamada vencida hace 2 días y sin intento reciente → elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lc from f)));
reset role;
select set_config('crm.op_base_gestion', 'on', true);  -- el sello solo deja escribir la rellamada al núcleo
update crm.leads set proxima_llamada_en = now() + interval '3 days' where id = (select lc from f);
select set_config('crm.op_base_gestion', 'off', true);
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: solo la rellamada vigente (intento viejo) → gris', 'false', split_part(pg_temp.fila((select ep_lc from f)), '|', 1));
reset role;
select pg_temp.sesion((select g from f)); set local role authenticated;
select pg_temp.err('G: repartir LC (rellamada vigente) a OTRO analista → P0409', 'P0409', format('select crm.rescatar_descartes(array[%L]::uuid[], array[%L]::uuid[])', (select ep_lc from f), (select a from f)));
reset role;
update r set obtenido = split_part(obtenido, ' ', 1) where caso like 'G: repartir LC%';
-- Una rellamada que quedó de un ciclo ANTERIOR (sin intento en este ciclo) no bloquea:
update crm.actividades set creado_en = creado_en - interval '30 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: rellamada vigente pero de un ciclo anterior (sin intento en este) → elegible', 'true|-|-|pendiente', pg_temp.fila((select ep_lc from f)));
reset role;


-- ───────── La regla no se expone ─────────
select pg_temp.caso('authenticated sin EXECUTE sobre la ayudante', 'false', has_function_privilege('authenticated', 'private.base_gestion_en_gestion_hasta(uuid)', 'EXECUTE')::text);
select pg_temp.caso('anon sin EXECUTE sobre la ayudante', 'false', has_function_privilege('anon', 'private.base_gestion_en_gestion_hasta(uuid)', 'EXECUTE')::text);
-- NO se prueba llamándola sin permiso: en la imagen Supabase 17.6 eso tumba el backend (memoria
-- postgres-cae-por-permiso-de-funcion, 20/08). Bastan los has_function_privilege de arriba.
select pg_temp.caso('ayudante: lead no descartado → NULL', 'null', coalesce(private.base_gestion_en_gestion_hasta((select id from crm.leads where etapa <> 'descartado' limit 1))::text, 'null'));

-- ───────── Sin seguimiento, el reparto sigue funcionando ─────────
select pg_temp.sesion((select s1 from f)); set local role authenticated;
select pg_temp.caso('S1: repartir LB (sin seguimiento) a A → 1 rescatado', '1', (crm.rescatar_descartes(array[(select ep_lb from f)], array[(select a from f)]))->>'rescatados');
reset role;

-- ───────── B5: el mes del lead ─────────
select pg_temp.sesion((select a from f)); set local role authenticated;
select pg_temp.caso('B5: A ve recibido_en = coalesce(tenencia_desde, creado_en) en su base', 'ok',
  (select case when bool_and(b.recibido_en is not distinct from coalesce(l.tenencia_desde, l.creado_en)) and count(*) > 0 then 'ok' else 'mal' end
     from crm.obtener_base_gestion() b join crm.leads l on l.id = b.lead_id));
reset role;
select pg_temp.caso('B3c+B5+B6: ninguna pieza del módulo está en el censo analítico', '0',
  (select count(*)::text from private.contadores_crudos_leads_citas() c
    where c.objeto ~ '^(crm|private)\.(obtener_base_gestion|base_gestion_[a-z_]+|rescate_descartes_mes|trg_leads_guard_seguimiento_activo|trg_actividades_enfriamiento_base)\('));

-- ───────── Límite aceptado: devolverlo a su MISMO analista no es reasignar ─────────
-- (el gris impide elegirlo en pantalla; por la RPC, con evitar origen = false, el candado no salta porque el dueño no cambia)
update crm.actividades set creado_en = creado_en + interval '30 days' where lead_id = (select lc from f) and metadata->>'evento' = 'intento_base';
select pg_temp.sesion((select s2 from f)); set local role authenticated;
select pg_temp.caso('S2: LC vuelve a estar en gris (intento del ciclo + rellamada vigente)', 'false', split_part(pg_temp.fila((select ep_lc from f)), '|', 1));
select pg_temp.caso('S2: devolver LC a su MISMO analista C (evitar origen = false) → pasa: el dueño no cambia', '1',
  (crm.rescatar_descartes(array[(select ep_lc from f)], array[(select c from f)], false))->>'rescatados');
reset role;

-- ───────── Resultado ─────────
update r set ok = coalesce(obtenido = esperado, false);  -- Codex 03/10: un NULL no es PASS
select format('%s %s · esperado %s · obtenido %s', case when ok is true then 'PASS' else 'FAIL' end, caso, esperado, left(obtenido, 200)) from r order by n;
select format('TOTAL: %s PASS · %s FAIL', count(*) filter (where ok), count(*) filter (where ok is not true)) from r;
do $$ begin if exists (select 1 from r where ok is not true) then raise exception 'B6: hay casos FAIL'; end if; end $$;
rollback;
