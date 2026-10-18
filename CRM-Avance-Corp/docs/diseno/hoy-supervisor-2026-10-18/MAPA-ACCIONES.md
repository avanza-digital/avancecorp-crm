# Acciones de Hoy — revisión de fase 3

| Control | Destino y contexto comprobado |
| --- | --- |
| Repartir leads / Ver derivaciones | Bandeja `#/derivaciones`; el resumen se invalida al repartir y se revalida al regresar. |
| Cifra de llamadas | `PanelAnalistaSupervisor` del equipo, registro de llamadas del día. |
| Ver quién necesita apoyo | Tabla diaria con filtro de atención y búsqueda reiniciada; foco en su título. |
| Citas de hoy | `#/reuniones/dia/<hoy Lima>`, tanto cifra como acceso de tarjeta. |
| Resultados de hoy | Diálogo con el mismo agregado por analista y moneda de la tarjeta. Facturación es un acceso general, no promete filtro diario. |
| Cifras mensuales | Tabla del mes; el acceso a Facturación se mantiene en esa pestaña. |
| Nombre del analista | Detalle diario existente, conservando filtros al cerrar. |
| Ver pendientes | Nuevo diálogo del equipo con pendientes y atrasadas por persona y total de la misma foto diaria. No abre la cola SLA como si fuera la lista de tareas. |
| Ver tareas de una persona | `PendientesSupervisor`, lector paginado existente y autorizado para ese analista. |
| Número de atrasadas en la tabla | Abre directamente las tareas vencidas del analista. |
| Actualizar | Recarga Gestión Diaria, mes, reparto, Citas y Facturación diaria. |
| Reintentar | Consulta solamente la fuente afectada. |

La lista del equipo no dispara consultas por cada persona: usa la foto ya leída.
La consulta detallada de tareas se activa al elegir un analista. Si el equipo
deja de estar disponible o la persona sale del ámbito, se retira el detalle y
se conserva el error/retorno de foco. Al cambiar actor o día se desmontan los diálogos.

## Revisión y corrección por Codex

- B3 corregida: acceso exacto a tareas, sin cambiar el lector ni sus permisos.
- Corregido el foco al pasar de lista de personas al detalle y de vuelta.
- `DialogTitle` acepta las propiedades nativas de `h2`, incluido su ref, para
  enfocar el título accesible sin modificar el comportamiento de Radix.
- **PASS:** 29 pruebas en 3 archivos (portada, tareas existentes, diálogos), lint,
  typecheck y diff sin errores de espacio. Incluyen refresco de las cinco fuentes,
  medianoche de Lima, teclado/foco, error, vacío y preservación de búsqueda.
- E2E existente actualizado para el nuevo acceso; **NOT RUN** por la restricción
  explícita de navegador/Docker. No se afirma un recorrido visual ejecutado.
- Logs `fase3-tests.log` y `fase3-tipos.log` en `/private/tmp/hoy-supervisor-goal-20261018/`.
- Cierre: acciones revisadas, sin defectos propios pendientes de esta fase.
