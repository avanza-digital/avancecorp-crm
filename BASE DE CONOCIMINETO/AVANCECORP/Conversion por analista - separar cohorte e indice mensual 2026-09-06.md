# Conversión por analista: separar cohorte e índice mensual

Estado: implementado en frontend; pendiente de publicación.

## Decisión

La cifra principal del detalle de un analista muestra la conversión de sus prospectos:

- numerador: prospectos de su cohorte que ya cerraron;
- divisor: prospectos del período atribuidos al primer analista;
- fuente: `responsables[].conversion_pct`, servida por `crm.metricas_conversiones_fn`.

El índice mensual ponderado se conserva únicamente en el bloque de metas bajo el rótulo **Índice para la meta mensual**. No se presenta como la conversión de los prospectos del analista.

Ejemplo que motivó la corrección: 2 prospectos convertidos de 23 muestran 8.70%. El 14.29% de 3 cierres acreditados sobre una base automática de 21 pertenece al índice mensual ponderado y responde otra pregunta.

La corrección reutiliza los datos ya servidos. No agrega cálculos, funciones independientes ni cambios en los núcleos o contratos del servidor.

## Relacionado

- [[Inventario de indicadores de Gerencia - Comercial]]
- [[Conversion mensual - plan de implementacion]]
- [[Terminologia comercial - prospectos recibidos 2026-09-06]]
