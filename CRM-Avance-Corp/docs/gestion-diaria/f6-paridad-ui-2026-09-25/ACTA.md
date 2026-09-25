# F6 — Corrección de paridad visual y orientación horizontal

**PUBLICADA Y VERIFICADA** el 25/09, 10:13 Lima, fuente `65e96df9`.
81/81 archivos HTTPS y nueve comprobaciones reales PASS.
[Acta de publicación](PUBLICACION-2026-09-25.md).

Miguel reportó el 25/09 que gerencia seguía siendo visualmente distinta de
supervisión y reiteró que la orientación debía ser horizontal. La publicación
anterior `f9196dba` está acreditada; su validación no cubrió adecuadamente la
composición habitual con el menú abierto. Esta incidencia reabre la entrega
visual de F6, sin repetir la conformidad de negocio ya cerrada.

## Causa y corrección

La captura anterior a 1366 × 900, con menú abierto, mostraba dos filas grandes
de indicadores y ocultaba el detalle lateral al disponer de menos de 1236 px
útiles. La nueva prueba reprodujo el fallo: el panel no estaba visible.
[Supervisión de referencia](antes/supervision-1366-menu-abierto.png) y
[gerencia antes](antes/gerencia-1366-menu-abierto.png) se capturaron en esta
sesión con el mismo tamaño y el menú abierto, usando datos sintéticos por rol.

Gerencia ahora reutiliza las clases de cabecera, resumen, acciones y pie de
supervisión. Conserva los ocho indicadores actuales en una franja compacta;
«Comparar días» reúne las ocho cifras del día elegido, anterior y referencia.
Las definiciones, los denominadores y los valores nulos se conservan. Los
filtros de atención usan la misma presentación de supervisión.

Con al menos 960 px útiles, la tabla y el detalle permanecen lado a lado,
tanto en Pulso como en Hábitos. Las columnas adicionales desplazan dentro de
la tabla, con la primera columna fija. En menos ancho, el detalle pasa a
un diálogo y el móvil mantiene el reflujo. La fecha, selección, filtros,
registro, exportación y navegación hasta la ficha conservan sus contratos.
No se modifica la pantalla de supervisión ni SQL, RPC, RLS o permisos.

## Verificación

- **PASS**: regresión reproducida antes y corregida después; escritorio con
  menú abierto a 1366 y 1280 px, indicadores en una sola fila, tabla y detalle
  alineados, sin desbordamiento de página; columnas accesibles con teclado.
- **PASS**: `npm run check`, 4423 pruebas / 298 archivos, lint, tipos, cobertura,
  configuración de publicación, build, bundle y duplicación.
- **PASS**: suite completa Chromium en Docker, 271 aprobadas / 0 fallos /
  26 omitidas / 0 reintentos (`e2e-completo.json`, implementación `14ed7336`, después de resolver el review).
- **PASS tras la revisión y el ajuste móvil final**: 11 E2E Chromium y 11 WebKit en Docker, sin fallos,
  omitidas ni reintentos; `e2e-dirigido-final.json` y `e2e-webkit-final.json`.
  Incluyen desplazamiento en ambos ejes y transición exacta 960/959 px útiles.
  `npm run check` repetido tras los ajustes: 4423/298 PASS (`check-final.log`).
- **Revisión independiente realizada**: [CHANGES_REQUESTED](REVISION-CLAUDE.md).
  [Resolución del PRIMARY](RESOLUCION-REVISION.md): hipótesis del solapamiento
  reproducida y corregida; especificidad, foco y cierre reforzados. No se
  atribuye una segunda aprobación del reviewer.
- **NOT RUN**: CLI `gate:realidad`, falta `SUPABASE_URL` en este entorno. La
  corrección no altera datos; se inspeccionó la vista productiva sin actividad
  y se probó el caso de cero actividad con tasas nulas y pendientes existentes.
  Esto no se atribuye como ejecución del CLI.
- **PASS, publicación**: PR #103 integrado manualmente; Miguel autorizó
  expresamente publicar tomando esa integración como aprobación. Main CI 3/3,
  81/81 archivos HTTPS y recorrido real 9/9 PASS. GitHub no registra una
  revisión APPROVED; no se atribuye una excepción general para otros PR.

Las capturas locales son evidencia de presentación y comportamiento con
transporte interceptado; no constituyen una nueva conciliación SQL ni RLS.
La observación de F3–F5 y el corte del sábado conservan su estado. La retirada
de Seguimiento sigue condicionada a siete días reales estables.

## Evidencia visual final

- [Gerencia a 1366 × 900](despues/gerencia-1366x900-menu-abierto.png): mismo
  viewport que las capturas anteriores, menú abierto.
- [Portátil a 1366 × 768](despues/gerencia-1366x768-menu-abierto.png) y
  [1280 × 800](despues/gerencia-1280x800-menu-abierto.png).
- [Analista y detalle lateral](despues/gerencia-analista-horizontal.png),
  [Hábitos](despues/gerencia-habitos-horizontal.png) y
  [comparación completa](despues/gerencia-comparacion.png).
- [Desplazamiento con cabecera preservada](despues/gerencia-tabla-desplazada.png).
- [Móvil a 390 px, con valores dentro de su casilla](despues/gerencia-movil-390.png).

Evidencia sintética inspeccionada por Codex PRIMARY. El CSS conserva el texto
operativo de 16 px y controles de 44 px; se reutilizan los componentes y tokens
de supervisión. La tabla añade scroll interno cuando las columnas no caben,
para que el panel siga a la derecha sin desbordar toda la página.

## Ajuste final de legibilidad móvil

La inspección de la [captura móvil anterior](antes/porcentaje-movil.png) detectó que «62.5 %» sobresalía de su
casilla a 390 px, aunque la página completa no desbordaba. Se reprodujo con
una prueba geométrica de cada etiqueta y valor (`movil-antes.log`). Se permite
el salto de línea del valor y se usa una sola columna en el ancho útil mínimo
(260 px). Se comprueban 390, 360 y 320 px. La composición de escritorio no
cambia. La suite completa 271/0/26 corresponde al commit `14ed7336`; este
ajuste exclusivamente móvil tiene PASS en los 11 recorridos de Chromium y
los 11 de WebKit, sin fallos ni reintentos. La prueba comprueba cada casilla
a 390, 360 y 320 px. El gate final vuelve a pasar con 4423 pruebas / 298
archivos. Los reportes finales y la captura móvil están adjuntos a esta acta.
