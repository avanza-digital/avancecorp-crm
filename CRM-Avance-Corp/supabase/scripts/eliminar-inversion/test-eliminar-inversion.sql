-- Pruebas de crm.eliminar_inversion_fn (20261005200945) en el BANCO Docker propio: esquema de producción, sin datos.
-- Se corre como supabase_admin (la siembra apaga los triggers con session_replication_role; las pruebas los encienden).
-- TODO termina en ROLLBACK: el banco queda como estaba y la batería se puede repetir.
--   docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U supabase_admin -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -qAt -f - < supabase/scripts/eliminar-inversion/test-eliminar-inversion.sql
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

-- Llama a la puerta COMO authenticated (lo que hace PostgREST). Un error revierte el SET LOCAL ROLE con su subtransacción.
create function pg_temp.eliminar(p_uid uuid, p_fuente uuid, p_motivo text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform pg_temp.como(p_uid);
  set local role authenticated;
  r := crm.eliminar_inversion_fn(p_fuente, p_motivo);
  reset role;
  perform pg_temp.como(null);
  return r;
end $$;

create function pg_temp.rechaza(p_sql text, p_estado text, p_mensaje text default null) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlstate = p_estado and (p_mensaje is null or position(p_mensaje in sqlerrm) > 0) then
      perform pg_temp.como(null);
      return;
    end if;
    raise exception 'FALLA: se esperaba % «%», llegó % «%» en: %', p_estado, coalesce(p_mensaje, ''), sqlstate, sqlerrm, p_sql;
  end;
  raise exception 'FALLA: debió rechazar con % en: %', p_estado, p_sql;
end $$;

-- ── Siembra (triggers apagados SOLO aquí) ──────────────────────────────────────────────────────────────────────────────
set local session_replication_role = replica;

insert into crm.empresas (id, clave, nombre_legal, nombre_visible, fuente_capital, activa) values
  ('10000000-0000-4000-8000-000000000001', 'avance', 'AVANCE PRUEBA SAC', 'Avance', 'contratos', true),
  ('10000000-0000-4000-8000-000000000002', 'prodelco', 'PRODELCO PRUEBA', 'Prodelco', 'cierres_externos', true),
  ('10000000-0000-4000-8000-000000000003', 'qorilazo', 'QORILAZO PRUEBA', 'Qorilazo', 'cierres_externos', true);

-- ADM admin sin CRM · GER admin + gerencia · GSO gerencia sin admin del portal · VEN vendedor · CLI cliente (Avance)
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('a0000000-0000-4000-8000-0000000000a1', 'ADMIN PRUEBA', 'admin', true),
  ('a0000000-0000-4000-8000-0000000000a2', 'GERENCIA PRUEBA', 'admin', true),
  ('a0000000-0000-4000-8000-0000000000a3', 'GERENCIA SOLA PRUEBA', 'analista', true),
  ('a0000000-0000-4000-8000-0000000000a4', 'VENDEDOR PRUEBA', 'analista', true),
  ('a0000000-0000-4000-8000-0000000000a5', 'CLIENTE AVANCE PRUEBA', 'cliente', true);
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('a0000000-0000-4000-8000-0000000000a2', 'gerencia', true),
  ('a0000000-0000-4000-8000-0000000000a3', 'gerencia', true),
  ('a0000000-0000-4000-8000-0000000000a4', 'vendedor', true);

insert into crm.inversionistas (id, estado) values
  ('b0000000-0000-4000-8000-0000000000b1', 'activo'), ('b0000000-0000-4000-8000-0000000000b2', 'activo'),
  ('b0000000-0000-4000-8000-0000000000b3', 'activo'), ('b0000000-0000-4000-8000-0000000000b4', 'activo'),
  ('b0000000-0000-4000-8000-0000000000b5', 'activo'), ('b0000000-0000-4000-8000-0000000000b6', 'activo');

-- Leads convertidos: cooperativa (agosto, rama de conversión ANTERIOR a septiembre), cooperativa ya anulada, Avance.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, contrato_id, activo, monto_estimado) values
  ('c0000000-0000-4000-8000-0000000000c1', 'LEAD COOP CONVERSION', '999000001', 'landing', 'convertido', '2026-08-20 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', null, true, 1000),
  ('c0000000-0000-4000-8000-0000000000c2', 'LEAD COOP ANULADO', '999000002', 'landing', 'convertido', '2026-08-21 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', null, true, 1000),
  ('c0000000-0000-4000-8000-0000000000c3', 'LEAD AVANCE CONVERSION', '999000003', 'landing', 'convertido', '2026-08-22 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', 'd0000000-0000-4000-8000-0000000000d2', true, 1000);
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  select l.id, 1, 1, 'a0000000-0000-4000-8000-0000000000a4', 'asignado', l.convertido_en - interval '5 days', 'PEN', 'landing',
    l.convertido_en - interval '5 days', gen_random_uuid(), l.convertido_en, l.convertido_en, 'convertido', l.convertido_en,
    l.convertido_en, 'a0000000-0000-4000-8000-0000000000a4', 'convertido'
  from crm.leads l where l.id in ('c0000000-0000-4000-8000-0000000000c1', 'c0000000-0000-4000-8000-0000000000c2', 'c0000000-0000-4000-8000-0000000000c3');

