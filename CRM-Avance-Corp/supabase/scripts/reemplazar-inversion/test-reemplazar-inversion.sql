-- Pruebas de «Reemplazar inversión» (20261017162053) en el BANCO Docker propio (esquema de producción del 17/10/2026, sin
-- datos de producción). TODO termina en ROLLBACK: la base queda como estaba y la batería se puede repetir.
--   docker exec -i -e PGPASSWORD=<local> reemplazo-inv-db psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -qAt -f - < supabase/scripts/reemplazar-inversion/test-reemplazar-inversion.sql
-- Con la migración SIN aplicar, el bloque 0 (reproducción del defecto) pasa y el resto falla en «no existe la puerta».
-- La siembra de configuración copia producción (leída el 17/10/2026, solo lectura): empresas, banderas multiempresa,
-- política de rentabilidad v18 (observación, base 15, tope técnico 25), producto histórico, política de valoración del
-- capital, pesos y política de conversión, plazo de septiembre al 22/10 00:00 Lima y agosto sellado.
-- Las altas de contrato van por la puerta REAL (crm.crear_contrato_con_cuenta_pdf_v2) y los triggers encendidos; solo la
-- siembra de configuración, personas y leads apaga triggers (session_replication_role = replica).
-- Cada caso corre en un subbloque que se deshace con el centinela P7999 (sus triggers diferidos se disparan antes con
-- SET CONSTRAINTS ALL IMMEDIATE), así los casos no se contaminan entre sí.
\set ON_ERROR_STOP on
begin;
set local lock_timeout = '5s';

create function pg_temp.exigir(ok boolean, mensaje text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FALLA: %', mensaje; end if; end $$;

create function pg_temp.como(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  perform set_config('request.jwt.claims',
    case when p_uid is null then '' else jsonb_build_object('sub', p_uid, 'role', 'authenticated')::text end, true);
end $$;

-- Ejecuta p_sql COMO authenticated con la sesión de p_uid (lo que hace PostgREST) y devuelve el jsonb que produzca.
create function pg_temp.api(p_uid uuid, p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.como(p_uid);
  set local role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end $$;

-- p_sql tiene que fallar con p_estado (y, si se da, con p_mensaje dentro del texto). Lo que hizo se deshace.
create function pg_temp.rechaza(p_sql text, p_estado text, p_mensaje text default null) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    reset role;
    if sqlstate = p_estado and (p_mensaje is null or position(p_mensaje in sqlerrm) > 0) then
      return;
    end if;
    raise exception 'FALLA: se esperaba % «%», llegó % «%» en: %', p_estado, coalesce(p_mensaje, ''), sqlstate, sqlerrm, p_sql;
  end;
  reset role;
  raise exception 'FALLA: debió rechazar con % en: %', p_estado, p_sql;
end $$;

create function pg_temp.cuotas(p_inicio date, p_capital numeric) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('numero_cuota', n, 'fecha_programada', (p_inicio + n * interval '1 month')::date,
    'monto_programado', round(p_capital * 0.0125, 2), 'tipo', 'cuota') order by n)
    || jsonb_build_array(jsonb_build_object('numero_cuota', 13, 'fecha_programada', (p_inicio + interval '12 months')::date,
    'monto_programado', p_capital, 'tipo', 'retorno'))
  from generate_series(1, 12) n $$;

create function pg_temp.contrato(p_cliente uuid, p_numero text, p_capital numeric, p_moneda text, p_tasa numeric, p_inicio date,
  p_analista uuid default 'a0000000-0000-4000-8000-0000000000a4') returns jsonb language sql as $$
  select jsonb_build_object('cliente_id', p_cliente, 'analista_cierre_id', p_analista, 'numero_contrato', p_numero,
    'capital', p_capital, 'moneda', p_moneda, 'categoria', 'nuevo', 'tasa_anual', p_tasa, 'tipo_interes', 'simple',
    'modalidad', 'mensual', 'fecha_inicio', p_inicio, 'fecha_vencimiento', (p_inicio + interval '12 months')::date) $$;

create function pg_temp.cuenta(p_n int, p_moneda text default 'PEN') returns jsonb language sql as $$
  select jsonb_build_object('tipo', 'nueva', 'banco', 'BANCO FICTICIO', 'tipo_cuenta', 'ahorros', 'moneda', p_moneda,
    'numero_cuenta', 'PRUEBA-' || p_n, 'cci', lpad(p_n::text, 20, '9'), 'titular_distinto', false) $$;

-- Alta REAL de un contrato como p_uid (gerencia + admin por defecto). Devuelve su id.
create function pg_temp.alta(p_contrato jsonb, p_cuenta jsonb,
  p_uid uuid default 'a0000000-0000-4000-8000-0000000000a2') returns uuid language plpgsql as $$
begin
  return (pg_temp.api(p_uid, format('select crm.crear_contrato_con_cuenta_pdf_v2(%L::jsonb, %L::jsonb, %L::jsonb)',
    p_contrato, pg_temp.cuotas((p_contrato ->> 'fecha_inicio')::date, (p_contrato ->> 'capital')::numeric), p_cuenta)) ->> 'id')::uuid;
end $$;

-- Enlaza un lead convertido a su contrato como lo hace la conversión (válvula privilegiada): el trigger acredita la venta.
create function pg_temp.enlazar(p_lead uuid, p_contrato uuid) returns void language plpgsql as $$
begin
  perform set_config('crm.op_privilegiada', 'on', true);
  update crm.leads set contrato_id = p_contrato where id = p_lead;
  perform set_config('crm.op_privilegiada', 'off', true);
end $$;

create function pg_temp.reemplazar(p_uid uuid, p_fuente uuid, p_motivo text, p_contrato jsonb, p_cuenta jsonb) returns jsonb
language sql as $$
  select pg_temp.api(p_uid, format('select crm.reemplazar_inversion_fn(%L::uuid, %L, %L::jsonb, %L::jsonb, %L::jsonb)',
    p_fuente, p_motivo, p_contrato, pg_temp.cuotas((p_contrato ->> 'fecha_inicio')::date, (p_contrato ->> 'capital')::numeric), p_cuenta)) $$;

create function pg_temp.sql_reemplazar(p_uid uuid, p_fuente uuid, p_motivo text, p_contrato jsonb, p_cuenta jsonb) returns text
language sql as $$
  select format('select pg_temp.reemplazar(%L::uuid, %L::uuid, %L, %L::jsonb, %L::jsonb)', p_uid, p_fuente, p_motivo, p_contrato, p_cuenta) $$;

create function pg_temp.conservar(p_uid uuid, p_fuente uuid, p_conservar uuid, p_motivo text) returns jsonb language sql as $$
  select pg_temp.api(p_uid, format('select crm.reemplazar_inversion_por_existente_fn(%L::uuid, %L::uuid, %L)',
    p_fuente, p_conservar, p_motivo)) $$;

-- Fotos que deben quedar iguales: la conversión del mes como la ve Gerencia, y el capital del mes por moneda.
create function pg_temp.foto_conversion(p_periodo date) returns jsonb language sql as $$
  select pg_temp.api('a0000000-0000-4000-8000-0000000000a2', format('select crm.conversion_mensual_fn(%L::date)', p_periodo)) $$;

create function pg_temp.foto_capital(p_periodo date) returns jsonb language sql as $$
  select coalesce(jsonb_object_agg(x.moneda, x.monto order by x.moneda), '{}'::jsonb)
  from (select o.moneda, sum(o.monto) as monto
        from private.capital_operaciones_base(p_periodo::timestamptz - interval '400 days', p_periodo::timestamptz + interval '400 days') o
        where o.mes_comercial = p_periodo and not coalesce(o.anulado, false)
        group by o.moneda) x $$;

create function pg_temp.cuenta_conversion(p_periodo date) returns numeric language sql as $$
  select coalesce(sum(c.aporte_numerador), 0)
  from private.conversion_cierres(p_periodo::timestamptz, (p_periodo + interval '1 month')::timestamptz, p_periodo, true, null, 1, null) c
  where c.tipo = 'cierre' and not c.anulado $$;

-- ── Siembra (triggers apagados SOLO aquí) ──────────────────────────────────────────────────────────────────────────────
set local session_replication_role = replica;
insert into crm.empresas (clave, nombre_legal, nombre_visible, fuente_capital, activa, monedas) values
  ('avance', 'AVANCE PRUEBA SAC', 'Avance', 'contratos', true, array['PEN','USD']),
  ('prodelco', 'PRODELCO PRUEBA', 'Prodelco', 'cierres_externos', true, array['PEN','USD']),
  ('qorilazo', 'QORILAZO PRUEBA', 'Qorilazo', 'cierres_externos', true, array['PEN'])
  on conflict (clave) do nothing;
insert into crm.multiempresa_flags (nombre, activo, descripcion) values
  ('ficha_360_neutral', true, 'banco'), ('inversiones_escritura', true, 'banco'),
  ('metricas_multiempresa_sombra', false, 'banco'), ('postventa_neutral', true, 'banco'),
  ('potencial_lead', true, 'banco'), ('resolver_en_puertas', true, 'banco')
  on conflict (nombre) do update set activo = excluded.activo;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select coalesce(max(version), 0) + 1, '2026-09-01', 15, 25, 1, 'observacion' from crm.politica_rentabilidad;
insert into crm.productos_inversion (id, codigo, es_legacy, estado, permite_altas_legacy, revision, archivado_en)
  values ('2bb1e96f-9ddd-426b-917e-7d836fc6476b', 'HISTORICO-SIN-CATALOGO', true, 'archivado', true, 1, now())
  on conflict do nothing;
insert into crm.capital_valoracion_politica (id, vigente_desde, activa, politica, activada_en)
  values (true, '2026-10-01', true, 'sbs_punto_medio_7d_v1', now()) on conflict (id) do nothing;
insert into crm.conversion_pesos (vigente_desde, peso_referido, peso_renovacion, tope_referidos_pct, nota) values
  ('2026-07-01', 0.15, 0.15, null, 'banco'), ('2026-10-01', 1, 0, 15, 'banco') on conflict do nothing;
insert into crm.conversion_politica (unica, vigente_desde, activada_en, manifiesto_huella, resultado)
  values (true, '2026-09-01', '2026-09-27 08:35+00', 'e5d42ab0916447ba4fea622ef280f557', '{"version":1}') on conflict do nothing;

-- Actores. GER admin + gerencia · ADM admin sin CRM · GSO gerencia sin admin del portal · SUP supervisor · VEN y VEN2 vendedores.
insert into auth.users (id) values
  ('a0000000-0000-4000-8000-0000000000a1'), ('a0000000-0000-4000-8000-0000000000a2'), ('a0000000-0000-4000-8000-0000000000a3'),
  ('a0000000-0000-4000-8000-0000000000a6'), ('a0000000-0000-4000-8000-0000000000a4'), ('a0000000-0000-4000-8000-0000000000a7');
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, dni, telefono, correo) values
  ('a0000000-0000-4000-8000-0000000000a1', 'ADMIN PRUEBA', 'admin', true, 'DNI', '40000001', '+51900000001', 'admin@example.invalid'),
  ('a0000000-0000-4000-8000-0000000000a2', 'GERENCIA PRUEBA', 'admin', true, 'DNI', '40000002', '+51900000002', 'gerencia@example.invalid'),
  ('a0000000-0000-4000-8000-0000000000a3', 'GERENCIA SOLA PRUEBA', 'analista', true, 'DNI', '40000003', '+51900000003', 'gerencia-sola@example.invalid'),
  ('a0000000-0000-4000-8000-0000000000a6', 'SUPERVISOR PRUEBA', 'analista', true, 'DNI', '40000006', '+51900000006', 'supervisor@example.invalid'),
  ('a0000000-0000-4000-8000-0000000000a4', 'VENDEDOR PRUEBA', 'analista', true, 'DNI', '40000004', '+51900000004', 'vendedor@example.invalid'),
  ('a0000000-0000-4000-8000-0000000000a7', 'VENDEDOR DOS PRUEBA', 'analista', true, 'DNI', '40000007', '+51900000007', 'vendedor2@example.invalid');
insert into crm.equipo (perfil_id, rol_crm, activo, supervisor_id) values
  ('a0000000-0000-4000-8000-0000000000a2', 'gerencia', true, null),
  ('a0000000-0000-4000-8000-0000000000a3', 'gerencia', true, null),
  ('a0000000-0000-4000-8000-0000000000a6', 'supervisor', true, null),
  ('a0000000-0000-4000-8000-0000000000a4', 'vendedor', true, 'a0000000-0000-4000-8000-0000000000a6'),
  ('a0000000-0000-4000-8000-0000000000a7', 'vendedor', true, 'a0000000-0000-4000-8000-0000000000a6');

-- Clientes (c1..c6) del vendedor VEN.
insert into auth.users (id) select ('c1000000-0000-4000-8000-00000000000' || n)::uuid from generate_series(1, 6) n;
insert into public.perfiles (id, nombre_completo, rol, activo, tipo_documento, dni, asesor_perfil_id, domicilio, correo)
  select ('c1000000-0000-4000-8000-00000000000' || n)::uuid, 'CLIENTE ' || n || ' PRUEBA', 'cliente', true, 'DNI', '4100000' || n,
    'a0000000-0000-4000-8000-0000000000a4', 'Calle Prueba ' || n, 'cliente' || n || '@example.invalid'
  from generate_series(1, 6) n;

-- Leads convertidos (d1..d5): la venta es de VEN en octubre (d1..d4) y en septiembre (d5).
insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, vendedor_id, perfil_id, activo, monto_estimado)
  select ('d1000000-0000-4000-8000-00000000000' || n)::uuid, 'LEAD ' || n || ' PRUEBA', '+5199900000' || n, '4100000' || n, 'landing',
    'convertido', case when n = 5 then timestamptz '2026-09-20 15:00-05' else timestamptz '2026-10-05 15:00-05' end,
    'a0000000-0000-4000-8000-0000000000a4', ('c1000000-0000-4000-8000-00000000000' || n)::uuid, true, 1000
  from generate_series(1, 5) n;
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  select l.id, 1, 1, 'a0000000-0000-4000-8000-0000000000a4', 'asignado', l.convertido_en - interval '5 days', 'PEN', 'landing',
    l.convertido_en - interval '5 days', gen_random_uuid(), l.convertido_en, l.convertido_en, 'convertido', l.convertido_en,
    l.convertido_en, 'a0000000-0000-4000-8000-0000000000a4', 'convertido'
  from crm.leads l where l.id::text like 'd1000000%';
