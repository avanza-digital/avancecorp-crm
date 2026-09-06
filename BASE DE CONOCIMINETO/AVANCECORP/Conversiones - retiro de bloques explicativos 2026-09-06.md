---
fecha: 2026-09-06
estado: implementado-localmente
tags: [crm, gerencia, conversiones, ux, decision]
---

# Conversiones — retiro de bloques explicativos

Miguel señaló que los bloques «Llegadas con cita realizada» y «Operaciones elegidas para conversión» de la captura no le resultan claros ni aportan valor comercial. Después de considerar gráficos y un detalle opcional, pidió eliminarlos.

Se retiraron ambos paneles de `inteligencia-comercial.tsx`, incluida la tabla de identificadores de operaciones. No se sustituyen por gráficos ni por otra sección. Se conserva el indicador compacto de citas ya existente, el detalle del analista y los cierres por semana.

El cambio es de presentación: se mantienen las consultas, los datos, las reglas de conversión, los pesos de renovaciones/upgrades y los otros consumidores del contrato. Las 43 pruebas de la pantalla, TypeScript y lint pasan. Esta entrega es local; no implica publicación.

Relacionadas: [[Decisiones UI UX Gerencia - 2026-09-06]], [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]], [[Inventario de reutilizacion frontend - F0 UI UX 2 2026-09-06]].