-- Cierres de cooperativa: NC (no conversión), CV (conversión sin anular), CA (conversión ya anulada), H (con retiro).
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
    vendedor_id, creado_por, es_cierre_inicial, lead_id, inversionista_id, fecha_comercial, fecha_imputacion, anulado_en, anulado_por, motivo_anulacion,
    comprobante_objeto_id, referencia_externa) values
  ('e0000000-0000-4000-8000-0000000000e1', 'prodelco', 1000, 'USD', 'DNI', '40000001', 'PERSONA NC', 'TX-NC',
    'a0000000-0000-4000-8000-0000000000a4', 'a0000000-0000-4000-8000-0000000000a4', false, null, 'b0000000-0000-4000-8000-0000000000b1', '2026-09-15', '2026-09-15', null, null, null, gen_random_uuid(), 'REF NC'),
  ('e0000000-0000-4000-8000-0000000000e2', 'qorilazo', 2000, 'PEN', 'DNI', '40000002', 'PERSONA CV', 'TX-CV',
    'a0000000-0000-4000-8000-0000000000a4', 'a0000000-0000-4000-8000-0000000000a4', true, 'c0000000-0000-4000-8000-0000000000c1', 'b0000000-0000-4000-8000-0000000000b2', '2026-08-20', '2026-08-20', null, null, null, gen_random_uuid(), 'REF CV'),
  ('e0000000-0000-4000-8000-0000000000e3', 'qorilazo', 3000, 'PEN', 'DNI', '40000003', 'PERSONA CA', 'TX-CA',
    'a0000000-0000-4000-8000-0000000000a4', 'a0000000-0000-4000-8000-0000000000a4', true, 'c0000000-0000-4000-8000-0000000000c2', 'b0000000-0000-4000-8000-0000000000b3', '2026-08-21', '2026-08-21',
    '2026-09-01 10:00-05', 'a0000000-0000-4000-8000-0000000000a2', 'Anulada antes por gerencia', gen_random_uuid(), 'REF CA'),
  ('e0000000-0000-4000-8000-0000000000e4', 'prodelco', 4000, 'USD', 'DNI', '40000004', 'PERSONA H', 'TX-H',
    'a0000000-0000-4000-8000-0000000000a4', 'a0000000-0000-4000-8000-0000000000a4', false, null, 'b0000000-0000-4000-8000-0000000000b6', '2026-09-16', '2026-09-16', null, null, null, gen_random_uuid(), 'REF H');
insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion) values
  ('f0000000-0000-4000-8000-0000000000f1', 'b0000000-0000-4000-8000-0000000000b1', '10000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-0000000000e1', 'vigente', '2026-09-15', false),
  ('f0000000-0000-4000-8000-0000000000f2', 'b0000000-0000-4000-8000-0000000000b2', '10000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-0000000000e2', 'vigente', '2026-08-20', true),
  ('f0000000-0000-4000-8000-0000000000f3', 'b0000000-0000-4000-8000-0000000000b3', '10000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-0000000000e3', 'anulada', '2026-08-21', true),
  ('f0000000-0000-4000-8000-0000000000f4', 'b0000000-0000-4000-8000-0000000000b6', '10000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-0000000000e4', 'vigente', '2026-09-16', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id)
  select i.id, i.inversionista_id from crm.inversiones i where i.id::text like 'f0000000%';
insert into crm.inversion_eventos (inversion_id, tipo) select i.id, 'registro' from crm.inversiones i where i.id::text like 'f0000000%';
insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por)
  select 'DEP-' || right(c.id::text, 2), c.id, 'a0000000-0000-4000-8000-0000000000a4' from crm.cierres_externos c where c.id::text like 'e0000000%';
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por, estado, inversion_id, resultado, confirmado_por)
  select ('5' || substr(i.id::text, 2))::uuid, i.inversionista_id, i.empresa_id, 'a0000000-0000-4000-8000-0000000000a4', md5(i.id::text) || md5(i.id::text || 'x'), '{}'::jsonb,
    'a0000000-0000-4000-8000-0000000000a4', 'confirmada', i.id,
    case when i.cierre_externo_id is not null then jsonb_build_object('fuente', jsonb_build_object('cierre_id', i.cierre_externo_id))
         else jsonb_build_object('fuente', jsonb_build_object('id', i.contrato_id)) end, 'a0000000-0000-4000-8000-0000000000a4'
  from crm.inversiones i where i.id::text like 'f0000000%';
insert into crm.postventa_retiros (id, inversionista_id, fuente_id, empresa, motivo, creado_por) values
  (gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000b6', 'e0000000-0000-4000-8000-0000000000e4', 'prodelco', 'Retiro de prueba', 'a0000000-0000-4000-8000-0000000000a4');

-- Avance: NC (contrato sin conversión) y CV (contrato que es la conversión del lead c3).
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento,
    producto_condicion_id, fecha_cierre_comercial, estado, categoria) values
  ('d0000000-0000-4000-8000-0000000000d1', 'PRUEBA-0001', 'a0000000-0000-4000-8000-0000000000a5', 5000, 'PEN', 'mensual', '2026-09-10', '2027-09-10',
    gen_random_uuid(), '2026-09-10', 'activo', 'nuevo'),
  ('d0000000-0000-4000-8000-0000000000d2', 'PRUEBA-0002', 'a0000000-0000-4000-8000-0000000000a5', 6000, 'PEN', 'mensual', '2026-08-22', '2027-08-22',
    gen_random_uuid(), '2026-08-22', 'activo', 'nuevo');
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id, estado, fecha_comercial, es_primera_conversion) values
  ('f0000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-0000000000b4', '10000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000d1', 'vigente', '2026-09-10', false),
  ('f0000000-0000-4000-8000-0000000000a2', 'b0000000-0000-4000-8000-0000000000b5', '10000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000d2', 'vigente', '2026-08-22', true);
insert into crm.inversion_titulares (inversion_id, inversionista_id)
  select i.id, i.inversionista_id from crm.inversiones i where i.contrato_id is not null and i.id::text like 'f0000000%';
insert into crm.inversion_eventos (inversion_id, tipo) select i.id, 'registro' from crm.inversiones i where i.contrato_id is not null and i.id::text like 'f0000000%';
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por, estado, inversion_id, resultado, confirmado_por)
  select ('5' || substr(i.id::text, 2))::uuid, i.inversionista_id, i.empresa_id, 'a0000000-0000-4000-8000-0000000000a4', md5(i.id::text) || md5(i.id::text || 'x'), '{}'::jsonb,
    'a0000000-0000-4000-8000-0000000000a4', 'confirmada', i.id, jsonb_build_object('fuente', jsonb_build_object('id', i.contrato_id)), 'a0000000-0000-4000-8000-0000000000a4'
  from crm.inversiones i where i.contrato_id is not null and i.id::text like 'f0000000%';


