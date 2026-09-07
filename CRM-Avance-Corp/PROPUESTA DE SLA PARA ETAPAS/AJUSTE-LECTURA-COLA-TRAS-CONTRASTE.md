# Lectura de cola completa dentro del núcleo SLA

Estado: requisito incorporado tras el contraste; **pendiente de implementación antes de activar**. No modifica los plazos ni crea otro núcleo. Amplía SLA-3/SLA-4 del plan.

Problema comprobado: 342 primeras atenciones, cola N1 limitada a 200 y sin paginación. De 455 revisiones, solo 18 tienen revisión como acción dominante. `hay_mas` por sí solo no permite consultar lo restante.

La responsabilidad queda distribuida así:

| Pieza | Contrato a completar |
|---|---|
| `private.sla_operacion_leads` | Conserva el único cálculo de estado, acciones y señales por lead. No copia reglas al filtro ni al navegador. |
| Ventana `private.sla_operacion_autorizada` | Resuelve actor, capacidades, ámbito y reloj del servidor. Los parámetros de consulta nunca conceden más ámbito. |
| Adaptador de cola v2 | Añade filtro de señal y cursor a la lectura del resultado autorizado. Mantiene una sola definición no ambigua; actualizar firma, grants, gate, contrato, tests y reversa juntos antes de publicar. |
| Pantallas | Abren la lista correspondiente a la señal seleccionada, permiten recorrerla completa y muestran las demás señales de cada lead. Los contadores no se derivan de una página. |

Entrada prevista: `p_limite` (1–200), `p_senal` opcional (`primera_atencion`, `tareas_vencidas`, `seguimientos_pendientes`, `revisiones`, `datos_incompletos`, más reparto autorizado) y `p_cursor` opcional. Validar nombres y estructura; no aceptar parámetros de rol, propietario efectivo o reloj arbitrario del cliente. `revisiones` requiere capacidad de supervisión/lectura gerencial según las reglas vigentes.

Secuencia obligatoria: resolver ámbito → evaluar el núcleo una vez con reloj único → calcular totales de señales sobre todo el ámbito → aplicar filtro por **señal**, independientemente de la acción dominante → ordenar de forma total → aplicar cursor → limitar. Para revisión, el criterio de pertenencia es `senales.revisiones=true`, no `accion.bucket='revision_comercial'`.

Usar cursor por clave ordenada —prioridad, referencia temporal con tratamiento explícito de nulos, UUID— vinculado al filtro y contexto de consulta. Revalidar permisos en cada página. Respuesta: `totales` del ámbito, `total_filtrado`, `items`, `siguiente_cursor`, `hay_mas`, reloj y revisión de configuración. Mostrar recarga cuando cambie el contexto de consulta. La paginación de datos vivos no se presenta como una foto histórica inmutable; no inventar garantías de consistencia entre transacciones sin implementarlas.

Criterios de aceptación sobre este corte congelado:

- Recorrer todos los 342 pendientes de primera atención sin omisiones ni duplicados, aunque superen 200.
- El filtro de revisiones devuelve los 455 leads, incluidos los que tienen primera atención, seguimiento o tarea como acción dominante. Los tres sin asignación también quedan accesibles para reparto.
- Los totales y el universo filtrado permanecen independientes del tamaño de página.
- Conciliar el conjunto completo con las señales del estado v2, por rol/ámbito; probar cursor inválido, cambiado de filtro, fuera de ámbito y contexto obsoleto.
- No añadir lecturas de tablas crudas ni fórmulas SLA a los adaptadores o pantallas. Gates y rollback deben reconocer la firma final.

Este ajuste se integra en la entrega funcional completa. El contraste valida el cálculo N1 y expone esta limitación de consulta; no certifica como terminado este contrato pendiente.
