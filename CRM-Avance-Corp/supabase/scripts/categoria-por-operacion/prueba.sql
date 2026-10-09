-- prueba.sql — Categoría por operación (migración 20261009120000). SOLO banco local de Docker. Termina en ROLLBACK.
--
-- Corre sobre el mundo de banco/mundo.sql (estado de producción del 08/10) con la migración aplicada, como el
-- superusuario del stack local (cambia de rol con SET LOCAL ROLE y fija los claims del JWT para cada actor).
-- Cada caso se anota; al final, si alguno falla, `raise exception 'PRUEBA CATEGORIA FALLA: …'` (mutantes.py lo busca).
-- Los intentos que podrían escribir se hacen con pr_intentar(), que deshace SIEMPRE lo que el intento haya hecho.
--
-- Bloques: C catálogo · A autoridad · M/I datos · S sellado · R respaldo · E eliminación · Y alta y sincronización ·
-- D la puerta con éxito (auditoría, PDF, congelación, idempotencia, producto, libro de rentabilidad en observación y en
-- enforcement, declaración de origen pendiente repuesta y vacía durante el UPDATE) · P prevención (toda vía, también si
-- otro BEFORE cambia la categoría) · y aparte, en su propia transacción REPEATABLE READ, F2 (aislamiento: la puerta, la
-- sincronización por sus dos caminos y la guarda con y sin operación responden 25001; editar otra cosa pasa).
-- P3 mira qué guarda hay puesta: desde 20261009180000 (categoria-sin-operacion) un contrato sin operación solo puede
-- volver a 'nuevo', así que su cambio a 'renovacion' espera 23514; con la guarda de 20261009120000, «pasa».
-- R6/R7 (desde 20261009180000 la guarda rechaza lo mismo que el respaldo del núcleo, con el mismo texto): la puerta
-- rechaza ANTES de intentar el UPDATE (un BEFORE de prueba delata cualquier UPDATE); así el mutante M2 sigue muriendo.
-- Las carreras entre dos conexiones (bloqueo de la fila en la sincronización, orden mes→fila, día comercial que cambia,
-- foto REPEATABLE READ frente a la guarda, guiones bajo REPEATABLE READ y frente a un sello o un alta a medias) están en
-- concurrencia.py.
begin isolation level read committed;
set local statement_timeout = '300s';
set local lock_timeout = '10s';

do $guardia$
begin
  if coalesce(current_setting('app.settings.jwt_secret', true), '') <> 'super-secret-jwt-token-with-at-least-32-characters-long' then
    raise exception 'prueba.sql solo corre en un banco LOCAL de Docker';
  end if;
  if to_regprocedure('crm.corregir_categoria_contrato_fn(uuid,text,text)') is null then
    raise exception 'prueba.sql: falta la migración 20261009120000';
  end if;
  if not exists (select 1 from public.contratos where id = 'ca7e0000-0000-4000-8000-000000002001' and categoria = 'nuevo') then
    raise exception 'prueba.sql: falta el mundo (banco/mundo.sql) o ya no está en su estado inicial';
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

-- Dispara AHORA los triggers diferidos pendientes (observador de rentabilidad, cinturón del alta) y vuelve a diferirlos.
create function pg_temp.pr_disparar_diferidos() returns jsonb
language plpgsql as $f$
begin
  set constraints all immediate;
  set constraints all deferred;
  return '{}'::jsonb;
end $f$;

create function pg_temp.pr_num(p_sql text) returns numeric language plpgsql as $f$
declare v numeric; begin execute p_sql into v; return v; end $f$;
create function pg_temp.pr_txt(p_sql text) returns text language plpgsql as $f$
declare v text; begin execute p_sql into v; return v; end $f$;

-- ── C · Catálogo ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $c$
begin
  perform pg_temp.pr_anotar('C1 anon no ejecuta la puerta',
    not has_function_privilege('anon', 'crm.corregir_categoria_contrato_fn(uuid,text,text)'::regprocedure, 'execute'));
  perform pg_temp.pr_anotar('C2 authenticated no ejecuta el núcleo ni los triggers',
    not has_function_privilege('authenticated', 'private.fijar_categoria_contrato(uuid,text,text,text,uuid)'::regprocedure, 'execute')
    and not has_function_privilege('authenticated', 'private.trg_operacion_cartera_fija_categoria()'::regprocedure, 'execute')
    and not has_function_privilege('authenticated', 'private.trg_contrato_categoria_por_operacion()'::regprocedure, 'execute'));
  perform pg_temp.pr_anotar('C3 ACL exacta de la puerta',
    (select p.proacl::text from pg_proc p where p.oid = 'crm.corregir_categoria_contrato_fn(uuid,text,text)'::regprocedure)
      = '{postgres=X/postgres,authenticated=X/postgres}');
end $c$;

-- ── A · Autoridad: nadie fuera de Gerencia vigente (K1 queda intacto) ──────────────────────────────────────────────────
do $a$
declare
  q constant text := $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'upgrade', 'Prueba de autoridad del banco')$q$;
