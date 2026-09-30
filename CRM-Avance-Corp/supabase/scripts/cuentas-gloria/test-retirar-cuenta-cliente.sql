-- PRUEBA de 20260927012948_crm_retirar_cuenta_cliente (F4) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra usuarios, contratos, cuentas y archivos FICTICIOS en UNA
-- transacción que termina en ROLLBACK. Requiere aplicadas la F3 (20260926204051) y la F4.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-retirar-cuenta-cliente.sql
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

-- Paridad con producción: la exigencia de cuenta al registrar un pago (P-0XX S3).
select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista (asesor de C) · 04 superadmin · 05 cliente C ·
-- 06 cliente D · 07 admin con la membresía CRM revocada · 08 otro admin.
insert into auth.users (id, email, aud, role) values
  ('e7b40000-0000-4000-8000-000000000001', 'f4.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000002', 'f4.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000003', 'f4.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000004', 'f4.super@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000005', 'f4.cliente.c@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000006', 'f4.cliente.d@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000007', 'f4.revocada@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000008', 'f4.admin2@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b40000-0000-4000-8000-000000000009', 'f4.analista2@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b40000-0000-4000-8000-000000000001', 'F4 ADMIN PRUEBA', null, '77740001', 'f4.admin@prueba.invalid', 'admin', true, null),
  ('e7b40000-0000-4000-8000-000000000002', 'F4 OPERACIONES PRUEBA', null, '77740002', 'f4.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b40000-0000-4000-8000-000000000003', 'F4 ANALISTA PRUEBA', null, '77740003', 'f4.analista@prueba.invalid', 'analista', true, null),
  ('e7b40000-0000-4000-8000-000000000004', 'F4 SUPERADMIN PRUEBA', null, '77740004', 'f4.super@prueba.invalid', 'superadmin', true, null),
  ('e7b40000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE CE', 'CLIENTE', '77740005', 'f4.cliente.c@prueba.invalid', 'cliente', true, 'e7b40000-0000-4000-8000-000000000003'),
  ('e7b40000-0000-4000-8000-000000000006', 'PRUEBA CLIENTE DE', 'CLIENTE', '77740006', 'f4.cliente.d@prueba.invalid', 'cliente', true, 'e7b40000-0000-4000-8000-000000000003'),
  ('e7b40000-0000-4000-8000-000000000007', 'F4 ADMIN REVOCADA', null, '77740007', 'f4.revocada@prueba.invalid', 'admin', true, null),
  ('e7b40000-0000-4000-8000-000000000008', 'F4 ADMIN DOS', null, '77740008', 'f4.admin2@prueba.invalid', 'admin', true, null),
  ('e7b40000-0000-4000-8000-000000000009', 'F4 ANALISTA OTRA CARTERA', null, '77740009', 'f4.analista2@prueba.invalid', 'analista', true, null);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('e7b40000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C: A (cobra K1 activo), A2 (cobra K2 vencido), B (solo K4 renovado),
-- C2 (cobra K6 activo, con una cuota pagada), X (ya retirada), U (USD, libre), T (libre).
-- Z es del cliente D.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_en, desactivada_por, desactivada_en) values
  ('e7b4c000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, true, 'contrato', '2026-01-01', null, null),
  ('e7b4c000-0000-4000-8000-000000000002', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BBVA', 'ahorros', '01100000000002', '01110000000000000002', false, true, 'contrato', '2026-01-02', null, null),
  ('e7b4c000-0000-4000-8000-000000000003', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000003', '00389800000000000003', false, true, 'contrato', '2026-01-03', null, null),
  ('e7b4c000-0000-4000-8000-000000000004', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000004', '00907000000000000004', false, true, 'contrato', '2026-01-04', null, null),
  ('e7b4c000-0000-4000-8000-000000000005', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'BanBif', 'ahorros', '70000000000005', '03870000000000000005', false, false, 'contrato', '2025-01-01', 'e7b40000-0000-4000-8000-000000000001', '2026-06-01 15:00-05'),
  ('e7b4c000-0000-4000-8000-000000000006', 'e7b40000-0000-4000-8000-000000000005', 'USD', 'BCP', 'ahorros', '19100000000006', '00219100000000000006', false, true, 'contrato', '2026-01-06', null, null),
  ('e7b4c000-0000-4000-8000-000000000007', 'e7b40000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros', '19100000000007', '00219100000000000007', false, true, 'contrato', '2026-01-07', null, null),
  ('e7b4c000-0000-4000-8000-000000000008', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Pichincha', 'ahorros', '27000000000008', '03527000000000000008', false, true, 'contrato', '2026-01-08', null, null),
  -- A3v: versión VIEJA (corregida el 01/05) que todavía cobra F4-K7; A3: su versión vigente (mismo CCI).
  ('e7b4c000-0000-4000-8000-00000000000a', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Mibanco', 'ahorros', '40000000000009', '04940000000000000009', false, false, 'contrato', '2026-01-09', 'e7b40000-0000-4000-8000-000000000001', '2026-05-01 10:00-05'),
  ('e7b4c000-0000-4000-8000-000000000009', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Mibanco', 'corriente', '40000000000009', '04940000000000000009', false, true, 'contrato', '2026-05-01', null, null),
  ('e7b4c000-0000-4000-8000-00000000000b', 'e7b40000-0000-4000-8000-000000000005', 'PEN', 'Caja Arequipa', 'ahorros', '80000000000011', '80380000000000000011', false, true, 'contrato', '2026-01-11', null, null);

alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b4d000-0000-4000-8000-000000000001', 'F4-K1', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b4d000-0000-4000-8000-000000000002', 'F4-K2', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'vencido',  '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b4d000-0000-4000-8000-000000000004', 'F4-K4', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'renovado', '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b4d000-0000-4000-8000-000000000006', 'F4-K6', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b4d000-0000-4000-8000-000000000007', 'F4-K7', 'e7b40000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;

insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b4d000-0000-4000-8000-000000000001', 'e7b4c000-0000-4000-8000-000000000001'),
  ('e7b4d000-0000-4000-8000-000000000002', 'e7b4c000-0000-4000-8000-000000000002'),
  ('e7b4d000-0000-4000-8000-000000000004', 'e7b4c000-0000-4000-8000-000000000003'),
  ('e7b4d000-0000-4000-8000-000000000006', 'e7b4c000-0000-4000-8000-000000000004'),
  ('e7b4d000-0000-4000-8000-000000000007', 'e7b4c000-0000-4000-8000-00000000000a');

-- K6 #1 nace pagada: el sello de la F3 la anota en C2.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado) values
  ('e7b4e000-0000-4000-8000-000000000061', 'e7b4d000-0000-4000-8000-000000000006', 1, '2026-02-01', 100, 'pagado');

-- Respaldos (como postgres), con quién los subió.
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f401\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000006/e7b4f000-0000-4000-8000-000000000002.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f402\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf',
   'e7b40000-0000-4000-8000-000000000008', 'e7b40000-0000-4000-8000-000000000008', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f403\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000004.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "text/plain", "eTag": "\"f404\""}'),
  ('respaldos-cambio-cuenta', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf',
   'e7b40000-0000-4000-8000-000000000001', 'e7b40000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f405\""}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
-- Intenta retirar como un usuario; devuelve 'OK:<json>' o 'ERR:<sqlstate>:<mensaje>|<detail>'.
create function pg_temp.retirar(p_uid uuid, p_sol uuid, p_cuenta uuid, p_mot text, p_ruta text default null,
  p_cli uuid default 'e7b40000-0000-4000-8000-000000000005') returns text
language plpgsql as $f$
declare r jsonb; e text; m text; d text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.retirar_cuenta_cliente(p_sol, p_cli, p_cuenta, p_mot, p_ruta);
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text, d = pg_exception_detail;
    execute 'reset role';
    return 'ERR:' || e || ':' || m || '|' || coalesce(d, '');
  end;
end;
$f$;
-- Cambio de cuenta de pago de la F3 (para el caso «lo pagado sigue nombrando la cuenta retirada»).
create function pg_temp.cambio(p_uid uuid, p_sol uuid, p_cta uuid, p_ids uuid[], p_mot text, p_ruta text,
  p_cli uuid default 'e7b40000-0000-4000-8000-000000000005') returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, p_cli, p_cta, p_ids, p_mot, p_ruta);
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
-- Lee los retiros como un usuario; devuelve el JSON de filas o 'ERR:<sqlstate>'.
create function pg_temp.leer_retiros(p_uid uuid, p_rol text default 'authenticated') returns text
language plpgsql as $f$
declare r jsonb; e text;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_rol) else json_build_object('sub', p_uid, 'role', p_rol) end::text, true);
  execute format('set local role %I', p_rol);
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.retirado_en, x.cuenta_id), '[]'::jsonb) into r
    from crm.retiros_cuentas_cliente_fn('e7b40000-0000-4000-8000-000000000005') x;
    execute 'reset role';
    return r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate;
    execute 'reset role';
    return 'ERR:' || e;
  end;
end;
$f$;
create function pg_temp.espera(p_resultado text, p_prefijo text, p_caso text) returns void
language plpgsql as $f$
begin
  if p_resultado is null or p_resultado not like p_prefijo || '%' then
    raise exception 'FALLO [%]: esperaba «%…», vino «%»', p_caso, p_prefijo, p_resultado;
  end if;
end;
$f$;
create function pg_temp.activa(p_cuenta uuid) returns boolean language sql as $f$
  select activa from crm.cuentas_bancarias where id = p_cuenta;
$f$;
create function pg_temp.mutar(p_firma text, p_de text, p_a text) returns void
language plpgsql as $f$
declare s text; t text;
begin
  s := pg_get_functiondef(p_firma::regprocedure);
  t := replace(s, p_de, p_a);
  if t = s then raise exception 'MUTANTE MAL ESCRITO: no se encontró el fragmento en %', p_firma; end if;
  execute t;
end;
$f$;

-- ── A. Permisos y reglas ─────────────────────────────────────────────────────────────────────
do $reglas$
declare
  A constant uuid := 'e7b4c000-0000-4000-8000-000000000001';
  A2 constant uuid := 'e7b4c000-0000-4000-8000-000000000002';
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  X constant uuid := 'e7b4c000-0000-4000-8000-000000000005';
  Z constant uuid := 'e7b4c000-0000-4000-8000-000000000007';
  T constant uuid := 'e7b4c000-0000-4000-8000-000000000008';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
  S constant uuid := 'e7b4a000-0000-4000-8000-000000000099';
  MOT constant text := 'El cliente cerró esa cuenta';
  u uuid;
begin
  foreach u in array array['e7b40000-0000-4000-8000-000000000002', 'e7b40000-0000-4000-8000-000000000003',
                           'e7b40000-0000-4000-8000-000000000005', 'e7b40000-0000-4000-8000-000000000007']::uuid[] loop
    perform pg_temp.espera(pg_temp.retirar(u, S, T, MOT), 'ERR:42501', 'permiso ' || u);
  end loop;
  raise notice 'OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501';

  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, 'x'), 'ERR:22023:Escribe el motivo', 'motivo corto');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, '     '), 'ERR:22023:Escribe el motivo', 'motivo en blanco');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, E'\t\t\t\t\t\t'), 'ERR:22023:Escribe el motivo', 'motivo de tabuladores');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, E'\n\n\n\n\n\n'), 'ERR:22023:Escribe el motivo', 'motivo de saltos de línea');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, E'\u00a0\u00a0\u3000\u2003\u00a0\u00a0'), 'ERR:22023:Escribe el motivo', 'motivo de espacios Unicode');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, E' \t a b \n c \u00a0 '), 'ERR:22023:Escribe el motivo', 'motivo con menos de 5 visibles');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, Z, MOT), 'ERR:22023:La cuenta no es de este cliente', 'cuenta ajena');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, gen_random_uuid(), MOT), 'ERR:22023:La cuenta no es de este cliente', 'cuenta inexistente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, X, MOT), 'ERR:22023:La cuenta ya no está vigente desde el 01/06/2026: se reemplazó por una versión corregida', 'versión reemplazada');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, 'e7b4c000-0000-4000-8000-000000000009', MOT),
    'ERR:22023:La cuenta todavía cobra el contrato F4-K7. Primero cambia su cuenta de pago|contratos_abiertos', 'cuenta física con una versión vieja que cobra');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, A, MOT),
    'ERR:22023:La cuenta todavía cobra el contrato F4-K1. Primero cambia su cuenta de pago|contratos_abiertos', 'contrato activo');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, A2, MOT),
    'ERR:22023:La cuenta todavía cobra el contrato F4-K2. Primero cambia su cuenta de pago|contratos_abiertos', 'contrato vencido');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000006/e7b4f000-0000-4000-8000-000000000002.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo de otro cliente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-0000000000ff.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo inexistente');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/libre.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo con nombre inválido');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000004.pdf'),
    'ERR:22023:El respaldo no es un archivo válido de este cliente', 'respaldo que no es PDF/imagen');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S, T, MOT, 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf'),
    'ERR:22023:El respaldo debe subirlo quien retira la cuenta', 'respaldo de otro admin');
  if exists (select 1 from crm.cuentas_bancarias_retiros)
     or not pg_temp.activa(A) or not pg_temp.activa(A2) or not pg_temp.activa(B) or not pg_temp.activa(T)
     or not pg_temp.activa('e7b4c000-0000-4000-8000-000000000009') then
    raise exception 'FALLO: un rechazo dejó cambios';
  end if;
  raise notice 'OK reglas: motivo (también solo espacios), cuenta ajena/inexistente/reemplazada, contrato activo o vencido (con su lista) también por una versión vieja del mismo CCI, respaldo ajeno/inexistente/inválido/de otro admin; ningún rechazo cambia nada';
