# Matriz comercial — Hoy del supervisor

Fase 1 del Goal, 18/10/2026. Revisión de Codex sobre el código actual.
Las fuentes son contratos existentes; no se cambian fórmulas, permisos ni SQL.

| Indicador | Fuente y población | Regla/periodo | Acción |
| --- | --- | --- | --- |
| Leads por repartir | `useResumenCarteraOperativo` → `listarResumenCartera` → `crm.resumen_cartera_fn`; ámbito autorizado | `totales.parkeados`, abiertos sin analista, incluidos pendientes anteriores. El resumen del servidor es completo aunque la página sea de una fila. | Bandeja `#/derivaciones`. |
| Llamadas del equipo | `useDiaEquipo` → `gestion_diaria_equipo_fn`; foto completa del equipo autorizado | Suma de `marcador.llamadas` del día Lima. | Registro del equipo con pestaña llamadas. |
| Contacto | Misma foto de Gestión Diaria | Suma contestadas / suma útiles × 100; sin útiles, ausencia de tasa. Respetar mínimo de muestra del servidor. | Registro y detalle por analista. |
| Primeras gestiones vencidas | Foto diaria, `primer_intento_vencido` | Suma solo si todas las filas tienen la regla disponible; no inventar cero cuando falta. | Equipo que necesita apoyo. |
| Citas de hoy | `useDatosCitasGerencia` → `useCitasGerencia`; consulta del mes/actor | Fecha prevista en Lima; cada estado se cuenta explícitamente. No usar creación ni inferir asistencia. | `#/reuniones/dia/<hoy>`. |
| Resultados de hoy | `useResultadosHoy` → `useFacturacionDiaria`; ámbito completo autorizado por el servidor | Fecha comercial de Facturación. Sumar `operaciones`, no filas/clientes. Todos los tipos válidos, atribución histórica, PEN/USD separados. | Desglose por analista y Facturación. |
| Capital/meta/brecha mensual | `useDatosSupervisor`, store y `cumplimientoDesdeRpc`; foto oficial mensual de capital/metas del supervisor | Mismo periodo y revisión. Valoración oficial cuando existe; en legado convertir con la regla compartida. Si no son comparables, sin porcentaje ni brecha. | Tabla mensual. |
| Operaciones mensuales | `operacionesConfirmadas` sobre el cumplimiento del supervisor | `contratos_real` del corte valorado o `contratosReal` legado; sin corte no reconstruir desde cifras viejas. | Tabla mensual y Facturación. |
| Conversión mensual | `useConversionMensual`, alcance `equipo`, actor y mes | `totalConversionPublicable` y `lecturaCobertura`; usar tasa oficial y no promedios individuales. | Tabla mensual con divisor por persona. |
| Tareas y apoyo | `useDiaEquipo`, `presentarEquipo` y reglas del servidor | Pendientes actuales y vencidas al corte; apoyo por motivos/umbrales existentes. No todas las tareas son de hoy. | Detalle de analista y seguimiento del ámbito. |

## Disponibilidad y población

- Un cero requiere respuesta válida. Error, ausencia, posible recorte o corte
  anterior a hoy no acreditan cero cierres.
- Capital/metas y conversión tienen poblaciones oficiales diferentes. Las filas
  mensuales siguen el agregado de `cumplimientoDesdeRpc`; no sustituirlo por el
  roster operativo ni ampliarlo con reglas nuevas.
- Facturación diaria conserva todos los productores que el servidor autoriza,
  incluidos subequipos y atribución histórica; no aplicar un filtro de supervisor
  directo en el navegador.
- La sesión limpia la caché mediante `AUTH_CLEARED_EVENT`. La vista también se
  remonta por actor/demo/día. Revisar la independencia de las consultas al actor.
- El detalle y la tarjeta de resultados consumen el mismo agregado, con importes
  originales por moneda. La demo usa sus contratos existentes sin cambiar fechas.