set local session_replication_role = origin;

-- Ventas por la puerta real (octubre: k1..k4; septiembre: k5) y su enlace al lead (acredita la venta).
do $siembra$
declare v uuid;
begin
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910001', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(1));
  perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000001', v);
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910002', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(2));
  perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000002', v);
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910003', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(3));
  perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000003', v);
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910004', 4000, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(4));
  perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000004', v);
end $siembra$;
set constraints all immediate;
set constraints all deferred;

-- Septiembre: la venta de d5 se registró el 20/09 (se envejecen contrato y acreditación, como si hubiera ocurrido ese día)
-- y Gerencia amplió el plazo de septiembre al 21/10 (como en producción: plazo_hasta 22/10 00:00 Lima).
do $septiembre$
declare v uuid;
begin
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910005', 1500, 'PEN', 15, date '2026-09-20'), pg_temp.cuenta(5));
  set local session_replication_role = replica;
  insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por, decidido_en)
    values ('2026-09-01', '2026-10-21', timestamptz '2026-10-22 00:00-05', 'banco: como producción', 'a0000000-0000-4000-8000-0000000000a2', now() - interval '3 days');
  update public.contratos set creado_en = timestamptz '2026-09-20 12:00-05' where id = v;
  set local session_replication_role = origin;
  perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000005', v);
  set local session_replication_role = replica;
  update crm.conversion_acreditaciones set confirmado_en = timestamptz '2026-09-20 12:00-05', vinculado_en = timestamptz '2026-09-20 12:05-05',
    acreditado_en = timestamptz '2026-09-20 12:05-05' where lead_id = 'd1000000-0000-4000-8000-000000000005';
  set local session_replication_role = origin;
end $septiembre$;
set constraints all immediate;
set constraints all deferred;

-- Una inversión sin venta de lead (cliente 6) y un original «antiguo» con tasa 28 que hoy pasa el tope técnico (25): se crea
-- con una política anterior más permisiva y luego se publica la de hoy.
do $otras$
declare v uuid;
begin
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910006', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(6));
  insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
    select max(version) + 1, clock_timestamp(), 15, 30, 1, 'observacion' from crm.politica_rentabilidad;
  v := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910007', 2500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(7));
end $otras$;
set constraints all immediate;
set constraints all deferred;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'observacion' from crm.politica_rentabilidad;

do $verificar_siembra$
begin
  perform pg_temp.exigir((select count(*) = 5 from crm.conversion_acreditaciones ca where ca.lead_id::text like 'd1000000%' and ca.estado = 'acreditada'),
    'siembra: 5 ventas acreditadas (4 de octubre, 1 de septiembre)');
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4 and pg_temp.cuenta_conversion('2026-09-01') = 1, 'siembra: conversión 4 + 1');
  raise notice 'siembra OK: octubre % · septiembre % · capital octubre %', pg_temp.cuenta_conversion('2026-10-01'),
    pg_temp.cuenta_conversion('2026-09-01'), pg_temp.foto_capital('2026-10-01');
end $verificar_siembra$;

-- Helpers que dependen de la siembra.
create function pg_temp.k(p_numero text) returns uuid language sql stable as $$
  select c.id from public.contratos c where c.numero_contrato = p_numero $$;
create function pg_temp.deshacer() returns void language plpgsql as $$
begin raise exception using errcode = 'P7999', message = 'deshacer el caso'; end $$;
create function pg_temp.acr(p_lead uuid) returns crm.conversion_acreditaciones language sql stable as $$
  select * from crm.conversion_acreditaciones ca where ca.lead_id = p_lead $$;

-- ── 0 · Reproducción del defecto: «Eliminar inversión» + volver a cargar = venta perdida para siempre ───────────────────
do $c0$
declare v_nuevo uuid; r jsonb;
begin
  begin
    r := pg_temp.api('a0000000-0000-4000-8000-0000000000a2',
      format('select crm.eliminar_inversion_fn(%L::uuid, %L)', pg_temp.k('2026-01-910001'), 'Error de carga: número equivocado'));
    perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean, 'C0: eliminar anula la venta');
    v_nuevo := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910101', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(101));
    perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000001', v_nuevo);
    set constraints all immediate;
    perform pg_temp.exigir(private.cierre_anulado('d1000000-0000-4000-8000-000000000001'), 'C0: la anulación es por lead y no se deshace');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 3, 'C0: la venta recargada NO vuelve a contar (4 → 3)');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 0 reproducción: eliminar + recargar deja octubre en 3 (la venta se pierde)';
