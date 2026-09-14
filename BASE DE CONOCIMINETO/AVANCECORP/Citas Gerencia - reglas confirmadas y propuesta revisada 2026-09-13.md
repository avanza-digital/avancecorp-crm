---
fecha: 2026-09-13
estado: reglas-aclaradas-propuesta-por-revisar
tags: [crm, citas, gerencia, metas, reglas-negocio]
---

# Citas Gerencia — reglas aclaradas y propuesta revisada

Estado posterior: [[Citas Gerencia - avance integrado sin deploy 2026-09-13]].
Esta nota conserva el historial de aclaraciones y de la presentación aprobada.

Miguel respondió: «1. cuenta dos veces, el ticket se cuenta por mes es el periodo, sii cunetan las citas y cunetan los leads». Después pidió repasar todo y explicar cómo quedaría. Esta nota conserva las aclaraciones; no acredita implementación ni publicación.

## Confirmado

- Meta de citas: **1,25 citas por lead**, configurada internamente. Por ejemplo, 100 leads y 125 citas equivalen a **100% de cumplimiento de esa meta**. No sumar un objetivo adicional de 125% ni volver a la regla anterior de tres citas.
- Objetivos de entrevistas y depósitos: **70% y 70%**. La fórmula exacta de sus bases debe distinguirse de estos valores ya acordados.
- La base mensual incluye los leads asignados, incluso sin citas. **Ahora también cuentan los leads registrados manualmente y sus citas**. Esta respuesta sustituye la exclusión anterior; no volver a preguntarla como si siguiera pendiente.
- Cita: generada en el CRM. Entrevista: asistencia a una cita. **Si una persona asiste dos veces, suma dos entrevistas**.
- Depósito: acreditado al convertirse en cliente mediante el flujo del CRM. Una conversión no se duplica por varias entrevistas de esa persona.
- Ticket: de **cada analista y del mes consultado**. Queda resuelta la elección del período; no confundirla con haber conectado ya la fuente monetaria real.
- Mantener el recorrido horizontal de inasistencias y la tabla por analista, con filtros compactos, estilos del CRM y detalle a demanda. La recuperación conserva personas únicas y la secuencia vinculada: no asistió → reprogramó → asistió después → se convirtió a cliente.

## Propuesta de integración, no decisiones nuevas confirmadas

En Citas → Resultados: filtros compactos; recorrido horizontal de recuperación; una tabla por analista con leads, citas, cumplimiento, entrevistas/asistencia, clientes/conversión, ticket del mes y cierre estimado. Mantener Bandeja y Agenda. Evitar repetir los conteos en tarjetas grandes. Superadmin deberá poder activar una configuración con vigencia e historial; el guardado de borradores existente no basta.

Las cuatro semanas comerciales son tramos 1–7, 8–14, 15–21 y 22–fin del mes, no cuatro semanas naturales exactas. El alcance semanal de actividad debe quedar separado y rotulado frente al cumplimiento y la proyección mensuales; un filtro de estado no debe inflar artificialmente una tasa al eliminar su base.

Para convertir entrevistados a clientes se propone usar **personas entrevistadas únicas** como denominador, conservando cada asistencia en el contador de entrevistas. Esto evita que una segunda visita cambie la conversión de una misma persona de 100% a 50%. **Miguel confirmó el conteo repetido de entrevistas, pero no confirmó todavía este denominador del 70% de depósitos.** Si se elige el total de entrevistas como en el encadenamiento literal del Excel, hay que explicitar esa unidad y sus efectos; no cambiar de base silenciosamente.

Para cierre mensual se propone usar el ritmo observado, tasas reales y ticket del mes. La estimación de clientes debe descontar entrevistas repetidas y respetar la población elegible; multiplicar entrevistas repetidas por una tasa calculada sobre personas únicas sería incorrecto. El escenario de metas 70/70 es distinto del pronóstico con tasas actuales. La fórmula de proyección sigue siendo propuesta, no regla activada.

Conservar como pendientes de definición o implementación: base exacta del avance de entrevistas y tratamiento de citas futuras/sin resultado, atribución al mes y al analista cuando cambia el responsable o el resultado cruza de mes, vigencia de la configuración y fuente monetaria del ticket. Proponer soluciones concretas sin presentarlas como respuestas de Miguel. El dinero debe provenir de importes reales vinculados al cierre; no de la estimación del lead, ni mezclar monedas. Sin base suficiente, mostrar dato insuficiente.

