# Encargo 3 a Codex (IMPLEMENTADOR) — Facturación fase 4: últimos ajustes de foco y anchos

ROLE: IMPLEMENTER delegado por Claude (PRIMARY). Mismas reglas:
- solo este worktree;
- sin commit, red, Docker, dependencias nuevas ni otros agentes;
- en español.

Al final, `npm run check` tiene que quedar en VERDE en `app/`.

**Estado verificado por el PRIMARY:**
- `npm run check`: PASS (6574 pruebas).
- e2e de Facturación en Docker: 15/15. El PRIMARY cambió `getByRole('complementary')` por
  `page.locator('aside.lista-operaciones')` en los e2e, porque la barra lateral del CRM también es un `<aside>`.
- El revisor de accesibilidad verificó tu pasada 2: P1 y P3 resueltos, y P2 resueltos salvo lo de abajo.

Rutas: LO = `app/src/screens/facturacion/lista-operaciones.tsx` (+ `.css`), F = `app/src/screens/facturacion.tsx`.

## P2

1. **N1 — Un refresco de fondo no deshabilita el botón con foco.**
   - La paginación usa `disabled={… || consulta.isFetching}` (LO ~295-296). Los refrescos automáticos (intervalo, volver a
     la ventana, reconexión) deshabilitan el botón enfocado y el foco se pierde.
   - Deshabilitar solo mientras llega una página nueva: `const paginando = !ejemplo && consulta.isPlaceholderData`.
   - Test: con el foco en «Página siguiente», un refresco de fondo no lo mueve ni lo deshabilita.
2. **N2 — El efecto de foco no mueve el foco sin acción del usuario.**
   - En LO ~168-170, enfocar el título solo si el foco ya está en la hoja o en `body`:
     `const a = document.activeElement; const focoEnHoja = a == null || a === document.body || !!panel.current?.contains(a)`.
   - `ir()` no hace nada si no cambian ni la página ni el tamaño, para no dejar armada la bandera.
   - Tests:
     - con el foco en la malla, ni un error de fondo ni un refresco mueven el foco;
     - pulsar el tamaño ya activo y luego un refresco tampoco.
3. **N3 — Por debajo de 1280 px de ancho, la hoja es MODAL.**
   - Entre unos 1030 y 1180 px, con el menú expandido, la reserva de 560 px deja la malla sin ninguna celda de día visible.
   - Usar `useEsEstrecha` (`app/src/lib/media.ts` ~98) o el umbral equivalente: con la pantalla estrecha, la hoja usa la
     semántica y el comportamiento MODAL que ya existe para celular (dialog, `aria-modal`, fondo inerte y foco contenido),
     sin reserva de ancho ni `scroll-padding`.
   - El aspecto en celular (≤ 640 px) sigue siendo el panel inferior con tarjetas. Entre 641 y 1279 px se mantiene el
     panel lateral, pero modal.
   - Test unitario.
   - e2e (lo corre el PRIMARY), a 1100×800 sin pantalla táctil: abrir una celda y comprobar `aria-modal` y el fondo
     inerte, y que Esc devuelve el foco.

## P3

4. **N4 — En celular/modal, Shift+Tab** desde la tarjeta enfocada al paginar (`tabIndex=-1`) no salta al último control.
   Solo se envuelve cuando el foco está en el título o fuera del panel.
5. **N5 — En NO modal, Esc no se apropia de los campos del fondo.** Si el destino es `input`, `textarea`, `select` o
   `[contenteditable]` FUERA del panel, no se cierra ni se hace `preventDefault`: así se conserva el borrado del buscador
   «Buscar analista». Un Esc desde un botón de la malla sigue cerrando (el e2e lo comprueba).
6. **N6 — El elemento del panel es SIEMPRE `<section>`**, con `role="dialog"` y `aria-modal` solo en modo modal, y
   `aria-labelledby` siempre. En no modal, una `section` con nombre es una región.
   - Motivo: `role="dialog"` no está permitido sobre `<aside>`, y cambiar de elemento remonta el árbol al girar el
     teléfono.
   - Ajusta los e2e a `page.locator('.lista-operaciones')` (sin el nombre del elemento) y los tests unitarios que busquen
     `complementary`: ahora es `region` con su nombre.
7. **Avisos emergentes (sonner) en modo modal.** `<Toaster>` vive dentro de `#root` (`app/src/main.tsx` ~31), y
   `#root.inert` los deja sin anunciar ni pulsar. Aplica `inert` al contenedor de la app y no a la sección de los
   avisos. Si no se puede limpiamente, explícalo en el informe.
8. **Detalles:**
   - actualizar el motivo de la supresión en F ~1500, que dice que las celdas de equipo nunca son botones y ahora lo son;
   - quitar el `aria-label` repetido de la lista de tarjetas: «Operaciones de este número» ya está en la región y en el
     caption.
9. **Test:** Esc dentro de un modal Radix abierto encima de la hoja NO cierra la hoja (la guarda ya existe, falta el
   test).

Informe final breve: archivos, PASS/FAIL de `npm run check` y lo no verificado.
