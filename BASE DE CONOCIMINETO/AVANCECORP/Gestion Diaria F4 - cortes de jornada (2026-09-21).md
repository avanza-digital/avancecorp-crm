---
tags: [crm, gestion-diaria, f4, cortes]
estado: implementada y verificada localmente — sin publicación ni activación
fecha: 2026-09-21
---

# Gestión Diaria F4 — Cortes de jornada

Miguel aclaró: implementar la etapa 3 y preparar su publicación. La entrega
incluye política versionada inicialmente OFF, cálculo del servidor y contrato
de lectura compatible. No incluye pop-up/aplazamiento (etapa 4), pantalla de
configuración (etapa 5) ni activación (etapa 6).

Conserva las decisiones de [[Gestion Diaria F4.1 - banco humano y reglas de cortes (2026-09-21)]].
La base de las 11:30 no crece con llamadas posteriores; el segundo corte es
acumulado, no llamadas extra. Cartera abierta y jerarquía se evalúan al consultar:
el histórico no es una foto inmutable. Ventanas `[medianoche Lima, corte)`.
El sábado el primer aviso puede recuperarse antes de las 13:00.

Código y evidencia en `CRM-Avance-Corp/docs/gestion-diaria/F4-CORTES-JORNADA.md`.
Candidato `20260921214018_crm_gestion_diaria_cortes.sql`, SHA-256
`8563bf8bf66e97a4e328d54582bbcf74e17f63d3d6056c6f9ae2dc4b9f940ea5`.
Miguel autorizó sólo banco local `gestion_diaria_f4_vista_chvrqh` y reversa.
Ensayo completo PASS: negocio y RLS por identidad, paridad supervisor/gerencia/global,
umbrales de puertas F3/F4, cartera vacía/cerrada y revocación, calendario Lima,
15 mutantes, regresiones, tipos, censo y reversión de funciones. Base termina
sin objetos candidatos; fixtures revertidos y auditoría local conservada.

Aplicación: 4.073 tests y `npm run check` PASS; scripts y siete tests offline PASS.
Dos reviews Claude: último CHANGES_REQUESTED; PRIMARY incorporó permisos por
columna, autor/orden futuro, guardas y pruebas. Descartó hipótesis con evidencia:
F3 sí pasa medianoche Lima y umbrales legacy sí conserva su sello. No se pidió
otro review para obtener PASS. HTTP completo y carga/concurrencia con roster
productivo siguen pendientes antes de activar; local probó 6.000 llamadas por
analista con cartera en roster de tres. No se atribuye aprobación total a Claude.

La etapa 3 no cambia todavía la pantalla. Próximo producto: etapa 4, pop-up y
reconocer/posponer en servidor. Después editor gerencial y validación/activación.
Publicación requiere SQL exacto autorizado, integración en Main sin pisar trabajo
concurrente y `$release-crm`; no hubo push, PR, despliegue ni activación en esta entrega.

## Guardado y punto de retoma

Miguel pidió guardar el plan y continuar aproximadamente una hora después.
La recomendación registrada es publicar la etapa 3 por separado **apagada**,
después de cerrar la matriz HTTP/Auth en pruebas, preparar la recuperación
productiva y verificar integración/artefacto desde Main = `avancecorp/main`.
Después se necesitan autorización del SQL exacto y el flujo humano `$release-crm`.
La reversa local no se debe ejecutar directamente en producción. El guardado
no autoriza despliegues ni activación durante la pausa.

La implementación está guardada en `19f8c180`, rama
`codex/gestion-diaria-typesafe-piloto`, en el taller existente. Al volver,
retomar los pendientes de publicación, no reconstruir la etapa 3 ni empezar
automáticamente la etapa 4. Secuencia: publicar la base OFF → avisos/reconocer/
posponer (4) → configuración (5) → validación integral y activación (6).
Estado y lista completa en el último punto de control del plan principal:
`CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
Las pruebas consignadas son las de la entrega previa; este guardado sólo
actualiza documentación. TypeSafe continúa separado y sin activar en el CRM.

Relacionadas: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] · [[Inicio]].