begin
  perform pg_temp.pr_espera('A1 anon → 42501', null, 'anon', q, '42501', 'permission denied');
  perform pg_temp.pr_espera('A2 vendedor → 42501', 'ca7e0000-0000-4000-8000-000000000003', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A3 supervisor → 42501', 'ca7e0000-0000-4000-8000-000000000002', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A4 coordinador → 42501', 'ca7e0000-0000-4000-8000-000000000009', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A5 gerencia con la membresía revocada → 42501', 'ca7e0000-0000-4000-8000-00000000000a', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A6 admin del portal sin equipo → 42501', 'ca7e0000-0000-4000-8000-00000000000b', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A7 directorio → 42501', 'ca7e0000-0000-4000-8000-00000000000c', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A8 authenticated sin sesión → 42501', null, 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_espera('A9 perfil vendedor de PRUEBAS (mismo nombre que Gerencia) → 42501', 'd731f284-eeaa-4c27-b71f-ac4f1d8e96c2', 'authenticated', q, '42501', 'Solo Gerencia puede corregir la categoría');
  perform pg_temp.pr_anotar('A10 K1 sigue en nuevo y sin fila de motivo',
    (select categoria from public.contratos where id = 'ca7e0000-0000-4000-8000-000000002001') = 'nuevo'
    and not exists (select 1 from public.audit_log where tabla = 'contratos.categoria' and fila_id = 'ca7e0000-0000-4000-8000-000000002001'));
end $a$;

-- ── M/I · Datos de entrada (como Gerencia) ────────────────────────────────────────────────────────────────────────────
do $m$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
begin
  perform pg_temp.pr_espera('M1 motivo nulo → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'upgrade', null)$q$, '22023', 'El motivo debe tener entre 5 y 300 caracteres');
  perform pg_temp.pr_espera('M2 motivo de 4 caracteres → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'upgrade', 'abcd')$q$, '22023', 'El motivo debe tener entre 5 y 300 caracteres');
  perform pg_temp.pr_espera('M3 motivo de 301 caracteres → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'upgrade', repeat('x', 301))$q$, '22023', 'El motivo debe tener entre 5 y 300 caracteres');
  perform pg_temp.pr_espera('M4 motivo en blanco → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'upgrade', '        ')$q$, '22023', 'El motivo debe tener entre 5 y 300 caracteres');
  perform pg_temp.pr_espera('I1 categoría inválida → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'otra', 'Motivo de prueba')$q$, '22023', 'La categoría debe ser nuevo, renovacion o upgrade');
  perform pg_temp.pr_espera('I2 categoría nula → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', null, 'Motivo de prueba')$q$, '22023', 'La categoría debe ser nuevo, renovacion o upgrade');
  perform pg_temp.pr_espera('I3 contrato inexistente → P0002', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-0000000020ff', 'nuevo', 'Motivo de prueba')$q$, 'P0002', 'Contrato no encontrado');
  perform pg_temp.pr_espera('I4 contrato nulo → 22023', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn(null, 'nuevo', 'Motivo de prueba')$q$, '22023', 'El contrato es obligatorio');
end $m$;

-- ── S/R/E · Sellado, respaldo y eliminación ──────────────────────────────────────────────────────────────────────────
do $s$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  v jsonb;
begin
  perform pg_temp.pr_espera('S1 K3 de agosto (sellado) → P0409', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002003', 'upgrade', 'Upgrade registrado como nuevo')$q$, 'P0409', 'No se puede reescribir un mes comercial sellado');
  perform pg_temp.pr_espera('R1 K4 sin operación a upgrade → 23514', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002004', 'upgrade', 'Sin respaldo de cartera')$q$, '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
  perform pg_temp.pr_espera('R2 K1 con operación upgrade a renovacion → 23514', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'renovacion', 'La operación dice otra cosa')$q$, '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera('R3 K5 upgrade coherente a nuevo → 23514', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002005', 'nuevo', 'Quitarle el upgrade')$q$, '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera('E1 K9 en proceso de eliminación → 55000', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002009', 'upgrade', 'Upgrade registrado como nuevo')$q$, '55000', 'El contrato está en proceso de eliminación');
  -- Un contrato antiguo sin operación (upgrade de julio, p. ej.) sí puede volver a nuevo; motivo de 300 caracteres (borde).
  v := pg_temp.pr_espera('R4 K6 antiguo sin operación a nuevo (motivo de 300) → pasa', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002006', 'nuevo', repeat('m', 300))$q$, '00000');
  perform pg_temp.pr_anotar('R5 K6 quedó en nuevo, cambio = true y sin operación en la respuesta',
    (select categoria from public.contratos where id = 'ca7e0000-0000-4000-8000-000000002006') = 'nuevo'
    and (v ->> 'cambio')::boolean and (v ->> 'operacion_id') is null, coalesce(v::text, 'sin respuesta'));
end $s$;

-- ── R6/R7 · El respaldo del NÚCLEO rechaza ANTES de intentar el UPDATE ──────────────────────────────────────────────
-- Desde 20261009180000 la guarda también rechaza, con el mismo texto, lo que el respaldo rechaza (toda vía): R1–R3 ya no
-- distinguen quién lo hizo. Un BEFORE de prueba (solo en esta transacción) delata cualquier UPDATE que llegue: la puerta
-- tiene que contestar con su 23514 sin escribir ni disparar nada (ni la foto de producto ni el PDF).
do $r_primera$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
begin
  create function private.prueba_detectar_update() returns trigger language plpgsql as $f$
  begin
    if coalesce(current_setting('prueba.detectar_update', true), '') = 'on' then
      raise exception 'prueba: la puerta llegó al UPDATE' using errcode = 'P0001';
    end if;
    return new;
  end $f$;
  create trigger trg_contratos_zz_prueba_detectar before update on public.contratos
    for each row execute function private.prueba_detectar_update();
  perform set_config('prueba.detectar_update', 'on', true);
  perform pg_temp.pr_espera_deshacer('R6 K4 sin operación a upgrade: la puerta rechaza ANTES del UPDATE (respaldo del núcleo)', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002004', 'upgrade', 'Sin respaldo de cartera')$q$,
    '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
  perform pg_temp.pr_espera_deshacer('R7 K1 con operación upgrade a renovacion: la puerta rechaza ANTES del UPDATE', g, 'authenticated',
    $q$select crm.corregir_categoria_contrato_fn('ca7e0000-0000-4000-8000-000000002001', 'renovacion', 'La operación dice otra cosa')$q$,
    '23514', 'La categoría la decide la operación de cartera');
  perform set_config('prueba.detectar_update', '', true);
  drop trigger trg_contratos_zz_prueba_detectar on public.contratos;
  drop function private.prueba_detectar_update();
end $r_primera$;

-- ── P7 · La ventana entre la migración y 2-REAL: «Corregir» un contrato todavía incoherente (K1: nuevo + op upgrade)
--    SIN cambiar su categoría tiene que pasar; la prevención solo mira cuando la categoría CAMBIA.
do $p_ventana$
declare
  ad constant uuid := 'ca7e0000-0000-4000-8000-00000000000b';
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
begin
  perform pg_temp.pr_espera_deshacer('P7 «Corregir» K1 incoherente sin tocar la categoría (p_categoria nula) pasa', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, %L, null)', k1, 'CAT-K1', 'nota de la ventana'), '00000');
  perform pg_temp.pr_espera_deshacer('P7b «Corregir» K1 incoherente repitiendo su categoría (nuevo) pasa', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, %L, %L)', k1, 'CAT-K1', 'nota de la ventana', 'nuevo'), '00000');
end $p_ventana$;

-- ── Y · El alta normal no cambia (public.crear_contrato) y no toca la declaración de origen del upgrade ─────────────────
do $y_alta$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  v_declaracion constant text := 'ca7e0000-0000-4000-8000-00000000010e|ca7e0000-0000-4000-8000-00000000110e';
  v jsonb;
  v_id uuid;
begin
  -- Lo que hace crm.crear_contrato_con_cuenta_pdf_v2 antes de bajar a public.crear_contrato: publicar el origen del upgrade.
  perform set_config('crm.rentabilidad_origen_upgrade', v_declaracion, true);
  v := pg_temp.pr_espera('Y3 alta de upgrade por public.crear_contrato → pasa', g, 'authenticated',
    $q$select public.crear_contrato(
         jsonb_build_object('cliente_id', 'ca7e0000-0000-4000-8000-00000000010e', 'numero_contrato', 'CAT-Y3', 'capital', 30000,
                            'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple',
                            'fecha_inicio', (now() at time zone 'America/Lima')::date,
                            'fecha_vencimiento', ((now() at time zone 'America/Lima')::date + interval '12 months')::date,
                            'categoria', 'upgrade'),
         jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', ((now() at time zone 'America/Lima')::date + 30), 'monto_programado', 375)))$q$,
    '00000');
  v_id := (v ->> 'id')::uuid;
  perform pg_temp.pr_anotar('Y3b el alta de upgrade quedó upgrade, con su operación y SIN fila de sincronización',
    (select c.categoria from public.contratos c where c.id = v_id) = 'upgrade'
    and exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id and o.tipo = 'upgrade')
    and not exists (select 1 from public.audit_log a where a.tabla = 'contratos.categoria' and a.fila_id = v_id::text), coalesce(v::text, 'sin id'));
  perform pg_temp.pr_anotar('Y5 la sincronización no tocó la declaración de origen del alta (sigue publicada hasta el commit)',
    current_setting('crm.rentabilidad_origen_upgrade', true) = v_declaracion, current_setting('crm.rentabilidad_origen_upgrade', true));
  perform pg_temp.pr_espera('Y5b el observador de rentabilidad del alta corre sin error', null, null,
    'select pg_temp.pr_disparar_diferidos()', '00000');
  perform pg_temp.pr_anotar('Y5c el libro del alta guarda el contrato de origen declarado',
    exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = v_id
             and l.contrato_origen_id = 'ca7e0000-0000-4000-8000-00000000110e'));

  v := pg_temp.pr_espera('Y4 alta de renovación por public.crear_contrato → pasa', g, 'authenticated',
    $q$select public.crear_contrato(
         jsonb_build_object('cliente_id', 'ca7e0000-0000-4000-8000-000000000115', 'numero_contrato', 'CAT-Y4', 'capital', 35000,
                            'moneda', 'PEN', 'tasa_anual', 15, 'modalidad', 'mensual', 'tipo_interes', 'simple',
                            'fecha_inicio', date '2026-10-05', 'fecha_vencimiento', date '2027-10-05', 'categoria', 'renovacion',
                            'contrato_origen_id', 'ca7e0000-0000-4000-8000-000000001115', 'capital_renovado', 30000, 'capital_adicional', 5000),
         jsonb_build_array(jsonb_build_object('numero_cuota', 1, 'fecha_programada', date '2026-11-05', 'monto_programado', 437.5)))$q$,
    '00000');
  v_id := (v ->> 'id')::uuid;
  perform pg_temp.pr_anotar('Y4b la renovación quedó renovacion, con su operación y SIN fila de sincronización',
    (select c.categoria from public.contratos c where c.id = v_id) = 'renovacion'
    and exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = v_id and o.tipo = 'renovacion')
    and not exists (select 1 from public.audit_log a where a.tabla = 'contratos.categoria' and a.fila_id = v_id::text), coalesce(v::text, 'sin id'));
  perform pg_temp.pr_espera('Y4c el cinturón y el observador del alta corren sin error', null, null,
    'select pg_temp.pr_disparar_diferidos()', '00000');
end $y_alta$;

-- ── D · La puerta con éxito sobre K1 (como uno de los 12: nuevo + op upgrade, PDF sellado, producto legacy) ─────────────
create temporary table pr_k1_antes on commit drop as
select c.*,
       (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = c.id) as jobs,
       (select count(*) from private.contrato_pdfs p where p.contrato_id = c.id) as pdfs,
       (select count(*) from public.audit_log a where a.tabla = 'contratos' and a.fila_id = c.id::text) as audit_fila,
       (select count(*) from crm.ledger_rentabilidad l where l.contrato_id = c.id) as libro,
       (select o.id from crm.operaciones_cartera o where o.contrato_nuevo_id = c.id) as operacion_id
  from public.contratos c where c.id = 'ca7e0000-0000-4000-8000-000000002001';

do $d$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
  c_motivo constant text := 'Upgrade registrado como nuevo: la operación de cartera manda (banco)';
  a record;
  v jsonb;
  v_motivo public.audit_log%rowtype;
  v_audit public.audit_log%rowtype;
begin
  select * into a from pg_temp.pr_k1_antes;
  v := pg_temp.pr_espera('D1 Gerencia corrige K1 a upgrade → pasa', g, 'authenticated',
    format('select crm.corregir_categoria_contrato_fn(%L, %L, %L)', k1, 'upgrade', c_motivo), '00000');
  perform pg_temp.pr_anotar('D1b respuesta: cambio, de nuevo a upgrade, con la operación',
    (v ->> 'cambio')::boolean and v ->> 'categoria_anterior' = 'nuevo' and v ->> 'categoria' = 'upgrade'
    and (v ->> 'operacion_id')::uuid = a.operacion_id, coalesce(v::text, 'sin respuesta'));
  perform pg_temp.pr_anotar('D1c K1 quedó en upgrade',
    (select categoria from public.contratos where id = k1) = 'upgrade');

  -- Auditoría: la fila general del UPDATE y UNA fila hermana con el motivo.
  select * into v_audit from public.audit_log x
   where x.tabla = 'contratos' and x.fila_id = k1::text and x.operacion = 'UPDATE' order by x.ts desc limit 1;
  perform pg_temp.pr_anotar('D2 trg_audit_contratos guardó el UPDATE (nuevo → upgrade) a nombre de Gerencia',
    (select count(*) from public.audit_log x where x.tabla = 'contratos' and x.fila_id = k1::text) = a.audit_fila + 1
    and v_audit.data_antes ->> 'categoria' = 'nuevo' and v_audit.data_despues ->> 'categoria' = 'upgrade' and v_audit.usuario_id = g);
  select * into v_motivo from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k1::text;
  perform pg_temp.pr_anotar('D2b una sola fila de motivo, con el motivo, la vía, la operación y Gerencia',
    (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k1::text) = 1
    and v_motivo.operacion = 'UPDATE' and v_motivo.usuario_id = g
    and v_motivo.data_antes ->> 'categoria' = 'nuevo' and v_motivo.data_despues ->> 'categoria' = 'upgrade'
    and v_motivo.data_despues ->> 'motivo' = c_motivo and v_motivo.data_despues ->> 'via' = 'puerta'
    and (v_motivo.data_despues ->> 'operacion_id')::uuid = a.operacion_id, coalesce(row_to_json(v_motivo)::text, 'sin fila'));

  -- PDF: sigue sellado, sin trabajos ni archivos nuevos.
  perform pg_temp.pr_anotar('D3 el PDF sigue sellado: 0 trabajos y 0 archivos nuevos',
    (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = k1) = a.jobs
    and (select count(*) from private.contrato_pdfs p where p.contrato_id = k1) = a.pdfs
    and (select j.estado || '/' || j.revision from private.contrato_pdf_jobs j where j.contrato_id = k1 order by j.revision desc limit 1) = 'sellado/1');

  -- La congelación quedó CERRADA: el GUC vacío y un cambio de términos de K1 vuelve a chocar con el PDF (55000).
  perform pg_temp.pr_anotar('D4 la congelación quedó cerrada (GUC vacío)',
    coalesce(current_setting('crm.contrato_pdf_revision_autorizada', true), '') = '',
    current_setting('crm.contrato_pdf_revision_autorizada', true));
  perform pg_temp.pr_espera_deshacer('D4b cambiar el capital de K1 después de la puerta → 55000', null, null,
    format('update public.contratos set capital = capital + 1 where id = %L', k1), '55000', 'Los términos del contrato están congelados por su PDF legal');

  -- Idempotencia: misma categoría → cambio = false y nada escrito.
  v := pg_temp.pr_espera('D5 segunda corrección igual → pasa', g, 'authenticated',
    format('select crm.corregir_categoria_contrato_fn(%L, %L, %L)', k1, 'upgrade', c_motivo), '00000');
  perform pg_temp.pr_anotar('D5b cambio = false y ni una fila más en la bitácora',
    not coalesce((v ->> 'cambio')::boolean, true)
    and (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k1::text) = 1
    and (select count(*) from public.audit_log x where x.tabla = 'contratos' and x.fila_id = k1::text) = a.audit_fila + 1,
    coalesce(v::text, 'sin respuesta'));

  -- Producto: el puente legacy hizo otra foto (categoría upgrade) del mismo contrato; los demás términos, intactos.
  perform pg_temp.pr_anotar('D6 producto legacy: foto nueva con categoría upgrade para K1',
    exists (select 1 from public.contratos c join crm.producto_condiciones pc on pc.id = c.producto_condicion_id
             where c.id = k1 and c.producto_condicion_id <> a.producto_condicion_id
               and pc.es_legacy and pc.categoria = 'upgrade' and pc.legacy_contrato_id = k1));
  perform pg_temp.pr_anotar('D7 la puerta solo cambió la categoría (capital, tasa, moneda, fechas, analista, día comercial)',
    exists (select 1 from public.contratos c where c.id = k1
             and (c.capital, c.tasa_anual, c.moneda, c.fecha_inicio, c.fecha_vencimiento, c.analista_cierre_id,
                  c.fecha_cierre_comercial, c.fuente_cierre_comercial, c.numero_contrato, c.cliente_id, c.estado, c.es_demo)
               = (a.capital, a.tasa_anual, a.moneda, a.fecha_inicio, a.fecha_vencimiento, a.analista_cierre_id,
                  a.fecha_cierre_comercial, a.fuente_cierre_comercial, a.numero_contrato, a.cliente_id, a.estado, a.es_demo)));

  -- Libro de rentabilidad en OBSERVACIÓN: el observador corre (sin P0410) y deja UNA fila más, sin origen declarado.
  perform pg_temp.pr_espera('D8 observador en observación sin P0410', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');
  perform pg_temp.pr_anotar('D8b una fila más en el libro: upgrade, sin contrato de origen, origen observacion',
    (select count(*) from crm.ledger_rentabilidad l where l.contrato_id = k1) = a.libro + 1
    and exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = k1 and l.categoria = 'upgrade'
                 and l.contrato_origen_id is null and l.origen = 'observacion'));
end $d$;

-- Libro en ENFORCEMENT. D9: con una declaración de origen de OTRO cliente pendiente en la sesión (la de un alta de la
-- misma transacción, por ejemplo): la puerta no la pierde (la repone tal cual) y el observador no la usa para K2.
-- D10: en modo INMEDIATO (el observador corre al final del UPDATE, dentro del núcleo) y con una declaración del MISMO
-- cliente pendiente: durante el UPDATE está vacía, así que la corrección no hereda tasa (sin P0410) y después se repone.
do $d_enf$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  k2 constant uuid := 'ca7e0000-0000-4000-8000-000000002002';
  c1401 constant uuid := 'ca7e0000-0000-4000-8000-000000001203';    -- 2026-01-001401: tasa 24, cliente 3 (su anterior: 15)
  c_otra constant text := 'ca7e0000-0000-4000-8000-00000000010b|ca7e0000-0000-4000-8000-00000000110b';   -- cliente de K1
  c_misma constant text := 'ca7e0000-0000-4000-8000-000000000103|ca7e0000-0000-4000-8000-000000001103';  -- cliente de 001401
  v_jobs bigint := (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = 'ca7e0000-0000-4000-8000-000000002002');
begin
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota)
  select p.version + 1, p.id, now(), 15, 25, 1, 'enforcement', 'prueba.sql: enforcement'
    from crm.politica_rentabilidad p order by p.version desc limit 1;
  perform set_config('crm.rentabilidad_origen_upgrade', c_otra, true);
  perform pg_temp.pr_espera('D9 Gerencia corrige K2 a upgrade bajo enforcement → pasa', g, 'authenticated',
    format('select crm.corregir_categoria_contrato_fn(%L, %L, %L)', k2, 'upgrade', 'Upgrade registrado como nuevo (enforcement)'), '00000');
  perform pg_temp.pr_anotar('D9e la puerta repuso la declaración de origen pendiente tal cual (no la pierde)',
    current_setting('crm.rentabilidad_origen_upgrade', true) = c_otra, current_setting('crm.rentabilidad_origen_upgrade', true));
  perform pg_temp.pr_espera('D9b observador en enforcement sin P0410', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');
  perform pg_temp.pr_anotar('D9c el libro de K2: upgrade, enforcement y SIN origen (la declaración era de otro cliente)',
    exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = k2 and l.categoria = 'upgrade'
             and l.origen = 'enforcement' and l.contrato_origen_id is null)
    and not exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = k2 and l.contrato_origen_id is not null));
  perform pg_temp.pr_anotar('D9d el PDF pendiente de K2 sigue igual (0 trabajos nuevos)',
    (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = k2) = v_jobs
    and (select j.estado from private.contrato_pdf_jobs j where j.contrato_id = k2 order by j.revision desc limit 1) = 'pendiente');

  set constraints all immediate;
  perform set_config('crm.rentabilidad_origen_upgrade', c_misma, true);
  perform pg_temp.pr_espera('D10 en modo inmediato y con una declaración del MISMO cliente, la corrección de 001401 pasa sin P0410', g, 'authenticated',
    format('select crm.corregir_categoria_contrato_fn(%L, %L, %L)', c1401, 'upgrade', 'Upgrade registrado como nuevo (inmediato)'), '00000');
  perform pg_temp.pr_anotar('D10b el libro de 001401: upgrade, enforcement y SIN origen (la declaración estaba vacía durante el UPDATE)',
    exists (select 1 from crm.ledger_rentabilidad l where l.contrato_id = c1401 and l.categoria = 'upgrade'
             and l.origen = 'enforcement' and l.contrato_origen_id is null));
  perform pg_temp.pr_anotar('D10c después, la declaración del mismo cliente vuelve a estar como estaba',
    current_setting('crm.rentabilidad_origen_upgrade', true) = c_misma, current_setting('crm.rentabilidad_origen_upgrade', true));
  set constraints all deferred;
  perform set_config('crm.rentabilidad_origen_upgrade', '', true);
  -- De vuelta a observación para el resto.
  insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota)
  select p.version + 1, p.id, clock_timestamp(), 15, 25, 1, 'observacion', 'prueba.sql: observación'
    from crm.politica_rentabilidad p order by p.version desc limit 1;
end $d_enf$;

-- ── P · Prevención: ninguna vía deja la categoría distinta de la operación ─────────────────────────────────────────────
do $p$
declare
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  ad constant uuid := 'ca7e0000-0000-4000-8000-00000000000b';
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
  k5 constant uuid := 'ca7e0000-0000-4000-8000-000000002005';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
begin
  -- «Corregir» del portal/CRM por su puerta viva (abre la congelación y crea revisión de PDF): elegir 'nuevo' → 23514.
  perform pg_temp.pr_espera_deshacer('P1 «Corregir» (actualizar_numero_contrato_pdf_v3) K5 upgrade → nuevo → 23514', ad, 'authenticated',
    format('select crm.actualizar_numero_contrato_pdf_v3(%L, %L, null, %L)', k5, 'CAT-K5', 'nuevo'), '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera_deshacer('P1b «Corregir» (public.actualizar_contrato) de Gerencia, K5 a nuevo → 23514', g, 'authenticated',
    format('select public.actualizar_contrato(%L, %L::jsonb, null)', k5,
      jsonb_build_object('capital', 45000, 'tasa_anual', 16, 'modalidad', 'mensual', 'tipo_interes', 'simple', 'moneda', 'PEN',
                         'fecha_inicio', date '2026-09-16', 'fecha_vencimiento', date '2027-09-16', 'categoria', 'nuevo')), '23514', 'La categoría la decide la operación de cartera');
  perform set_config('crm.contrato_pdf_revision_autorizada', k1::text, true);   -- congelación abierta solo para K1
  perform pg_temp.pr_espera_deshacer('P2 UPDATE directo de K1 (op upgrade) a renovacion, con la congelación abierta → 23514', null, null,
    format($q$update public.contratos set categoria = 'renovacion' where id = %L$q$, k1), '23514', 'La categoría la decide la operación de cartera');
  perform pg_temp.pr_espera_deshacer('P2b UPDATE directo de K1 de vuelta a nuevo → 23514', null, null,
    format($q$update public.contratos set categoria = 'nuevo' where id = %L$q$, k1), '23514', 'La categoría la decide la operación de cartera');
  perform set_config('crm.contrato_pdf_revision_autorizada', '', true);
  -- P3 depende de la guarda puesta: hasta 20261009180000 un contrato sin operación cambiaba de categoría sin restricción;
  -- desde ella solo puede volver a 'nuevo' (o quedar vacío). Así la suite vale con las dos versiones de la guarda.
  if exists (select 1 from pg_proc x where x.oid = 'private.trg_contrato_categoria_por_operacion()'::regprocedure
              and x.prosrc like '%20261009180000%') then
    perform pg_temp.pr_espera_deshacer('P3 contrato antiguo sin operación (K6): a renovacion → 23514 (20261009180000: sin operación, solo nuevo)', null, null,
      format($q$update public.contratos set categoria = 'renovacion' where id = %L$q$, k6), '23514', 'Un contrato sin operación de cartera solo puede quedar como nuevo');
  else
    perform pg_temp.pr_espera_deshacer('P3 contrato antiguo sin operación (K6): cambiar la categoría no se restringe', null, null,
      format($q$update public.contratos set categoria = 'renovacion' where id = %L$q$, k6), '00000');
  end if;
  perform pg_temp.pr_espera_deshacer('P4 corregir otra cosa de K5 (notas) pasa', null, null,
    format($q$update public.contratos set notas_internas = 'nota de prueba' where id = %L$q$, k5), '00000');
  -- public.actualizar_numero_contrato (la que llama «Corregir»): su UPDATE pone categoria en el SET aunque no cambie.
  perform pg_temp.pr_espera_deshacer('P5 «Corregir» sin tocar la categoría (p_categoria nula) pasa', ad, null,
    format('select public.actualizar_numero_contrato(%L, %L, %L, null)', k5, 'CAT-K5', 'nota nueva'), '00000');
  perform pg_temp.pr_espera_deshacer('P6 K5 con categoría vacía (NULL) → 23514', null, null,
    format($q$update public.contratos set categoria = null where id = %L$q$, k5), '23514', 'La categoría la decide la operación de cartera');
  -- P8: otro trigger BEFORE (de prueba, solo en esta transacción) cambia la categoría aunque el UPDATE no la nombre: la
  --     guarda es AFTER y por fila, así que mira la fila FINAL y la rechaza.
  create function private.prueba_categoria_forzada() returns trigger language plpgsql as $f$
  begin
    if coalesce(current_setting('prueba.forzar_categoria', true), '') <> '' then
      new.categoria := current_setting('prueba.forzar_categoria', true);
    end if;
    return new;
  end $f$;
  create trigger trg_contratos_zz_prueba_forzada before update on public.contratos
    for each row execute function private.prueba_categoria_forzada();
  perform set_config('prueba.forzar_categoria', 'nuevo', true);
  perform pg_temp.pr_espera_deshacer('P8 un BEFORE ajeno cambia la categoría de K5 al editar sus notas → 23514 (la guarda ve la fila final)', null, null,
    format($q$update public.contratos set notas_internas = 'nota con categoría forzada' where id = %L$q$, k5), '23514', 'La categoría la decide la operación de cartera');
  perform set_config('prueba.forzar_categoria', '', true);
  drop trigger trg_contratos_zz_prueba_forzada on public.contratos;
  drop function private.prueba_categoria_forzada();
end $p$;

-- ── Y · Sincronización al registrar la operación (molde del backfill B: INSERT directo, sin tocar el contrato) ─────────
do $y$
declare
  k4 constant uuid := 'ca7e0000-0000-4000-8000-000000002004';
  k7 constant uuid := 'ca7e0000-0000-4000-8000-000000002007';
  k8 constant uuid := 'ca7e0000-0000-4000-8000-000000002008';
  k10 constant uuid := 'ca7e0000-0000-4000-8000-00000000200a';
  v_jobs_k7 bigint := (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = 'ca7e0000-0000-4000-8000-000000002007');
  v_op uuid;
  v_motivo public.audit_log%rowtype;
begin
  perform pg_temp.pr_espera('Y1 operación upgrade sobre K7 (nuevo, PDF sellado) → entra', null, null,
    format($q$with o as (insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion,
                periodo, moneda, elegible_conversion, desglose_completo, fuente, creado_por)
              select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial, date_trunc('month', c.fecha_cierre_comercial)::date,
                     c.moneda, true, true, 'flujo_cartera', 'ca7e0000-0000-4000-8000-00000000000b'
                from public.contratos c where c.id = %L returning id) select to_jsonb(o.id) from o$q$, k7), '00000');
  select o.id into v_op from crm.operaciones_cartera o where o.contrato_nuevo_id = k7;
  select * into v_motivo from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k7::text;
  perform pg_temp.pr_anotar('Y1b K7 quedó upgrade en la misma transacción', (select categoria from public.contratos where id = k7) = 'upgrade');
  perform pg_temp.pr_anotar('Y1c una fila de motivo de la sincronización (vía operacion_de_cartera, con la operación)',
    (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k7::text) = 1
    and v_motivo.data_antes ->> 'categoria' = 'nuevo' and v_motivo.data_despues ->> 'categoria' = 'upgrade'
    and v_motivo.data_despues ->> 'via' = 'operacion_de_cartera' and (v_motivo.data_despues ->> 'operacion_id')::uuid = v_op
    and length(v_motivo.data_despues ->> 'motivo') between 5 and 300, coalesce(row_to_json(v_motivo)::text, 'sin fila'));
  perform pg_temp.pr_anotar('Y1d el PDF de K7 sigue sellado sin trabajos nuevos y la congelación quedó cerrada',
    (select count(*) from private.contrato_pdf_jobs j where j.contrato_id = k7) = v_jobs_k7
    and (select j.estado from private.contrato_pdf_jobs j where j.contrato_id = k7 order by j.revision desc limit 1) = 'sellado'
    and coalesce(current_setting('crm.contrato_pdf_revision_autorizada', true), '') = '');
  perform pg_temp.pr_espera_deshacer('Y1e cambiar el capital de K7 después de la sincronización → 55000', null, null,
    format('update public.contratos set capital = capital + 1 where id = %L', k7), '55000', 'Los términos del contrato están congelados por su PDF legal');

  perform pg_temp.pr_espera('Y2 operación upgrade sobre K8 de agosto (sellado) → P0409', null, null,
    format($q$with o as (insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion,
                periodo, moneda, elegible_conversion, desglose_completo, fuente, creado_por)
              select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial, date_trunc('month', c.fecha_cierre_comercial)::date,
                     c.moneda, true, true, 'flujo_cartera', 'ca7e0000-0000-4000-8000-00000000000b'
                from public.contratos c where c.id = %L returning id) select to_jsonb(o.id) from o$q$, k8), 'P0409', 'No se puede reescribir un mes comercial sellado');
  perform pg_temp.pr_anotar('Y2b K8 sigue en nuevo, sin operación y sin fila de motivo',
    (select categoria from public.contratos where id = k8) = 'nuevo'
    and not exists (select 1 from crm.operaciones_cartera o where o.contrato_nuevo_id = k8)
    and not exists (select 1 from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k8::text));

  perform pg_temp.pr_espera('Y7 operación de renovación sobre K10 (nuevo) → entra', null, null,
    format($q$with o as (insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id,
                fecha_operacion, periodo, moneda, capital_renovado, capital_adicional, elegible_conversion, desglose_completo, fuente, creado_por)
              select c.cliente_id, c.analista_cierre_id, 'renovacion', 'ca7e0000-0000-4000-8000-000000001114', c.id, c.fecha_cierre_comercial,
                     date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, 30000, 5000, true, true, 'flujo_cartera',
                     'ca7e0000-0000-4000-8000-00000000000b'
                from public.contratos c where c.id = %L returning id) select to_jsonb(o.id) from o$q$, k10), '00000');
  perform pg_temp.pr_anotar('Y7b K10 quedó renovacion, con su fila de motivo',
    (select categoria from public.contratos where id = k10) = 'renovacion'
    and (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k10::text) = 1);

  -- La operación es append-only; si algún día se permitiera moverla, el contrato al que pasa también toma su categoría.
  -- (Solo aquí, en el banco: se apaga el append-only DENTRO de esta transacción, que se deshace al final.)
  alter table crm.operaciones_cartera disable trigger trg_operaciones_cartera_00_append_only;
  perform pg_temp.pr_espera('Y6 mover la operación de K7 a K4 (UPDATE OF contrato_nuevo_id) → entra', null, null,
    format($q$with u as (update crm.operaciones_cartera set contrato_nuevo_id = %L where id = %L returning 1) select to_jsonb(count(*)) from u$q$, k4, v_op), '00000');
  alter table crm.operaciones_cartera enable trigger trg_operaciones_cartera_00_append_only;
  perform pg_temp.pr_anotar('Y6b K4 tomó la categoría de la operación (upgrade) con su fila de motivo',
    (select categoria from public.contratos where id = k4) = 'upgrade'
    and (select count(*) from public.audit_log x where x.tabla = 'contratos.categoria' and x.fila_id = k4::text) = 1);
  perform pg_temp.pr_espera('Y8 los observadores de todo lo anterior corren sin error', null, null, 'select pg_temp.pr_disparar_diferidos()', '00000');
