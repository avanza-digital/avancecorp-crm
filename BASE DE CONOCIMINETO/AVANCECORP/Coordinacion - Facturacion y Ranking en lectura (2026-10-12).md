---
tags: [crm, coordinacion, permisos, facturacion, ranking]
fecha: 2026-10-12
estado: publicado y verificado; rama temporal eliminada
---

# Coordinación — Facturación y Ranking en lectura

Miguel autorizó que Coordinación consulte Facturación y Ranking de toda la empresa,
con filtros y desgloses numéricos, conservando Repartir leads como inicio. Este permiso
de reportes no habilita fichas ni PII o identificadores de clientes/leads/contratos
en Facturación/Ranking, ni nuevas escrituras.

Implementación publicada: capacidades `verFacturacion` y `verRanking`; ruta Ranking
permitida expresamente sin habilitar las demás vistas de Gerencia. Proyección de
nombres y jerarquía `crm.equipo_reportes_fn`, separada del equipo operativo y del boot
de Repartir. La migración `20261012165115_crm_coordinacion_reportes_lectura.sql` añade
un helper de Coordinación activa y otro de fotos cerradas, sin alterar
`es_lector_global`, `vendedor_ids_visibles`, policies, fórmulas ni permisos de escritura.
Todo detalle de Facturación para Coordinación llega enmascarado.

Verificación final: app limpia `npm run check` PASS, 413 archivos / 6.640 tests,
tipos, build, bundle y duplicación 0,43 %. E2E Docker integrado 36 PASS. Suite
completa sobre bundle de desarrollo: 405 PASS / 2 FAIL / 26 SKIPPED; los dos casos
dependían de fuentes exclusivas del servidor Vite y, repetidos con ese servidor,
pasaron ambos. Matriz SQL: 120 comparaciones de otros roles, 24 lecturas globales,
tres páginas sin PII, bajas y ACL PASS; reversa/reaplicación PASS. Dos reviews
independientes evaluados por el PRIMARY. Matriz HTTP/Auth general PASS: 3.900
aserciones, cero fallos, incluido grupo A. F4-e se omite porque sigue sin instalar
en el padre. Oráculos corregidos en PR #258, fusionada en Main el 12/10/2026
a las 23:07 UTC (`01dd5742`). El acta se completó el 13/10/2026.

Publicado el 12/10/2026, 22:53 UTC, junto al cambio de Ver cierres para Coordinación.
Fuente limpia `10e3411deb2288cbf01c81513b63a5c1ca6d9a51`, build vivo
`build-20261012T224322167Z`, ZIP `crm-20261012T224323Z-10e3411deb22.zip`, SHA-256
`265fbb65b89b0ed0527b8a9e36cf9f9a9a494dc65f83f4a915915fc04801b10e`.
Comprobación independiente de portada, versión y 121 JS/CSS: HTTP 200 y huellas
exactas, PASS. Backend `20261012223850 crm_coordinacion_reportes_lectura`: trece
funciones idénticas a la rama ensayada en cuerpo, propietario y permisos.
Se detectó la instalación del trabajo paralelo y se evitó una segunda aplicación.
Advisors: aviso esperado de RPC SECURITY DEFINER con puerta de rol probada;
las advertencias anteriores se conservan. La autorización de rama propia limita
el gasto a US$1; la rama propia se eliminó y se confirmó ausente tras las pruebas.
Coste estimado US$0,0332 de cómputo (2 h 28 min a US$0,01344/h, no factura).

Kit y límites: `CRM-Avance-Corp/supabase/scripts/coordinacion-reportes/LEEME.md`.
Las bajas del banco fabrican estados con guards suspendidos solo durante esa siembra,
restaurados antes de consultar; no verifican el comando real de offboarding.

Relacionadas: [[Facturacion - auditoria completa (2026-10-08)]],
[[Ranking - origen acreditado y desglose de cartera (2026-09-28)]], [[Inicio]].