## Estado técnico al revisar

La corrección local de [[Citas Gerencia - meta incorrecta detectada y correccion local 2026-09-13]] conserva todavía exclusiones de manuales y decisiones nulas. **Las últimas respuestas no están aplicadas al runtime, al candidato SQL ni a la configuración.** Las comprobaciones anteriores sólo cubren el alcance y las reglas anteriores. El panel de Superadmin sigue siendo un borrador; avance70/70, ticket y proyección aún requieren integración. No se realizó ningún despliegue en este repaso.

Relacionado: [[Citas Gerencia - analisis del Excel de proyeccion por analista 2026-09-10]], [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]], [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]], [[Citas Gerencia - deposito acreditado por conversion a cliente 2026-09-08]], [[Fundamentos UX del CRM]].

## Presentación local posterior

Tras ver la propuesta, Miguel indicó que le gusta y pidió que el indicador se llame **«Entrevistas»**, en lugar de «Asistencia». Se actualizó la terminología de la vista local, detalle, ayuda y exportación, conservando los cálculos. Esta aceptación visual no equivale a activar las reglas productivas ni a confirmar las fórmulas propuestas.

Miguel pidió «muéstrame cómo se vería en local». Se creó y abrió en Chrome <http://127.0.0.1:4180/prototypes/citas-avance.html>, una entrada independiente con componentes del CRM y datos ficticios. El navegador integrado no estaba disponible. Se conservó la propuesta anterior `citas-metas.html`.

La nueva vista incluye filtros, recuperación horizontal con listas paginadas y ficha personal, tabla de cuatro analistas, detalle de brechas y leads sin citas, Bandeja/Agenda y exportación. La ayuda permite comparar las dos bases de conversión sin guardar configuración. Semana filtra el seguimiento y muestra su actividad aparte; avance, ticket y proyección permanecen mensuales y se rotulan así.

Verificación: lint/typecheck PASS,3.474 pruebas PASS, build de app y del prototipo PASS en salidas temporales independientes, sin sobrescribir `app/dist`. Verificación visual e interacciones en `UX-UI-GERENCIA/citas-avance-local-2026-09-13/`; conserva capturas y script reproducible. SQL/RLS, datos reales, activación y publicación de este alcance: NOT RUN. **Presentar la vista no activa las últimas reglas en el módulo productivo ni confirma las fórmulas propuestas.**

## Semántica visual posterior

Miguel pidió que los colores respondieran al resultado. Se ajustó la misma propuesta local según [[Fundamentos UX del CRM]], con los helpers de semáforo compartidos: azul para metas alcanzadas, ámbar para resultados por mejorar, rojo para brechas importantes y gris para ausencia de base. La escala de tasas conserva el criterio existente del CRM: rojo por debajo de la mitad del objetivo, ámbar hasta alcanzarlo. Iconos, leyenda, descripción accesible y detalle al pulsar acompañan al color.

Se propone una referencia visual del ritmo de citas según el día del mes: al 13/09, 43,3% de la meta mensual. No modifica el cumplimiento ni la meta interna; evita señalar como retraso un 50% en ese momento del mes. El ticket y la proyección permanecen neutros al no tener una meta monetaria confirmada. La tasa de recuperación no se compara con el 70% de conversión, porque usa otra base. El recorrido destaca en navy a los clientes y en ámbar a quienes siguen sin nueva cita.

Este ajuste permanece local, con datos ficticios. Lint específico, typecheck, cuatro pruebas del modelo, build del prototipo, navegación en cuatro anchos y contraste de los indicadores de al menos 4,5:1: PASS. La evidencia visual y el README se actualizaron; no se repitieron los gates productivos para esta presentación. No hubo commit ni publicación.

Miguel respondió «ahora sí me gusta» tras revisar los colores. La presentación actual queda como referencia visual aceptada: formato compacto y horizontal, terminología «Entrevistas», filtros y colores según el resultado. Esta aceptación visual no resuelve las fórmulas pendientes ni representa una instrucción nueva de publicación.
