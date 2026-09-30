-- PRUEBA de 20260927024423_crm_pago_declara_cuenta (F5) — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra datos FICTICIOS en UNA transacción que termina en ROLLBACK.
-- Requiere aplicadas F3 (20260926204051), F4 (20260927012948), los arreglos (20260927020317) y F5.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-pago-declara-cuenta.sql
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
-- 01 admin · 02 operaciones · 03 analista (asesor de C) · 05 cliente C · 07 admin revocado (P04).
insert into auth.users (id, email, aud, role) values
  ('e7b60000-0000-4000-8000-000000000006', 'f6.cliente.d@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000001', 'f6.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000002', 'f6.oper@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000003', 'f6.analista@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000005', 'f6.cliente@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b60000-0000-4000-8000-000000000007', 'f6.revocada@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo, asesor_perfil_id) values
  ('e7b60000-0000-4000-8000-000000000001', 'F6 ADMIN PRUEBA', null, '77760001', 'f6.admin@prueba.invalid', 'admin', true, null),
  ('e7b60000-0000-4000-8000-000000000002', 'F6 OPERACIONES PRUEBA', null, '77760002', 'f6.oper@prueba.invalid', 'operaciones', true, null),
  ('e7b60000-0000-4000-8000-000000000003', 'F6 ANALISTA PRUEBA', null, '77760003', 'f6.analista@prueba.invalid', 'analista', true, null),
  ('e7b60000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE EF', 'CLIENTE', '77760005', 'f6.cliente@prueba.invalid', 'cliente', true, 'e7b60000-0000-4000-8000-000000000003'),
  ('e7b60000-0000-4000-8000-000000000007', 'F6 ADMIN REVOCADA', null, '77760007', 'f6.revocada@prueba.invalid', 'admin', true, null),
  ('e7b60000-0000-4000-8000-000000000006', 'PRUEBA CLIENTE DE', 'CLIENTE', '77760006', 'f6.cliente.d@prueba.invalid', 'cliente', true, 'e7b60000-0000-4000-8000-000000000003');
insert into crm.equipo (perfil_id, rol_crm, activo) values ('e7b60000-0000-4000-8000-000000000007', 'gerencia', false);

-- Cuentas del cliente C (PEN): A (cuenta de pago de K1), B (vigente, será la nueva), Z (vigente pero
-- NUNCA de pago de K1: anomalía), Av (versión VIEJA de A, mismo CCI, retirada al corregir).
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_en, desactivada_por, desactivada_en) values
  ('e7b6c000-0000-4000-8000-000000000001', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, true, 'contrato', '2026-03-01', null, null),
  ('e7b6c000-0000-4000-8000-000000000002', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000002', '00389800000000000002', false, true, 'contrato', '2026-09-20', null, null),
  ('e7b6c000-0000-4000-8000-000000000003', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000003', '00907000000000000003', false, true, 'contrato', '2026-01-03', null, null),
  ('e7b6c000-0000-4000-8000-000000000004', 'e7b60000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'corriente', '19100000000001', '00219100000000000001', false, false, 'contrato', '2026-01-01', 'e7b60000-0000-4000-8000-000000000001', '2026-03-01 10:00-05'),
  -- Z2: cuenta vigente de OTRO cliente (D), misma moneda.
  ('e7b6c000-0000-4000-8000-000000000005', 'e7b60000-0000-4000-8000-000000000006', 'PEN', 'BCP', 'ahorros', '19100000000009', '00219100000000000009', false, true, 'contrato', '2026-01-09', null, null);
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b6d000-0000-4000-8000-000000000001', 'F6-K1', 'e7b60000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b6d000-0000-4000-8000-000000000002', 'F6-K2', 'e7b60000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;
insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b6d000-0000-4000-8000-000000000001', 'e7b6c000-0000-4000-8000-000000000001');
-- Cuotas: #1 pagada de antes (deducida), #2..#7 pendientes.
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, fecha_pago_real) values
  ('e7b6e000-0000-4000-8000-000000000001', 'e7b6d000-0000-4000-8000-000000000001', 1, '2026-02-01', 100, 'pagado', '2026-02-01'),
  ('e7b6e000-0000-4000-8000-000000000002', 'e7b6d000-0000-4000-8000-000000000001', 2, '2026-10-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000003', 'e7b6d000-0000-4000-8000-000000000001', 3, '2026-11-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000004', 'e7b6d000-0000-4000-8000-000000000001', 4, '2026-12-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000005', 'e7b6d000-0000-4000-8000-000000000001', 5, '2027-01-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000006', 'e7b6d000-0000-4000-8000-000000000001', 6, '2027-02-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000007', 'e7b6d000-0000-4000-8000-000000000001', 7, '2027-03-01', 100, 'pendiente', null),
  ('e7b6e000-0000-4000-8000-000000000008', 'e7b6d000-0000-4000-8000-000000000001', 8, '2027-04-01', 100, 'pendiente', null);
-- K2 #1 pagada SIN cuenta de pago (como las 38 de prod): sin sello. Los triggers de exigencia se saltan.
alter table public.cronograma_pagos disable trigger user;
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, fecha_pago_real) values
  ('e7b6e000-0000-4000-8000-000000000021', 'e7b6d000-0000-4000-8000-000000000002', 1, '2026-02-01', 100, 'pagado', '2026-02-01');
alter table public.cronograma_pagos enable trigger user;
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'e7b60000-0000-4000-8000-000000000005/e7b6f000-0000-4000-8000-000000000001.pdf',
   'e7b60000-0000-4000-8000-000000000001', 'e7b60000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f601\""}');

