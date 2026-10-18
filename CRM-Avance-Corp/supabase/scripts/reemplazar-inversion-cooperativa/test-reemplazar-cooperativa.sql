-- Pruebas de 20261018053228 (Reemplazar inversión, Fase 4: cooperativas) en el BANCO Docker reemplazo-inv-db (esquema de
-- producción del 17/10/2026, sin datos de producción). NO se corre sola: probar.sh le antepone la siembra y los ayudantes de la
-- batería de la Fase 1 (../reemplazar-inversion/test-reemplazar-inversion.sql: configuración copiada de producción, plazo de
-- septiembre al 22/10 00:00 Lima, agosto sellado, personas a1 (admin del portal sin CRM), a2 (GER: gerencia + admin), a3
-- (gerencia sola), a4/a7 (vendedores), a6 (supervisor), empresas avance/prodelco (PEN, USD)/qorilazo (PEN), pesos de
-- conversión) y aplica la migración en la marca «@@ MIGRACION @@». Todo termina en ROLLBACK.
--
-- Siembra propia: leads convertidos f1..f6 con su inversionista (sin portal) y su inversión INICIAL de cooperativa K1..K6
-- (crm.cierres_externos + depósito reclamado + crm.inversiones por private.inversion_vincular_fuente + evento «registro»),
-- con el comprobante como objeto del bucket (storage.objects del banco, sin políticas). La venta se acredita al insertar el
-- cierre (trigger de acreditación). K4 es un aporte adicional (no inicial, sin lead); K5 se anula con la puerta real.

-- ── Ayudantes ──────────────────────────────────────────────────────────────────────────────────────────────────────────
create temporary table sembrados (clave text primary key, id uuid not null);
create function pg_temp.sembrado(p_clave text) returns uuid language sql stable as $$
  select s.id from pg_temp.sembrados s where s.clave = p_clave $$;

-- Lead fN convertido por p_analista el p_convertido (sin perfil del portal: es una venta de cooperativa) y su inversionista bN.
create function pg_temp.lead_coop(p_n int, p_analista uuid, p_convertido timestamptz, p_origen text default 'landing') returns void language plpgsql as $f$
declare
  v_lead uuid := ('f2000000-0000-4000-8000-00000000000' || p_n)::uuid;
  v_inv uuid := ('b2000000-0000-4000-8000-00000000000' || p_n)::uuid;
begin
  set local session_replication_role = replica;
  insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, vendedor_id, activo, monto_estimado)
    values (v_lead, 'LEAD COOP ' || p_n || ' PRUEBA', '+5199700000' || p_n, '4200000' || p_n, p_origen, 'convertido',
      p_convertido, p_analista, true, 1000);
  insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
      sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado,
      resultado_en, finalizado_en, finalizado_por, motivo_cierre)
    values (v_lead, 1, 1, p_analista, 'asignado', p_convertido - interval '5 days', 'PEN', p_origen,
      p_convertido - interval '5 days', gen_random_uuid(), p_convertido, p_convertido, 'convertido', p_convertido,
      p_convertido, p_analista, 'convertido');
  insert into crm.inversionistas (id, estado, perfil_id, responsable_relacion_id, no_contactar, creado_por)
    values (v_inv, 'activo', null, p_analista, false, 'a0000000-0000-4000-8000-0000000000a2');
  set local session_replication_role = origin;
end $f$;

-- Un objeto del bucket de comprobantes (el banco no tiene políticas de storage: la fila basta para la FK y la validación).
create function pg_temp.objeto(p_ruta text, p_bytes bigint default 1000, p_mime text default 'application/pdf') returns uuid language plpgsql as $f$
declare v_id uuid := gen_random_uuid();
begin
  insert into storage.objects (id, bucket_id, name, metadata, is_delete_marker, is_versioned)
    values (v_id, 'f4-comprobantes', p_ruta, jsonb_build_object('size', p_bytes, 'mimetype', p_mime), false, false);
  return v_id;
end $f$;

-- La inversión INICIAL de cooperativa del lead fN: cierre KN con su comprobante, depósito, fila de inversión y evento «registro».
-- Triggers encendidos: la venta se acredita al insertar el cierre. Devuelve el id del cierre.
create function pg_temp.coop(p_n int, p_coop text, p_monto numeric, p_moneda text, p_fecha date, p_analista uuid,
  p_inicial boolean default true) returns uuid language plpgsql as $f$
declare
  v_lead uuid := case when p_inicial then ('f2000000-0000-4000-8000-00000000000' || p_n)::uuid end;
  v_inv uuid := ('b2000000-0000-4000-8000-00000000000' || p_n)::uuid;
  v_obj uuid := pg_temp.objeto(v_inv::text || '/' || gen_random_uuid()::text || '/comprobante.pdf');
  v_k uuid := gen_random_uuid();
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
begin
  insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
    numero_transaccion, referencia_externa, vence_en, nota, vendedor_id, creado_por, creado_en, inversionista_id,
    es_cierre_inicial, fecha_comercial, fecha_imputacion, comprobante_objeto_id, plazo_meses, tasa_anual, base_plazo)
  values (v_k, v_lead, p_coop, p_monto, p_moneda, 'DNI', '4200000' || p_n, 'CLIENTE COOP ' || p_n || ' PRUEBA',
    'OP-' || p_n || '-PRUEBA', 'ref ' || p_n, (p_fecha + interval '12 months')::date, null, p_analista, a2, p_fecha::timestamp at time zone 'America/Lima' + interval '10 hours',
    v_inv, p_inicial, p_fecha, p_fecha, v_obj, 12, 10.00, 'calendario');
  insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por) values ('OP-' || p_n || '-PRUEBA', v_k, a2);
  perform private.inversion_vincular_fuente(v_inv, null, v_k, a2, p_inicial);
  insert into crm.inversion_eventos (inversion_id, tipo, creado_por)
    select i.id, 'registro', a2 from crm.inversiones i where i.cierre_externo_id = v_k;
  insert into pg_temp.sembrados values ('k' || p_n, v_k);
  return v_k;
end $f$;

create function pg_temp.cierres_validos(p_lead uuid) returns bigint language sql as $$
  select count(*) from private.conversion_episodios(timestamptz '2026-09-01 00:00:00-05', pg_catalog.clock_timestamp(), null, true, null, 1) x
  where x.tipo = 'cierre' and x.lead_id = p_lead and not x.anulado and x.aporte_numerador > 0 $$;

