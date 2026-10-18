-- Pruebas de la vista previa del mes (20261017211313). NO se corre sola: probar.sh le antepone la siembra y los helpers de
-- la batería de la Fase 1 (supabase/scripts/reemplazar-inversion/test-reemplazar-inversion.sql, todo lo anterior a su
-- bloque 0) y le pone el ROLLBACK final. Regla de oro: lo que la vista previa ANUNCIA es lo que el reemplazo HACE (paridad),
-- en cada forma de calcular el mes; y la vista previa no escribe nada.

create function pg_temp.previa(p_uid uuid, p_fuente uuid, p_fecha date, p_conservar uuid default null) returns jsonb
language sql as $$
  select pg_temp.api(p_uid, format('select crm.reemplazar_inversion_vista_previa_fn(%L::uuid, %L::date, %L::uuid)',
    p_fuente, p_fecha, p_conservar)) $$;

create function pg_temp.sql_previa(p_uid uuid, p_fuente uuid, p_fecha date, p_conservar uuid default null) returns text
language sql as $$
  select format('select pg_temp.previa(%L::uuid, %L::uuid, %L::date, %L::uuid)', p_uid, p_fuente, p_fecha, p_conservar) $$;

-- Lo que se escribió en ESTA transacción, tabla por tabla (filas insertadas, actualizadas y borradas).
create function pg_temp.escrituras() returns bigint language sql as $$
  select coalesce(sum(t.n_tup_ins + t.n_tup_upd + t.n_tup_del), 0)::bigint from pg_catalog.pg_stat_xact_all_tables t
  where t.schemaname not in ('pg_catalog', 'information_schema', 'pg_toast') and t.schemaname not like 'pg_temp%' $$;

-- ── V1 · Paridad, mismo mes: la venta se queda en octubre ───────────────────────────────────────────────────────────────
do $v1$
declare v_k uuid := pg_temp.k('2026-01-910001'); p jsonb; r jsonb;
begin
  begin
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-10-05');
    perform pg_temp.exigir(p ->> 'mes_actual' = '2026-10-01' and p ->> 'mes_resultante' = '2026-10-01'
      and not (p ->> 'cambia_mes')::boolean and not (p ->> 'fecha_corregida')::boolean and not (p ->> 'cuotas_pagadas')::boolean,
      'V1: la previa dice octubre, sin mudanza ni cuotas pagadas');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-911101', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(201));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r ->> 'contrato_id')::uuid)
      = (p ->> 'fecha_comercial_resultante')::date, 'V1: el reemplazo deja la fecha que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V1 paridad: mismo mes';
end $v1$;
set constraints all deferred;

-- ── V2 · Paridad con mudanza: la fecha nueva cae en septiembre (abierto) ───────────────────────────────────────────────
do $v2$
declare v_k uuid := pg_temp.k('2026-01-910002'); p jsonb; r jsonb;
begin
  begin
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-09-28');
    perform pg_temp.exigir(p ->> 'mes_actual' = '2026-10-01' and p ->> 'mes_resultante' = '2026-09-01'
      and (p ->> 'cambia_mes')::boolean and p ->> 'fecha_comercial_resultante' = '2026-09-28', 'V2: la previa anuncia la mudanza a septiembre');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'La inversión empezó en septiembre',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-911202', 2000, 'PEN', 18, date '2026-09-28'), pg_temp.cuenta(202));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r ->> 'contrato_id')::uuid)
      = (p ->> 'fecha_comercial_resultante')::date and r #>> '{conversion,periodo_despues}' = p ->> 'mes_resultante',
      'V2: el reemplazo deja la fecha y el mes que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V2 paridad: mudanza a un mes abierto';
end $v2$;
set constraints all deferred;

-- ── V3 · Paridad: la venta se registró ANTES de la fecha nueva → manda el día de la venta (20/09) ──────────────────────
do $v3$
declare v_k uuid := pg_temp.k('2026-01-910005'); p jsonb; r jsonb;
begin
  begin
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-10-01');
    perform pg_temp.exigir(p ->> 'fecha_comercial_resultante' = '2026-09-20' and p ->> 'mes_resultante' = '2026-09-01'
      and not (p ->> 'cambia_mes')::boolean, 'V3: la previa dice 20/09 (septiembre), no la fecha de inicio nueva');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Fecha de inicio equivocada',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-911505', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(203));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r ->> 'contrato_id')::uuid)
      = (p ->> 'fecha_comercial_resultante')::date, 'V3: el reemplazo deja la fecha que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V3 paridad: manda el día de registro de la venta';
end $v3$;
set constraints all deferred;

