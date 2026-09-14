# Propuesta visual: avance y cierre por analista

Visual de conversación, sin cambios al runtime del CRM ni al panel Superadmin. Fuente editable: `cierre-por-analista.html`. Toma la apariencia del panel de analistas actual y agrega entrevistas, depósitos, ticket y cierre en una misma fila; el detalle se abre a demanda.

## Definiciones nuevas confirmadas

- Cita: la que el analista genera en el CRM.
- Entrevista: asistencia registrada a esa cita.
- Depósito: conversión posterior a cliente de quien asistió.
- Se desea proyectar el cierre mensual con los porcentajes actuales y el ticket propio del analista.

## Ejemplo provisional, no política aprobada

La vista usa corte de 10 de septiembre de 2026, último día completo anterior a la conversación del 11/09, y 30 días calendario. Todas las cifras y nombres son ficticios. Cada entrevista corresponde a una persona distinta en este ejemplo; todas las citas incluidas ya tienen resultado. No resuelve cómo contar entrevistas repetidas ni el desfase temporal entre cita y conversión.

1. Citas previstas al mes = citas generadas hasta el corte / 10 × 30.
2. Tasa de asistencia = entrevistas / citas evaluadas.
3. Tasa de conversión = clientes convertidos después de entrevistar / entrevistados.
4. Clientes esperados = citas previstas × tasa de asistencia × tasa de conversión.
5. Captación estimada = clientes esperados × ticket histórico de referencia.

La cifra es el **total esperado del mes**, incluye los clientes ya obtenidos; no se debe volver a sumarlos. Supone suficiente población elegible y continuidad del ritmo durante el resto del mes. No es una predicción calibrada ni una garantía de captación. Los porcentajes se calculan de la actividad observada; no se multiplican de nuevo por la meta de 1,25. El escenario «Con 70% / 70%» usa ese mismo volumen previsto con ambas tasas objetivo; no se presenta como el pronóstico actual.

Ana: 100 citas → 70 entrevistas → 35 clientes, ticket S/20.000. Proyección: 300 citas → 210 entrevistas → 105 clientes → S/2.100.000. Con ambas tasas al 70%: 147 clientes → S/2.940.000. Bruno: S/1.260.000 actual, S/1.764.000 a objetivos. Carla: S/1.575.000 actual, S/2.205.000 a objetivos.

La simulación permite variar las tasas y el ticket; modifica sólo el escenario. Los esperados fraccionarios conservan precisión para el importe, aunque la cantidad se presenta aproximada. No se interpreta 58,8 como 59 depósitos realizados.

## Decisiones consultadas y todavía pendientes

- Ticket medio: histórico de meses anteriores, promedio actual o valor configurable. Para mostrar el ejemplo se usa histórico, sin período aprobado.
- Volumen mensual: extrapolar ritmo real hasta hoy o usar la meta según leads asignados. El ejemplo usa ritmo real, sin establecer esa opción como decisión del usuario.
- Antes de integrar: determinar corte y denominadores válidos, personas repetidas, citas futuras/pendientes, capacidad de leads únicos, atribución temporal y al analista, población manual, moneda, fuente de capital realmente depositado y tratamiento de falta de datos. Un ticket ausente debe ser dato insuficiente, no cero; PEN y USD no se suman sin conversión explícita.

No modifica el SQL candidato, no instala ni publica nada y no necesita consultar datos productivos. El módulo de recuperación de inasistencias conserva su lugar y sus reglas. La guía del diseño ya leído está en el vault, `Fundamentos UX del CRM.md`, y la referencia visual es `propuesta-citas-crm-2026-09-08/integracion/conversion-cliente/citas-desktop.png`.

## Segundo borrador: integración en Resultados

`integracion-resultados.html` muestra la propuesta dentro del marco de Citas, con recuperación arriba y una tabla de avance por analista debajo. Añade el cumplimiento de citas sin exponer la constante interna, y detalle de brechas a demanda. Los filtros son locales; las semanas como cortes acumulados son una propuesta, no una regla confirmada.

Miguel pidió parar y seguir más tarde inmediatamente después de escribir este archivo. **Validación de sintaxis, aritmética e interacción: NOT RUN. Presentación y aprobación visual: pendientes.** No usar la verificación de la primera visualización como evidencia de este segundo borrador. No continuar hasta que Miguel retome; no se integró en el runtime del CRM, no se instaló SQL ni se publicó.

### Retoma autorizada con «sigue»

Se retomó y revisó el segundo borrador para presentarlo en la conversación. Se corrigió el encabezado del evento «Reprogramó» (su fecha no es la fecha prevista de la nueva cita) y la dependencia del selector de analistas respecto al supervisor. Cambiar de supervisor conserva el analista sólo cuando pertenece al nuevo equipo.

**PASS:** sintaxis JavaScript y ejecución aislada en JSDOM, sin cargar recursos externos; aritmética de las tres filas, objetivos enteros y brechas, filtros de analista/supervisor, cortes acumulados al 7/10 de septiembre, recorrido y lista por etapa, conservación de las métricas al seleccionar una etapa, foco al abrir el detalle y estados sin datos. **NOT RUN:** inspección visual en navegador, datos reales y suite del CRM; esta entrega sólo cambia la propuesta de conversación y la documentación, no el runtime del producto.

En esta segunda vista: Ana lleva 80% del objetivo de citas, 70% de asistencia y 50% de conversión; le faltan 25 citas y 14 clientes sobre las bases del corte. Bruno lleva 64%, 50% y 70%. Carla lleva 100%, 70% y aproximadamente 71,4% y alcanza los tres objetivos; su proyección ilustrativa es S/2.250.000. El escenario de ambos porcentajes exactamente al 70% puede ser menor que su desempeño actual.

La aprobación visual, la selección del ticket, la base de proyección y el uso de semanas como cortes acumulados siguen pendientes. No se aplicó ni publicó la lógica en el CRM. La presentación de esta propuesta no aprueba automáticamente estas decisiones.

### Vista local solicitada

Miguel pidió verla en local. Se exportó con el renderizador de visualizaciones a `CRM-Avance-Corp/app/prototypes/citas-metas.html` y se abrió en Chrome usando el servidor existente:

<http://127.0.0.1:4180/prototypes/citas-metas.html>

Se comprobó el renderizado inicial en navegador: filtros, recuperación y las tres filas de analistas visibles. Se dejó la pestaña abierta. Esta comprobación visual inicial no equivale a repetir todos los flujos JSDOM en navegador ni a validar datos reales. El archivo es una exportación autónoma del ejemplo, no la pantalla productiva.
