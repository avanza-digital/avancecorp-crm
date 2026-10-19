VERDICT: **CHANGES_REQUESTED**

SUMMARY: Hay dos discrepancias concretas: la atribución de ventas no coincide con Resultados y la sincronización de URL depende de haber entrado por un enlace de Proyección. La prueba de invariantes sí utiliza `calcularAvanceCitas` real, pero sus escenarios no detectan estas diferencias.

FINDINGS:

- **P1 — Una venta puede convertir la fila del analista equivocado.** En [proyeccion.ts:212](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/components/citas/proyeccion.ts:212), `convertidas` comprueba persona y compatibilidad temporal, sin comprobar quién tiene atribuida la venta. Resultados, en `resultados(id)`, restringe `clientesMes` al propietario de la fila y exige correspondencia entre propietarios.

  Contraejemplo con creación, cita, entrevista y venta dentro del mismo mes: Ana y Luis entrevistan a la misma persona; la venta pertenece a Luis. Proyección muestra **100 % para ambos**; Resultados muestra **0 % para Ana y 100 % para Luis**. La diferencia también afecta a «Proyectado citas». Si Luis pertenece a otro supervisor y se selecciona únicamente el equipo de Ana, Proyección sigue utilizando su venta, mientras Resultados la excluye del ámbito. Compartir `entrevistaCompatibleConVenta` no comparte toda la regla de vinculación.

- **P2 — Cambiar la Proyección puede conservar un enlace de Agenda.** En [propuesta.tsx:197](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx:197), `sincronizarProyeccion` retorna si la URL todavía no tiene esa variante. `cambiarVista` tampoco la genera al entrar.

  Reproducción: abrir `#/reuniones/mes/2026-10`, seleccionar Proyección y cambiar rango o columnas. La URL continúa describiendo Agenda; compartirla o recargar vuelve a Agenda. Cambiar Supervisor pasa por la sincronización del enlace mensual existente. Desde `#/reuniones` tampoco se genera el enlace. Esto incumple la sincronización descrita para los cambios dentro de la pestaña; la prueba nueva únicamente cubre una URL que **ya empieza** en Proyección.

TEST GAPS:

- **La comparación con Resultados es auténtica, pero restringida.** En `proyeccion-invariantes.test.ts`, `venta(c, …)` atribuye cada venta al analista de su cita. Faltan ventas de otro analista, colaboración entre equipos y el mismo escenario con Supervisor seleccionado.
- **La completitud de la cohorte sigue sin demostrarse.** [propuesta.tsx:112](/Users/usuario/dev/avancecorp-crm-proyeccion-f2/CRM-Avance-Corp/app/src/components/citas/propuesta.tsx:112) solicita los meses del rango. Según el contrato descrito del lector, una cita creada el 19/10 y prevista el 02/11, cuyo lead no tenga citas previstas en octubre, puede quedar fuera de la consulta de octubre. Las pruebas entregan directamente las citas a la función o al fusionador; no comprueban que el lector las entregue. Es una brecha potencial heredada, pendiente de contrastar con el lector real.
- Por inspección, no encontré huecos ni solapamientos en los tramos válidos. Los dos botones «Mes» pertenecen a grupos accesibles con nombres distintos; su duplicidad no constituye por sí sola un defecto.
- **Verificación propia: NOT RUN.** No hubo acceso al árbol ni a los protocolos locales mediante las herramientas disponibles. El `check` comunicado por el PRIMARY precede a los últimos ajustes.

NEXT ACTIONS:

1. Alinear atribución y ámbito de las conversiones con Resultados, conservando el seguimiento temporal de la cohorte.
2. Generar/sincronizar la variante de Proyección también al llegar desde una URL genérica o de Agenda.
3. Añadir los contraejemplos anteriores, verificar la cobertura del lector y ejecutar los checks sobre el estado final.

CONFIDENCE: **Alta en los dos hallazgos por inspección del diff; limitada respecto a la cobertura del lector no adjunto.**
