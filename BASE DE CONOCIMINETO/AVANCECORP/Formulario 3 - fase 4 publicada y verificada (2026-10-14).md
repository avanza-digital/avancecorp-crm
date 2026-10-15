# Formulario 3 - fase 4 publicada y verificada

Estado: **CRM publicado y verificado; importación real todavía apagada**. Publicación comprobada el 14/10/2026 a las 23:17 Lima (15/10, 04:17 UTC). Continúa [[Formulario 3 - plan de integración en CRM y activación (2026-10-14)]].

El CRM recibe, guarda y muestra la campaña **Formulario 3**, y permite filtrarla en Cartera. Conserva el canal **FORMULARIO**, su turno, reglas de conversión y circuito de Coordinación. Las coincidencias mantienen responsable e historial; no se reclasificaron los 3.687 leads existentes. Los clientes/reingresos llevan campaña en su actividad según el contrato probado, sin prometer nuevas altas por cada fila.

## Publicación y evidencia

- [PR 280](https://github.com/avanza-digital/avancecorp-crm/pull/280), fuente `0fa4a39892c1b38946d06b7a0e03d57b83b013c9`. Main limpio e igual al remoto al construir. Build vivo `build-20261015T041350920Z`.
- Migraciones exactas `20261014210146` y `20261014215453`; después, importador v24 con JWT exigido; por último, frontend. Se verificaron 124 archivos web contra el artefacto y el acceso público en Chromium/Docker.
- App 6.707 tests y gates relevantes PASS; 3 E2E específicos, 98 SQL y 18 HTTP/Auth en rama, más 2 E2E con el ZIP anterior contra la base nueva. La fase 3 ya había probado el recorrido completo, reparto, duplicados, recuperación y avisos. No se atribuyen los ensayos de rama a producción.
- En producción: columna y permisos correctos, RLS activo, firma única de cartera con 15 argumentos; lectura antigua/nueva bajo cuatro contextos SQL authenticated en READ ONLY. No fueron sesiones HTTP humanas de producción.
- Claude revisó la fase; Codex resolvió sus observaciones con evidencia. Se conservan dos advertencias históricas del gate (analistas inactivos y clientes sin domicilio) sin modificar datos para ocultarlas.
- La rama temporal y sus credenciales se retiraron. El ZIP anterior y su manifiesto se conservan para recuperación compatible; no se revierte SQL ni se borran datos automáticamente.

[Acta técnica y resultados](../../CRM-Avance-Corp/docs/N8N-FORMULARIO3-FASE4-PUBLICADA.md) · [Figma actualizado](https://www.figma.com/board/JB4jRdmLXZXS0hBhEHxRbV?node-id=2-34).

## Siguiente paso

n8n `BjI5m1PKVWhO0NDb` permanece inactivo, con envío false y nodo HTTP deshabilitado. Aviso productivo manual 52 SUCCESS enviado a Miguel. No se cargaron filas reales; las 127 filas iniciales deben volver a leerse antes de importar.

La fase 5 probará **una fila real**, con cron apagado, confirmación del CRM, campaña/reparto/recibo y repetición segura. Antes debe verificarse la poda del contenido fallido del VPS (política: máximo siete días) o desactivarse ese almacenamiento; todavía no se ha verificado. Lotes de hasta 25 y activación periódica quedan para fase 6.

Relacionado: [[Formulario 3 - fase 3 integrada y validada sin publicar (2026-10-14)]] · [[n8n - Formulario 3 preparado y avisos conectados (2026-10-14)]] · [[Canales de origen de leads CRM]].