end;
$reglas$;

-- ── B. Retiro correcto, idempotencia, respaldo y la cuenta desaparece de las vigentes ────────
do $retiro$
declare
  v text; n integer;
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  U constant uuid := 'e7b4c000-0000-4000-8000-000000000006';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
  S1 constant uuid := 'e7b4a000-0000-4000-8000-000000000001';
  S2 constant uuid := 'e7b4a000-0000-4000-8000-000000000002';
  R1 constant text := 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf';
begin
  -- B solo cobraba un contrato ya renovado: se puede retirar (sin respaldo). Los bordes con
  -- tabuladores, saltos o espacios Unicode se quitan antes de guardar.
  v := pg_temp.retirar(ADMIN, S1, B, E'\t El cliente cerró su cuenta Interbank\n\u00a0');
  perform pg_temp.espera(v, 'OK:', 'retiro de B');
  if pg_temp.activa(B)
     or (select desactivada_por from crm.cuentas_bancarias where id = B) is distinct from ADMIN
     or (select desactivada_en from crm.cuentas_bancarias where id = B) is distinct from now()
     or (select count(*) from crm.cuentas_bancarias_retiros
         where cuenta_id = B and solicitud_id = S1 and motivo = 'El cliente cerró su cuenta Interbank'
           and respaldo_ruta is null and retirado_por = ADMIN and moneda = 'PEN') <> 1 then
    raise exception 'FALLO: el retiro de B no dejó la cuenta retirada con su constancia: %', v;
  end if;
  -- Idempotencia y mensajes claros.
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S1, B, E'\t El cliente cerró su cuenta Interbank\n\u00a0'), 'OK:{"cuenta_id": "e7b4c000-0000-4000-8000-000000000003", "ya_aplicada": true', 'doble clic');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S1, B, 'Otro motivo distinto'), 'ERR:22023:Esta solicitud ya se usó con otros datos', 'solicitud con otros datos');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, B, 'El cliente cerró su cuenta Interbank'),
    'ERR:22023:La cuenta ya fue retirada el ' || to_char(now() at time zone 'America/Lima', 'DD/MM/YYYY') || ' por F4 ADMIN PRUEBA', 'retirar otra vez');
  -- Con respaldo (el correo del cliente, subido por el mismo admin).
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, U, 'El cliente pidió dejar de usar su cuenta en dólares', R1), 'OK:', 'retiro con respaldo');
  if (select respaldo_ruta from crm.cuentas_bancarias_retiros where cuenta_id = U) is distinct from R1 then
    raise exception 'FALLO: el retiro de U debía guardar su respaldo';
  end if;
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, U, 'El cliente pidió dejar de usar su cuenta en dólares', R1), 'OK:{"cuenta_id": "e7b4c000-0000-4000-8000-000000000006", "ya_aplicada": true', 'doble clic con respaldo');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, S2, U, 'El cliente pidió dejar de usar su cuenta en dólares',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf'), 'ERR:22023:Esta solicitud ya se usó con otros datos', 'misma solicitud con otro respaldo');
  -- El superadmin también retira.
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000004', 'e7b4a000-0000-4000-8000-000000000004',
    'e7b4c000-0000-4000-8000-00000000000b', 'El cliente ya no usa la Caja Arequipa'), 'OK:', 'retiro del superadmin');
  -- Ya no se ofrecen: la lectura de vigentes (la que usan el CRM y la ventana «Cuentas») no las trae.
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select count(*) into n from crm.cuentas_bancarias_cliente_fn('e7b40000-0000-4000-8000-000000000005', 'PEN') c where c.cuenta_id = B;
  if n <> 0 then raise exception 'FALLO: la cuenta retirada B sigue entre las vigentes'; end if;
  select count(*) into n from crm.cuentas_bancarias_cliente_fn('e7b40000-0000-4000-8000-000000000005', 'USD') c where c.cuenta_id = U;
  if n <> 0 then raise exception 'FALLO: la cuenta retirada U sigue entre las vigentes'; end if;
  -- Nunca se reactiva (candado de versiones).
  begin
    update crm.cuentas_bancarias set activa = true, desactivada_por = null, desactivada_en = null where id = B;
    raise exception 'FALLO: una cuenta retirada se pudo reactivar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK retiro: la cuenta queda retirada con fecha, quién, motivo y respaldo (admin y superadmin); doble clic no duplica (con o sin respaldo); otra vez da un mensaje claro; deja de ofrecerse y no se reactiva';