end $c0$;
set constraints all deferred;

-- ── 1 · Reemplazo «nueva», mismo mes y mismo capital: la conversión y el capital quedan iguales ────────────────────────
do $c1$
declare
  v_k uuid := pg_temp.k('2026-01-910001'); v_lead uuid := 'd1000000-0000-4000-8000-000000000001';
  v_conv jsonb; v_cap jsonb; v_acr crm.conversion_acreditaciones; v_acr2 crm.conversion_acreditaciones;
  v_orig public.contratos; v_nuevo public.contratos; r jsonb; v_copia crm.inversiones_eliminadas;
begin
  begin
    v_conv := pg_temp.foto_conversion('2026-10-01'); v_cap := pg_temp.foto_capital('2026-10-01');
    v_acr := pg_temp.acr(v_lead); select * into v_orig from public.contratos where id = v_k;
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga: número de contrato equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910101', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(11));
    set constraints all immediate;
    perform pg_temp.exigir((r ->> 'ok')::boolean and r ->> 'modo' = 'nueva' and r #>> '{conversion,estado}' = 'acreditada', 'C1: respuesta');
    select * into v_nuevo from public.contratos where id = (r ->> 'contrato_id')::uuid;
    perform pg_temp.exigir(not exists (select 1 from public.contratos where id = v_k), 'C1: el original ya no existe');
    perform pg_temp.exigir(v_nuevo.cliente_id = v_orig.cliente_id and v_nuevo.analista_cierre_id = v_orig.analista_cierre_id
      and v_nuevo.categoria = 'nuevo' and v_nuevo.numero_contrato = '2026-01-910101', 'C1: mismo cliente, mismo analista, categoría nuevo');
    perform pg_temp.exigir(v_nuevo.fecha_cierre_comercial = v_orig.fecha_cierre_comercial
      and v_nuevo.fuente_cierre_comercial = v_orig.fuente_cierre_comercial, 'C1: misma fecha de cierre comercial');
    perform pg_temp.exigir((select contrato_id from crm.leads where id = v_lead) = v_nuevo.id, 'C1: el lead quedó enlazado al nuevo');
    v_acr2 := pg_temp.acr(v_lead);
    perform pg_temp.exigir(v_acr2.id = v_acr.id and v_acr2.fuente_id = v_nuevo.id and v_acr2.estado = 'acreditada'
      and v_acr2.episodio_id = v_acr.episodio_id and v_acr2.analista_id = v_acr.analista_id
      and v_acr2.periodo_comercial = v_acr.periodo_comercial, 'C1: la misma acreditación pasa al nuevo');
    perform pg_temp.exigir(not private.cierre_anulado(v_lead) and not exists (select 1 from crm.cierres_avance_anulados where lead_id = v_lead),
      'C1: la venta NO se anuló');
    select * into v_copia from crm.inversiones_eliminadas where fuente_id = v_k;
    perform pg_temp.exigir(v_copia.es_conversion and not v_copia.conversion_anulada and v_copia.reemplazada_por = v_nuevo.id
      and v_copia.lead_id = v_lead and v_copia.rol_actor = 'gerencia' and v_copia.anulacion is null
      and v_copia.snapshot #>> '{reemplazo,modo}' = 'nueva' and v_copia.snapshot #>> '{reemplazo,numero_contrato}' = '2026-01-910101'
      and v_copia.snapshot #>> '{reemplazo,acreditacion_antes,id}' = v_acr.id::text, 'C1: la copia guardada');
    perform pg_temp.exigir(exists (select 1 from crm.contratos_eliminados_auditoria a where a.contrato_id = v_k), 'C1: la auditoría del borrado');
    perform pg_temp.exigir(exists (select 1 from private.contrato_pdf_jobs j where j.contrato_id = v_nuevo.id), 'C1: el PDF del nuevo, reservado');
    perform pg_temp.exigir(pg_temp.foto_conversion('2026-10-01') = v_conv, 'C1: conversión de octubre (todo el JSON) igual');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4, 'C1: octubre sigue en 4');
    perform pg_temp.exigir(pg_temp.foto_capital('2026-10-01') = v_cap, 'C1: capital de octubre igual');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 1 reemplazo: mismo mes y capital → conversión (JSON entero) y capital iguales, copia con reemplazada_por, venta sin anular';
end $c1$;
set constraints all deferred;

-- ── 2 · Mismo número, otro capital y otra moneda: la conversión igual; el capital cambia exactamente lo corregido ────────
do $c2$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_cap jsonb; r jsonb;
begin
  begin
    v_cap := pg_temp.foto_capital('2026-10-01');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Moneda equivocada: era en dólares',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910001', 6000, 'USD', 15, date '2026-10-05'), pg_temp.cuenta(12, 'USD'));
    set constraints all immediate;
    perform pg_temp.exigir((select numero_contrato from public.contratos where id = (r ->> 'contrato_id')::uuid) = '2026-01-910001',
      'C2: el número del original se reutiliza');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4, 'C2: octubre sigue en 4');
    perform pg_temp.exigir((pg_temp.foto_capital('2026-10-01') ->> 'PEN')::numeric = (v_cap ->> 'PEN')::numeric - 5000
      and (pg_temp.foto_capital('2026-10-01') ->> 'USD')::numeric = 6000, 'C2: capital PEN -5000 y USD +6000');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 2 mismo número, capital y moneda corregidos: conversión igual, capital movido exactamente';
end $c2$;
set constraints all deferred;

-- ── 3 · La fecha cae en septiembre (abierto): la venta se muda de octubre a septiembre; el total no cambia ────────────────
do $c3$
declare v_k uuid := pg_temp.k('2026-01-910002'); r jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'La inversión empezó en septiembre',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910202', 2000, 'PEN', 18, date '2026-09-28'), pg_temp.cuenta(13));
    set constraints all immediate;
    perform pg_temp.exigir(r #>> '{conversion,periodo_antes}' = '2026-10-01' and r #>> '{conversion,periodo_despues}' = '2026-09-01'
      and r #>> '{conversion,estado}' = 'acreditada', 'C3: la venta se mudó a septiembre');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 3 and pg_temp.cuenta_conversion('2026-09-01') = 2,
      'C3: octubre 4 → 3, septiembre 1 → 2');
    perform pg_temp.exigir((pg_temp.foto_capital('2026-09-01') ->> 'PEN')::numeric = 3500, 'C3: el capital también se mudó');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 3 fecha en otro mes abierto: la venta se muda y el total se conserva';
end $c3$;
set constraints all deferred;

-- ── 4 · Original registrado ANTES de su fecha de inicio: el reemplazo conserva su mes (no lo mueve la fecha de hoy) ──────
do $c4$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_lead uuid := 'd1000000-0000-4000-8000-000000000005'; r jsonb; v_cc date;
begin
  begin
    -- d5: registrado el 20/09; se corrige la fecha de inicio al 01/10 → la venta sigue siendo del 20/09 (septiembre).
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Fecha de inicio equivocada',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910505', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(14));
    set constraints all immediate;
    select fecha_cierre_comercial into v_cc from public.contratos where id = (r ->> 'contrato_id')::uuid;
    perform pg_temp.exigir(v_cc = date '2026-09-20', 'C4: la fecha comercial es la del registro original (20/09), no la de hoy');
    perform pg_temp.exigir((pg_temp.acr(v_lead)).periodo_comercial = '2026-09-01' and (pg_temp.acr(v_lead)).estado = 'acreditada'
      and pg_temp.cuenta_conversion('2026-09-01') = 1, 'C4: la venta sigue en septiembre y cuenta');
    perform pg_temp.exigir((select (snapshot #>> '{reemplazo,acreditacion_antes,acreditado_en}')::timestamptz
      from crm.inversiones_eliminadas where fuente_id = v_k) = timestamptz '2026-09-20 12:05-05', 'C4: la copia guarda el reloj anterior');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 4 original registrado antes de su inicio: el reemplazo conserva el mes de la venta';
end $c4$;
set constraints all deferred;

-- ── 5 · Plazo de carga vencido: no se hace NADA (rechazo antes de borrar) ──────────────────────────────────────────────
do $c5$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_lead uuid := 'd1000000-0000-4000-8000-000000000005'; v_acr crm.conversion_acreditaciones;
begin
  begin
    v_acr := pg_temp.acr(v_lead);
    set local session_replication_role = replica;
    insert into crm.plazos_carga_mes (periodo, ultimo_dia, plazo_hasta, motivo, decidido_por, decidido_en)
      -- Gerencia vuelve al plazo base (día 10): el de septiembre venció el 11/10 00:00 Lima.
      values ('2026-09-01', '2026-10-10', timestamptz '2026-10-11 00:00-05', 'banco: plazo vencido', 'a0000000-0000-4000-8000-0000000000a2', now());
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910555', 1500, 'PEN', 15, date '2026-09-20'), pg_temp.cuenta(15)),
      'P0409', 'Venció el plazo de carga de 09/2026');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k)
      and not exists (select 1 from crm.inversiones_eliminadas where fuente_id = v_k)
      and pg_temp.acr(v_lead) = v_acr, 'C5: el original, la copia y la acreditación quedan intactos');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 5 plazo vencido: rechazo con mensaje claro y sin ningún cambio';
end $c5$;
set constraints all deferred;

