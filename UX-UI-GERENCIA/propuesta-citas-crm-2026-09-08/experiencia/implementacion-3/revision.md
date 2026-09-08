# Evaluación de revisión independiente

Fecha: 2026-09-08. Codex PRIMARY; Claude SECONDARY_REVIEWER mediante `scripts/claude-review`, sin herramientas ni edición. Nivel 2 por la incorporación del inspector no modal al componente compartido Sheet.

La primera ejecución no completó el servicio; se repitió la misma consulta con acceso autorizado. La revisión completada devolvió **CHANGES_REQUESTED**. No se presenta ese dictamen como PASS ni se pidió otra revisión para obtener conformidad. Codex evaluó sus hallazgos y verificó las correcciones.

| Hallazgo | Evaluación y resolución |
| --- | --- |
| P1: el retorno de foco reconocía cualquier Sheet y podía interferir con la cita vinculada | Aceptado. `sheet.tsx` usa la referencia al contenido propio y restaura de forma síncrona en modo no modal; si ya hay foco en un filtro u otro panel, lo conserva. El modo modal predeterminado sigue su camino previo. `tablero.test.tsx` prueba la transición en ambos modos; el navegador verifica recorrido → cita → agenda. |
| P2: asistencia del inspector menos estricta que la del flujo | Aceptado. La condición existente se extrajo como `asistioTrasInasistencia`, reutilizada por ambos. Una prueba con asistencia anterior a la reprogramación comprueba que ni flujo ni ficha la reconocen. No se modificaron fixtures ni reglas de confirmación de depósitos. |
| P2: cambio de persona no anunciado | Aceptado. Triggers con `aria-expanded`/`aria-controls` y región de estado con el nombre seleccionado. Prueba de cambio Andrea → Mónica. |
| Falta de pruebas de 4/3/1/1, 25%, monto y Sin nueva cita | Descartado como carencia real: ya se cubrían en `depositos.test.ts` e `inasistencias.test.tsx`, que no estaban completos en el paquete del reviewer. Se volvieron a ejecutar. |
| Prueba no modal basada en `aria-modal` | Aceptado. La versión instalada de Radix no añade ese atributo. Se comprueba presencia/ausencia del overlay y comportamiento del foco en vez de un atributo ausente en ambos modos. |
| Meta de la consulta frente a historial fuera de período | Se mantienen ambas bases por requerimiento. La meta dice «consulta actual» y el recorrido ahora indica que incluye seguimiento fuera del período. |
| Fechas opcionales de reprogramación/confirmación | La cadena exige `reprogramadaEn` válida en `seguimientoInasistencias`; los movimientos exigen confirmación válida en `depositosDeInasistencias`. No se relaja el contrato. La ficha también indica que las horas son de Lima. |
| Varios depósitos con una sola fecha | Corregido: cuando existen varios se indica cantidad y «desde» la primera fecha. |
| Vacío del filtro Sin nueva cita | Corregido: «Todas las personas reprogramaron». |

Refinamientos P3 aceptados: al cruzar 1536 px con una ficha abierta, Radix cambia de modalidad y puede reiniciar su desplazamiento; se conserva la persona y el modo adecuado al espacio disponible. Nombre y chevron siguen siendo dos accesos al mismo recorrido. La lista de depositantes usa el conjunto validado de recuperados, cuya pertenencia a la conversión está cubierta por los tests de conjuntos anidados.

Validación posterior: 32 tests del prototipo, 3106 tests del gate integral, comprobaciones estáticas/build y recorrido en navegador. Sin hallazgos P1/P2 pendientes dentro del alcance local.
