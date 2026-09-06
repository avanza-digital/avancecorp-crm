# Revisión UX1/UX2 — Resumen y Conversiones

Entrega del 6 de septiembre de 2026. Continúa el plan UI-UX (2), bloque A, a partir de la propuesta de Resumen escritorio elegida por Miguel. **Diseño preparado para revisión; frontend aún pausado.**

[Abrir la revisión en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=176-733) · [Prototipo escritorio](https://www.figma.com/proto/1FEvjQkwSzNDsGJ7UUvqIK?node-id=162-264&page-id=108%3A2&starting-point-node-id=162%3A264&scaling=scale-down&content-scaling=fixed) · [Prototipo móvil](https://www.figma.com/proto/1FEvjQkwSzNDsGJ7UUvqIK?node-id=162-718&page-id=108%3A2&starting-point-node-id=162%3A718&scaling=scale-down&content-scaling=fixed).

## Qué está preparado

| Entrega | Resultado |
| --- | --- |
| UX1 — componentes | Tres composiciones propias, nueve presentaciones, sobre las nueve familias y 30 variantes conservadas. [Catálogo y correspondencia con React](../../03-componentes/CATALOGO-UX1.md). |
| UX2 — Resumen escritorio | Se conserva la dirección elegida: indicadores gráficos, pendientes compactos, evolución y responsables. Los indicadores pasan a instancias reutilizables. |
| UX2 — Resumen móvil | Contexto e indicadores más compactos. Evolución situada antes de citas y detalle, comenzando en la primera pantalla de 390 × 844. |
| UX2 — Conversiones | Conversión mensual junto a analistas en escritorio y antes de resultados del rango en móvil. Bases visibles y comparación cercana. |
| Recorrido acotado | Resumen ↔ Conversiones → comparación Carla/Bruno → regreso; en móvil, abrir filtros y volver a cada reporte. |
| Orden y continuidad | Revisión separada de los originales; portada de Figma actualizada, exportaciones locales, catálogo, comprobaciones y nota del Vault. |

## Pantallas de esta revisión

| Vista | Tamaño de diseño | Imagen | Figma |
| --- | --- | --- | --- |
| Resumen escritorio | 1440 × 960 | [Ver](exportados/resumen-escritorio.png) | [162:264](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=162-264) |
| Resumen móvil | 390 × 844 | [Ver](exportados/resumen-movil.png) | [162:718](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=162-718) |
| Conversiones escritorio | 1440 × 960 | [Ver](exportados/conversiones-escritorio.png) | [165:454](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=165-454) |
| Conversiones móvil | 390 × 844 | [Ver](exportados/conversiones-movil.png) | [165:843](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=165-843) |
| Comparación escritorio | 1440 × 960 | [Ver](exportados/comparacion-escritorio.png) | [167:638](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=167-638) |
| Comparación móvil | 390 × 844 | [Ver](exportados/comparacion-movil.png) | [167:909](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=167-909) |
| Filtros de Resumen móvil | 390 × 844 | [Ver](exportados/filtros-resumen-movil.png) | [167:1106](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=167-1106) |
| Filtros de Conversiones móvil | 390 × 844 | [Ver](exportados/filtros-conversiones-movil.png) | [167:1272](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=167-1272) |

Las ocho vistas tienen desplazamiento vertical de contenido. Una exportación de la primera pantalla no representa todo el contenido inferior. El prototipo permite recorrerlo. Los originales `112:14`, `113:55`, `113:366` y `113:734` se conservan como referencia; esta revisión no los sustituye por un rediseño ajeno al CRM.

## Autoevaluación

- Las ocho vistas se comprobaron por estructura: fuentes esperadas, límites horizontales, desplazamiento y destinos. No se encontraron desbordamientos horizontales de los elementos revisados.
- Las acciones activas del recorrido móvil cumplen 44 × 44 px; las 14 filas de navegación móvil se ajustaron a 44 px de alto y caben antes del pie.
- Las tres familias nuevas conservan variables y fuentes del CRM. Se revisó el contraste de texto pequeño sobre las superficies de esos componentes, sin fallos encontrados en esa comprobación concreta.
- Se contrastaron capturas anteriores y nuevas. Se corrigieron fuentes heredadas, barras que conservaban un ancho incorrecto, notas compartidas entre variantes, enlaces que apuntaban a la propuesta anterior y el texto real del estado sin TC.
- El recorrido de escritorio y los accesos de filtros/comparación/regreso de móvil se comprobaron en el visor de Figma de Chrome. La automatización inicial de un enlace móvil no navegó; se recuperó la sesión de prueba y la activación accesible del mismo botón abrió la comparación correcta. No se atribuye ese intento fallido a un error del CRM.
- [462 archivos del frontend sin cambios respecto al inicio](verificacion-fuente.json). Este trabajo no escribió en backend, permisos ni fórmulas. No se ejecutó publicación.

Evidencia estructurada: [QA del diseño](qa-diseno.json), [recorridos técnicos](recorridos-verificados.json), [manifiesto de imágenes](exportados/manifest.json). Los registros completos `calls/`, `scripts/`, `evidencia/` y `state.json` permanecen locales; las exportaciones y resultados curados sí se versionan.

## Datos y límites

Las cifras son ejemplos fijos del CRM para septiembre de 2026: capital S/ 1,840,096 con TC S/ 3.751, conversión mensual 23.06 % sobre 36 leads automáticos, resultado de llegadas 17/184 = 9.2 %, 82 citas pactadas y 58 realizadas, y bases individuales de analistas. Se conservan las diferencias entre mes, rango, llegada, fecha de cierre, atribución y moneda.

Los filtros no son editables ni recalculan datos. La comparación es fija Carla/Bruno; la selección libre, sus botones de detalle, búsqueda y alta son ilustrativos. Los enlaces a Ranking/Citas/Metas llevan a diseños previos, no a un recorrido integrado de este bloque. No hay escrituras comerciales, datos en vivo ni nuevas fórmulas.

No se declara accesibilidad completa, aprobación visual global ni mejora porcentual de tiempo/clics. F0 registra **cero personas observadas**, con tiempos humanos pendientes. UX4/UX5/UX6 completarán estados, recorridos y validación según el plan.

## Qué sigue

1. Revisar con Miguel Resumen móvil y Conversiones en ambos tamaños, manteniendo Resumen escritorio como dirección elegida. Registrar los ajustes y la decisión del bloque A.
2. Completar prioridades/frecuencias y una tarea humana de F0 con el guion ya preparado.
3. Después de la revisión visual prevista, integrar este bloque en el frontend existente y comprobar interacción, datos y estados reales. Continuar Ranking y los demás módulos en el bloque B y las fases UX3–UX6, sin saltar el plan.

Plan vigente: [plan maestro](../../01-plan/PLAN-MAESTRO.md). La organización y F0 se guardaron primero en el commit `387a1b8`; esta revisión se guarda en un segundo commit local, sin push ni despliegue.
