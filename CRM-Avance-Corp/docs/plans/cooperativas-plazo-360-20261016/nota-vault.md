---
tags: [crm, cooperativas, contratos, plazo]
estado: implementado-aislado-validado-publicacion-pendiente
---

# Cooperativas: plazo de 360 días confirmado y borrador aislado

Miguel confirmó 12 meses = 360 días corridos para Qorilazo y Prodelco;
cada mes equivale a 30 días. La tasa anual no cambia. Los contratos anteriores
conservan calendario, aun al agregar/corregir condiciones. Nuevos usan dias_360.

SQL exacto aprobado, SHA256 518641adaee9ca85d8eecf50cfe09dd50d79af377cee3613af6a96bac0acd363.
Implementación y evidencia persistidas en
`CRM-Avance-Corp/docs/plans/cooperativas-plazo-360-20261016/README.md`.
No integrado en Main, instalado en producción ni publicado. Copia aislada
porque el checkout compartido contenía trabajo ajeno. No se cambió su rama.

PASS: lint, TypeScript, build, 6.998 unitarias, 29 E2E Docker F5/F6, replay
SQL/reversa, 95 casos Auth/RPC/Storage reales, check:scripts y preflight Edge PASS. Preflight de solo lectura:
74 registros productivos, 49 con condiciones, 0 incompatibles con CHECK nuevo.
Advisors sin hallazgos nuevos: seguridad 380→380, rendimiento 345→332.
Dos reviews Claude CHANGES_REQUESTED; el PRIMARY cerró sus verificaciones con
evidencia, sin pedir un dictamen favorable adicional. Gerencia lee revisión
real del servidor y el cliente ya acepta Prodelco USD con etiqueta correcta.

Miguel aprobó US$0,01344/h en la organización de PortalAvanceCorp. Banco remoto
creado 16/10/2026 20:33:34 UTC y eliminado 22:01:02 UTC, ausencia verificada.
Coste estimado por tarifa ~US$0,02. Sin clientes copiados ni producción alterada.
El historial viejo de rama falló; se reconstruyó a paridad y se eliminó, sin merge.

Pendiente integrar sobre Main vigente, gate RLS integral y E2E completo y
publicación coordinada mediante invocación humana `$release-crm`/`/release-crm`.
Las PWA antiguas pueden aplazar actualización: detener altas durante ventana,
actualizar sesiones y editar/revisar solicitudes antiguas. Recontar tres
solicitudes preparadas observadas antes; no se reescriben automáticamente.

Relacionadas: [[F8 - ajustes de cartera y condiciones COOPAC preparados (2026-09-14)]] ·
[[Upgrade cooperativo separado de reinversion (2026-10-06)]] ·
[[Cierres en cooperativas Qorilazo y Prodelco - plan]].
