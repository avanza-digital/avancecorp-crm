-- PRUEBA de 20260926204051_crm_cambio_cuenta_pago (F3.1) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra usuarios, contratos, cuentas y archivos FICTICIOS en UNA
-- transacción que termina en ROLLBACK. Los disparadores de public.contratos se apagan SOLO
-- mientras se insertan los contratos ficticios (dentro de la transacción) y se vuelven a
-- encender antes de probar nada.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-cambio-cuenta-pago.sql   (migración aplicada)
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

-- Paridad con producción: si el banco no tiene la exigencia de cuenta al registrar un pago
-- (P-0XX S3, ya en producción), se instala DENTRO de esta transacción.
select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista · 04 superadmin · 05 cliente C · 06 cliente D ·
-- 07 admin con la membresía CRM revocada (P04) · 08 otro admin.
insert into auth.users (id, email, aud, role) values
  ('e7b10000-0000-4000-8000-000000000001', 'f3.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000002', 'f3.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000003', 'f3.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000004', 'f3.super@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000005', 'f3.cliente.c@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000006', 'f3.cliente.d@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000007', 'f3.revocada@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b10000-0000-4000-8000-000000000008', 'f3.admin2@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b10000-0000-4000-8000-000000000001', 'F3 ADMIN PRUEBA', null, '77710001', 'f3.admin@prueba.invalid', 'admin', true, null),
  ('e7b10000-0000-4000-8000-000000000002', 'F3 OPERACIONES PRUEBA', null, '77710002', 'f3.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b10000-0000-4000-8000-000000000003', 'F3 ANALISTA PRUEBA', null, '77710003', 'f3.analista@prueba.invalid', 'analista', true, null),
  ('e7b10000-0000-4000-8000-000000000004', 'F3 SUPERADMIN PRUEBA', null, '77710004', 'f3.super@prueba.invalid', 'superadmin', true, null),
  ('e7b10000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE CE', 'CLIENTE', '77710005', 'f3.cliente.c@prueba.invalid', 'cliente', true, 'e7b10000-0000-4000-8000-000000000003'),
  ('e7b10000-0000-4000-8000-000000000006', 'PRUEBA CLIENTE DE', 'CLIENTE', '77710006', 'f3.cliente.d@prueba.invalid', 'cliente', true, 'e7b10000-0000-4000-8000-000000000003'),
  ('e7b10000-0000-4000-8000-000000000007', 'F3 ADMIN REVOCADA', null, '77710007', 'f3.revocada@prueba.invalid', 'admin', true, null),
  ('e7b10000-0000-4000-8000-000000000008', 'F3 ADMIN DOS', null, '77710008', 'f3.admin2@prueba.invalid', 'admin', true, null);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('e7b10000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C: A (vigente, la de pago hoy), B (vigente, la nueva), X (retirada), U (USD),
-- T (vigente, a nombre de un tercero). Z es del cliente D.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, beneficiario_nombre, beneficiario_dni, activa, origen, creado_en, desactivada_en) values
  ('e7b1c000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000002', '00389800000000000002', false, null, null, true, 'contrato', '2026-09-20', null),
  ('e7b1c000-0000-4000-8000-000000000003', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'BBVA', 'ahorros', '01100000000003', '01110000000000000003', false, null, null, false, 'contrato', '2025-01-01', '2025-06-01'),
  ('e7b1c000-0000-4000-8000-000000000004', 'e7b10000-0000-4000-8000-000000000005', 'USD', 'BCP', 'ahorros', '19100000000004', '00219100000000000004', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000005', 'e7b10000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros', '19100000000005', '00219100000000000005', false, null, null, true, 'contrato', '2026-01-01', null),
  ('e7b1c000-0000-4000-8000-000000000006', 'e7b10000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000006', '00907000000000000006', true, 'MARIA TERCERA PRUEBA', '44556677', true, 'contrato', '2026-09-21', null);

-- Contratos: K1 activo PEN, K2 vencido PEN, K3 activo USD, K4 renovado PEN (cerrado), K5 activo sin cuenta.
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b1d000-0000-4000-8000-000000000001', 'F3-K1', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b1d000-0000-4000-8000-000000000002', 'F3-K2', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'vencido',  '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b1d000-0000-4000-8000-000000000003', 'F3-K3', 'e7b10000-0000-4000-8000-000000000005', 10000, 'USD', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b1d000-0000-4000-8000-000000000004', 'F3-K4', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'renovado', '2025-01-01', '2026-01-01', 'd0000000-0000-4000-8000-000000000002', '2025-01-01'),
  ('e7b1d000-0000-4000-8000-000000000005', 'F3-K5', 'e7b10000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo',   '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;

insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b1d000-0000-4000-8000-000000000001', 'e7b1c000-0000-4000-8000-000000000001'),
  ('e7b1d000-0000-4000-8000-000000000002', 'e7b1c000-0000-4000-8000-000000000001'),
  ('e7b1d000-0000-4000-8000-000000000003', 'e7b1c000-0000-4000-8000-000000000004'),
  ('e7b1d000-0000-4000-8000-000000000004', 'e7b1c000-0000-4000-8000-000000000001');

-- Cuotas (con todos los disparadores): K1 #1 nace pagada (el sello de INSERT la marca en A);
-- K1 #2, #3, #4, #5 y K2 #1 pendientes.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado) values
  ('e7b1e000-0000-4000-8000-000000000001', 'e7b1d000-0000-4000-8000-000000000001', 1, '2026-02-01', 100, 'pagado'),
  ('e7b1e000-0000-4000-8000-000000000002', 'e7b1d000-0000-4000-8000-000000000001', 2, '2026-10-01', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000003', 'e7b1d000-0000-4000-8000-000000000002', 1, '2026-10-05', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000004', 'e7b1d000-0000-4000-8000-000000000001', 3, '2026-11-01', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000005', 'e7b1d000-0000-4000-8000-000000000001', 4, '2026-12-01', 100, 'pendiente'),
  ('e7b1e000-0000-4000-8000-000000000006', 'e7b1d000-0000-4000-8000-000000000001', 5, '2027-01-01', 100, 'pendiente');

-- Respaldos ya subidos (como postgres), cada uno con quien lo subió (owner y owner_id) y la huella
-- de contenido que calcula Storage (eTag). R1 no trae eTag (p. ej. subida por partes).
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  -- R1: el correo del cliente C, subido por el admin (para S1), sin eTag
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf"}'),
  -- R_D: en la carpeta del cliente D
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000006/e7b1f000-0000-4000-8000-000000000002.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e02\""}'),
  -- R3 y R4: para S3 y S4 (admin)
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000003.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e03\""}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000004.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e04\""}'),
  -- R5: para S5, subido por el superadmin
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000005.pdf',
   'e7b10000-0000-4000-8000-000000000004', 'e7b10000-0000-4000-8000-000000000004', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e05\""}'),
  -- R_ADMIN2: subido por OTRO admin
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf',
   'e7b10000-0000-4000-8000-000000000008', 'e7b10000-0000-4000-8000-000000000008', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e06\""}'),
  -- R_TXT: nombre .pdf pero contenido de texto
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "text/plain", "eTag": "\"e07\""}'),
  -- R_OPER y R_REVOC: para los mutantes de permisos
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000008.pdf',
   'e7b10000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000002', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e08\""}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf',
   'e7b10000-0000-4000-8000-000000000007', 'e7b10000-0000-4000-8000-000000000007', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e09\""}'),
  -- R_ALT: otro correo válido del admin, sin usar
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000b.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e0b\""}'),
  -- R10, R11, R12 y R14: para el aviso en curso, el aviso parcial y su mutante
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000010.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e10\""}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000011.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e11\""}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000012.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e12\""}'),
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000014.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e14\""}'),
  -- R_DUP: el MISMO contenido que R3 (misma eTag) subido con otra ruta
  ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000013.pdf',
   'e7b10000-0000-4000-8000-000000000001', 'e7b10000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"e03\""}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
