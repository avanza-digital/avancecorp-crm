-- mundo.sql — Mundo SINTÉTICO del banco de «categoría por operación», en el ESTADO DE PRODUCCIÓN del 08/10/2026.
-- SOLO banco local de Docker (se niega en otro sitio). Sin datos personales: nombres, documentos y correos inventados.
--
-- Se corre UNA vez, con la migración 20261009120000 SIN aplicar (o revertida con reversa.sql): las operaciones de cartera
-- se insertan «como el backfill B del 23/09», sobre contratos que ya existían y sin tocar el contrato, que es justo como
-- quedaron los 12 de producción. Después se aplica la migración.
--
-- QUÉ CREA
--   · Personas: gerencia «MIGUEL BANCO» (portal admin + equipo gerencia) y el perfil de PRUEBAS d731f284 con el MISMO
--     nombre (vendedor), como en producción; supervisor, seis analistas (uno supervisor, como 001401), coordinador,
--     directorio, una gerencia con la membresía revocada y un admin del portal sin equipo.
--   · Los 12 de producción con su número, moneda, capital, tasa y día comercial (R1 de medir-categoria.json): 'nuevo',
--     producto legacy, PDF sellado (9) o pendiente sin archivo (3), y su operación upgrade creada DESPUÉS
--     (fuente flujo_cartera; la de 001408 no elegible: su cliente tiene el primer contrato en septiembre).
--     Cada cliente tiene un contrato anterior (junio), salvo 001408 (su primero es de septiembre).
--   · Contratos de prueba K1–K11 para la suite (prueba.sql): ver la tabla al final.
--   · Agosto SELLADO (fila en crm.periodos_cerrados), septiembre abierto, y la política de rentabilidad con los
--     parámetros de la v18 de producción (observación, base 15, tope técnico 25).
begin;
do $guardia$
begin
  if coalesce(current_setting('app.settings.jwt_secret', true), '') <> 'super-secret-jwt-token-with-at-least-32-characters-long'
     or inet_server_addr() is null then
    raise exception 'mundo.sql solo corre en un banco LOCAL de Docker';
  end if;
  if exists (select 1 from public.perfiles where id = 'ca7e0000-0000-4000-8000-000000000001') then
    raise exception 'mundo.sql: el mundo ya existe en este banco';
  end if;
  if to_regprocedure('private.trg_operacion_cartera_fija_categoria()') is not null then
    raise exception 'mundo.sql: la migración 20261009120000 está aplicada; revertirla antes (reversa.sql) para crear el estado de producción';
  end if;
end $guardia$;
-- Tope técnico 50 SOLO mientras nacen los contratos (001362 tiene tasa 32,4: nació cuando el tope lo permitía).
insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota)
select p.version + 1, p.id, now(), 15, 50, 1, 'observacion', 'banco categoria: tope 50 mientras nacen los contratos del mundo'
  from crm.politica_rentabilidad p order by p.version desc limit 1;
commit;

begin;
set local session_replication_role = replica;   -- personas: sin las validaciones de jerarquía (fixture fuera de banda)
insert into auth.users (id, email, aud, role)
select v.id, v.correo, 'authenticated', 'authenticated'
  from (values
    ('ca7e0000-0000-4000-8000-000000000001'::uuid, 'gerencia.banco@categoria.test'),
    ('d731f284-eeaa-4c27-b71f-ac4f1d8e96c2'::uuid, 'pruebas.banco@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000002'::uuid, 'supervisor.banco@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000003'::uuid, 'analista1@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000004'::uuid, 'analista2@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000005'::uuid, 'analista3@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000006'::uuid, 'analista4@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000007'::uuid, 'analista5@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000008'::uuid, 'analista6@categoria.test'),
    ('ca7e0000-0000-4000-8000-000000000009'::uuid, 'coordinador@categoria.test'),
    ('ca7e0000-0000-4000-8000-00000000000a'::uuid, 'gerencia.revocada@categoria.test'),
    ('ca7e0000-0000-4000-8000-00000000000b'::uuid, 'admin.portal@categoria.test'),
    ('ca7e0000-0000-4000-8000-00000000000c'::uuid, 'directorio@categoria.test')
  ) as v(id, correo);
