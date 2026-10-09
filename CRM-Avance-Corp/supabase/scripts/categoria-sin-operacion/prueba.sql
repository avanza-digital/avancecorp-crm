-- prueba.sql — Sin operación de cartera, solo 'nuevo' (migración 20261009180000). SOLO banco local de Docker. Termina en ROLLBACK.
--
-- Corre sobre el mundo de categoria-por-operacion/banco/mundo.sql (estado de producción del 08/10) con 20261009120000 y
-- 20261009180000 aplicadas, como el superusuario del stack local (cambia de rol con SET LOCAL ROLE y fija los claims del
-- JWT para cada actor). Cada caso se anota; al final, si alguno falla, `raise exception 'PRUEBA SIN OPERACION FALLA: …'`
-- (mutantes.py lo busca). Los intentos que podrían escribir se hacen con pr_intentar(), que deshace SIEMPRE lo que hizo.
--
-- Bloques: C catálogo · N sin operación (toda vía: SQL directo, «Corregir» del portal y de Gerencia, un BEFORE ajeno) ·
-- O con operación (igual que antes) · R RLS (el admin del portal no ve las operaciones y la guarda, DEFINER, sí) ·
-- P la puerta de Gerencia (sin cambios) · Y el alta normal y el cinturón del alta ·
-- K producto de CATÁLOGO · S sincronización (la operación llega después y la guarda la ve) · y aparte, en su propia
-- transacción REPEATABLE READ, F (el rechazo de aislamiento 25001 sigue primero).
-- Mundo: K1 'nuevo' + op upgrade (PDF sellado) · K4 'nuevo' sin op · K5 'upgrade' + op upgrade · K6 'upgrade' SIN op
-- (como los 106 antiguos) · K7 'nuevo' sin op (PDF sellado) · K10 'nuevo' sin op (con contrato de origen).
begin isolation level read committed;
set local statement_timeout = '300s';
set local lock_timeout = '10s';

do $guardia$
begin
  if coalesce(current_setting('app.settings.jwt_secret', true), '') <> 'super-secret-jwt-token-with-at-least-32-characters-long' then
    raise exception 'prueba.sql solo corre en un banco LOCAL de Docker';
  end if;
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is null
     or not exists (select 1 from pg_proc p where p.oid = to_regprocedure('private.trg_contrato_categoria_por_operacion()')
                     and p.prosrc like '%20261009180000%') then
    raise exception 'prueba.sql: faltan las migraciones 20261009120000 y 20261009180000';
  end if;
  if (select string_agg(c.numero_contrato || '=' || coalesce(c.categoria, 'vacía') || '/' ||
                        (exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id))::text,
                        ',' order by c.numero_contrato)
        from public.contratos c where c.numero_contrato in ('CAT-K4', 'CAT-K5', 'CAT-K6', 'CAT-K7', 'CAT-K10'))
     is distinct from 'CAT-K10=nuevo/false,CAT-K4=nuevo/false,CAT-K5=upgrade/true,CAT-K6=upgrade/false,CAT-K7=nuevo/false' then
    raise exception 'prueba.sql: falta el mundo (categoria-por-operacion/banco/mundo.sql) o no está en su estado inicial';
  end if;
end $guardia$;

create temporary table pr_casos (n serial primary key, caso text not null, ok boolean not null, detalle text) on commit drop;

create function pg_temp.pr_anotar(p_caso text, p_ok boolean, p_detalle text default null) returns void
language sql as $f$ insert into pg_temp.pr_casos (caso, ok, detalle) values (p_caso, coalesce(p_ok, false), p_detalle) $f$;

-- Ejecuta p_sql (que devuelve UNA columna jsonb) como p_actor con el rol p_rol (null = superusuario del banco).
create function pg_temp.pr_correr(p_actor uuid, p_rol text, p_sql text, out estado text, out resultado jsonb, out mensaje text)
language plpgsql as $f$
begin
  perform set_config('request.jwt.claims',
    case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', coalesce(p_rol, 'authenticated'))::text end, true);
  perform set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true);
  begin
    if p_rol is not null then
      execute format('set local role %I', p_rol);
    end if;
    execute p_sql into resultado;
    estado := '00000';
    execute 'reset role';
  exception when others then
    estado := sqlstate;
    mensaje := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $f$;

-- Ejecuta p_sql y DESHACE siempre lo que haya hecho; devuelve su sqlstate ('00000' si no falló).
create function pg_temp.pr_intentar(p_sql text) returns jsonb
language plpgsql as $f$
declare
  v_estado text;
begin
  begin
    execute p_sql;
    v_estado := '00000';
    raise exception using errcode = 'P0001', message = 'pr_deshacer';
  exception when others then
    if v_estado = '00000' and sqlerrm = 'pr_deshacer' then
      return to_jsonb('00000'::text);
    end if;
    return to_jsonb(sqlstate::text || ' · ' || sqlerrm);
  end;
