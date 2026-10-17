savepoint citas_sin_corte;
update crm.capital_valoracion_politica set activa=true;
select set_config('request.jwt.claim.sub',pg_temp.persona(1)::text,true);
set local role authenticated;
select pg_temp.comprobar((select datos#>>'{gestion,valoracion,corte_id}' is null
  and jsonb_array_length(datos#>'{gestion,capital}')=0
  and (datos#>>'{gestion,valoracion,cobertura,pendientes,cantidad}')::int>0
  from (select crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31') datos) q),
  'Citas sin primer corte devuelve capital pendiente, no convierte las fuentes vivas');
reset role;
select jsonb_build_object('tc_fixture','citas-sin-corte','payload',crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'));
rollback to savepoint citas_sin_corte;