-- ── V4 · Paridad en una CADENA: el contrato que dejó un reemplazo hereda el día de la venta (no su propio registro) ─────
do $v4$
declare v_k uuid := pg_temp.k('2026-01-910005'); r jsonb; p jsonb; r2 jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Fecha de inicio equivocada',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-911515', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(204));
    -- El contrato nuevo se registró HOY (octubre); la previa tiene que seguir diciendo 20/09.
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, date '2026-10-01');
    perform pg_temp.exigir(p ->> 'fecha_comercial_resultante' = '2026-09-20', 'V4: la previa sigue la cadena (20/09)');
    r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, 'Número de contrato equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-911516', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(205));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r2 ->> 'contrato_id')::uuid)
      = (p ->> 'fecha_comercial_resultante')::date, 'V4: el segundo reemplazo deja la fecha que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V4 paridad: cadena de reemplazos';
end $v4$;
set constraints all deferred;

-- ── V5 · Paridad en «quedarme con la otra»: la duplicada cargada después no muda la venta ──────────────────────────────
do $v5$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_dup uuid; p jsonb;
begin
  begin
    set local session_replication_role = replica;
    update public.contratos set fecha_inicio = date '2026-10-03', fecha_vencimiento = date '2027-10-03' where id = v_k;
    set local session_replication_role = origin;
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-911530', 1500, 'PEN', 15, date '2026-10-03'), pg_temp.cuenta(206));
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, null, v_dup);
    perform pg_temp.exigir(p ->> 'fecha_inicio' = '2026-10-03' and p ->> 'fecha_comercial_resultante' = '2026-09-20',
      'V5: la previa usa la fecha de inicio de la que se conserva y el día de la venta');
    perform pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces por error');
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = v_dup) = (p ->> 'fecha_comercial_resultante')::date,
      'V5: «quedarme con la otra» deja la fecha que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V5 paridad: quedarme con la otra';
end $v5$;
set constraints all deferred;

-- ── V5b · «Quedarme con la otra» cuando la fecha de inicio de la conservada es la que manda ───────────────────────────
do $v5b$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_dup uuid; p jsonb;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-911531', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(207));
    -- La previa NO recibe fecha: la toma de la que se conserva (05/10, antes del registro de hoy).
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, null, v_dup);
    perform pg_temp.exigir(p ->> 'fecha_comercial_resultante' = '2026-10-05', 'V5b: manda la fecha de inicio de la que se conserva');
    perform pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces por error');
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = v_dup) = (p ->> 'fecha_comercial_resultante')::date,
      'V5b: «quedarme con la otra» deja la fecha que anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V5b paridad: quedarme con la otra con la fecha de la conservada';
end $v5b$;
set constraints all deferred;

-- ── V6 · Una fecha que Gerencia corrigió a mano se conserva (y la previa lo dice) ─────────────────────────────────────
do $v6$
declare v_k uuid := pg_temp.k('2026-01-910006'); p jsonb; r jsonb;
begin
  begin
    set local session_replication_role = replica;
    update public.contratos set fecha_cierre_comercial = date '2026-10-02', fuente_cierre_comercial = 'correccion_manual' where id = v_k;
    update crm.inversiones set fecha_comercial = date '2026-10-02' where contrato_id = v_k;
    set local session_replication_role = origin;
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-09-15');
    perform pg_temp.exigir(p ->> 'fecha_comercial_resultante' = '2026-10-02' and (p ->> 'fecha_corregida')::boolean
      and not (p ->> 'cambia_mes')::boolean, 'V6: la previa conserva la fecha corregida por Gerencia');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-911606', 7000, 'PEN', 15, date '2026-09-15'), pg_temp.cuenta(208));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r ->> 'contrato_id')::uuid)
      = (p ->> 'fecha_comercial_resultante')::date, 'V6: el reemplazo deja la fecha corregida, como anunció la previa');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V6 paridad: fecha corregida por Gerencia';
end $v6$;
set constraints all deferred;