-- Intenta el cambio como un usuario; devuelve 'OK:<json>' o 'ERR:<sqlstate>:<mensaje>'.
create function pg_temp.cambio(p_uid uuid, p_sol uuid, p_cta uuid, p_ids uuid[], p_mot text, p_ruta text,
  p_cli uuid default 'e7b10000-0000-4000-8000-000000000005') returns text
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
create function pg_temp.origen(p_cuota uuid) returns text language sql as $f$
  select origen from crm.cuotas_cuenta_pagada where cuota_id = p_cuota;
$f$;
-- Estado compartido entre bloques (tokens de reserva).
create table pg_temp.f3_estado (clave text primary key, valor text);
-- Reclamar / confirmar el aviso con el rol indicado (por defecto el de la Edge: service_role).
create function pg_temp.reclamar(p_sol uuid, p_actor uuid, p_dry boolean default false,
  p_rol text default 'service_role') returns jsonb
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_rol)::text, true);
  execute format('set local role %I', p_rol);
  begin
    r := crm.reclamar_aviso_cambio_cuenta(p_sol, p_actor, p_dry);
    execute 'reset role';
    return r;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return jsonb_build_object('error', e, 'mensaje', m);
  end;
end;
$f$;
create function pg_temp.confirmar(p_sol uuid, p_res uuid, p_nov boolean, p_cor boolean, p_err text default null,
  p_rol text default 'service_role') returns jsonb
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_rol)::text, true);
  execute format('set local role %I', p_rol);
  begin
    r := crm.confirmar_aviso_cambio_cuenta(p_sol, p_res, p_nov, p_cor, p_err);
    execute 'reset role';
    return r;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return jsonb_build_object('error', e, 'mensaje', m);
  end;
end;
$f$;
-- Cuenta respaldos del bucket visibles para un rol/usuario.
create function pg_temp.respaldos_visibles(p_rol text, p_uid uuid default null) returns integer
language plpgsql as $f$
declare n integer;
begin
  perform set_config('request.jwt.claims',
    case when p_uid is null then json_build_object('role', p_rol)
         else json_build_object('sub', p_uid, 'role', p_rol) end::text, true);
  execute format('set local role %I', p_rol);
  select count(*) into n from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
  execute 'reset role';
  return n;
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
create function pg_temp.enlace(p_contrato uuid) returns uuid language sql as $f$
  select cuenta_bancaria_id from crm.contrato_cuentas_pago where contrato_id = p_contrato;
$f$;
create function pg_temp.sello(p_cuota uuid) returns uuid language sql as $f$
  select cuenta_bancaria_id from crm.cuotas_cuenta_pagada where cuota_id = p_cuota;
$f$;
create function pg_temp.hoy() returns date language sql as $f$
  select (now() at time zone 'America/Lima')::date;
$f$;
-- Aplica un mutante reemplazando un fragmento del cuerpo vivo; falla si el fragmento no está.
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

-- ── A. Permisos, reglas, cambio e idempotencia ───────────────────────────────────────────────
do $casos$
declare
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  X constant uuid := 'e7b1c000-0000-4000-8000-000000000003';
  Z constant uuid := 'e7b1c000-0000-4000-8000-000000000005';
  K1 constant uuid := 'e7b1d000-0000-4000-8000-000000000001';
  K2 constant uuid := 'e7b1d000-0000-4000-8000-000000000002';
  K3 constant uuid := 'e7b1d000-0000-4000-8000-000000000003';
  K4 constant uuid := 'e7b1d000-0000-4000-8000-000000000004';
  K5 constant uuid := 'e7b1d000-0000-4000-8000-000000000005';
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  OPER constant uuid := 'e7b10000-0000-4000-8000-000000000002';
  ANAL constant uuid := 'e7b10000-0000-4000-8000-000000000003';
  CLI constant uuid := 'e7b10000-0000-4000-8000-000000000005';
  REVOC constant uuid := 'e7b10000-0000-4000-8000-000000000007';
  R1 constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf';
  R_D constant text := 'e7b10000-0000-4000-8000-000000000006/e7b1f000-0000-4000-8000-000000000002.pdf';
  R_ALT constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000b.pdf';
  R_REVOC constant text := 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf';
  S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
  MOT constant text := 'El cliente lo pidió por correo el 26/09';
  v text;