-- El reemplazo como p_uid (authenticated con su sesión), con el p_cierre dado.
create function pg_temp.sql_reemplazar(p_uid uuid, p_fuente uuid, p_motivo text, p_cierre jsonb) returns text language sql as $$
  select format('select pg_temp.api(%L::uuid, %L)', p_uid,
    format('select crm.reemplazar_inversion_cooperativa_fn(%L::uuid, %L, %L::jsonb)', p_fuente, p_motivo, p_cierre)) $$;
create function pg_temp.reemplazar(p_uid uuid, p_fuente uuid, p_motivo text, p_cierre jsonb) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  execute pg_temp.sql_reemplazar(p_uid, p_fuente, p_motivo, p_cierre) into r;
  return r;
exception when others then
  reset role;
  if sqlstate = 'P7999' then raise; end if;
  raise exception 'FALLA: el reemplazo debió aplicarse y falló con % «%»', sqlstate, sqlerrm;
end $f$;
create function pg_temp.previa(p_uid uuid, p_fuente uuid, p_fecha date default null) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  r := pg_temp.api(p_uid, format('select crm.reemplazar_inversion_cooperativa_vista_previa_fn(%L::uuid, %L::date)', p_fuente, p_fecha));
  return r;
end $f$;

-- ── S · Siembra ────────────────────────────────────────────────────────────────────────────────────────────────────────
-- Hecho del banco: storage.objects viene del volcado sin sus grants; en producción postgres tiene UPDATE (el alta de
-- cooperativa hace `for key share` sobre el comprobante y funciona). Se concede aquí, dentro de la transacción.
grant select, update on storage.objects to postgres;
do $s$
declare
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a7 constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
  v uuid;
begin
  perform pg_temp.lead_coop(1, a4, '2026-10-10 15:00-05');
  perform pg_temp.lead_coop(2, a7, '2026-10-12 15:00-05');
  perform pg_temp.lead_coop(3, a4, '2026-09-20 15:00-05');
  perform pg_temp.lead_coop(5, a4, '2026-10-08 15:00-05');
  perform pg_temp.lead_coop(6, a7, '2026-10-14 15:00-05');
  -- K4: aporte adicional (no inicial, sin lead) de la persona b2; su inversionista existe por el lead 2.
  v := pg_temp.coop(1, 'prodelco', 3000, 'PEN', date '2026-10-10', a4);
  v := pg_temp.coop(2, 'qorilazo', 2500, 'PEN', date '2026-10-12', a7);
  v := pg_temp.coop(3, 'prodelco', 4000, 'PEN', date '2026-09-20', a4);
  v := pg_temp.coop(5, 'prodelco', 1500, 'PEN', date '2026-10-08', a4);
  v := pg_temp.coop(6, 'prodelco', 700, 'USD', date '2026-10-14', a7);
  -- K4 cuelga del inversionista b2 (el de K2): no inicial, sin lead.
  insert into pg_temp.sembrados values ('b4', 'b2000000-0000-4000-8000-000000000002');
  set constraints all immediate; set constraints all deferred;
end $s$;
do $s4$
declare
  a7 constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  v_inv uuid := 'b2000000-0000-4000-8000-000000000002';
  v_obj uuid := pg_temp.objeto(v_inv::text || '/' || gen_random_uuid()::text || '/comprobante.pdf');
  v_k uuid := gen_random_uuid();
begin
  insert into crm.cierres_externos (id, lead_id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo,
    numero_transaccion, referencia_externa, vence_en, nota, vendedor_id, creado_por, creado_en, inversionista_id,
    es_cierre_inicial, fecha_comercial, fecha_imputacion, comprobante_objeto_id, plazo_meses, tasa_anual, base_plazo)
  values (v_k, null, 'qorilazo', 900, 'PEN', 'DNI', '42000002', 'CLIENTE COOP 2 PRUEBA', 'OP-4-PRUEBA', 'aporte adicional',
    date '2027-10-13', null, a7, a2, timestamptz '2026-10-13 15:00-05', v_inv, false, date '2026-10-13', date '2026-10-13', v_obj, 12, 10.00, 'calendario');
  insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por) values ('OP-4-PRUEBA', v_k, a2);
  perform private.inversion_vincular_fuente(v_inv, null, v_k, a2, false);
  insert into crm.inversion_eventos (inversion_id, tipo, creado_por) select i.id, 'registro', a2 from crm.inversiones i where i.cierre_externo_id = v_k;
  insert into pg_temp.sembrados values ('k4', v_k);
  set constraints all immediate; set constraints all deferred;
  -- K5 se anula con la puerta real de Gerencia (la venta de f5 queda anulada; el cierre sigue).
  perform pg_temp.api(a2, format('select crm.anular_cierre_externo(%L::uuid, %L)', pg_temp.sembrado('k5'), 'Anulada en el banco para probar el rechazo'));
  set constraints all immediate; set constraints all deferred;
end $s4$;

do $s1$
declare c record;
begin
  for c in select n, ('f2000000-0000-4000-8000-00000000000' || n)::uuid as lead, pg_temp.sembrado('k' || n) as k from unnest(array[1, 2, 3, 6]) n loop
    perform pg_temp.exigir((pg_temp.acr(c.lead)).fuente_tipo = 'cierre_externo' and (pg_temp.acr(c.lead)).fuente_id = c.k
        and (pg_temp.acr(c.lead)).estado = 'acreditada' and pg_temp.cierres_validos(c.lead) = 1 and not private.cierre_anulado(c.lead),
      format('S K%s: la venta del lead está acreditada al cierre inicial y cuenta', c.n));
    perform pg_temp.exigir(exists (select 1 from crm.inversiones i where i.cierre_externo_id = c.k and i.es_primera_conversion and i.estado = 'vigente'),
      format('S K%s: la inversión existe, vigente y marcada como primera conversión', c.n));
  end loop;
  perform pg_temp.exigir((pg_temp.acr('f2000000-0000-4000-8000-000000000003')).periodo_comercial = date '2026-09-01'
      and (pg_temp.acr('f2000000-0000-4000-8000-000000000001')).periodo_comercial = date '2026-10-01',
    'S: K3 cuenta en septiembre y K1 en octubre');
  perform pg_temp.exigir(private.cierre_anulado('f2000000-0000-4000-8000-000000000005')
      and (select ce.anulado_en is not null from crm.cierres_externos ce where ce.id = pg_temp.sembrado('k5')),
    'S K5: anulada por la puerta real');
  perform pg_temp.exigir(not exists (select 1 from crm.conversion_acreditaciones ca where ca.fuente_id = pg_temp.sembrado('k4'))
      and (select not ce.es_cierre_inicial and ce.lead_id is null from crm.cierres_externos ce where ce.id = pg_temp.sembrado('k4')),
    'S K4: aporte adicional sin venta');
  perform pg_temp.exigir(to_regprocedure('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)') is null,
    'S: la puerta de cooperativas todavía no existe (la migración va después)');
  raise notice 'PASS S siembra: 5 ventas de cooperativa acreditadas (K1 prodelco oct, K2 qorilazo oct, K3 prodelco sep, K6 prodelco USD) + K4 aporte adicional + K5 anulada';
