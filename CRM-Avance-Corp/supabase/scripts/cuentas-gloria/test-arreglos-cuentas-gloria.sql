-- PRUEBA de 20260927020317_crm_cuentas_gloria_motivo_y_cuenta_retirada — SOLO BANCO.
-- ⚠️ Jamás contra producción: siembra datos FICTICIOS en UNA transacción que termina en ROLLBACK.
-- Requiere aplicadas la F3 (20260926204051), la F4 (20260927012948) y esta migración.
--
-- Uso: psql "$DB_URL" -v ON_ERROR_STOP=1 -f test-arreglos-cuentas-gloria.sql
\set ON_ERROR_STOP 1
begin;
set local lock_timeout = '5s';

select to_regprocedure('private.exigir_cuenta_pago_cronograma()') is null as falta_exigir \gset
\if :falta_exigir
\ir ../../migrations/20260925194026_p0xx_pagos_solo_cuenta_contractual.sql
\endif

-- ── Siembra ficticia ─────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, aud, role) values
  ('e7b50000-0000-4000-8000-000000000001', 'f5.admin@prueba.invalid', 'authenticated', 'authenticated'),
  ('e7b50000-0000-4000-8000-000000000005', 'f5.cliente@prueba.invalid', 'authenticated', 'authenticated');
insert into public.perfiles (id, nombre_completo, nombres, dni, correo, rol, activo) values
  ('e7b50000-0000-4000-8000-000000000001', 'F5 ADMIN PRUEBA', null, '77750001', 'f5.admin@prueba.invalid', 'admin', true),
  ('e7b50000-0000-4000-8000-000000000005', 'PRUEBA CLIENTE EF', 'CLIENTE', '77750005', 'f5.cliente@prueba.invalid', 'cliente', true);
-- A: vigente (cobra K1). Bv (versión vieja, cobra K2) + B (versión vigente, mismo CCI). R: retirada
-- del todo (cobra K3, un contrato que volvió a abrirse). N: vigente, para el cambio de K1.
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, activa, origen, creado_en, desactivada_por, desactivada_en) values
  ('e7b5c000-0000-4000-8000-000000000001', 'e7b50000-0000-4000-8000-000000000005', 'PEN', 'BCP', 'ahorros', '19100000000001', '00219100000000000001', false, true, 'contrato', '2026-01-01', null, null),
  ('e7b5c000-0000-4000-8000-000000000002', 'e7b50000-0000-4000-8000-000000000005', 'PEN', 'Mibanco', 'ahorros', '40000000000002', '04940000000000000002', false, false, 'contrato', '2026-01-02', 'e7b50000-0000-4000-8000-000000000001', '2026-05-01 10:00-05'),
  ('e7b5c000-0000-4000-8000-000000000003', 'e7b50000-0000-4000-8000-000000000005', 'PEN', 'Mibanco', 'corriente', '40000000000002', '04940000000000000002', false, true, 'contrato', '2026-05-01', null, null),
  ('e7b5c000-0000-4000-8000-000000000004', 'e7b50000-0000-4000-8000-000000000005', 'PEN', 'Scotiabank', 'ahorros', '00070000000004', '00907000000000000004', false, false, 'contrato', '2026-01-04', 'e7b50000-0000-4000-8000-000000000001', '2026-06-01 10:00-05'),
  ('e7b5c000-0000-4000-8000-000000000005', 'e7b50000-0000-4000-8000-000000000005', 'PEN', 'Interbank', 'ahorros', '89830000000005', '00389800000000000005', false, true, 'contrato', '2026-01-05', null, null);
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial) values
  ('e7b5d000-0000-4000-8000-000000000001', 'F5-K1', 'e7b50000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b5d000-0000-4000-8000-000000000002', 'F5-K2', 'e7b50000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01'),
  ('e7b5d000-0000-4000-8000-000000000003', 'F5-K3', 'e7b50000-0000-4000-8000-000000000005', 10000, 'PEN', 12, 'simple', 'mensual', 'activo', '2026-01-01', '2027-01-01', 'd0000000-0000-4000-8000-000000000002', '2026-01-01');
alter table public.contratos enable trigger user;
insert into crm.contrato_cuentas_pago (contrato_id, cuenta_bancaria_id) values
  ('e7b5d000-0000-4000-8000-000000000001', 'e7b5c000-0000-4000-8000-000000000001'),
  ('e7b5d000-0000-4000-8000-000000000002', 'e7b5c000-0000-4000-8000-000000000002'),
  ('e7b5d000-0000-4000-8000-000000000003', 'e7b5c000-0000-4000-8000-000000000004');
insert into storage.objects (bucket_id, name, owner, owner_id, metadata) values
  ('respaldos-cambio-cuenta', 'e7b50000-0000-4000-8000-000000000005/e7b5f000-0000-4000-8000-000000000001.pdf',
   'e7b50000-0000-4000-8000-000000000001', 'e7b50000-0000-4000-8000-000000000001', '{"size": 2048, "mimetype": "application/pdf", "eTag": "\"f501\""}');

create function pg_temp.cambio(p_sol uuid, p_cta uuid, p_ids uuid[], p_mot text) returns text
language plpgsql as $f$
declare r jsonb; e text; m text;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b50000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    r := crm.cambiar_cuenta_pago_contratos(p_sol, 'e7b50000-0000-4000-8000-000000000005', p_cta, p_ids, p_mot,
      'e7b50000-0000-4000-8000-000000000005/e7b5f000-0000-4000-8000-000000000001.pdf');
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

