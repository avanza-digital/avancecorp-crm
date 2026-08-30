-- TRINQUETE de la analitica de leads y citas (P-055 F6.a).
-- El detalle PRIMERO y el veredicto AL FINAL: `db query` devuelve SOLO las
-- filas de la ultima sentencia (y no transporta los raise notice).
select tipo, objeto, declarada, huella_ok
  from private.contadores_crudos_leads_citas()
 order by declarada, huella_ok, tipo, objeto;

select private.assert_analitica_leads_citas() as veredicto;
