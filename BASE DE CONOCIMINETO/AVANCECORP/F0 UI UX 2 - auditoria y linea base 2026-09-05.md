---
fecha: 2026-09-05
estado: auditoria-experta-realizada-validacion-humana-pendiente
tags: [crm, ux, ui, figma, ux0, continuidad]
---
# F0 / UX0 — Auditoría actual y línea base

Miguel autorizó «ok comencemos la F0» después de recibir [[Plan maestro UI UX del CRM - adaptacion UI-UX 2 2026-09-05]]. Se ejecutó **UX0 del documento UI-UX (2)**. El G-F0 histórico se conserva como antecedente y no se confunden sus cierres.

## Estado real

**Ubicación vigente:** los entregables físicos están en `UX-UI-GERENCIA/02-f0-auditoria`; la ruta anterior de `output/` es un acceso compatible. La página Figma `128:2` se llama ahora «01 · F0 · Auditoría actual». Consultar [[Organizacion local y Figma - UI UX Gerencia 2026-09-06]] y [el índice local](../../UX-UI-GERENCIA/README.md).

**Continuación de F0 — 6 de septiembre:** se completó [[Inventario de reutilizacion frontend - F0 UI UX 2 2026-09-06]] por indicación de Miguel de aprovechar el desarrollo y las librerías actuales. Diez áreas vinculadas a sus componentes existentes; nuevo tablero Figma `138:2`. Dos recorridos móviles no reprodujeron el riesgo de desplazamiento heredado al regresar de Cartera a Resumen; ver tres capturas complementarias en `138:52`. Se mantiene el hallazgo de foco de la ficha y el resto de los nueve hallazgos iniciales; no se aplicó ninguna corrección. Prioridades y prueba humana continúan pendientes.

**Revisión de Miguel — 6 de septiembre:** el enlace `128:2` que estaba viendo corresponde a la auditoría del estado actual. Después aclaró: «la propuesta si me gusta, Propuesta UI-UX (2) · Resumen / desktop esta se va mas con lo que busco». Se registra [Resumen escritorio, nodo `112:14`](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=112-14) como dirección visual elegida para continuar su diseño: más comparación gráfica y lectura comercial, conservando la identidad del CRM. No se registra rechazo de esa propuesta. Esta preferencia no cierra UX0 ni aprueba por extensión móvil, Conversiones, todos los estados o la reanudación de implementación.

La auditoría experta y la preparación de medición están realizadas. **La F0 sigue abierta**: falta confirmar las cinco pantallas más usadas/tres tareas más frecuentes y observar al menos a una persona sin dirigirla. Se preguntó a Miguel durante la ejecución; no hay respuesta registrada. No se midieron tiempos ni éxito humanos y no se declara 100%.

La autorización de F0 es de auditoría, no de implementación ni de publicación. El código continúa pausado. Se conservaron los avances locales anteriores y los cambios concurrentes de otras tareas. Los 462 archivos de `app/src` tienen las mismas huellas al inicio y al control final de esta ejecución; no se modificaron backend, permisos ni fórmulas por esta tarea.

## Entregables

- [Informe completo con 14 capturas actuales](../../output/ux-gerencia-ux0-uiux2-2026-09-05/informe-auditoria.md).
- [Inventario documental de 21 rutas por rol](../../output/ux-gerencia-ux0-uiux2-2026-09-05/inventario-pantallas.md).
- [Nueve hallazgos con prioridad, evidencia, fase y cierre](../../output/ux-gerencia-ux0-uiux2-2026-09-05/hallazgos.json).
- [Tres recorridos y línea base técnica](../../output/ux-gerencia-ux0-uiux2-2026-09-05/linea-base.json).
- [Guion y registro de prueba humana](../../output/ux-gerencia-ux0-uiux2-2026-09-05/prueba-usabilidad.md).
- [Comprobación de huellas del frontend](../../output/ux-gerencia-ux0-uiux2-2026-09-05/verificacion-fuente.json).
- [Figma · resultado y puerta de cierre](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=128-3).
- [Figma · evidencia y notas de 14 pasos](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=128-10).

Figma MCP se verificó y se utilizó. Nueva página `128:2`, «08 · UX0 · Auditoría actual». Se subieron las catorce capturas de demo aceptadas a sus nodos, conservando relación de aspecto y notas. Las propuestas anteriores de UI-UX (2) permanecen en la página `108:2` como diseños por revisar.

## Hallazgos principales

| Prioridad | Hallazgos | Fase de preparación |
| --- | --- | --- |
| P1 | Gráficos de Resumen y Conversiones desplazados hacia abajo; contexto y texto dominan la primera lectura. | UX1 → UX2 / bloque A |
| P1 | Capital del mes muestra sólo PEN en el hero de Conversiones mientras Resumen usa equivalente PEN con USD/TC. Aclarar alcance y moneda sin alterar el dato. | UX1 → UX2 / bloque A |
| P1 | Capital estimado queda en 43 × 36 px a 390 × 844. | UX1 → UX3 / bloque C |
| P1 | Al cerrar la ficha de Cartera el foco termina en BODY; la búsqueda sí permanece. | UX1 → UX4/UX5 |
| P2 | Orden de campos, objetivos táctiles, cuatro acciones por fila, nombres truncados, barras saturadas de Ranking y título móvil de Conversiones. | UX1–UX3 |

La paleta actual de Ranking contiene verde frente a la regla documental «sin verde»: registrar y resolver en UX1, sin borrar variables ni recolorear masivamente en F0. El desplazamiento heredado al navegar en móvil se anotó como riesgo a reproducir, separado de los nueve hallazgos confirmados.

## Avances previos que sí sirven

- Comparar Carla/Bruno funciona con la misma base mensual y conserva selección al navegar.
- Ranking conserva mes, Capital total y foco en Carla al regresar del detalle.
- En móvil: Enter abre el detalle, Shift+Tab recorre el límite y Escape cierra/restaura foco.
- Cartera ya se adapta a lista móvil y conserva la búsqueda después de cerrar ficha.
- Logo, menú, desgloses, períodos, nueve familias de componentes y 72 variables existentes se reutilizan. La existencia de componentes no certifica todos sus estados.
- G-F4 (metas/capacidad) se conserva como antecedente; no fue retestado ni cerrado por esta auditoría.

## Límites que deben persistir

Muestra local Gerencia demo: ocho capturas escritorio 1440 × 960 y seis móvil 390 × 844. No producción, otros roles visuales ni teléfono físico. No se enviaron formularios ni se provocaron fallos de red. La demo tiene filtros de período/origen restringidos; no prueba dinamismo con datos reales. Las acciones del agente no son clics mínimos ni tiempos humanos.

## Siguiente paso

Revisar hallazgos con Miguel, confirmar prioridades reales y realizar la observación del guion. Actualizar la línea base y la decisión de cierre. UX1 tiene definida su entrada — indicadores/monedas, cabecera/período, acciones, tabla/lista, campos, diálogo y estados—, pero no se inicia implementación por el mero cierre de la auditoría.

Relacionado: [[AVC-UX-GERENCIA-FIGMA-20260905-R1]], [[Replanteamiento UI UX con UI-UX 2 - 2026-09-05]], [[Fundamentos UX del CRM]], [[Acceso y roles del CRM]], [[Plan de mejoras UX-UI del CRM]].