insert into public.perfiles (id, nombre_completo, correo, rol, activo)
values
  ('ca7e0000-0000-4000-8000-000000000001', 'MIGUEL BANCO', 'gerencia.banco@categoria.test', 'admin', true),
  ('d731f284-eeaa-4c27-b71f-ac4f1d8e96c2', 'MIGUEL BANCO', 'pruebas.banco@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000002', 'SUPERVISOR BANCO', 'supervisor.banco@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000003', 'ANALISTA UNO', 'analista1@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000004', 'ANALISTA DOS', 'analista2@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000005', 'ANALISTA TRES', 'analista3@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000006', 'ANALISTA CUATRO', 'analista4@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000007', 'ANALISTA CINCO', 'analista5@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000008', 'ANALISTA SEIS', 'analista6@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-000000000009', 'COORDINADOR BANCO', 'coordinador@categoria.test', 'comercial', true),
  ('ca7e0000-0000-4000-8000-00000000000a', 'GERENCIA REVOCADA BANCO', 'gerencia.revocada@categoria.test', 'admin', true),
  ('ca7e0000-0000-4000-8000-00000000000b', 'ADMIN PORTAL BANCO', 'admin.portal@categoria.test', 'admin', true),
  ('ca7e0000-0000-4000-8000-00000000000c', 'DIRECTORIO BANCO', 'directorio@categoria.test', 'directorio', true);
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
values
  ('ca7e0000-0000-4000-8000-000000000001', 'gerencia', null, true),
  ('d731f284-eeaa-4c27-b71f-ac4f1d8e96c2', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000002', 'supervisor', null, true),
  ('ca7e0000-0000-4000-8000-000000000003', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000004', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000005', 'supervisor', null, true),
  ('ca7e0000-0000-4000-8000-000000000006', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000007', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000008', 'vendedor', 'ca7e0000-0000-4000-8000-000000000002', true),
  ('ca7e0000-0000-4000-8000-000000000009', 'coordinador', null, true),
  ('ca7e0000-0000-4000-8000-00000000000a', 'gerencia', null, false),
  ('ca7e0000-0000-4000-8000-00000000000c', 'directorio', null, true);
-- Clientes: uno por cada contrato de los 12 (los tres de 001439/40/41 comparten cliente) y once para K1–K11.
insert into auth.users (id, email, aud, role)
select ('ca7e0000-0000-4000-8000-0000000001' || lpad(to_hex(g), 2, '0'))::uuid, 'cliente' || g || '@categoria.test', 'authenticated', 'authenticated'
  from generate_series(1, 21) g;
insert into public.perfiles (id, nombre_completo, dni, tipo_documento, correo, rol, activo, asesor_perfil_id)
select ('ca7e0000-0000-4000-8000-0000000001' || lpad(to_hex(g), 2, '0'))::uuid,
       'CLIENTE CATEGORIA ' || lpad(g::text, 2, '0'), (71000000 + g)::text, 'DNI',
       'cliente' || g || '@categoria.test', 'cliente', true,
       case when g <= 10 then (array['ca7e0000-0000-4000-8000-000000000003', 'ca7e0000-0000-4000-8000-000000000004',
                                     'ca7e0000-0000-4000-8000-000000000005', 'ca7e0000-0000-4000-8000-000000000006',
                                     'ca7e0000-0000-4000-8000-000000000007', 'ca7e0000-0000-4000-8000-000000000007',
                                     'ca7e0000-0000-4000-8000-000000000004', 'ca7e0000-0000-4000-8000-000000000006',
                                     'ca7e0000-0000-4000-8000-000000000006', 'ca7e0000-0000-4000-8000-000000000008'])[g]::uuid
            else 'ca7e0000-0000-4000-8000-000000000003'::uuid end
  from generate_series(1, 21) g;
commit;

-- Los contratos nacen por la vía normal (triggers encendidos): producto legacy, período comercial, auditoría y libro de
-- rentabilidad, como en producción.
begin;
do $contratos$
declare
  r record;
  v_id uuid;
begin
  -- Contrato anterior de cada cliente (junio; el de 001408 en septiembre, antes de él).
  for r in select * from (values
    -- cliente, numero, fecha, moneda, capital, analista
    (1,  'CAT-PREVIO-01', date '2026-06-05', 'PEN', 20000::numeric, 3),
    (2,  'CAT-PREVIO-02', date '2026-06-06', 'PEN', 20000, 4),
    (3,  'CAT-PREVIO-03', date '2026-06-07', 'PEN', 20000, 5),
    (4,  'CAT-PREVIO-04', date '2026-06-08', 'PEN', 20000, 6),
    (5,  'CAT-PREVIO-05', date '2026-09-05', 'USD', 2000, 7),
    (6,  'CAT-PREVIO-06', date '2026-06-10', 'USD', 2000, 7),
    (7,  'CAT-PREVIO-07', date '2026-06-11', 'USD', 2000, 4),
    (8,  'CAT-PREVIO-08', date '2026-06-12', 'PEN', 20000, 6),
    (9,  'CAT-PREVIO-09', date '2026-06-13', 'PEN', 20000, 6),
    (10, 'CAT-PREVIO-10', date '2026-06-14', 'PEN', 20000, 8),
    (11, 'CAT-PREVIO-K1', date '2026-06-15', 'PEN', 20000, 3),
    (12, 'CAT-PREVIO-K2', date '2026-06-16', 'USD', 2000, 3),
    (13, 'CAT-PREVIO-K3', date '2026-06-17', 'PEN', 20000, 3),
    (14, 'CAT-PREVIO-K4', date '2026-06-18', 'PEN', 20000, 3),
    (15, 'CAT-PREVIO-K5', date '2026-06-19', 'PEN', 20000, 3),
    (16, 'CAT-PREVIO-K6', date '2026-06-20', 'PEN', 20000, 3),
    (17, 'CAT-PREVIO-K7', date '2026-06-21', 'PEN', 20000, 3),
    (18, 'CAT-PREVIO-K8', date '2026-06-22', 'PEN', 20000, 3),
    (19, 'CAT-PREVIO-K9', date '2026-06-23', 'PEN', 20000, 3),
    (20, 'CAT-ORIGEN-K10', date '2026-06-24', 'PEN', 30000, 3),
    (21, 'CAT-ORIGEN-K11', date '2025-10-05', 'PEN', 30000, 3)
  ) as v(cliente, numero, fecha, moneda, capital, analista) loop
    v_id := ('ca7e0000-0000-4000-8000-0000000011' || lpad(to_hex(r.cliente), 2, '0'))::uuid;
    insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                                  fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
    values (v_id, r.numero, ('ca7e0000-0000-4000-8000-0000000001' || lpad(to_hex(r.cliente), 2, '0'))::uuid,
            r.capital, r.moneda, 15, 'mensual', 'simple', r.fecha, (r.fecha + interval '12 months')::date,
            'activo', 'nuevo', 'ca7e0000-0000-4000-8000-00000000000b',
            ('ca7e0000-0000-4000-8000-0000000000' || lpad(to_hex(r.analista), 2, '0'))::uuid);
  end loop;

  -- Los 12 de producción (R1): número, día comercial, moneda, capital, tasa y analista.
  for r in select * from (values
    (1,  '2026-01-001362', date '2026-09-02', 'PEN', 577554::numeric, 32.4::numeric, 1, 3),
    (2,  '2026-01-001369', date '2026-09-03', 'PEN', 100000, 18, 2, 4),
    (3,  '2026-01-001401', date '2026-09-08', 'PEN', 1116900, 24, 3, 5),
    (4,  '2026-01-001400', date '2026-09-09', 'PEN', 120000, 18, 4, 6),
    (5,  '2026-01-001408', date '2026-09-09', 'USD', 3100, 10, 5, 7),
    (6,  '2026-01-001439', date '2026-09-12', 'USD', 25000, 16, 6, 7),
    (7,  '2026-01-001440', date '2026-09-12', 'USD', 25471, 16, 6, 7),
    (8,  '2026-01-001441', date '2026-09-13', 'PEN', 97800, 17, 6, 7),
    (9,  '2026-01-001424', date '2026-09-14', 'USD', 1400, 17, 7, 4),
    (10, '2026-01-001425', date '2026-09-14', 'PEN', 10000, 19, 8, 6),
    (11, '2026-01-001445', date '2026-09-16', 'PEN', 20000, 16, 9, 6),
    (12, '2026-01-001447', date '2026-09-17', 'PEN', 50000, 17, 10, 8)
  ) as v(n, numero, fecha, moneda, capital, tasa, cliente, analista) loop
    insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                                  fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
    values (('ca7e0000-0000-4000-8000-0000000012' || lpad(to_hex(r.n), 2, '0'))::uuid, r.numero,
            ('ca7e0000-0000-4000-8000-0000000001' || lpad(to_hex(r.cliente), 2, '0'))::uuid,
            r.capital, r.moneda, r.tasa, 'mensual', 'simple', r.fecha, (r.fecha + interval '12 months')::date,
            'activo', 'nuevo', ('ca7e0000-0000-4000-8000-0000000000' || lpad(to_hex(r.analista), 2, '0'))::uuid,
            ('ca7e0000-0000-4000-8000-0000000000' || lpad(to_hex(r.analista), 2, '0'))::uuid);
  end loop;

  -- K1–K11 (clientes 11–21), para la suite.
  for r in select * from (values
    (1,  'CAT-K1',  date '2026-09-10', 'PEN', 100000::numeric, 18::numeric, 11, 'nuevo'),
    (2,  'CAT-K2',  date '2026-09-12', 'USD', 25000, 16, 12, 'nuevo'),
    (3,  'CAT-K3',  date '2026-08-10', 'PEN', 50000, 17, 13, 'nuevo'),
    (4,  'CAT-K4',  date '2026-09-15', 'PEN', 40000, 16, 14, 'nuevo'),
    (5,  'CAT-K5',  date '2026-09-16', 'PEN', 45000, 16, 15, 'upgrade'),
    (6,  'CAT-K6',  date '2026-09-17', 'PEN', 46000, 16, 16, 'nuevo'),
    (7,  'CAT-K7',  date '2026-09-18', 'PEN', 47000, 16, 17, 'nuevo'),
    (8,  'CAT-K8',  date '2026-08-12', 'PEN', 48000, 16, 18, 'nuevo'),
    (9,  'CAT-K9',  date '2026-09-19', 'PEN', 49000, 16, 19, 'nuevo'),
    (10, 'CAT-K10', date '2026-09-20', 'PEN', 35000, 16, 20, 'nuevo')
  ) as v(k, numero, fecha, moneda, capital, tasa, cliente, categoria) loop
    insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
                                  fecha_inicio, fecha_vencimiento, estado, categoria, creado_por, analista_cierre_id)
    values (('ca7e0000-0000-4000-8000-0000000020' || lpad(to_hex(r.k), 2, '0'))::uuid, r.numero,
            ('ca7e0000-0000-4000-8000-0000000001' || lpad(to_hex(r.cliente), 2, '0'))::uuid,
            r.capital, r.moneda, r.tasa, 'mensual', 'simple', r.fecha, (r.fecha + interval '12 months')::date,
            'activo', r.categoria, 'ca7e0000-0000-4000-8000-000000000003', 'ca7e0000-0000-4000-8000-000000000003');
  end loop;

  -- K5 es un upgrade COHERENTE (como lo deja public.crear_contrato): su operación nace en la misma transacción.
  insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id, fecha_operacion,
                                       periodo, moneda, capital_renovado, capital_adicional, elegible_conversion,
                                       desglose_completo, fuente, creado_por)
  select c.cliente_id, 'ca7e0000-0000-4000-8000-000000000003', 'upgrade', null, c.id, c.fecha_cierre_comercial,
         date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, null, null, true, true, 'flujo_cartera',
         'ca7e0000-0000-4000-8000-00000000000b'
    from public.contratos c where c.id = 'ca7e0000-0000-4000-8000-000000002005';