-- ── Utilidades ───────────────────────────────────────────────────────────────────────────────
create function pg_temp.registrar(p_uid uuid, p_cuota uuid, p_fecha date, p_monto numeric, p_cci text) returns text
language plpgsql as $f$
declare r uuid; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.registrar_pago_con_cuenta(p_cuota, p_fecha, p_monto, p_cci);
    execute 'reset role';
    return 'OK:' || coalesce(r::text, 'null');
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
  end;
end;
$f$;
create function pg_temp.cambio(p_sol uuid, p_cta uuid, p_mot text) returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b60000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, 'e7b60000-0000-4000-8000-000000000005', p_cta,
      array['e7b6d000-0000-4000-8000-000000000001'::uuid], p_mot,
      'e7b60000-0000-4000-8000-000000000005/e7b6f000-0000-4000-8000-000000000001.pdf');
    execute 'reset role';
    return 'OK:' || r::text;
  exception when others then
    get stacked diagnostics e = returned_sqlstate, m = message_text;
    execute 'reset role';
    return 'ERR:' || e || ':' || m;
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
create function pg_temp.sello(p_cuota uuid) returns text language sql as $f$
  select coalesce((select cuenta_bancaria_id::text || '|' || origen from crm.cuotas_cuenta_pagada where cuota_id = p_cuota), 'sin sello');
$f$;
create function pg_temp.estado(p_cuota uuid) returns text language sql as $f$
  select estado from public.cronograma_pagos where id = p_cuota;
$f$;
create function pg_temp.hoy() returns date language sql as $f$
  select (now() at time zone 'America/Lima')::date;
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

-- ── A. El caso del «mismo día» (criterio 1) y las reglas de la RPC ──────────────────────────
do $mismo_dia$
declare
  A constant text := 'e7b6c000-0000-4000-8000-000000000001';
  B constant uuid := 'e7b6c000-0000-4000-8000-000000000002';
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
  C3 constant uuid := 'e7b6e000-0000-4000-8000-000000000003';
  C4 constant uuid := 'e7b6e000-0000-4000-8000-000000000004';
