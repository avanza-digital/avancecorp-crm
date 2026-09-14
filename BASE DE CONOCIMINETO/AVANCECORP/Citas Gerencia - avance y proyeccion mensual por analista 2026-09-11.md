---
fecha: 2026-09-11
estado: propuesta-visual-bases-pendientes
tags: [crm, citas, gerencia, metricas, proyeccion]
---

# Citas Gerencia — avance y proyección mensual por analista

**Actualización 13/09:** Miguel confirmó entrevistas repetidas, ticket del mes consultado e inclusión de leads manuales y sus citas. Véase [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]]. Las propuestas y pendientes de esta nota son históricos cuando contradigan esa aclaración; no se ha activado la proyección.

Después de ver el panel de Superadmin, Miguel aclaró el flujo: **cita generada por el analista en el CRM → asistencia a esa cita, que cuenta como entrevista → conversión posterior a cliente, que acredita depósito**. Quiere medir cuántos entrevistados se convierten a cliente frente al objetivo del 70%.

Luego solicitó una propuesta visual que agregue el **cierre mensual proyectado con los porcentajes actuales y el ticket medio de cada analista**, aprovechando lo que ya existe en Citas. Continúa explicando la lógica; no interpretar esta solicitud visual como aprobación de una fórmula productiva.

## Propuesta presentada

En la misma tabla de analistas: entrevistas (% y base), depósitos (% y base), ticket de referencia y monto estimado de cierre. Comparación secundaria con el escenario de ambos objetivos al 70%; detalle y simulación a demanda. Se conserva el módulo horizontal de recuperación de inasistencias y no se muestra la meta interna de 1,25 en el tablero.

Visual de conversación: `UX-UI-GERENCIA/proyeccion-citas-2026-09-11/cierre-por-analista.html`. La guía contigua documenta la aritmética, limitaciones y ejemplos. No cambia archivos de ejecución del CRM ni el SQL candidato.

## Bases todavía por elegir

Se preguntó qué ticket usar (histórico anterior, mes actual o configurable) y si el volumen de citas debe salir del ritmo real o de la meta calculada sobre leads asignados. Ambas preguntas siguen pendientes al preparar esta nota.

Para ilustrar solamente: corte al 10/09/2026, 10 de 30 días calendario, ticket histórico de ejemplo y ritmo constante. Citas previstas = citas generadas / días transcurridos × días del mes; clientes esperados = citas previstas × asistencia × conversión; captación esperada = clientes esperados × ticket. Es un total de cierre, no un importe adicional al conseguido. El 70% alimenta un escenario objetivo, no sustituye las tasas observadas en el pronóstico.

El ejemplo usa entrevistas de personas distintas y citas con resultado; antes de producción deben resolverse entrevistas repetidas, citas futuras/pendientes, desfases de conversión, límites de población elegible, atribución temporal/al analista, exclusión de manuales, fuente y moneda del ticket. Conversión acredita un depósito, pero no por sí sola su importe. No mezclar PEN/USD, tratar falta de ticket como dato insuficiente y evitar sumar porcentajes o promedios de analistas sin sus bases.

Estas aclaraciones definen qué es entrevista y la relación del depósito con ella; no confirman todavía la unidad para contar visitas repetidas. No se actualizó ni activó la configuración productiva. El panel anterior conserva sus borradores hasta acordar e implementar la lógica completa.

Relacionado: [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]], [[Citas Gerencia - analisis del Excel de proyeccion por analista 2026-09-10]], [[Fundamentos UX del CRM]], [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]].

## Pausa solicitada por Miguel — integración visual pendiente

Miguel pidió mostrar cómo integrar el avance de las metas de cada analista en lo existente. Se propuso mantener el recorrido de inasistencias en **Citas → Resultados** y ampliar la tabla de analistas con cumplimiento de citas, asistencia frente a 70%, conversión frente a 70%, ticket y cierre estimado. La regla de 1,25 permanece interna; las brechas se abren al seleccionar al analista.

Se escribió `UX-UI-GERENCIA/proyeccion-citas-2026-09-11/integracion-resultados.html`, una segunda visualización de conversación con marco del CRM, filtros y detalle a demanda. **No se presentó aún al usuario ni se verificó su sintaxis, aritmética o interacción.** No equivale a integración en la aplicación. Es un borrador para revisar al retomar.

Antes de presentarla, revisar especialmente: el uso propuesto de semanas como cortes de avance mensual acumulado (no aprobado todavía), el alcance de los porcentajes frente a metas, la coherencia de las cifras de ejemplo y del recorrido por persona, y las hipótesis de ritmo futuro/ticket. El borrador integrado cambia el ejemplo de Carla a 30 clientes de 42 entrevistados para mostrar una analista que llega a las tres metas; no son datos reales. No modifica la primera visualización ya presentada.

Miguel interrumpió con «okok para el trabajo seguimos mas tarde». **Pausar aquí; no continuar implementación, pruebas, instalación SQL, commits ni publicación hasta que retome.** Los nuevos archivos están guardados localmente. Las preguntas sobre fuente del ticket y base de volumen de la proyección siguen sin respuesta; no tratar el tiempo transcurrido como confirmación.

## Retoma de la propuesta integrada

Miguel indicó «sigue». Se retomó la revisión de `integracion-resultados.html` y su presentación visual en la conversación. Se corrigieron la etiqueta de fecha de reprogramación y los selectores dependientes de supervisor/analista.

La verificación de sintaxis y de interacción mediante JSDOM pasó: cálculos y brechas de las tres metas, filtros, cortes al 7/10, etapas y lista del recorrido, falta de datos y foco del detalle. **Inspección visual en navegador y datos productivos: NOT RUN.** No se modificó el runtime del CRM, no se ejecutó SQL ni se publicó.

La propuesta conserva recuperación de inasistencias arriba y amplía la tabla de analistas debajo. Las cifras permanecen ficticias, la regla de 1,25 es interna y seleccionar un analista abre sus cantidades conseguidas frente al objetivo y las brechas del corte. Presentar el ejemplo no confirma el ticket, la fórmula de proyección ni los cortes semanales acumulados; esas decisiones siguen abiertas.

## Presentación en navegador local

Miguel pidió «en local muéstrame cómo se ve». Se exportó la propuesta a `CRM-Avance-Corp/app/prototypes/citas-metas.html`, accesible en <http://127.0.0.1:4180/prototypes/citas-metas.html>. Se abrió en Chrome, se inspeccionó el renderizado inicial y se dejó la pestaña abierta. Las dos secciones y las tres filas se muestran correctamente en esa vista. No se modificó la pantalla productiva ni se conectaron datos reales; la exportación sigue usando los ejemplos y decisiones pendientes de esta nota.
