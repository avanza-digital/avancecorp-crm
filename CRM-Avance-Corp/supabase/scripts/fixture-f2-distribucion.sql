-- Fixture de F2.3a: solo siembra, ni una asercion. Lo carga el runner UNA
-- vez, antes de fotografiar la forma de la funcion vieja.

set search_path = '';

-- ── Fixture: 1 vendedora, 3 episodios de julio (2 cerrados, 1 descartado);
--    uno de los cierres esta ANULADO. Con la funcion vieja contaban 2.
insert into public.perfiles (id, nombre_completo) values
  ('22222222-2222-4222-8222-222222222222', 'Vendedora Uno')
on conflict (id) do nothing;
insert into crm.equipo (perfil_id, rol_crm) values
  ('22222222-2222-4222-8222-222222222222', 'vendedor')
on conflict (perfil_id) do nothing;

insert into crm.leads (id, creado_en, activo, etapa) values
  ('44444444-0000-4000-8000-000000000001', '2026-07-03 09:00-05', true, 'convertido'),
  ('44444444-0000-4000-8000-000000000002', '2026-07-04 09:00-05', true, 'convertido'),
  ('44444444-0000-4000-8000-000000000003', '2026-07-05 09:00-05', true, 'descartado'),
  -- Asignado en julio pero CERRADO EN AGOSTO: su cierre sigue siendo suyo, y
  -- solo se ve si la pierna de cierres mira mas alla del rango.
  ('44444444-0000-4000-8000-000000000004', '2026-07-06 09:00-05', true, 'convertido')
on conflict (id) do nothing;

insert into crm.lead_asignaciones
  (analista_id, lead_id, origen, asignado_en, resultado, resultado_en, finalizado_en, moneda, monto_estimado)
values
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000001',
   'campania', '2026-07-03 10:00-05', 'convertido', '2026-07-20 10:00-05', '2026-07-20 10:00-05', 'PEN', 50000),
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000002',
   'campania', '2026-07-04 10:00-05', 'convertido', '2026-07-21 10:00-05', '2026-07-21 10:00-05', 'PEN', 50000),
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000003',
   'campania', '2026-07-05 10:00-05', 'descartado', '2026-07-22 10:00-05', '2026-07-22 10:00-05', 'PEN', 50000),
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000004',
   'campania', '2026-07-06 10:00-05', 'convertido', '2026-08-10 10:00-05', '2026-08-10 10:00-05', 'PEN', 50000);

-- El segundo cierre lo anulo gerencia
insert into private.anulados_stub values ('44444444-0000-4000-8000-000000000002')
on conflict do nothing;

