---
description: Crea una animación de video nueva (Remotion) en el laboratorio
argument-hint: <descripción del video, ej. "intro del logo para reels vertical">
---

Miguel pide una animación de VIDEO (Remotion, se exporta a MP4): **$ARGUMENTS**

Proyecto: `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/ui-playground/remotion`

1. **Crea la composición** en `src/` (un archivo por animación) y **regístrala** en `src/Root.tsx` con un `id` claro en PascalCase (ej. `LogoAvanceCorp`).
   - El logo de la marca está en `public/avance-logo-full.png` (cargar con `staticFile`).
   - Colores: navy `#0c1530`/`#1a2f5a`, verde `#4caf50`, dorado `#c8922a`.
   - Por defecto 1920×1080 a 30fps; si es para redes en vertical (reels/TikTok), 1080×1920.
2. **Verifica** con `npx tsc --noEmit`, y renderiza UN fotograma representativo con `npx remotion still <Id> <scratchpad>/frame.png --frame=N`, luego míralo con Read para confirmar que se ve bien.
3. Avisa a Miguel que la vea en movimiento en el Studio (`http://localhost:3000`) y ofrécele /render para sacar el MP4 final.