-- r2 (Codex r1): conversión de SEPTIEMBRE (rama de acreditaciones) cuya solicitud de alta trae lead de origen (al cancelarla, el
-- trigger AFTER UPDATE sincroniza el lead), cierre SIN fila en crm.inversiones y cierre con una corrección previa.
insert into crm.conversion_politica (unica, vigente_desde, activada_en, manifiesto_huella, resultado)
  values (true, '2026-09-01', '2026-09-01 00:00-05', 'prueba', '{}'::jsonb)
  on conflict (unica) do update set activada_en = excluded.activada_en, manifiesto_huella = excluded.manifiesto_huella, resultado = excluded.resultado;
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, contrato_id, activo, monto_estimado) values
  ('c0000000-0000-4000-8000-0000000000c4', 'LEAD COOP SEPTIEMBRE', '999000004', 'landing', 'convertido', '2026-09-20 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', null, true, 1000);
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  values ('c0000000-0000-4000-8000-0000000000c4', 1, 1, 'a0000000-0000-4000-8000-0000000000a4', 'asignado', '2026-09-15 15:00-05', 'PEN', 'landing',
    '2026-09-15 15:00-05', gen_random_uuid(), '2026-09-20 15:00-05', '2026-09-20 15:00-05', 'convertido', '2026-09-20 15:00-05',
    '2026-09-20 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', 'convertido');
insert into crm.inversionistas (id, estado) values
  ('b0000000-0000-4000-8000-0000000000b7', 'activo'), ('b0000000-0000-4000-8000-0000000000b8', 'activo'), ('b0000000-0000-4000-8000-0000000000b9', 'activo');
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
    vendedor_id, creado_por, es_cierre_inicial, lead_id, inversionista_id, fecha_comercial, fecha_imputacion, comprobante_objeto_id, referencia_externa) values
  ('e0000000-0000-4000-8000-0000000000e5', 'qorilazo', 5000, 'PEN', 'DNI', '40000005', 'PERSONA SE', 'TX-SE', 'a0000000-0000-4000-8000-0000000000a4',
    'a0000000-0000-4000-8000-0000000000a4', true, 'c0000000-0000-4000-8000-0000000000c4', 'b0000000-0000-4000-8000-0000000000b7', '2026-09-20', '2026-09-20', gen_random_uuid(), 'REF SE'),
  ('e0000000-0000-4000-8000-0000000000e6', 'prodelco', 600, 'USD', 'DNI', '40000006', 'PERSONA SI', 'TX-SI', 'a0000000-0000-4000-8000-0000000000a4',
    'a0000000-0000-4000-8000-0000000000a4', false, null, 'b0000000-0000-4000-8000-0000000000b8', '2026-09-21', '2026-09-21', gen_random_uuid(), 'REF SI'),
  ('e0000000-0000-4000-8000-0000000000e7', 'prodelco', 700, 'USD', 'DNI', '40000007', 'PERSONA CO', 'TX-CO', 'a0000000-0000-4000-8000-0000000000a4',
    'a0000000-0000-4000-8000-0000000000a4', false, null, 'b0000000-0000-4000-8000-0000000000b9', '2026-09-22', '2026-09-22', gen_random_uuid(), 'REF CO');
insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion) values
  ('f0000000-0000-4000-8000-0000000000f5', 'b0000000-0000-4000-8000-0000000000b7', '10000000-0000-4000-8000-000000000003', 'e0000000-0000-4000-8000-0000000000e5', 'vigente', '2026-09-20', true),
  ('f0000000-0000-4000-8000-0000000000f7', 'b0000000-0000-4000-8000-0000000000b9', '10000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-0000000000e7', 'vigente', '2026-09-22', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id) values
  ('f0000000-0000-4000-8000-0000000000f5', 'b0000000-0000-4000-8000-0000000000b7'), ('f0000000-0000-4000-8000-0000000000f7', 'b0000000-0000-4000-8000-0000000000b9');
insert into crm.inversion_eventos (inversion_id, tipo, motivo) values
  ('f0000000-0000-4000-8000-0000000000f5', 'registro', null), ('f0000000-0000-4000-8000-0000000000f7', 'registro', null),
  ('f0000000-0000-4000-8000-0000000000f7', 'correccion', 'Monto corregido por gerencia');
insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por) values
  ('DEP-e5', 'e0000000-0000-4000-8000-0000000000e5', 'a0000000-0000-4000-8000-0000000000a4'),
  ('DEP-e6', 'e0000000-0000-4000-8000-0000000000e6', 'a0000000-0000-4000-8000-0000000000a4'),
  ('DEP-e7', 'e0000000-0000-4000-8000-0000000000e7', 'a0000000-0000-4000-8000-0000000000a4');
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por, estado,
    inversion_id, resultado, confirmado_por, lead_origen_id) values
  ('50000000-0000-4000-8000-0000000000f5', 'b0000000-0000-4000-8000-0000000000b7', '10000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-0000000000a4',
    md5('se') || md5('se2'), jsonb_build_object('lead_id', 'c0000000-0000-4000-8000-0000000000c4'), 'a0000000-0000-4000-8000-0000000000a4', 'confirmada',
    'f0000000-0000-4000-8000-0000000000f5', jsonb_build_object('fuente', jsonb_build_object('cierre_id', 'e0000000-0000-4000-8000-0000000000e5')),
    'a0000000-0000-4000-8000-0000000000a4', 'c0000000-0000-4000-8000-0000000000c4');
insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
    confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, motivo)
  values ('c0000000-0000-4000-8000-0000000000c4', gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000b7', 'a0000000-0000-4000-8000-0000000000a4',
    'landing', 'cierre_externo', 'e0000000-0000-4000-8000-0000000000e5', '2026-09-20', '2026-09-20 15:00-05', '2026-09-20 15:00-05',
    '2026-09-20 15:00-05', '2026-09-01', private.conversion_plazo_hasta('2026-09-01'), 'acreditada', 'Acreditación de prueba');


-- r3 (auditor-rls r2): actores inactivos y superadmin sin gerencia; un cierre limpio para el censo de dependencias; Avance cuya
-- conversión la decide la ACREDITACIÓN (el lead no enlaza el contrato) y Avance con acreditación que discrepa del lead enlazado.
insert into public.perfiles (id, nombre_completo, rol, activo) values
  ('a0000000-0000-4000-8000-0000000000a6', 'ADMIN INACTIVO PRUEBA', 'admin', false),
  ('a0000000-0000-4000-8000-0000000000a7', 'GERENCIA INACTIVA PRUEBA', 'analista', true),
  ('a0000000-0000-4000-8000-0000000000a8', 'SUPERADMIN PRUEBA', 'superadmin', true);
insert into crm.equipo (perfil_id, rol_crm, activo) values ('a0000000-0000-4000-8000-0000000000a7', 'gerencia', false);
insert into crm.inversionistas (id, estado) values ('b0000000-0000-4000-8000-0000000000ba', 'activo'),
  ('b0000000-0000-4000-8000-0000000000bb', 'activo'), ('b0000000-0000-4000-8000-0000000000bc', 'activo');
