-- Fixture de F2.3b: el de F2.3a (que el runner carga ANTES que este) mas lo
-- que la v3 necesita para que sus aserciones MUERDAN:
--   · un episodio en DOLARES cerrado en julio (sin el, el % USD del resumen y
--     del analista se asertarian sobre 0/0 y pasarian en vacio)
--   · un perfil de GERENCIA para probar el gate del despachador en positivo
--     (la leccion de F2.1: un gate que nunca se prueba en positivo no se prueba)

set search_path = '';

insert into public.perfiles (id, nombre_completo) values
  ('33333333-3333-4333-8333-333333333333', 'Gerente Uno')
on conflict (id) do nothing;
insert into crm.equipo (perfil_id, rol_crm) values
  ('33333333-3333-4333-8333-333333333333', 'gerencia')
on conflict (perfil_id) do nothing;

-- Episodio USD: asignado y CERRADO en julio, sin anular → 1/1 = 100 %.
insert into crm.leads (id, creado_en, activo, etapa, moneda) values
  ('44444444-0000-4000-8000-000000000005', '2026-07-07 09:00-05', true, 'convertido', 'USD')
on conflict (id) do nothing;

insert into crm.lead_asignaciones
  (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en, finalizado_en, moneda, monto_estimado)
values
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000005',
   'campania', 'entrada', '2026-07-07 10:00-05', 'convertido', '2026-07-25 10:00-05', '2026-07-25 10:00-05', 'USD', 20000);

-- El fixture base (compartido con el banco F2.3a) deja `motivo_apertura` NULL,
-- pero el nucleo VIVO agrega por motivo con `jsonb_object_agg`, que no admite
-- clave NULL — y en produccion el motivo siempre viene relleno. Se realinea
-- aqui para no tocar el fixture de F2.3a.
update crm.lead_asignaciones set motivo_apertura = 'entrada'
 where motivo_apertura is null;

-- (Codex b6) Sin un REFERIDO y una OPERACION DE CARTERA, los dos terminos
-- distintivos del numerador del nucleo valen cero y un mutante que los
-- rompiera (factor→1, borrar +operaciones) pasaria verde. Se ejercitan:
--   · lead REFERIDO cerrado en julio: fuera del divisor, aporta 0.15
--   · 1 operacion de cartera elegible de julio: aporta 1
-- Numerador esperado del nucleo: 2 (lead1 + lead5) + 0.15 + 1 = 3.15 → 63.00 %
insert into crm.leads (id, creado_en, activo, etapa, moneda) values
  ('44444444-0000-4000-8000-000000000006', '2026-07-08 09:00-05', true, 'convertido', 'PEN')
on conflict (id) do nothing;
insert into crm.lead_asignaciones
  (analista_id, lead_id, origen, motivo_apertura, asignado_en, resultado, resultado_en, finalizado_en, moneda, monto_estimado)
values
  ('22222222-2222-4222-8222-222222222222', '44444444-0000-4000-8000-000000000006',
   'referido', 'entrada', '2026-07-08 10:00-05', 'convertido', '2026-07-26 10:00-05', '2026-07-26 10:00-05', 'PEN', 30000);
insert into crm.operaciones_cartera
  (cliente_id, vendedor_id, tipo, fecha_operacion, periodo, moneda, capital_renovado, elegible_conversion, creado_en)
values
  ('55555555-5555-4555-8555-555555555555', '22222222-2222-4222-8222-222222222222',
   'renovacion', '2026-07-15', '2026-07-01', 'PEN', 10000, true, '2026-07-15 10:00-05');
