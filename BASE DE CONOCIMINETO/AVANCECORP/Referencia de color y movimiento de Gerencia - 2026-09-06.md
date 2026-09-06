---
fecha: 2026-09-06
estado: direccion-visual-ampliada-en-revision
tags: [crm, ux, figma, color, movimiento]
---

# Referencia de color y movimiento de Gerencia

Miguel consideró bonita pero demasiado estática la propuesta anterior. Preguntó por GSAP y después informó que está mejorándola con el agente de Figma. Pidió revisar esa versión porque quiere colores y otros recursos que ayuden a entender la información.

La referencia comprobada por MCP es [Resumen escritorio `112:14`](https://www.figma.com/design/1FEvjQkwSzNDsGJ7UUvqIK?node-id=112-14), seleccionado en el navegador mediante su área `112:176`. Ahora presenta iconos, barras con azul/verde/ámbar/naranja, gradientes suaves y etiquetas de contexto con fondo. La estructura y las cifras continúan siendo las del ejemplo. La vista móvil `113:55` todavía no reflejaba esos colores al capturarla.

**Decisión de continuidad:** tomar esa dirección cromática como referencia para las siguientes propuestas. La restricción anterior de no ampliar el verde no debe usarse para rechazar la nueva preferencia explícita de Miguel. La semántica de cada color sigue por definir: categoría, serie, cumplimiento o atención. No inventar umbrales, alertas ni reglas de negocio. El verde del indicador mensual y los colores por analista necesitan una explicación consistente con sus bases y objetivos.

El agente de Figma está trabajando la parte visual. Revisar su estado actual antes de editar, coordinar la referencia y conservar la compactación móvil, componentes y recorridos ya preparados en [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]]. La versión `176:733` conserva esa entrega anterior; no refleja por sí sola la actualización cromática observada en `112:14`.

GSAP y `@gsap/react` ya se usan en `components/gerencia/motion.tsx`, con entradas de controles/indicadores/paneles y preferencia de movimiento reducido. La mejora propuesta debe conectar movimiento con cambios de consulta, selección, comparación y detalle. La consulta actual de Context7 confirmó el patrón de `useGSAP`, alcance y limpieza de dependencias. No se implementó ni probó movimiento nuevo en esta revisión.

Evidencia: [revisión de escritorio/móvil con capturas nuevas](../../UX-UI-GERENCIA/05-validacion/revision-propuesta-color-2026-09-06/README.md). Figma se consultó sólo en lectura. No se modificó código, backend, permisos ni fórmulas. Continúan UX2/UX4/UX5 y la revisión visual prevista antes de frontend; F0 mantiene pendiente la observación humana.

Relacionadas: [[Plan maestro UI UX del CRM - adaptacion UI-UX 2 2026-09-05]], [[AVC-UX-GERENCIA-FIGMA-20260905-R1]], [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]].