insert into crm.cierres_externos (id, cooperativa, monto, moneda, documento_tipo, documento, nombre_completo, numero_transaccion,
    vendedor_id, creado_por, es_cierre_inicial, lead_id, inversionista_id, fecha_comercial, fecha_imputacion, comprobante_objeto_id, referencia_externa) values
  ('e0000000-0000-4000-8000-0000000000e8', 'prodelco', 800, 'USD', 'DNI', '40000008', 'PERSONA D', 'TX-D', 'a0000000-0000-4000-8000-0000000000a4',
    'a0000000-0000-4000-8000-0000000000a4', false, null, 'b0000000-0000-4000-8000-0000000000ba', '2026-09-23', '2026-09-23', gen_random_uuid(), 'REF D');
insert into crm.inversiones (id, inversionista_id, empresa_id, cierre_externo_id, estado, fecha_comercial, es_primera_conversion) values
  ('f0000000-0000-4000-8000-0000000000f8', 'b0000000-0000-4000-8000-0000000000ba', '10000000-0000-4000-8000-000000000002', 'e0000000-0000-4000-8000-0000000000e8', 'vigente', '2026-09-23', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id) values ('f0000000-0000-4000-8000-0000000000f8', 'b0000000-0000-4000-8000-0000000000ba');
insert into crm.inversion_eventos (inversion_id, tipo) values ('f0000000-0000-4000-8000-0000000000f8', 'registro');
insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por) values ('DEP-e8', 'e0000000-0000-4000-8000-0000000000e8', 'a0000000-0000-4000-8000-0000000000a4');
insert into crm.inversion_solicitudes (id, inversionista_id, empresa_id, responsable_esperado_id, hash_payload, datos, creado_por, estado,
    inversion_id, resultado, confirmado_por) values
  ('50000000-0000-4000-8000-0000000000f8', 'b0000000-0000-4000-8000-0000000000ba', '10000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-0000000000a4',
    md5('d') || md5('d2'), '{}'::jsonb, 'a0000000-0000-4000-8000-0000000000a4', 'confirmada', 'f0000000-0000-4000-8000-0000000000f8',
    jsonb_build_object('fuente', jsonb_build_object('cierre_id', 'e0000000-0000-4000-8000-0000000000e8')), 'a0000000-0000-4000-8000-0000000000a4');
insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, modalidad, fecha_inicio, fecha_vencimiento,
    producto_condicion_id, fecha_cierre_comercial, estado, categoria) values
  ('d0000000-0000-4000-8000-0000000000d3', 'PRUEBA-0003', 'a0000000-0000-4000-8000-0000000000a5', 9000, 'PEN', 'mensual', '2026-09-24', '2027-09-24',
    gen_random_uuid(), '2026-09-24', 'activo', 'nuevo'),
  ('d0000000-0000-4000-8000-0000000000d4', 'PRUEBA-0004', 'a0000000-0000-4000-8000-0000000000a5', 9500, 'PEN', 'mensual', '2026-09-25', '2027-09-25',
    gen_random_uuid(), '2026-09-25', 'activo', 'nuevo');
insert into crm.inversiones (id, inversionista_id, empresa_id, contrato_id, estado, fecha_comercial, es_primera_conversion) values
  ('f0000000-0000-4000-8000-0000000000a3', 'b0000000-0000-4000-8000-0000000000bb', '10000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000d3', 'vigente', '2026-09-24', false),
  ('f0000000-0000-4000-8000-0000000000a4', 'b0000000-0000-4000-8000-0000000000bc', '10000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-0000000000d4', 'vigente', '2026-09-25', false);
insert into crm.inversion_titulares (inversion_id, inversionista_id) values
  ('f0000000-0000-4000-8000-0000000000a3', 'b0000000-0000-4000-8000-0000000000bb'), ('f0000000-0000-4000-8000-0000000000a4', 'b0000000-0000-4000-8000-0000000000bc');
insert into crm.inversion_eventos (inversion_id, tipo) values ('f0000000-0000-4000-8000-0000000000a3', 'registro'), ('f0000000-0000-4000-8000-0000000000a4', 'registro');
-- c5: convertido con perfil, SIN contrato enlazado; su conversión de septiembre está acreditada al contrato d3.
-- c6: convertido y ENLAZADO a d4; c7: convertido, pero la acreditación de d4 es SUYA (discrepancia).
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, convertido_en, vendedor_id, contrato_id, activo, monto_estimado, perfil_id) values
  ('c0000000-0000-4000-8000-0000000000c5', 'LEAD AVANCE ACREDITADO', '999000005', 'landing', 'convertido', '2026-09-24 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', null, true, 1000, 'a0000000-0000-4000-8000-0000000000a5'),
  ('c0000000-0000-4000-8000-0000000000c6', 'LEAD AVANCE ENLAZADO', '999000006', 'landing', 'convertido', '2026-09-25 15:00-05', 'a0000000-0000-4000-8000-0000000000a4', 'd0000000-0000-4000-8000-0000000000d4', true, 1000, 'a0000000-0000-4000-8000-0000000000a5'),
  ('c0000000-0000-4000-8000-0000000000c7', 'LEAD AVANCE OTRO', '999000007', 'landing', 'convertido', '2026-09-25 16:00-05', 'a0000000-0000-4000-8000-0000000000a4', null, true, 1000, 'a0000000-0000-4000-8000-0000000000a5');
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura, asignado_en, moneda, origen,
    sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en, primer_contacto_limite_en, resultado, resultado_en,
    finalizado_en, finalizado_por, motivo_cierre)
  select l.id, 1, 1, 'a0000000-0000-4000-8000-0000000000a4', 'asignado', l.convertido_en - interval '5 days', 'PEN', 'landing',
    l.convertido_en - interval '5 days', gen_random_uuid(), l.convertido_en, l.convertido_en, 'convertido', l.convertido_en,
    l.convertido_en, 'a0000000-0000-4000-8000-0000000000a4', 'convertido'
  from crm.leads l where l.id in ('c0000000-0000-4000-8000-0000000000c5', 'c0000000-0000-4000-8000-0000000000c6', 'c0000000-0000-4000-8000-0000000000c7');