end $s1$;

-- La migración exige el candado de SESIÓN de migraciones; la prueba lo toma como lo haría la migración.
select pg_catalog.pg_advisory_lock(pg_catalog.hashtext('crm_migracion_funciones'));
-- @@ MIGRACION @@
select pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('crm_migracion_funciones'));
select pg_temp.como(null);

-- ── C · Catálogo tras la migración ──────────────────────────────────────────────────────────────────────────────────────
do $c$
begin
  perform pg_temp.exigir(to_regprocedure('crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)') is not null
      and to_regprocedure('crm.reemplazar_inversion_cooperativa_vista_previa_fn(uuid,date)') is not null
      and to_regprocedure('private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)') is not null
      and to_regprocedure('private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)') is not null
      and to_regprocedure('private.f4_comprobante_reemplazo_autorizado(text)') is not null, 'C: las cinco funciones existen');
  perform pg_temp.exigir(not exists (select 1 from unnest(array['anon', 'authenticated', 'service_role']) r(rol)
      where has_function_privilege(r.rol, 'private.reemplazar_inversion_cooperativa(uuid,jsonb,uuid,text,jsonb)', 'execute')
         or has_function_privilege(r.rol, 'private.registrar_inversion_reemplazada_cooperativa(jsonb,uuid,text,text,uuid,jsonb)', 'execute'))
      and has_function_privilege('authenticated', 'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)', 'execute')
      and not has_function_privilege('anon', 'crm.reemplazar_inversion_cooperativa_fn(uuid,text,jsonb)', 'execute'),
    'C: el núcleo sin EXECUTE para la API; la puerta solo authenticated');
  raise notice 'PASS C catálogo: funciones, permisos';
end $c$;

-- ── P · Vista previa ───────────────────────────────────────────────────────────────────────────────────────────────────
do $p$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a1 constant uuid := 'a0000000-0000-4000-8000-0000000000a1';
  r jsonb;
begin
  r := pg_temp.previa(a2, pg_temp.sembrado('k1'), date '2026-09-15');
  perform pg_temp.exigir(r ->> 'cooperativa' = 'prodelco' and (r ->> 'es_inicial')::boolean and not (r ->> 'anulada')::boolean
      and (r ->> 'venta_de_lead')::boolean and (r ->> 'comprobante')::boolean
      and (r ->> 'mes_actual')::date = date '2026-10-01' and (r ->> 'mes_resultante')::date = date '2026-09-01'
      and (r ->> 'cambia_mes')::boolean and not (r ->> 'mes_sellado')::boolean and not (r ->> 'plazo_vencido')::boolean
      and not (r ->> 'fecha_futura')::boolean and r ->> 'no_reemplazable' is null,
    format('P1 K1 al 15/09: la venta quedaría en septiembre, nada lo impide (%s)', r));
  r := pg_temp.previa(a2, pg_temp.sembrado('k1'));
  perform pg_temp.exigir(not (r ->> 'cambia_mes')::boolean and (r ->> 'fecha_comercial_resultante')::date = date '2026-10-10',
    'P2 K1 sin fecha: el mes de hoy, sin cambio');
  r := pg_temp.previa(a2, pg_temp.sembrado('k4'));
  perform pg_temp.exigir(not (r ->> 'es_inicial')::boolean and not (r ->> 'venta_de_lead')::boolean and r ->> 'no_reemplazable' like 'Solo se reemplaza la inversión inicial%',
    'P3 K4 aporte adicional: no reemplazable');
  r := pg_temp.previa(a2, pg_temp.sembrado('k5'));
  perform pg_temp.exigir((r ->> 'anulada')::boolean and r ->> 'no_reemplazable' like '%ya fue anulada%', 'P4 K5 anulada: no reemplazable');
  r := pg_temp.previa('a0000000-0000-4000-8000-0000000000a3', pg_temp.sembrado('k2'), date '2026-10-01');
  perform pg_temp.exigir(r ->> 'cooperativa' = 'qorilazo' and not (r ->> 'cambia_mes')::boolean, 'P5 Gerencia sin portal también consulta');
  perform pg_temp.rechaza(format('select pg_temp.previa(%L::uuid, %L::uuid)', a1, pg_temp.sembrado('k1')), '42501', 'Solo gerencia puede reemplazar una inversión de cooperativa');
  perform pg_temp.rechaza(format('select pg_temp.previa(%L::uuid, %L::uuid)', a4, pg_temp.sembrado('k1')), '42501', 'Solo admin o gerencia');
  perform pg_temp.rechaza(format('select pg_temp.previa(%L::uuid, %L::uuid)', a2, gen_random_uuid()), 'P0002', 'no existe');
  perform pg_temp.rechaza(format('select pg_temp.previa(%L::uuid, %L::uuid, %L::date)', a2, pg_temp.sembrado('k1'), 'infinity'), '22023', 'fecha comercial no es válida');
  r := pg_temp.previa(a2, pg_temp.sembrado('k1'), date '2099-01-01');
  perform pg_temp.exigir((r ->> 'fecha_futura')::boolean, 'P6 fecha futura: avisada');
  raise notice 'PASS P vista previa: mes resultante, cambia_mes, no reemplazable (aporte adicional, anulada), roles, fecha futura';
end $p$;

-- ── R · Rechazos de la puerta y del núcleo (cada uno deshace lo suyo) ───────────────────────────────────────────────────
do $r$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a6 constant uuid := 'a0000000-0000-4000-8000-0000000000a6';
  k1 uuid := pg_temp.sembrado('k1');
  k6 uuid := pg_temp.sembrado('k6');
  v_contrato uuid := (select l.contrato_id from crm.leads l where l.id = 'd1000000-0000-4000-8000-000000000001');
  cambio constant jsonb := '{"fecha_comercial": "2026-09-15"}';
