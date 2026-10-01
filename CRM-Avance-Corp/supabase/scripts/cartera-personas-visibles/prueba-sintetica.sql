-- SOLO LECTURA, datos sintéticos (VALUES): el lateral viejo y la CTE nueva deben elegir el mismo nombre para cada (persona, lector).
-- Casos: empate en creado_en (desempata id), fuente duplicada, fuente con inversionista_id NULL, empresa 'avance' excluida,
-- nombre NULL/vacío, persona sin cierres, lector true/false.
with cierres(id, nombre_completo, creado_en) as (values
  ('00000000-0000-0000-0000-00000000000a'::uuid, 'Cierre A', '2026-01-01 10:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000000b'::uuid, 'Cierre B (empate, id mayor)', '2026-01-01 10:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000000c'::uuid, 'Cierre C (más reciente)', '2026-02-01 10:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000000d'::uuid, null, '2026-03-01 10:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000000e'::uuid, '   ', '2026-03-01 10:00'::timestamptz),
  ('00000000-0000-0000-0000-00000000000f'::uuid, 'Contrato avance (excluido)', '2026-04-01 10:00'::timestamptz)),
fuentes(fuente_id, inversionista_id, empresa) as (values
  ('00000000-0000-0000-0000-00000000000a'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'qorilazo'),
  ('00000000-0000-0000-0000-00000000000b'::uuid, '10000000-0000-0000-0000-000000000001'::uuid, 'qorilazo'),   -- empate con A
  ('00000000-0000-0000-0000-00000000000c'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 'prodelco'),
  ('00000000-0000-0000-0000-00000000000c'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 'prodelco'),   -- duplicada
  ('00000000-0000-0000-0000-00000000000a'::uuid, '10000000-0000-0000-0000-000000000002'::uuid, 'qorilazo'),   -- más antigua
  ('00000000-0000-0000-0000-00000000000d'::uuid, '10000000-0000-0000-0000-000000000003'::uuid, 'qorilazo'),   -- nombre null (más reciente)
  ('00000000-0000-0000-0000-00000000000a'::uuid, '10000000-0000-0000-0000-000000000003'::uuid, 'qorilazo'),
  ('00000000-0000-0000-0000-00000000000e'::uuid, '10000000-0000-0000-0000-000000000004'::uuid, 'prodelco'),   -- nombre vacío
  ('00000000-0000-0000-0000-00000000000f'::uuid, '10000000-0000-0000-0000-000000000005'::uuid, 'avance'),     -- excluida
  ('00000000-0000-0000-0000-00000000000c'::uuid, null, 'qorilazo')),                                          -- sin persona
personas(id, lector) as (values
  ('10000000-0000-0000-0000-000000000001'::uuid, false), ('10000000-0000-0000-0000-000000000001'::uuid, true),
  ('10000000-0000-0000-0000-000000000002'::uuid, false), ('10000000-0000-0000-0000-000000000003'::uuid, false),
  ('10000000-0000-0000-0000-000000000004'::uuid, false), ('10000000-0000-0000-0000-000000000005'::uuid, false),
  ('10000000-0000-0000-0000-000000000006'::uuid, false), ('10000000-0000-0000-0000-000000000002'::uuid, true)),
viejo as (
  select i.id, i.lector, ce.nombre_completo from personas i
  left join lateral (
    select ce0.nombre_completo from cierres ce0 join fuentes f on f.fuente_id=ce0.id and f.empresa<>'avance'
    where f.inversionista_id=i.id and not i.lector order by ce0.creado_en desc, ce0.id limit 1) ce on true),
cierres_nombre as (
  select distinct on (f.inversionista_id) f.inversionista_id, ce0.nombre_completo
  from fuentes f join cierres ce0 on ce0.id=f.fuente_id where f.empresa<>'avance'
  order by f.inversionista_id, ce0.creado_en desc, ce0.id),
nuevo as (
  select i.id, i.lector, ce.nombre_completo from personas i
  left join cierres_nombre ce on ce.inversionista_id=i.id and not i.lector)
select json_build_object(
  'solo_en_viejo', (select count(*) from (select * from viejo except all select * from nuevo) x),
  'solo_en_nuevo', (select count(*) from (select * from nuevo except all select * from viejo) x),
  'filas', (select count(*) from nuevo),
  'nuevo', (select json_agg(json_build_array(right(id::text,1), lector, nombre_completo) order by id, lector) from nuevo)
)::text v;