-- ── 1. Motivo del cambio de cuenta de pago ──────────────────────────────────────────────────
do $motivo$
declare K1 constant uuid := 'e7b5d000-0000-4000-8000-000000000001'; N constant uuid := 'e7b5c000-0000-4000-8000-000000000005';
begin
  perform pg_temp.espera(pg_temp.cambio('e7b5a000-0000-4000-8000-000000000001', N, array[K1], E'\t\t\t\t\t\t'), 'ERR:22023:Escribe el motivo', 'tabuladores');
  perform pg_temp.espera(pg_temp.cambio('e7b5a000-0000-4000-8000-000000000001', N, array[K1], E'\n\n\n\n\n\n'), 'ERR:22023:Escribe el motivo', 'saltos');
  perform pg_temp.espera(pg_temp.cambio('e7b5a000-0000-4000-8000-000000000001', N, array[K1], E'  　   '), 'ERR:22023:Escribe el motivo', 'espacios Unicode');
  perform pg_temp.espera(pg_temp.cambio('e7b5a000-0000-4000-8000-000000000001', N, array[K1], E' \t a b \n c   '), 'ERR:22023:Escribe el motivo', 'menos de 5 visibles');
  if (select count(*) from crm.contrato_cuenta_pago_cambios) <> 0 then raise exception 'FALLO: un motivo inválido dejó cambios'; end if;
  -- Los bordes raros se quitan antes de guardar.
  perform pg_temp.espera(pg_temp.cambio('e7b5a000-0000-4000-8000-000000000001', N, array[K1], E'\t El cliente lo pidió por correo\n '), 'OK:', 'motivo válido con bordes');
  if (select motivo from crm.contrato_cuenta_pago_cambios where contrato_id = K1) <> 'El cliente lo pidió por correo' then
    raise exception 'FALLO: el motivo debía guardarse sin los bordes';
  end if;
  -- La regla de la tabla también lo exige (escritura directa del dueño).
  begin
    insert into crm.contrato_cuenta_pago_cambios (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id, motivo, respaldo_ruta, cambiado_por)
    values (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), E'\t\t\t\t\t\t',
            'e7b50000-0000-4000-8000-000000000005/e7b5f000-0000-4000-8000-000000000001.pdf', 'e7b50000-0000-4000-8000-000000000001');
    raise exception 'FALLO: la tabla aceptó un motivo de tabuladores';
  exception when check_violation then null;
  end;
  raise notice 'OK motivo F3: tabuladores, saltos, espacios Unicode y menos de 5 visibles se rechazan (núcleo y tabla); los bordes se limpian';
end;
$motivo$;

-- ── 2. cuenta_retirada en la lectura de contratos ───────────────────────────────────────────
do $retirada$
declare r record;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b50000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  for r in select numero_contrato, cuenta_retirada, banco from crm.contratos_cuenta_pago_cliente_fn('e7b50000-0000-4000-8000-000000000005') loop
    if (r.numero_contrato = 'F5-K1' and r.cuenta_retirada is not false)        -- N vigente
       or (r.numero_contrato = 'F5-K2' and r.cuenta_retirada is not false)     -- versión vieja, pero hay versión vigente
       or (r.numero_contrato = 'F5-K3' and r.cuenta_retirada is not true) then -- retirada del todo
      raise exception 'FALLO: cuenta_retirada mal calculada para % (%): %', r.numero_contrato, r.banco, r.cuenta_retirada;
    end if;
  end loop;
  execute 'reset role';
  raise notice 'OK cuenta_retirada: false con cuenta vigente o versión corregida; true cuando ninguna versión sigue vigente';
end;
$retirada$;

-- ── Mutantes ─────────────────────────────────────────────────────────────────────────────────
savepoint m1;
select pg_temp.mutar('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)',
  $r$, '', 'g')) < 5$r$, $r$, '', 'g')) < 0$r$);
do $m1$ begin
  if pg_temp.cambio('e7b5a000-0000-4000-8000-0000000000a1', 'e7b5c000-0000-4000-8000-000000000003',
       array['e7b5d000-0000-4000-8000-000000000002'::uuid], E'\t\t\t\t\t\t') like 'ERR:22023:Escribe el motivo%' then
    raise exception 'MUTANTE 1 NO CAZADO';
  end if;
  raise notice 'OK mutante 1 cazado (sin contar visibles, el núcleo dejaría pasar tabuladores hasta la tabla)';
end $m1$;
rollback to savepoint m1;

savepoint m2;
select pg_temp.mutar('private.contratos_cuenta_pago_cliente_autorizado(uuid)',
  'and v.cci = cb.cci and v.activa is true', 'and v.id = cb.id and v.activa is true');
do $m2$ declare v boolean; begin
  perform set_config('request.jwt.claims', json_build_object('sub', 'e7b50000-0000-4000-8000-000000000001', 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select cuenta_retirada into v from crm.contratos_cuenta_pago_cliente_fn('e7b50000-0000-4000-8000-000000000005') where numero_contrato = 'F5-K2';
  execute 'reset role';
  if v is not true then raise exception 'MUTANTE 2 NO CAZADO'; end if;
  raise notice 'OK mutante 2 cazado (mirando solo la versión, una cuenta corregida se marcaría como retirada)';
end $m2$;
rollback to savepoint m2;

select 'ARREGLOS_OK' as veredicto;
rollback;