end;
$retiro$;

-- ── C. Lo pagado y el historial siguen nombrando la cuenta retirada; F3 ya no la ofrece ──────
do $constancias$
declare
  r record; v_json jsonb; v_banco text;
  A constant uuid := 'e7b4c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b4c000-0000-4000-8000-000000000003';
  C2 constant uuid := 'e7b4c000-0000-4000-8000-000000000004';
  ADMIN constant uuid := 'e7b40000-0000-4000-8000-000000000001';
begin
  -- K6 cobraba en C2 (con una cuota pagada allí): se cambia a A con la F3 y después se retira C2.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b4a000-0000-4000-8000-000000000031', A,
    array['e7b4d000-0000-4000-8000-000000000006'::uuid], 'El cliente pidió cobrar en su cuenta BCP',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf'), 'OK:', 'cambio F3 de K6');
  perform pg_temp.espera(pg_temp.retirar(ADMIN, 'e7b4a000-0000-4000-8000-000000000003', C2,
    'El cliente cerró su cuenta Scotiabank', 'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000005.pdf'),
    'OK:', 'retiro de C2 tras el cambio, con el mismo correo del cambio');
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b40000-0000-4000-8000-000000000005') where numero_contrato = 'F4-K6';
  if r.cuenta_bancaria_id is distinct from A
     or not exists (select 1 from jsonb_array_elements(r.pagadas_por_cuenta) p
                    where p->>'cuenta_bancaria_id' = C2::text and p->>'banco' = 'Scotiabank' and (p->>'cuotas')::int = 1) then
    raise exception 'FALLO: la cuota pagada en C2 debía seguir mostrando C2 tras retirarla: %', row_to_json(r);
  end if;
  select h.banco_anterior into v_banco from crm.cambios_cuenta_pago_cliente_fn('e7b40000-0000-4000-8000-000000000005') h
  where h.numero_contrato = 'F4-K6';
  if v_banco is distinct from 'Scotiabank' then
    raise exception 'FALLO: el historial de cambios debía seguir nombrando la cuenta retirada, mostró %', v_banco;
  end if;
  -- «Cambiar cuenta de pago» no ofrece ni acepta una cuenta retirada.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b4a000-0000-4000-8000-000000000032', B,
    array['e7b4d000-0000-4000-8000-000000000001'::uuid], 'Prueba de cuenta retirada',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000001.pdf'), 'ERR:22023:La cuenta nueva ya no está vigente', 'F3 con cuenta retirada');
  raise notice 'OK constancias: lo pagado y el historial de cambios siguen nombrando la cuenta retirada; «Cambiar cuenta de pago» no la acepta';