-- ── 6 · Todo o nada: si el alta falla después de borrar, no queda nada hecho ──────────────────────────────────────────
do $c6$
declare v_k uuid := pg_temp.k('2026-01-910003'); v_lead uuid := 'd1000000-0000-4000-8000-000000000003'; v_acr crm.conversion_acreditaciones;
begin
  v_acr := pg_temp.acr(v_lead);
  -- Cronograma vacío: el alta de siempre lo rechaza DESPUÉS del borrado.
  perform pg_temp.rechaza(format('select pg_temp.api(%L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2',
    format('select crm.reemplazar_inversion_fn(%L::uuid, %L, %L::jsonb, %L::jsonb, %L::jsonb)', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910303', 3000, 'PEN', 15, date '2026-10-07'), '[]', pg_temp.cuenta(16))),
    'P0001', 'cronograma');
  perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k)
    and (select contrato_id from crm.leads where id = v_lead) = v_k
    and not exists (select 1 from crm.inversiones_eliminadas where fuente_id = v_k)
    and not exists (select 1 from crm.contratos_eliminados_auditoria where contrato_id = v_k)
    and pg_temp.acr(v_lead) = v_acr and not private.cierre_anulado(v_lead), 'C6: nada cambió');
  raise notice 'PASS 6 todo o nada: el alta falla tras el borrado y no queda ningún cambio';
end $c6$;

-- ── 7 · Rechazos ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $c7$
declare
  v_k3 uuid := pg_temp.k('2026-01-910003'); v_k4 uuid := pg_temp.k('2026-01-910004');
  c3 jsonb := pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910333', 3000, 'PEN', 15, date '2026-10-07');
  c4 jsonb := pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910444', 4000, 'PEN', 15, date '2026-10-08');
  ger uuid := 'a0000000-0000-4000-8000-0000000000a2';
begin
  -- Roles.
  perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a4', v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)),
    '42501', 'Solo admin o gerencia');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)),
    '42501', 'solo gerencia puede reemplazarla');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a3', v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)),
    '42501', 'la reemplaza un admin del portal');
  perform pg_temp.rechaza(format('select pg_temp.reemplazar(null, %L::uuid, %L, %L::jsonb, %L::jsonb)', v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)),
    '42501', 'Inicia sesión');
  -- Datos.
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Ab', c3, pg_temp.cuenta(21)), '22023', 'motivo');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba',
    c3 || '{"cliente_id":"c1000000-0000-4000-8000-000000000004"}', pg_temp.cuenta(21)), '22023', 'mismo cliente');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba',
    c3 || '{"analista_cierre_id":"a0000000-0000-4000-8000-0000000000a7"}', pg_temp.cuenta(21)), '22023', 'analista de la venta no cambia');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba',
    c3 || '{"categoria":"upgrade"}', pg_temp.cuenta(21)), '22023', 'categoría Nuevo');
  perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, gen_random_uuid(), 'Error de carga de prueba', c3, pg_temp.cuenta(21)), 'P0002', 'no existe');
  -- Anon no ejecuta la puerta; authenticated no ejecuta el núcleo.
  perform pg_temp.exigir(not has_function_privilege('anon', 'crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'crm.reemplazar_inversion_por_existente_fn(uuid,uuid,text)', 'execute')
    and has_function_privilege('authenticated', 'crm.reemplazar_inversion_fn(uuid,text,jsonb,jsonb,jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'private.reemplazar_inversion_avance(uuid,jsonb,uuid,text,jsonb,jsonb,jsonb,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'private.registrar_inversion_reemplazada_avance(jsonb,uuid,uuid,text,text,uuid,text,jsonb)', 'execute'),
    'C7: permisos de puertas y núcleo');

  -- Mes sellado (conversión) y capital sellado: rechazo ANTES de borrar.
  begin
    set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-10-01', now(), ger, false, 1, 0, '{}');
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)), 'P0409', 'ya está cerrado');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k3), 'C7: con el mes sellado el original sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  -- Un mes POR DETRÁS del último sello (noviembre sellado, octubre no) también queda congelado.
  begin
    set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-11-01', now(), ger, false, 1, 0, '{}');
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)), 'P0409', 'ya está cerrado');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;

  -- Historia propia: el contrato quedó registrado como un upgrade (operación de cartera).
  begin
    set local session_replication_role = replica;
    insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id, fecha_operacion, periodo,
        moneda, elegible_conversion, desglose_completo, fuente, creado_por)
      values ('c1000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-0000000000a4', 'upgrade', null, v_k3,
        '2026-10-07', '2026-10-01', 'PEN', true, true, 'flujo_cartera', ger);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k3, 'Error de carga de prueba', c3, pg_temp.cuenta(21)), 'P0409', 'upgrade');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;

  -- Dos leads convertidos apuntan al contrato.
  begin
    set local session_replication_role = replica;
    insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, perfil_id, contrato_id, activo, monto_estimado)
      values ('d1000000-0000-4000-8000-000000000009', 'LEAD DUPLICADO PRUEBA', '+51999000009', 'landing', 'convertido', now(),
        'a0000000-0000-4000-8000-0000000000a4', 'c1000000-0000-4000-8000-000000000004', v_k4, true, 1000);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k4, 'Error de carga de prueba', c4, pg_temp.cuenta(22)), 'P0409', 'Varios leads convertidos');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;

  -- La venta ya está anulada (la anula Gerencia antes).
  begin
    perform pg_temp.api(ger, format('select crm.anular_cierre_avance(%L::uuid, %L)', 'd1000000-0000-4000-8000-000000000004', 'Venta anulada de prueba'));
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k4, 'Error de carga de prueba', c4, pg_temp.cuenta(22)), 'P0409', 'ya fue anulada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;

  -- Venta de prueba.
  begin
    set local session_replication_role = replica;
    update public.contratos set es_demo = true where id = v_k4;
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k4, 'Error de carga de prueba', c4, pg_temp.cuenta(22)), 'P0409', 'venta de prueba');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;

  -- La venta del lead está acreditada a OTRA inversión del cliente (el enlace del lead y la acreditación no coinciden).
  begin
    declare v_otro uuid;
    begin
      v_otro := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910445', 900, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(23));
      set local session_replication_role = replica;
      update crm.conversion_acreditaciones set fuente_id = v_otro where lead_id = 'd1000000-0000-4000-8000-000000000004';
      set local session_replication_role = origin;
      perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k4, 'Error de carga de prueba', c4, pg_temp.cuenta(22)), 'P0409', 'acreditada a otra inversión');
    end;
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 7 rechazos: analista, admin sin gerencia en una venta, gerencia sin admin, sin sesión, motivo, otro cliente, otro analista, categoría, inexistente, permisos, mes sellado, mes detrás del sello, upgrade, dos convertidos, venta anulada, venta de prueba, venta acreditada a otra inversión';
end $c7$;
set constraints all deferred;

-- ── 8 · «Quedarme con la otra»: la inversión que tiene la venta se cargó dos veces ─────────────────────────────────────
do $c8$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_dup uuid; v_lead uuid := 'd1000000-0000-4000-8000-000000000001';
  v_cap jsonb; r jsonb; v_acr crm.conversion_acreditaciones;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910111', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(31));
    set constraints all immediate;
    v_cap := pg_temp.foto_capital('2026-10-01'); v_acr := pg_temp.acr(v_lead);
    -- Rechazos propios del modo.
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2', v_k, v_k, 'Cargada dos veces'),
      '22023', 'Elige otra inversión');
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2', v_k, pg_temp.k('2026-01-910002'), 'Cargada dos veces'),
      '22023', 'mismo cliente');
    r := pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces por error');
    set constraints all immediate;
    perform pg_temp.exigir(r ->> 'modo' = 'existente' and (r ->> 'contrato_id')::uuid = v_dup, 'C8: respuesta');
    perform pg_temp.exigir(not exists (select 1 from public.contratos where id = v_k)
      and (select contrato_id from crm.leads where id = v_lead) = v_dup
      and (pg_temp.acr(v_lead)).fuente_id = v_dup and (pg_temp.acr(v_lead)).estado = 'acreditada'
      and (pg_temp.acr(v_lead)).episodio_id = v_acr.episodio_id, 'C8: la venta pasó a la otra inversión');
    perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4, 'C8: octubre sigue en 4');
    perform pg_temp.exigir((pg_temp.foto_capital('2026-10-01') ->> 'PEN')::numeric = (v_cap ->> 'PEN')::numeric - 5000,
      'C8: el capital duplicado sale');
    perform pg_temp.exigir((select reemplazada_por = v_dup and snapshot #>> '{reemplazo,modo}' = 'existente'
      from crm.inversiones_eliminadas where fuente_id = v_k), 'C8: la copia');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 8 quedarme con la otra: la venta pasa a la inversión conservada; conversión igual; sale el capital duplicado';
end $c8$;
set constraints all deferred;

-- ── 9 · Idempotencia ─────────────────────────────────────────────────────────────────────────────────────────────────
do $c9$
declare v_k uuid := pg_temp.k('2026-01-910002'); r jsonb; r2 jsonb; c jsonb;
begin
  begin
    c := pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910222', 2000, 'PEN', 18, date '2026-10-06');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(41));
    r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(41));
    perform pg_temp.exigir((r2 ->> 'idempotente')::boolean and r2 ->> 'contrato_id' = r ->> 'contrato_id'
      and (select count(*) from public.contratos where cliente_id = 'c1000000-0000-4000-8000-000000000002') = 1, 'C9: el reintento no crea otro');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 9 idempotente: el reintento devuelve el mismo contrato';
