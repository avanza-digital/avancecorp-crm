---
description: Crea un componente animado nuevo en la galería del UI Playground
argument-hint: <descripción del componente, ej. "sidebar colapsable con hover">
---

Miguel pide un componente animado nuevo para la galería del UI Playground: **$ARGUMENTS**

Proyecto: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/galeria`

Reglas del laboratorio:

1. **Crea el componente** en `src/componentes/<NombreEnPascalCase>.tsx`, usando la marca (tokens en `src/index.css`: navy `#111e3d`/`#1a2f5a`, dorado `#c8922a`, verde `#2fa855`/`#4caf50`).
   - Micro-interacciones de UI (hover, tap, entradas, transiciones) → **Motion** (`import { motion } from "motion/react"`).
   - Animaciones ligadas al scroll o timelines complejos → **GSAP** (`useGSAP` con `scope` + `ScrollTrigger`).
2. **Registra la demo** en `src/App.tsx`: nueva `<section>` con su id, título y descripción corta en español, y su entrada en `SECCIONES` (menú lateral).
3. Los textos de demo usan contenido real del negocio (inversiones, asesor, cartera, cobranza) — nunca lorem ipsum.
4. **Verifica**: `npm run build` debe salir limpio. Si la galería no está corriendo, arráncala (o usa el flujo de /lab).
5. Termina diciéndole a Miguel exactamente **qué mirar y cómo interactuar** (dónde pasar el mouse, qué clickear, si hay que scrollear) en `http://localhost:5173`.

El componente queda en la galería hasta que Miguel lo apruebe; la promoción a CRM/portal va por /promover.