end $f$;

-- Caso que espera un sqlstate y CONSERVA el efecto si pasa (para los éxitos que se revisan después).
create function pg_temp.pr_espera(p_caso text, p_actor uuid, p_rol text, p_sql text, p_esperado text, p_mensaje text default null) returns jsonb
language plpgsql as $f$
declare r record;
begin
  select * into r from pg_temp.pr_correr(p_actor, p_rol, p_sql);
  perform pg_temp.pr_anotar(p_caso, r.estado = p_esperado and (p_mensaje is null or strpos(coalesce(r.mensaje, ''), p_mensaje) > 0),
    format('esperado %s%s · obtenido %s%s', p_esperado, coalesce(' «' || p_mensaje || '»', ''), r.estado, coalesce(' · ' || r.mensaje, '')));
  return r.resultado;
end $f$;

-- Caso que espera un sqlstate y DESHACE siempre el intento.
create function pg_temp.pr_espera_deshacer(p_caso text, p_actor uuid, p_rol text, p_sql text, p_esperado text, p_mensaje text default null) returns void
language plpgsql as $f$
declare r record; v_obtenido text;
begin
  select * into r from pg_temp.pr_correr(p_actor, p_rol, format('select pg_temp.pr_intentar(%L)', p_sql));
  v_obtenido := case when r.estado <> '00000' then r.estado || ' · ' || coalesce(r.mensaje, '') else r.resultado #>> '{}' end;
  perform pg_temp.pr_anotar(p_caso, split_part(v_obtenido, ' · ', 1) = p_esperado and (p_mensaje is null or strpos(v_obtenido, p_mensaje) > 0),
    format('esperado %s%s · obtenido %s', p_esperado, coalesce(' «' || p_mensaje || '»', ''), v_obtenido));
end $f$;

-- Pone en orden las categorías p_pasos (un elemento NULL = vacía) con un UPDATE directo; con p_pdf, abre antes la
-- congelación del PDF SOLO para ese contrato. Falla si el contrato no existe (así un «pasa» prueba que la fila cambió).
create function pg_temp.pr_categoria(p_id uuid, p_pasos text[], p_pdf boolean default false) returns jsonb
language plpgsql as $f$
declare v text;
begin
  if p_pdf then
    perform set_config('crm.contrato_pdf_revision_autorizada', p_id::text, true);
  end if;
  foreach v in array p_pasos loop
    update public.contratos set categoria = v where id = p_id;
    if not found then
      raise exception 'pr_categoria: no existe el contrato %', p_id using errcode = 'P0002';
    end if;
  end loop;
  if p_pdf then
    perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
  end if;
  return '{}'::jsonb;
end $f$;

-- Dispara AHORA los triggers diferidos pendientes (observador de rentabilidad, cinturón del alta) y vuelve a diferirlos.
create function pg_temp.pr_disparar_diferidos() returns jsonb
language plpgsql as $f$
begin
  set constraints all immediate;
  set constraints all deferred;
  return '{}'::jsonb;
end $f$;