begin
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a4, k1, 'Error de carga de prueba', cambio), '42501', 'Solo admin o gerencia');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a6, k1, 'Error de carga de prueba', cambio), '42501', 'Solo admin o gerencia');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', k1, 'Error de carga de prueba', cambio), '42501', 'Solo gerencia puede reemplazar una inversión de cooperativa');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '[1]'), '22023', 'datos del reemplazo no son válidos');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'abc', cambio), '22023', 'motivo del reemplazo');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, repeat('x', 301), cambio), '22023', 'como máximo 300');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, null, 'Error de carga de prueba', cambio), '22023', 'Indica la inversión');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, gen_random_uuid(), 'Error de carga de prueba', cambio), 'P0002', 'no existe o ya fue eliminada');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"monto": 1}'), '22023', 'cambia solo la cooperativa, la fecha comercial y el comprobante');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{}'), '22023', 'Nada que reemplazar');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"cooperativa": "prodelco", "fecha_comercial": "2026-10-10"}'), '22023', 'Nada que reemplazar');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2099-01-01"}'), '22023', 'no puede ser futura');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "no es fecha"}'), '22023', 'fecha comercial no es válida');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"cooperativa": "otra"}'), '22023', 'cooperativa indicada no existe');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k6, 'Error de carga de prueba', '{"cooperativa": "qorilazo"}'), 'P0409', 'no admite inversiones en USD');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, pg_temp.sembrado('k4'), 'Error de carga de prueba', cambio), 'P0409', 'Solo se reemplaza la inversión inicial');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, pg_temp.sembrado('k5'), 'Error de carga de prueba', cambio), 'P0409', 'ya fue anulada');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, v_contrato, 'Error de carga de prueba', cambio), '0A000', 'puerta de Avance');
  -- El comprobante: un objeto VÁLIDO en la carpeta de otra persona, o de otra inversión de la misma persona; inexistente; grande;
  -- otro mimetype; uno que ya respalda otra inversión viva.
  perform pg_temp.objeto('b2000000-0000-4000-8000-000000000002/reemplazo-' || k1 || '/x.pdf');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000002/reemplazo-' || k1 || '/x.pdf')), '22023', 'carpeta de esta inversión');
  perform pg_temp.objeto('b2000000-0000-4000-8000-000000000001/reemplazo-' || pg_temp.sembrado('k3') || '/x.pdf');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || pg_temp.sembrado('k3') || '/x.pdf')), '22023', 'carpeta de esta inversión');
  perform pg_temp.objeto('b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/texto.pdf', 1000, 'text/plain');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/texto.pdf')), 'P0409', 'Sube el comprobante válido');
  perform pg_temp.objeto('b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/ajeno.pdf');
  set local session_replication_role = replica;
  update crm.cierres_externos set comprobante_objeto_id = (select o.id from storage.objects o where o.name = 'b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/ajeno.pdf')
    where id = pg_temp.sembrado('k3');
  set local session_replication_role = origin;
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/ajeno.pdf')), 'P0409', 'ya respalda otra inversión');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/no-existe.pdf')), 'P0409', 'Sube el comprobante válido');
  perform pg_temp.objeto('b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/grande.pdf', 20000000);
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba',
      jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || k1 || '/grande.pdf')), 'P0409', 'Sube el comprobante válido');
  raise notice 'PASS R1 rechazos: roles (solo Gerencia), motivo, fuente, p_cierre, claves ajenas, nada que reemplazar, fecha futura/inválida, cooperativa, moneda, aporte adicional, anulada, Avance, comprobante (carpeta de ESTA inversión, inexistente, grande, mimetype, ya usado)';
end $r$;

-- Mes sellado, plazo vencido y movimientos: estado preparado en una subtransacción que se deshace con el centinela P7999.
do $r2$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  k1 uuid := pg_temp.sembrado('k1');
  k3 uuid := pg_temp.sembrado('k3');
begin
  begin
    set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-10-01', now(), a2, false, 1, 0, '{}');
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-10-03"}'), 'P0409', 'ya está cerrado');
    perform pg_temp.exigir((pg_temp.previa(a2, k1, date '2026-10-03') ->> 'mes_sellado')::boolean, 'R2a: la vista previa avisa el mes sellado');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    set local session_replication_role = replica;
    insert into crm.capital_mes_sellos (periodo, corte_id) values ('2026-09-01', gen_random_uuid());
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), 'P0409', 'ya está cerrado');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    -- El plazo de carga de septiembre vencido: K3 (venta de septiembre) no se puede re-acreditar.
    set local session_replication_role = replica;
    insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por, decidido_en)
      values ('2026-09-01', '2026-10-10', timestamptz '2026-10-11 00:00-05', 'banco: plazo vencido', a2, now());
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k3, 'Error de carga de prueba', '{"cooperativa": "qorilazo"}'), 'P0409', 'Venció el plazo de carga de 09/2026');
    perform pg_temp.exigir((pg_temp.previa(a2, k3) ->> 'plazo_vencido')::boolean, 'R2c: la vista previa avisa el plazo vencido');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    -- Movimientos: una solicitud de retiro sobre K1 (la regla canónica de «Eliminar inversión»).
    set local session_replication_role = replica;
    insert into crm.postventa_retiros (id, inversionista_id, fuente_id, empresa, estado, motivo, creado_por)
      values (gen_random_uuid(), 'b2000000-0000-4000-8000-000000000001', k1, 'prodelco', 'solicitada', 'Retiro de prueba', a2);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), 'P0409', 'retiro');
    perform pg_temp.exigir(pg_temp.previa(a2, k1) ->> 'no_reemplazable' like '%retiro%', 'R2d: la vista previa avisa los movimientos');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    -- Membresía del CRM revocada (Gerencia dada de baja en crm.equipo, pero sigue siendo admin del portal).
    set local session_replication_role = replica;
    update crm.equipo set activo = false where perfil_id = a2;
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), '42501', 'Solo gerencia puede reemplazar');
    perform pg_temp.rechaza(format('select pg_temp.previa(%L::uuid, %L::uuid)', a2, k1), '42501', 'Solo gerencia puede reemplazar');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    -- Un origen de capital confirmado por Gerencia sobre K1: no se traslada a ciegas.
    set local session_replication_role = replica;
    insert into crm.origenes_capital_confirmados (id, cierre_externo_id, origen, motivo, confirmado_por, activo, fecha_comercial)
      values (gen_random_uuid(), k1, 'oficina', 'Confirmación de prueba del banco', a2, true, date '2026-10-10');
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), 'P0409', 'origen de capital confirmado');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.exigir(exists (select 1 from crm.cierres_externos ce where ce.id = k1) and pg_temp.cierres_validos('f2000000-0000-4000-8000-000000000001') = 1,
    'R2: nada cambió tras los rechazos');
  raise notice 'PASS R2 rechazos con estado: mes sellado (conversión y capital), plazo vencido, movimientos, membresía revocada, origen confirmado; la vista previa los avisa';
