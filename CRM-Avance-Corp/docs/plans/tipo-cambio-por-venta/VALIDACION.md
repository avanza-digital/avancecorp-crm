# Correspondencia de aceptación y evidencia

Implementación candidata local, no activación. Detalles, conteos y límites en
[ESTADO.md](ESTADO.md); aprobación operativa pendiente en ACTIVACION.md.

| Requisito de PLAN.md | Evidencia ejecutada |
| --- | --- |
| USD20k a3,40 permanece68000; segunda10k a3,10 suma99000 | prueba.sql, prueba-cortes.sql, prueba-escritores.sql; verificar-http-local.mjs con Auth y F4 reales; capital-valorado.spec.ts y pruebas de Citas/CSV. Incluye sello y cotización posterior. |
| PEN sin conversión, centavos y revisión por corrección | Oráculo numeric y CHECK en SQL; corrección nativa PEN/USD y cooperativa; sumas frontend en céntimos. |
| Fecha comercial y carga tardía | Cortes históricos por fecha, fuentes/firmas canónicas, corrector autorizado y F4 nativo. El trigger legado usa LEAST(inicio, registro Lima), no se le inventa otra política. |
| Venta comercial preoctubre imputada en octubre | prueba-legado.sql y simulacion.test.ts: TC legado al fin del mes original, reconstruida_legada, reimputación no crea revisión; septiembre intacto. |
| Pares incompletos, compra sola, menos de siete, ampliar ventana, feriado | consolidacion.test.ts: 16/32/64, confirmación común en/tras D y promedio solo hasta D; pendiente sin dato, política legada separada. Nueve fechas reales reconsultadas BCRP. |
| Caída, reservas, reintentos y recuperación idempotente | prueba.sql, handler.test.ts, Auth HTTP F4 pendiente y servicio resolve/reconcile; sin tasa de emergencia ni equivalencia cero. |
| Último corte completo y ausencia de primer corte | SQL y fixtures de activo/pendiente/sin-corte/sellado; Ranking, Metas, Facturación y Citas modelo/UI/E2E desktop/mobile; importe/personas/metas/identidad de una publicación. |
| Renovación/upgrade/desglose y autor/analista fuera de metas | prueba-atribucion.sql 16 aserciones, paridad de once meses antes/después y guardas de fecha/periodo. Stock una vez; partes no adquieren otra tasa. |
| Fecha faltante en cooperativa | Fuente no genera valor consolidado sin fecha; cobertura/preflight bloquea completo. No se usa digitación como fecha comercial acreditada. Censo actualizado sin faltantes. |
| Anulación/deuda/arrastre/ajuste de venta anterior | ATR-4 nativo sanciona conversión, conserva capital; prueba-atribucion/cortes conserva esa asimetría. Actualmente ajustes monetarios son cero. Preflight/sello rechaza deuda monetaria sin origen; no repartir deudas agregadas ni fabricar ajustes parciales USD. |
| Metas futuras con USD | Política vigente publica objetivo PEN. Se rechaza USD no cero sin equivalente fijado; prueba-cortes.sql. Habilitar metas USD requeriría otra decisión/implementación explícita. |
| Reasignación/baja/supervisión y PII | Proyección nativa preservada, ámbitos actuales revalidados, matriz Auth HTTP11 cuentas/ocho ámbitos, Citas SQL tras reasignar, Coordinación y Directorio sin PII. |
| Dos workers y fuente en edición | concurrencia-local.mjs: revisión única y SKIP LOCKED con relectura; identidad fuente/fecha/política única. |
| Cierre/corrección en ambos órdenes | concurrencia-cierre-local.mjs observa esperas reales y revisión exacta del sello; rechazo de reescritura cuando gana cierre. |
| Cierre sin cobertura y atasco24h | Ciclo nativo con reloj simulado, rollback de TODOS los componentes, estado atascado; 600 ventas conocidas no se materializan bajo bloqueos, se espera al worker. Cron ausente/pausado/activo compatible ensayado por metadata, sin scheduler nuevo. |
| Inmutabilidad después de sello y reversa | Sello apunta al corte exacto; lectura incluso suspendida y después de otra cotización; UPDATE/DELETE/TRUNCATE rechazados. Reversa de persistencia solo en fundación vacía. |
| Septiembre/agosto y rango mixto | Paridad de RPC originales; API agosto-octubre segmenta meses. UI navega agosto/septiembre/octubre y semana Sep28–Oct4, total185100 con TC legado3,5 y operación3,4; escritorio y móvil. La UI no tenía selector arbitrario de tres meses: no se añadió otra función ajena. |
| Exportaciones y consumidores | MAPA-CONSUMIDORES.md, Citas CSV comparte modelo y corte; estimaciones, saldos y monedas originales conservan significado. No existe CSV productivo de Ranking/Metas/Facturación que requiera inventar una función nueva. |
| Seguridad/schema/tipos/advisors/release | Huella public íntegra, RLS/RPC HTTP; tipos completos oficiales, Advisors antes/después sin WARN/ERROR nuevos; check integral app y preflights. Release preparado, sin publicar, conforme a ACTIVACION.md. |

La aceptación local no sustituye censo/preflight frescos, integración con main,
publicación humana, secretos/cron y verificación de solo lectura en producción.
Esos son pasos de la activación futura, no acciones autorizadas por este trabajo.
La comparación nativa por analista, avance y posición de la captura actual está
en [SIMULACION-ACTUALIZADA.md](SIMULACION-ACTUALIZADA.md).