end $contratos$;
commit;

-- K6: un upgrade ANTIGUO sin operación (como los ~106 de marzo a julio): nace 'nuevo' y se corrige después.
begin;
update public.contratos set categoria = 'upgrade' where id = 'ca7e0000-0000-4000-8000-000000002006';
commit;

-- PDF: sellado con su archivo (9 de los 12, K1, K3, K7) o pendiente sin archivo (001439, 001440, 001441 y K2).
begin;
set local session_replication_role = replica;   -- los PDF nacen por su Edge; aquí solo su foto
insert into private.contrato_pdf_jobs (id, contrato_id, estado, storage_path, nombre_archivo, template_version, snapshot,
                                       sha256, bytes, solicitado_por, subido_en, sellado_en, revision)
select j.id, c.id,
       case when j.sellado then 'sellado' else 'pendiente' end,
       c.id::text || '/v2/' || j.id::text || '/contrato.pdf', 'contrato-' || c.numero_contrato || '.pdf', 'contrato-aep-17-v9',
       jsonb_build_object('categoria', c.categoria, 'numero', c.numero_contrato),
       case when j.sellado then md5(c.id::text) || md5(c.numero_contrato) end,
       case when j.sellado then 123456 end,
       'ca7e0000-0000-4000-8000-00000000000b',
       case when j.sellado then now() end, case when j.sellado then now() end, 1
  from (select c.id as contrato_id, gen_random_uuid() as id,
               c.numero_contrato not in ('2026-01-001439', '2026-01-001440', '2026-01-001441', 'CAT-K2') as sellado
          from public.contratos c
         where c.id::text like 'ca7e0000-0000-4000-8000-0000000012%'
            or c.numero_contrato in ('CAT-K1', 'CAT-K2', 'CAT-K3', 'CAT-K7')) j
  join public.contratos c on c.id = j.contrato_id;
