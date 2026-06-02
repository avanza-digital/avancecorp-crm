---
tags: [bug, lecciones]
actualizado: 2026-06-01
---

# Bug de fechas UTC

**Problema:** `new Date("YYYY-MM-DD")` se interpreta como UTC y **corre 1 día** en Perú (UTC-5) por la tarde — fechas de cuotas/contratos mostradas un día antes.

## Solución
- `_helpers.formatearFecha` parsea `YYYY-MM-DD` como fecha **LOCAL**.
- Parcheado también en el cliente (`dashboard.js`, `inversion.js`, `documentos.js`, `crono-timeline.js`) y en `admin/dashboard.js` (`fechaLocalISO()` reemplaza `toISOString()`).

## ⚠️ Anti-patrón vigente
Algunos módulos cliente re-definen `formatearFecha` localmente **sin** el fix → riesgo de recaída. **Preferir importar de `_helpers.js`.**

## Notas relacionadas
[[Arquitectura del portal]] · [[Auditorías del portal]] · [[Inicio]]