end;
$constancias$;

-- ── D. Lectura de motivos para «Cuentas anteriores» ─────────────────────────────────────────
do $lectura$
declare v text; j jsonb;
begin
  v := pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000001');
  j := v::jsonb;
  if jsonb_array_length(j) <> 4
     or (select count(*) from jsonb_array_elements(j) x where x->>'respaldo_ruta' is not null) <> 2
     or (select count(*) from jsonb_array_elements(j) x where x->>'retirado_por_nombre' = 'F4 ADMIN PRUEBA') <> 3
     or (select count(*) from jsonb_array_elements(j) x where x->>'retirado_por_nombre' = 'F4 SUPERADMIN PRUEBA') <> 1 then
    raise exception 'FALLO: el admin debía ver los 4 retiros con quién y los 2 respaldos: %', v;
  end if;
  foreach v in array array[pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000003'),
                           pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000002')] loop
    j := v::jsonb;
    if jsonb_array_length(j) <> 4
       or exists (select 1 from jsonb_array_elements(j) x where x->>'respaldo_ruta' is not null)
       or not exists (select 1 from jsonb_array_elements(j) x where x->>'motivo' = 'El cliente cerró su cuenta Interbank') then
      raise exception 'FALLO: analista y operaciones debían ver los motivos sin la ruta del respaldo: %', v;
    end if;
  end loop;
  perform pg_temp.espera(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000005'), 'ERR:42501', 'cliente');
  perform pg_temp.espera(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000009'), 'ERR:42501', 'analista de otra cartera');
  perform pg_temp.espera(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000007'), 'ERR:42501', 'admin revocado');
  perform pg_temp.espera(pg_temp.leer_retiros(null, 'anon'), 'ERR:42501', 'anon');
  raise notice 'OK lectura: admin ve motivos y respaldo; analista de la cartera y operaciones ven motivos sin respaldo; cliente, analista de otra cartera, admin revocado y anon 42501';
end;
$lectura$;

-- ── E. El registro no se modifica ni se borra; anon no retira ───────────────────────────────
do $candados$
begin
  begin
    update crm.cuentas_bancarias_retiros set motivo = 'reescrito por prueba';
    raise exception 'FALLO: el retiro se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.cuentas_bancarias_retiros;
    raise exception 'FALLO: el retiro se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  begin
    truncate crm.cuentas_bancarias_retiros;
    raise exception 'FALLO: el registro de retiros se pudo vaciar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK candados: el registro del retiro no se modifica, no se borra ni se vacía';
end;
$candados$;
set local role anon;
do $anon$
begin
  begin
    perform crm.retirar_cuenta_cliente(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'motivo largo');
    raise exception 'FALLO: anon pudo retirar';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501';
end;
$anon$;
reset role;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M0: el núcleo sin contar caracteres visibles → un motivo de tabuladores pasaría la validación.
savepoint m0;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  $r$, '', 'g')) < 5$r$, $r$, '', 'g')) < 0$r$);
do $m0$ begin
  if pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a0',
       'e7b4c000-0000-4000-8000-000000000008', E'\t\t\t\t\t\t') like 'ERR:22023:Escribe el motivo%' then
    raise exception 'MUTANTE 0 NO CAZADO';
  end if;
  raise notice 'OK mutante 0 cazado (sin contar visibles, un motivo de tabuladores llegaría a la base)';