end $r2$;

do $r3$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  k1 uuid := pg_temp.sembrado('k1');
begin
  begin
    -- La venta de f1 acreditada a OTRA fuente (K4, el aporte adicional, sin venta propia): mover el cierre movería una venta
    -- que no es suya. Revisión.
    set local session_replication_role = replica;
    update crm.conversion_acreditaciones set fuente_id = pg_temp.sembrado('k4') where lead_id = 'f2000000-0000-4000-8000-000000000001';
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), 'P0409', 'acreditada a otra inversión');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  begin
    -- La red final (invariante): si el escritor de acreditaciones dejara la venta en otro estado (regla del plazo cambiada en
    -- private.conversion_decidir_plazo, que el preflight no mira), el reemplazo aborta TODO con un mensaje claro.
    create or replace function private.conversion_decidir_plazo(p_fecha_comercial date, p_confirmado_en timestamp with time zone,
      p_vinculado_en timestamp with time zone, p_sellado_en timestamp with time zone)
    returns table(periodo_comercial date, plazo_hasta timestamp with time zone, acreditado_en timestamp with time zone, estado text)
    language plpgsql stable set search_path to '' as $f$
    begin
      periodo_comercial := pg_catalog.date_trunc('month', p_fecha_comercial::timestamp)::date;
      plazo_hasta := private.conversion_plazo_hasta(periodo_comercial);
      acreditado_en := greatest(p_confirmado_en, p_vinculado_en);
      estado := 'fuera_de_plazo';
      return next;
    end $f$;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Error de carga de prueba', '{"fecha_comercial": "2026-09-15"}'), 'P0409', 'el reemplazo no puede conservar la venta');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.exigir((pg_temp.acr('f2000000-0000-4000-8000-000000000001')).fuente_id = k1 and exists (select 1 from crm.cierres_externos where id = k1),
    'R3: nada cambió');
  raise notice 'PASS R3: la venta acreditada a otra inversión se niega; la red del invariante aborta todo';
end $r3$;

-- ── V · Reemplazos que deben pasar (cada uno en una subtransacción que se deshace) ──────────────────────────────────────
-- V1 · K1 cambia de mes (10/10 → 15/09): la venta de f1 se muda a septiembre; todo lo demás, igual.
do $v1$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  f1 constant uuid := 'f2000000-0000-4000-8000-000000000001';
  k1 uuid := pg_temp.sembrado('k1');
  v_cap_oct jsonb := pg_temp.foto_capital('2026-10-01');
  v_cap_sep jsonb := pg_temp.foto_capital('2026-09-01');
  v_antes crm.cierres_externos%rowtype;
  v_acr_antes crm.conversion_acreditaciones%rowtype := pg_temp.acr(f1);
  v_inv_antes uuid := (select i.id from crm.inversiones i where i.cierre_externo_id = k1);
  v_oct numeric := pg_temp.cuenta_conversion('2026-10-01');
  v_sep numeric := pg_temp.cuenta_conversion('2026-09-01');
  r jsonb; r2 jsonb; v_nuevo uuid; v_ce crm.cierres_externos%rowtype; v_copia crm.inversiones_eliminadas%rowtype;
