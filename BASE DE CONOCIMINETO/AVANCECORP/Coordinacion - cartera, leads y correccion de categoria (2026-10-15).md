---
fecha: 2026-10-15
estado: publicado y verificado
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
Migraciones `20261015211217`, `20261015212939` y `20261015224848` aplicadas por merge de rama
el 15/10 a las 18:58 Lima, tras autorización explícita. 93 SQL + 61 Auth/PostgREST PASS;
1.110 funciones/propietarios/ACL idénticos a la rama validada. Se conservaron 818 contratos,
165 operaciones, importes y categorías. Rama temporal eliminada. Advisors: cero WARN/ERROR
nuevos y dos INFO esperados de la auditoría privada. Gate de realidad PASS (dos divergencias
preexistentes); matriz general seed-demo NOT RUN, matriz focalizada PASS.
Frontend sobre Main con #299: 6.966 tests y Docker completo 427 PASS / 26 omitidos / 0 fallos.
Publicado a las 19:28 Lima en https://crm.miavance.com. Fuente `d1796dd4`, build
`build-20261016T002734754Z`; ZIP `crm-20261016T002735Z-d1796dd4cf8c.zip`. Smoke 126 archivos
idénticos, incluidos los 123 JS/CSS. Coordinación comprobada en Chrome: Leads, 664 clientes
sin filtros y formulario de categoría en contrato Avance; cancelado sin modificar datos.
Acta exacta: `CRM-Avance-Corp/docs/COORDINACION-CARTERA-CATEGORIA-PUBLICADA.md`.
Detalle en `VERIFICACION-CLOUD.md`.

Relacionadas: [[Categorización de inversiones - Nuevo Renovación Upgrade]],
[[Coordinacion - Facturacion y Ranking en lectura (2026-10-12)]],
[[Conversion - adicional de renovacion como upgrade probado en branch (2026-10-14)]],
[[Inicio]].