begin
  -- #1 pagada antes de F5: sigue 'registro' en A (criterio 5).
  perform pg_temp.espera(pg_temp.sello('e7b6e000-0000-4000-8000-000000000001'), A || '|registro', 'pago anterior');
  -- El Excel se exportó con A y Operaciones depositó en A; ESE MISMO DÍA Gloria cambia K1 a B.
  perform pg_temp.espera(pg_temp.cambio('e7b6a000-0000-4000-8000-000000000001', B, 'El cliente pidió cobrar en Interbank'), 'OK:', 'cambio A→B');
  -- Importación posterior: la fila declara el CCI de A → queda en A como declarado, no en B.
  perform pg_temp.espera(pg_temp.registrar(OPER, C2, pg_temp.hoy(), 100, '00219100000000000001'), 'OK:' || C2::text, 'importación con CCI de A');
  perform pg_temp.espera(pg_temp.sello(C2), A || '|declarado', 'mismo día → A declarado');
  -- El formato del Excel no importa: espacios, guiones, apóstrofo de Excel.
  perform pg_temp.espera(pg_temp.registrar(OPER, C3, pg_temp.hoy(), 100, ' ''002-19100000000000001 '), 'OK:' || C3::text, 'CCI con formato');
  perform pg_temp.espera(pg_temp.sello(C3), A || '|declarado', 'CCI con formato → A');
  -- Sin CCI: se deduce por la fecha como hasta hoy (pago de hoy → B, la cuenta nueva).
  perform pg_temp.espera(pg_temp.registrar(OPER, C4, pg_temp.hoy(), 100, null), 'OK:' || C4::text, 'sin CCI');
  perform pg_temp.espera(pg_temp.sello(C4), B::text || '|registro', 'sin CCI → deducido');
  raise notice 'OK mismo día: el Excel viejo con el CCI de A deja el pago en A (declarado) aunque el contrato ya cobre en B; sin CCI se deduce por fecha; el pago anterior no cambia';
end;
$mismo_dia$;

