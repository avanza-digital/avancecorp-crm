-- SIEMBRA FICTICIA de 20261001233019_crm_cuentas_pago_motivo_y_rezago — SOLO BANCO Docker propio.
-- ⚠️ Jamás contra producción: escribe y CONFIRMA personas, cuentas, contratos y cuotas inventados.
-- Idempotente: todo entra con «on conflict do nothing»; repetirla no crea ni cambia nada. NO
-- repone el mundo si una prueba dejó restos (eso lo hace ciclo.sh con su limpieza y la reversa).
-- Se lanza como postgres, en un solo mensaje:
--   docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U postgres -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -qAt < siembra.sql
--
-- EL MUNDO (15 contratos activos, 3 cuotas pendientes cada uno, más UNA cuota que REZAGO-04 ya
-- tenía pagada antes de tener vínculo; todo con identificadores fijos):
--   personas  c9e00000-…-NN   cuentas  c9ec0000-…-NN   contratos  c9ed0000-…-NN (REZAGO-NN)
--   vínculos  c9ef0000-…-NN   cuotas   c9ee0000-…-NNCC (contrato NN, cuota CC)
--
--   NN  contrato   moneda  cliente  caso sembrado            qué tiene el cliente
--   01  REZAGO-01  PEN     A        ok                       vínculo → su cuenta PEN activa
--   02  REZAGO-02  PEN     B        ok                       vínculo → su cuenta PEN, DESACTIVADA después
--                                                            de vincular (+ otra PEN activa, sin vincular)
--   03  REZAGO-03  PEN     C        una_cuenta               1 PEN activa + 1 PEN inactiva (más nueva) + 1 USD activa
--   04  REZAGO-04  USD     D        una_cuenta               1 USD activa + 1 PEN activa (como el caso real);
--                                                            además su cuota 0 ya estaba PAGADA, sin sello
--   05  REZAGO-05  PEN     E        una_cuenta               1 PEN activa (la misma para los dos contratos)
--   06  REZAGO-06  PEN     E        una_cuenta               »
--   07  REZAGO-07  PEN     F        varias_cuentas           2 PEN activas (una a nombre de un tercero)
--   08  REZAGO-08  USD     G        varias_cuentas           3 USD activas + 1 PEN activa
--   09  REZAGO-09  USD     H        otra_moneda              solo 1 PEN activa
--   10  REZAGO-10  PEN     I        otra_moneda              solo 2 USD activas
--   11  REZAGO-11  USD     J        sin_cuenta               ninguna cuenta
--   12  REZAGO-12  PEN     K        sin_cuenta               solo 1 PEN INACTIVA (no se vincula nunca)
--   13  REZAGO-13  PEN     L        sin_cuenta  (es_demo)    ninguna cuenta; contrato marcado de prueba
--   14  REZAGO-14  PEN     M        cuenta_no_corresponde    vínculo → cuenta PEN de OTRO cliente (H); M tiene 1 PEN activa propia
--   15  REZAGO-15  PEN     N        cuenta_no_corresponde    vínculo → su cuenta USD (otra moneda); no tiene PEN
--
--   Personas: 01 admin (gestor) · 02 operaciones (gestor) · 03 admin con la membresía CRM REVOCADA
--   (crm.equipo.activo = false; así lo lee private.membresia_crm_revocada) · 04 analista (asesor
--   de todos los clientes) · 11..24 clientes A..N. El «cliente» de las pruebas es C (13).
--
-- TRES ATAJOS, los tres dentro de esta transacción y con el disparador repuesto antes de confirmar:
--   · public.contratos: se apagan sus disparadores de usuario SOLO mientras entran los contratos
--     (igual que supabase/scripts/cuentas-gloria/test-*.sql): el alta real exige operación de
--     cartera, lead, producto publicado…, y no deja nacer un contrato con es_demo = true.
--   · crm.contrato_cuentas_pago: el estado «cuenta_no_corresponde» no se puede fabricar por la vía
--     normal (private.trg_contrato_cuenta_pago_coherente lo impide, con razón). Se apaga ESE
--     disparador solo para insertar los dos vínculos incoherentes (14 y 15) y se vuelve a encender.
--   · public.cronograma_pagos: la cuota 0 de REZAGO-04 se pagó «antes del bloqueo», como las cuotas
--     viejas de producción: está pagada y NO tiene sello en crm.cuotas_cuenta_pagada. Hoy el
--     bloqueo no deja insertarla (el contrato no tiene vínculo): se apagan los disparadores de
--     usuario de esa tabla SOLO para esa fila (igual que cuentas-gloria/test-pago-declara-cuenta.sql).
--   El bloque final comprueba que no quedó ningún disparador apagado.
begin;
set local lock_timeout = '5s';

