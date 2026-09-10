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

El 10/09 Miguel delegó expresamente el punto 3: «esta prueba puedes hcaerla tu
por favor». Codex ejecutó la reasignación por UI y verificó el acceso con ambos
asesores. Sigue el punto 4. Los puntos 4–8 permanecen pendientes: veto, reinversión, retiro,
accesibilidad y recuperación de un envío cuya respuesta se perdió.

## Punto 3 — ejecución delegada a Codex

**PASS funcional**, ejecutado en el banco sintético con sesiones autenticadas.
La demo general sigue habilitada como opción local, pero este caso se realizó
con las cuentas de prueba porque la demo no contiene el recorrido F6.

- Persona usada por Codex: `6e81c382-127d-4594-84ec-f05e3c886991`, Qorilazo.
  Gerencia cambió el responsable de PRUEBA F4 VENDEDOR a PRUEBA F4 AJENO desde
  el formulario visible. La ficha mostró el nuevo responsable.
- El nuevo asesor vio la persona y las dos tareas pendientes. Se conservaron
  los mismos IDs, títulos, tipos, estados y horarios, sin duplicación.
- El asesor anterior perdió ficha y agenda incluso reutilizando el JWT obtenido
  antes de reasignar. F5 devuelve HTTP 200 con `null`; F6 devuelve HTTP 403/42501;
  la lectura directa de tareas bajo RLS devuelve cero filas. Por UI, el enlace
  directo vuelve a Cartera con «El acceso cambió. La cartera se volverá a consultar.»
- La información de inversiones devuelta por la ficha no cambió. El analista
  histórico de la operación sigue siendo PRUEBA F4 VENDEDOR.
- Caso sin responsable: fixture independiente en transacción, con rollback.
  Se bloqueó agendar sin responsable (P0409), Gerencia conservó el pendiente en
  su cola y los vendedores no lo vieron; al asignarlo llegó la misma tarea al
  nuevo asesor. Al terminar se verificaron tareas previas y banderas intactas,
  y ausencia de la persona temporal.

Evidencia: [reasignación](manual-2026-09-10/reasignacion-evidencia.json) y
[cola sin responsable](manual-2026-09-10/cola-evidencia.json).
La reasignación queda aplicada en el banco a PRUEBA F4 AJENO. No hubo cambios de
producto ni de producción. El tramo de cola fue una prueba funcional de servidor,
no un recorrido visual de una cola con datos persistentes ni una aprobación humana.

El arnés inicial esperaba por error HTTP 403 para la ficha F5 oculta y PT409 para
la ausencia de responsable. Se ajustó al contrato comprobado en código/catálogo
(HTTP 200/null y P0409) antes de completar las comprobaciones. No se modificó el
producto para acomodarlo al arnés; las ejecuciones finales pasaron.

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
