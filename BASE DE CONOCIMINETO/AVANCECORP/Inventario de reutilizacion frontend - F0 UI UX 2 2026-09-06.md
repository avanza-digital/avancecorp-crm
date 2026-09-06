---
fecha: 2026-09-06
estado: inventario-realizado-validacion-humana-pendiente
tags: [crm, ux, ui, figma, ux0, reutilizacion]
---
# F0 — Reutilizar el desarrollo del CRM

Miguel pidió continuar F0 y reiteró: el CRM ya tiene mucho desarrollo y buenas librerías React; debemos aprovecharlos. Es una regla de trabajo vigente para [[Plan maestro UI UX del CRM - adaptacion UI-UX 2 2026-09-05]], junto a la dirección elegida «Propuesta UI-UX (2) · Resumen / desktop».

## Resultado de esta continuación

Se documentaron diez áreas: marca/navegación, indicadores, gráficos de Gerencia, gráficos Recharts, período/regreso, tablas/listas, formularios, paneles/foco, estados/avisos y movimiento. Cada una tiene base existente, fuentes de código y decisión para las siguientes fases.

- [Inventario editable en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=138-2).
- [Inventario completo con fuentes y librerías declaradas](../../output/ux-gerencia-ux0-uiux2-2026-09-05/continuacion-2026-09-06/inventario-reutilizacion.md).
- [Comprobación móvil complementaria en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=138-52).
- [Informe de continuación](../../output/ux-gerencia-ux0-uiux2-2026-09-05/continuacion-2026-09-06/informe-continuacion.md).

La muestra de archivos comprende 16 UI, 14 comunes y 16 de Gerencia; no equivale al número de componentes ni a una certificación integral. ECharts ya está integrado en los reportes activos. Recharts y sus adaptadores están disponibles; no se encontró un import activo de `GraficasGerencia`, por lo que no se debe insertar ese panel antiguo por el mero hecho de existir. Radix, Lucide, GSAP, Sonner, Tailwind y la infraestructura de consulta se mantienen como base.

Se consultó CodeGraph primero y se complementaron las rutas ausentes con búsqueda/lectura puntual, sin reindexar. No se instalaron ni actualizaron librerías. El inventario no introduce cambios en el frontend, backend, permisos ni fórmulas.

## Comprobación pendiente de móvil

Se repitió Resumen → Cartera → Resumen a 390 × 844, con y sin búsqueda. Ambos regresos terminaron en desplazamiento 0; el segundo partía de Cartera a 579 px estables. El riesgo de desplazamiento heredado observado antes no se reprodujo en estas condiciones. No se declara corregido: no hubo corrección y el escenario anterior incluía cambio de tamaño. Quedan tres capturas representativas en Figma y el registro de mediciones local.

La búsqueda de Cartera se conserva al cerrar su ficha según la auditoría inicial; al cambiar de módulo y entrar de nuevo quedó vacía. No extender la garantía de conservación de consulta de los reportes a todo el CRM.

## Estado para retomar

La F0 sigue abierta por las prioridades/frecuencias reales y la observación humana, según [[F0 UI UX 2 - auditoria y linea base 2026-09-05]]. Se dejó Resumen en demo local, tamaño normal y menú abierto. Se presentó a Miguel una tarea de lectura/comparación; no hay respuesta registrada, observación humana ni tiempos medidos. Un comentario posterior sobre esa tarea será autoinforme salvo que se observe realmente el recorrido.

Las mejoras se preparan con los componentes actuales; una variante nueva debe resolver una carencia concreta. Primero diseño y revisión en las fases previstas; la implementación sigue pausada. Relacionado: [[AVC-UX-GERENCIA-FIGMA-20260905-R1]].
