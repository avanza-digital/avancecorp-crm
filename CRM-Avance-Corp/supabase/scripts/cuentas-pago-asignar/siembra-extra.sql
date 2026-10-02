-- SIEMBRA EXTRA FICTICIA de 20261002005004_crm_asignar_cuenta_pago — SOLO BANCO Docker propio.
-- ⚠️ Jamás contra producción: escribe y CONFIRMA personas, cuentas, contratos y cuotas inventados.
-- Va DESPUÉS de ../cuentas-pago-rezago/siembra.sql (la siembra común: REZAGO-01…15) y añade solo lo
-- que esa no trae y la asignación necesita. Idempotente: todo entra con «on conflict do nothing»;
-- repetirla no crea ni cambia nada. NO repone el mundo si una prueba dejó restos (eso lo hace
-- ciclo.sh con su limpieza). Se lanza como postgres, en un solo mensaje:
--   docker exec -i -e PGPASSWORD=postgres <contenedor> psql -U postgres -h 127.0.0.1 -d postgres \
--     -v ON_ERROR_STOP=1 -qAt < siembra-extra.sql
--
-- LO QUE AÑADE (identificadores fijos, prefijo a519…):
--   personas   a5190000-…-NN   cuentas  a519c000-…-NN   contratos  a519d000-…-NN (ASIGNAR-NN)
--   cuotas     a519e000-…-NNCC (contrato NN, cuota CC)
--
--   Personal:  31 superadmin · 32 admin DESACTIVADO (perfiles.activo = false) · 33 superadmin con la
--              membresía CRM REVOCADA (crm.equipo.activo = false) · 34 admin con membresía CRM VIGENTE
--              (crm.equipo gerencia, activo = true: estar en el equipo no es estar revocado) ·
--              36 comercial · 37 directorio
--   Clientes:  41 cliente P · 42 cliente Q
--   Cuentas:   P → 01 PEN BCP · 02 PEN Interbank · 03 USD BCP · 04 PEN BBVA (INACTIVA) ·
--                  05 USD Interbank · 06 PEN Scotiabank (la que «retira» la prueba de concurrencia)
--              Q → 11 PEN BCP (la «cuenta de otro cliente»)
--   Contratos (todos del cliente P y todos SIN vínculo; 3 cuotas pendientes en los abiertos):
--     01 activo PEN · 02 VENCIDO PEN (abierto: se puede asignar) · 03 RENOVADO PEN (cerrado) ·
--     04 RETIRADO PEN (cerrado) · 05 activo USD ·
--     06…13 activos PEN, reservados para lo que se CONFIRMA de verdad: la prueba de concurrencia
--     (prueba-concurrencia.sh) y la asignación confirmada de ciclo.sh.
--
--   P tiene tres cuentas PEN activas y dos USD activas a propósito: todos sus contratos son
--   «varias_cuentas», así que la carga del rezago de 20261001233019 (que solo vincula cuando hay
--   UNA cuenta posible) nunca los toca, se aplique antes o después.
--
-- UN ATAJO, dentro de esta transacción y con el disparador repuesto antes de confirmar: se apagan
-- los disparadores de usuario de public.contratos SOLO mientras entran los contratos (igual que la
-- siembra común): el alta real exige operación de cartera, lead, producto publicado… El bloque
-- final comprueba que no quedó ninguno apagado.
begin;
set local lock_timeout = '5s';

do $requisito$
begin
  if (select count(*) from public.contratos where id::text like 'c9ed0000-%') <> 15
     or not exists (select 1 from public.perfiles where id = 'c9e00000-0000-4000-8000-000000000004' and rol = 'analista')
     or not exists (select 1 from crm.producto_condiciones where id = 'c9e90000-0000-4000-8000-000000000003') then
    raise exception 'SIEMBRA EXTRA cuentas-pago-asignar: falta la siembra común (../cuentas-pago-rezago/siembra.sql); lánzala antes';
  end if;
end;
$requisito$;