end $y$;

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
    raise exception 'PRUEBA CATEGORIA FALLA: % de % casos: %', v_fallos, v_total, v_lista;
  end if;
  raise notice 'PRUEBA CATEGORIA OK: % de % casos', v_total, v_total;
end $veredicto$;
select 'PRUEBA CATEGORIA OK' as veredicto, count(*) as casos from pg_temp.pr_casos;
rollback;

-- ── F2 · Aislamiento: corregir, registrar una renovación/upgrade y cambiar una categoría, solo en READ COMMITTED ───────
-- Una transacción aparte, REPEATABLE READ, que también se deshace. Todos responden 25001 antes de leer o bloquear nada;
-- editar OTRA cosa del contrato en REPEATABLE READ sigue pasando (la guarda solo mira los cambios de categoría).
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
  g constant uuid := 'ca7e0000-0000-4000-8000-000000000001';
  k1 constant uuid := 'ca7e0000-0000-4000-8000-000000002001';
  k5 constant uuid := 'ca7e0000-0000-4000-8000-000000002005';
  k6 constant uuid := 'ca7e0000-0000-4000-8000-000000002006';
  k7 constant uuid := 'ca7e0000-0000-4000-8000-000000002007';
  c_op constant text := $q$insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_nuevo_id, fecha_operacion,
      periodo, moneda, elegible_conversion, desglose_completo, fuente, creado_por)
    select c.cliente_id, c.analista_cierre_id, 'upgrade', c.id, c.fecha_cierre_comercial, date_trunc('month', c.fecha_cierre_comercial)::date,
           c.moneda, true, true, 'flujo_cartera', 'ca7e0000-0000-4000-8000-00000000000b'
      from public.contratos c where c.id = %L$q$;
  r record;
  v_estado text;
  v_mensaje text;
  v_casos jsonb := '[]'::jsonb;
  v_fallos text;