insert into crm.conversion_acreditaciones (lead_id, episodio_id, inversionista_id, analista_id, origen, fuente_tipo, fuente_id, fecha_comercial,
    confirmado_en, vinculado_en, acreditado_en, periodo_comercial, plazo_hasta, estado, motivo) values
  ('c0000000-0000-4000-8000-0000000000c5', gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000bb', 'a0000000-0000-4000-8000-0000000000a4', 'landing',
    'contrato', 'd0000000-0000-4000-8000-0000000000d3', '2026-09-24', '2026-09-24 15:00-05', '2026-09-24 15:00-05', '2026-09-24 15:00-05',
    '2026-09-01', private.conversion_plazo_hasta('2026-09-01'), 'acreditada', 'Acreditación de prueba'),
  ('c0000000-0000-4000-8000-0000000000c7', gen_random_uuid(), 'b0000000-0000-4000-8000-0000000000bc', 'a0000000-0000-4000-8000-0000000000a4', 'landing',
    'contrato', 'd0000000-0000-4000-8000-0000000000d4', '2026-09-25', '2026-09-25 16:00-05', '2026-09-25 16:00-05', '2026-09-25 16:00-05',
    '2026-09-01', private.conversion_plazo_hasta('2026-09-01'), 'acreditada', 'Acreditación de prueba');

-- Un lead convertido de Avance está enlazado a su perfil de cliente (como en producción).
update crm.leads set perfil_id = 'a0000000-0000-4000-8000-0000000000a5' where id = 'c0000000-0000-4000-8000-0000000000c3';

set local session_replication_role = origin;

-- ── Pruebas ────────────────────────────────────────────────────────────────────────────────────────────────────────────
do $pruebas$
declare
  ADM constant uuid := 'a0000000-0000-4000-8000-0000000000a1';
  GER constant uuid := 'a0000000-0000-4000-8000-0000000000a2';
  GSO constant uuid := 'a0000000-0000-4000-8000-0000000000a3';
  VEN constant uuid := 'a0000000-0000-4000-8000-0000000000a4';
  CE_NC constant uuid := 'e0000000-0000-4000-8000-0000000000e1';
  CE_CV constant uuid := 'e0000000-0000-4000-8000-0000000000e2';
  CE_CA constant uuid := 'e0000000-0000-4000-8000-0000000000e3';
  CE_H  constant uuid := 'e0000000-0000-4000-8000-0000000000e4';
  C_NC constant uuid := 'd0000000-0000-4000-8000-0000000000d1';
  C_CV constant uuid := 'd0000000-0000-4000-8000-0000000000d2';
  L_CV constant uuid := 'c0000000-0000-4000-8000-0000000000c1';
  L_CA constant uuid := 'c0000000-0000-4000-8000-0000000000c2';
  L_AV constant uuid := 'c0000000-0000-4000-8000-0000000000c3';
  L_SE constant uuid := 'c0000000-0000-4000-8000-0000000000c4';
  CE_SE constant uuid := 'e0000000-0000-4000-8000-0000000000e5';
  CE_SI constant uuid := 'e0000000-0000-4000-8000-0000000000e6';
  CE_CO constant uuid := 'e0000000-0000-4000-8000-0000000000e7';
  CE_D constant uuid := 'e0000000-0000-4000-8000-0000000000e8';
  C_AC constant uuid := 'd0000000-0000-4000-8000-0000000000d3';
  C_MM constant uuid := 'd0000000-0000-4000-8000-0000000000d4';
  L_AC constant uuid := 'c0000000-0000-4000-8000-0000000000c5';
  ADM_IN constant uuid := 'a0000000-0000-4000-8000-0000000000a6';
  GER_IN constant uuid := 'a0000000-0000-4000-8000-0000000000a7';
  SUPER constant uuid := 'a0000000-0000-4000-8000-0000000000a8';
  v_n bigint;
  r jsonb; a crm.inversiones_eliminadas%rowtype; v_aporte numeric; v_anulado boolean;
  v_llave text;