begin
  select * into v_antes from crm.cierres_externos where id = k1;
  begin
    r := pg_temp.reemplazar(a2, k1, 'La fecha se registró mal', '{"fecha_comercial": "2026-09-15"}');
    v_nuevo := (r ->> 'cierre_id')::uuid;
    perform pg_temp.exigir((r ->> 'ok')::boolean and r ->> 'modo' = 'nueva' and (r ->> 'fuente_id')::uuid = k1 and v_nuevo is not null and v_nuevo <> k1
        and r ->> 'cooperativa' = 'prodelco' and (r ->> 'fecha_comercial')::date = date '2026-09-15' and (r ->> 'vence_en')::date = date '2027-09-15'
        and not (r ->> 'comprobante_cambiado')::boolean and (r #>> '{conversion,periodo_antes}')::date = date '2026-10-01'
        and (r #>> '{conversion,periodo_despues}')::date = date '2026-09-01' and r #>> '{conversion,estado}' = 'acreditada',
      format('V1: el acuse (%s)', r));
    select * into v_ce from crm.cierres_externos where id = v_nuevo;
    perform pg_temp.exigir(not exists (select 1 from crm.cierres_externos where id = k1) and v_ce.id is not null, 'V1: la original ya no está y la nueva sí');
    perform pg_temp.exigir(v_ce.lead_id = f1 and v_ce.cooperativa = 'prodelco' and v_ce.monto = v_antes.monto and v_ce.moneda = v_antes.moneda
        and v_ce.documento = v_antes.documento and v_ce.nombre_completo = v_antes.nombre_completo and v_ce.numero_transaccion = v_antes.numero_transaccion
        and v_ce.referencia_externa = v_antes.referencia_externa and v_ce.vendedor_id = v_antes.vendedor_id and v_ce.inversionista_id = v_antes.inversionista_id
        and v_ce.es_cierre_inicial and v_ce.fecha_comercial = date '2026-09-15' and v_ce.fecha_imputacion = date '2026-09-15'
        and v_ce.comprobante_objeto_id = v_antes.comprobante_objeto_id and v_ce.plazo_meses = 12 and v_ce.tasa_anual = 10 and v_ce.base_plazo = 'calendario'
        and v_ce.vence_en = date '2027-09-15' and v_ce.creado_por = a2 and v_ce.anulado_en is null,
      'V1: la nueva copia todo de la original salvo la fecha (y el vencimiento, 12 meses después)');
    perform pg_temp.exigir((select count(*) from crm.depositos_reclamados d where d.cierre_id = v_nuevo and d.numero_norm = 'OP-1-PRUEBA') = 1
        and not exists (select 1 from crm.depositos_reclamados d where d.cierre_id = k1), 'V1: el depósito reclamado pasa a la nueva');
    perform pg_temp.exigir(exists (select 1 from crm.inversiones i where i.cierre_externo_id = v_nuevo and i.es_primera_conversion and i.estado = 'vigente'
          and i.fecha_comercial = date '2026-09-15' and i.inversionista_id = 'b2000000-0000-4000-8000-000000000001'
          and i.empresa_id = (select e.id from crm.empresas e where e.clave = 'prodelco'))
        and not exists (select 1 from crm.inversiones i where i.id = v_inv_antes)
        and exists (select 1 from crm.inversion_eventos e join crm.inversiones i on i.id = e.inversion_id
                    where i.cierre_externo_id = v_nuevo and e.tipo = 'registro' and e.motivo like 'Reemplazo de inversión:%')
        and exists (select 1 from crm.inversion_titulares t join crm.inversiones i on i.id = t.inversion_id
                    where i.cierre_externo_id = v_nuevo and t.rol = 'principal' and t.inversionista_id = 'b2000000-0000-4000-8000-000000000001'),
      'V1: la fila de inversión nueva (primera conversión, vigente, con su evento y su titular); la vieja no está');
    select * into v_copia from crm.inversiones_eliminadas e where e.fuente_tipo = 'cierre_externo' and e.fuente_id = k1;
    perform pg_temp.exigir(v_copia.id is not null and (r ->> 'auditoria_id')::uuid = v_copia.id and v_copia.reemplazada_por = v_nuevo
        and v_copia.es_conversion and not v_copia.conversion_anulada and v_copia.anulacion is null and v_copia.lead_id = f1
        and v_copia.rol_actor = 'gerencia' and v_copia.eliminado_por = a2 and v_copia.empresa = 'prodelco'
        and v_copia.snapshot #>> '{cierre,id}' = k1::text and (v_copia.snapshot #>> '{reemplazo,cambios,fecha_comercial,despues}')::date = date '2026-09-15'
        and (v_copia.snapshot #>> '{reemplazo,acreditacion_antes,id}')::uuid = v_acr_antes.id
        and v_copia.archivos @> jsonb_build_array(jsonb_build_object('tipo', 'comprobante', 'objeto_id', v_antes.comprobante_objeto_id)),
      'V1: la copia «reemplazada por» con la venta vigente, el actor, los cambios y el comprobante');
    perform pg_temp.exigir((pg_temp.acr(f1)).id = v_acr_antes.id and (pg_temp.acr(f1)).fuente_tipo = 'cierre_externo' and (pg_temp.acr(f1)).fuente_id = v_nuevo
        and (pg_temp.acr(f1)).estado = 'acreditada' and (pg_temp.acr(f1)).periodo_comercial = date '2026-09-01'
        and (pg_temp.acr(f1)).episodio_id = v_acr_antes.episodio_id and (pg_temp.acr(f1)).analista_id = v_acr_antes.analista_id
        and not private.cierre_anulado(f1) and pg_temp.cierres_validos(f1) = 1,
      'V1: la MISMA venta (acreditación, episodio, analista) ahora en septiembre y a la nueva fuente');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = v_oct - 1 and pg_temp.cuenta_conversion('2026-09-01') = v_sep + 1,
      format('V1: la conversión se muda de octubre a septiembre (oct %s → %s, sep %s → %s)', v_oct, pg_temp.cuenta_conversion('2026-10-01'), v_sep, pg_temp.cuenta_conversion('2026-09-01')));
    set constraints all immediate; set constraints all deferred;
    perform pg_temp.exigir(coalesce((pg_temp.foto_capital('2026-10-01') ->> 'PEN')::numeric, 0) = coalesce((v_cap_oct ->> 'PEN')::numeric, 0) - 3000
        and coalesce((pg_temp.foto_capital('2026-09-01') ->> 'PEN')::numeric, 0) = coalesce((v_cap_sep ->> 'PEN')::numeric, 0) + 3000,
      format('V1: el capital de K1 (3 000 PEN) se muda de octubre a septiembre (oct %s → %s, sep %s → %s)', v_cap_oct, pg_temp.foto_capital('2026-10-01'), v_cap_sep, pg_temp.foto_capital('2026-09-01')));
    -- Idempotencia: el mismo pedido devuelve lo mismo; otro pedido, se niega.
    r2 := pg_temp.reemplazar(a2, k1, 'La fecha se registró mal', '{"fecha_comercial": "2026-09-15"}');
    perform pg_temp.exigir((r2 ->> 'idempotente')::boolean and (r2 ->> 'cierre_id')::uuid = v_nuevo and (r2 ->> 'auditoria_id')::uuid = v_copia.id,
      'V1: un reintento con los mismos datos devuelve el mismo resultado');
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k1, 'Otro intento', '{"fecha_comercial": "2026-09-16"}'), 'P0409', 'ya se reemplazó con otros datos');
    -- La nueva se puede volver a reemplazar (encadenado), y la vieja copia sigue apuntando a la primera.
    r2 := pg_temp.reemplazar(a2, v_nuevo, 'Segunda corrección', '{"cooperativa": "qorilazo"}');
    perform pg_temp.exigir((r2 ->> 'ok')::boolean and (r2 ->> 'cierre_id')::uuid <> v_nuevo and r2 ->> 'cooperativa' = 'qorilazo'
        and (pg_temp.acr(f1)).fuente_id = (r2 ->> 'cierre_id')::uuid and (pg_temp.acr(f1)).periodo_comercial = date '2026-09-01'
        and (select e.reemplazada_por from crm.inversiones_eliminadas e where e.fuente_id = v_nuevo) = (r2 ->> 'cierre_id')::uuid,
      'V1: la nueva se reemplaza otra vez (cadena) y la venta la sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.exigir(exists (select 1 from crm.cierres_externos where id = k1) and (pg_temp.acr(f1)).fuente_id = k1
      and pg_temp.cuenta_conversion('2026-10-01') = v_oct, 'V1: deshecho, todo como antes');
  raise notice 'PASS V1 cambio de fecha: la venta se muda de mes, la copia «reemplazada por», idempotencia y cadena';
end $v1$;

-- V2 · K2 cambia de cooperativa (qorilazo → prodelco), mismo mes; lo hace Gerencia SIN ser admin del portal (a3).
do $v2$
declare
  a1 constant uuid := 'a0000000-0000-4000-8000-0000000000a3';
  f2 constant uuid := 'f2000000-0000-4000-8000-000000000002';
  k2 uuid := pg_temp.sembrado('k2');
  v_acr_antes crm.conversion_acreditaciones%rowtype := pg_temp.acr(f2);
  v_oct numeric := pg_temp.cuenta_conversion('2026-10-01');
  r jsonb; v_nuevo uuid;
