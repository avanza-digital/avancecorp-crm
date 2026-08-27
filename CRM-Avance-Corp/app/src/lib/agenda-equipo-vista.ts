// Vista del panel "Agenda del equipo" — helpers PUROS (sin React) que preparan
// la fotografía de crm.metricas_agenda_fn para leerse como la supervisión de
// distribución de gerencia: totales del ámbito primero, una sección por
// supervisor cuando hay varios equipos y las filas todo-en-cero colapsadas en
// una sola línea ("no registra nada" sigue siendo señal, pero ya no un muro).
import type { MetricaAgendaVendedor } from './metricas-agenda'
import type { Miembro } from './tipos'

/**
 * Las dos mitades de `canceladas`, con degradación honesta.
 *
 * FUENTE ÚNICA de la separación pedida por Miguel (2026-07-26): "separa lo que
 * cancela el sistema y lo que cancela el asesor". Nadie debe volver a leer
 * `ven.canceladas` a pelo para juzgar a una persona — ese número mezcla las
 * anulaciones del asesor con las que dispara el trigger cuando un lead se
 * convierte o se descarta.
 *
 * Si la BD todavía no tiene el desglose (migración sin aplicar), TODO cae del
 * lado del asesor: es exactamente el comportamiento de antes, así que el panel
 * no cambia de números por sorpresa a mitad de un despliegue. Nunca al revés —
 * mandarlas a «sistema» inflaría los % de todo el equipo con datos inventados.
 */
export function canceladasAsesor(ven: MetricaAgendaVendedor): number {
  return ven.canceladas_asesor ?? ven.canceladas
}

/** Las que canceló el trigger al cerrarse el lead. 0 si la BD no lo desglosa. */
export function canceladasSistema(ven: MetricaAgendaVendedor): number {
  return ven.canceladas_sistema ?? 0
}

/**
 * De las anulaciones humanas, las que firmó OTRO: su supervisor o gerencia.
 *
 * 0 cuando la BD no lo desglosa — misma degradación honesta que arriba, y en la
 * misma dirección: sin el dato TODO se considera propio, que es el
 * comportamiento anterior. Nunca al revés.
 */
export function canceladasAjenas(ven: MetricaAgendaVendedor): number {
  return ven.canceladas_ajenas ?? 0
}

/**
 * Las anulaciones que esta persona decidió SOBRE SU PROPIA agenda — las únicas
 * que pesan en su %.
 *
 * Decisión de Miguel (2026-07-26): «si el supervisor anula una tarea el
 * vendedor no debería poder hacer nada sobre esa tarea», o sea que tampoco
 * puede cargar con ella. Las propias SÍ cuentan: anular lo tuyo es una decisión
 * sobre tu agenda, y sacarlas convertiría el botón de anular en una salida
 * gratis para no hacer nada.
 *
 * El `max(0)` no es paranoia decorativa: `canceladas_asesor` y
 * `canceladas_ajenas` llegan como dos claves independientes y OPCIONALES. Una
 * BD a medio migrar puede mandar la segunda sin la primera, y sin el suelo el
 * denominador se iría en negativo y el % saldría disparado por encima de 100.
 */
export function canceladasPropias(ven: MetricaAgendaVendedor): number {
  return Math.max(0, canceladasAsesor(ven) - canceladasAjenas(ven))
}

/** Totales de agenda de un conjunto de miembros (ámbito completo o un equipo). */
export interface ResumenAgenda {
  toques: number
  completadas: number
  /** Cierres del periodo (completadas + no asistió + anuladas POR ÉL MISMO) —
   *  denominador del %. Quedan FUERA las que cancela el sistema (convertir un
   *  lead cancela sus pendientes, y contarlas hacía que cerrar la venta le
   *  bajara la nota) y las que anula un superior (no tuvo control sobre ellas).
   *  Espejo de pct_completadas en la RPC. */
  cierres: number
  /** % entero de completadas sobre cierres; null cuando no hubo cierres que porcentuar. */
  pctCompletadas: number | null
  noAsistio: number
  /** Leads abiertos sin próxima acción (foto actual). */
  sinAccion: number
  /** Tareas vencidas (foto actual). */
  vencidas: number
}

/** Id estable de la sección final para miembros sin supervisor en el payload. */
export const SIN_EQUIPO_ID = 'sin-equipo'

/** Sección por supervisor del modo agrupado (caso gerencia). */
export interface GrupoAgendaEquipo {
  /** vendedor_id del supervisor, o SIN_EQUIPO_ID en la sección final. */
  id: string
  /** Fila del supervisor en el payload; null solo en «Sin equipo asignado». */
  supervisor: MetricaAgendaVendedor | null
  nombreEquipo: string
  /** Miembros CON producción (incluye al supervisor si registra), toques desc → nombre. */
  miembros: MetricaAgendaVendedor[]
  /** Miembros todo-en-cero (colapsan en una línea), ordenados por nombre. */
  sinActividad: MetricaAgendaVendedor[]
  agregados: ResumenAgenda
}

function porNombre(a: MetricaAgendaVendedor, b: MetricaAgendaVendedor): number {
  return a.nombre.localeCompare(b.nombre, 'es')
}