begin
  -- Sello al insertar una cuota ya pagada.
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000001') is distinct from A
     or (select origen from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000001') <> 'registro' then
    raise exception 'FALLO: la cuota pagada al insertarse debía quedar sellada en A como registro';
  end if;
  raise notice 'OK sello: una cuota que nace pagada guarda su cuenta (registro)';

  -- Permisos: solo admin o superadmin con la membresía CRM vigente.
  perform pg_temp.espera(pg_temp.cambio(OPER, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'operaciones');
  perform pg_temp.espera(pg_temp.cambio(ANAL, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'analista');
  perform pg_temp.espera(pg_temp.cambio(CLI, S1, B, array[K1, K2], MOT, R1), 'ERR:42501', 'cliente');
  perform pg_temp.espera(pg_temp.cambio(REVOC, S1, B, array[K1, K2], MOT, R_REVOC), 'ERR:42501', 'admin con membresía CRM revocada');
  raise notice 'OK permisos: operaciones, analista, cliente y admin revocado (P04) → 42501';

  -- Reglas (todas 22023 y sin cambiar nada).
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000ff.pdf'), 'ERR:22023:Adjunta el correo', 'respaldo inexistente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, R_D), 'ERR:22023:Adjunta el correo', 'respaldo de otro cliente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, null), 'ERR:22023:Adjunta el correo', 'sin respaldo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, 'e7b10000-0000-4000-8000-000000000005/libre.pdf'), 'ERR:22023:Adjunta el correo', 'nombre inválido');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], 'x', R1), 'ERR:22023:Escribe el motivo', 'motivo corto');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], '    ', R1), 'ERR:22023:Escribe el motivo', 'motivo en blanco');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, Z, array[K1], MOT, R1), 'ERR:22023:La cuenta nueva no es de este cliente', 'cuenta ajena');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, X, array[K1], MOT, R1), 'ERR:22023:La cuenta nueva ya no está vigente', 'cuenta retirada');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K4], MOT, R1), 'ERR:22023:El contrato F3-K4 está cerrado', 'contrato cerrado');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K3], MOT, R1), 'ERR:22023:El contrato F3-K3 es en USD', 'moneda distinta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K5], MOT, R1), 'ERR:22023:El contrato F3-K5 no tiene cuenta de pago', 'sin cuenta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, A, array[K1], MOT, R1), 'ERR:22023:El contrato F3-K1 ya cobra en esa cuenta', 'misma cuenta');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K1], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'repetidos');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[]::uuid[], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'vacío');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, null], MOT, R1), 'ERR:22023:Elige entre 1 y 100', 'con nulo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, gen_random_uuid()], MOT, R1), 'ERR:22023:Algún contrato no existe', 'contrato inexistente');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K4], MOT, R1), 'ERR:22023:El contrato F3-K4 está cerrado', 'todo o nada');
  if pg_temp.enlace(K1) is distinct from A or (select count(*) from crm.contrato_cuenta_pago_cambios) <> 0 then
    raise exception 'FALLO: un rechazo dejó cambios a medias';
  end if;
  raise notice 'OK reglas: respaldo (inexistente, ajeno, ausente, nombre), motivo, cuenta ajena/retirada, contrato cerrado/otra moneda/sin cuenta/inexistente, misma cuenta, repetidos, vacío, nulo y todo-o-nada';

  -- Cambio correcto de K1 y K2 a B.
  v := pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R1);
  perform pg_temp.espera(v, 'OK:', 'cambio correcto');
  if pg_temp.enlace(K1) is distinct from B or pg_temp.enlace(K2) is distinct from B
     or (select count(*) from crm.contrato_cuenta_pago_cambios
         where solicitud_id = S1 and cuenta_anterior_id = A and cuenta_nueva_id = B
           and cambiado_por = ADMIN and cliente_id = CLI and motivo = MOT and respaldo_ruta = R1) <> 2 then
    raise exception 'FALLO: el cambio no dejó los enlaces en B con 2 filas de historial completas: %', v;
  end if;
  raise notice 'OK cambio: K1 y K2 cobran en B; historial con 2 filas (anterior, nueva, quién, motivo, respaldo)';

  -- Idempotencia: la misma solicitud no se repite; con cualquier dato distinto se rechaza.
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R1), 'OK:{"contratos": 2, "ya_aplicada": true', 'doble clic');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K2, K1], MOT, R1), 'OK:{"contratos": 2, "ya_aplicada": true', 'doble clic en otro orden');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1], MOT, R1), 'ERR:22023:Esta solicitud ya se usó', 'otros contratos');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], 'Otro motivo distinto del original', R1), 'ERR:22023:Esta solicitud ya se usó', 'otro motivo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, B, array[K1, K2], MOT, R_ALT), 'ERR:22023:Esta solicitud ya se usó', 'otro respaldo');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S1, 'e7b1c000-0000-4000-8000-000000000006', array[K1, K2], MOT, R1), 'ERR:22023:Esta solicitud ya se usó', 'otra cuenta');
  if (select count(*) from crm.contrato_cuenta_pago_cambios) <> 2 then
    raise exception 'FALLO: el doble clic duplicó historial';
  end if;
  raise notice 'OK idempotencia: el doble clic no duplica; la solicitud con otros contratos, motivo, respaldo o cuenta se rechaza';
end;
$casos$;

-- ── B. Sello: lo pagado conserva su cuenta; cuenta por FECHA del pago ────────────────────────
do $sello$
declare
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  n integer;
begin
  -- Pago hecho hoy, después del cambio → cuenta nueva.
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
   where id = 'e7b1e000-0000-4000-8000-000000000002';
  -- Pago hecho AYER (antes del cambio) pero registrado hoy → cuenta anterior.
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy() - 1
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000001') is distinct from A
     or pg_temp.sello('e7b1e000-0000-4000-8000-000000000002') is distinct from B
     or pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from A then
    raise exception 'FALLO: la cuota vieja debía seguir en A, la pagada hoy en B y la pagada ayer en A';
  end if;
  -- Anular y volver a pagar re-sella (una sola fila por cuota).
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
   where id = 'e7b1e000-0000-4000-8000-000000000004';
  select count(*) into n from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000004';
  if n <> 1 or pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from B then
    raise exception 'FALLO: volver a pagar debía re-sellar la misma fila en B (filas=%)', n;
  end if;
  if exists (select 1 from crm.cuotas_cuenta_pagada
             where contrato_id = 'e7b1d000-0000-4000-8000-000000000001' and origen <> 'registro') then
    raise exception 'FALLO: los sellos del registro debían marcarse como registro';
  end if;
  raise notice 'OK sello: lo pagado antes sigue en A; lo pagado hoy va a B; un pago de ayer registrado hoy va a A; volver a pagar re-sella';

  -- Corregir la fecha de una cuota pagada: re-sella lo deducido por fecha; lo inferido, no.
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy() - 1
   where id = 'e7b1e000-0000-4000-8000-000000000006';
  -- (simula un sello del backfill)
  update crm.cuotas_cuenta_pagada set origen = 'inferido' where cuota_id = 'e7b1e000-0000-4000-8000-000000000006';
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() where id = 'e7b1e000-0000-4000-8000-000000000006';
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() - 1 where id = 'e7b1e000-0000-4000-8000-000000000004';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000006') is distinct from A
     or pg_temp.origen('e7b1e000-0000-4000-8000-000000000006') <> 'inferido'
     or pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from A
     or pg_temp.origen('e7b1e000-0000-4000-8000-000000000004') <> 'registro' then
    raise exception 'FALLO: corregir la fecha debía re-sellar lo deducido por fecha (04 → A) y dejar lo inferido (06 en A)';
  end if;
  raise notice 'OK corrección de fecha: re-sella lo deducido por fecha y deja lo inferido';
end;
$sello$;

-- M4b: el sello sin la regla de la fecha → un pago de ayer se atribuiría a la cuenta nueva.
savepoint m4b;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()', 'if new.fecha_pago_real is not null then', 'if false then');
do $m4b$ begin
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy() - 1
   where id = 'e7b1e000-0000-4000-8000-000000000003';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000003') is distinct from 'e7b1c000-0000-4000-8000-000000000002' then
    raise exception 'MUTANTE 4b NO CAZADO';
  end if;
  raise notice 'OK mutante 4b cazado (sin la regla de la fecha, un pago de ayer iría a la cuenta nueva)';
end $m4b$;
rollback to savepoint m4b;