## Brechas de implementación identificadas

| ID | Evidencia inicial | Alcance a completar |
| --- | --- | --- |
| B1 | `useResumenCartera` carece de intervalo; invalidación por reparto existe, pero no garantiza nuevas llegadas con Hoy abierto. | Refresco visible y aislado al actor; cubrir llegada, reparto parcial/total, regreso y error. |
| B2 | Facturación refresca cada 5 min; el resumen mensual del store solo al volver o mutar/actualizar. | Refrescar el mes durante una sesión abierta sin duplicar fórmulas ni lecturas por fila. |
| B3 | «Ver pendientes» abre la cola SLA de seguimiento, que no es la lista exacta de tareas que cuenta la cabecera. | Dar acceso inequívoco a tareas por analista y nombrar correctamente el acceso amplio. |
| B4 | Pruebas actuales cubren error de reparto, pero no la secuencia visible 0 → varios → 1 → 0. | Pruebas de cambios confirmados y ausencia de espacio/aviso al agotarse. |
| B5 | Checks previos son de la iteración local; árbol Git en rama antigua con muchos cambios ajenos. | Revisión integral y preparación limpia del artefacto en fases 6–8, preservando trabajo ajeno. |

Estas brechas son el alcance previsto de las fases de implementación; no cambian
la definición comercial. El cierre de fase 1 acredita la matriz, no declara
corregido el código ni aprobado el ZIP.

## Revisión y verificación de fase 1

- CodeGraph consultado primero. Encontró el enrutamiento por rol, pero no todos
  los nuevos componentes; se completó con lecturas puntuales.
- Contraste con `resumen_cartera_fn`, `cumplimientoDesdeRpc`, consultas de Citas,
  Facturación, Gestión Diaria, store y notas del vault: definiciones consistentes.
- **PASS:** 32 pruebas en 5 archivos sobre agregados, vista, resultados, demo y
  frontera HTTP de Facturación. Log: `/private/tmp/hoy-supervisor-goal-20261018/fase1-base.log`.
- **NOT RUN:** gate de realidad; ejecución intentada, termina antes de consultar
  por ausencia de `SUPABASE_URL`. No se afirma conciliación productiva.
- **Claude inicial:** no necesaria; no hay nueva decisión de fórmula, autorización
  o contrato. Se reserva la revisión independiente para la implementación completa.
- **Cierre Codex:** matriz revisada, sin defectos de definición pendientes;
  brechas B1–B5 pasan al alcance de las fases correspondientes.

## Contraste con Main durante la fase 5

Main `49e2267c` incorpora desde octubre ventas propias del supervisor al capital
y operaciones de su equipo (`cumplimientoDesdeRpc`), sin asignarle una meta
individual. El desglose ahora conserva esa fila, incluida la identidad del corte
valorado aunque cambie el equipo vivo. La conversión usa exclusivamente su fuente
oficial; no se reconstruye con la conversión de cumplimiento ni se atribuye el
agregado «fuera de roster» a una persona sin evidencia.

La tarjeta Citas cuenta todos los estados del día previsto. La columna diaria
está rotulada «pendientes hoy» y usa Gestión Diaria; no son el mismo indicador.
Citas ya consulta cada 60 segundos en primer plano (actor/mes), además de foco,
reconexión y Actualizar. Reparto consulta cada 60 segundos; mes y Facturación,
cada cinco minutos visibles. Las invalidaciones de reparto conservan su prefijo.

El fallo booleano de `store.recargar` se registra en la portada como indisponibilidad
mensual incluso si conserva una foto vigente en memoria. Reintentar y cambiar de
mes comparten la petición en curso; una respuesta de otra sesión no reemplaza el
estado del nuevo actor. El TC solo se reconsulta por cambio de día o recuperación.

El resumen mensual también se revalida al entrar o regresar a Hoy; no espera
el primer intervalo. El arranque se cancela si la vista ya se desmontó.
