// Vista del panel "Agenda del equipo" — helpers PUROS (sin React) que preparan
// la fotografía de crm.metricas_agenda_fn para leerse como la supervisión de
// distribución de gerencia: totales del ámbito primero, una sección por
// supervisor cuando hay varios equipos y las filas todo-en-cero colapsadas en
// una sola línea ("no registra nada" sigue siendo señal, pero ya no un muro).
import type { MetricaAgendaVendedor } from './metricas-agenda'
import type { Miembro } from './tipos'

/** Totales de agenda de un conjunto de miembros (ámbito completo o un equipo). */
export interface ResumenAgenda {
  toques: number
  completadas: number
  /** Cierres del periodo (completadas + no asistió + canceladas) — denominador del %. */
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
  /** Miembros CON actividad (incluye al supervisor si registra), rezago desc → toques desc → nombre. */
  miembros: MetricaAgendaVendedor[]
  /** Miembros todo-en-cero (colapsan en una línea), ordenados por nombre. */
  sinActividad: MetricaAgendaVendedor[]
  agregados: ResumenAgenda
}

function porNombre(a: MetricaAgendaVendedor, b: MetricaAgendaVendedor): number {
  return a.nombre.localeCompare(b.nombre, 'es')
}

/** Rezago acumulado del miembro: lo que el manager destraba HOY. */
function rezagoDe(ven: MetricaAgendaVendedor): number {
  return ven.vencidas + ven.leads_sin_accion + ven.no_asistio
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
    cierres += ven.completadas + ven.no_asistio + ven.canceladas
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
 * true si el miembro registró algo en el periodo o arrastra carga viva.
 * No mira los derivados (toques_por_dia, pct_completadas): dependen de estos.
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
    || ven.vencidas > 0
    || ven.leads_sin_accion > 0
  )
}

/**
 * Separa a los miembros con actividad de los todo-en-cero (la base del
 * colapso de filas-cero en el modo plano y dentro de cada sección).
 *
 * Orden de los activos por SEVERIDAD: primero quien acumula rezago
 * (vencidas + sin acción + no asistió) desc — lo que el manager destraba
 * hoy — luego toques desc y al final nombre. Los cero van alfabéticos.
 */
export function separarPorActividad(vendedores: readonly MetricaAgendaVendedor[]): {
  conActividad: MetricaAgendaVendedor[]
  sinActividad: MetricaAgendaVendedor[]
} {
  const conActividad: MetricaAgendaVendedor[] = []
  const sinActividad: MetricaAgendaVendedor[] = []
  for (const ven of vendedores) (tieneActividad(ven) ? conActividad : sinActividad).push(ven)
  conActividad.sort(
    (a, b) => rezagoDe(b) - rezagoDe(a) || b.toques - a.toques || porNombre(a, b),
  )
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
