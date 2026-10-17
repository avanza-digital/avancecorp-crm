# Alcance de capital confirmado y otras medidas

Auditoría local de código, 16/10/2026. Una conversión PEN/USD por sí sola no
prueba que el dato sea producción confirmada. La fuente y la medida deciden.

| Superficie | Fuente y significado | Tratamiento desde octubre |
| --- | --- | --- |
| Ranking Gerencia/Equipo y fuera de ranking | Cumplimiento v2, personas y producción del corte | Equivalentes persistidos; detalle pide el mismo corte. La rama de conversión mensual solo admite ausencia de valoración. |
| Metas, resúmenes Gerencia/analista/supervisor/mando/móvil | Cumplimiento; seis dimensiones de moneda/categoría | `capitalComercialEnSoles` y `metaComercialEnSoles` usan valor almacenado y objetivo PEN. Los desgloses por moneda conservan importes originales. |
| Facturación, totales y cifras pulsables | Facturación v2; lista v3 con mapa de cortes por mes | Importes individuales, tasas y fechas almacenados; detalle conserva referencia al abrir/paginar. Tramo anterior a octubre usa su corte mensual legado. |
| Citas: ticket y proyección mensual, CSV de avance | Stock confirmado sin anulados, identidad única por persona | RPC v2 y corte, incluidos persona y operación; proyección sigue siendo estimada. Detalle en INTEGRACION-CITAS.md. |
| Gráficas de capital por mes | `metricas_capital_mes_fn`; episodios agrupados por moneda/categoría | Importes originales en pestañas PEN/USD, sin total convertido ni dependencia de TC. No son otro equivalente comercial. |
| Equipo en proceso, Directorio operativo, pipeline y cartera de leads | Leads abiertos y monto estimado | Estimaciones: conservan su conversión indicada, sin crear valoraciones de venta. |
| Derivaciones del equipo | `crm_reporte_derivaciones_equipo_supervisor`: suma `monto_estimado` de episodios de derivación por moneda | Capital estimado repartido, no ventas; conserva su regla. |
| Citas: lista y CSV de citas | Monto estimado del lead | Estimación, diferente del CSV de avance confirmado. |
| Pagos, vencimientos, saldos y PDF contractual | Movimientos financieros o documento en moneda original | No se sustituyen por producción comercial equivalente. |
| Otros CSV localizados | Actividades, resultados de bases cargadas | No exportan un equivalente de producción confirmada. |
| Prototipos de Citas | Datos de demostración fuera del flujo productivo | No son fuentes de producción real. |

Referencias de código: `lib/capital-unificado.ts`, `lib/conversion-vendedores.ts`,
`lib/objetivos.ts`, `lib/facturacion.ts`, `components/citas/avance.ts`,
`components/citas/avance-csv.ts`, `screens/facturacion/parametros-de-cifra.ts`,
`screens/hoy/graficas-gerencia.tsx` y `screens/derivaciones.tsx`.

`totalEnSoles` permanece como operación legada o estimación. En lectores activos
de capital confirmado, la falta del primer corte o de una valoración no permite
caer a una tasa actual. El ranking fuera de población ya usaba las personas del
corte: se añadió una regresión para probar su invariancia sin cambiar esa rama.

No se encontró un CSV productivo existente de Ranking/Metas/Facturación que
necesitara añadirse como función nueva. No se inventa un exportador adicional.
Matriz Auth/HTTP, E2E de rangos mixtos y correspondencia integral del PLAN
completados localmente; evidencia y límites en ESTADO.md y VALIDACION.md.
