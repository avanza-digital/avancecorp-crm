# Inasistencias que terminaron en depósito

Ampliación local solicitada por Miguel el 8 de septiembre de 2026. Disponible en http://127.0.0.1:4180/prototypes/citas-crm.html, pestaña **Resultados**, apartado de inasistencias.

## Uso

El flujo es **No asistieron → Se reprogramaron → Asistieron después → Leads que depositaron**. Cada tarjeta abre los leads de esa etapa; cada etapa es un subconjunto de la anterior. La franja inferior muestra conversión sobre la base inicial y montos por moneda. **Ver depósitos** muestra la inasistencia, el registro de la reprogramación, la asistencia real y los movimientos confirmados. El acceso **Sin nueva cita** se conserva como filtro compacto.

Los filtros habituales eligen las inasistencias de origen. El mes y la semana no recortan los depósitos posteriores: se siguen hasta el corte del ejemplo. Los filtros de moneda y monto siguen refiriéndose al estimado de la cita; los depósitos de los leads seleccionados se muestran en su propia moneda.

## Definición del ejemplo

- Base: leads únicos con al menos una inasistencia en la consulta, ocurrida hasta el corte.
- Reprogramaron: leads de esa base con una sucesora vinculada expresamente a una inasistencia filtrada, registrada hasta el corte.
- Asistieron: leads de la etapa anterior con una cita realizada en esa cadena y una fecha real de asistencia válida, posterior a la inasistencia, no anterior al registro de reprogramación y hasta el corte. Una nueva cita posterior no borra una asistencia ya cumplida.
- Depositantes: leads que llegaron a asistencia y realizaron después un depósito confirmado y no anulado al corte. Se usa el instante real de asistencia; la hora prevista no lo sustituye.
- Conversión: depositantes / base de leads con inasistencia. Sin base no se calcula porcentaje.
- Un mismo lead cuenta una sola vez aunque haya faltado varias veces o realizado varios depósitos. Cada movimiento se suma una vez por id.
- Se excluyen pendientes, anulaciones conocidas al corte, fechas inválidas, depósitos anteriores o simultáneos a la asistencia, depósitos o confirmaciones posteriores al corte, montos no positivos y movimientos de otros leads.
- Un depósito sin reprogramación y asistencia queda fuera de este flujo. Todas las etapas cuentan leads únicos, no una mezcla de citas y personas.
- Si hay varios episodios filtrados del mismo lead, cada etapa conserva un episodio que cumple su condición: el más antiguo para base y reprogramación; la primera asistencia válida para recuperación y depósitos. El desempate es estable por fecha e id. El detalle conserva el origen real de la cadena que califica, sin inventar un vínculo entre episodios independientes.
- El vínculo por lead y orden temporal muestra una conversión de la cohorte; no prueba causalidad ni atribuye un depósito a un ciclo concreto.
- Nunca se interpreta `cerrado` o el monto estimado de la cita como depósito.

Ejemplo fijo al 7 de septiembre de 2026, 13:00 Lima: **4 → 3 → 1 → 1**, con **1 de 4 leads convertido (25%), S/ 35.000**. Andrea Peralta faltó el 1 de septiembre a las 11:00; reprogramó ese día a las 17:00; asistió el 3 a las 11:05 y depositó el 4 a las 10:00 (confirmación 10:05). Mónica y Pablo tienen nuevas citas pendientes; Esteban no tiene una nueva cita vinculada. Su depósito ficticio sigue en los datos, pero se excluye al no completar el flujo. Los movimientos pendientes y anulados tampoco incrementan el indicador.

Esta definición incorpora la corrección explícita de Miguel: no pueden aparecer más depositantes que asistentes dentro del mismo flujo. Sustituye la interpretación anterior que incluía depósitos sin asistencia.

Los depósitos son fixtures expresos de la propuesta. No se modificaron datos reales, APIs, contratos, lógica financiera productiva, migraciones ni componentes compartidos. La integración real requiere movimientos confirmados identificables, vínculo fiable al lead y validación del contrato de lectura; los cierres y el capital acumulado de Gerencia no se renombraron como depósitos.

## Verificación

- **PASS:** pruebas del prototipo incluidas en la suite general. Cubren etapas anidadas para todos los asesores y semanas, identidad, doble conteo, asistencia intermedia en una cadena, orden de entrada, fecha real de asistencia, corte, confirmación, anulación, monedas, filtros, vacío, detalle y retorno de foco.
- **PASS:** `npm run test:run`, 3.098 tests en 216 archivos sobre el árbol local existente.
- **PASS:** `npm run lint`, sin errores; cuatro advertencias previas en `coverflow-carousel.tsx`.
- **PASS:** `npm run typecheck` y `npm run build`. Continúan avisos previos de chunks y `demo-config.ts`.
- **PASS:** Chrome, flujo visible 4 → 3 → 1 → 1; filtro Ana: 1/1, Diego: 0/1; detalle, fechas y cierre. Sin desbordamiento a 390 px y 1.227 px CSS. Consola sin errores capturados durante la comprobación.
- Revisión independiente de esta corrección: **CHANGES_REQUESTED**, completada con el wrapper. Codex corrigió la pérdida de una asistencia intermedia y el desempate de episodios; evaluó los demás puntos y ejecutó de nuevo todos los checks. Véanse [dictamen recibido](review-claude-flujo.md) y [evaluación de Codex](evaluacion-codex-flujo.md). No se solicitó un segundo dictamen ni se presenta el primero como PASS.
- **NOT RUN:** `check:all`, matriz completa de dispositivos/lectores de pantalla y pruebas de datos reales. Es una ampliación del prototipo local; no hay integración de backend ni publicación.

Evidencia ficticia actualizada: [consulta de escritorio](consulta-escritorio.png), [página móvil con detalle abierto](detalle-movil.png). Las capturas completas incluyen espacio de la página alrededor de la ficha fija. El viewport temporal se restableció al concluir la revisión.

Implementación: `depositos.ts` contiene fixtures y lectura derivada; `inasistencias.tsx` agrupa seguimiento y detalle, extraídos de `resultados.tsx`. La guía **Cómo usar Citas** explica el indicador y su período.