begin
  -- 1. Quién puede: anon, sin sesión y vendedor NO.
  perform pg_temp.exigir(not has_function_privilege('anon', 'crm.eliminar_inversion_fn(uuid,text)', 'execute'), 'anon puede ejecutar la puerta');
  perform pg_temp.exigir(has_function_privilege('authenticated', 'crm.eliminar_inversion_fn(uuid,text)', 'execute'), 'authenticated no puede ejecutar la puerta');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(null, %L, %L)', CE_NC, 'Registro equivocado'), '42501', 'Inicia sesión');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', VEN, CE_NC, 'Registro equivocado'), '42501', 'Solo admin o gerencia');
  -- 2. Motivo obligatorio (5 a 300).
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_NC, '   '), '22023', 'motivo');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_NC, 'abcd'), '22023', 'motivo');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_NC, repeat('x', 301)), '22023', '300');
  -- 3. Fuente inexistente.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, gen_random_uuid(), 'Registro equivocado'), 'P0002');

  -- 4. Cooperativa SIN conversión: admin la elimina con su copia.
  r := pg_temp.eliminar(ADM, CE_NC, 'Registro equivocado de prueba');
  perform pg_temp.exigir(r ->> 'ok' = 'true' and r ->> 'empresa' = 'prodelco' and (r ->> 'conversion_anulada')::boolean = false, 'respuesta NC: ' || r::text);
  perform pg_temp.exigir(not exists (select 1 from crm.cierres_externos where id = CE_NC), 'NC: el cierre sigue');
  perform pg_temp.exigir(not exists (select 1 from crm.inversiones where id = 'f0000000-0000-4000-8000-0000000000f1'), 'NC: la inversión sigue');
  perform pg_temp.exigir(not exists (select 1 from crm.depositos_reclamados where cierre_id = CE_NC), 'NC: el depósito sigue');
  perform pg_temp.exigir(not exists (select 1 from crm.inversion_eventos where inversion_id = 'f0000000-0000-4000-8000-0000000000f1'), 'NC: el evento sigue');
  perform pg_temp.exigir(not exists (select 1 from crm.inversion_titulares where inversion_id = 'f0000000-0000-4000-8000-0000000000f1'), 'NC: el titular sigue');
  perform pg_temp.exigir((select estado = 'cancelada' and inversion_id is null from crm.inversion_solicitudes
    where id = '50000000-0000-4000-8000-0000000000f1'), 'NC: la solicitud de alta no quedó cancelada y conservada');
  select * into a from crm.inversiones_eliminadas where fuente_id = CE_NC;
  perform pg_temp.exigir(a.id::text = r ->> 'auditoria_id' and a.eliminado_por = ADM and a.rol_actor = 'admin'
    and a.motivo = 'Registro equivocado de prueba' and not a.es_conversion and not a.conversion_anulada
    and a.snapshot -> 'cierre' ->> 'numero_transaccion' = 'TX-NC' and jsonb_array_length(a.snapshot -> 'depositos') = 1
    and jsonb_array_length(a.snapshot -> 'eventos') = 1 and jsonb_array_length(a.snapshot -> 'titulares') = 1, 'NC: la copia no es completa');
  perform pg_temp.exigir((select count(*) from public.audit_log where tabla = 'crm.cierres_externos' and fila_id = CE_NC::text and operacion = 'DELETE' and usuario_id = ADM) = 1,
    'NC: el DELETE del cierre no quedó atribuido al actor en la bitácora');
  -- Repetir: ya no existe.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_NC, 'Registro equivocado'), 'P0002');

  -- 5. Con historia propia (retiro): no se elimina y nada cambia.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', GER, CE_H, 'Registro equivocado'), 'P0409', 'retiro');
  perform pg_temp.exigir(exists (select 1 from crm.cierres_externos where id = CE_H) and not exists (select 1 from crm.inversiones_eliminadas where fuente_id = CE_H),
    'H: se tocó una inversión con historia');

  -- 6. La válvula no se puede forzar: sin llave, con llave inventada o con la llave de OTRA copia.
  perform pg_temp.rechaza(format('delete from crm.cierres_externos where id = %L', CE_H), 'P0409', 'no se elimina');
  perform set_config('crm.inversion_eliminacion', gen_random_uuid()::text, true);
  perform pg_temp.como(ADM);
  perform pg_temp.rechaza(format('delete from crm.cierres_externos where id = %L', CE_H), 'P0409', 'no se elimina');
  select valvula::text into v_llave from crm.inversiones_eliminadas where fuente_id = CE_NC;
  perform set_config('crm.inversion_eliminacion', v_llave, true);
  perform pg_temp.como(ADM);
  perform pg_temp.rechaza(format('delete from crm.cierres_externos where id = %L', CE_H), 'P0409', 'no se elimina');
  perform pg_temp.como(ADM);
  perform pg_temp.rechaza(format('delete from crm.depositos_reclamados where cierre_id = %L', CE_H), 'P0409', 'no se edita ni se borra');
  perform pg_temp.como(ADM);
  perform pg_temp.rechaza('delete from crm.inversion_eventos where inversion_id = ''f0000000-0000-4000-8000-0000000000f4''', 'P0409', 'historial');
  perform pg_temp.rechaza(format('update crm.depositos_reclamados set numero_norm = ''X'' where cierre_id = %L', CE_H), 'P0409', 'no se edita ni se borra');
  perform set_config('crm.inversion_eliminacion', '', true);

  -- 7. Conversión de cooperativa SIN anular: admin no; gerencia la anula y la elimina, y NO resucita.
  select c.anulado, c.aporte_numerador into v_anulado, v_aporte
    from private.conversion_cierres('2026-08-01 00:00-05', '2026-09-01 00:00-05', null, true, null, null, array[L_CV]) c where c.lead_id = L_CV;
  perform pg_temp.exigir(v_anulado = false and v_aporte = 1, 'CV: antes de eliminar la conversión de agosto debe contar 1 (anulado=' || coalesce(v_anulado::text, 'null') || ', aporte=' || coalesce(v_aporte::text, 'null') || ')');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_CV, 'Registro equivocado'), '42501', 'solo gerencia');
  perform pg_temp.exigir(exists (select 1 from crm.cierres_externos where id = CE_CV and anulado_en is null), 'CV: el rechazo dejó algo a medias');
  r := pg_temp.eliminar(GER, CE_CV, 'Conversión registrada por error');
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean, 'CV: la respuesta no informa la anulación');
  perform pg_temp.exigir(not exists (select 1 from crm.cierres_externos where id = CE_CV), 'CV: el cierre sigue');
  select * into a from crm.inversiones_eliminadas where fuente_id = CE_CV;
  perform pg_temp.exigir(a.es_conversion and a.conversion_anulada and a.lead_id = L_CV and a.rol_actor = 'gerencia'
    and a.anulacion ->> 'ok' = 'true' and a.snapshot -> 'cierre' ->> 'anulado_en' is not null, 'CV: la copia no registra la anulación');
  perform pg_temp.exigir(private.cierre_anulado(L_CV) and private.cierre_externo_anulado(L_CV), 'CV: la anulación no sobrevivió a la eliminación');
  select c.anulado, c.aporte_numerador into v_anulado, v_aporte
    from private.conversion_cierres('2026-08-01 00:00-05', '2026-09-01 00:00-05', null, true, null, null, array[L_CV]) c where c.lead_id = L_CV;
  perform pg_temp.exigir(v_anulado and v_aporte = 0, 'CV: la conversión de agosto RESUCITÓ tras eliminar el cierre');

  -- 8. Conversión YA anulada: admin sí puede eliminarla (no mueve la conversión) y sigue anulada.
  r := pg_temp.eliminar(ADM, CE_CA, 'Limpieza de un cierre ya anulado');
  perform pg_temp.exigir(not (r ->> 'conversion_anulada')::boolean, 'CA: no debía volver a anular');
  select * into a from crm.inversiones_eliminadas where fuente_id = CE_CA;
  perform pg_temp.exigir(a.es_conversion and a.conversion_anulada and a.anulacion is null and a.lead_id = L_CA, 'CA: copia incorrecta');
  perform pg_temp.exigir(private.cierre_anulado(L_CA), 'CA: la anulación previa se perdió');
  perform pg_temp.exigir(jsonb_array_length(a.snapshot -> 'eventos') = 1, 'CA: faltan eventos en la copia');

  -- 9. Avance: gerencia SIN admin del portal no; admin sin gerencia elimina el contrato normal.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', GSO, C_NC, 'Registro equivocado'), '42501', 'admin del portal');
  r := pg_temp.eliminar(ADM, C_NC, 'Contrato registrado por error');
  perform pg_temp.exigir(r ->> 'empresa' = 'avance' and not exists (select 1 from public.contratos where id = C_NC)
    and not exists (select 1 from crm.inversiones where contrato_id = C_NC), 'AV: el contrato o su inversión siguen');
  select * into a from crm.inversiones_eliminadas where fuente_id = C_NC;
  perform pg_temp.exigir(a.fuente_tipo = 'contrato' and a.contrato_auditoria_id is not null and a.inversion_id = 'f0000000-0000-4000-8000-0000000000a1'
    and exists (select 1 from crm.contratos_eliminados_auditoria x where x.id = a.contrato_auditoria_id and x.contrato_id = C_NC and x.eliminado_por = ADM),
    'AV: la copia no enlaza la del contrato');

  -- 10. Avance conversión: admin no; gerencia (admin) la anula y la elimina.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, C_CV, 'Registro equivocado'), '42501', 'solo gerencia');
  r := pg_temp.eliminar(GER, C_CV, 'Conversión Avance registrada por error');
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean and not exists (select 1 from public.contratos where id = C_CV), 'AV-CV: no se anuló o no se eliminó');
  perform pg_temp.exigir(exists (select 1 from crm.cierres_avance_anulados where lead_id = L_AV) and private.cierre_anulado(L_AV), 'AV-CV: la anulación de Avance no quedó');
  select * into a from crm.inversiones_eliminadas where fuente_id = C_CV;
  perform pg_temp.exigir(a.es_conversion and a.conversion_anulada and a.lead_id = L_AV, 'AV-CV: copia incorrecta');

  -- 11. La copia es inmutable y nadie de la API la lee.
  perform pg_temp.rechaza(format('update crm.inversiones_eliminadas set motivo = ''otro motivo'' where fuente_id = %L', CE_NC), '42501', 'inmutable');
  perform pg_temp.rechaza(format('delete from crm.inversiones_eliminadas where fuente_id = %L', CE_NC), '42501', 'inmutable');
  perform pg_temp.exigir(not has_table_privilege('authenticated', 'crm.inversiones_eliminadas', 'select')
    and not has_table_privilege('service_role', 'crm.inversiones_eliminadas', 'select'), 'la copia es legible desde la API');

  -- 12. Los candados siguen cerrados para todo lo demás.
  perform pg_temp.exigir(exists (select 1 from crm.cierres_externos where id = CE_H), 'H: desapareció');
  perform pg_temp.rechaza(format('delete from crm.cierres_externos where id = %L', CE_H), 'P0409', 'no se elimina');


  -- 13. (r2) Conversión de SEPTIEMBRE (rama de acreditaciones), con la solicitud de alta enlazada a su lead: antes cuenta 1;
  --     gerencia la anula y la elimina; después no cuenta (anulada y fuente retirada), la solicitud queda cancelada y el hecho
  --     de la acreditación sigue registrado.
  select coalesce(sum(c.aporte_numerador), 0) into v_aporte
    from private.conversion_cierres('2026-09-01 00:00-05', '2026-10-01 00:00-05', null, true, null, null, array[L_SE]) c where c.lead_id = L_SE;
  perform pg_temp.exigir(v_aporte = 1, 'SE: antes de eliminar la conversión de septiembre debe contar 1 (aporte=' || v_aporte || ')');
  r := pg_temp.eliminar(GER, CE_SE, 'Conversión de septiembre registrada por error');
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean and not exists (select 1 from crm.cierres_externos where id = CE_SE), 'SE: no se anuló o no se eliminó');
  select coalesce(sum(c.aporte_numerador), 0) into v_aporte
    from private.conversion_cierres('2026-09-01 00:00-05', '2026-10-01 00:00-05', null, true, null, null, array[L_SE]) c where c.lead_id = L_SE;
  perform pg_temp.exigir(v_aporte = 0, 'SE: la conversión de septiembre sigue contando tras eliminarla (aporte=' || v_aporte || ')');
  perform pg_temp.exigir(private.cierre_anulado(L_SE), 'SE: la anulación no sobrevivió');
  perform pg_temp.exigir((select estado = 'cancelada' and inversion_id is null and lead_origen_id = L_SE from crm.inversion_solicitudes
    where id = '50000000-0000-4000-8000-0000000000f5'), 'SE: la solicitud con lead de origen no quedó cancelada y conservada');
  perform pg_temp.exigir(exists (select 1 from crm.conversion_acreditaciones where fuente_id = CE_SE), 'SE: se perdió el hecho de la acreditación');
  perform pg_temp.exigir(jsonb_array_length((select snapshot -> 'acreditaciones' from crm.inversiones_eliminadas where fuente_id = CE_SE)) = 1,
    'SE: la copia no guarda la acreditación');

  -- 14. (r2) Cierre SIN fila en crm.inversiones: también se elimina con su copia.
  r := pg_temp.eliminar(ADM, CE_SI, 'Cierre suelto registrado por error');
  select * into a from crm.inversiones_eliminadas where fuente_id = CE_SI;
  perform pg_temp.exigir(a.inversion_id is null and a.empresa = 'prodelco' and a.snapshot -> 'inversion' = 'null'::jsonb
    and jsonb_array_length(a.snapshot -> 'depositos') = 1 and not exists (select 1 from crm.cierres_externos where id = CE_SI), 'SI: copia o borrado incorrectos');

  -- 15. (r2) Una corrección previa es administrativa (no es historia D3): se elimina y la copia guarda los dos eventos.
  r := pg_temp.eliminar(ADM, CE_CO, 'Registro duplicado');
  perform pg_temp.exigir(jsonb_array_length((select snapshot -> 'eventos' from crm.inversiones_eliminadas where fuente_id = CE_CO)) = 2
    and not exists (select 1 from crm.inversion_eventos where inversion_id = 'f0000000-0000-4000-8000-0000000000f7'), 'CO: faltan eventos en la copia o siguen vivos');

  -- 16. (r2) El depósito de la inversión eliminada queda LIBRE para el registro correcto (decisión explícita; queda en la copia).
  insert into crm.depositos_reclamados (numero_norm, cierre_id, reclamado_por) values ('DEP-e1', CE_H, VEN);
  perform pg_temp.exigir((select count(*) from crm.depositos_reclamados where numero_norm = 'DEP-e1') = 1, 'el depósito liberado no se pudo volver a reclamar');

  -- 17. (r3, P4) Tras eliminar sus conversiones de cooperativa, los leads convertidos SIN perfil siguen siendo editables.
  update crm.leads set monto_estimado = monto_estimado + 1 where id in (L_CV, L_CA, L_SE);
  get diagnostics v_n = row_count;
  perform pg_temp.exigir(v_n = 3, 'P4: los leads convertidos quedaron sin poder editarse (' || v_n || ')');

  -- 18. (r3) Válvula, cada cláusula por separado, con una copia FALSA idéntica a la fila viva: control positivo (misma
  --     transacción y mismo actor → abre), otra transacción → no abre, otro actor → no abre. Cada intento se deshace.
  for v_llave in select unnest(array['positivo', 'otra_transaccion', 'otro_actor']) loop
    begin
      insert into crm.inversiones_eliminadas (fuente_tipo, fuente_id, empresa, es_conversion, conversion_anulada, motivo, eliminado_por,
          rol_actor, snapshot, valvula, transaccion)
        values ('cierre_externo', CE_H, 'prodelco', false, false, 'Copia falsa de la prueba de la válvula',
          case when v_llave = 'otro_actor' then GER else ADM end, 'admin',
          jsonb_build_object('cierre', (select to_jsonb(c) from crm.cierres_externos c where c.id = CE_H),
            'depositos', (select jsonb_agg(to_jsonb(d)) from crm.depositos_reclamados d where d.cierre_id = CE_H), 'eventos', '[]'::jsonb),
          'aaaaaaaa-0000-4000-8000-000000000001', case when v_llave = 'otra_transaccion' then '1'::xid8 else pg_current_xact_id() end);
      perform set_config('crm.inversion_eliminacion', 'aaaaaaaa-0000-4000-8000-000000000001', true);
      perform pg_temp.como(ADM);
      if v_llave = 'positivo' then
        delete from crm.depositos_reclamados where cierre_id = CE_H;   -- (el bloque 16 le dio un segundo depósito)
        get diagnostics v_n = row_count;
        perform pg_temp.exigir(v_n > 0 and not exists (select 1 from crm.depositos_reclamados where cierre_id = CE_H),
          'válvula: el control positivo no abrió (la prueba no distinguiría)');
      else
        perform pg_temp.rechaza(format('delete from crm.depositos_reclamados where cierre_id = %L', CE_H), 'P0409', 'no se edita ni se borra');
      end if;
      raise exception 'DESHACER_VALVULA';
    exception when others then
      if sqlerrm <> 'DESHACER_VALVULA' then raise; end if;
    end;
  end loop;
  perform set_config('crm.inversion_eliminacion', '', true);
  perform pg_temp.como(null);

  -- 19. (r3) Censo de dependencias: si aparece una tabla nueva que apunta a las inversiones, el borrado se niega (y se deshace).
  begin
    create table crm.prueba_dependencia_nueva (id uuid primary key, inversion_id uuid references crm.inversiones (id));
    perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, CE_D, 'Registro equivocado'), '55000', 'dependencias nuevas');
    raise exception 'DESHACER_DEPENDENCIA';
  exception when others then
    if sqlerrm <> 'DESHACER_DEPENDENCIA' then raise; end if;
  end;

  -- 20. (r3) Actores: admin inactivo y gerencia con la membresía inactiva NO; superadmin sin gerencia SÍ (y queda como tal).
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM_IN, CE_D, 'Registro equivocado'), '42501', 'Solo admin o gerencia');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', GER_IN, CE_D, 'Registro equivocado'), '42501', 'Solo admin o gerencia');
  r := pg_temp.eliminar(SUPER, CE_D, 'Registro equivocado por superadmin');
  perform pg_temp.exigir((select rol_actor = 'superadmin' and eliminado_por = SUPER from crm.inversiones_eliminadas where fuente_id = CE_D),
    'superadmin: no quedó registrado como tal');

  -- 21. (r3, P2) Avance cuya conversión la decide la ACREDITACIÓN (el lead no enlaza el contrato): admin NO; gerencia la anula y
  --     la elimina; la conversión de septiembre deja de contar.
  select coalesce(sum(c.aporte_numerador), 0) into v_aporte
    from private.conversion_cierres('2026-09-01 00:00-05', '2026-10-01 00:00-05', null, true, null, null, array[L_AC]) c where c.lead_id = L_AC;
  perform pg_temp.exigir(v_aporte = 1, 'AC: antes de eliminar, la conversión acreditada al contrato debe contar 1 (aporte=' || v_aporte || ')');
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', ADM, C_AC, 'Registro equivocado'), '42501', 'solo gerencia');
  r := pg_temp.eliminar(GER, C_AC, 'Contrato acreditado registrado por error');
  perform pg_temp.exigir((r ->> 'conversion_anulada')::boolean and not exists (select 1 from public.contratos where id = C_AC)
    and private.cierre_anulado(L_AC), 'AC: no se anuló o no se eliminó');
  select coalesce(sum(c.aporte_numerador), 0) into v_aporte
    from private.conversion_cierres('2026-09-01 00:00-05', '2026-10-01 00:00-05', null, true, null, null, array[L_AC]) c where c.lead_id = L_AC;
  perform pg_temp.exigir(v_aporte = 0, 'AC: la conversión acreditada sigue contando (aporte=' || v_aporte || ')');
  perform pg_temp.exigir((select lead_id = L_AC and es_conversion and conversion_anulada and rol_actor = 'gerencia'
    from crm.inversiones_eliminadas where fuente_id = C_AC), 'AC: copia incorrecta');

  -- 22. (r3, P2) Acreditación de un lead y enlace de OTRO sobre el mismo contrato: no se decide aquí (P0409) y nada cambia.
  perform pg_temp.rechaza(format('select pg_temp.eliminar(%L, %L, %L)', GER, C_MM, 'Registro equivocado'), 'P0409', 'no coincide');
  perform pg_temp.exigir(exists (select 1 from public.contratos where id = C_MM), 'MM: se tocó el contrato en discrepancia');
  raise notice 'PASS eliminar_inversion: 22 bloques (roles, motivo, NC, historia, válvula y sus cláusulas, conversión coop que no resucita, ya anulada, Avance, Avance conversión y por acreditación, discrepancia, inmutabilidad, septiembre, sin inversión, corrección, depósito liberado, P4, censo de dependencias, actores)';
end
$pruebas$;

select 'PASS eliminar_inversion (22 bloques); se revierte';
rollback;
