---
tags: [feature, frontend, mobile]
actualizado: 2026-08-24
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

## Dirección UX aprobada para la siguiente versión (2026-08-24)

Miguel confirmó una evolución **mobile-first** del apartado porque los clientes usan el portal como PWA:

- El carrusel se mantiene como elemento principal; no se reemplaza por una lista simplificada.
- El encabezado debe decir exactamente **“Aliados de MasCapitalGroup”**.
- Se usan los siete logos reales disponibles: Phoenix, Belysh, NTC Agency, Qorilazo, MasCapital, Clínica Álvarez y Prodelco.
- La propuesta adopta un coverflow moderado: tarjeta activa frontal y siguiente tarjeta parcialmente visible, inclinada y con profundidad. Se evita una rotación excesiva para conservar la legibilidad de los logos.
- Contador, anterior, pausa y siguiente quedan debajo del carrusel, dentro de la zona cómoda del pulgar; los filtros actualizan el mismo carrusel.
- Los CTA de asesor usan el patrón visual de WhatsApp y el texto **“Consultar por WhatsApp”**. Mientras sea prototipo, la interfaz explica que el enlace real se conectará al canal del asesor.
- La tipografía de la propuesta final es nativa de aplicación: Avenir Next/SF Pro con fallbacks del sistema y SF Mono para etiquetas; no depende de Google Fonts.
- Los convenios continúan mostrando el estado honesto **“Convenio en negociación”**; no se inventan descuentos ni condiciones.
- La implementación actual es un prototipo revisable. No se modificó la versión de producción de `public_html/beneficios.html`.

Artefactos de referencia:

- Versión final de aplicación PWA, autónoma y sin runtime de maqueta: `revision-carrusel-mejorado/beneficios-pwa-app.html`. Fue validada en 320 × 568, 390 × 844, 430 × 932 y 844 × 390 px; mantiene áreas táctiles de 44 px, safe areas y cero desbordamiento horizontal.
- Prototipo PWA: `revision-carrusel-mejorado/Carrusel Beneficios Mejorado.dc.html`.
- Componente reutilizable React/TypeScript: `CRM-Avance-Corp/app/src/components/ui/coverflow-carousel.tsx`.
- Demo con aliados reales: `CRM-Avance-Corp/app/src/components/ui/coverflow-carousel.demo.tsx`.

La regla de producción se mantiene: cuando se apruebe la propuesta, el despliegue debe conservar el fallback existente y realizarse de forma progresiva.

## Notas relacionadas
[[Arquitectura del portal]] · [[Auditorías del portal]] · [[Deploy a Hostinger]] · [[Inicio]]