-- ── C. Candados ──────────────────────────────────────────────────────────────────────────────
do $candados$
declare S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
begin
  -- El enlace no se mueve sin historial en la transacción.
  begin
    update crm.contrato_cuentas_pago set cuenta_bancaria_id = 'e7b1c000-0000-4000-8000-000000000001'
     where contrato_id = 'e7b1d000-0000-4000-8000-000000000001';
    raise exception 'FALLO: el enlace cambió sin historial';
  exception when sqlstate '22023' then null;
  end;
  -- El historial no se reescribe (motivo ni autor) ni se borra.
  begin
    update crm.contrato_cuenta_pago_cambios set motivo = 'reescrito por prueba' where solicitud_id = S1;
    raise exception 'FALLO: el historial se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    update crm.contrato_cuenta_pago_cambios set cambiado_por = 'e7b10000-0000-4000-8000-000000000008' where solicitud_id = S1;
    raise exception 'FALLO: el autor del cambio se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.contrato_cuenta_pago_cambios where solicitud_id = S1;
    raise exception 'FALLO: el historial se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  -- El sello no se borra ni cambia de cuota.
  begin
    delete from crm.cuotas_cuenta_pagada where cuota_id = 'e7b1e000-0000-4000-8000-000000000001';
    raise exception 'FALLO: un sello se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  begin
    update crm.cuotas_cuenta_pagada set cuota_id = gen_random_uuid() where cuota_id = 'e7b1e000-0000-4000-8000-000000000001';
    raise exception 'FALLO: un sello cambió de cuota';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK candados: el enlace no cambia sin historial; historial y sellos no se reescriben ni se borran';
end;
$candados$;

-- ── D. Lecturas (admin y superadmin sí; el resto 42501) ──────────────────────────────────────
do $lecturas$
declare r record; u uuid; n integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') where numero_contrato = 'F3-K1';
  if r.cuenta_bancaria_id is distinct from 'e7b1c000-0000-4000-8000-000000000002' or r.cuotas_pendientes <> 1
     or r.proxima_fecha is distinct from '2026-12-01'::date
     or r.pagadas_por_cuenta <> jsonb_build_array(
          jsonb_build_object('cuenta_bancaria_id', 'e7b1c000-0000-4000-8000-000000000001', 'banco', 'BCP',
                             'numero_cuenta', '19100000000001', 'cuotas', 3, 'inferidas', 1),
          jsonb_build_object('cuenta_bancaria_id', 'e7b1c000-0000-4000-8000-000000000002', 'banco', 'Interbank',
                             'numero_cuenta', '89830000000002', 'cuotas', 1, 'inferidas', 0)) then
    raise exception 'FALLO: la lectura de K1 no muestra B, 1 pendiente (01/12) y A=3 (1 inferida) / B=1 pagadas: %', row_to_json(r);
  end if;
  if (select count(*) from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005')) <> 4 then
    raise exception 'FALLO: debían listarse los 4 contratos abiertos (sin el renovado)';
  end if;
  if (select count(*) from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005')
      where cambiado_por_nombre = 'F3 ADMIN PRUEBA' and aviso_estado = 'pendiente') <> 2 then
    raise exception 'FALLO: el historial debía traer 2 cambios del admin con aviso pendiente';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000004', 'role', 'authenticated')::text, true);
  select count(*) into n from crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
  if n <> 4 then raise exception 'FALLO: el superadmin debía leer los 4 contratos, leyó %', n; end if;
  foreach u in array array['e7b10000-0000-4000-8000-000000000002', 'e7b10000-0000-4000-8000-000000000003',
                           'e7b10000-0000-4000-8000-000000000005', 'e7b10000-0000-4000-8000-000000000007']::uuid[] loop
    perform set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);
    begin
      perform crm.contratos_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
      raise exception 'FALLO: % pudo leer las cuentas de pago', u;
    exception when insufficient_privilege then null;
    end;
    begin
      perform crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005');
      raise exception 'FALLO: % pudo leer el historial de cambios', u;
    exception when insufficient_privilege then null;
    end;
  end loop;
  raise notice 'OK lecturas: admin y superadmin ven contratos (cuenta nueva, pendientes, pagadas por cuenta) e historial; operaciones, analista, cliente y admin revocado 42501';
end;
$lecturas$;

-- ── E. Aviso en dos pasos (reservar con token → confirmar por canal), solo service_role ─────
do $aviso$
declare
  v jsonb; r1 uuid; r2 uuid;
  S1 constant uuid := 'e7b1a000-0000-4000-8000-000000000001';
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
begin
  -- Solo service_role: authenticated no tiene EXECUTE; y el dueño sin el rol del servicio, tampoco.
  v := pg_temp.reclamar(S1, ADMIN, true, 'authenticated');
  if v->>'error' is distinct from '42501' then raise exception 'FALLO: authenticated reclamó un aviso: %', v; end if;
  v := pg_temp.confirmar(S1, gen_random_uuid(), true, true, null, 'authenticated');
  if v->>'error' is distinct from '42501' then raise exception 'FALLO: authenticated confirmó un aviso: %', v; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  begin
    perform crm.reclamar_aviso_cambio_cuenta(S1, ADMIN, true);
    raise exception 'FALLO: reclamar corrió sin el rol del servicio';
  exception when insufficient_privilege then null;
  end;
  -- Quien lo pide debe ser admin vigente.
  if pg_temp.reclamar(S1, 'e7b10000-0000-4000-8000-000000000002', true)->>'error' is distinct from '42501'
     or pg_temp.reclamar(S1, 'e7b10000-0000-4000-8000-000000000007', true)->>'error' is distinct from '42501'
     or pg_temp.reclamar(S1, null, true)->>'error' is distinct from '42501' then
    raise exception 'FALLO: operaciones, un admin revocado o un actor nulo pudieron pedir el aviso';
  end if;

  v := pg_temp.reclamar(S1, ADMIN, true);
  if (v->>'dry_run')::boolean is not true or v->>'ultimos_nuevo' <> '0002' or v->'reserva' <> 'null'::jsonb
     or v->'contratos' <> '["F3-K1", "F3-K2"]'::jsonb or (v->>'titular_distinto')::boolean
     or v->'beneficiario_nombre' <> 'null'::jsonb
     or exists (select 1 from crm.cambio_cuenta_avisos) then
    raise exception 'FALLO: dry_run no debía escribir nada y debía traer los 2 contratos: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  r1 := (v->>'reserva')::uuid;
  if r1 is null or (v->>'pendiente_novedad')::boolean is not true or (v->>'pendiente_correo')::boolean is not true
     or v->>'correo' <> 'f3.cliente.c@prueba.invalid' then
    raise exception 'FALLO: la primera reserva debía traer token y pedir portal y correo: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  if (v->>'en_curso')::boolean is not true then
    raise exception 'FALLO: una segunda reserva inmediata debía decir en_curso: %', v;
  end if;
  -- Sin el token de la reserva no se confirma.
  if pg_temp.confirmar(S1, gen_random_uuid(), true, true)->>'error' is distinct from '22023'
     or pg_temp.confirmar(S1, null, true, true)->>'error' is distinct from '22023' then
    raise exception 'FALLO: se confirmó un aviso sin el token de su reserva';
  end if;
  -- Llegó el portal pero falló el correo: NO se sella; se guarda el error y se libera la reserva.
  v := pg_temp.confirmar(S1, r1, true, false, 'Resend respondió 500');
  if v ? 'error' or (v->>'completo')::boolean
     or exists (select 1 from crm.contrato_cuenta_pago_cambios where notificado_en is not null)
     or (select ultimo_error from crm.cambio_cuenta_avisos where solicitud_id = S1) <> 'Resend respondió 500'
     or (select reserva from crm.cambio_cuenta_avisos where solicitud_id = S1) is not null then
    raise exception 'FALLO: un aviso a medias no debía sellarse: %', v;
  end if;
  -- El reintento solo pide lo que faltó (el correo), con un token nuevo; el viejo ya no vale.
  v := pg_temp.reclamar(S1, ADMIN);
  r2 := (v->>'reserva')::uuid;
  if r2 is null or r2 = r1 or (v->>'pendiente_novedad')::boolean or (v->>'pendiente_correo')::boolean is not true then
    raise exception 'FALLO: el reintento debía pedir solo el correo con un token nuevo: %', v;
  end if;
  if pg_temp.confirmar(S1, r1, false, true)->>'error' is distinct from '22023' then
    raise exception 'FALLO: un token viejo confirmó el aviso';
  end if;
  v := pg_temp.confirmar(S1, r2, false, true);
  if (v->>'completo')::boolean is not true
     or (select count(*) from crm.contrato_cuenta_pago_cambios where solicitud_id = S1 and notificado_en is not null) <> 2 then
    raise exception 'FALLO: con portal y correo entregados debía sellarse: %', v;
  end if;
  v := pg_temp.reclamar(S1, ADMIN);
  if (v->>'ya_notificada')::boolean is not true then
    raise exception 'FALLO: tras sellar debía decir ya_notificada: %', v;
  end if;
  begin
    update crm.contrato_cuenta_pago_cambios set notificado_en = now() where solicitud_id = S1;
    raise exception 'FALLO: el sello del aviso se pudo reescribir';
  exception when sqlstate '22023' then null;
  end;
  begin
    delete from crm.cambio_cuenta_avisos where solicitud_id = S1;
    raise exception 'FALLO: el estado del aviso se pudo borrar';
  exception when sqlstate '22023' then null;
  end;
  raise notice 'OK aviso: solo service_role y para admin vigente; dry_run sin efectos; reserva con token; doble reserva en_curso; sin token no confirma; a medias no sella y guarda el error; reintento solo del canal que faltó con token nuevo; token viejo rechazado; sello final no reescribible';