end $c9$;
set constraints all deferred;

-- ── 10 · La tasa aprobada se hereda (observación con tope 25 y enforcement con base 15) ───────────────────────────────
do $c10$
declare v_k7 uuid := pg_temp.k('2026-01-910007'); v_k2 uuid := pg_temp.k('2026-01-910002'); r jsonb;
  ger uuid := 'a0000000-0000-4000-8000-0000000000a2';
begin
  -- Observación (tope 25): el original tiene 28. Un alta nueva con 28 se rechaza; el reemplazo que conserva 28, no.
  begin
    perform pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910777', 2500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(51));
    set constraints all immediate;
    raise exception 'FALLA: C10 un alta nueva con 28 pasó el tope 25';
  exception when sqlstate 'P0410' then null;
  end;
  set constraints all deferred;
  begin
    r := pg_temp.reemplazar(ger, v_k7, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910778', 2500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(52));
    set constraints all immediate;
    perform pg_temp.exigir((select (l.detalle ->> 'reemplazo_tasa_heredada')::boolean from crm.ledger_rentabilidad l
      where l.contrato_id = (r ->> 'contrato_id')::uuid), 'C10: el libro de rentabilidad anota la tasa heredada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  set constraints all deferred;
  -- Con otra tasa (29) ya no es herencia: rige el tope.
  begin
    r := pg_temp.reemplazar(ger, v_k7, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910779', 2500, 'PEN', 29, date '2026-10-10'), pg_temp.cuenta(53));
    set constraints all immediate;
    raise exception 'FALLA: C10 una tasa distinta a la heredada pasó el tope';
  exception when sqlstate 'P0410' then null;
  end;
  set constraints all deferred;
  raise notice 'PASS 10a tasa en observación: se hereda la del original por encima del tope; otra tasa sigue el tope';
end $c10$;
set constraints all deferred;

-- Enforcement (base 15). La política se publica en su PROPIA sentencia: el candado mira la vigente a la hora de inicio de la
-- sentencia (statement_timestamp), y dentro del mismo DO todavía no lo estaría. Se deshace con el savepoint.
savepoint c10b;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c10b$
declare v_k2 uuid := pg_temp.k('2026-01-910002'); r jsonb; ger uuid := 'a0000000-0000-4000-8000-0000000000a2';
begin
  perform pg_temp.exigir((private.politica_rentabilidad_vigente(statement_timestamp())).modo = 'enforcement', 'C10b: enforcement vigente');
  -- Control: un alta NUEVA a 18 sin autorización se rechaza.
  begin
    perform pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910287', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(56));
    set constraints all immediate;
    raise exception 'FALLA: C10b un alta nueva a 18 pasó sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  set constraints all deferred;
  -- El original de d2 tiene 18: el reemplazo que lo conserva pasa, sin autorización nueva y con el origen anotado.
  begin
    r := pg_temp.reemplazar(ger, v_k2, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910288', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(54));
    set constraints all immediate;
    perform pg_temp.exigir((select l.origen = 'enforcement' and l.tasa_final = 18 and l.solicitud_id is null
        and (l.detalle ->> 'reemplazo_tasa_heredada')::boolean and (l.detalle ->> 'tasa_en_juego')::boolean
        and l.detalle #>> '{reemplazo_de,contrato_id}' = v_k2::text
      from crm.ledger_rentabilidad l where l.contrato_id = (r ->> 'contrato_id')::uuid), 'C10b: enforcement hereda 18 y lo anota');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  set constraints all deferred;
  -- Con 19 ya no es herencia: hace falta autorización.
  begin
    r := pg_temp.reemplazar(ger, v_k2, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910289', 2000, 'PEN', 19, date '2026-10-06'), pg_temp.cuenta(55));
    set constraints all immediate;
    raise exception 'FALLA: C10b enforcement aceptó 19 sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  set constraints all deferred;
  raise notice 'PASS 10b tasa en enforcement: se hereda la del original sin autorización nueva (anotada en el libro); otra tasa la exige';
end $c10b$;
rollback to savepoint c10b;
set constraints all deferred;

-- ── 11 · Inversión sin venta de lead: la reemplaza un admin del portal sin Gerencia ────────────────────────────────────
do $c11$
declare v_k uuid := pg_temp.k('2026-01-910006'); r jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga: capital equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910666', 7500, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(61));
    set constraints all immediate;
    perform pg_temp.exigir(r -> 'conversion' = 'null'::jsonb or r -> 'conversion' is null, 'C11: sin venta que mover');
    perform pg_temp.exigir((select not es_conversion and rol_actor = 'admin' and reemplazada_por = (r ->> 'contrato_id')::uuid
      from crm.inversiones_eliminadas where fuente_id = v_k), 'C11: la copia (sin venta, rol admin)');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 11 sin venta de lead: admin sin gerencia reemplaza; copia sin conversión';
end $c11$;
set constraints all deferred;

-- ── 12 · La marca de primera conversión pasa al contrato que queda ─────────────────────────────────────────────────────
do $c12$
declare v_k uuid := pg_temp.k('2026-01-910001'); r jsonb;
begin
  begin
    set local session_replication_role = replica;
    update crm.inversiones set es_primera_conversion = true where contrato_id = v_k;   -- como la deja la conversión
    set local session_replication_role = origin;
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910121', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(71));
    set constraints all immediate;
    perform pg_temp.exigir((select es_primera_conversion from crm.inversiones where contrato_id = (r ->> 'contrato_id')::uuid),
      'C12: el contrato que queda es la primera conversión');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 12 primera conversión: la marca pasa al contrato que queda';
end $c12$;
set constraints all deferred;

-- ── 13 · Más rechazos ANTES de borrar: analista dado de baja y venta anterior a septiembre con su mes sellado ─────────
do $c13$
declare v_k uuid; ger uuid := 'a0000000-0000-4000-8000-0000000000a2';
begin
  -- El analista de la venta ya no está en el equipo.
  begin
    set local session_replication_role = replica;
    update crm.equipo set activo = false where perfil_id = 'a0000000-0000-4000-8000-0000000000a4';
    set local session_replication_role = origin;
    v_k := pg_temp.k('2026-01-910003');
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910313', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(81)),
      'P0409', 'ya no está activo');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k), 'C13: el original sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  -- Venta de AGOSTO (régimen anterior: sin acreditación; su mes sale del episodio) con agosto sellado, aunque su contrato
  -- se registró en octubre: la detecta private.mes_sellado_de_venta.
  begin
    set local session_replication_role = replica;
    insert into crm.periodos_cerrados (periodo, cerrado_en, cerrado_por, automatico, ponderacion_referido, meta_revision, cobertura)
      values ('2026-08-01', '2026-09-11 00:05-05', ger, false, 0.15, 0, '{}');
    insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, vendedor_id, perfil_id, activo, monto_estimado)
      values ('d1000000-0000-4000-8000-000000000008', 'LEAD AGOSTO PRUEBA', '+51999000008', '41000006', 'landing', 'convertido',
        '2026-08-20 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', 'c1000000-0000-4000-8000-000000000006', true, 1000);
    insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
        sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
        finalizado_en, finalizado_por, motivo_cierre)
      values ('d1000000-0000-4000-8000-000000000008', 1, 1, 'a0000000-0000-4000-8000-0000000000a4', 'asignado', '2026-08-15 15:00-05', 'PEN',
        'landing', '2026-08-15 15:00-05', gen_random_uuid(), '2026-08-20 15:00-05', '2026-08-20 15:00-05', 'convertido', '2026-08-20 15:00-05',
        '2026-08-20 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', 'convertido');
    set local session_replication_role = origin;
    v_k := pg_temp.k('2026-01-910006');
    perform pg_temp.enlazar('d1000000-0000-4000-8000-000000000008', v_k);
    perform pg_temp.rechaza(pg_temp.sql_reemplazar(ger, v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910616', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(82)),
      'P0409', 'ya está cerrado');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k), 'C13: el original de agosto sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 13 rechazos antes de borrar: analista dado de baja y venta de agosto con su mes sellado';
end $c13$;
set constraints all deferred;

-- ── 14 · La red final: si el escritor de acreditaciones dejara la venta en otro estado, el reemplazo aborta TODO ────────
-- Se simula un cambio de regla del plazo (private.conversion_decidir_plazo devuelve «fuera_de_plazo») que la comprobación
-- previa no ve (esa mira private.conversion_plazo_hasta). La función real vuelve con el savepoint.
savepoint c14;
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
do $c14$
declare v_k uuid := pg_temp.k('2026-01-910003'); v_lead uuid := 'd1000000-0000-4000-8000-000000000003'; v_acr crm.conversion_acreditaciones;
begin
  v_acr := pg_temp.acr(v_lead);
  perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
    pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910314', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(91)),
    'P0409', 'ya cerró: el reemplazo no puede conservar la venta');
  perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k) and pg_temp.acr(v_lead) = v_acr
    and not exists (select 1 from crm.inversiones_eliminadas where fuente_id = v_k), 'C14: nada cambió');
  raise notice 'PASS 14 red final: si la conversión no queda igual, el reemplazo aborta sin dejar nada';
end $c14$;
rollback to savepoint c14;

