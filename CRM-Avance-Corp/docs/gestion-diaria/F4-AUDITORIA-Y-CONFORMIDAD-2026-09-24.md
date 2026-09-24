# F4: auditoría técnica y cierre de participación manual

24/09/2026, hora de Lima. Fuente del frontend auditado: `929fbbcc`.

Miguel pidió sustituir la comprobación manual de persistencia por una auditoría
y después indicó: «marca todo lo que depende de mi como terminando haz la
audiotria y sigamos con lo demas que es F4.1-F6». Queda cerrada su participación
manual pendiente y registrada su conformidad. Reportará incidencias durante el
uso. Esta decisión no se presenta como ejecución de pruebas humanas omitidas ni
como resultado de controles cuyo horario todavía no ha ocurrido.

## Evidencia y resultados

| Control | Resultado y alcance |
| --- | --- |
| Cifras del primer corte | PASS: cotejo productivo del recorrido previo, 10 analistas, 43 llamadas a las 12:30, 4 cumplieron, 1 recuperó y 5 pendientes. Es una fotografía de esa hora. |
| Aplazamiento productivo | PASS: una acción a las 12:34:21, vencimiento 13:34:21, exactamente 3.600 segundos; recarga y nueva pestaña comprobadas. |
| Reaviso productivo | PASS de registro: lectura a las 14:36 confirma entrega inicial a las 11:50:16 y un solo reaviso a las 13:39:00, posterior al vencimiento. El asiento acredita la reserva/entrega del servidor, no una nueva observación visual del popup. |
| Reconocimiento productivo de este aviso | No ejecutado; la decisión operativa de Miguel fue posponer. La auditoría no reconoce el aviso en su nombre. |
| Persistencia entre sesiones | PASS en banco local: cuatro sesiones Auth nuevas, dos por cada supervisor sintético, leen idéntico historial y vista vigente. Cada actor conserva un reconocimiento y un aplazamiento de corte de una hora. Lectura de historia del banco del 22/09; no se repitieron las acciones. |
| Concurrencia | Evidencia previa PASS del 22/09: dos solicitudes esperando simultáneamente el mismo bloqueo; una entrega, un aplazamiento, reintento idempotente y reconocimiento compartido. No se repite su preparación de una sola ejecución. |
| Código servidor | PASS del control `private.assert_gestion_diaria()` en producción y banco. Los cuerpos de presentar, reconocer, avisos, cortes y llamadas cotejados tienen las mismas huellas. El banco no equivale a toda la instalación productiva: conserva diferencias posteriores del panel de pendientes. |
| Pruebas dirigidas actuales | PASS: 57 pruebas en cuatro archivos de avisos, cortes y consultas; 6 E2E en Docker. Los E2E interceptan la API y prueban la interfaz, no acreditan una conexión productiva. |

No se encontró una incidencia nueva dentro de este alcance. La casilla de cifras,
avisos y acciones entre sesiones se cierra mediante esta evidencia combinada y
la aceptación de esa modalidad por Miguel. Dos sesiones o dispositivos reales de
producción siguen sin haberse recorrido: no se les atribuye PASS.

## Pendientes técnicos y seguimiento

- Corte real del 24/09 a las 16:00 y ausencia de reaviso después de las 18:00.
- Corte único del sábado 26/09 a las 11:30 y cierre a las 13:00.
- Registrar cualquier incidencia y su corrección. No se instala un monitor
  automático ni se declara cumplido un control por ausencia de reportes.
- F4.1 conserva pendiente medir la calidad de la IA. La conformidad de Miguel
  cierra la tarea manual asignada, pero no crea etiquetas humanas ni demuestra
  precisión sobre notas reales. La fase no bloquea F5.

El plan siguiente está en [EJECUCION-F4-1-F6-2026-09-24.md](EJECUCION-F4-1-F6-2026-09-24.md).
Evidencia durable: `/Users/usuario/.local/share/avancecorp-checkpoints/gestion-diaria-auditoria-2026-09-24/`.
El [acta del recorrido](F4-RECORRIDO-SUPERVISION-2026-09-24.md) conserva las
observaciones originales. Este documento no requiere otra publicación del CRM.


## Evidencia conservada

- [Resumen anonimizado](auditoria-2026-09-24/evidencia.json).
- [Lecturas en cuatro sesiones Auth del banco](auditoria-2026-09-24/sesiones-locales.json).
- [57 pruebas dirigidas](auditoria-2026-09-24/unit.log) y [6 E2E Docker](auditoria-2026-09-24/e2e.log).
- [Tablero de F4](auditoria-2026-09-24/figma-0.png), [F4.1](auditoria-2026-09-24/figma-1.png) y [conformidad manual](auditoria-2026-09-24/figma-2.png).
