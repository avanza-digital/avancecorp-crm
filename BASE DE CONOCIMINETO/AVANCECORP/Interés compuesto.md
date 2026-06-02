---
tags: [feature, contratos, finanzas]
actualizado: 2026-06-01
---

# Interés compuesto

**Implementado en la auditoría pre-lanzamiento (2026-05-24).** Los contratos soportan **interés simple y compuesto**.

- **Compuesto:** capitaliza anual, años exactos, **pago único al vencimiento**.
- El admin genera un cronograma de **1 cuota** + proyección año a año.
- El cliente ve la **curva compuesta** en el dashboard (gráfico SVG).
- Vive en la relación `contratos → cronograma_pagos` ([[Arquitectura del portal]]).

## Notas relacionadas
[[Notificaciones de pagos]] · [[Arquitectura del portal]] · [[Inicio]]