-- ── 15 · Cadena de reemplazos (Codex r1, P1): el segundo reemplazo no mueve el mes de la venta ─────────────────────────
do $c15$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_lead uuid := 'd1000000-0000-4000-8000-000000000005'; r jsonb; r2 jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Fecha de inicio equivocada',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910515', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(101));
    r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, 'Número de contrato equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910516', 1500, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(102));
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = (r2 ->> 'contrato_id')::uuid) = date '2026-09-20'
      and (pg_temp.acr(v_lead)).periodo_comercial = '2026-09-01' and pg_temp.cuenta_conversion('2026-09-01') = 1
      and pg_temp.cuenta_conversion('2026-10-01') = 4, 'C15: la venta sigue el 20/09 tras dos reemplazos');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 15 cadena: el segundo reemplazo hereda el día de registro de la venta';
end $c15$;
set constraints all deferred;

-- ── 16 · «Quedarme con la otra» de OTRO analista se rechaza (Codex r1, P1) ─────────────────────────────────────────────
do $c16$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_dup uuid;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910161', 5000, 'PEN', 15, date '2026-10-05',
      'a0000000-0000-4000-8000-0000000000a7'), pg_temp.cuenta(103));
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2',
      v_k, v_dup, 'Cargada dos veces'), '22023', 'es de otro analista');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 16 quedarme con la otra: otro analista se rechaza';
end $c16$;
set constraints all deferred;

-- ── 17 · Venta sin acreditación previa: el reemplazo no la crea (Codex r1, P1) ─────────────────────────────────────────
do $c17$
declare v_k uuid := pg_temp.k('2026-01-910003'); v_lead uuid := 'd1000000-0000-4000-8000-000000000003';
begin
  begin
    set local session_replication_role = replica;
    delete from crm.conversion_acreditaciones where lead_id = v_lead;   -- el lead quedó enlazado sin acreditación
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910317', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(104)),
      'P0409', 'crearía una acreditación nueva');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k)
      and not exists (select 1 from crm.conversion_acreditaciones where lead_id = v_lead), 'C17: nada cambió');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 17 venta sin acreditación: el reemplazo no crea una';
end $c17$;
set constraints all deferred;

-- ── 18 · Lead de la venta sin enlace al contrato: queda enlazado al nuevo (Codex r1, P1) ───────────────────────────────
do $c18$
declare v_k uuid := pg_temp.k('2026-01-910004'); v_lead uuid := 'd1000000-0000-4000-8000-000000000004'; r jsonb;
begin
  begin
    perform set_config('crm.op_privilegiada', 'on', true);
    update crm.leads set contrato_id = null where id = v_lead;          -- la acreditación sigue en el contrato
    perform set_config('crm.op_privilegiada', 'off', true);
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910418', 4000, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(105));
    set constraints all immediate;
    perform pg_temp.exigir((select contrato_id from crm.leads where id = v_lead) = (r ->> 'contrato_id')::uuid
      and (pg_temp.acr(v_lead)).fuente_id = (r ->> 'contrato_id')::uuid and (r #>> '{conversion,lead_enlazado}')::boolean
      and pg_temp.cuenta_conversion('2026-10-01') = 4, 'C18: lead y acreditación en el nuevo');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 18 lead sin enlace: queda enlazado al contrato que queda';
end $c18$;
set constraints all deferred;

-- ── 19 · El reintento exige los mismos permisos (Codex r1, P2) ────────────────────────────────────────────────────────
do $c19$
declare v_k uuid := pg_temp.k('2026-01-910002'); c jsonb;
begin
  begin
    c := pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910219', 2000, 'PEN', 18, date '2026-10-06');
    perform pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(106));
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(106)),
      '42501', 'solo gerencia');
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a3', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(106)),
      '42501', 'admin del portal');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 19 reintento: admin sin gerencia y gerencia sin admin no recuperan el resultado';
end $c19$;
set constraints all deferred;

-- ── 20 · La tasa se hereda aunque quien llama tenga las restricciones en IMMEDIATE ─────────────────────────────────────
set constraints all immediate;
do $c20$
declare v_k7 uuid := pg_temp.k('2026-01-910007'); r jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k7, 'Error de carga: número de contrato',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910720', 2500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(107));
    set constraints all immediate;
    perform pg_temp.exigir((select (l.detalle ->> 'reemplazo_tasa_heredada')::boolean from crm.ledger_rentabilidad l
      where l.contrato_id = (r ->> 'contrato_id')::uuid), 'C20: hereda 28 con IMMEDIATE');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 20 tasa heredada con las restricciones en IMMEDIATE';
end $c20$;
set constraints all deferred;

-- ── 21 · Sin su copia no hay excepción de tasa: un alta de admin a 28 (por encima del tope) se rechaza aunque en la misma
--        transacción se haya eliminado otro contrato con 28 ─────────────────────────────────────────────────────────────
do $c21$
begin
  begin
    perform pg_temp.api('a0000000-0000-4000-8000-0000000000a2', format('select crm.eliminar_inversion_fn(%L::uuid, %L)',
      pg_temp.k('2026-01-910007'), 'Eliminación de prueba'));
    perform pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910721', 2500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(108));
    set constraints all immediate;
    raise exception 'FALLA: C21 un alta a 28 sin reemplazo pasó el tope';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 21 la excepción de tasa exige la copia del reemplazo';
end $c21$;
set constraints all deferred;

-- ── 22 · Enforcement: la herencia vale para la MISMA intención; con otro capital, la tasa vuelve a pedir autorización ──
savepoint c22;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c22$
declare v_k2 uuid := pg_temp.k('2026-01-910002'); r jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k2, 'Capital equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910222', 9000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(111));
    set constraints all immediate;
    raise exception 'FALLA: C22 enforcement heredó 18 con otro capital sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 22 enforcement: con otra intención (capital) la tasa por encima de la base pide autorización';
end $c22$;
rollback to savepoint c22;
set constraints all deferred;

-- ── 23 · Observación: el reemplazo con otro capital conserva la tasa por encima del tope (como una corrección) ─────────
do $c23$
declare v_k7 uuid := pg_temp.k('2026-01-910007'); r jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k7, 'Capital equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910723', 3500, 'PEN', 28, date '2026-10-10'), pg_temp.cuenta(112));
    set constraints all immediate;
    perform pg_temp.exigir((select capital = 3500 and tasa_anual = 28 from public.contratos where id = (r ->> 'contrato_id')::uuid),
      'C23: capital corregido y tasa conservada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 23 observación: otro capital conserva la tasa heredada';
end $c23$;
set constraints all deferred;

-- ── 24 · «Quedarme con la otra» con la conservada en eliminación preparada → 55000 ────────────────────────────────────
do $c24$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_dup uuid;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910124', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(113));
    set local session_replication_role = replica;
    insert into private.contrato_eliminaciones (contrato_id, token, solicitado_por, objetos, creado_en)
      values (v_dup, gen_random_uuid(), 'a0000000-0000-4000-8000-0000000000a2', '[]', now());
    set local session_replication_role = origin;
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2',
      v_k, v_dup, 'Cargada dos veces'), '55000', 'en proceso de eliminación');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 24 quedarme con la otra: una conservada en eliminación preparada se rechaza';
end $c24$;
set constraints all deferred;

-- ── 25 · Reintento con OTROS datos: no recibe el resultado del primero ───────────────────────────────────────────────
do $c25$
declare v_k uuid := pg_temp.k('2026-01-910002'); c jsonb;
begin
  begin
    c := pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910225', 2000, 'PEN', 18, date '2026-10-06');
    perform pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(114));
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      c || '{"capital":2100}', pg_temp.cuenta(114)), 'P0409', 'ya se reemplazó por el contrato 2026-01-910225 con otros datos');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 25 reintento con otros datos: rechazo claro con el número del contrato que quedó';
end $c25$;
set constraints all deferred;

-- ── 26 · Venta de lead cuyo mes no se puede determinar (sin acreditación, sin episodio, sin convertido_en) → no se toca ──
do $c26$
declare v_k uuid := pg_temp.k('2026-01-910006');
begin
  begin
    set local session_replication_role = replica;
    insert into crm.leads (id, nombre_completo, telefono, dni, origen, etapa, convertido_en, vendedor_id, perfil_id, contrato_id, activo, monto_estimado)
      values ('d1000000-0000-4000-8000-000000000007', 'LEAD SIN FECHA PRUEBA', '+51999000007', '41000006', 'landing', 'convertido',
        null, 'a0000000-0000-4000-8000-0000000000a4', 'c1000000-0000-4000-8000-000000000006', v_k, true, 1000);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910626', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(121)),
      'P0409', 'no se puede determinar');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 26 venta sin mes determinable: el detector de las anulaciones la rechaza antes de borrar';
end $c26$;
set constraints all deferred;

-- ── 27 · Admin del portal con la membresía del CRM revocada: no reemplaza en ningún modo (revisión de seguridad) ────────
do $c27$
declare v_k uuid := pg_temp.k('2026-01-910006'); v_dup uuid;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910627', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(131));
    set local session_replication_role = replica;
    insert into crm.equipo (perfil_id, rol_crm, activo) values ('a0000000-0000-4000-8000-0000000000a1', 'vendedor', false);
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910628', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(132)),
      '42501', 'membresía del CRM está revocada');
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a1',
      v_k, v_dup, 'Cargada dos veces'), '42501', 'membresía del CRM está revocada');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 27 membresía revocada: admin del portal sin CRM vigente no reemplaza (nueva ni quedarme con la otra)';
end $c27$;
set constraints all deferred;