end;
$aviso$;

-- ── F. Aviso superado, cuenta de un tercero y reserva vencida ───────────────────────────────
-- S3 mueve K1 de B a A y S4 lo pasa a T (cuenta a nombre de un tercero): el aviso de S3 ya no se envía.
do $superado$
declare v jsonb; v_estado text; r1 uuid; r2 uuid;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  S3 constant uuid := 'e7b1a000-0000-4000-8000-000000000003';
  S4 constant uuid := 'e7b1a000-0000-4000-8000-000000000004';
begin
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S3, 'e7b1c000-0000-4000-8000-000000000001',
    array['e7b1d000-0000-4000-8000-000000000001'::uuid], 'El cliente pidió volver a su cuenta anterior',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000003.pdf'), 'OK:', 'S3');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S4, 'e7b1c000-0000-4000-8000-000000000006',
    array['e7b1d000-0000-4000-8000-000000000001'::uuid], 'El cliente pidió cobrar en la cuenta de su esposa',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000004.pdf'), 'OK:', 'S4');
  v := pg_temp.reclamar(S3, ADMIN);
  if (v->>'superada')::boolean is not true then
    raise exception 'FALLO: el aviso de un cambio superado no debía enviarse: %', v;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', ADMIN, 'role', 'authenticated')::text, true);
  select h.aviso_estado into v_estado from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') h
  where h.solicitud_id = S3;
  if v_estado is distinct from 'superado' then
    raise exception 'FALLO: el historial debía mostrar el aviso de S3 como superado, mostró %', v_estado;
  end if;
  v := pg_temp.reclamar(S4, ADMIN);
  r1 := (v->>'reserva')::uuid;
  if v->'contratos' <> '["F3-K1"]'::jsonb or (v->>'titular_distinto')::boolean is not true
     or v->>'beneficiario_nombre' <> 'MARIA TERCERA PRUEBA' or v->>'ultimos_nuevo' <> '0006' then
    raise exception 'FALLO: el aviso de S4 debía anunciar solo F3-K1 y a nombre del tercero: %', v;
  end if;
  -- Reserva vencida (10 min): otro intento toma una reserva nueva y el token viejo deja de valer.
  update crm.cambio_cuenta_avisos set reclamado_en = clock_timestamp() - interval '11 minutes' where solicitud_id = S4;
  v := pg_temp.reclamar(S4, ADMIN);
  r2 := (v->>'reserva')::uuid;
  if r2 is null or r2 = r1 then
    raise exception 'FALLO: una reserva vencida debía ceder a un intento nuevo: %', v;
  end if;
  if pg_temp.confirmar(S4, r1, true, true)->>'error' is distinct from '22023'
     or (pg_temp.confirmar(S4, r2, true, true)->>'completo')::boolean is not true then
    raise exception 'FALLO: solo la reserva vigente debía confirmar';
  end if;
  raise notice 'OK aviso superado: no se envía y el historial lo muestra; el vigente anuncia solo sus contratos y el tercero; una reserva vencida cede y su token ya no vale';
end;
$superado$;

-- ── G. Superadmin, respaldo ajeno, reutilizado o que no es PDF/imagen ────────────────────────
do $respaldos$
declare n integer;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  SUPER constant uuid := 'e7b10000-0000-4000-8000-000000000004';
  K2 constant uuid := 'e7b1d000-0000-4000-8000-000000000002';
  A constant uuid := 'e7b1c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b1c000-0000-4000-8000-000000000002';
  MOT constant text := 'El cliente lo pidió por correo el 26/09';
begin
  perform pg_temp.espera(pg_temp.cambio(SUPER, 'e7b1a000-0000-4000-8000-000000000005', A, array[K2],
    'Pedido del cliente por correo (superadmin)', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000005.pdf'),
    'OK:', 'superadmin');
  if pg_temp.enlace(K2) is distinct from A then raise exception 'FALLO: el cambio del superadmin no movió K2 a A'; end if;
  select count(*) into n from crm.contrato_cuenta_pago_cambios;
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000006', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf'), 'ERR:22023:Ese correo ya respalda otro cambio', 'respaldo reutilizado');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000007', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf'), 'ERR:22023:El respaldo debe subirlo quien hace el cambio', 'respaldo de otro admin');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000008', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf'), 'ERR:22023:Adjunta el correo', 'respaldo que no es PDF/imagen');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000013', B, array[K2], MOT,
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000013.pdf'), 'ERR:22023:Ese correo ya respalda otro cambio', 'mismo contenido con otra ruta');
  if pg_temp.enlace(K2) is distinct from A or (select count(*) from crm.contrato_cuenta_pago_cambios) <> n then
    raise exception 'FALLO: un respaldo rechazado dejó cambios';
  end if;
  raise notice 'OK respaldos: el superadmin cambia; un correo ya usado (por ruta o por contenido), subido por otro admin o que no es PDF/imagen se rechaza';
end;
$respaldos$;