insert into private.contrato_pdfs (contrato_id, job_id, storage_path, nombre_archivo, sha256, bytes, template_version, snapshot,
                                   generado_por, revision)
select j.contrato_id, j.id, j.storage_path, j.nombre_archivo, j.sha256, j.bytes, j.template_version, j.snapshot,
       j.solicitado_por, 1
  from private.contrato_pdf_jobs j
  join public.contratos c on c.id = j.contrato_id
 where j.estado = 'sellado'
   and (c.id::text like 'ca7e0000-0000-4000-8000-0000000012%' or c.numero_contrato in ('CAT-K1', 'CAT-K3', 'CAT-K7'));
-- K9 está en proceso de eliminación.
insert into private.contrato_eliminaciones (contrato_id, token, solicitado_por, objetos)
values ('ca7e0000-0000-4000-8000-000000002009', gen_random_uuid(), 'ca7e0000-0000-4000-8000-000000000001', '[]'::jsonb);
commit;

-- Las operaciones upgrade de los 12, de K1, K2, K3 y K9 llegan DESPUÉS y «sin tocar contratos» (molde del backfill B).
begin;
insert into crm.operaciones_cartera (cliente_id, vendedor_id, tipo, contrato_origen_id, contrato_nuevo_id, fecha_operacion,
                                     periodo, moneda, capital_renovado, capital_adicional, elegible_conversion,
                                     desglose_completo, fuente, creado_por)