-- ── 28 · Contrato con cuotas pagadas: no se reemplaza (los pagos se perderían) — revisión de negocio ──────────────────
do $c28$
declare v_k uuid := pg_temp.k('2026-01-910003');
begin
  begin
    set local session_replication_role = replica;
    update public.cronograma_pagos set estado = 'pagado', monto_pagado = monto_programado, fecha_pago_real = date '2026-10-15'
      where contrato_id = v_k and numero_cuota = 1;
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910328', 3000, 'PEN', 15, date '2026-10-07'), pg_temp.cuenta(141)),
      'P0409', 'cuotas pagadas');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k), 'C28: el original sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 28 cuotas pagadas: el reemplazo se rechaza antes de borrar';
end $c28$;
set constraints all deferred;

-- ── 29 · «Quedarme con la otra» exige un duplicado de verdad (mismos datos) — revisión de negocio ──────────────────────
do $c29$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_otra uuid;
begin
  begin
    v_otra := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910129', 800, 'PEN', 15, date '2026-10-01'), pg_temp.cuenta(142));
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2',
      v_k, v_otra, 'Cargada dos veces'), 'P0409', 'no es igual a la original');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 29 quedarme con la otra: una inversión distinta no sirve como duplicado';
end $c29$;
set constraints all deferred;

-- ── 30 · «Quedarme con la otra» no muda la venta de mes porque el duplicado se cargó más tarde — revisión de negocio ────
do $c30$
declare v_k uuid := pg_temp.k('2026-01-910005'); v_lead uuid := 'd1000000-0000-4000-8000-000000000005'; v_dup uuid; r jsonb;
begin
  begin
    -- La venta de d5 se registró el 20/09 con inicio el 03/10 (venta de septiembre, fuente «registro»).
    set local session_replication_role = replica;
    update public.contratos set fecha_inicio = date '2026-10-03', fecha_vencimiento = date '2027-10-03' where id = v_k;
    set local session_replication_role = origin;
    -- El duplicado se carga HOY con el mismo inicio: el alta le pone el 03/10 (octubre).
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000005', '2026-01-910530', 1500, 'PEN', 15, date '2026-10-03'), pg_temp.cuenta(143));
    perform pg_temp.exigir((select fecha_cierre_comercial from public.contratos where id = v_dup) = date '2026-10-03', 'C30: el duplicado nace en octubre');
    r := pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces por error');
    set constraints all immediate;
    perform pg_temp.exigir((select fecha_cierre_comercial = date '2026-09-20' and fuente_cierre_comercial = 'registro'
      from public.contratos where id = v_dup), 'C30: la conservada queda con el día de la venta (20/09)');
    perform pg_temp.exigir((pg_temp.acr(v_lead)).periodo_comercial = '2026-09-01' and pg_temp.cuenta_conversion('2026-09-01') = 1
      and pg_temp.cuenta_conversion('2026-10-01') = 4, 'C30: la venta sigue en septiembre');
    perform pg_temp.exigir((select fecha_comercial from crm.inversiones where contrato_id = v_dup) = date '2026-09-20',
      'C30: la inversión acompaña a su contrato');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 30 quedarme con la otra: la venta conserva su mes aunque el duplicado se cargara después';
end $c30$;
set constraints all deferred;

-- ── 31 · El origen de capital confirmado por Gerencia pasa al contrato que queda — revisión de negocio ──────────────
do $c31$
declare v_k uuid := pg_temp.k('2026-01-910006'); r jsonb; c jsonb;
begin
  begin
    set local session_replication_role = replica;
    insert into crm.origenes_capital_confirmados (contrato_id, origen, motivo, confirmado_por, fecha_comercial)
      values (v_k, 'oficina', 'Origen confirmado por Gerencia en prueba', 'a0000000-0000-4000-8000-0000000000a2', date '2026-10-09');
    set local session_replication_role = origin;
    c := pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910631', 7000, 'PEN', 15, date '2026-10-09');
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(144)),
      '42501', 'origen de capital confirmado');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(144));
    set constraints all immediate;
    perform pg_temp.exigir(exists (select 1 from crm.origenes_capital_confirmados o where o.contrato_id = (r ->> 'contrato_id')::uuid
      and o.activo and o.origen = 'oficina'), 'C31: el origen confirmado pasó al contrato que queda');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 31 origen confirmado: pasa al contrato que queda; un admin sin Gerencia no puede reemplazarlo';
end $c31$;
set constraints all deferred;

-- ── 32 · Los cotitulares del original pasan al contrato que queda si el pedido no los trae ────────────────────────────
do $c32$
declare v_k uuid := pg_temp.k('2026-01-910006'); r jsonb;
begin
  begin
    set local session_replication_role = replica;
    insert into public.contrato_titulares (contrato_id, orden, nombre_completo, tipo_documento, documento, creado_por)
      values (v_k, 1, 'COTITULAR PRUEBA', 'DNI', '42000001', 'a0000000-0000-4000-8000-0000000000a2');
    set local session_replication_role = origin;
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910632', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(145));
    set constraints all immediate;
    perform pg_temp.exigir(exists (select 1 from public.contrato_titulares t where t.contrato_id = (r ->> 'contrato_id')::uuid
      and t.documento = '42000001'), 'C32: el cotitular pasó al contrato que queda');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 32 cotitulares: pasan al contrato que queda';
end $c32$;
set constraints all deferred;

-- ── 33 · Enforcement: una cadena A → B → C en la misma transacción no salta la validación de B (Codex r2, P1) ─────────
savepoint c33;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c33$
declare v_k2 uuid := pg_temp.k('2026-01-910002'); r jsonb; r2 jsonb;
begin
  begin
    -- B: otro capital con la tasa 18 (sin autorización nueva: C22 lo rechaza al commit).
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k2, 'Capital equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910333', 9000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(150));
    -- C: B con los mismos datos de B. Si B se borra antes de juzgarse, su copia «legitimaría» la tasa de C.
    r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910334', 9000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(151));
    set constraints all immediate;
    raise exception 'FALLA: C33 la cadena A → B → C heredó 18 con otro capital sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 33 enforcement: un intermedio sin validar no legitima la tasa del siguiente reemplazo';
end $c33$;
rollback to savepoint c33;
set constraints all deferred;

-- ── 34 · Observación: A (15) → B (28, sobre el tope) → C (28) en la misma transacción no salta el tope (Codex r2, P1) ───
do $c34$
declare v_k uuid := pg_temp.k('2026-01-910006'); r jsonb; r2 jsonb;
begin
  begin
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Tasa equivocada',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910634', 7000, 'PEN', 28, date '2026-10-09'), pg_temp.cuenta(152));
    r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910635', 7000, 'PEN', 28, date '2026-10-09'), pg_temp.cuenta(153));
    set constraints all immediate;
    raise exception 'FALLA: C34 la cadena A → B → C dejó 28 sobre el tope 25';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 34 observación: un intermedio sobre el tope no legitima la tasa del siguiente reemplazo';
end $c34$;
set constraints all deferred;

-- ── 35 · «Quedarme con la otra» con cotitulares distintos no es una carga doble (Codex r2, P2) ─────────────────────────
do $c35$
declare v_k uuid := pg_temp.k('2026-01-910006'); v_dup uuid;
begin
  begin
    set local session_replication_role = replica;
    insert into public.contrato_titulares (contrato_id, orden, nombre_completo, tipo_documento, documento, creado_por)
      values (v_k, 1, 'COTITULAR PRUEBA', 'DNI', '42000035', 'a0000000-0000-4000-8000-0000000000a2');
    set local session_replication_role = origin;
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910636', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(154));
    perform pg_temp.rechaza(format('select pg_temp.conservar(%L::uuid, %L::uuid, %L::uuid, %L)', 'a0000000-0000-4000-8000-0000000000a2',
      v_k, v_dup, 'Cargada dos veces'), 'P0409', 'cotitulares');
    perform pg_temp.exigir(exists (select 1 from public.contratos where id = v_k), 'C35: el original sigue');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 35 quedarme con la otra: con otros cotitulares no es un duplicado';
end $c35$;
set constraints all deferred;

-- ── 36 · El reintento con origen confirmado exige Gerencia, como el reemplazo (Codex r2, P2) ───────────────────────────
do $c36$
declare v_k uuid := pg_temp.k('2026-01-910006'); r jsonb; c jsonb;
begin
  begin
    set local session_replication_role = replica;
    insert into crm.origenes_capital_confirmados (contrato_id, origen, motivo, confirmado_por, fecha_comercial)
      values (v_k, 'oficina', 'Origen confirmado por Gerencia en prueba', 'a0000000-0000-4000-8000-0000000000a2', date '2026-10-09');
    set local session_replication_role = origin;
    c := pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910637', 7000, 'PEN', 15, date '2026-10-09');
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(155));
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a1', v_k, 'Error de carga de prueba', c, pg_temp.cuenta(155)),
      '42501', 'origen de capital confirmado');
    perform pg_temp.exigir((select ie.rol_actor from crm.inversiones_eliminadas ie where ie.fuente_id = v_k) = 'gerencia',
      'C36: la copia dice que hizo falta Gerencia');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 36 reintento: con origen confirmado, un admin sin Gerencia no recupera el resultado';
end $c36$;
set constraints all deferred;

