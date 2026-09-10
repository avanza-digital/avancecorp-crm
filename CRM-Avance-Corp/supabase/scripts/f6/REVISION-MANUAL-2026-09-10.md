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
asesores. Después, ante «ok sigamos con eso como lo haras?», Codex explicó y
ejecutó la prueba No contactar del punto 4. Ante «ok hazlo», Codex avanzó el punto 5
con confirmaciones de reinversión desde el CRM y verificaciones de integridad.
Falta completar su carga visual de comprobante y envío inicial del formulario:
Chrome bloqueó el permiso de archivo. Los puntos 6–8 permanecen pendientes:
retiro, accesibilidad y recuperación de un envío cuya respuesta se perdió.

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

## Punto 4 — No contactar, ejecutado por Codex

**PASS funcional** en la misma persona sintética, con PRUEBA F4 AJENO como
responsable. Gerencia marcó y levantó el veto desde el formulario del CRM.

- Al marcarlo con motivo, la ficha mostró No contactar y deshabilitó Agendar
  gestión. Los dos pendientes anteriores quedaron cancelados y la agenda vacía.
- Un intento directo de agendar con el JWT del asesor actual fue rechazado con
  P0429 («Esta persona pidió no ser contactada»; HTTP 500 del contrato vigente).
  No creó tareas. El mismo asesor no pudo levantar el veto: HTTP 403/42501.
- Gerencia levantó el bloqueo con un motivo. Agendar volvió a habilitarse y las
  dos tareas canceladas permanecieron canceladas, sin reaparecer.
- Se programó después una única llamada nueva por la RPC del asesor actual,
  titulada «Seguimiento posterior a No contactar F6». Se verificó que su ID era
  nuevo y que los dos anteriores seguían cancelados. La ficha tras recargar
  conserva este contacto como único pendiente.
- Las inversiones, tareas ya cerradas antes del caso y banderas conservaron sus
  datos. El motivo de prueba y su levantamiento quedan en la historia.

Estado final local: No contactar desactivado, PRUEBA F4 AJENO como responsable,
dos tareas originales canceladas y un contacto nuevo pendiente. No se restauran
las tareas canceladas porque precisamente se verificó que levantar el veto no
las revive. [Evidencia del recorrido](manual-2026-09-10/veto-evidencia.json).

No hubo cambios de código ni de producción. Es una verificación de Codex; no se
atribuye a Miguel una aprobación visual de los casos que no ejecutó.

## Punto 5 — vencimientos y reinversión, ejecución parcial de Codex

**PASS funcional con recorrido UI parcial**. La falta del permiso de archivo
en la extensión de Chrome impidió completar el envío inicial desde el formulario.
No se presenta este tramo como aceptación visual completa ni aprobación humana.

- Se crearon dos antecedentes cooperativos nuevos mediante la conversión canónica,
  con persona, documento, lead y depósito sintéticos únicos. Ambos son de S/ 1.000
  y vencen el 17/09/2026. Aparecieron en Vencimientos y abrieron la persona,
  empresa y referencia de origen correctas en Reinvertir desde esta inversión.
- El selector de comprobante fue bloqueado por Chrome: `fileChooser.setFiles`
  devolvió `Not allowed`. Se indicó cómo habilitar el acceso a URLs de archivo;
  no se cambió ese permiso automáticamente. Para continuar se prepararon las dos
  solicitudes con `preparar_reinversion_fn` y se cargaron los PNG ficticios por
  la API local de Storage. La descarga autenticada devolvió exactamente esos bytes.
- Se retomó cada solicitud por su referencia desde el CRM. Se revisaron persona,
  empresa, capital, fechas y depósito, y se pulsó Confirmar inversión por UI.
  Qorilazo añadió S/ 1.500 y Prodelco S/ 2.000. Ambas fichas mostraron dos
  inversiones: original de S/ 1.000 y nueva inversión, con comprobante disponible.
- Repetir la confirmación mediante la RPC devolvió el mismo ID. Cada solicitud
  tiene una inversión nueva, un vínculo de origen y una gestión de reinversión.
  Los registros completos de los dos orígenes y las 87 inversiones del snapshot
  anterior se conservaron. La reinversión no creó otra persona, lead ni Auth;
  se compararon los IDs de personas/leads y los IDs/correos de Auth, no todos
  los campos de sesión. Las banderas tampoco cambiaron.
- Avance: Aumentar inversión abrió con F4-BASE-UPGRADE-ELEGIBLE. Como no había
  contratos vencidos en el banco, se añadió un antecedente nuevo de S/ 1.000 al
  cliente ficticio existente, mediante la RPC contractual canónica y cuenta
  existente. Se ensayó primero con rollback y restricciones diferidas forzadas.
  Su vencimiento 01/09/2026 habilitó Renovar contrato, mostrando origen, PEN y
  capital anterior correctos. Ambos diálogos se cancelaron sin revisar ni crear
  solicitudes. Los 48 contratos anteriores permanecieron idénticos; el nuevo
  antecedente también se conservó tras abrir y cerrar el formulario.

[Evidencia de reinversión y acciones Avance](manual-2026-09-10/reinversion-evidencia.json).
Queda **NOT RUN** el recorrido completo de carga de archivo y envío inicial de
Revisar inversión por UI. No hubo cambio de producto ni de producción. Los casos
ficticios quedan disponibles en el banco para retomar la prueba.

En el reintento del 10/09, Miguel indicó que ya había habilitado el permiso.
La carga automática volvió a responder `Not allowed`; no se pudo completar
por el selector nativo y la política del navegador rechazó abrir la configuración
de extensiones. Por tanto, el permiso efectivo no quedó verificado. Se dejó
un formulario Qorilazo completo, con capital ficticio nuevo de S/ 750 y depósito
único, pendiente de que Miguel seleccione el PNG preparado. No se pulsó Revisar
inversión ni Confirmar en este intento. Un snapshot nuevo confirmó inversiones,
cierres, solicitudes y banderas sin cambios. El punto 5 continúa pendiente de
este tramo; no se sustituye la evidencia parcial anterior por un PASS visual.

El primer snapshot del arnés usó por error `crm.contratos`; la tabla correcta es
`public.contratos`. Se corrigió el arnés y se capturó el snapshot antes de operar
las reinversiones, sin repetir los antecedentes ya creados. No fue un fallo del CRM.

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