end $m0$;
rollback to savepoint m0;

-- M1: el núcleo sin compuerta → Operaciones retiraría cuentas.
savepoint m1;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if not coalesce(private.admin_banca_vigente(v_actor), false) then', 'if false then');
do $m1$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000002', 'e7b4a000-0000-4000-8000-0000000000a1',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró'), 'OK:', 'MUTANTE 1 NO CAZADO');
  raise notice 'OK mutante 1 cazado (sin compuerta, Operaciones retiraría cuentas)';
end $m1$;
rollback to savepoint m1;

-- M1b: la compuerta sin P04 → un admin revocado retiraría cuentas.
savepoint m1b;
select pg_temp.mutar('private.admin_banca_vigente(uuid)', 'e.perfil_id = p_uid and e.activo is false', 'false');
do $m1b$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000007', 'e7b4a000-0000-4000-8000-0000000000b1',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró'), 'OK:', 'MUTANTE 1b NO CAZADO');
  raise notice 'OK mutante 1b cazado (sin P04, un admin revocado retiraría cuentas)';
end $m1b$;
rollback to savepoint m1b;

-- M2: el núcleo sin mirar contratos abiertos → se retiraría la cuenta que cobra F4-K1.
savepoint m2;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if coalesce(pg_catalog.cardinality(v_abiertos), 0) > 0 then', 'if false then');
do $m2$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a2',
    'e7b4c000-0000-4000-8000-000000000001', 'El cliente la cerró'), 'OK:', 'MUTANTE 2 NO CAZADO');
  raise notice 'OK mutante 2 cazado (sin mirar contratos abiertos, se retiraría una cuenta que cobra)';