-- ── 37 · Venta acreditada a esta inversión con el lead enlazado a OTRA: requiere revisión (Codex r2, hueco) ─────────────
do $c37$
declare v_k uuid := pg_temp.k('2026-01-910004'); v_lead uuid := 'd1000000-0000-4000-8000-000000000004'; v_otra uuid;
begin
  begin
    v_otra := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910437', 600, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(156));
    set local session_replication_role = replica;
    update crm.leads set contrato_id = v_otra where id = v_lead;      -- la acreditación sigue en el original
    set local session_replication_role = origin;
    perform pg_temp.rechaza(pg_temp.sql_reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k, 'Error de carga de prueba',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910438', 4000, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(157)),
      'P0409', 'enlazado a otra inversión');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 37 lead enlazado a otra inversión: el reemplazo pide revisión';
end $c37$;
set constraints all deferred;

-- ── 38 · Enforcement: la cadena LEGÍTIMA (mismos datos en cada paso) sigue heredando la tasa ──────────────────────────
savepoint c38;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c38$
declare v_k2 uuid := pg_temp.k('2026-01-910002'); r jsonb; r2 jsonb;
begin
  r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k2, 'Número equivocado',
    pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910338', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(158));
  r2 := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', (r ->> 'contrato_id')::uuid, 'Otra vez el número',
    pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910339', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(159));
  set constraints all immediate;
  perform pg_temp.exigir((select tasa_anual = 18 from public.contratos where id = (r2 ->> 'contrato_id')::uuid)
    and (select (l.detalle ->> 'reemplazo_tasa_heredada')::boolean from crm.ledger_rentabilidad l
         where l.contrato_id = (r2 ->> 'contrato_id')::uuid), 'C38: la cadena con los mismos datos hereda 18');
  raise notice 'PASS 38 enforcement: la cadena legítima A → B → C hereda la tasa (el intermedio se juzga y pasa)';
end $c38$;
rollback to savepoint c38;
set constraints all deferred;

-- ── 39 · Enforcement: con otra condición de producto declarada, la tasa vuelve a pedir autorización (Codex r2, hueco) ─
savepoint c39;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c39$
declare v_k2 uuid := pg_temp.k('2026-01-910002'); v_cond uuid := gen_random_uuid(); r jsonb;
begin
  begin
    -- El original pasa a una condición DECLARADA del catálogo (no legacy); el alta del reemplazo nace libre (legacy).
    set local session_replication_role = replica;
    insert into crm.producto_condiciones (id, version_id, orden, categoria, moneda, plazo_meses, modalidad, tipo_interes,
        capital_minimo, capital_maximo, tasa_referencia, tasa_minima, tasa_maxima)
      select v_cond, pc.version_id, 99, 'nuevo', 'PEN', 12, 'mensual', 'simple', 100, 100000, 15, 10, 30
      from crm.producto_condiciones pc join public.contratos c on c.producto_condicion_id = pc.id where c.id = v_k2;
    update public.contratos set producto_condicion_id = v_cond where id = v_k2;
    set local session_replication_role = origin;
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_k2, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000002', '2026-01-910340', 2000, 'PEN', 18, date '2026-10-06'), pg_temp.cuenta(160));
    set constraints all immediate;
    raise exception 'FALLA: C39 heredó 18 con otra condición de producto sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 39 enforcement: otra condición de producto declarada es otra intención';
end $c39$;
rollback to savepoint c39;
set constraints all deferred;

-- ── 40 · Dos copias nombran al mismo contrato: el día de la venta lo da la copia de la VENTA (Codex r2, hueco) ───────────
do $c40$
declare v_k uuid := pg_temp.k('2026-01-910001'); v_lead uuid := 'd1000000-0000-4000-8000-000000000001'; v_a2 uuid; v_d uuid; r jsonb;
begin
  begin
    -- A2: la misma inversión, sin venta, registrada el 20/09; D: el duplicado que se conserva.
    v_a2 := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910140', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(161));
    set local session_replication_role = replica;
    update public.contratos set creado_en = timestamptz '2026-09-20 10:00:00-05' where id = v_a2;
    set local session_replication_role = origin;
    v_d := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910141', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(162));
    perform pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_a2, v_d, 'Cargada dos veces');   -- sin venta
    perform pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_d, 'Cargada tres veces');   -- la venta de d1
    -- Reemplazar D: su copia de la venta dice «registrada hoy» (octubre); la de A2, 20/09. Manda la de la venta.
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_d, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000001', '2026-01-910142', 5000, 'PEN', 15, date '2026-10-05'), pg_temp.cuenta(163));
    set constraints all immediate;
    perform pg_temp.exigir((pg_temp.acr(v_lead)).periodo_comercial = '2026-10-01' and pg_temp.cuenta_conversion('2026-10-01') = 4
      and pg_temp.cuenta_conversion('2026-09-01') = 1, 'C40: la venta sigue en octubre');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 40 cadena con dos copias: el día de la venta sale de la copia de la venta';
end $c40$;
set constraints all deferred;

-- ── 35b · «Quedarme con la otra» con los MISMOS cotitulares cargados en otro orden: es una carga doble (auditor r2, P2) ─
do $c35b$
declare v_k uuid := pg_temp.k('2026-01-910006'); v_dup uuid; r jsonb;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000006', '2026-01-910639', 7000, 'PEN', 15, date '2026-10-09'), pg_temp.cuenta(164));
    set local session_replication_role = replica;
    insert into public.contrato_titulares (contrato_id, orden, nombre_completo, tipo_documento, documento, creado_por) values
      (v_k, 1, 'COTITULAR A', 'DNI', '42000041', 'a0000000-0000-4000-8000-0000000000a2'),
      (v_k, 2, 'COTITULAR B', 'DNI', '42000042', 'a0000000-0000-4000-8000-0000000000a2');
    insert into public.contrato_titulares (contrato_id, orden, nombre_completo, tipo_documento, documento, creado_por) values
      (v_dup, 1, 'COTITULAR B', 'DNI', ' 42000042 ', 'a0000000-0000-4000-8000-0000000000a2'),
      (v_dup, 2, 'COTITULAR A', 'DNI', '42000041', 'a0000000-0000-4000-8000-0000000000a2');
    set local session_replication_role = origin;
    r := pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces');
    set constraints all immediate;
    perform pg_temp.exigir(not exists (select 1 from public.contratos where id = v_k) and (r ->> 'contrato_id')::uuid = v_dup
      and (select count(*) from public.contrato_titulares where contrato_id = v_dup) = 2, 'C35b: se conserva la otra con sus 2 cotitulares');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 35b quedarme con la otra: los mismos cotitulares en otro orden sí son un duplicado';
end $c35b$;
set constraints all deferred;

-- ── 37b · «Quedarme con la otra» con el lead YA enlazado a la que se conserva: la venta se muda allí (auditor r2, P3) ──
do $c37b$
declare v_k uuid := pg_temp.k('2026-01-910004'); v_lead uuid := 'd1000000-0000-4000-8000-000000000004'; v_dup uuid; r jsonb;
begin
  begin
    v_dup := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000004', '2026-01-910439', 4000, 'PEN', 15, date '2026-10-08'), pg_temp.cuenta(165));
    set local session_replication_role = replica;
    update crm.leads set contrato_id = v_dup where id = v_lead;      -- la acreditación sigue en el original
    set local session_replication_role = origin;
    r := pg_temp.conservar('a0000000-0000-4000-8000-0000000000a2', v_k, v_dup, 'Cargada dos veces');
    set constraints all immediate;
    perform pg_temp.exigir((pg_temp.acr(v_lead)).fuente_id = v_dup and (select contrato_id from crm.leads where id = v_lead) = v_dup
      and pg_temp.cuenta_conversion('2026-10-01') = 4, 'C37b: venta y enlace en la que se conserva');
    perform pg_temp.deshacer();
  exception when sqlstate 'P7999' then null;
  end;
  raise notice 'PASS 37b quedarme con la otra: el lead ya enlazado a la conservada no bloquea';
end $c37b$;
set constraints all deferred;

-- ── 41 · Enforcement: un alta normal SIN autorización y su reemplazo en la misma transacción → P0410 (auditor r2) ───────
savepoint c41;
insert into crm.politica_rentabilidad (version, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo)
  select max(version) + 1, clock_timestamp(), 15, 25, 1, 'enforcement' from crm.politica_rentabilidad;
do $c41$
declare v_x uuid; r jsonb;
begin
  begin
    v_x := pg_temp.alta(pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910341', 3000, 'PEN', 18, date '2026-10-07'), pg_temp.cuenta(166));
    r := pg_temp.reemplazar('a0000000-0000-4000-8000-0000000000a2', v_x, 'Número equivocado',
      pg_temp.contrato('c1000000-0000-4000-8000-000000000003', '2026-01-910342', 3000, 'PEN', 18, date '2026-10-07'), pg_temp.cuenta(167));
    set constraints all immediate;
    raise exception 'FALLA: C41 el reemplazo legitimó la tasa 18 de un alta sin autorización';
  exception when sqlstate 'P0410' then null;
  end;
  raise notice 'PASS 41 enforcement: el reemplazo no legitima la tasa de un alta aún sin juzgar';
end $c41$;
rollback to savepoint c41;
set constraints all deferred;

do $fin$
begin
  perform pg_temp.exigir(pg_temp.cuenta_conversion('2026-10-01') = 4 and pg_temp.cuenta_conversion('2026-09-01') = 1
    and not exists (select 1 from crm.inversiones_eliminadas), 'los casos se deshicieron');
  raise notice 'PASS reemplazar_inversion: 45 bloques (0 reproducción, 1-9, 10a, 10b, 11-35, 35b, 36, 37, 37b, 38-41); se revierte';
end $fin$;
rollback;