-- ── Personas ─────────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, email, aud, role)
select ('a5190000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       'asignar.persona' || lpad(n::text, 2, '0') || '@prueba.invalid', 'authenticated', 'authenticated'
from unnest(array[31, 32, 33, 34, 36, 37, 41, 42]) as t(n)
on conflict (id) do nothing;

insert into public.perfiles (id, nombre_completo, dni, correo, rol, activo) values
  ('a5190000-0000-4000-8000-000000000031', 'SUPERADMIN FICTICIA DE ASIGNAR',   '77890031', 'asignar.persona31@prueba.invalid', 'superadmin', true),
  ('a5190000-0000-4000-8000-000000000032', 'ADMIN FICTICIO DESACTIVADO',       '77890032', 'asignar.persona32@prueba.invalid', 'admin',      false),
  ('a5190000-0000-4000-8000-000000000033', 'SUPERADMIN FICTICIA REVOCADA',     '77890033', 'asignar.persona33@prueba.invalid', 'superadmin', true),
  ('a5190000-0000-4000-8000-000000000034', 'ADMIN FICTICIO CON EQUIPO VIGENTE', '77890034', 'asignar.persona34@prueba.invalid', 'admin',      true),
  ('a5190000-0000-4000-8000-000000000036', 'COMERCIAL FICTICIO DE ASIGNAR',    '77890036', 'asignar.persona36@prueba.invalid', 'comercial',  true),
  ('a5190000-0000-4000-8000-000000000037', 'DIRECTORIO FICTICIO DE ASIGNAR',   '77890037', 'asignar.persona37@prueba.invalid', 'directorio', true)
on conflict (id) do nothing;

-- La revocación (P04) es una fila de crm.equipo con activo = false; una fila con activo = true NO revoca.
insert into crm.equipo (perfil_id, rol_crm, activo) values
  ('a5190000-0000-4000-8000-000000000033', 'gerencia', false),
  ('a5190000-0000-4000-8000-000000000034', 'gerencia', true)
on conflict (perfil_id) do nothing;

insert into public.perfiles (id, nombre_completo, dni, correo, rol, activo, asesor_perfil_id) values
  ('a5190000-0000-4000-8000-000000000041', 'CLIENTE FICTICIO P', '77891041', 'asignar.persona41@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004'),
  ('a5190000-0000-4000-8000-000000000042', 'CLIENTE FICTICIO Q', '77891042', 'asignar.persona42@prueba.invalid', 'cliente', true, 'c9e00000-0000-4000-8000-000000000004')
on conflict (id) do nothing;

-- ── Cuentas bancarias (números y CCI inventados; fechas fijas) ─────────────────────────────────
insert into crm.cuentas_bancarias
  (id, cliente_id, moneda, banco, tipo_cuenta, numero_cuenta, cci, titular_distinto, beneficiario_nombre, beneficiario_dni,
   activa, origen, creado_por, creado_en, desactivada_por, desactivada_en) values
  ('a519c000-0000-4000-8000-000000000001', 'a5190000-0000-4000-8000-000000000041', 'PEN', 'BCP',        'ahorros',   '19151900000001', '00251900000000000001', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-01 15:00+00', null, null),
  ('a519c000-0000-4000-8000-000000000002', 'a5190000-0000-4000-8000-000000000041', 'PEN', 'Interbank',  'ahorros',   '89851900000002', '00351900000000000002', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-02-02 15:00+00', null, null),
  ('a519c000-0000-4000-8000-000000000003', 'a5190000-0000-4000-8000-000000000041', 'USD', 'BCP',        'ahorros',   '19151900000003', '00251900000000000003', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-03 15:00+00', null, null),
  ('a519c000-0000-4000-8000-000000000004', 'a5190000-0000-4000-8000-000000000041', 'PEN', 'BBVA',       'corriente', '01151900000004', '01151900000000000004', false, null, null, false, 'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-04 15:00+00', 'c9e00000-0000-4000-8000-000000000001', '2026-03-04 15:00+00'),
  ('a519c000-0000-4000-8000-000000000005', 'a5190000-0000-4000-8000-000000000041', 'USD', 'Interbank',  'ahorros',   '89851900000005', '00351900000000000005', false, null, null, true,  'portal',   'c9e00000-0000-4000-8000-000000000001', '2026-02-05 15:00+00', null, null),
  ('a519c000-0000-4000-8000-000000000006', 'a5190000-0000-4000-8000-000000000041', 'PEN', 'Scotiabank', 'ahorros',   '00051900000006', '00951900000000000006', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-06 15:00+00', null, null),
  ('a519c000-0000-4000-8000-000000000011', 'a5190000-0000-4000-8000-000000000042', 'PEN', 'BCP',        'ahorros',   '19151900000011', '00251900000000000011', false, null, null, true,  'contrato', 'c9e00000-0000-4000-8000-000000000001', '2026-02-11 15:00+00', null, null)
on conflict (id) do nothing;

-- ── Contratos (el atajo: sin los disparadores de usuario de public.contratos) ──────────────────
alter table public.contratos disable trigger user;
insert into public.contratos
  (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, tipo_interes, modalidad, estado, categoria,
   fecha_inicio, fecha_vencimiento, producto_condicion_id, fecha_cierre_comercial, es_demo, creado_en, actualizado_en)
select ('a519d000-0000-4000-8000-0000000000' || lpad(k.n::text, 2, '0'))::uuid,
       'ASIGNAR-' || lpad(k.n::text, 2, '0'),
       'a5190000-0000-4000-8000-000000000041'::uuid,
       10000, k.moneda, 12, 'simple', 'mensual', k.estado, 'nuevo',
       k.inicio, (k.inicio + interval '1 year')::date, 'c9e90000-0000-4000-8000-000000000003', k.inicio,
       false, timestamptz '2026-02-12 15:00+00', timestamptz '2026-02-12 15:00+00'
from (values
  ( 1, 'PEN', 'activo',   date '2026-02-01'), ( 2, 'PEN', 'vencido',  date '2025-02-01'),
  ( 3, 'PEN', 'renovado', date '2025-02-01'), ( 4, 'PEN', 'retirado', date '2025-02-01'),
  ( 5, 'USD', 'activo',   date '2026-02-01'), ( 6, 'PEN', 'activo',   date '2026-02-01'),
  ( 7, 'PEN', 'activo',   date '2026-02-01'), ( 8, 'PEN', 'activo',   date '2026-02-01'),
  ( 9, 'PEN', 'activo',   date '2026-02-01'), (10, 'PEN', 'activo',   date '2026-02-01'),
  (11, 'PEN', 'activo',   date '2026-02-01'), (12, 'PEN', 'activo',   date '2026-02-01'),
  (13, 'PEN', 'activo',   date '2026-02-01')
) as k(n, moneda, estado, inicio)
on conflict (id) do nothing;
alter table public.contratos enable trigger user;

-- ── Cuotas: 3 pendientes por contrato ABIERTO (con todos los disparadores de cronograma_pagos) ──
insert into public.cronograma_pagos (id, contrato_id, numero_cuota, fecha_programada, monto_programado, estado, creado_en)
select ('a519e000-0000-4000-8000-00000000' || lpad(k::text, 2, '0') || lpad(c::text, 2, '0'))::uuid,
       ('a519d000-0000-4000-8000-0000000000' || lpad(k::text, 2, '0'))::uuid,
       c, (date '2026-10-05' + make_interval(months => c))::date, 100, 'pendiente', timestamptz '2026-02-13 15:00+00'
from unnest(array[1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13]) as k cross join generate_series(1, 3) as c
on conflict (id) do nothing;

-- ── Comprobación (aborta sin confirmar si lo añadido no es lo descrito) ────────────────────────
do $siembra$
declare
  v text;
begin
  select format('%s personal, %s clientes, %s cuentas (%s inactivas), %s contratos (%s abiertos, %s cerrados), %s vínculos, %s cuotas pendientes',
    (select count(*) from public.perfiles where id::text like 'a5190000-%' and rol <> 'cliente'),
    (select count(*) from public.perfiles where id::text like 'a5190000-%' and rol = 'cliente'),
    (select count(*) from crm.cuentas_bancarias where id::text like 'a519c000-%'),
    (select count(*) from crm.cuentas_bancarias where id::text like 'a519c000-%' and not activa),
    (select count(*) from public.contratos where id::text like 'a519d000-%'),
    (select count(*) from public.contratos where id::text like 'a519d000-%' and estado in ('activo', 'vencido')),
    (select count(*) from public.contratos where id::text like 'a519d000-%' and estado in ('renovado', 'retirado')),
    (select count(*) from crm.contrato_cuentas_pago where contrato_id::text like 'a519d000-%'),
    (select count(*) from public.cronograma_pagos where id::text like 'a519e000-%' and estado = 'pendiente')) into v;
  if v <> '6 personal, 2 clientes, 7 cuentas (1 inactivas), 13 contratos (11 abiertos, 2 cerrados), 0 vínculos, 33 cuotas pendientes' then
    raise exception 'SIEMBRA EXTRA cuentas-pago-asignar: lo añadido no es lo esperado (¿restos de una prueba? ciclo.sh los limpia): %', v;
  end if;
  if (select string_agg(p.rol || ':' || p.activo::text, ',' order by p.id) from public.perfiles p
      where p.id::text like 'a5190000-%' and p.rol <> 'cliente')
     <> 'superadmin:true,admin:false,superadmin:true,admin:true,comercial:true,directorio:true' then
    raise exception 'SIEMBRA EXTRA cuentas-pago-asignar: el personal añadido no tiene los roles esperados';
  end if;
  if (select string_agg(e.perfil_id::text || ':' || e.activo::text, ',' order by e.perfil_id) from crm.equipo e
      where e.perfil_id::text like 'a5190000-%')
     <> 'a5190000-0000-4000-8000-000000000033:false,a5190000-0000-4000-8000-000000000034:true' then
    raise exception 'SIEMBRA EXTRA cuentas-pago-asignar: las membresías CRM (revocada y vigente) no quedaron como se espera';
  end if;
  if exists (select 1 from pg_catalog.pg_trigger t
             where t.tgrelid in ('public.contratos'::regclass, 'crm.contrato_cuentas_pago'::regclass,
                                 'public.cronograma_pagos'::regclass, 'crm.cuentas_bancarias'::regclass)
               and not t.tgisinternal and t.tgenabled <> 'O') then
    raise exception 'SIEMBRA EXTRA cuentas-pago-asignar: quedó un disparador apagado';
  end if;
  raise notice 'SIEMBRA EXTRA cuentas-pago-asignar OK: %', v;
end;
$siembra$;
commit;
