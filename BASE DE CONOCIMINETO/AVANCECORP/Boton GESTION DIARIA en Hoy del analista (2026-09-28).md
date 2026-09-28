---
tags: [crm, hoy, analista, ux, cta, ui-playground]
fecha: 2026-09-28
estado: publicado 28/09/2026
---

# Botón «GESTIÓN DIARIA» en «Hoy» del analista (2026-09-28)

Miguel quería «un botón call to action que jale la vista» para que los analistas entren a Gestión diaria desde
«Hoy», en la esquina superior derecha. Se diseñó en el UI Playground (`/componente`, pieza **CRM-02**; la variante
de líneas **CRM-03** quedó en la galería como alternativa) y se promovió al CRM con `/promover`.

## Lo que Miguel decidió, en orden
- Un botón animado en la esquina, donde estaba la pastilla «Vista personal» (que baja debajo, más pequeña).
- Icono: **teléfono de casa** que suena solo, sin necesidad del mouse (antes probó celular y calendario).
- Investigación (Mobbin + guías de CTA) → 7 mejoras aplicadas; luego recortó: **fuera capital, hora de la siguiente
  cita, racha y puesto**; fuera las letras ámbar; el rótulo es solo **GESTIÓN DIARIA** con la **barra de avance** del día.
- **Rebote de pelota** sobre el piso «como para niño» y un **«pop»** al pasar el cursor.

## Cómo quedó en el CRM
- `components/app/boton-gestion-diaria.tsx` + `.css` (CSS puro, sin Motion; `prefers-reduced-motion` apaga los bucles).
  Estados: urgente (vencidas: borde/aura/barra en ámbar, timbre fuerte ~2 s), activo (pendientes: timbre suave ~4 s),
  al día (quieto, check, sin barra), sin cifras (navy neutro, sin barra ni check). Aura ×3 al entrar y brillo cada 7 s
  solo hasta que el analista entra ese día. Clic: descuelga 420 ms y navega por hash a `gestion-diaria`.
- `data/use-conteo-gestion-diaria.ts`: en sesión real, vencidas/pendientes de la MISMA cola que Gestión diaria
  (`useColaSlaPagina` + `ordenarColaDiaria`, misma clave de caché) y hechas = `marcador.llamadas` del día
  (`useDiaAnalista`); `sinCifras` si la cola no llegó, falló, tiene más página, el día no es hoy o la cartera viene
  truncada. En demo, el espejo `filasDiariasDemo`. Visita del día en `localStorage` `crm:gd-visita:<uid>`.
- El sonido solo suena tras el primer clic o tecla en la página (regla de autoplay del navegador) y solo con el
  contexto de audio en marcha; nada se encola en pausa.

## Verificación y publicación
- check 4834 PASS (34 pruebas nuevas), revisor-a11y aplicado, Codex CHANGES_REQUESTED → 3 P2 aplicados (fuente
  autoritativa, disponibilidad por día/truncado, audio sin encolar).
- Commits `34737983` + `7e9b426a`; build `build-20260928T233226790Z`, artefacto `crm-20260928T233227Z-7e9b426aba7d`;
  humo PASS (chunk y CSS de Hoy idénticos local↔vivo). PR **#129** (incluye lo de #128, aún abierta: al fusionar #129,
  cerrar #128). #126 y #127 fusionadas y traídas al local (`bf73675e`).
- Pendiente menor: exportar `LIMITE_COLA` desde `analista.tsx` para no duplicar el 100.

Ver [[Hoy del analista - sin espacios vacios (2026-09-28)]].
