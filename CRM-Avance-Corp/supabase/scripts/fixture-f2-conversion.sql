-- Fixture COMPARTIDO de F2 (lo usan test-f2-conversiones.sql y test-f2-ranking.sql).
-- Solo siembra: ni una asercion. Julio 2026 como mes medido — ya pasado, para
-- que la maduracion de la cosecha no dependa de la hora ni del huso de quien
-- ejecute ([[Una prueba de fechas en tu propia zona no prueba nada]]).

set search_path = '';

-- La identidad la fija el test (auth.uid() la lee de aqui): asi el gate de rol
-- se puede probar de verdad, en positivo y en negativo.
set test.uid = '11111111-1111-4111-8111-111111111111';

-- Esquema propio (no `pg_temp`): el fixture y las pruebas corren en sesiones
-- de psql DISTINTAS, y los objetos temporales no sobreviven a la sesion.
create schema banco;
create table banco.ids (k text primary key, id uuid);
insert into banco.ids (k, id) values
  ('V1', '22222222-2222-4222-8222-222222222222'),
  ('C1', '33333333-3333-4333-8333-333333333333');

create function banco.uid(p text) returns uuid
language sql stable as $fx$ select id from banco.ids where k = p $fx$;
create function banco.lead(n int) returns uuid
language sql immutable as
$fx$ select ('44444444-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $fx$;

-- El vendedor del mundo de prueba (tambien sirve de identidad DENEGADA)
insert into public.perfiles (id) values (banco.uid('V1'));
insert into crm.equipo (perfil_id, rol_crm) values (banco.uid('V1'), 'vendedor');

-- ── LEADS (alta) ───────────────────────────────────────────────────────────
insert into crm.leads (id, creado_en, origen, categoria_interes, etapa, vendedor_id) values
  (banco.lead(1), '2026-07-03 09:00-05', 'campania', 'renta', 'convertido', banco.uid('V1')),
  (banco.lead(2), '2026-07-05 09:00-05', 'referido', 'renta', 'convertido', banco.uid('V1')),
  (banco.lead(3), '2026-07-06 09:00-05', 'campania', 'renta', 'convertido', banco.uid('V1')),
  (banco.lead(4), '2026-07-10 09:00-05', 'campania', 'renta', 'contactado',  banco.uid('V1')),
  (banco.lead(5), '2026-06-20 09:00-05', 'campania', 'renta', 'convertido', banco.uid('V1')),
  (banco.lead(6), '2026-07-12 09:00-05', 'campania', 'renta', 'convertido', banco.uid('V1'));
-- OJO: contrato_id queda NULL en TODOS, igual que en produccion (371
-- contratos, 0 enlazados). Ese es el mundo real que hacia 0 % la pantalla.

-- ── LEDGER de asignaciones (la verdad de la conversion) ────────────────────
insert into crm.lead_asignaciones
  (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en) values
  -- cierra en julio, no referido
  (banco.uid('V1'), banco.lead(1), 'campania', 'nuevo', '2026-07-03 10:00-05', 'convertido', '2026-07-20 15:00-05'),
  -- cierra en julio, REFERIDO (fuera del divisor, pesa 0.15)
  (banco.uid('V1'), banco.lead(2), 'referido', 'nuevo', '2026-07-05 10:00-05', 'convertido', '2026-07-22 15:00-05'),
  -- cierra en julio pero ANULADO: no cuenta en ningun numerador
  (banco.uid('V1'), banco.lead(3), 'campania', 'nuevo', '2026-07-06 10:00-05', 'convertido', '2026-07-25 15:00-05'),
  -- recibido en julio, sin cerrar
  (banco.uid('V1'), banco.lead(4), 'campania', 'nuevo', '2026-07-10 10:00-05', null, null),
  -- alta de JUNIO, asignado en julio: entra al nucleo, NO a la cosecha
  (banco.uid('V1'), banco.lead(5), 'campania', 'nuevo', '2026-07-02 10:00-05', 'convertido', '2026-07-24 15:00-05'),
  -- alta de julio que cierra en AGOSTO: entra a la cosecha (maduracion),
  -- NO al numerador del nucleo de julio
  (banco.uid('V1'), banco.lead(6), 'campania', 'nuevo', '2026-07-12 10:00-05', 'convertido', '2026-08-10 15:00-05');

insert into private.anulados_stub values (banco.lead(3));

-- ── CARTERA: una operacion elegible de julio (suma 1 al numerador) ─────────
insert into crm.operaciones_cartera
  (cliente_id, vendedor_id, tipo, fecha_operacion, periodo, moneda,
   capital_renovado, capital_adicional, elegible_conversion, creado_por, creado_en)
values (banco.uid('C1'), banco.uid('V1'), 'renovacion', '2026-07-15', '2026-07-01',
        'PEN', 1000, 0, true, banco.uid('V1'), '2026-07-15 10:00-05');