-- ── V10 · Cuotas pagadas: la previa lo avisa ANTES y el reemplazo se niega igual (una sola regla) ───────────────────
do $v10$
declare v_k uuid := pg_temp.k('2026-01-910003'); p jsonb;
begin
  begin
    set local session_replication_role = replica;
    update public.cronograma_pagos set estado = 'pagado', monto_pagado = monto_programado, fecha_pago_real = date '2026-10-15'
      where contrato_id = v_k and numero_cuota = 1;
    set local session_replication_role = origin;
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-10-07');
    perform pg_temp.exigir((p ->> 'cuotas_pagadas')::boolean, 'V10: la previa avisa las cuotas pagadas');
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-911303', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(209)),
      'P0409', 'cuotas pagadas');
    perform pg_temp.exigir(not exists (select 1 from crm.inversiones_eliminadas), 'V10: no se borró nada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V10 cuotas pagadas: la previa lo avisa y el reemplazo se niega';
end $v10$;
set constraints all deferred;

-- ── V7 · Quién puede pedir la previa y qué valida ─────────────────────────────────────────────────────────────────────
do $v7$
declare v_k uuid := pg_temp.k('2026-01-910006'); v_otro uuid := pg_temp.k('2026-01-910001'); p jsonb;
begin
  begin
    -- Admin del portal sin Gerencia sí la ve (el reemplazo de una VENTA le exigirá Gerencia al confirmar).
    p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a1', v_k, date '2026-10-09');
    perform pg_temp.exigir(p ->> 'mes_resultante' = '2026-10-01', 'V7: admin del portal ve la previa');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a3', v_k, date '2026-10-09'), '42501', 'admin del portal');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a4', v_k, date '2026-10-09'), '42501', 'Solo admin o gerencia');
    perform pg_temp.rechaza(pg_temp.sql_previa(null, v_k, date '2026-10-09'), '42501', 'Inicia sesión');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', gen_random_uuid(), date '2026-10-09'), 'P0002', 'no existe');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, null), '22023', 'fecha de inicio');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, 'infinity'::date), '22023', 'fecha de inicio');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, '-infinity'::date), '22023', 'fecha de inicio');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, null, gen_random_uuid()), 'P0002', 'se conserva');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, null, v_k), '22023', 'la misma');
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a2', v_k, null, v_otro), '22023', 'otro cliente');
    set local session_replication_role = replica;
    insert into crm.equipo (perfil_id, rol_crm, activo) values ('a0000000-0000-4000-8000-0000000000a1', 'vendedor', false);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_previa('a0000000-0000-4000-8000-0000000000a1', v_k, date '2026-10-09'), '42501', 'membresía del CRM está revocada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V7 roles y validaciones de la previa';
end $v7$;

-- ── V8 · La previa no escribe nada ─────────────────────────────────────────────────────────────────────────────────────
do $v8$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_antes bigint; v_despues bigint; p jsonb;
begin
  v_antes := pg_temp.escrituras();
  p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', v_k, date '2026-08-15');
  p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a1', pg_temp.k('2026-01-910001'), date '2026-10-05');
  -- La rama «quedarme con la otra» (k7 y k6 son del mismo cliente).
  p := pg_temp.previa('a0000000-0000-4000-8000-0000000000a2', pg_temp.k('2026-01-910006'), null, pg_temp.k('2026-01-910007'));
  v_despues := pg_temp.escrituras();
  perform pg_temp.exigir(v_antes = v_despues, format('V8: la previa escribió filas (%s → %s)', v_antes, v_despues));
  raise notice 'PASS V8 la previa no escribe (filas escritas en la transacción: % antes y después)', v_antes;
end $v8$;

-- ── V9 · Catálogo: puerta DEFINER solo para authenticated; ayudantes sin EXECUTE para la API; el núcleo los usa ────────
do $v9$
begin
  perform pg_temp.exigir((select p.prosecdef and pg_catalog.has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('anon', p.oid, 'EXECUTE')
      and not pg_catalog.has_function_privilege('service_role', p.oid, 'EXECUTE')
    from pg_catalog.pg_proc p where p.oid = 'crm.reemplazar_inversion_vista_previa_fn(uuid,date,uuid)'::regprocedure),
    'V9: la previa es DEFINER y solo authenticated la ejecuta');
  perform pg_temp.exigir(not exists (select 1 from pg_catalog.pg_proc p cross join unnest(array['anon','authenticated','service_role']) r(rol)
      where p.oid in ('private.reemplazo_dia_registro_venta(uuid)'::regprocedure, 'private.reemplazo_fecha_comercial(uuid,date)'::regprocedure)
        and pg_catalog.has_function_privilege(r.rol, p.oid, 'EXECUTE')), 'V9: los ayudantes no los ejecuta la API');
  perform pg_temp.exigir((select position('private.reemplazo_fecha_comercial(p_fuente, v_fi)' in p.prosrc) > 0
      and position('private.reemplazo_dia_registro_venta(p_fuente)' in p.prosrc) > 0
      and position('private.contrato_tiene_cuotas_pagadas(p_fuente)' in p.prosrc) > 0
      and position('least(v_fi, v_dia_registro)' in p.prosrc) = 0
    from pg_catalog.pg_proc p where p.oid = 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)'::regprocedure),
    'V9: el núcleo usa los ayudantes (una sola regla)');
  raise notice 'PASS V9 catálogo';
end $v9$;

do $fin$
begin
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4 and pg_temp.cuenta_conversion('2026-09-01') = 1
    and not exists (select 1 from crm.inversiones_eliminadas), 'los casos se deshicieron');
  raise notice 'PASS vista_previa: 12 bloques (V1-V5, V5b, V6-V10); se revierte';
end $fin$;