end $m2$;
rollback to savepoint m2;

-- M3: el núcleo sin exigir cuenta vigente → retirar una ya retirada no diría con claridad que ya lo estaba.
savepoint m3;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  '  if not v_cuenta.activa then', '  if false then');
do $m3$ begin
  if pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a3',
       'e7b4c000-0000-4000-8000-000000000005', 'El cliente la cerró') like 'ERR:22023:La cuenta ya no está vigente%' then
    raise exception 'MUTANTE 3 NO CAZADO';
  end if;
  raise notice 'OK mutante 3 cazado (sin exigir vigente, una cuenta ya retirada no daría su mensaje claro)';
end $m3$;
rollback to savepoint m3;

-- M4: el núcleo sin idempotencia → el doble clic fallaría en vez de confirmar.
savepoint m4;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  '  if found then
    if v_previo.cuenta_id = p_cuenta_id', '  if false then
    if v_previo.cuenta_id = p_cuenta_id');
do $m4$ begin
  if pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-000000000001',
       'e7b4c000-0000-4000-8000-000000000003', 'El cliente cerró su cuenta Interbank') like 'OK:%"ya_aplicada": true%' then
    raise exception 'MUTANTE 4 NO CAZADO';
  end if;
  raise notice 'OK mutante 4 cazado (sin idempotencia, el doble clic fallaría)';
