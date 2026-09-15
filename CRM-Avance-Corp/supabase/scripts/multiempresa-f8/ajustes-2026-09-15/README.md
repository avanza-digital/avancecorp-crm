# F8 — ensayo remoto y corrección de conflictos

Estado: banco autorizado verificado; publicación pendiente. Continúa la [entrega inicial](../ajustes-2026-09-14/README.md).

El banco Supabase propio usa datos ficticios y las definiciones actuales de producción. La copia incluye sus 287 migraciones iniciales y la actualización concurrente de PDF v9 (288). Las dos migraciones F8 conservan sus bytes aprobados. Una tercera migración corrige un bloqueo detectado por HTTP: confirmar o corregir una revisión antigua responde PT409 / HTTP 409 en vez de lanzar el 40001 que PostgREST 14.5 reintenta indefinidamente.

## Comprobaciones

- PASS: 62 casos de lectura/Auth, mismos permisos e información histórica; 37 fichas y 197 condiciones históricas NULL. Ninguna ficha del ensayo necesitó una segunda página; no se atribuye cobertura HTTP multipágina.
- PASS: 18 casos HTTP reales de alta COOPAC, plazos/porcentaje anual, corrección, confirmación, idempotencia, comprobante y acceso por rol. Revisión antigua: HTTP 409 en 174 ms al corregir y 158 ms al confirmar.
- PASS: SQL final posterior al rebase, siete actores y siete enlaces demo/fusión, condiciones/reintentos/permisos; volumen sintético corregido entre 1,46 y 1,61 s, anterior agota ocho segundos. Incluye conexión/fixtures; no es latencia productiva.
- PASS: 20 casos adicionales, incluyendo dos confirmaciones simultáneas. Crean una sola inversión: una responde éxito inicial y la otra reintento idempotente. Un intento de cambiar empresa conserva el rechazo 22023 anterior.
- PASS: cliente antiguo con once argumentos nombrados y reintento, condiciones históricas NULL y fecha original. Su wrapper de confirmación también devuelve PT409 al recibir una revisión obsoleta.
- PASS: guardas de la tercera migración, search_path vacío, delta exacto de cuatro códigos, propietario/ACL/configuración intactos y rollback íntegro si la segunda función cambia.
- PASS: actualización del banco para conservar PDF v9. Las otras 18 Edge conservan su bundle; los nueve archivos del PDF son idénticos byte a byte al padre y al repositorio. El EZBR recompilado tiene una huella distinta; no se declara identidad binaria.
- PASS: check integral del Main a38f267 (3.581 tests, lint, tipos, cobertura, build, bundle y duplicación). El test adicional del código PT409 pasó aparte; el gate de push repetirá la suite.
- PASS: cuatro preflights backend y tipos afectados generados desde la rama. Advisors: 209 antes / 210 después; única advertencia adicional, protección de contraseñas filtradas, ya existe en producción. No se modificó Auth.
- NOT RUN: matriz RLS general, cuya semilla no corresponde a este banco. Se usa la matriz específica SQL/Auth/Storage y se conserva esta limitación.

## Migraciones

1. `20260914213634` → ledger de rama `20260915010349`: Cartera eficiente.
2. `20260914213928` → `20260915010350`: plazo y rentabilidad COOPAC.
3. `20260915015315`: conflictos de revisión sin reintentos infinitos.

[Huellas exactas](sql-huellas.json). Las migraciones anteriores permanecen inmutables. El merge directo del MCP aplica el delta del historial; no se usa el flujo Dashboard que genera otro diff. Las 287 entradas iniciales coinciden íntegras; el rebase segmentó en la rama la nueva entrada PDF conservando su SQL. Producción debe conservar sus 288 entradas originales y el PDF concurrente. Las tres migraciones forman una entrega: si la tercera falla, no se publica frontend y se resuelve la deriva mediante una migración revisada; no se borra información.

## Revisión y límites

Claude emitió CHANGES_REQUESTED sobre hipótesis del proceso de publicación y PASS sobre la nueva corrección PT409. La [evaluación del PRIMARY](EVALUACION-REVIEW.md) documenta las decisiones y fuentes. El banco tiene seis diferencias gestionadas respecto al padre (CHECK equivalentes, pg_net/event trigger/publicación interna); nunca se añadieron al historial ni al payload de merge.

G7-R01 requiere comprobar Cartera/ficha en producción tras publicar. G7 mantiene pendiente la conformidad visual del solicitante y sus observaciones. Los datos reales siguen cambiando con la operación diaria.