-- ── J. Un aviso en curso frena el cambio; el aviso parcial sella solo lo anunciado ──────────
do $en_curso$
declare v jsonb; r5 uuid;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
  S5 constant uuid := 'e7b1a000-0000-4000-8000-000000000005';
  S10 constant uuid := 'e7b1a000-0000-4000-8000-000000000010';
begin
  v := pg_temp.reclamar(S5, ADMIN);
  r5 := (v->>'reserva')::uuid;
  if r5 is null or v->'contratos' <> '["F3-K2"]'::jsonb then
    raise exception 'FALLO: el aviso de S5 debía reservarse para F3-K2: %', v;
  end if;
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S10, 'e7b1c000-0000-4000-8000-000000000002',
    array['e7b1d000-0000-4000-8000-000000000002'::uuid], 'El cliente volvió a pedir otra cuenta',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000010.pdf'),
    'ERR:22023:Se está enviando al cliente el aviso de un cambio anterior del contrato F3-K2', 'aviso en curso');
  if pg_temp.enlace('e7b1d000-0000-4000-8000-000000000002') is distinct from 'e7b1c000-0000-4000-8000-000000000001' then
    raise exception 'FALLO: con un aviso en curso el enlace no debía moverse';
  end if;
  if (pg_temp.confirmar(S5, r5, true, true)->>'completo')::boolean is not true then
    raise exception 'FALLO: el aviso de S5 debía completarse';
  end if;
  perform pg_temp.espera(pg_temp.cambio(ADMIN, S10, 'e7b1c000-0000-4000-8000-000000000002',
    array['e7b1d000-0000-4000-8000-000000000002'::uuid], 'El cliente volvió a pedir otra cuenta',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000010.pdf'), 'OK:', 'tras el aviso');
  raise notice 'OK aviso en curso: mientras se envía el aviso de un contrato no se cambia su cuenta; al confirmarse, sí';
end;
$en_curso$;

-- S11 pasa K1 (T→A) y K2 (B→A); S12 vuelve a mover K1 (A→B): el aviso de S11 anuncia solo F3-K2.
do $parcial_prep$
declare v jsonb;
  ADMIN constant uuid := 'e7b10000-0000-4000-8000-000000000001';
begin
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000011', 'e7b1c000-0000-4000-8000-000000000001',
    array['e7b1d000-0000-4000-8000-000000000001', 'e7b1d000-0000-4000-8000-000000000002']::uuid[], 'El cliente pidió unificar en su cuenta BCP',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000011.pdf'), 'OK:', 'S11');
  perform pg_temp.espera(pg_temp.cambio(ADMIN, 'e7b1a000-0000-4000-8000-000000000012', 'e7b1c000-0000-4000-8000-000000000002',
    array['e7b1d000-0000-4000-8000-000000000001'::uuid], 'El cliente pidió que F3-K1 cobre en Interbank',
    'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000012.pdf'), 'OK:', 'S12');
  v := pg_temp.reclamar('e7b1a000-0000-4000-8000-000000000011', ADMIN);
  if v->'contratos' <> '["F3-K2"]'::jsonb or v->>'reserva' is null then
    raise exception 'FALLO: el aviso de S11 debía anunciar solo F3-K2: %', v;
  end if;
  insert into pg_temp.f3_estado (clave, valor) values ('reserva_s11', v->>'reserva');
end;
$parcial_prep$;

-- M11: confirmar sellando toda la solicitud → daría por avisado F3-K1, que no se anunció.
savepoint m11;
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'and l.cuenta_bancaria_id = c.cuenta_nueva_id)', ')');
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'and c2.cambiado_en > c.cambiado_en)', 'and false)');
do $m11$ begin
  perform pg_temp.confirmar('e7b1a000-0000-4000-8000-000000000011', (select valor::uuid from pg_temp.f3_estado where clave = 'reserva_s11'), true, true);
  if (select notificado_en from crm.contrato_cuenta_pago_cambios
      where solicitud_id = 'e7b1a000-0000-4000-8000-000000000011' and contrato_id = 'e7b1d000-0000-4000-8000-000000000001') is null then
    raise exception 'MUTANTE 11 NO CAZADO';
  end if;
  raise notice 'OK mutante 11 cazado (sellar toda la solicitud daría por avisado un contrato no anunciado)';
end $m11$;
rollback to savepoint m11;

do $parcial$
declare v jsonb; e1 text; e2 text;
  S11 constant uuid := 'e7b1a000-0000-4000-8000-000000000011';
begin
  v := pg_temp.confirmar(S11, (select valor::uuid from pg_temp.f3_estado where clave = 'reserva_s11'), true, true);
  if (v->>'completo')::boolean is not true then
    raise exception 'FALLO: el aviso de S11 debía completarse: %', v;
  end if;
  if (select notificado_en from crm.contrato_cuenta_pago_cambios where solicitud_id = S11 and contrato_id = 'e7b1d000-0000-4000-8000-000000000001') is not null
     or (select notificado_en from crm.contrato_cuenta_pago_cambios where solicitud_id = S11 and contrato_id = 'e7b1d000-0000-4000-8000-000000000002') is null then
    raise exception 'FALLO: debía sellarse solo F3-K2 (el anunciado)';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  select h.aviso_estado into e1 from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') h
  where h.solicitud_id = S11 and h.numero_contrato = 'F3-K1';
  select h.aviso_estado into e2 from crm.cambios_cuenta_pago_cliente_fn('e7b10000-0000-4000-8000-000000000005') h
  where h.solicitud_id = S11 and h.numero_contrato = 'F3-K2';
  if e1 is distinct from 'superado' or e2 is distinct from 'enviado' then
    raise exception 'FALLO: el historial debía mostrar F3-K1 superado y F3-K2 enviado; mostró % y %', e1, e2;
  end if;
  raise notice 'OK aviso parcial: se anuncia y se sella solo el contrato vigente; el superado se muestra como tal';
end;
$parcial$;

-- ── H. anon no ejecuta nada ─────────────────────────────────────────────────────────────────
set local role anon;
do $anon$
begin
  begin
    perform crm.cambiar_cuenta_pago_contratos(gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), array[gen_random_uuid()], 'motivo largo', 'x');
    raise exception 'FALLO: anon pudo ejecutar el cambio';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.contratos_cuenta_pago_cliente_fn(gen_random_uuid());
    raise exception 'FALLO: anon pudo leer las cuentas de pago';
  exception when insufficient_privilege then null;
  end;
  begin
    perform crm.reclamar_aviso_cambio_cuenta(gen_random_uuid(), gen_random_uuid(), true);
    raise exception 'FALLO: anon pudo reclamar un aviso';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501 en cambio, lectura y aviso';
end;
$anon$;
reset role;