begin
  -- F2a la puerta, sobre K1 (incoherente: habría que escribir) → 25001 del núcleo.
  perform set_config('request.jwt.claims', json_build_object('sub', g, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', g::text, true);
  begin
    execute 'set local role authenticated';
    perform crm.corregir_categoria_contrato_fn(k1, 'upgrade', 'Prueba bajo REPEATABLE READ');
    v_estado := '00000';
    v_mensaje := '';
  exception when others then
    v_estado := sqlstate;
    v_mensaje := sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2a', 'la puerta sobre K1', v_estado, v_mensaje,
               '25001', 'La categoría de un contrato solo se corrige en una transacción READ COMMITTED'));
  -- F2b la sincronización al registrar una operación upgrade sobre K7 ('nuevo': habría que escribir) → 25001.
  select * into r from pg_temp.rr_intento(format(c_op, k7));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2b', 'operación upgrade sobre K7 (nuevo)', r.estado, r.mensaje,
               '25001', 'Una renovación o un upgrade solo se registran en una transacción READ COMMITTED'));
  -- F2e la sincronización por el camino que COINCIDE (K6 ya es upgrade y no tiene operación: no escribiría nada) → 25001.
  select * into r from pg_temp.rr_intento(format(c_op, k6));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2e', 'operación upgrade sobre K6 (ya upgrade: camino que coincide)', r.estado, r.mensaje,
               '25001', 'Una renovación o un upgrade solo se registran en una transacción READ COMMITTED'));
  -- F2c la guarda: cambiar la categoría de K6 (SIN operación; en READ COMMITTED pasaría, caso P3) → 25001.
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set categoria = 'renovacion' where id = %L$q$, k6));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2c', 'la guarda: K6 sin operación a renovacion', r.estado, r.mensaje,
               '25001', 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'));
  -- F2d la guarda: K5 (CON operación upgrade) a nuevo → 25001, no 23514 (no llega a buscar la operación con la foto vieja).
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set categoria = 'nuevo' where id = %L$q$, k5));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2d', 'la guarda: K5 con operación a nuevo', r.estado, r.mensaje,
               '25001', 'La categoría de un contrato solo se cambia en una transacción READ COMMITTED'));
  -- F2f editar las notas de K5 en REPEATABLE READ (la categoría no cambia) → pasa.
  select * into r from pg_temp.rr_intento(format($q$update public.contratos set notas_internas = 'nota bajo REPEATABLE READ' where id = %L$q$, k5));
  v_casos := v_casos || jsonb_build_array(jsonb_build_array('F2f', 'editar las notas de K5 (sin tocar la categoría)', r.estado, r.mensaje,
               '00000', ''));

  select string_agg(format('%s %s [esperado %s «%s» · obtenido %s «%s»]', x ->> 0, x ->> 1, x ->> 4, x ->> 5, x ->> 2, x ->> 3), ' | ')
    into v_fallos
    from jsonb_array_elements(v_casos) x
   where x ->> 2 is distinct from x ->> 4 or strpos(x ->> 3, x ->> 5) = 0;
  if v_fallos is not null then
    raise exception 'PRUEBA CATEGORIA FALLA: aislamiento — %', v_fallos;
  end if;
  raise notice 'PRUEBA AISLAMIENTO OK: % casos (puerta, sincronización por los dos caminos y guarda con y sin operación: 25001; notas: pasa)',
    jsonb_array_length(v_casos);
end $rr$;
rollback;
select 'PRUEBA AISLAMIENTO OK' as aislamiento;