begin
  begin
    r := pg_temp.reemplazar(a1, k2, 'Se registró en la cooperativa equivocada', '{"cooperativa": "prodelco"}');
    v_nuevo := (r ->> 'cierre_id')::uuid;
    perform pg_temp.exigir((r ->> 'ok')::boolean and r ->> 'cooperativa' = 'prodelco' and (r ->> 'fecha_comercial')::date = date '2026-10-12'
        and (r #>> '{conversion,periodo_antes}')::date = (r #>> '{conversion,periodo_despues}')::date, format('V2: el acuse (%s)', r));
    perform pg_temp.exigir((select ce.cooperativa = 'prodelco' and ce.fecha_comercial = date '2026-10-12' and ce.vence_en = date '2027-10-12' from crm.cierres_externos ce where ce.id = v_nuevo)
        and exists (select 1 from crm.inversiones i where i.cierre_externo_id = v_nuevo and i.empresa_id = (select e.id from crm.empresas e where e.clave = 'prodelco'))
        and (select e.rol_actor = 'gerencia' and not e.conversion_anulada from crm.inversiones_eliminadas e where e.fuente_id = k2),
      'V2: la nueva es de Prodelco (empresa de la inversión incluida); la copia registra a Gerencia');
    perform pg_temp.exigir((pg_temp.acr(f2)).id = v_acr_antes.id and (pg_temp.acr(f2)).fuente_id = v_nuevo and (pg_temp.acr(f2)).periodo_comercial = date '2026-10-01'
        and pg_temp.cuenta_conversion('2026-10-01') = v_oct, 'V2: la venta sigue en octubre, misma acreditación, misma conversión');
    set constraints all immediate; set constraints all deferred;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V2 cambio de cooperativa por Gerencia sin portal: misma venta y mes';
end $v2$;

-- V3 · K1 con comprobante NUEVO: la ruta de reemplazo pasa la política de subida (Gerencia y admin sí; vendedor no), el
-- reemplazo la usa y, después, el comprobante se ve con la visibilidad de la ficha.
do $v3$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  a1 constant uuid := 'a0000000-0000-4000-8000-0000000000a1';
  a4 constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  a7 constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
  k1 uuid := pg_temp.sembrado('k1');
  v_ruta text := 'b2000000-0000-4000-8000-000000000001/reemplazo-' || pg_temp.sembrado('k1') || '/nuevo.pdf';
  v_obj uuid; r jsonb; v_nuevo uuid; v_ok boolean;
begin
  begin
    -- La política de SUBIDA: antes de subir nada.
    perform pg_temp.como(a2); select private.f4_comprobante_autorizado(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V3: Gerencia puede subir la ruta de reemplazo');
    perform pg_temp.como('a0000000-0000-4000-8000-0000000000a3'); select private.f4_comprobante_autorizado(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V3: Gerencia sin portal también');
    perform pg_temp.como(a1); select private.f4_comprobante_autorizado(v_ruta) into v_ok; perform pg_temp.exigir(not v_ok, 'V3: el admin del portal sin Gerencia no');
    perform pg_temp.como(a4); select private.f4_comprobante_autorizado(v_ruta) into v_ok; perform pg_temp.exigir(not v_ok, 'V3: un vendedor no');
    perform pg_temp.como(a2);
    select private.f4_comprobante_autorizado('b2000000-0000-4000-8000-000000000002/reemplazo-' || k1 || '/nuevo.pdf') into v_ok;
    perform pg_temp.exigir(not v_ok, 'V3: la carpeta de otra persona no');
    select private.f4_comprobante_autorizado('b2000000-0000-4000-8000-000000000005/reemplazo-' || pg_temp.sembrado('k5') || '/nuevo.pdf') into v_ok;
    perform pg_temp.exigir(not v_ok, 'V3: una inversión anulada no');
    select private.f4_comprobante_autorizado('b2000000-0000-4000-8000-000000000002/reemplazo-' || pg_temp.sembrado('k4') || '/nuevo.pdf') into v_ok;
    perform pg_temp.exigir(not v_ok, 'V3: un aporte adicional no');
    select private.f4_comprobante_autorizado(v_ruta || '.exe') into v_ok; perform pg_temp.exigir(not v_ok, 'V3: otra extensión no');
    perform pg_temp.como(null);
    -- Lo que la pantalla sube; antes de confirmar, nadie lo ve todavía (no respalda ninguna inversión).
    v_obj := pg_temp.objeto(v_ruta, 2048, 'image/png');
    perform pg_temp.como(a2); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(not v_ok, 'V3: antes de confirmar, la ruta no es visible');
    perform pg_temp.como(null);
    r := pg_temp.reemplazar(a2, k1, 'El comprobante era de otra operación', jsonb_build_object('comprobante_ruta', v_ruta));
    v_nuevo := (r ->> 'cierre_id')::uuid;
    perform pg_temp.exigir((r ->> 'comprobante_cambiado')::boolean and (r ->> 'fecha_comercial')::date = date '2026-10-10' and r ->> 'cooperativa' = 'prodelco',
      format('V3: el acuse (%s)', r));
    perform pg_temp.exigir((select ce.comprobante_objeto_id = v_obj from crm.cierres_externos ce where ce.id = v_nuevo)
        and (select (e.snapshot #>> '{reemplazo,cambios,comprobante_cambiado}')::boolean from crm.inversiones_eliminadas e where e.fuente_id = k1),
      'V3: la nueva lleva el comprobante nuevo; la copia lo registra');
    -- La VISIBILIDAD después: Gerencia y el responsable de la relación (a4) sí; otro vendedor (a7) no.
    perform pg_temp.como(a2); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V3: Gerencia ve el comprobante nuevo');
    perform pg_temp.como(a4); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V3: el responsable de la relación lo ve');
    perform pg_temp.como(a7); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(not v_ok, 'V3: otro vendedor no lo ve');
    perform pg_temp.como(null);
    -- Un SEGUNDO reemplazo con OTRO comprobante: el primero queda en la copia de la inversión reemplazada y lo sigue viendo Gerencia.
    perform pg_temp.objeto('b2000000-0000-4000-8000-000000000001/reemplazo-' || v_nuevo || '/otro.pdf');
    r := pg_temp.reemplazar(a2, v_nuevo, 'Otro comprobante más', jsonb_build_object('comprobante_ruta', 'b2000000-0000-4000-8000-000000000001/reemplazo-' || v_nuevo || '/otro.pdf'));
    perform pg_temp.como(a2); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V3: el comprobante de la copia (historia) lo ve Gerencia');
    perform pg_temp.como(a4); select private.f4_comprobante_visible(v_ruta) into v_ok; perform pg_temp.exigir(not v_ok, 'V3: el comprobante de la copia no lo ve el responsable (solo Gerencia)');
    perform pg_temp.como(null);
    set constraints all immediate; set constraints all deferred;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.como(null);
  raise notice 'PASS V3 comprobante nuevo: la política de subida (quién y qué ruta), el reemplazo lo usa, la visibilidad después y la de la copia';
end $v3$;

-- V4 · Cotitulares: la nueva inversión hereda los titulares no principales de la original.
do $v4$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  k2 uuid := pg_temp.sembrado('k2');
  v_inv uuid := (select i.id from crm.inversiones i where i.cierre_externo_id = pg_temp.sembrado('k2'));
  r jsonb; v_nuevo uuid;
begin
  begin
    set local session_replication_role = replica;
    insert into crm.inversionistas (id, estado, perfil_id, responsable_relacion_id, no_contactar, creado_por)
      values ('b2000000-0000-4000-8000-000000000009', 'activo', null, 'a0000000-0000-4000-8000-0000000000a7', false, a2);
    insert into crm.inversion_titulares (inversion_id, inversionista_id, rol, creado_por) values (v_inv, 'b2000000-0000-4000-8000-000000000009', 'cotitular', a2);
    set local session_replication_role = origin;
    r := pg_temp.reemplazar(a2, k2, 'La fecha se registró mal', '{"fecha_comercial": "2026-10-01"}');
    v_nuevo := (r ->> 'cierre_id')::uuid;
    perform pg_temp.exigir((select count(*) from crm.inversion_titulares t join crm.inversiones i on i.id = t.inversion_id where i.cierre_externo_id = v_nuevo) = 2
        and exists (select 1 from crm.inversion_titulares t join crm.inversiones i on i.id = t.inversion_id
                    where i.cierre_externo_id = v_nuevo and t.rol = 'cotitular' and t.inversionista_id = 'b2000000-0000-4000-8000-000000000009'),
      'V4: la nueva inversión tiene al titular principal y al cotitular de la original');
    set constraints all immediate; set constraints all deferred;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS V4 cotitulares heredados';
end $v4$;

-- V5 · Identidad fusionada: la inversión K6 apunta a b6, fusionada en b8 (la canónica, la que ve la ficha). El comprobante nuevo
-- va en la carpeta de b8: la regla del bucket y el núcleo exigen la misma carpeta; la de b6 no vale en ninguna de las dos.
do $v5$
declare
  a2 constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  k6 uuid := pg_temp.sembrado('k6');
  b6 constant uuid := 'b2000000-0000-4000-8000-000000000006';
  b8 constant uuid := 'b2000000-0000-4000-8000-000000000008';
  v_ruta text := 'b2000000-0000-4000-8000-000000000008/reemplazo-' || pg_temp.sembrado('k6') || '/nuevo.pdf';
  v_ruta_vieja text := 'b2000000-0000-4000-8000-000000000006/reemplazo-' || pg_temp.sembrado('k6') || '/nuevo.pdf';
  v_ok boolean; r jsonb;
begin
  begin
    set local session_replication_role = replica;
    insert into crm.inversionistas (id, estado, perfil_id, responsable_relacion_id, no_contactar, creado_por)
      values (b8, 'activo', null, 'a0000000-0000-4000-8000-0000000000a7', false, a2);
    update crm.inversionistas set estado = 'fusionado', inversionista_canonico_id = b8, fusionado_en = now() where id = b6;
    set local session_replication_role = origin;
    perform pg_temp.exigir(private.inversionista_canonica(b6) = b8, 'V5: b6 fusionada en b8');
    perform pg_temp.como(a2);
    select private.f4_comprobante_autorizado(v_ruta) into v_ok; perform pg_temp.exigir(v_ok, 'V5: el bucket admite la carpeta de la canónica');
    select private.f4_comprobante_autorizado(v_ruta_vieja) into v_ok; perform pg_temp.exigir(not v_ok, 'V5: el bucket no admite la carpeta de la fusionada');
    perform pg_temp.como(null);
    perform pg_temp.objeto(v_ruta);
    perform pg_temp.objeto(v_ruta_vieja);
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(a2, k6, 'El comprobante era de otra operación', jsonb_build_object('comprobante_ruta', v_ruta_vieja)), '22023', 'carpeta de esta inversión');
    r := pg_temp.reemplazar(a2, k6, 'El comprobante era de otra operación', jsonb_build_object('comprobante_ruta', v_ruta));
    perform pg_temp.exigir((r ->> 'comprobante_cambiado')::boolean
        and exists (select 1 from crm.inversiones i where i.cierre_externo_id = (r ->> 'cierre_id')::uuid and i.inversionista_id = b8),
      'V5: con la carpeta de la canónica el reemplazo pasa y la inversión nueva es de la canónica');
    set constraints all immediate; set constraints all deferred;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  perform pg_temp.como(null);
  raise notice 'PASS V5 identidad fusionada: la carpeta del comprobante es la de la persona canónica, en el bucket y en el núcleo';
end $v5$;

-- (No hay V6: con la política vigente, todo lead con acreditación tiene su asignación convertida desde septiembre, así que el
-- trigger del alta siempre mueve la venta; un fixture con la asignación en agosto rompe la integridad del ledger («2 episodios
-- de cierre»). La llamada explícita a private.conversion_acreditar_fuente del núcleo es una red idempotente, no una ruta viva.)

-- ── D · Después de todo: nada quedó a medias ────────────────────────────────────────────────────────────────────────────
do $d$
declare c record;
begin
  for c in select n, ('f2000000-0000-4000-8000-00000000000' || n)::uuid as lead, pg_temp.sembrado('k' || n) as k from unnest(array[1, 2, 3, 6]) n loop
    perform pg_temp.exigir(exists (select 1 from crm.cierres_externos ce where ce.id = c.k) and (pg_temp.acr(c.lead)).fuente_id = c.k
        and pg_temp.cierres_validos(c.lead) = 1, format('D K%s: sigue como se sembró', c.n));
  end loop;
  perform pg_temp.exigir(not exists (select 1 from crm.inversiones_eliminadas e where e.fuente_tipo = 'cierre_externo' and e.reemplazada_por is not null),
    'D: ninguna copia «reemplazada por» quedó (todo se deshizo)');
  raise notice 'PASS reemplazar_cooperativa: 12 bloques (S, C, P, R1, R2, R3, V1, V2, V3, V4, V5, D); se revierte';
end $d$;