select c.cliente_id, c.analista_cierre_id, 'upgrade', null, c.id, c.fecha_cierre_comercial,
       date_trunc('month', c.fecha_cierre_comercial)::date, c.moneda, null, null,
       date_trunc('month', c.fecha_cierre_comercial)::date >
         (select min(date_trunc('month', c2.fecha_cierre_comercial)::date) from public.contratos c2 where c2.cliente_id = c.cliente_id),
       true, 'flujo_cartera', 'ca7e0000-0000-4000-8000-00000000000b'
  from public.contratos c
 where c.id::text like 'ca7e0000-0000-4000-8000-0000000012%'
    or c.id in ('ca7e0000-0000-4000-8000-000000002001', 'ca7e0000-0000-4000-8000-000000002002',
                'ca7e0000-0000-4000-8000-000000002003', 'ca7e0000-0000-4000-8000-000000002009')
 order by c.fecha_cierre_comercial, c.numero_contrato;
commit;

-- Agosto SELLADO (fila de foto mínima; sin las cifras del sello), septiembre abierto.
begin;
set local session_replication_role = replica;
insert into crm.periodos_cerrados (periodo, automatico, cerrado_por, ponderacion_referido, meta_revision, cobertura, ponderacion_renovacion)
values (date '2026-08-01', true, null, 0.15, 1, '{"banco": "categoria"}'::jsonb, 0.15)
on conflict (periodo) do nothing;
commit;

