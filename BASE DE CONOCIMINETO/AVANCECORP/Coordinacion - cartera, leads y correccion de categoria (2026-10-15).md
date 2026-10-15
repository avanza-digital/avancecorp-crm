---
fecha: 2026-10-15
estado: preparado en copia aislada; no publicado
tags: [crm, coordinacion, permisos, conversion, ranking]
---

# Coordinación — cartera, Leads y corrección de categoría

Miguel pidió habilitar la cartera de clientes de toda la empresa y el módulo Leads para
Coordinadora. También autorizó que Admin, Gerencia y Coordinadora corrijan la categoría de
inversión Nuevo/Renovación/Upgrade cuando el analista la registró mal, aunque difiera del
registro original de operación. Confirmó expresamente que debe corregir **conversión y ranking**.

La categoría se corrige por contrato Avance, con motivo y auditoría. Se conservan hechos
financieros y plazos originales; no se fabrica capital ni una nueva oportunidad de acreditar
fuera de plazo. La categoría manual corregida prevalece sobre el cálculo automático de
Renovación con adicional como Upgrade; sin corrección sigue rigiendo esa regla de octubre.
Los meses sellados permanecen protegidos. Coordinación consulta Leads y clientes sin adquirir
escrituras generales, banca, archivos o postventa; mantiene el reparto ya autorizado.

Implementación y pruebas en `CRM-Avance-Corp/supabase/scripts/permisos-coordinacion/`.
Migraciones preparadas `20261015211217` y `20261015212939`; no aplicadas a producción.
74 checks SQL y carreras de revocación/sello PASS. Cierre de verificación en `VERIFICACION.md`.

Relacionadas: [[Categorización de inversiones - Nuevo Renovación Upgrade]],
[[Coordinacion - Facturacion y Ranking en lectura (2026-10-12)]],
[[Conversion - adicional de renovacion como upgrade probado en branch (2026-10-14)]],
[[Inicio]].
