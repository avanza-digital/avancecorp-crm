---
fecha: 2026-09-06
estado: bloque-a-diseno-preparado-revision-pendiente
tags: [crm, gerencia, ux, ui, figma, continuidad]
---

# UX1 y UX2 — componentes y revisión visual de Gerencia

Miguel autorizó continuar el plan principal y guardar commits por bloques. La entrega prepara UX1 y la revisión UX2 de Resumen/Conversiones, partiendo de la dirección de Resumen escritorio `112:14` que eligió. **La implementación sigue pausada hasta la revisión visual acordada.** F0 conserva pendientes las prioridades de uso y una observación humana.

## Abrir primero

- [Revisión UX2 en Figma](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=176-733).
- [Resultado, imágenes y comprobaciones locales](../../UX-UI-GERENCIA/04-propuestas/revision-ux1-ux2-2026-09-06/README.md).
- [Catálogo UX1 con correspondencia al CRM](../../UX-UI-GERENCIA/03-componentes/CATALOGO-UX1.md).

## Qué se conserva y qué se preparó

Se conservaron nueve familias/30 variantes, 72 variables, ocho estilos de texto y dos de efectos. Se añadieron tres composiciones nativas a partir de las piezas propias: Indicador visual (seis variantes), Período compacto (un componente) y Conversión por analista (dos variantes). No se instalaron librerías ni se sustituyó la base React/ECharts del CRM.

Los componentes nuevos reutilizan los indicadores, acciones y barras de las propuestas anteriores. La correspondencia con React es documental; no existe una sincronización Code Connect verificada. Las nuevas posiciones, tamaños y barras son diseño pendiente de integración con el frontend existente.

| Pantalla | Escritorio | Móvil |
| --- | --- | --- |
| Resumen | `162:264` | `162:718` |
| Conversiones | `165:454` | `165:843` |
| Comparación Carla/Bruno | `167:638` | `167:909` |
| Filtros de Resumen / Conversiones | Contexto visible en cada reporte | `167:1106` / `167:1272` |

Las vistas nuevas están en «03 · Propuestas · UI-UX (2)», separadas de los originales conservados. La portada `147:3` dirige a la revisión vigente. Biblioteca nueva: documentación `156:10`, `158:1600`, `164:476`; estados móviles `160:29`.

Resumen escritorio mantiene la jerarquía elegida. El móvil compacta contexto/indicadores y coloca evolución antes de citas y detalle. Conversiones presenta conversión mensual y analistas primero, con resultados del rango agrupados después. Los porcentajes, bases, monedas, períodos y atribuciones conservan su significado original.

## Verificación y límites

Se inspeccionaron las ocho vistas y las tres familias nuevas: tipografías del CRM, límites horizontales, variables, contraste de texto en sus superficies, tamaños táctiles activos y destinos. Se corrigieron fuentes heredadas, escalas de barras, notas de variantes compartidas y conexiones a pantallas anteriores. El mensaje real de la muestra sin TC distingue importes por moneda de un equivalente pendiente.

El visor de Figma en Chrome permitió comprobar Resumen → Conversiones → comparación → regreso en escritorio y móvil, además de abrir/cerrar los filtros móviles. Son recorridos técnicos del agente. No prueban tiempo, éxito ni clics de una persona, ni teclado/foco de la aplicación React. La verificación SHA-256 conservó los 462 archivos de `app/src` respecto al inicio del bloque.

El prototipo usa ejemplos fijos de septiembre de 2026. Los filtros no se editan ni recalculan; Carla/Bruno es una comparación fija. Selección libre, detalle de ambos, búsqueda y alta siguen siendo ilustrativos. Ranking, Citas y Metas enlazan a referencias previas; no se completó un nuevo recorrido integral de esos módulos.

F0 continúa con cero participantes observados y sin tiempos humanos. UX4 mantiene la matriz completa de estados; UX5, las tareas integrales; UX6, la validación continua. No se declara todo el CRM al 100 %.

## Próximo paso y guardado

Revisar visualmente con Miguel Resumen móvil y Conversiones en ambos tamaños, registrar sus ajustes y la decisión del bloque A. Completar las prioridades/observación de F0. Después de la revisión prevista, implementar el bloque con las consultas, operaciones y componentes actuales y ejecutar pruebas del frontend.

Ranking mantiene su piloto de escritorio/móvil, detalle y regreso en el bloque B y UX3; Citas, Metas, Rendimiento y los bloques C/D conservan el orden del plan. No se adelantó un cambio de backend, permisos o fórmulas.

La organización y F0 se guardaron en el commit local `387a1b8`. La revisión UX1/UX2 se guarda en un segundo commit local con documentación y exportaciones curadas. Los registros MCP completos se conservan en la carpeta local y se excluyen de Git. No se hizo push ni despliegue. Los cambios de implementación anteriores/concurrentes permanecen fuera de estos commits.

Relacionadas: [[Plan maestro UI UX del CRM - adaptacion UI-UX 2 2026-09-05]], [[AVC-UX-GERENCIA-FIGMA-20260905-R1]], [[Inventario de reutilizacion frontend - F0 UI UX 2 2026-09-06]], [[F0 UI UX 2 - auditoria y linea base 2026-09-05]], [[Organizacion local y Figma - UI UX Gerencia 2026-09-06]].
