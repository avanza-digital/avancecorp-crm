# Verificación de las propuestas — 18/10/2026

## PASS

- `node --check docs/diseno/hoy-supervisor-2026-10-18/propuestas.js`.
- Comprobación aritmética independiente: capital 1 360 000, metas 2 000 000,
  26 operaciones, 180 llamadas, 170 útiles, 74 contestadas, 13 citas con 7
  realizadas/4 pendientes/2 inasistencias, 24 vencidas, 7 primeras gestiones,
  16 oportunidades y 620 000 de potencial. También estados de citas por persona,
  68% de cumplimiento y 43,5% de contacto. Verificación con Node/assert sobre el
  fixture, sin modificar la aplicación.
- Recursos locales del HTML existentes, ausencia de espacios al final de líneas
  y `git diff --check` del directorio. Sin dependencias nuevas.
- Inspección real en Chrome: propuestas 1 y 2 a 1440 × 1100 y 390 × 844.
- Navegación entre propuestas, tabla de la propuesta 2 entre día/mes, apertura
  de detalle de Valeria, cierre con Escape y devolución del foco a su nombre.
- Orden de la propuesta 1 por brecha: Mateo, Valeria, Diego, Lucía, Bruno, Camila;
  vuelta al orden inicial por capital.
- Estados de falta de datos: diálogo con Sin meta, Muestra insuficiente,
  No disponible, Provisional y cero confirmado, comprobado en móvil.
- Ancho móvil final: viewport 390, documento 375 CSS px (resto es scrollbar),
  sin desplazamiento horizontal de página en las dos propuestas. La tabla
  conserva su desplazamiento propio para comparar columnas.
- Las cuatro capturas corresponden a la versión final de la maqueta.

## Hallazgos resueltos durante la comprobación

- El texto accesible de una cabecera de tabla, posicionado respecto al documento,
  extendía la página hasta 637 px en móvil. Se hizo relativo el contenedor de tabla.
- Los localizadores de prueba exactos por etiqueta no resolvieron dos controles;
  se usaron el rol de combobox y el control accesible observado. Las acciones se
  completaron y verificaron. No se presentan los intentos fallidos como exitosos.
- La primera revisión restringida de Claude no completó. La revisión ejecutada
  con el wrapper fuera de ese entorno devolvió CHANGES_REQUESTED; se evaluaron
  sus hallazgos con código y se corrigieron los pertinentes. Resolución completa
  en `REVISION-RESUELTA.md`; no se afirma PASS del reviewer.

## NOT RUN

- Build, tests y E2E del CRM: no se modificó código del producto. La inspección
  interactiva aquí es del prototipo estático, no un E2E acreditado del CRM.
- Gate de realidad y conciliación de cifras productivas: fuera del alcance de
  estas propuestas. La sesión real se inspeccionó únicamente para entender la UI.
- Validación humana del diseño: pendiente de la conversación con Miguel.

No se publicaron cambios ni se modificaron registros del CRM.

## Ajuste solicitado por Miguel — 18/10/2026, 02:24

Retirados de la cabecera compartida «Cómo leer las cifras» y «Si faltan datos».
PASS: ambos accesos ausentes en las dos propuestas, comprobado en Chrome tras
recargar; `git diff --check` sin errores. La captura `cabecera-sin-enlaces.jpg`
documenta este ajuste posterior; las cuatro capturas anteriores son históricas.
