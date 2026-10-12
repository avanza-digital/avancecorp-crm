---
tags: [crm, coordinacion, permisos, facturacion, ranking]
fecha: 2026-10-12
estado: preparado y verificado localmente; no publicado
---

# Coordinación — Facturación y Ranking en lectura

Miguel autorizó que Coordinación consulte Facturación y Ranking de toda la empresa,
con filtros y desgloses numéricos, conservando Repartir leads como inicio. Sin acceso
a fichas de clientes, PII, identificadores de clientes/leads/contratos ni nuevas escrituras.

Implementación local: capacidades `verFacturacion` y `verRanking`; ruta Ranking
permitida expresamente sin habilitar las demás vistas de Gerencia. Proyección de
nombres y jerarquía `crm.equipo_reportes_fn`, separada del equipo operativo y del boot
de Repartir. La migración `20261012165115_crm_coordinacion_reportes_lectura.sql` añade
un helper de Coordinación activa y otro de fotos cerradas, sin alterar
`es_lector_global`, `vendedor_ids_visibles`, policies, fórmulas ni permisos de escritura.
Todo detalle de Facturación para Coordinación llega enmascarado.

Verificación: 6.624 tests de app PASS; tipos, build y bundle PASS; 38 E2E existentes
de Repartir/Facturación y tres nuevos PASS. Matriz PostgreSQL exclusiva: 120 comparaciones
de otros roles, 24 lecturas globales, tres páginas sin PII, estados de baja y ACL PASS;
reversa y reaplicación PASS. Dos reviews independientes evaluados por el PRIMARY.
El gate integral detecta copias preexistentes ` 2.*`; duplicación sin ellas 0,43 % PASS.

Producción **sin modificar**. Matriz HTTP/Auth general, advisors y publicación
pendientes del ciclo de release en rama Supabase. La publicación exige invocación
humana de `$release-crm` según `CRM-Avance-Corp/CLAUDE.md`. Las huellas del catálogo
deben cotejarse nuevamente: otra tarea de conversión puede cambiar esos cuerpos.

Kit y límites: `CRM-Avance-Corp/supabase/scripts/coordinacion-reportes/LEEME.md`.
Las bajas del banco fabrican estados con guards suspendidos solo durante esa siembra,
restaurados antes de consultar; no verifican el comando real de offboarding.

Relacionadas: [[Facturacion - auditoria completa (2026-10-08)]],
[[Ranking - origen acreditado y desglose de cartera (2026-09-28)]], [[Inicio]].
