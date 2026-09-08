# QA de Citas: identidad del CRM recuperada

Fecha: 2026-09-08. Miguel autorizó aplicar la recomendación tras rechazar el aspecto de la propuesta 3. Este QA reemplaza el anterior: una prueba técnica o una comparación contra el concepto previo no equivale a aprobación visual del cliente.

## Referencia y comparación

Fuente visual vigente: [Ranking actual del CRM](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/recursos-figma/02-ranking-crm.png). Implementación: [Citas](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/tablero.png), en `http://127.0.0.1:4180/prototypes/citas-crm.html`.

Ambas imágenes se abrieron juntas en una misma entrada de comparación, a **1672×941 px**, viewport CSS **1672×941**, densidad **1**, fuentes cargadas, tema claro y sin marco de navegador. Fuente: Ranking de la demo local; implementación: Resultados de Citas, septiembre completo, todos los analistas y sin ficha abierta. Son módulos y datos diferentes: se compara identidad, geometría, controles, tipografía y densidad, no igualdad píxel a píxel del contenido. Las cabeceras globales conservan sus 64 px y el menú mide 240 px.

Se inspeccionaron a resolución original los textos, filas, pestañas, campos, barras y márgenes en la misma entrada. Los detalles son legibles a esa resolución; no se necesitó un recorte de detalle adicional. También se comparó [la vista completa](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/tablero-completo.png) y se abrió la [ficha de Andrea](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/ficha-andrea.png).

## Cinco superficies de fidelidad

| Superficie | Evaluación |
| --- | --- |
| Tipografía | IBM Plex Sans comprobada en estilos computados. Títulos navy de 20 px para secciones; texto de tablas 13 px, encabezados y fechas secundarias 11 px, formato numérico del CRM. No se fuerza la fuente histórica del vault sobre la referencia vigente. |
| Espaciado y composición | Menú real, cabecera de 64 px, margen de 24 px, paneles de radio 16 px y separación de 16 px. Se devuelve aire a las filas: al menos 44 px. Se elimina la cabecera intermedia de personas. Documento completo 1672×1173 px: el total de analistas requiere desplazarse 232 px; es una decisión deliberada de legibilidad, no se afirma que todo cabe en 941 px. |
| Colores y tokens | Variables y gi-card vigentes de Gerencia: superficies blancas, bordes cálidos, títulos navy, azul discreto en barras y selección; ámbar solo en Sin nueva cita. Los campos y las pestañas recuperan el fondo suave del CRM. |
| Recursos | Sidebar, BrandLockup, Avatar, iconos Lucide, Button, Select, Progress y Sheet existentes. Sin imágenes reconstruidas ni nuevo tema importado. La cabecera se compone con la geometría del Topbar, pero usa acciones locales de Citas y no monta su store. |
| Contenido | Flujo 4→3→1→1, 25%=1/4 y S/35,000. Equipo 40/26, promedio 1.54, cumplimiento 51.3%, 3 de 26 leads con 3+. Meta 3=100% y objetivo 3.75=125%, escala de barras hasta 125% y marca100%. Los filtros y cálculos son los del ejemplo anterior. Fecha de origen y corte visibles. |

## Iteraciones

1. **P1 — deriva de identidad en el antecedente:** [implementación rechazada](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/recursos-figma/04-propuesta-no-aprobada.png) usaba un rail reducido de 208 px, lienzo plano y pestañas subrayadas. Se sustituyó por Sidebar real y composición de Gerencia. Comparación final con Ranking: resuelto en esta propuesta; pendiente la opinión visual de Miguel.
2. **P2 — etapas cruzadas en anchos intermedios:** la primera prueba de geometría detectó un borde de flecha en 422.7 px frente al siguiente botón en 396.5 px. Las etiquetas ahora pasan debajo del número a 1279 px y el flujo usa dos filas bajo 900 px. Las pruebas de geometría finales pasan en 1280/1024/768; [1024](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/ancho-1024.png) y [768](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/ancho-768.png) inspeccionadas. Resuelto.
3. **P2 — mes recortado en filtros estrechos:** [tablet anterior](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/antes-filtro-tablet.png) y [móvil anterior](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/antes-filtro-movil.png). Se amplían las columnas a dos y se abrevia el nombre del mes conservando el año. Capturas finales de 768 y [390 px](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/movil.png): mes y semana completos. Resuelto.

Tablet y móvil son adaptaciones del contenido: no se dispone de una fuente móvil de Citas para comparación exacta. Los viewports son 768×941 y 390×844, densidad 1, capturas de página completa. En ventanas estrechas las tablas conservan desplazamiento propio; las regiones son enfocables para recorrer columnas con flechas. El menú mantiene el comportamiento del componente compartido. La [ficha móvil](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/movil-ficha.png) mide 390×844.

## Verificación

PASS: [recorrido en Chromium aislado](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/interacciones.json): filtros globales, etapa sin cambiar base, estados vacíos, seguimiento fuera de semana, columnas, CSV de 40 citas desde página 2, teclado, retorno de foco, ficha modal, recorrido→cita→agenda y anchos 1672/1366/1280/1024/768/390. Cero errores de consola. En un intento el script enfocó el selector antes de completarse el retorno de foco del modal; otro, concurrente con el gate integral, no confirmó el foco de retorno. Se añadió comprobación explícita del foco dentro del diálogo antes de cerrarlo y del foco devuelto antes de continuar; se guardará un diagnóstico si vuelve a fallar. La secuencia final aislada pasa. No se cambió el Sheet compartido.

PASS: `npm run check` integral final, 218 archivos y 3112 pruebas. Después de los últimos ajustes, 31 tests del prototipo, TypeScript/build y lint. Cuatro advertencias previas de coverflow, ninguna nueva en Citas. Las dos expectativas antiguas de panel no modal se actualizaron al comportamiento modal deliberado.

NOT RUN: E2E completa de producción, datos/backend reales, lector de pantalla exhaustivo y medición automática de todos los contrastes. Este prototipo no inicia sesión ni registra citas o depósitos reales.

No quedan diferencias visuales P0/P1/P2 accionables en las capturas inspeccionadas. La aprobación visual del cliente continúa pendiente.


Revisión de Claude recibida y evaluada por Codex: [registro](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/adaptacion-identidad/revision.md). Se aplicaron los ajustes respaldados por evidencia y se descartaron las hipótesis resueltas por los componentes compartidos.

Dimensiones de los PNG finales (densidad 1):

- tablero.png: 1672×941 px.
- tablero-completo.png: 1672×1173 px.
- ancho-1366.png: 1366×1241 px.
- ancho-1024.png: 1024×1361 px.
- ancho-768.png: 768×1568 px.
- movil.png: 390×1767 px.
- movil-ficha.png: 390×844 px.

final result: passed
