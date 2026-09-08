# Evaluación del review de Citas

Codex PRIMARY; Claude SECONDARY_REVIEWER. Una consulta mediante `scripts/claude-review`, sin herramientas, escritura ni delegación. LEVEL 2 por nueva lógica de consulta y navegación. Dictamen original: [CHANGES_REQUESTED](revision-claude.txt), confianza media por dependencias no adjuntadas. No se solicitó una segunda revisión para obtener conformidad.

## Hallazgos evaluados

- **Promedio vacío:** descartado como defecto. `src/lib/format.ts`, función `numero`, acepta `number | null | undefined` y devuelve «—» para null o valores no finitos. Se agregó una aserción de pantalla para un mes vacío. Typecheck y tests pasan.
- **Navegación desde ficha de una reprogramación fuera del filtro:** aceptado. `verAnalistaDeFicha` restablece la consulta al mes de la cita y al analista de la ficha. La navegación desde la tabla de Resultados conserva los filtros, porque allí sí se está desglosando el mismo conjunto. Nuevo test reproduce el salto desde semana 1 / no asistieron hacia las citas de Valeria y confirma que la nueva cita del 9 de septiembre aparece.
- **Totales de leads no sumables:** aceptado como aclaración comercial. La nota de Resultados explica que un lead compartido cuenta para cada asesor y una sola vez en el total; también explica el recálculo de leads repetidos y promedio.
- **Campos de fecha personalizada sin acceso:** aceptado. Se retiraron los inputs Desde/Hasta, su chip y validación visual separada. La UI del ejemplo solo ofrece mes y semana; el adaptador traduce ese período al rango inclusivo del modelo original.
- **Pruebas de semanas débiles:** aceptado. Se generan citas para cada día de meses de 28, 29, 30 y 31 días. Se comprueban tamaños, partición sin duplicados, igualdad con el mes completo e inclusión del último día. La segunda semana del fixture tiene ocho citas.
- **Identidad del fixture:** se agregó prueba de id canónico, nombre/teléfono únicos por id y relaciones de reprogramación dentro del mismo lead.
- **CSV en error:** se agregó `finally` para quitar el enlace y liberar la URL aun si el click falla. La guía especifica que exporta citas, no los promedios o el seguimiento. El modelo existente ya escapa las celdas CSV; no se cambió su contrato.
- **Regiones accesibles:** se agregó `role="region"` a las dos tarjetas principales con nombre accesible.
- **Sucesoras múltiples:** documentada la regla de registro más reciente/desempate por id. No se afirma que sea el contrato productivo. Los ids y fechas del fixture son estáticos; su formato HH:MM está normalizado. La comparación temporal actual es coherente con ese formato.
- **Foco del Sheet:** se mantuvo el componente compartido intacto. El retorno al disparador y el salto al tab destino tienen pruebas; se comprobó navegación en Chrome. Exponer una nueva API de foco del Sheet queda fuera del alcance de esta propuesta local.
- **Estado de etapa sin coincidencias:** la selección se conserva y se muestra «No hay citas en esta etapa»; no se restablece silenciosamente una selección del usuario.
- **Reutilización y alcance:** `prototypes/` está dentro de la raíz de Vite (`CRM-Avance-Corp/app`), no fuera. Los estilos adicionales se cargan desde `main.tsx` de la propuesta y están acotados a sus clases. No se modificaron estilos ni componentes compartidos.

Los textos con el corte y el mes del ejemplo son deliberadamente fijos. Optimización de lecturas duplicadas sobre 40 fixtures, exportación de métricas, parametrización temporal y contrato de sucesores reales quedan para la integración. No son garantías de producción de esta entrega.

Tras los ajustes: lint y typecheck PASS; 3.079 tests en 214 archivos PASS; build PASS. Los límites de la revisión visual y gates no ejecutados se registran en README.
