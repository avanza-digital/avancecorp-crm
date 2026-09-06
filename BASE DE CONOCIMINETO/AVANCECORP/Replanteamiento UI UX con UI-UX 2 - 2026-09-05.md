---
fecha: 2026-09-05
estado: propuesta-para-revision-implementacion-pausada
tags: [crm, ux, ui, figma, continuidad]
---
# Replanteamiento UI y UX con UI-UX (2)

Miguel pidió pausar la implementación y preparar un plan de mejora UI y UX basado en `CRM-Avance-Corp/UI-UX (2).pdf`, conservando la esencia del CRM existente. La entrega solicitada incluye guardar sus elementos actuales, investigar componentes y recursos de Figma compatibles y mostrar una propuesta editable de cómo se vería el CRM antes de continuar con código.

Esta instrucción sustituye el avance automático de implementación de [[AVC-UX-GERENCIA-FIGMA-20260905-R1]]. El trabajo ya realizado se conserva como base local; no se descarta ni se considera aprobado por estar implementado. El plan general del documento (fases 0–6) y el plan de Gerencia (F0–F5) tienen numeraciones diferentes: se debe documentar su correspondencia.

## Preferencias vigentes

El plan adaptado está en [[Plan maestro UI UX del CRM - adaptacion UI-UX 2 2026-09-05]]. Figma contiene una página nueva, **07 · UI-UX (2) · Plan y propuesta**, con cinco capturas actuales conservadas, recursos evaluados y una muestra editable de Resumen y Conversiones en escritorio y móvil. La muestra no equivale al rediseño completo del CRM ni a aprobación de Miguel.

- Conservar marca, navegación familiar, vocabulario comercial, componentes útiles y comportamiento existente.
- Resumen debe comunicar visualmente cómo va el negocio: más gráficos útiles, menos texto inicial, conservando medida, período, base y explicación ampliable.
- Miguel rechazó la presentación visual de Conversiones. Su corrección queda pendiente de esta nueva revisión de diseño; no está aprobada.
- Alcance de diseño y frontend. Backend, permisos y fórmulas permanecen fuera del cambio. No hay autorización de publicación para este trabajo.
- Durante la preparación del nuevo plan se permiten lectura, capturas, documentación y diseño en Figma; la implementación del CRM queda en pausa por instrucción expresa.

## Base existente que debe aprovecharse

- Figma verificado por MCP: archivo `1FEvjQkwSzNDsGJ7UUvqIK`, con auditoría, nueve familias de componentes, 72 variables, estilos, piloto Ranking y referencias F2–F4.
- F1: mejoras locales de contexto, regreso a Ranking, cabecera móvil y detalle. Parte de los recorridos se probó con datos demo.
- F2: Resumen y Citas implementados localmente; Resumen todavía requiere la revisión visual solicitada.
- F3: comparación y lectura progresiva implementadas; presentación visual pendiente y rechazada por Miguel.
- F4: revisión antes de cambios de capacidad/metas y retorno a consultas implementados localmente, con pruebas focales; revisión completa en navegador y diseño aún pendientes.
- Las pruebas automáticas previas no equivalen a validación de usabilidad con Gerencia ni cierre visual. F5 no está cerrada.

Relacionado: [[Plan de mejoras UX-UI del CRM]], [[Fundamentos UX del CRM]], [[Plan de mejora UX de Gerencia - revision 2026-09-05]], [[Desarrollo UX Gerencia - F1 y F2 2026-09-05]].
