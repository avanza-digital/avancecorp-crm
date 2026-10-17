select pg_temp.comprobar((select datos#>>'{gestion,valoracion,corte_id}'=(select id::text from cortes_prueba where nombre='corregido')
  and (datos#>>'{gestion,valoracion,cobertura,pendientes,cantidad}')::int=2
  and exists(select 1 from jsonb_array_elements(datos#>'{gestion,capital}') k
    where (k->>'contrato_id')::uuid=pg_temp.contrato(1)
    and (k->>'equivalente_pen')::numeric=62000 and k->>'fecha_comercial'='2026-10-05')
  from (select crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31') datos) q),
  'Citas conserva importe, fecha y operación del último corte completo durante una corrección pendiente');
select jsonb_build_object('tc_fixture','citas-pendiente','payload',crm.citas_gerencia_consulta_v2_fn('2026-10-01','2026-10-31'));
