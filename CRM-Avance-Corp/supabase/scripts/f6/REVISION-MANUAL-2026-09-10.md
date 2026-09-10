# F6 — avance de revisión manual del 10/09/2026

Estado: **EN CURSO; aceptación completa pendiente**.
Revisor humano: Miguel. Recorrido guiado con rol vendedor y banco local sintético.
Referencia de código F6: `b54fe94219fa516ab3824ec1be9ae756fc3144e1`.

## Confirmaciones recibidas

| Comprobación | Resultado | Evidencia humana |
|---|---|---|
| Crear una llamada y verla en la ficha | PASS | «si aparecio!!» |
| Visualizarla en Hoy | PASS | «OKOK YA REVISE SII SALE EN LA PANTALLA DE HOY» |
| Localizarla en Agenda, una sola vez | PASS | «funciona. aprobado», respondiendo a los tres pasos de Agenda |
| Abrirla desde Agenda y conservar la misma ficha al recargar | PASS | Misma aprobación explícita de los tres pasos |
| Completar la llamada con detalle y conservarla en el historial | PASS | «funciona», tras la instrucción de cerrar la llamada y revisar el historial |
| Programar el siguiente contacto, una sola vez y con la fecha elegida | PASS | Misma confirmación del cierre con siguiente contacto |
| Cambiar la hora de la reunión y verla actualizada en Agenda | PASS | «le puse un nueva hora sii, y ahora me figura en mi agente con ese horario cambiado» |
| Confirmar la cita | PASS | «y confirme la cita», tras preguntar expresamente por la confirmación de asistencia |

El visto bueno cubre los comportamientos anteriores. No se atribuye a una tarea
o identidad concreta: Miguel no confirmó su título ni su identificador. El banco
se preparó con una persona Qorilazo sin perfil Avance; esa condición del caso
exacto utilizado no se da por ratificada solo con la aprobación de navegación.

## Siguiente paso y pendientes

El punto 2 de [la guía](REVISION-MANUAL.md) tiene aceptación humana: cierre con
detalle e historial, siguiente contacto con fecha y sin duplicación, cambio de
hora visible en Agenda y confirmación de la reunión. Miguel confirmó por separado
el cambio guardado y la confirmación; no se dedujo de la mera apertura del formulario.

Continuar el punto 3: reasignación como Gerencia y acceso de ambos asesores.
Los puntos 3–8 siguen
pendientes de aceptación humana: responsable, veto, reinversión, retiro,
accesibilidad y recuperación de un envío cuya respuesta se perdió.

## Preparación del banco y alcance

Durante la revisión se detectó que faltaba la fila de configuración de
`crm.sla_operacion_control` en el banco local. Se restituyó su semilla en modo
`legado`, con la guarda restaurada en la misma transacción. El RPC de seguimiento
respondió HTTP 200 después del ajuste; la huella de tareas permaneció idéntica y
los tres triggers de esa tabla quedaron habilitados. Fue una corrección de la
preparación local; no hubo cambios de código de producto ni de producción.

Las comprobaciones de este registro no cierran F6 ni firman G6/G7/G8. Se conserva
el estado publicado F4/F5/F6 apagadas en producción. Las comisiones son externas.

Validación de este cambio documental: `git diff --check` y enlaces locales.
Tests y build del producto: **NOT RUN**, por ser un registro sin cambios de runtime.