-- ── I. Storage ──────────────────────────────────────────────────────────────────────────────
do $storage$
declare n integer; total integer;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into storage.objects (bucket_id, name, owner, metadata)
  values ('respaldos-cambio-cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-00000000000c.png',
          'e7b10000-0000-4000-8000-000000000001', '{"size": 10, "mimetype": "image/png"}');
  begin
    insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta', 'nombre-libre.pdf');
    raise exception 'FALLO: admin subió con nombre inválido';
  exception when insufficient_privilege then null;
  end;
  update storage.objects set metadata = '{}' where bucket_id = 'respaldos-cambio-cuenta';
  get diagnostics n = row_count;
  if n <> 0 then raise exception 'FALLO: se pudo sustituir un respaldo'; end if;
  -- Storage además prohíbe todo borrado directo (storage.protect_delete); cualquiera de los
  -- dos candados vale: lo que importa es que no se borre nada.
  begin
    delete from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'FALLO: se pudo borrar un respaldo'; end if;
  exception when others then
    if sqlerrm like 'FALLO:%' then raise; end if;
  end;
  execute 'reset role';
  select count(*) into total from storage.objects where bucket_id = 'respaldos-cambio-cuenta';
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000001') <> total
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000004') <> total then
    raise exception 'FALLO: admin y superadmin debían leer los % respaldos', total;
  end if;
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000007') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000005') <> 0
     or pg_temp.respaldos_visibles('anon') <> 0 then
    raise exception 'FALLO: operaciones, un admin revocado, el cliente o anon leyeron respaldos';
  end if;
  foreach n in array array[2, 7] loop
    perform set_config('request.jwt.claims', json_build_object('sub', format('e7b10000-0000-4000-8000-00000000000%s', n), 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta',
        'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000d0.pdf');
      execute 'reset role';
      raise exception 'FALLO: el usuario % subió un respaldo', n;
    exception when insufficient_privilege then execute 'reset role';
    end;
  end loop;
  raise notice 'OK storage: admin y superadmin suben y leen con nombre válido; nadie sustituye ni borra; operaciones, admin revocado, cliente y anon ni leen ni suben';
end;
$storage$;

-- Fronteras: aunque otra política permisiva abriera TODO storage.objects, este bucket sigue cerrado.
savepoint fronteras;
create policy f3_prueba_abierta_anon on storage.objects for select to anon using (true);
create policy f3_prueba_abierta_auth_select on storage.objects for select to authenticated using (true);
create policy f3_prueba_abierta_auth_update on storage.objects for update to authenticated using (true) with check (true);
create policy f3_prueba_abierta_auth_insert on storage.objects for insert to authenticated with check (true);
do $fronteras$
declare n integer;
begin
  if pg_temp.respaldos_visibles('anon') <> 0
     or pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') <> 0 then
    raise exception 'FALLO: una política abierta de otro bucket dejó leer respaldos a anon u operaciones';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update storage.objects set metadata = '{}' where bucket_id = 'respaldos-cambio-cuenta';
  get diagnostics n = row_count;
  execute 'reset role';
  if n <> 0 then raise exception 'FALLO: una política abierta dejó sustituir un respaldo'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000002', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into storage.objects (bucket_id, name) values ('respaldos-cambio-cuenta',
      'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-0000000000d1.pdf');
    execute 'reset role';
    raise exception 'FALLO: una política abierta dejó subir a operaciones';
  exception when insufficient_privilege then execute 'reset role';
  end;
  raise notice 'OK fronteras: con políticas abiertas de otro bucket, anon y operaciones siguen sin leer ni subir y nadie sustituye';
end $fronteras$;
rollback to savepoint fronteras;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M1: el núcleo sin la compuerta → Operaciones cambiaría la cuenta (con un respaldo suyo).
savepoint m1;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if not coalesce(private.admin_banca_vigente(v_actor), false) then', 'if false then');
do $m1$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000002', 'e7b1a000-0000-4000-8000-0000000000a1',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000008.pdf'),
    'OK:', 'MUTANTE 1 NO CAZADO');
  raise notice 'OK mutante 1 cazado (sin compuerta, Operaciones cambiaría la cuenta)';
end $m1$;
rollback to savepoint m1;

-- M1b: la compuerta sin P04 → un admin con la membresía CRM revocada cambiaría la cuenta.
savepoint m1b;
select pg_temp.mutar('private.admin_banca_vigente(uuid)', 'e.perfil_id = p_uid and e.activo is false', 'false');
do $m1b$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000007', 'e7b1a000-0000-4000-8000-0000000000b1',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000009.pdf'),
    'OK:', 'MUTANTE 1b NO CAZADO');
  raise notice 'OK mutante 1b cazado (sin P04, un admin revocado cambiaría la cuenta)';
end $m1b$;
rollback to savepoint m1b;

-- M2: el candado sin exigir historial → el enlace cambiaría a mano.
savepoint m2;
select pg_temp.mutar('private.trg_contrato_cuenta_pago_inmutable()',
  'if new.cuenta_bancaria_id is distinct from old.cuenta_bancaria_id', 'if false');
do $m2$ declare cazado boolean := false; begin
  begin
    update crm.contrato_cuentas_pago set cuenta_bancaria_id = 'e7b1c000-0000-4000-8000-000000000002'
     where contrato_id = 'e7b1d000-0000-4000-8000-000000000002';
    cazado := true;
  exception when sqlstate '22023' then cazado := false;
  end;
  if not cazado then raise exception 'MUTANTE 2 NO CAZADO'; end if;
  raise notice 'OK mutante 2 cazado (sin exigir historial, el enlace cambiaría a mano)';
end $m2$;
rollback to savepoint m2;

-- M3: el núcleo sin comprobar el tipo del archivo → un texto valdría como respaldo.
savepoint m3;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  $r$or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then$r$, 'then');
do $m3$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000a3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000007.pdf'),
    'OK:', 'MUTANTE 3 NO CAZADO');
  raise notice 'OK mutante 3 cazado (sin comprobar el tipo, un texto valdría como respaldo)';
end $m3$;
rollback to savepoint m3;

-- M3b: el núcleo sin comprobar quién subió el respaldo → valdría el archivo de otro admin.
savepoint m3b;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then', 'if false then');
do $m3b$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000b3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000006.pdf'),
    'OK:', 'MUTANTE 3b NO CAZADO');
  raise notice 'OK mutante 3b cazado (sin comprobar quién subió el respaldo, valdría el de otro admin)';
end $m3b$;
rollback to savepoint m3b;

-- M3c: el núcleo sin impedir reutilizar el respaldo → un mismo correo respaldaría dos cambios.
savepoint m3c;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id', 'where false');
do $m3c$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000c3',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000001.pdf'),
    'OK:', 'MUTANTE 3c NO CAZADO');
  raise notice 'OK mutante 3c cazado (sin impedir reutilizar, un correo respaldaría dos cambios)';
end $m3c$;
rollback to savepoint m3c;

-- M4: el sello no sella → la cuota pagada no guardaría su cuenta.
savepoint m4;
create or replace function private.sellar_cuenta_cuota_pagada() returns trigger
language plpgsql security definer set search_path to '' as $m$ begin return null; end; $m$;
update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy()
 where id = 'e7b1e000-0000-4000-8000-000000000003';
do $m4$ begin
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000003') is not null then
    raise exception 'MUTANTE 4 NO CAZADO';
  end if;
  raise notice 'OK mutante 4 cazado (sin sello, la cuota pagada no guardaría su cuenta)';
