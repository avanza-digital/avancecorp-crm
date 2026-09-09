# UI y UX de Gerencia — Avance Corp

> **Actualización 06/09/2026 (tarde).** Miguel descartó el plan anterior y el trabajo de Figma previo. Lo vigente es el **[plan de mejora del usuario Gerencia](PLAN-GERENCIA-2026-09-06.md)**, basado en el CRM publicado y en `UI-UX.pdf`, con evidencias en [08-produccion-2026-09-06](08-produccion-2026-09-06/) y dos archivos **nuevos** de Figma: [flujos (FigJam)](https://www.figma.com/board/TAdFQI94B2DABzSLU8I9kI) y [mockups (Design)](https://www.figma.com/design/1OD5qEmCz7CI1IuNBm642E). Las carpetas 01–07 quedan como antecedente.

Punto de entrada del trabajo `AVC-UX-GERENCIA-FIGMA-20260905-R1`. Organización actualizada el 6 de septiembre de 2026.

**Objetivo:** un dashboard dinámico y sencillo de leer comercialmente, conservando la identidad, el desarrollo y las librerías del CRM.

**Estado:** reinicio de la propuesta visual solicitado por Miguel. Se toma su CRM actual como referencia principal y se prepara una nueva composición en Figma antes de extender código. El intento local está [conservado aparte](07-implementacion/bloque-a-2026-09-06/intento-no-aprobado/README.md); aún no se ha restaurado el frontend activo. Se mantienen el plan por fases y los componentes útiles.

## Abrir primero

- [Reinicio visual y siguiente paso](PROXIMO-PASO.md).
- [Registro de decisiones](01-plan/DECISIONES.md).

- [Antecedente: Resumen y Conversiones, escritorio y móvil](04-propuestas/revision-ux1-ux2-2026-09-06/README.md).
- [Qué sigue y qué falta para cerrar F0](PROXIMO-PASO.md).
- [Plan maestro por fases](01-plan/PLAN-MAESTRO.md).
- [Índice de Figma y estado de las propuestas](ENLACES-FIGMA.md).
- [Auditoría F0 completa](02-f0-auditoria/informe-auditoria.md).
- [Qué desarrollo y componentes reutilizamos](03-componentes/README.md).
- [Continuidad para retomar el trabajo](06-continuidad/AVC-UX-GERENCIA-FIGMA-20260905-R1.md).

## Carpetas vigentes

| Carpeta | Contenido |
| --- | --- |
| [01-plan](01-plan/README.md) | Plan maestro, origen de la decisión y documento UI-UX (2). |
| [02-f0-auditoria](02-f0-auditoria/README.md) | Informe, hallazgos, pantallas, capturas y continuación de F0. |
| [03-componentes](03-componentes/README.md) | Inventario, catálogo UX1 y correspondencia con el CRM. |
| [04-propuestas](04-propuestas/README.md) | Accesos a las propuestas de Figma y sus imágenes exportadas. |
| [05-validacion](05-validacion/README.md) | Guion de prueba, línea base y verificaciones técnicas. |
| [06-continuidad](06-continuidad/README.md) | Serial, estado vigente y memoria para la siguiente sesión. |
| [07-implementacion](07-implementacion/bloque-a-2026-09-06/intento-no-aprobado/README.md) | Evidencias de implementación, línea base e intento visual no aprobado conservado. |

## Antecedentes conservados

| Carpeta | Contenido |
| --- | --- |
| [90-auditoria-inicial](90-auditoria-inicial/informe-auditoria.md) | Auditoría anterior al replanteamiento UI-UX (2). |
| [91-figma-inicial](91-figma-inicial/F0-gerencia.md) | Preparación inicial de Figma, biblioteca y auditoría histórica. |
| [92-desarrollo-anterior](92-desarrollo-anterior/seguimiento.md) | Avances G-F1–G-F4, propuestas iniciales, capturas y registros. |
| [99-organizacion](99-organizacion/README.md) | Mapa de movimientos y comprobaciones de esta organización. |

Los documentos de decisiones son accesos directos a sus notas del Vault, para mantener una única edición. Las carpetas de evidencias se trasladaron aquí; los enlaces anteriores de `output/` siguen funcionando. Los registros técnicos dentro de `calls/` y `state.json` conservan la trazabilidad de Figma.

## Reglas para continuar

1. Leer el plan y la continuidad antes de cambiar el alcance.
2. Partir de los componentes, librerías, datos y recorridos existentes. Justificar cualquier variante nueva.
3. Distinguir auditoría del CRM actual, propuesta visual, implementación y validación.
4. Guardar las siguientes entregas en esta carpeta y actualizar su índice; las decisiones de negocio permanecen en el Vault.
5. Mantener el alcance de diseño y frontend, sin cambiar backend, permisos ni fórmulas. La publicación requiere su autorización correspondiente.
