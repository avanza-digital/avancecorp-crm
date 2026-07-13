---
tags: [feature, frontend, mobile]
actualizado: 2026-07-13
---

# Carrusel de beneficios táctil

**Qué es (2026-07-13, en producción):** el carrusel de aliados de `beneficios.html` dejó de ser una animación CSS pasiva — ahora el cliente puede **arrastrarlo con el dedo** (scroll nativo con inercia), **tocarlo para pausarlo** y ver una empresa con calma; retoma solo ~2 s después de soltarlo. En desktop, el hover sigue pausando como antes. El bucle "sin fin" se mantiene.

## La decisión importante (regla de trabajo)

Miguel exigió **NO borrar nada** del código en producción. Por eso se hizo como **mejora progresiva 100% aditiva**:

- El marquee CSS original (16 tarjetas = 2 sets duplicados + `@keyframes benMarquee`) quedó **íntegro como fallback**: si el JS falla o no corre, la página se comporta exactamente como antes.
- Lo nuevo se activa solo cuando `initCarrusel()` (en `js/beneficios.js`) agrega la clase `.ben-marquee--touch` — al **final** del init, para que cualquier error previo deje el original intacto.

> **Regla derivada:** los cambios al portal en producción se hacen **aditivos y con fallback**, nunca destructivos.

## Detalles técnicos que no son obvios

- `touch-action: pan-x` a secas **bloqueaba el scroll vertical de la página** sobre la franja del carrusel (hallazgo 🔴 de la revisión adversarial de 53 agentes, verificado con gesto táctil real). El valor correcto es `pan-x pan-y`.
- `scrollLeft += fracción` se **congela** en monitores 120/144 Hz (el navegador redondea a píxeles) → la posición vive en una variable float propia.
- El bucle infinito usa el set duplicado (period = distancia tarjeta 1 → su clon); la corrección `pos -= period` corre **solo en el tick** del autoplay, nunca durante la inercia del usuario (la mataría en seco).
- Arranque sin salto: se lee el `transform` computado del marquee CSS y el scroll arranca ahí.
- Detalle canónico completo → `public_html/CLAUDE.md` (changelog 2026-07-13, §13: `beneficios v7`, SW `avance-v94`).

## Notas relacionadas
[[Arquitectura del portal]] · [[Auditorías del portal]] · [[Deploy a Hostinger]] · [[Inicio]]
