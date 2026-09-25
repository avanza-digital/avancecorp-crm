# F6 — Corrección de paridad visual y orientación horizontal

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
- **PASS**: 11 E2E dirigidos Chromium en Docker, cero fallos y cero reintentos.
- **PASS**: `npm run check`, 4423 pruebas / 298 archivos, lint, tipos, cobertura,
  configuración de publicación, build, bundle y duplicación.
- **En curso**: suite completa Docker y revisión independiente.
- **NOT RUN**: CLI `gate:realidad`, falta `SUPABASE_URL` en este entorno. La
  corrección no altera datos; se inspeccionó la vista productiva sin actividad
  y se probó el caso de cero actividad con tasas nulas y pendientes existentes.
  Esto no se atribuye como ejecución del CLI.
- **Pendiente**: revisión normal de GitHub y publicación de esta corrección.

Las capturas locales son evidencia de presentación y comportamiento con
transporte interceptado; no constituyen una nueva conciliación SQL ni RLS.
La observación de F3–F5 y el corte del sábado conservan su estado. La retirada
de Seguimiento sigue condicionada a siete días reales estables.
