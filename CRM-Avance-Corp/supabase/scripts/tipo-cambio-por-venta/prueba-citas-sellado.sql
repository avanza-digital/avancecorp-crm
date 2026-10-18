savepoint citas_selladas;
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
set local role authenticated;
select pg_temp.comprobar((select (datos#>>'{gestion,valoracion,sellado}')::boolean
  and datos#>>'{gestion,valoracion,cobertura,estado}'='completo'
  and exists(select 1 from jsonb_array_elements(datos#>'{gestion,capital}') k
    where (k->>'contrato_id')::uuid=pg_temp.contrato(1)
      and (k->>'monto')::numeric=20000 and (k->>'tasa')::numeric=3.4 and (k->>'equivalente_pen')::numeric=68000)
  from (select crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31') datos) q),
  'Citas sellada conserva USD 20 000 a 3,40 = S/ 68 000 tras otra cotización y suspensión de presentación');
reset role;
select jsonb_build_object('tc_fixture','citas-sellado','payload',crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'));
rollback to savepoint citas_selladas;