/** Totales + % de completadas (null si no hubo cierres, igual que la RPC). */
export function resumenAgenda(vendedores: readonly MetricaAgendaVendedor[]): ResumenAgenda {
  let toques = 0
  let completadas = 0
  let cierres = 0
  let noAsistio = 0
  let sinAccion = 0
  let vencidas = 0
  for (const ven of vendedores) {
    toques += ven.toques
    completadas += ven.completadas
    cierres += ven.completadas + ven.no_asistio + canceladasPropias(ven)
    noAsistio += ven.no_asistio
    sinAccion += ven.leads_sin_accion
    vencidas += ven.vencidas
  }
  return {
    toques,
    completadas,
    cierres,
    pctCompletadas: cierres > 0 ? Math.round((completadas / cierres) * 100) : null,
    noAsistio,
    sinAccion,
    vencidas,
  }
}

/**
 * true si el miembro REGISTRÓ producción o planificación en el periodo.
 * No mira los derivados (toques_por_dia, pct_completadas): dependen de estos.
 *
 * 2026-08-23: `vencidas` y `leads_sin_accion` salieron de aquí a propósito —
 * son REZAGO, y el rezago vive solo en «Tu equipo hoy». Con ellas dentro, un
 * vendedor sin producción pero con 2 sin acción salía del colapso como una
 * fila entera de guiones (lo cazó la auditoría de Codex).
 */
export function tieneActividad(ven: MetricaAgendaVendedor): boolean {
  return (
    ven.toques > 0
    || ven.reuniones_realizadas > 0
    || ven.completadas > 0
    || ven.no_asistio > 0
    || ven.canceladas > 0
    || ven.tareas_creadas > 0
    || ven.reuniones_agendadas > 0
    || ven.reprogramaciones > 0
    || ven.pendientes > 0
  )
}

/**
 * Separa a los miembros con actividad de los todo-en-cero (la base del
 * colapso de filas-cero en el modo plano y dentro de cada sección).
 *
 * Orden de los activos por PRODUCCIÓN: toques desc y al final nombre. El
 * rezago dejó de ordenar esta tabla (2026-08-23): esta es la tabla de qué
 * hizo cada uno; quién arrastra pendientes se juzga en «Tu equipo hoy».
 */
export function separarPorActividad(vendedores: readonly MetricaAgendaVendedor[]): {
  conActividad: MetricaAgendaVendedor[]
  sinActividad: MetricaAgendaVendedor[]
} {
  const conActividad: MetricaAgendaVendedor[] = []
  const sinActividad: MetricaAgendaVendedor[] = []
  for (const ven of vendedores) (tieneActividad(ven) ? conActividad : sinActividad).push(ven)
  conActividad.sort((a, b) => b.toques - a.toques || porNombre(a, b))
  sinActividad.sort(porNombre)
  return { conActividad, sinActividad }
}

function grupoDe(
  id: string,
  supervisor: MetricaAgendaVendedor | null,
  nombreEquipo: string,
  filas: MetricaAgendaVendedor[],
): GrupoAgendaEquipo {
  const { conActividad, sinActividad } = separarPorActividad(filas)
  return {
    id,
    supervisor,
    nombreEquipo,
    miembros: conActividad,
    sinActividad,
    agregados: resumenAgenda(filas),
  }
}

/**
 * Agrupa el payload por SUPERVISOR (caso gerencia): una sección por supervisor
 * del payload (ordenadas por nombre), con el propio supervisor contado dentro
 * de su sección. Los vendedores cuyo supervisor no está en el payload — o que
 * no aparecen en `equipo` — van a una sección final «Sin equipo asignado».
 *
 * Devuelve null (modo plano) cuando no llega `equipo` o el payload trae 0-1
 * supervisores: el caso supervisor, donde seccionar sería ruido.
 */
export function agruparPorEquipo(
  vendedores: readonly MetricaAgendaVendedor[],
  equipo?: readonly Miembro[],
): GrupoAgendaEquipo[] | null {
  if (equipo == null) return null
  const supervisores = vendedores.filter((ven) => ven.rol === 'supervisor')
  if (supervisores.length <= 1) return null

  const supervisorDe = new Map(equipo.map((m) => [m.perfil_id, m.supervisor_id ?? null]))
  const filasPorSupervisor = new Map<string, MetricaAgendaVendedor[]>(
    supervisores.map((sup) => [sup.vendedor_id, [sup]]),
  )
  const sinEquipo: MetricaAgendaVendedor[] = []
  for (const ven of vendedores) {
    if (ven.rol === 'supervisor') continue
    const supervisorId = supervisorDe.get(ven.vendedor_id) ?? null
    const filas = supervisorId != null ? filasPorSupervisor.get(supervisorId) : undefined
    if (filas != null) filas.push(ven)
    else sinEquipo.push(ven)
  }

  const grupos = [...supervisores]
    .sort(porNombre)
    .map((sup) => grupoDe(sup.vendedor_id, sup, sup.nombre, filasPorSupervisor.get(sup.vendedor_id) ?? [sup]))
  if (sinEquipo.length > 0) {
    grupos.push(grupoDe(SIN_EQUIPO_ID, null, 'Sin equipo asignado', sinEquipo))
  }
  return grupos
}
