-- Oraculo de F2.5 (Reuniones sobre la tabla-base).
--
-- Mide JULIO 2026 — mes ya pasado — para que la maduracion (una reunion de
-- julio que acaba en cierre en agosto) sea un hecho fijo y no dependa de la
-- hora ni del huso de quien ejecute.

set search_path = '';
set test.uid = '11111111-1111-4111-8111-111111111111';

-- gerencia que consulta
insert into public.perfiles (id, nombre_completo) values
  ('11111111-1111-4111-8111-111111111111', 'Gerencia'),
  ('22222222-2222-4222-8222-222222222222', 'Vendedora Uno') on conflict do nothing;
insert into crm.equipo (perfil_id, rol_crm) values
  ('11111111-1111-4111-8111-111111111111', 'gerencia'),
  ('22222222-2222-4222-8222-222222222222', 'vendedor') on conflict do nothing;

-- 4 leads con reunion REALIZADA en julio:
--   R1 cierra despues de la reunion (cuenta)
--   R2 cierra despues pero ANULADO (no cuenta)
--   R3 no cierra (no cuenta)
--   R4 cierra en AGOSTO, despues de su reunion de julio (cuenta: maduracion)
insert into crm.leads (id, origen, perfil_id, contrato_id, convertido_en, etapa, creado_en) values
  ('44444444-0000-4000-8000-000000000001','campania','22222222-2222-4222-8222-222222222222',null,'2026-07-20 10:00-05','convertido','2026-07-01 09:00-05'),
  ('44444444-0000-4000-8000-000000000002','campania','22222222-2222-4222-8222-222222222222',null,'2026-07-21 10:00-05','convertido','2026-07-01 09:00-05'),
  ('44444444-0000-4000-8000-000000000003','campania',null,null,null,'contactado','2026-07-01 09:00-05'),
  ('44444444-0000-4000-8000-000000000004','campania','22222222-2222-4222-8222-222222222222',null,'2026-08-10 10:00-05','convertido','2026-07-01 09:00-05'),
  -- R5: cerro ANTES de su reunion. La reunion no lo trajo, asi que NO cuenta.
  ('44444444-0000-4000-8000-000000000005','campania','22222222-2222-4222-8222-222222222222',null,'2026-07-05 10:00-05','convertido','2026-07-01 09:00-05');

insert into crm.tareas (lead_id, vendedor_id, tipo, estado, vence_en, modalidad_reunion) values
  ('44444444-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','reunion','completada','2026-07-10 10:00-05','presencial'),
  ('44444444-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','reunion','completada','2026-07-11 10:00-05','presencial'),
  ('44444444-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','reunion','completada','2026-07-12 10:00-05','presencial'),
  ('44444444-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','reunion','completada','2026-07-13 10:00-05','presencial'),
  ('44444444-0000-4000-8000-000000000005','22222222-2222-4222-8222-222222222222','reunion','completada','2026-07-14 10:00-05','presencial');

insert into crm.lead_asignaciones (analista_id, lead_id, origen, asignado_en, resultado, resultado_en) values
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000001','campania','2026-07-02 10:00-05','convertido','2026-07-20 10:00-05'),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000002','campania','2026-07-02 10:00-05','convertido','2026-07-21 10:00-05'),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000003','campania','2026-07-02 10:00-05',null,null),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000004','campania','2026-07-02 10:00-05','convertido','2026-08-10 10:00-05'),
  ('22222222-2222-4222-8222-222222222222','44444444-0000-4000-8000-000000000005','campania','2026-07-02 10:00-05','convertido','2026-07-05 10:00-05');
insert into private.anulados_stub values ('44444444-0000-4000-8000-000000000002') on conflict do nothing;

do $$
declare v jsonb; e text := '';
begin
  v := private.metricas_reuniones_implementacion('2026-07-01', '2026-07-31');

  -- GUARDA ANTI-VACUIDAD: si el fixture no llega o la RUTA cambia, todo lo de
  -- abajo compararia contra NULL — que no es ni verdad ni mentira — y la
  -- prueba pasaria sin comprobar nada. Ya paso DOS veces en esta fase.
  if coalesce((v->'resumen'->>'realizadas')::int, 0) <> 5 then
    raise exception 'ORACULO VACUO: realizadas=% (el fixture no llego)',
      v->'resumen'->>'realizadas';
  end if;
  if v->'conversion'->>'clientes' is null
     or v->'conversion'->>'contratos' is null
     or v->'conversion'->>'leads_reunidos' is null then
    raise exception 'ORACULO VACUO: el bloque `conversion` no trae las claves esperadas (%)',
      v->'conversion';
  end if;
  if (v->'conversion'->>'leads_reunidos')::int <> 5 then
    raise exception 'ORACULO VACUO: leads_reunidos=% (≠5)', v->'conversion'->>'leads_reunidos';
  end if;

  -- Terminan en cliente: R1 y R4. Fuera: R2 (anulado), R3 (sin cerrar) y
  -- R5 (cerro ANTES de la reunion: la reunion no lo trajo) = 2 de 5
  if (v->'conversion'->>'clientes')::int <> 2 then
    e := e || format(' clientes=%s(≠2: o cuenta el anulado, o pierde el que cerro en agosto)',
                     v->'conversion'->>'clientes'); end if;
  -- «terminan en contrato» valia 0 SIEMPRE con la columna muerta
  if (v->'conversion'->>'contratos')::int <> 2 then
    e := e || format(' contratos=%s(≠2: ¿volvio el numerador muerto?)',
                     v->'conversion'->>'contratos'); end if;
  -- y el % servido: 2 de 4 reunidos
  if (v->'conversion'->>'conversion_cliente_pct')::numeric <> 40.0 then
    e := e || format(' conversion_cliente_pct=%s(≠40.0)',
                     v->'conversion'->>'conversion_cliente_pct'); end if;

  if e <> '' then raise exception 'ORACULO ROTO:%', e; end if;
  raise notice 'REUNIONES OK · 5 realizadas → 2 terminan en cliente (fuera: anulado, sin cerrar y el que cerro ANTES)';
end $$;

-- El gate: quien no es gerencia no pasa
do $$
declare v jsonb; e text := '';
begin
  perform set_config('test.uid', '22222222-2222-4222-8222-222222222222', true);
  begin
    v := private.metricas_reuniones_implementacion('2026-07-01', '2026-07-31');
    e := e || ' un VENDEDOR obtuvo el payload de Reuniones';
  exception when sqlstate '42501' then null; end;
  perform set_config('test.uid', '', true);
  begin
    v := private.metricas_reuniones_implementacion('2026-07-01', '2026-07-31');
    e := e || ' un ANONIMO obtuvo el payload de Reuniones';
  exception when sqlstate '42501' then null; end;
  if e <> '' then raise exception 'ORACULO ROTO (gate):%', e; end if;
  raise notice 'GATE DE REUNIONES OK';
end $$;

select 'TEST-F2-REUNIONES: TODO VERDE' as resultado;