do $reglas$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C5 constant uuid := 'e7b6e000-0000-4000-8000-000000000005';
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
begin
  -- Criterio 2: CCI de una cuenta del cliente que NUNCA fue de pago de este contrato → rechazo, sin marcar.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '00907000000000000003'), 'ERR:22023:El CCI del depósito no es de una cuenta de pago de este contrato', 'CCI ajeno al contrato');
  perform pg_temp.espera(pg_temp.estado(C5), 'pendiente', 'CCI ajeno no marca');
  perform pg_temp.espera(pg_temp.sello(C5), 'sin sello', 'CCI ajeno no sella');
  -- CCI mal formado, monto nulo o cero, cuota inexistente.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '123'), 'ERR:22023:El CCI del depósito no tiene 20 dígitos', 'CCI corto');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, 'N/A'), 'ERR:22023:El CCI del depósito no tiene 20 dígitos', 'CCI sin dígitos');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), null, null), 'ERR:22023:El monto pagado debe ser mayor que cero', 'monto nulo');
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 0, null), 'ERR:22023:El monto pagado debe ser mayor que cero', 'monto cero');
  perform pg_temp.espera(pg_temp.registrar(OPER, gen_random_uuid(), pg_temp.hoy(), 100, null), 'OK:null', 'cuota inexistente');
  -- Ya pagada: no se marca dos veces (NULL), y su sello no cambia.
  perform pg_temp.espera(pg_temp.registrar(OPER, C2, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:null', 'ya pagada');
  perform pg_temp.espera(pg_temp.sello(C2), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'ya pagada conserva su sello');
  perform pg_temp.espera(pg_temp.estado(C5), 'pendiente', 'nada marcó C5');
  raise notice 'OK reglas: CCI ajeno al contrato, CCI mal formado, monto nulo/cero, cuota inexistente y ya pagada no marcan ni sellan';
end;
$reglas$;

-- ── B. Versión vieja de la cuenta de pago (mismo CCI) y cuenta histórica de F3 ──────────────
do $versiones$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C5 constant uuid := 'e7b6e000-0000-4000-8000-000000000005';
  C6 constant uuid := 'e7b6e000-0000-4000-8000-000000000006';
begin
  -- Av (versión vieja de A, mismo CCI) resuelve a la versión vigente A: misma cuenta física.
  perform pg_temp.espera(pg_temp.registrar(OPER, C5, pg_temp.hoy(), 100, '00219100000000000001'), 'OK:' || C5::text, 'CCI de la cuenta física A');
  perform pg_temp.espera(pg_temp.sello(C5), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'resuelve a la versión vigente');
  -- B es la cuenta de pago actual (tras el cambio): declarada, queda en B.
  perform pg_temp.espera(pg_temp.registrar(OPER, C6, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C6::text, 'CCI de B');
  perform pg_temp.espera(pg_temp.sello(C6), 'e7b6c000-0000-4000-8000-000000000002|declarado', 'B declarado');
  raise notice 'OK versiones: el CCI resuelve la cuenta física (versión vigente) y acepta la cuenta actual y la histórica del contrato';
end;
$versiones$;

-- ── C. Corregir fecha no re-sella lo declarado; anular y volver a pagar re-sella (criterio 5) ──
do $fechas$
declare
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
  C4 constant uuid := 'e7b6e000-0000-4000-8000-000000000004';
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
begin
  update public.cronograma_pagos set fecha_pago_real = pg_temp.hoy() - 30 where id in (C2, C4);
  perform pg_temp.espera(pg_temp.sello(C2), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'declarado no se recalcula');
  perform pg_temp.espera(pg_temp.sello(C4), 'e7b6c000-0000-4000-8000-000000000001|registro', 'deducido sí se recalcula (hace 30 días cobraba A)');
  -- Anular y volver a pagar con CCI: re-sella como declarado (una sola fila por cuota).
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = C4;
  perform pg_temp.espera(pg_temp.registrar(OPER, C4, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C4::text, 'volver a pagar');
  perform pg_temp.espera(pg_temp.sello(C4), 'e7b6c000-0000-4000-8000-000000000002|declarado', 're-sellado como declarado');
  if (select count(*) from crm.cuotas_cuenta_pagada where cuota_id = C4) <> 1 then raise exception 'FALLO: dos sellos para una cuota'; end if;
  raise notice 'OK fechas: corregir la fecha no toca lo declarado y recalcula lo deducido; anular y volver a pagar re-sella como declarado';
end;
$fechas$;

-- ── D. Permisos (criterio 4): quién marca y quién no; el ajuste no se fija fuera de la RPC ──
do $permisos$
declare
  C7 constant uuid := 'e7b6e000-0000-4000-8000-000000000007';
  u uuid; v text;
begin
  foreach u in array array['e7b60000-0000-4000-8000-000000000003', 'e7b60000-0000-4000-8000-000000000005']::uuid[] loop
    perform pg_temp.espera(pg_temp.registrar(u, C7, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:null', 'no gestor ' || u);
    perform pg_temp.espera(pg_temp.estado(C7), 'pendiente', 'no gestor no marca ' || u);
  end loop;
  -- Un admin con la membresía CRM revocada: hoy la RLS de pagos (es_gestor_cartera) no aplica P04.
  -- Se documenta el comportamiento real: marca (igual que con el UPDATE directo de siempre).
  v := pg_temp.registrar('e7b60000-0000-4000-8000-000000000007', C7, pg_temp.hoy(), 100, '00389800000000000002');
  if v like 'OK:' || C7::text then
    raise notice 'AVISO documentado: el admin revocado (P04) marca pagos, igual que con el UPDATE directo vigente (la RLS de public.cronograma_pagos no aplica P04)';
    update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = C7;
  end if;
  -- El admin sí marca.
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000001', C7, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C7::text, 'admin');
  -- El ajuste queda limpio tras la RPC.
  if coalesce(current_setting('crm.cci_deposito', true), '') <> '' then raise exception 'FALLO: el ajuste crm.cci_deposito no se limpió'; end if;
  raise notice 'OK permisos: analista y cliente no marcan (RLS); operaciones y admin sí; el ajuste se limpia al salir';
end;
$permisos$;
-- ── F. Procedencia y limpieza (Codex F5) ────────────────────────────────────────────────────
do $procedencia$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C8 constant uuid := 'e7b6e000-0000-4000-8000-000000000008';
  C2 constant uuid := 'e7b6e000-0000-4000-8000-000000000002';
  v text;
begin
  -- Un CCI fijado A MANO (sin la RPC) no declara nada: el sello lo rechaza (testigo ausente).
  perform set_config('crm.cci_deposito', '00389800000000000002', true);
  begin
    update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy(), monto_pagado = 100 where id = C8;
    raise exception 'FALLO: un CCI fijado a mano se aceptó como declaración';
  exception when sqlstate '22023' then
    if sqlerrm not like 'La cuenta del depósito solo se declara por crm.registrar_pago_con_cuenta%' then raise; end if;
  end;
  perform set_config('crm.cci_deposito', '', true);
  perform pg_temp.espera(pg_temp.estado(C8), 'pendiente', 'CCI a mano no marca');
  -- Tras un 22023 atrapado (CCI ajeno) el ajuste queda limpio y la cuota sigue pendiente.
  perform pg_temp.espera(pg_temp.registrar(OPER, C8, pg_temp.hoy(), 100, '00907000000000000003'), 'ERR:22023:El CCI del depósito no es de una cuenta de pago', 'CCI ajeno');
  if coalesce(current_setting('crm.cci_deposito', true), '') <> '' or coalesce(current_setting('crm.cci_deposito_testigo', true), '') <> '' then
    raise exception 'FALLO: el ajuste quedó sucio tras un 22023';
  end if;
  -- Ya pagada + CCI ajeno: no marca (NULL), no sella, no deja el ajuste.
  v := pg_temp.registrar(OPER, C2, pg_temp.hoy(), 100, '00907000000000000003');
  perform pg_temp.espera(v, 'OK:null', 'ya pagada con CCI ajeno');
  perform pg_temp.espera(pg_temp.sello(C2), 'e7b6c000-0000-4000-8000-000000000001|declarado', 'ya pagada conserva su sello');
  if coalesce(current_setting('crm.cci_deposito', true), '') <> '' then raise exception 'FALLO: ajuste sucio tras ya pagada'; end if;
  -- Y después de todo eso, la vía buena sigue funcionando en la misma transacción.
  perform pg_temp.espera(pg_temp.registrar(OPER, C8, pg_temp.hoy(), 100, '00389800000000000002'), 'OK:' || C8::text, 'vía buena tras los rechazos');
  perform pg_temp.espera(pg_temp.sello(C8), 'e7b6c000-0000-4000-8000-000000000002|declarado', 'C8 declarado en B');
  raise notice 'OK procedencia: un CCI fijado a mano no declara; tras un 22023 el ajuste queda limpio; ya pagada + CCI ajeno no marca ni sella; la vía buena sigue';
end;
$procedencia$;

-- ── G. Huecos del auditor: otro cliente, UPDATE directo, service_role, cuota sin sello ───────
do $huecos$
declare
  OPER constant uuid := 'e7b60000-0000-4000-8000-000000000002';
  C7 constant uuid := 'e7b6e000-0000-4000-8000-000000000007';
  K2C1 constant uuid := 'e7b6e000-0000-4000-8000-000000000021';
begin
  -- CCI válido de OTRO cliente (misma moneda): 22023, sin marcar.
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = C7;
  perform pg_temp.espera(pg_temp.registrar(OPER, C7, pg_temp.hoy(), 100, '00219100000000000009'), 'ERR:22023:El CCI del depósito no es de una cuenta de pago', 'CCI de otro cliente');
  perform pg_temp.espera(pg_temp.estado(C7), 'pendiente', 'otro cliente no marca');
  -- UPDATE directo (sin RPC) con el ajuste vacío: sigue siendo «sin declaración» → 'registro'.
  perform set_config('crm.cci_deposito', '', true);
  perform set_config('request.jwt.claims', json_build_object('sub', OPER, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy(), monto_pagado = 100, registrado_por = OPER where id = C7;
  execute 'reset role';
  perform pg_temp.espera(pg_temp.sello(C7), 'e7b6c000-0000-4000-8000-000000000002|registro', 'UPDATE directo sin ajuste → deducido');
  -- Cuota pagada SIN sello (contrato sin cuenta de pago): corregir la fecha no crea sello; al recibir enlace y corregir, sella 'inferido' (semántica de F3).
  perform pg_temp.espera(pg_temp.sello(K2C1), 'sin sello', 'K2#1 sin sello');
  update public.cronograma_pagos set fecha_pago_real = '2026-02-02' where id = K2C1;
  perform pg_temp.espera(pg_temp.sello(K2C1), 'sin sello', 'sin enlace sigue sin sello');
  insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values ('e7b6d000-0000-4000-8000-000000000002', 'e7b6c000-0000-4000-8000-000000000003');
  update public.cronograma_pagos set fecha_pago_real = '2026-02-03' where id = K2C1;
  perform pg_temp.espera(pg_temp.sello(K2C1), 'e7b6c000-0000-4000-8000-000000000003|inferido', 'con enlace y corrección → inferido');
  raise notice 'OK huecos: CCI de otro cliente se rechaza; el UPDATE directo sin ajuste deduce; una cuota sin sello que recibe enlace se sella como inferido al corregir la fecha';
end;
$huecos$;
-- service_role no ejecuta la RPC: se acredita por el catálogo (ACL exacta), NUNCA ejecutándola con
-- SET ROLE service_role: en este banco, ese SET ROLE + llamada tumba el servidor (trampa conocida:
-- «Postgres se cae por un permiso de función»).
do $srv$
begin
  if pg_catalog.has_function_privilege('service_role', 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'EXECUTE')
     or not pg_catalog.has_function_privilege('authenticated', 'crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', 'EXECUTE') then
    raise exception 'FALLO: EXECUTE de la RPC no es exactamente authenticated';
  end if;
  raise notice 'OK service_role y anon sin EXECUTE sobre la RPC (catálogo)';
end;
$srv$;

-- anon no ejecuta la RPC.
set local role anon;
do $anon$
begin
  begin
    perform crm.registrar_pago_con_cuenta(gen_random_uuid(), current_date, 100, null);
    raise exception 'FALLO: anon pudo llamar la RPC';
  exception when insufficient_privilege then null;
  end;
  raise notice 'OK anon: 42501';
end;
$anon$;
reset role;

-- ── E. Lectura: pagadas por cuenta distingue declaradas ──────────────────────────────────────
do $lectura$
declare r record;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b60000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select * into r from crm.contratos_cuenta_pago_cliente_fn('e7b60000-0000-4000-8000-000000000005') where numero_contrato = 'F6-K1';
  execute 'reset role';
  -- A: #1 registro + #2 #3 #5 declaradas = 4 (3 declaradas) · B: #4 #6 #7 declaradas = 3 (3 declaradas)
  if r.pagadas_por_cuenta <> jsonb_build_array(
       jsonb_build_object('cuenta_bancaria_id', 'e7b6c000-0000-4000-8000-000000000001', 'banco', 'BCP', 'numero_cuenta', '19100000000001', 'cuotas', 4, 'inferidas', 0, 'declaradas', 3),
       jsonb_build_object('cuenta_bancaria_id', 'e7b6c000-0000-4000-8000-000000000002', 'banco', 'Interbank', 'numero_cuenta', '89830000000002', 'cuotas', 4, 'inferidas', 0, 'declaradas', 3)) then
    raise exception 'FALLO: pagadas_por_cuenta no cuadra: %', r.pagadas_por_cuenta;
  end if;
  raise notice 'OK lectura: pagadas por cuenta trae declaradas (A: 4, 3 declaradas · B: 4, 3 declaradas + 1 registro)';
end;
$lectura$;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
-- M1: el sello ignora la declaración → el Excel viejo del «mismo día» quedaría en B.
savepoint m1;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()', 'if v_nuevo_pago and v_cci is not null then', 'if false then');
do $m1$ begin
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = 'e7b6e000-0000-4000-8000-000000000002';
  perform pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000002', pg_temp.hoy(), 100, '00219100000000000001');
  if pg_temp.sello('e7b6e000-0000-4000-8000-000000000002') = 'e7b6c000-0000-4000-8000-000000000001|declarado' then raise exception 'MUTANTE 1 NO CAZADO'; end if;
  raise notice 'OK mutante 1 cazado (sin la declaración, el pago del mismo día iría a la cuenta nueva)';
end $m1$;
rollback to savepoint m1;

-- M2: el sello acepta cualquier cuenta del cliente → un depósito a Z (nunca de pago) se sellaría.
savepoint m2;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()',
  'and ref.cliente_id = cb.cliente_id and ref.moneda = cb.moneda and ref.cci = cb.cci)',
  'and true) or true');
do $m2$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, '00907000000000000003'), 'OK:', 'MUTANTE 2 NO CAZADO');
  raise notice 'OK mutante 2 cazado (sin la restricción, un depósito a una cuenta ajena al contrato se sellaría)';
end $m2$;
rollback to savepoint m2;

-- M3: la RPC no limpia el ajuste → un UPDATE directo posterior en la misma transacción heredaría el CCI.
savepoint m3;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$perform pg_catalog.set_config('crm.cci_deposito', '', true);
  perform pg_catalog.set_config('crm.cci_deposito_testigo', '', true);
  return v_id;$r$, $r$return v_id;$r$);
do $m3$ begin
  perform pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, '00389800000000000002');
  if coalesce(current_setting('crm.cci_deposito', true), '') = '' then raise exception 'MUTANTE 3 NO CAZADO'; end if;
  raise notice 'OK mutante 3 cazado (sin limpiar, el CCI se quedaría en la transacción)';
end $m3$;
rollback to savepoint m3;

-- M4: la RPC sin validar el CCI → «N/A» pasaría en silencio como «sin CCI».
savepoint m4;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$if pg_catalog.btrim(coalesce(p_cci, '')) <> '' and (v_cci is null or pg_catalog.length(v_cci) <> 20) then$r$, 'if false then');
do $m4$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000007', pg_temp.hoy(), 100, 'N/A'), 'OK:', 'MUTANTE 4 NO CAZADO');
  raise notice 'OK mutante 4 cazado (sin validar, un CCI dañado se registraría como si no hubiera CCI)';
end $m4$;
rollback to savepoint m4;

-- M5: la RPC marca cuotas ya pagadas → pisaría un pago registrado.
savepoint m5;
select pg_temp.mutar('crm.registrar_pago_con_cuenta(uuid,date,numeric,text)', $r$where id = p_cuota_id and estado = 'pendiente'$r$, $r$where id = p_cuota_id$r$);
do $m5$ begin
  perform pg_temp.espera(pg_temp.registrar('e7b60000-0000-4000-8000-000000000002', 'e7b6e000-0000-4000-8000-000000000002', pg_temp.hoy(), 100, null), 'OK:e7b6e000', 'MUTANTE 5 NO CAZADO');
  raise notice 'OK mutante 5 cazado (sin exigir pendiente, pisaría un pago ya registrado)';
end $m5$;
rollback to savepoint m5;

-- M6: el sello sin exigir el testigo → un CCI fijado a mano (sin la RPC) declararía la cuenta.
savepoint m6;
select pg_temp.mutar('private.sellar_cuenta_cuota_pagada()',
  'if v_cci is not null and v_testigo is distinct from', 'if false and v_testigo is distinct from');
do $m6$ begin
  perform set_config('crm.cci_deposito', '00389800000000000002', true);
  update public.cronograma_pagos set estado = 'pendiente', fecha_pago_real = null, monto_pagado = null where id = 'e7b6e000-0000-4000-8000-000000000007';
  update public.cronograma_pagos set estado = 'pagado', fecha_pago_real = pg_temp.hoy(), monto_pagado = 100 where id = 'e7b6e000-0000-4000-8000-000000000007';
  perform set_config('crm.cci_deposito', '', true);
  if pg_temp.sello('e7b6e000-0000-4000-8000-000000000007') <> 'e7b6c000-0000-4000-8000-000000000002|declarado' then raise exception 'MUTANTE 6 NO CAZADO'; end if;
  raise notice 'OK mutante 6 cazado (sin testigo, un CCI a mano sin la RPC declararía la cuenta)';
end $m6$;
rollback to savepoint m6;

select 'PAGO_DECLARA_CUENTA_OK' as veredicto;
rollback;
