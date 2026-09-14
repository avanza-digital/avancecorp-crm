---
tags: [crm, tasas, publicacion]
actualizado: 2026-09-14
---

# Rentabilidades menores a 15 — publicación autorizada

Miguel indicó «haz depoloy» después de la pausa y autorizó usar la organización
actual de PortalAvanceCorp para un banco temporal hasta US$1, eliminándolo al
terminar. La autorización de despliegue sigue vigente; no pedirla nuevamente.

Estado de preparación: candidata instalada únicamente en la rama exclusiva
`tasas-inferiores-20260914` (`gvstgldssatszdovumhe`), versión `20260914174353`.
El archivo fuente permanece `20260914042114_crm_tasas_inferiores_nuevas_inversiones.sql`.
La base reproduce 637 funciones y 281 migraciones actuales, incluidas dos F8;
propietarios, permisos, RLS y disparadores coinciden. Se usan datos ficticios y
configuración de negocio vigente, sin clientes reales. La candidata no añade
avisos de seguridad; solo varían las fechas de observación de los avisos previos.

Main integra `avancecorp/main` en `8c185f6`, conservando F8 y Facturación. Las
3.540 pruebas del frontend pasan con dos procesos; la primera tanda tuvo tiempos
agotados con concurrencia automática. No se ampliaron timeouts ni cambiaron tests.
Los checks de scripts, configuración de release, worker y duplicación pasan.

Regla: nuevas inversiones admiten desde 0,01 % hasta la base vigente, con dos
decimales. Superar la base requiere la aprobación exacta; una solicitud pendiente
sigue bloqueando la conversión. Renovaciones y contratos emitidos conservan sus
protecciones. [[Rentabilidades menores a 15 - entrega local sin deploy 2026-09-14]]
contiene el ensayo local, las dos revisiones de Claude y sus correcciones.

Pendientes: comparación RLS antes/después, ensayo remoto de tasas y HTTP, igualdad
Main local/remoto, artefacto final de ese commit, merge y verificación productiva,
publicación en Hostinger y eliminación de la rama propia. El respaldo frontend
anterior se verificó contra el `version.json` público. No publicar migraciones
pendientes de otros trabajos ni ejecutar `db push` general.

## Integración final previa a publicar

Citas se instaló en paralelo: el banco incorporó sus cinco migraciones por rebase.
Referencia final: 643 funciones / 286 migraciones productivas; candidata: 644 / 287.
Las cuatro funciones de tasas seguían con sus huellas originales en producción.
El ensayo específico remoto se repitió con Citas/F8 presentes: siete tasas, cuatro
regresiones, tres escenarios concurrentes, permisos y reversa antes/después del
uso PASS. Frontend integrado: 3546 tests con cobertura y 16 E2E de tasas/Citas PASS.
La comparación general anterior a Citas mantiene exactamente 42/1828 fallos en
ambos lados. Es PASS de no regresión, no PASS global. Incluye un test R1 que espera
observación aunque la política vigente ya usa enforcement, y contratos antiguos
de métricas/identidad. No se cambian permisos ni políticas para hacerlos pasar.
La comprobación HTTP y la publicación aún están en curso.
