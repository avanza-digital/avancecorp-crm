# QA de Citas: propuesta 3

Fecha: 2026-09-08. Fuente visual: [Detalle a demanda](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/ajuste-ux/detalle-a-demanda.png). Implementación: [ficha de Andrea](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/ficha-andrea.png), en `http://127.0.0.1:4180/prototypes/citas-crm.html`.

## Comparación

Fuente e implementación abiertas juntas en una misma entrada de comparación. Ambas miden **1672 × 941 px**, viewport CSS **1672 × 941**, densidad 1, sin marco de navegador ni escalado. Estado: Resultados, septiembre completo, todos los analistas, cuatro personas, Andrea seleccionada y ficha abierta. Fuentes cargadas antes de capturar y movimiento reducido. Se repitió la comparación tras corregir la densidad.

La comparación completa permite leer nombres, horas, porcentajes y controles al tamaño original; no fue necesario un recorte de detalle. Se inspeccionaron especialmente la fila de Andrea, el total del equipo y la cronología del depósito.

| Superficie | Resultado y adaptación deliberada |
| --- | --- |
| Tipografía | IBM Plex Sans real del CRM, comprobada en estilos computados. Jerarquía de títulos, cifras, datos y metadatos conservada. Cuerpo de tabla de 14 px y metadatos de 12 px; no se encogió el texto para que cupieran las filas. Formato numérico del CRM, sin ceros decimales de relleno. |
| Espaciado y composición | Flujo primero, personas después, comparación de analistas debajo. Sin tarjetas ni KPI duplicados. Inspector de 384 px; rail real del CRM de 208 px frente a 190 del dibujo. Las dos tablas y su total terminan a 916.8 px y caben en los 941 px de alto. |
| Colores y tokens | Superficie blanca, texto navy, azul para selección/acciones y ámbar para Sin nueva cita. Usa los tokens del CRM; fila seleccionada con mezcla del accent al 8%. La jerarquía de color se conserva sin introducir estados de alarma por estar bajo la meta. |
| Recursos e iconos | BrandLockup y logo reales del CRM, nítidos, sin estiramiento; iconos de Lucide existentes. No se reconstruyen los destinos incidentales del rail de la imagen. Campos y botones conservan los componentes, radios y estados del CRM. |
| Contenido | Flujo 4/3/1/1, 25%=1/4 y S/35,000; total 40/26, 1.54, 51.3% y 3 de 26. Andrea 2 citas/66.7%, depósito 4 sep. 10:00 y confirmación 10:05. Se explicitan las distintas bases de consulta e historial. Ayudas y datos secundarios quedan accesibles a demanda. |

## Hallazgos e iteraciones

1. **P2, densidad de escritorio:** [primera captura](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/antes-escritorio.png) cortaba los últimos analistas y total; la fuente sí los mostraba. Se redujeron alturas de filas, botones y separaciones, conservando el cuerpo de 14 px. Recaptura y comparación: [ficha final](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/ficha-andrea.png), total visible y documento de 1672 × 941. Resuelto.
2. **P2, desborde tras navegación y cambio a móvil:** la página de 390 px llegaba a scrollWidth 822 por etiquetas absolutas de la tabla. Se hizo relativo el contenedor de desplazamiento para contener también esos elementos. [Móvil final](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/movil.png): scrollWidth 390, las tablas conservan su propio desplazamiento. Resuelto.
3. **P2, etapas superpuestas a 768 px:** [tablet anterior](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/antes-tablet.png) mostraba la flecha de Reprogramaron sobre el número de Asistió. Hasta 1100 px la conversión ahora pasa debajo y el flujo usa el ancho disponible. [Tablet final](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/tablet.png) y medidas de botones/flechas comprueban separación. Resuelto.

El raster solo define escritorio. Tablet y móvil son adaptaciones del mismo contenido, no comparaciones píxel a píxel con una fuente móvil inexistente. Capturas de página completa: tablet 768 × 1076, móvil 390 × 1529; viewport 768 × 941 y 390 × 844 respectivamente. [Ficha móvil](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/movil-ficha.png): 390 × 844. Todas a densidad 1.

## Interacción y accesibilidad

PASS en Chromium aislado autorizado: filtros de analista, mes y semana; seguimiento vinculado fuera de la semana; vacío y exportación deshabilitada; columnas opcionales; conservación de filtros entre las tres vistas; CSV completo desde página 2; recorrido → cita → agenda; fichas modal/no modal, retorno y conservación del foco, tabulación y Escape; anchos 1672/1280/1024/768/390 sin desborde; cero errores de consola. [Evidencia reproducible](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/interacciones.json).

Los selectores tienen nombre accesible explícito; el cambio de persona se anuncia y sus botones expresan expansión/control. Se respeta movimiento reducido y objetivos táctiles de 44 px en móvil. No se realizó una auditoría exhaustiva con lector de pantalla, zoom de todas las pantallas ni medición automática de todos los contrastes.

PASS: `npm run check`, 218 archivos/3106 tests. Última validación tras CSS y copy: lint, 32 tests del prototipo y build con TypeScript. Cuatro advertencias previas en `coverflow-carousel.tsx`. NOT RUN: E2E completa de producción y backend real, fuera del alcance de este prototipo ficticio.

## Cierre

- [x] Composición y datos comparados contra la propuesta elegida.
- [x] Hallazgos P2 corregidos y recapturados.
- [x] Filtros, estados vacíos, exportación y fichas verificados.
- [x] Revisión técnica evaluada y correcciones verificadas: [registro](../../UX-UI-GERENCIA/propuesta-citas-crm-2026-09-08/experiencia/implementacion-3/revision.md).

No quedan diferencias P0/P1/P2 accionables. Refinamiento P3: al cambiar de ancho mientras la ficha está abierta puede reiniciarse su desplazamiento interno al cambiar de modalidad.

final result: passed
