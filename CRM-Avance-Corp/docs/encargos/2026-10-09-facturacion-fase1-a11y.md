# Encargo a Codex (IMPLEMENTADOR) — Fase 1 de Facturación: correcciones de accesibilidad

Mismas reglas que `2026-10-09-facturacion-fase1-hoja-excel.md`: escribes solo en este worktree, sin commit, push, red,
Docker ni otros agentes. Todo en español. Corres `npm run check` en `app/` y das un informe breve.

La revisión de accesibilidad (`revisor-a11y`, 09/10) de TU entrega de la fase 1 pide cambios. Corrige todo lo de abajo.
Las cifras no pueden cambiar.

## P1 — El contexto de las pastillas tiene que VERSE (regresión respecto de HEAD)

Hoy solo vive en el `title` de la pastilla, que en el celular y con teclado no se ve:
- comparación con el tramo anterior (%);
- composición soles + dólares;
- qué día fue el mejor;
- días hábiles del promedio;
- «Todavía sin cierres».

Con más de un analista, la pastilla es un `<p title=…>`. Ver `facturacion.tsx:1285-1300` (los textos se arman en
`:819-831`) y `pastilla.tsx:30`.

**Solución elegida (opción A):** una línea de contexto VISIBLE debajo de la fila de pastillas, en `text-sm` color
`--muted-foreground-strong`, con las piezas que existan unidas por « · ». Por ejemplo: «S/ 40,000 + US$ 2,000 ·
+12 % respecto del mismo tramo de septiembre · Mejor día: viernes 3 de octubre · 19 días hábiles; el domingo no cuenta».
- La fila de pastillas sigue midiendo ≤ 56 px; la línea va fuera de esa medida.
- El `title` queda solo como redundancia.
- Las pruebas que hoy leen ese contexto del `title` (`facturacion.test.tsx:968`, `:1089`, `:1486`;
  `e2e/facturacion-realidad.spec.ts:231-232`) pasan a leer el texto visible.
- El comentario de la prop `pista` en `pastilla.tsx:12` no debe invitar a meter información en el tooltip.
- Las pastillas pulsables pasan `pista="ver el desglose"`.

## P2

1. **Contraste.** El subtítulo «Equipo de …» de la fila marcada (`facturacion.tsx:347`, `:375`) tiene 4,24:1 sobre
   `#edf2fd`/`--muted`. Pasa a `text-muted-foreground-strong` (6,76:1).
2. **Foco bajo la cabecera fija** (SC 2.4.11). La cabecera de días mide unos 61 px y los botones reservan 56 px
   (`scroll-mt-14`); el botón del total (`:404`) no reserva nada. Pon una sola reserva en el contenedor:
   `.facturacion-malla { scroll-padding: <alto real de la cabecera + 4px> <ancho de la columna fija derecha>px 0
   <ancho de # + nombre>px; }`, medido, no a ojo. Quita los `scroll-mt-*`/`scroll-ml-*`/`scroll-mr-*` de los botones.
   Añade al e2e una prueba de Shift+Tab hasta el total de una fila que queda bajo la cabecera, con `seVeSinTapar`, que
   ya existe en el spec.
3. **Ancho intermedio.** Entre 768 y ~900 px las columnas fijas (48 + 272 + 150 = 470 px) no dejan ver ningún día; con
   zoom al 200 % pasa en pantallas normales. Elige tarjetas según el ancho de la REGIÓN, no de la ventana
   (`ResizeObserver` sobre el contenedor de la malla): por debajo de ~730 px útiles, tarjetas. Añade un e2e a 800×900
   que compruebe que se ve al menos una semana de días o que salen las tarjetas.
4. **Foco de la región desplazable** (`facturacion.css:24`, `facturacion.tsx:1444`). Con `outline-offset: -2px` el
   contorno queda tapado por las celdas fijas. Dibújalo por fuera, con margen dentro de la Card
   (`.facturacion-malla { margin: 4px } .facturacion-malla:focus-visible { outline-offset: 0 }`) o en un envoltorio con
   `:has(> .facturacion-malla:focus-visible)`.

## P3

- `facturacion/tarjetas.tsx`:
  - `:17`, `:20`: no anides landmarks; usa `aria-labelledby` al h3 o un `<div>`.
  - `:39-42`, `:47-51`: los botones dicen quién y qué; por ejemplo, `aria-label="ANA PRUEBA, viernes 3 de octubre:
    S/ 4,850 en 1 operación — ver el desglose"`.
  - Una sola parada de tabulación por acción.
  - `:23`: «1 analistas» pasa a singular y plural correctos.
- `aria-label` «Banda» (`facturacion.tsx:1564`, `:1679`) y «Total» (`:1634`) en celdas # vacías: quítalos o pon el
  texto real en `sr-only` («Total del día en soles»).
- El botón del total de fila (`:404`): nombre «Ver el mes completo de X: total S/ Y».
- La caption (`:1446-1453`) se adapta a la vista Día (no hay botones de día) y menciona la columna «por venir».
- Resumen: `flex-wrap: wrap` en `facturacion.css:41-44`; cuando cabe, sigue en una sola fila.
- `components/ui/estilos-hoja.ts:3`: `ENCABEZADO` no puede llevar 13 px (regla de 14 px o más), y sus usos existentes no
  deben cambiar de aspecto sin querer; revisa quién lo importa.
- `facturacion.css:48`: además de `transform: none`, añade `scale: none` (Tailwind v4 usa `scale`).
- `th` «10–31 oct · por venir»: añade un nombre accesible completo («del 10 al 31 de octubre, por venir»).

Los problemas que ya existían en HEAD (el foco al alternar «Comparar», los chips que desaparecen, el «hoy» en fin de
semana, las cifras abreviadas del pie) NO se tocan en esta entrega.