-- Política con los parámetros de la v18 de producción (observación, base 15, tope 25).
begin;
insert into crm.politica_rentabilidad (version, version_anterior_id, vigente_desde, tasa_base_nueva, tope_tecnico, vigencia_solicitud_dias, modo, nota)
select p.version + 1, p.id, now(), 15, 25, 1, 'observacion', 'banco categoria: parámetros de la v18 de producción'
  from crm.politica_rentabilidad p order by p.version desc limit 1;
commit;

select 'MUNDO CATEGORIA' as mundo,
       (select count(*) from public.contratos c join crm.operaciones_cartera o on o.contrato_nuevo_id = c.id
         where c.categoria = 'nuevo' and o.tipo = 'upgrade') as incoherentes,
       (select count(*) from public.contratos c where c.numero_contrato like '2026-01-001%') as los_12,
       (select count(*) from private.contrato_pdf_jobs j join public.contratos c on c.id = j.contrato_id
         where c.id::text like 'ca7e0000-0000-4000-8000-0000000012%') as pdf_de_los_12,
       (select string_agg(pc.periodo::text, ',') from crm.periodos_cerrados pc) as sellados;
-- K1  sept., 'nuevo' + op upgrade, PDF sellado       → la puerta (éxito, auditoría, PDF, GUC, idempotencia, observación)
-- K2  sept., 'nuevo' + op upgrade, PDF pendiente     → la puerta bajo enforcement y con una declaración de origen colgada
-- K3  agosto (sellado), 'nuevo' + op upgrade          → P0409
-- K4  sept., 'nuevo' sin operación                    → respaldo 23514 ('upgrade'); también cliente del alta de upgrade
-- K5  sept., 'upgrade' + op upgrade (coherente)       → «Corregir» a 'nuevo' → 23514; notas → pasa
-- K6  sept., 'upgrade' SIN operación (antiguo)        → sin restricción; la puerta lo deja en 'nuevo'
-- K7  sept., 'nuevo' sin operación, PDF sellado       → sincronización al insertar la operación
-- K8  agosto (sellado), 'nuevo' sin operación         → sincronización rechazada (P0409)
-- K9  sept., 'nuevo' + op upgrade, en eliminación     → 55000
-- K10 sept., 'nuevo' sin operación; origen CAT-ORIGEN-K10 → sincronización con una renovación
-- CAT-ORIGEN-K11 (cliente 21, vence 2026-10-05)       → alta real de una renovación con public.crear_contrato
