# F5 — coherencia visual con el CRM

08/09/2026. Miguel valoró favorablemente las capturas de F5 y pidió mantener la
similitud con los recursos y componentes del CRM. Se conserva la organización
presentada: cartera → ficha por persona → revisión de nueva inversión.

## Criterio y cambios

- Se usan la tipografía y los tokens existentes: Plus Jakarta Sans, navy
  `#111e3d`, azul `#2563eb`, lienzo `#f6f8fc`, tarjeta blanca y borde `#e4e9f2`.
  Se mantienen los tamaños de texto y la alineación a la izquierda del CRM.
- La cartera conserva el ancho máximo de 1.240 px usado por Mi cartera.
  Los filtros y el resumen por empresa/moneda se acomodan al ancho disponible
  del panel. En una ficha estrecha no se fuerzan tres columnas de escritorio.
- El estado sin resultados reutiliza `PanelVacio`. La paginación compartida
  usa `Button`, conserva sus condiciones y callbacks, y permite que contador
  y controles ocupen líneas distintas en móvil. Los botones tienen foco visible
  y una altura mínima de 40 px en pantallas estrechas.
- El formulario mantiene los componentes de campos, diálogo y contrato del CRM.
  Se uniforman los espacios de etiquetas y campos, el resumen de revisión y el
  tono de error. Los botones largos y nombres de archivo pueden ocupar varias
  líneas; las acciones de revisión se apilan en móvil.

El ajuste afecta presentación y composición de cuatro archivos de frontend.
No cambia payloads, importes, permisos, consultas, solicitudes, confirmaciones,
contratos, documentos ni comisiones. Riesgo LEVEL 1; cero consultas adicionales
al reviewer. La revisión original de F5 continúa documentada en [REVISION.md](REVISION.md).

## Verificación

Código del ajuste: `37ba1fa`. La documentación y las capturas se guardan después;
el manifiesto del nuevo paquete identifica el commit final sincronizado.

- `npm run check:all`: PASS. Lint, tipos, 3.127 tests en 221 archivos,
  cobertura, configuración de release, build, bundle y duplicación;
  147 Playwright PASS y 26 omisiones preexistentes.
- Los siete recorridos F5 pasan dentro del gate completo. Antes del gate
  también pasaron su suite específica y los 11 tests de interfaz F5.
- Recorrido visual adicional con datos ficticios: 13 capturas inspeccionadas
  en anchos de 320, 390, 768 y 1.440 px. Incluye lista, ficha, archivo largo,
  error al confirmar, recuperación de corrección, lista vacía y error de lectura.
  No se observó desborde horizontal del documento, los diálogos ni sus botones.
- La revisión visual no reemplaza el gate de datos del destino. F5 permanece
  candidata sin publicación; sus fixtures no se presentan como datos reales.
- `git diff --check`: PASS. Los cambios y los resultados quedan guardados
  junto con el paquete construido desde el commit sincronizado del manifiesto.
- **NOT RUN:** sesión manual de VoiceOver y gates de publicación en producción.
  No se atribuye una prueba con lector de pantalla a la inspección de capturas
  ni a la comprobación automática de nombres accesibles, teclado y foco.

## Capturas

- [Cartera en escritorio](evidencias/f5-acabado-cartera-1440.png).
- [Cartera en móvil y paginación](evidencias/f5-acabado-cartera-390.png).
- [Estado sin resultados](evidencias/f5-acabado-cartera-320-vacia.png).
- [Recuperación en móvil](evidencias/f5-acabado-recuperacion-320.png).

Las siete capturas originales de `evidencias/f5-*.png` se actualizaron desde
la última ejecución del gate. Las capturas previas, el recorrido adicional y
sus logs se conservan en el respaldo privado de este ajuste.

La publicación y el encendido siguen las condiciones de [README.md](README.md).