-- INSERT directo de un contrato 'upgrade' SIN operación y, enseguida, lo que pasaría al confirmar (el cinturón del alta).
create function pg_temp.pr_alta_upgrade_sin_operacion() returns jsonb
language plpgsql as $f$
begin
  insert into public.contratos (numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                                fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
  values ('CAT-SINOP-Y3', 'ca7e0000-0000-4000-8000-000000000110', 30000, 'PEN', 15, 'mensual', 'simple',
          date '2026-10-06', date '2027-10-06', 'activo', 'upgrade',
          'ca7e0000-0000-4000-8000-00000000000b', 'ca7e0000-0000-4000-8000-000000000003');
  set constraints all immediate;
  set constraints all deferred;
  return '{}'::jsonb;
end $f$;

-- ── C · Catálogo: la guarda conserva dueño, seguridad, search_path y permisos; trigger y piezas vecinas sin cambios ─────
do $c$
begin
  perform pg_temp.pr_anotar('C1 la guarda: dueño postgres, SECURITY DEFINER, search_path vacío y solo postgres la ejecuta',
    exists (select 1 from pg_proc p where p.oid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure
             and p.proowner = 'postgres'::regrole and p.prosecdef and p.proconfig = array['search_path=""']
             and p.proacl::text = '{postgres=X/postgres}'));
  perform pg_temp.pr_anotar('C2 anon, authenticated y service_role no ejecutan la guarda',
    not has_function_privilege('anon', 'private.trg_contrato_categoria_por_operacion()'::regprocedure, 'execute')
    and not has_function_privilege('authenticated', 'private.trg_contrato_categoria_por_operacion()'::regprocedure, 'execute')
    and not has_function_privilege('service_role', 'private.trg_contrato_categoria_por_operacion()'::regprocedure, 'execute'));
  perform pg_temp.pr_anotar('C3 el trigger sigue igual: AFTER UPDATE por fila, WHEN la categoría cambió, habilitado',
    exists (select 1 from pg_trigger t where t.tgrelid = 'public.contratos'::regclass
             and t.tgname = 'trg_contratos_01_categoria_por_operacion' and t.tgenabled = 'O' and t.tgtype = 17
             and t.tgattr::text = '' and pg_get_triggerdef(t.oid) like '%WHEN ((old.categoria IS DISTINCT FROM new.categoria))%'
             and t.tgfoid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure));
  perform pg_temp.pr_anotar('C4 las 6 piezas vecinas siguen con su cuerpo (md5 de prosrc medido en el banco = producción)',
    (select count(*) from pg_proc p join (values
       ('private.trg_operacion_cartera_fija_categoria()', 'ea9e412c6cc2fe5ef60136bca86c927f'),
       ('private.fijar_categoria_contrato(uuid,text,text,text,uuid)', '09f95007689ce1712ab164b1181f635d'),
       ('crm.corregir_categoria_contrato_fn(uuid,text,text)', '343be63ecd244de16ede8bf092d893df'),
       ('public.crear_contrato(jsonb,jsonb)', '1adfbe1a72739a1863c7321c3fd20439'),
       ('private.trg_contratos_producto_snapshot()', '4ae4d7a3ece48641f0ee12eb2df2e8fd'),
       ('public.actualizar_contrato(uuid,jsonb,jsonb)', 'db2e6d36d46c72250fd6f42022af80be')) as v(firma, huella)
       on p.oid = to_regprocedure(v.firma) and md5(p.prosrc) = v.huella) = 6);
end $c$;

-- ── N · Sin operación de cartera: solo 'nuevo' (o vacía), por TODA vía ──────────────────────────────────────────────────
do $n$
declare
  ad constant uuid := 'ca7e0000-0000-4000-8000-00000000000b';
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
  k7 constant uuid := 'ca7e0000-0000-4000-8000-000000002007';
  c_sin_op constant text := 'Un contrato sin operación de cartera solo puede quedar como nuevo';
  v_detalle text;
  v_pista text;
  v_estado text;
begin
  -- SQL directo como superusuario (la vía con más poder): K4 es 'nuevo' y no tiene operación.
  perform pg_temp.pr_espera_deshacer('N1 K4 sin operación: nuevo → upgrade → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array['upgrade']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N2 K4 sin operación: nuevo → renovacion → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array['renovacion']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N3 K4 sin operación: nuevo → vacía → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array[null]::text[]), '00000');
  perform pg_temp.pr_espera_deshacer('N4 K4 sin operación: vacía → upgrade → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array[null, 'upgrade']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N4b K4 sin operación: vacía → renovacion → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array[null, 'renovacion']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N4c K4 sin operación: vacía → nuevo → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array[null, 'nuevo']), '00000');
  -- K6: 'upgrade' antiguo sin operación (como los 106 de marzo a julio). Vuelve a 'nuevo' o a vacía; no cambia a otra.
  perform pg_temp.pr_espera_deshacer('N5 K6 antiguo sin operación: upgrade → nuevo → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k6, array['nuevo']), '00000');
  perform pg_temp.pr_espera_deshacer('N6 K6 antiguo sin operación: upgrade → renovacion → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k6, array['renovacion']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N7 K6 antiguo sin operación: upgrade → vacía → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k6, array[null]::text[]), '00000');
  perform pg_temp.pr_espera_deshacer('N8 K6 antiguo sin operación: upgrade → upgrade (sin cambio) → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k6, array['upgrade']), '00000');
  perform pg_temp.pr_espera_deshacer('N9 K6 antiguo: editar sus notas pasa (los existentes no se tocan)', null, null,
    format($q$update public.contratos set notas_internas = 'nota de K6' where id = %L$q$, k6), '00000');
  perform pg_temp.pr_espera_deshacer('N9b K4: editar sus notas pasa', null, null,
    format($q$update public.contratos set notas_internas = 'nota de K4' where id = %L$q$, k4), '00000');
  -- K7 tiene el PDF sellado: con la congelación abierta solo para él, la guarda rechaza; sin abrirla, el PDF va antes.
  perform pg_temp.pr_espera_deshacer('N10 K7 (PDF sellado, congelación abierta): nuevo → upgrade → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L, true)', k7, array['upgrade']), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N10b K7 sin abrir la congelación: nuevo → upgrade → 55000 (el PDF, BEFORE, va antes)', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k7, array['upgrade']), '55000', 'Los términos del contrato están congelados por su PDF legal');
  -- «Corregir» del portal (crm.actualizar_numero_contrato_pdf_v3 y public.actualizar_numero_contrato) y de Gerencia
  -- (public.actualizar_contrato, la que usa contrato-corregir.tsx del CRM).
  perform pg_temp.pr_espera_deshacer('N11 «Corregir» del portal (pdf_v3) K4 a upgrade → 23514', ad, 'authenticated',
    format('select crm.actualizar_numero_contrato_pdf_v3(%L, %L, null, %L)', k4, 'CAT-K4', 'upgrade'), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N11b «Corregir» del portal (actualizar_numero_contrato) K4 a renovacion → 23514', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, null, %L)', k4, 'CAT-K4', 'renovacion'), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N12 «Corregir» de Gerencia (public.actualizar_contrato) K4 a upgrade → 23514', g, 'authenticated',
    format('select public.actualizar_contrato(%L, %L::jsonb, null)', k4,
      jsonb_build_object('capital', 40000, 'tasa_anual', 16, 'modalidad', 'mensual', 'tipo_interes', 'simple', 'moneda', 'PEN',
                         'fecha_inicio', date '2026-09-15', 'fecha_vencimiento', date '2027-09-15', 'categoria', 'upgrade')), '23514', c_sin_op);
  perform pg_temp.pr_espera_deshacer('N13 «Corregir» del portal K6 repitiendo upgrade (cambia el número) → pasa', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, %L, %L)', k6, 'CAT-K6-B', 'nota', 'upgrade'), '00000');
  perform pg_temp.pr_espera_deshacer('N14 «Corregir» del portal K6 a nuevo → pasa', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, null, %L)', k6, 'CAT-K6', 'nuevo'), '00000');

  -- N15: el error explica qué pasa y qué hacer (detail y hint).
  begin
    perform pg_temp.pr_categoria(k4, array['upgrade']);
    v_estado := '00000';
  exception when others then
    get stacked diagnostics v_estado = returned_sqlstate, v_detalle = pg_exception_detail, v_pista = pg_exception_hint;
  end;
  perform pg_temp.pr_anotar('N15 el 23514 trae detail con la categoría pedida y hint con la cartera del cliente',
    v_estado = '23514'
    and v_detalle = 'El contrato no tiene operación de cartera; su categoría no puede pasar a upgrade.'
    and v_pista = 'Una renovación o un upgrade se registran desde la cartera del cliente, que crea su operación.',
    format('%s · %s · %s', v_estado, v_detalle, v_pista));

  -- N16: otro trigger BEFORE (de prueba, solo en esta transacción) pone 'upgrade' aunque el UPDATE no nombre la categoría:
  -- la guarda es AFTER y por fila, así que mira la fila FINAL y la rechaza.
  create function private.prueba_sin_op_forzada() returns trigger language plpgsql as $f$
  begin
    if coalesce(current_setting('prueba.forzar_categoria', true), '') <> '' then
      new.categoria := current_setting('prueba.forzar_categoria', true);
    end if;
    return new;
  end $f$;
  create trigger trg_contratos_zz_prueba_sin_op before update on public.contratos
    for each row execute function private.prueba_sin_op_forzada();
  perform set_config('prueba.forzar_categoria', 'upgrade', true);
  perform pg_temp.pr_espera_deshacer('N16 un BEFORE ajeno pone upgrade en K4 al editar sus notas → 23514 (la guarda ve la fila final)', null, null,
    format($q$update public.contratos set notas_internas = 'nota con categoría forzada' where id = %L$q$, k4), '23514', c_sin_op);
  perform set_config('prueba.forzar_categoria', '', true);
  drop trigger trg_contratos_zz_prueba_sin_op on public.contratos;
  drop function private.prueba_sin_op_forzada();

  perform pg_temp.pr_anotar('N17 K4 y K6 siguen como estaban (nada de lo anterior quedó escrito)',
    (select string_agg(numero_contrato || '=' || coalesce(categoria, 'vacía'), ',' order by numero_contrato)
       from public.contratos where id in (k4, k6)) = 'CAT-K4=nuevo,CAT-K6=upgrade');
end $n$;

-- ── O · Con operación de cartera: igual que antes («la operación decide») ────────────────────────────────────────────
do $o$
declare
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
  k5 constant uuid := 'ca7e0000-0000-4000-8000-000000002005';
  c_op constant text := 'La categoría la decide la operación de cartera';
begin
  perform pg_temp.pr_espera_deshacer('O1 K5 con operación upgrade: → nuevo → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k5, array['nuevo']), '23514', c_op);
  perform pg_temp.pr_espera_deshacer('O2 K5 con operación upgrade: → renovacion → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k5, array['renovacion']), '23514', c_op);
  perform pg_temp.pr_espera_deshacer('O3 K5 con operación upgrade: → vacía → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k5, array[null]::text[]), '23514', c_op);
  perform pg_temp.pr_espera_deshacer('O4 K1 (nuevo + operación upgrade, congelación abierta): → renovacion → 23514', null, null,
    format('select pg_temp.pr_categoria(%L, %L, true)', k1, array['renovacion']), '23514', c_op);
  perform pg_temp.pr_espera_deshacer('O5 K1: → upgrade (la de su operación) → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L, true)', k1, array['upgrade']), '00000');
  perform pg_temp.pr_espera_deshacer('O6 K5: editar sus notas pasa', null, null,
    format($q$update public.contratos set notas_internas = 'nota de K5' where id = %L$q$, k5), '00000');
end $o$;

-- ── R · RLS: la guarda (SECURITY DEFINER) VE la operación aunque quien edita no pueda leerla ──────────────────────────
-- El admin del portal edita contratos como `authenticated` (política contratos_admin_actualiza) y la RLS le oculta
-- crm.operaciones_cartera. Fixture (solo en esta transacción): un contrato 'nuevo', legacy y sin PDF, con su operación
-- upgrade insertada SIN sincronizar (el estado de los 12 antes de 2-REAL).
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                              fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
values ('ca7e0000-0000-4000-8000-0000000030b1', 'CAT-SINOP-RLS', 'ca7e0000-0000-4000-8000-000000000110', 30000, 'PEN', 15,
        'mensual', 'simple', date '2026-09-24', date '2027-09-24', 'activo', 'nuevo',
        'ca7e0000-0000-4000-8000-00000000000b', 'ca7e0000-0000-4000-8000-000000000003');
set local session_replication_role = replica;
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion, periodo, moneda,
                                     elegible_conversion, desglose_completo, fuente, creado_por)
select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial,
       date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, true, true, 'flujo_cartera', 'ca7e0000-0000-4000-8000-00000000000b'
  from public.contratos c where c.id = 'ca7e0000-0000-4000-8000-0000000030b1';
set local session_replication_role = origin;

do $r$
declare
  ad constant uuid := 'ca7e0000-0000-4000-8000-00000000000b';
  kr constant uuid := 'ca7e0000-0000-4000-8000-0000000030b1';
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k5 constant uuid := 'ca7e0000-0000-4000-8000-000000002005';
  v jsonb;
begin
  v := pg_temp.pr_espera('R0 el admin del portal NO ve la operación de esos contratos (RLS)', ad, 'authenticated',
    format('select to_jsonb(count(*)) from crm.operaciones_cartera where contrato_nuevo_id in (%L, %L)', kr, k5), '00000');
  perform pg_temp.pr_anotar('R0b … pero sí puede editar la categoría (y las operaciones existen)',
    v = to_jsonb(0)
    and (select count(*) from crm.operaciones_cartera o where o.contrato_nuevo_id in (kr, k5) and o.tipo = 'upgrade') = 2
    and has_column_privilege('authenticated', 'public.contratos', 'categoria', 'UPDATE'), coalesce(v::text, 'sin respuesta'));
  perform pg_temp.pr_espera_deshacer('R1 el admin del portal pasa a upgrade el contrato con operación upgrade que no ve → pasa', ad, 'authenticated',
    format('select pg_temp.pr_categoria(%L, %L)', kr, array['upgrade']), '00000');
  perform pg_temp.pr_espera_deshacer('R2 el admin del portal pasa K5 (operación upgrade que no ve) a nuevo → 23514', ad, 'authenticated',
    format('select pg_temp.pr_categoria(%L, %L)', k5, array['nuevo']), '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera_deshacer('R3 el admin del portal pasa K4 (sin operación) a upgrade → 23514', ad, 'authenticated',
    format('select pg_temp.pr_categoria(%L, %L)', k4, array['upgrade']), '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
end $r$;

-- ── P · La puerta de Gerencia, sin cambios ────────────────────────────────────────────────────────────────────────────
do $p$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  vend constant uuid := 'ca7e0000-0000-4000-8000-000000000003';
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k5 constant uuid := 'ca7e0000-0000-4000-8000-000000002005';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
  q constant text := 'select crm.corregir_categoria_contrato_fn(%L, %L, %L)';
begin
  perform pg_temp.pr_espera_deshacer('P1 la puerta: K4 sin operación a upgrade → 23514 (el núcleo, mismo texto)', g, 'authenticated',
    format(q, k4, 'upgrade', 'Prueba sin operación'), '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
  perform pg_temp.pr_espera_deshacer('P2 la puerta: K6 antiguo sin operación a nuevo → pasa', g, 'authenticated',
    format(q, k6, 'nuevo', 'Prueba sin operación'), '00000');
  perform pg_temp.pr_espera_deshacer('P3 la puerta: K1 a upgrade (la de su operación) → pasa', g, 'authenticated',
    format(q, k1, 'upgrade', 'Prueba sin operación'), '00000');
  perform pg_temp.pr_espera_deshacer('P4 la puerta: K5 con operación a nuevo → 23514', g, 'authenticated',
    format(q, k5, 'nuevo', 'Prueba sin operación'), '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera_deshacer('P5 la puerta: un vendedor → 42501', vend, 'authenticated',
    format(q, k4, 'nuevo', 'Prueba sin operación'), '42501', 'Solo Gerencia puede corregir la categoría');
end $p$;

-- ── Y · El alta normal (public.crear_contrato) inserta el contrato y DESPUÉS su operación: la guarda (de UPDATE) no la
--    toca; el cinturón del alta sigue exigiendo la operación al confirmar ───────────────────────────────────────────────
do $y_alta$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  v jsonb;
  v_id uuid;
begin
  perform set_config('crm.rentabilidad_origen_upgrade', 'ca7e0000-0000-4000-8000-00000000010e|ca7e0000-0000-4000-8000-00000000110e', true);
  v := pg_temp.pr_espera('Y1 alta de upgrade por public.crear_contrato → pasa', g, 'authenticated',
    $q$select public.crear_contrato(
         jsonb_build_object('cliente_id', 'ca7e0000-0000-4000-8000-00000000010e', 'numero_contrato', 'CAT-SINOP-Y1', 'capital', 30000,
                            'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple',
                            'fecha_inicio', (now() at time zone 'America/Lima')::date,
                            'fecha_vencimiento', ((now() at time zone 'America/Lima')::date + interval '12 months')::date,
                            'categoria', 'upgrade'),
         jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', ((now() at time zone 'America/Lima')::date + 30), 'monto_programado', 375)))$q$,
    '00000');
  v_id := (v ->> 'id')::uuid;
  perform pg_temp.pr_anotar('Y1b el alta quedó upgrade, con su operación upgrade y SIN fila de sincronización',
    (select c.categoria from public.contratos c where c.id = v_id) = 'upgrade'
    and exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id and o.tipo = 'upgrade')
    and not exists (select 1 from public.audit_log a where a.tabla = 'contratos.categoria' and a.fila_id = v_id::text), coalesce(v::text, 'sin id'));
  perform pg_temp.pr_espera('Y1c el cinturón y el observador del alta corren sin error', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');
  perform set_config('crm.rentabilidad_origen_upgrade', '', true);

  v := pg_temp.pr_espera('Y2 alta de renovación por public.crear_contrato → pasa', g, 'authenticated',
    $q$select public.crear_contrato(
         jsonb_build_object('cliente_id', 'ca7e0000-0000-4000-8000-000000000115', 'numero_contrato', 'CAT-SINOP-Y2', 'capital', 35000,
                            'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple',
                            'fecha_inicio', date '2026-10-05', 'fecha_vencimiento', date '2027-10-05', 'categoria', 'renovacion',
                            'contrato_origen_id', 'ca7e0000-0000-4000-8000-000000001115', 'capital_renovado', 30000, 'capital_adicional', 5000),
         jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', date '2026-11-05', 'monto_programado', 437.5)))$q$,
    '00000');
  v_id := (v ->> 'id')::uuid;
  perform pg_temp.pr_anotar('Y2b la renovación quedó renovacion, con su operación y SIN fila de sincronización',
    (select c.categoria from public.contratos c where c.id = v_id) = 'renovacion'
    and exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id and o.tipo = 'renovacion')
    and not exists (select 1 from public.audit_log a where a.tabla = 'contratos.categoria' and a.fila_id = v_id::text), coalesce(v::text, 'sin id'));
  perform pg_temp.pr_espera('Y2c el cinturón y el observador del alta corren sin error', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');

  -- Un INSERT directo de un 'upgrade' sin operación no pasa por la guarda (es de UPDATE): lo para el cinturón al confirmar.
  perform pg_temp.pr_espera_deshacer('Y3 INSERT directo de un upgrade SIN operación → 23514 del cinturón al confirmar', null, null,
    'select pg_temp.pr_alta_upgrade_sin_operacion()', '23514', 'Una renovación o upgrade debe registrarse por el flujo de cartera');
end $y_alta$;

-- ── K · Producto de CATÁLOGO (fixture solo en esta transacción) ───────────────────────────────────────────────────────
-- El producto y su versión publicada nacen sin el flujo de publicación (fixture fuera de banda, como las personas de
-- mundo.sql); el contrato nace por la vía normal con la condición de catálogo 'nuevo'.
set local session_replication_role = replica;
insert into crm.productos_inversion (id, codigo, estado)
values ('ca7e0000-0000-4000-8000-0000000030a1', 'PRUEBA-SIN-OPERACION', 'activo');
insert into crm.producto_versiones (id, producto_id, numero_version, estado, nombre, vigente_desde, publicada_en)
values ('ca7e0000-0000-4000-8000-0000000030a2', 'ca7e0000-0000-4000-8000-0000000030a1', 1, 'publicada',
        'Catálogo de prueba sin operación', date '2026-01-01', now());
insert into crm.producto_condiciones (id, version_id, orden, categoria, moneda, plazo_meses, modalidad, tipo_interes,
                                      capital_minimo, capital_maximo, tasa_referencia, tasa_minima, tasa_maxima)
values ('ca7e0000-0000-4000-8000-0000000030a3', 'ca7e0000-0000-4000-8000-0000000030a2', 1, 'nuevo', 'PEN', 12, 'mensual', 'simple',
        1000, 1000000, 15, 10, 20),
       ('ca7e0000-0000-4000-8000-0000000030a4', 'ca7e0000-0000-4000-8000-0000000030a2', 2, 'upgrade', 'PEN', 12, 'mensual', 'simple',
        1000, 1000000, 15, 10, 20);
set local session_replication_role = origin;
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                              fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id, producto_condicion_id)
values ('ca7e0000-0000-4000-8000-0000000030a5', 'CAT-SINOP-CATALOGO', 'ca7e0000-0000-4000-8000-000000000110', 30000, 'PEN', 15,
        'mensual', 'simple', date '2026-10-01', date '2027-10-01', 'activo', 'nuevo',
        'ca7e0000-0000-4000-8000-00000000000b', 'ca7e0000-0000-4000-8000-000000000003', 'ca7e0000-0000-4000-8000-0000000030a3');

do $k$
declare
  kc constant uuid := 'ca7e0000-0000-4000-8000-0000000030a5';
begin
  perform pg_temp.pr_anotar('K0 el contrato de catálogo nació nuevo, con su condición de catálogo y sin operación',
    exists (select 1 from public.contratos c join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
             where c.id = kc and c.categoria = 'nuevo' and not pc.es_legacy and pc.categoria = 'nuevo')
    and not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = kc));
  perform pg_temp.pr_espera_deshacer('K1 catálogo: nuevo → upgrade con la misma condición → 23514 de SU trigger de producto (BEFORE, antes)', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', kc, array['upgrade']), '23514', 'Los términos del contrato no cumplen la condición seleccionada');
  perform pg_temp.pr_espera_deshacer('K2 catálogo: elegir la condición de upgrade (el producto lo deja) → 23514 de la guarda', null, null,
    format($q$update public.contratos set categoria = 'upgrade', producto_condicion_id = 'ca7e0000-0000-4000-8000-0000000030a4' where id = %L$q$, kc),
    '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
  perform pg_temp.pr_espera_deshacer('K3 catálogo: editar sus notas pasa', null, null,
    format($q$update public.contratos set notas_internas = 'nota del contrato de catálogo' where id = %L$q$, kc), '00000');
end $k$;

-- ── S · Sincronización: la operación llega DESPUÉS sobre un contrato sin operación; la guarda ya la ve y deja pasar la
--    categoría de la operación (molde del backfill B: INSERT directo de la operación) ──────────────────────────────────
do $s$
declare
  ad constant uuid := 'ca7e0000-0000-4000-8000-00000000000b';
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
  k7 constant uuid := 'ca7e0000-0000-4000-8000-000000002007';
  k10 constant uuid := 'ca7e0000-0000-4000-8000-00000000200a';
  c_op constant text := $q$with o as (insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_origen_id,
                contrato_nuevo_id, fecha_operacion, periodo, moneda, capital_renovado, capital_adicional, elegible_conversion,
                desglose_completo, fuente, creado_por)
              select c.cliente_id, c.analista_cierre_id, %L, %L, c.id, c.fecha_cierre_comercial,
                     date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, %s, %s, true, true, 'flujo_cartera', %L
                from public.contratos c where c.id = %L returning id) select to_jsonb(o.id) from o$q$;
  v_motivo public.audit_log%rowtype;
begin
  perform pg_temp.pr_espera('S1 operación upgrade sobre K7 (nuevo, sin operación, PDF sellado) → entra', null, null,
    format(c_op, 'upgrade', null, 'null', 'null', ad, k7), '00000');
  select * into v_motivo from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k7::text;
  perform pg_temp.pr_anotar('S1b K7 quedó upgrade con UNA fila de motivo de la sincronización (vía operacion_de_cartera)',
    (select categoria from public.contratos where id = k7) = 'upgrade'
    and (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k7::text) = 1
    and v_motivo.data_antes ->> 'categoria' = 'nuevo' and v_motivo.data_despues ->> 'via' = 'operacion_de_cartera',
    coalesce(row_to_json(v_motivo)::text, 'sin fila'));
  perform pg_temp.pr_espera('S2 operación de renovación sobre K10 (nuevo, sin operación) → entra', null, null,
    format(c_op, 'renovacion', 'ca7e0000-0000-4000-8000-000000001114', '30000', '5000', ad, k10), '00000');
  perform pg_temp.pr_anotar('S2b K10 quedó renovacion', (select categoria from public.contratos where id = k10) = 'renovacion');
  perform pg_temp.pr_espera('S3 operación upgrade sobre K6 (ya upgrade, sin operación: camino que coincide) → entra', null, null,
    format(c_op, 'upgrade', null, 'null', 'null', ad, k6), '00000');
  perform pg_temp.pr_anotar('S3b K6 sigue upgrade y sin fila de motivo (no hubo nada que escribir)',
    (select categoria from public.contratos where id = k6) = 'upgrade'
    and not exists (select 1 from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k6::text));
  -- K4: primero vacía (sin operación, se permite) y después llega su operación: de vacía a upgrade CON operación sí.
  perform pg_temp.pr_espera('S4 K4 sin operación pasa a vacía → pasa', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k4, array[null]::text[]), '00000');
  perform pg_temp.pr_espera('S4b operación upgrade sobre K4 (vacía) → entra', null, null,
    format(c_op, 'upgrade', null, 'null', 'null', ad, k4), '00000');
  perform pg_temp.pr_anotar('S4c K4 quedó upgrade con su fila de motivo («sin categoría» → upgrade)',
    (select categoria from public.contratos where id = k4) = 'upgrade'
    and exists (select 1 from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k4::text
                 and x.data_antes ->> 'categoria' is null and x.data_despues ->> 'categoria' = 'upgrade'));
  -- Y ya con operación, K6 no puede volver a 'nuevo' (manda la operación).
  perform pg_temp.pr_espera_deshacer('S5 K6 ya con operación upgrade: → nuevo → 23514 (manda la operación)', null, null,
    format('select pg_temp.pr_categoria(%L, %L)', k6, array['nuevo']), '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera('S6 los observadores de todo lo anterior corren sin error', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');
end $s$;

-- ── Veredicto ─────────────────────────────────────────────────────────────────────────────────────────────────────────
select n, caso, case when ok then 'OK' else 'FALLA' end as resultado, case when ok then '' else detalle end as detalle
  from pg_temp.pr_casos order by n;
do $veredicto$
declare
  v_total int;
  v_fallos int;
  v_lista text;
begin
  select count(*), count(*) filter (where not ok),
         string_agg(caso || ' [' || coalesce(detalle, '') || ']', ' | ' order by n) filter (where not ok)
    into v_total, v_fallos, v_lista
    from pg_temp.pr_casos;
  if v_fallos > 0 then
    raise exception 'PRUEBA SIN OPERACION FALLA: % de % casos: %', v_fallos, v_total, v_lista;
  end if;
  raise notice 'PRUEBA SIN OPERACION OK: % de % casos', v_total, v_total;
end $veredicto$;
select 'PRUEBA SIN OPERACION OK' as veredicto, count(*) as casos from pg_temp.pr_casos;
rollback;

-- ── F · Aislamiento: en REPEATABLE READ, la guarda responde 25001 ANTES de mirar la regla nueva ────────────────────────
-- Una transacción aparte, REPEATABLE READ, que también se deshace.
begin isolation level repeatable read;
create function pg_temp.rr_intento(p_sql text, out estado text, out mensaje text) language plpgsql as $f$
begin
  execute p_sql;
  estado := '00000';
  mensaje := '';
exception when others then
  estado := sqlstate;
  mensaje := sqlerrm;
end $f$;
do $rr$
declare
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
  c_rr constant text := 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED';
  r record;
  v_casos jsonb := '[]'::jsonb;
  v_fallos text;
begin
  -- F1 K4 sin operación a upgrade: 25001, no 23514 (el aislamiento va primero).
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set categoria = 'upgrade' where id = %L$q$, k4));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F1', 'K4 sin operación a upgrade', r.estado, r.mensaje, '25001', c_rr));
  -- F2 K6 antiguo a nuevo (en READ COMMITTED pasaría): 25001.
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set categoria = 'nuevo' where id = %L$q$, k6));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2', 'K6 sin operación a nuevo', r.estado, r.mensaje, '25001', c_rr));
  -- F3 editar las notas de K4 en REPEATABLE READ (la categoría no cambia): pasa.
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set notas_internas = 'nota bajo REPEATABLE READ' where id = %L$q$, k4));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F3', 'editar las notas de K4', r.estado, r.mensaje, '00000', ''));

  select string_agg(format('%s %s [esperado %s «%s» · obtenido %s «%s»]', x ->> 0, x ->> 1, x ->> 4, x ->> 5, x ->> 2, x ->> 3), ' | ')
    into v_fallos
    from jsonb_array_elements(v_casos) x
   where x ->> 2 is distinct from x ->> 4 or strpos(x ->> 3, x ->> 5) = 0;
  if v_fallos is not null then
    raise exception 'PRUEBA SIN OPERACION FALLA: aislamiento — %', v_fallos;
  end if;
  raise notice 'PRUEBA AISLAMIENTO SIN OPERACION OK: % casos (K4 a upgrade y K6 a nuevo: 25001; notas: pasa)', jsonb_array_length(v_casos);
end $rr$;
rollback;
select 'PRUEBA AISLAMIENTO SIN OPERACION OK' as aislamiento;