end $m4$;
rollback to savepoint m4;

-- M5: el núcleo sin comprobar quién subió el respaldo → valdría el archivo de otro admin.
savepoint m5;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then', 'if false then');
do $m5$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a5',
    'e7b4c000-0000-4000-8000-000000000008', 'El cliente la cerró',
    'e7b40000-0000-4000-8000-000000000005/e7b4f000-0000-4000-8000-000000000003.pdf'), 'OK:', 'MUTANTE 5 NO CAZADO');
  raise notice 'OK mutante 5 cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)';
end $m5$;
rollback to savepoint m5;

-- M6: la lectura sin reservar la ruta al admin → el analista vería la ruta del correo.
savepoint m6;
select pg_temp.mutar('private.retiros_cuentas_cliente_autorizado(uuid)',
  'case when v_admin then r.respaldo_ruta end', 'r.respaldo_ruta');
do $m6$ begin
  if not exists (select 1 from jsonb_array_elements(pg_temp.leer_retiros('e7b40000-0000-4000-8000-000000000003')::jsonb) x
                 where x->>'respaldo_ruta' is not null) then
    raise exception 'MUTANTE 6 NO CAZADO';
  end if;
  raise notice 'OK mutante 6 cazado (sin reservar la ruta, el analista vería el correo del cliente)';
end $m6$;
rollback to savepoint m6;

-- M7: sin el candado del registro → el motivo se podría reescribir.
savepoint m7;
drop trigger trg_cuentas_bancarias_retiros_00_inmutable on crm.cuentas_bancarias_retiros;
do $m7$ declare n integer; begin
  update crm.cuentas_bancarias_retiros set motivo = 'reescrito por prueba';
  get diagnostics n = row_count;
  if n = 0 then raise exception 'MUTANTE 7 NO CAZADO'; end if;
  raise notice 'OK mutante 7 cazado (sin candado, el motivo del retiro se podría reescribir)';
end $m7$;
rollback to savepoint m7;

-- M8: mirar contratos abiertos solo por la versión (no por la cuenta física) → se retiraría A3,
-- cuya versión vieja todavía cobra F4-K7.
savepoint m8;
select pg_temp.mutar('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)',
  'and cb.cci = v_cuenta.cci', 'and cb.id = p_cuenta_id');
do $m8$ begin
  perform pg_temp.espera(pg_temp.retirar('e7b40000-0000-4000-8000-000000000001', 'e7b4a000-0000-4000-8000-0000000000a8',
    'e7b4c000-0000-4000-8000-000000000009', 'El cliente cerró su cuenta Mibanco'), 'OK:', 'MUTANTE 8 NO CAZADO');
  raise notice 'OK mutante 8 cazado (mirando solo la versión, se retiraría una cuenta cuya versión vieja cobra un contrato)';
end $m8$;
rollback to savepoint m8;

select 'RETIRO_CUENTA_OK' as veredicto;
rollback;