-- ── Personas ─────────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, aud, role)
select ('c9e00000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'rezago.persona' || lpad(n::text, 2, '0') || '@prueba.invalid', 'authenticated', 'authenticated'
from unnest(array[1, 2, 3, 4, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]) as t(n)
on conflict (id) do nothing;

-- Primero el personal (el analista tiene que existir antes de ser asesor de un cliente).
insert into public.perfiles (id, nombre_completo, dni, correo, rol, activo) values
  ('c9e00000-0000-4000-8000-000000000001', 'GESTORA FICTICIA ADMIN',       '77790001', 'rezago.persona01@prueba.invalid', 'admin',       true),
  ('c9e00000-0000-4000-8000-000000000002', 'GESTOR FICTICIO OPERACIONES',  '77790002', 'rezago.persona02@prueba.invalid', 'operaciones', true),
  ('c9e00000-0000-4000-8000-000000000003', 'GESTORA FICTICIA REVOCADA',    '77790003', 'rezago.persona03@prueba.invalid', 'admin',       true),
  ('c9e00000-0000-4000-8000-000000000004', 'ANALISTA FICTICIO DEL REZAGO', '77790004', 'rezago.persona04@prueba.invalid', 'analista',    true)
on conflict (id) do nothing;

-- La revocación (P04): fila en crm.equipo con activo = false. Sigue siendo admin activo del portal.
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('c9e00000-0000-4000-8000-000000000003', 'gerencia', false)
on conflict (perfil_id) do nothing;

insert into public.perfiles (id, nombre_completo, dni, correo, rol, activo, asesor_perfil_id) values
  ('c9e00000-0000-4000-8000-000000000011', 'CLIENTE FICTICIO A', '77791011', 'rezago.persona11@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000012', 'CLIENTE FICTICIO B', '77791012', 'rezago.persona12@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000013', 'CLIENTE FICTICIO C', '77791013', 'rezago.persona13@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000014', 'CLIENTE FICTICIO D', '77791014', 'rezago.persona14@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000015', 'CLIENTE FICTICIO E', '77791015', 'rezago.persona15@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000016', 'CLIENTE FICTICIO F', '77791016', 'rezago.persona16@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000017', 'CLIENTE FICTICIO G', '77791017', 'rezago.persona17@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000018', 'CLIENTE FICTICIO H', '77791018', 'rezago.persona18@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000019', 'CLIENTE FICTICIO I', '77791019', 'rezago.persona19@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000020', 'CLIENTE FICTICIO J', '77791020', 'rezago.persona20@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000021', 'CLIENTE FICTICIO K', '77791021', 'rezago.persona21@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000022', 'CLIENTE FICTICIO L', '77791022', 'rezago.persona22@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000023', 'CLIENTE FICTICIO M', '77791023', 'rezago.persona23@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('c9e00000-0000-4000-8000-000000000024', 'CLIENTE FICTICIO N', '77791024', 'rezago.persona24@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004')
on conflict (id) do nothing;

-- ── Cuentas bancarias (números y CCI inventados; fechas fijas para que la huella sea estable) ──
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, beneficiario_nombre, beneficiario_dni,
   activa, origen, creado_por, creado_en, desactivada_por, desactivada_en) values
  -- A: la cuenta de pago de REZAGO-01
  ('c9ec0000-0000-4000-8000-000000000001', 'c9e00000-0000-4000-8000-000000000011', 'PEN', 'BCP',        'ahorros',   '19199000000001', '00219900000000000001', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-10 15:00+00', null, null),
  -- B: 02 nace activa (se desactiva más abajo, YA vinculada a REZAGO-02); 03 es su cuenta nueva
  ('c9ec0000-0000-4000-8000-000000000002', 'c9e00000-0000-4000-8000-000000000012', 'PEN', 'Interbank',  'ahorros',   '89899000000002', '00389900000000000002', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-11 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000003', 'c9e00000-0000-4000-8000-000000000012', 'PEN', 'BBVA',       'ahorros',   '01199000000003', '01119900000000000003', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-06-01 15:00+00', null, null),
  -- C: una PEN activa (la que debe vincular la carga), una PEN INACTIVA más nueva y una USD activa
  ('c9ec0000-0000-4000-8000-000000000004', 'c9e00000-0000-4000-8000-000000000013', 'PEN', 'BCP',        'ahorros',   '19199000000004', '00219900000000000004', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-12 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000005', 'c9e00000-0000-4000-8000-000000000013', 'PEN', 'Scotiabank', 'corriente', '00099000000005', '00909900000000000005', false, null, null, false, 'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-03-12 15:00+00', 'c9e00000-0000-4000-8000-000000000001', '2026-04-12 15:00+00'),
  ('c9ec0000-0000-4000-8000-000000000006', 'c9e00000-0000-4000-8000-000000000013', 'USD', 'BCP',        'ahorros',   '19199000000006', '00219900000000000006', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-12 15:05+00', null, null),
  -- D: una USD activa (la que debe vincular la carga) y una PEN activa
  ('c9ec0000-0000-4000-8000-000000000007', 'c9e00000-0000-4000-8000-000000000014', 'USD', 'Interbank',  'ahorros',   '89899000000007', '00389900000000000007', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-01-13 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000008', 'c9e00000-0000-4000-8000-000000000014', 'PEN', 'Interbank',  'ahorros',   '89899000000008', '00389900000000000008', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-01-13 15:05+00', null, null),
  -- E: una sola PEN activa para sus DOS contratos
  ('c9ec0000-0000-4000-8000-000000000009', 'c9e00000-0000-4000-8000-000000000015', 'PEN', 'BBVA',       'ahorros',   '01199000000009', '01119900000000000009', false, null, null, true,  'perfil',   'c9e00000-0000-4000-8000-000000000001', '2026-01-14 15:00+00', null, null),
  -- F: dos PEN activas (la segunda a nombre de un tercero: su nombre y DNI no deben salir en ningún mensaje)
  ('c9ec0000-0000-4000-8000-000000000010', 'c9e00000-0000-4000-8000-000000000016', 'PEN', 'BCP',        'ahorros',   '19199000000010', '00219900000000000010', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-15 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000011', 'c9e00000-0000-4000-8000-000000000016', 'PEN', 'Scotiabank', 'ahorros',   '00099000000011', '00909900000000000011', true,  'BENEFICIARIA FICTICIA TERCERA', '44559911', true, 'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-15 15:00+00', null, null),
  -- G: tres USD activas y una PEN activa
  ('c9ec0000-0000-4000-8000-000000000012', 'c9e00000-0000-4000-8000-000000000017', 'USD', 'BCP',        'ahorros',   '19199000000012', '00219900000000000012', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-16 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000013', 'c9e00000-0000-4000-8000-000000000017', 'USD', 'Interbank',  'ahorros',   '89899000000013', '00389900000000000013', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-16 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000014', 'c9e00000-0000-4000-8000-000000000017', 'USD', 'BBVA',       'corriente', '01199000000014', '01119900000000000014', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-03-16 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000015', 'c9e00000-0000-4000-8000-000000000017', 'PEN', 'BCP',        'ahorros',   '19199000000015', '00219900000000000015', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-16 15:05+00', null, null),
  -- H: solo una PEN activa (su contrato es en USD). Es además la cuenta AJENA del vínculo incoherente 14.
  ('c9ec0000-0000-4000-8000-000000000016', 'c9e00000-0000-4000-8000-000000000018', 'PEN', 'BCP',        'ahorros',   '19199000000016', '00219900000000000016', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-17 15:00+00', null, null),
  -- I: solo dos USD activas (su contrato es en PEN)
  ('c9ec0000-0000-4000-8000-000000000017', 'c9e00000-0000-4000-8000-000000000019', 'USD', 'BCP',        'ahorros',   '19199000000017', '00219900000000000017', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-18 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000018', 'c9e00000-0000-4000-8000-000000000019', 'USD', 'Interbank',  'ahorros',   '89899000000018', '00389900000000000018', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-18 15:00+00', null, null),
  -- K: solo una PEN INACTIVA (J y L no tienen ninguna cuenta)
  ('c9ec0000-0000-4000-8000-000000000019', 'c9e00000-0000-4000-8000-000000000021', 'PEN', 'BBVA',       'ahorros',   '01199000000019', '01119900000000000019', false, null, null, false, 'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-19 15:00+00', 'c9e00000-0000-4000-8000-000000000001', '2026-02-19 15:00+00'),
  -- M: una PEN activa propia (su vínculo apunta a la de H) · N: solo una USD activa (a la que apunta su vínculo)
  ('c9ec0000-0000-4000-8000-000000000020', 'c9e00000-0000-4000-8000-000000000023', 'PEN', 'Interbank',  'ahorros',   '89899000000020', '00389900000000000020', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-20 15:00+00', null, null),
  ('c9ec0000-0000-4000-8000-000000000021', 'c9e00000-0000-4000-8000-000000000024', 'USD', 'BCP',        'ahorros',   '19199000000021', '00219900000000000021', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-01-21 15:00+00', null, null)
on conflict (id) do nothing;

-- ── Catálogo mínimo: solo para satisfacer la FK contratos.producto_condicion_id (no se prueba) ──
insert into crm.productos_inversion (id, codigo, estado) values
  ('c9e90000-0000-4000-8000-000000000001', 'REZAGO-FICTICIO', 'activo')
on conflict (id) do nothing;
insert into crm.producto_versiones (id, producto_id, numero_version, estado, nombre, vigente_desde) values
  ('c9e90000-0000-4000-8000-000000000002', 'c9e90000-0000-4000-8000-000000000001', 1, 'borrador', 'PRODUCTO FICTICIO DEL REZAGO', '2026-01-01')
on conflict (id) do nothing;
insert into crm.producto_condiciones
  (id, version_id, orden, categoria, moneda, plazo_meses, modalidad, tipo_interes, capital_minimo, capital_maximo,
   tasa_referencia, tasa_minima, tasa_maxima) values
  ('c9e90000-0000-4000-8000-000000000003', 'c9e90000-0000-4000-8000-000000000002', 1, 'nuevo', 'PEN', 12, 'mensual', 'simple',
   100, 100000000, 12, 1, 50)
on conflict (id) do nothing;

-- ── Contratos (atajo 1: sin los disparadores de usuario de public.contratos) ───────────────────
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado, categoria,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial, es_demo, creado_en, actualizado_en)
select ('c9ed0000-0000-4000-8000-0000000000' || lpad(k.n::text, 2, '0'))::uuid,
       'REZAGO-' || lpad(k.n::text, 2, '0'),
       ('c9e00000-0000-4000-8000-0000000000' || k.cliente)::uuid,
       10000, k.moneda, 12, 'simple', 'mensual', 'activo', 'nuevo',
       date '2026-01-01', date '2027-01-01', 'c9e90000-0000-4000-8000-000000000003', date '2026-01-01',
       k.es_demo, timestamptz '2026-01-22 15:00+00', timestamptz '2026-01-22 15:00+00'
from (values
  ( 1, '11', 'PEN', false), ( 2, '12', 'PEN', false), ( 3, '13', 'PEN', false), ( 4, '14', 'USD', false),
  ( 5, '15', 'PEN', false), ( 6, '15', 'PEN', false), ( 7, '16', 'PEN', false), ( 8, '17', 'USD', false),
  ( 9, '18', 'USD', false), (10, '19', 'PEN', false), (11, '20', 'USD', false), (12, '21', 'PEN', false),
  (13, '22', 'PEN', true),  (14, '23', 'PEN', false), (15, '24', 'PEN', false)
) as k(n, cliente, moneda, es_demo)
on conflict (id) do nothing;
alter table public.contratos enable trigger user;

-- ── Vínculos sembrados ───────────────────────────────────────────────────────────────────────
-- Los dos coherentes, por la vía normal (con todos sus disparadores).
insert into crm.contrato_cuentas_pago (id, contrato_id, cuenta_bancaria_id, creado_por, creado_en) values
  ('c9ef0000-0000-4000-8000-000000000001', 'c9ed0000-0000-4000-8000-000000000001', 'c9ec0000-0000-4000-8000-000000000001', 'c9e00000-0000-4000-8000-000000000001', '2026-01-23 15:00+00'),
  ('c9ef0000-0000-4000-8000-000000000002', 'c9ed0000-0000-4000-8000-000000000002', 'c9ec0000-0000-4000-8000-000000000002', 'c9e00000-0000-4000-8000-000000000001', '2026-01-23 15:00+00')
on conflict do nothing;
-- REZAGO-02: su cuenta se desactiva DESPUÉS de vinculada (sigue siendo la instrucción contractual).
update crm.cuentas_bancarias
   set activa = false, desactivada_por = 'c9e00000-0000-4000-8000-000000000001', desactivada_en = '2026-06-01 15:00+00'
 where id = 'c9ec0000-0000-4000-8000-000000000002' and activa;
-- Atajo 2: los dos vínculos incoherentes (cuenta de otro cliente · cuenta de otra moneda).
alter table crm.contrato_cuentas_pago disable trigger trg_contrato_cuenta_pago_coherente;
insert into crm.contrato_cuentas_pago (id, contrato_id, cuenta_bancaria_id, creado_por, creado_en) values
  ('c9ef0000-0000-4000-8000-000000000014', 'c9ed0000-0000-4000-8000-000000000014', 'c9ec0000-0000-4000-8000-000000000016', 'c9e00000-0000-4000-8000-000000000001', '2026-01-23 15:00+00'),
  ('c9ef0000-0000-4000-8000-000000000015', 'c9ed0000-0000-4000-8000-000000000015', 'c9ec0000-0000-4000-8000-000000000021', 'c9e00000-0000-4000-8000-000000000001', '2026-01-23 15:00+00')
on conflict do nothing;
alter table crm.contrato_cuentas_pago enable trigger trg_contrato_cuenta_pago_coherente;

-- ── Cuotas: 3 pendientes por contrato (con todos los disparadores de cronograma_pagos) ─────────
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, creado_en)
select ('c9ee0000-0000-4000-8000-00000000' || lpad(k::text, 2, '0') || lpad(c::text, 2, '0'))::uuid,
       ('c9ed0000-0000-4000-8000-0000000000' || lpad(k::text, 2, '0'))::uuid,
       c, (date '2026-10-05' + make_interval(months => c))::date, 100, 'pendiente', timestamptz '2026-01-24 15:00+00'
from generate_series(1, 15) as k cross join generate_series(1, 3) as c
on conflict (id) do nothing;

-- Atajo 3: la cuota que REZAGO-04 ya tenía pagada antes de tener vínculo (sin sello).
alter table public.cronograma_pagos disable trigger user;
insert into public.cronograma_pagos
  (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, fecha_pago_real, monto_pagado, creado_en) values
  ('c9ee0000-0000-4000-8000-000000000400', 'c9ed0000-0000-4000-8000-000000000004', 0, date '2026-09-05', 100, 'pagado',
   date '2026-09-05', 100, timestamptz '2026-01-24 15:00+00')
on conflict (id) do nothing;
alter table public.cronograma_pagos enable trigger user;

-- ── Comprobación de la siembra (aborta sin confirmar si el mundo no es el descrito) ────────────
do $siembra$
declare
  v text;
begin
  select format('%s personal, %s clientes, %s cuentas (%s inactivas), %s contratos (%s demo), %s vínculos sembrados, %s cuotas pendientes, %s pagada de antes',
    (select count(*) from public.perfiles where id::text like 'c9e00000-%' and rol <> 'cliente'),
    (select count(*) from public.perfiles where id::text like 'c9e00000-%' and rol = 'cliente'),
    (select count(*) from crm.cuentas_bancarias where id::text like 'c9ec0000-%'),
    (select count(*) from crm.cuentas_bancarias where id::text like 'c9ec0000-%' and not activa),
    (select count(*) from public.contratos where id::text like 'c9ed0000-%'),
    (select count(*) from public.contratos where id::text like 'c9ed0000-%' and es_demo),
    (select count(*) from crm.contrato_cuentas_pago where id::text like 'c9ef0000-%'),
    (select count(*) from public.cronograma_pagos where id::text like 'c9ee0000-%' and estado = 'pendiente'),
    (select count(*) from public.cronograma_pagos
     where id = 'c9ee0000-0000-4000-8000-000000000400' and estado = 'pagado' and monto_pagado = 100 and fecha_pago_real = date '2026-09-05')) into v;
  if v <> '4 personal, 14 clientes, 21 cuentas (3 inactivas), 15 contratos (1 demo), 4 vínculos sembrados, 45 cuotas pendientes, 1 pagada de antes' then
    raise exception 'SIEMBRA cuentas-pago-rezago: el mundo no es el esperado: %', v;
  end if;
  if exists (select 1 from crm.cuotas_cuenta_pagada where cuota_id = 'c9ee0000-0000-4000-8000-000000000400') then
    raise exception 'SIEMBRA cuentas-pago-rezago: la cuota que REZAGO-04 ya tenía pagada no debe tener sello';
  end if;
  if not exists (select 1 from crm.equipo where perfil_id = 'c9e00000-0000-4000-8000-000000000003' and activo is false) then
    raise exception 'SIEMBRA cuentas-pago-rezago: la gestora revocada no quedó revocada en crm.equipo';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid in ('public.contratos'::regclass, 'crm.contrato_cuentas_pago'::regclass,
                                 'public.cronograma_pagos'::regclass, 'crm.cuentas_bancarias'::regclass)
               and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'SIEMBRA cuentas-pago-rezago: quedó un disparador apagado';
  end if;
  raise notice 'SIEMBRA cuentas-pago-rezago OK: %', v;
end;
$siembra$;
commit;

-- Censo de lo sembrado, SIN funciones nuevas (una sola consulta; sirve antes y después de la carga).
select q.caso || '|' || count(*) || '|' || string_agg(q.numero_contrato, ',' order by q.numero_contrato)
from (
  select ct.numero_contrato,
         case
           when l.id is not null and cb.cliente_id = ct.cliente_id and cb.moneda = ct.moneda then 'ok'
           when l.id is not null then 'cuenta_no_corresponde'
           when a.en_moneda = 1 then 'una_cuenta'
           when a.en_moneda >= 2 then 'varias_cuentas'
           when a.otra_moneda >= 1 then 'otra_moneda'
           else 'sin_cuenta'
         end as caso
  from public.contratos ct
  left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
  left join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  cross join lateral (
    select count(*) filter (where x.moneda = ct.moneda) as en_moneda,
           count(*) filter (where x.moneda <> ct.moneda) as otra_moneda
    from crm.cuentas_bancarias x
    where x.cliente_id = ct.cliente_id and x.activa
  ) a
  where ct.id::text like 'c9ed0000-%'
) q
group by q.caso
order by q.caso;
