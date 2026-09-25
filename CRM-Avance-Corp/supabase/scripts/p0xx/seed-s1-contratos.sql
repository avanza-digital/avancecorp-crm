-- SOLO RAMA hhpjiygytwoayxymziqo, despues de seed-s1-clientes.sql.
-- Siete contratos ficticios: cinco sin vinculo, dos testigos vinculados.
begin;
set local lock_timeout = '10s';
select pg_catalog.set_config(
  'request.jwt.claim.sub', 'b0000000-0000-4000-8000-000000000002', true);

with casos(id,numero_contrato,cliente_id,moneda) as (
  values
    ('d0000000-0000-4000-8000-000000000001'::uuid,'P0XX-S1-001',
     'c0000000-0000-4000-8000-000000000001'::uuid,'PEN'::text),
    ('d0000000-0000-4000-8000-000000000002'::uuid,'P0XX-S1-002',
     'c0000000-0000-4000-8000-000000000001'::uuid,'USD'::text),
    ('d0000000-0000-4000-8000-000000000003'::uuid,'P0XX-S1-003',
     'c0000000-0000-4000-8000-000000000002'::uuid,'PEN'::text),
    ('d0000000-0000-4000-8000-000000000004'::uuid,'P0XX-S1-004',
     'c0000000-0000-4000-8000-000000000003'::uuid,'USD'::text),
    ('d0000000-0000-4000-8000-000000000005'::uuid,'P0XX-S1-005',
     'c0000000-0000-4000-8000-000000000004'::uuid,'PEN'::text),
    ('d0000000-0000-4000-8000-000000000006'::uuid,'P0XX-S1-006',
     'c0000000-0000-4000-8000-000000000005'::uuid,'PEN'::text),
    ('d0000000-0000-4000-8000-000000000007'::uuid,'P0XX-S1-007',
     'c0000000-0000-4000-8000-000000000005'::uuid,'USD'::text)
)
insert into public.contratos
  (id,numero_contrato,cliente_id,capital,moneda,modalidad,tipo_interes,
   fecha_inicio,fecha_vencimiento,categoria,tasa_anual,creado_por)
select c.id,c.numero_contrato,c.cliente_id,1000,c.moneda,'mensual','simple',
       (pg_catalog.now() at time zone 'America/Lima')::date,
       ((pg_catalog.now() at time zone 'America/Lima')::date
         + interval '12 months')::date,
       'nuevo',
       (private.resolver_tasa(c.cliente_id,'nuevo',null::uuid,
                              pg_catalog.statement_timestamp())->>'tasa_base')::numeric,
       'b0000000-0000-4000-8000-000000000002'::uuid
from casos c
on conflict (id) do nothing;

insert into crm.contrato_cuentas_pago
  (contrato_id,cuenta_bancaria_id,creado_por)
values
  ('d0000000-0000-4000-8000-000000000006',
   'e0000000-0000-4000-8000-000000000003',
   'b0000000-0000-4000-8000-000000000002'),
  ('d0000000-0000-4000-8000-000000000007',
   'e0000000-0000-4000-8000-000000000004',
   'b0000000-0000-4000-8000-000000000002')
on conflict (contrato_id) do nothing;

commit;