end $m4$;
rollback to savepoint m4;

-- M5: confirmar sella aunque falte un canal → el aviso a medias se daría por hecho.
savepoint m5;
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'v_completo := v_aviso.novedad_en is not null', 'v_completo := true or v_aviso.novedad_en is not null');
do $m5$ declare v jsonb; S12 constant uuid := 'e7b1a000-0000-4000-8000-000000000012'; begin
  v := pg_temp.reclamar(S12, 'e7b10000-0000-4000-8000-000000000001');
  v := pg_temp.confirmar(S12, (v->>'reserva')::uuid, true, false, 'correo caído');
  if not coalesce((v->>'completo')::boolean, false) then
    raise exception 'MUTANTE 5 NO CAZADO';
  end if;
  raise notice 'OK mutante 5 cazado (sellar a medias daría por avisado a quien no recibió el correo)';
end $m5$;
rollback to savepoint m5;

-- M6: confirmar sin exigir el token → un intento viejo liberaría la reserva de uno nuevo.
savepoint m6;
select pg_temp.mutar('crm.confirmar_aviso_cambio_cuenta(uuid,uuid,boolean,boolean,text)',
  'and reserva = p_reserva', '');
do $m6$ declare v jsonb; S12 constant uuid := 'e7b1a000-0000-4000-8000-000000000012'; begin
  perform pg_temp.reclamar(S12, 'e7b10000-0000-4000-8000-000000000001');
  v := pg_temp.confirmar(S12, gen_random_uuid(), true, true);
  if v ? 'error' then
    raise exception 'MUTANTE 6 NO CAZADO';
  end if;
  raise notice 'OK mutante 6 cazado (sin token, cualquier intento confirmaría y liberaría la reserva)';
end $m6$;
rollback to savepoint m6;

-- M7: reclamar sin exigir el rol del servicio → el dueño lo correría con otra sesión.
savepoint m7;
select pg_temp.mutar('crm.reclamar_aviso_cambio_cuenta(uuid,uuid,boolean)',
  $r$if (select auth.role()) is distinct from 'service_role' then$r$, 'if false then');
do $m7$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b10000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  perform crm.reclamar_aviso_cambio_cuenta('e7b1a000-0000-4000-8000-000000000012', 'e7b10000-0000-4000-8000-000000000001', true);
  raise notice 'OK mutante 7 cazado (sin exigir service_role, reclamar correría con cualquier sesión)';
exception when insufficient_privilege then
  raise exception 'MUTANTE 7 NO CAZADO';
end $m7$;
rollback to savepoint m7;

-- M8: sin la frontera de anon → una política abierta de otro bucket le dejaría leer respaldos.
savepoint m8;
drop policy respaldo_cambio_cuenta_anon_frontera on storage.objects;
create policy f3_prueba_abierta_anon on storage.objects for select to anon using (true);
do $m8$ begin
  if pg_temp.respaldos_visibles('anon') = 0 then raise exception 'MUTANTE 8 NO CAZADO'; end if;
  raise notice 'OK mutante 8 cazado (sin frontera, anon leería respaldos por otra política)';
end $m8$;
rollback to savepoint m8;

-- M9: sin la frontera de lectura → una política abierta dejaría leer respaldos a Operaciones.
savepoint m9;
drop policy respaldo_cambio_cuenta_select_frontera on storage.objects;
create policy f3_prueba_abierta_auth_select on storage.objects for select to authenticated using (true);
do $m9$ begin
  if pg_temp.respaldos_visibles('authenticated', 'e7b10000-0000-4000-8000-000000000002') = 0 then
    raise exception 'MUTANTE 9 NO CAZADO';
  end if;
  raise notice 'OK mutante 9 cazado (sin frontera, Operaciones leería respaldos por otra política)';
end $m9$;
rollback to savepoint m9;

-- M10: el núcleo sin frenar ante un aviso en curso → el aviso anunciaría una cuenta ya dejada.
savepoint m10;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if v_en_curso is not null then', 'if false then');
do $m10$ declare v jsonb; begin
  v := pg_temp.reclamar('e7b1a000-0000-4000-8000-000000000012', 'e7b10000-0000-4000-8000-000000000001');
  if v->>'reserva' is null then raise exception 'MUTANTE 10 MAL PREPARADO: %', v; end if;
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-000000000014',
    'e7b1c000-0000-4000-8000-000000000001', array['e7b1d000-0000-4000-8000-000000000001'::uuid],
    'El cliente pidió otra cuenta', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000014.pdf'),
    'OK:', 'MUTANTE 10 NO CAZADO');
  raise notice 'OK mutante 10 cazado (sin freno, un cambio dejaría atrás un aviso que se está enviando)';
end $m10$;
rollback to savepoint m10;

-- M12: el núcleo sin comparar el contenido → el mismo correo con otra ruta respaldaría otro cambio.
savepoint m12;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  'if v_etag is not null then', 'if false then');
do $m12$ begin
  perform pg_temp.espera(pg_temp.cambio('e7b10000-0000-4000-8000-000000000001', 'e7b1a000-0000-4000-8000-0000000000c4',
    'e7b1c000-0000-4000-8000-000000000002', array['e7b1d000-0000-4000-8000-000000000002'::uuid],
    'El cliente lo pidió por correo', 'e7b10000-0000-4000-8000-000000000005/e7b1f000-0000-4000-8000-000000000013.pdf'),
    'OK:', 'MUTANTE 12 NO CAZADO');
  raise notice 'OK mutante 12 cazado (sin comparar contenido, una copia del correo respaldaría otro cambio)';
end $m12$;
rollback to savepoint m12;

-- M14: el trigger de sello sin mirar la fecha → corregir la fecha no re-sellaría.
savepoint m14;
drop trigger trg_cronograma_pagos_20_sellar_cuenta_update on public.cronograma_pagos;
create trigger trg_cronograma_pagos_20_sellar_cuenta_update
  after update of estado on public.cronograma_pagos
  for each row when (new.estado = 'pagado' and old.estado is distinct from 'pagado')
  execute function private.sellar_cuenta_cuota_pagada();
do $m14$ begin
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() where id = 'e7b1e000-0000-4000-8000-000000000004';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from 'e7b1c000-0000-4000-8000-000000000001' then
    raise exception 'MUTANTE 14 NO CAZADO';
  end if;
  raise notice 'OK mutante 14 cazado (sin mirar la fecha, corregirla no re-sellaría)';
end $m14$;
rollback to savepoint m14;
-- …y sin el mutante, corregir la fecha a hoy SÍ re-sella (K1 cobra ahora en B).
do $m14_control$ begin
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() where id = 'e7b1e000-0000-4000-8000-000000000004';
  if pg_temp.sello('e7b1e000-0000-4000-8000-000000000004') is distinct from 'e7b1c000-0000-4000-8000-000000000002' then
    raise exception 'FALLO: corregir la fecha a hoy debía re-sellar en la cuenta vigente (B)';
  end if;
end $m14_control$;

select 'CAMBIO_CUENTA_OK' as veredicto;
rollback;
