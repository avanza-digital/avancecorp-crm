---
tags: [feature, contratos, finanzas]
actualizado: 2026-06-10
---

# Interés compuesto

**Implementado en la auditoría pre-lanzamiento (2026-05-24); estructura de cobro rediseñada el 2026-06-10.** Los contratos soportan **interés simple y compuesto**.

- **Compuesto:** capitaliza anual, años exactos.
- **Cronograma (estructura 2026-06-10): 2 cuotas, espejo del simple.**
  - Cuota 1 — `tipo='devolucion'`: los **intereses** acumulados, en la fecha de **vencimiento**.
  - Cuota 2 — `tipo='retorno'`: el **capital**, **7 días calendario después** del vencimiento.
  - *(Antes era 1 sola cuota `retorno` con capital+intereses juntos; se partió para que el área de pagos deposite por separado, igual que en el simple.)*
- El admin ve además la **proyección año a año** (informativa) y el cliente la **curva compuesta** + la fila dorada **INTERESES** en su cronograma.
- Vive en la relación `contratos → cronograma_pagos` ([[Arquitectura del portal]]).

## Migración 2026-06-10 (aplicada en prod)
- `cronograma_tipo_devolucion_compuesto` — CHECK de `cronograma_pagos.tipo` acepta `'devolucion'` + la métrica "intereses pagados" del [[Rol Directorio]] pasa a `tipo IN ('retorno','devolucion')` (mantiene la paridad con lo que contaba antes).
- `split_pago_vencimiento_compuestos_existentes` — los 2 contratos compuestos existentes se partieron en sus 2 cuotas (montos verificados).
- Código: generadores (`contratos.js` v27 / `analista.js` v12), etiquetas "PAGO DE INTERESES" en pagos/dashboard/detalle, `crono-timeline.js` v5 (cliente), edge `notificar-pagos` v3 ("el pago de tus intereses"). SW v89. **Desplegado a miavance.com el 2026-06-10** — primer deploy vía MCP de Hostinger (ver [[Deploy a Hostinger]]).

## Notas relacionadas
[[Notificaciones de pagos]] · [[Arquitectura del portal]] · [[Rol Directorio]] · [[Inicio]]
