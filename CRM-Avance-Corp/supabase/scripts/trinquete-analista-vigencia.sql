-- TRINQUETE de la autoridad del analista (P-055 F5.a).
--
-- 🔴 DOS TRAMPAS DEL CANAL, las dos pagadas en este proyecto:
--   1. `supabase db query` NO transporta los `raise notice`: un gate que buscara
--      su OK en un aviso estaria siempre verde por vacio. El veredicto viaja
--      como FILA.
--   2. Y devuelve SOLO las filas de la ULTIMA sentencia del archivo. Por eso el
--      detalle va PRIMERO y el veredicto va AL FINAL: al reves, el gate no ve
--      nunca su fila de OK (medido el 2026-08-30, tras publicar).

-- El detalle, para leerlo de un vistazo.
select tipo, objeto, declarada, huella_ok
  from private.puertas_analista_sin_vigencia()
 order by declarada, huella_ok, tipo, objeto;

-- El veredicto: ESTA es la fila que el gate exige ver.
select private.assert_analista_vigencia() as veredicto;
