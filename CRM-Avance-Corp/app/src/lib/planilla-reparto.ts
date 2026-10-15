import { hoyLimaIso, sumarDiasIso } from './distribucion-lecturas'
import { ORIGENES_LECTURA, type ColaLead, type DiaAgendaReparto, type OrigenLectura, type SupervisorReparto } from './tipos'

export interface PeriodoPlanilla {
  modo: 'todas' | 'dia' | 'semana' | 'rango' | 'dias'
  desde: string
  hasta: string
  dias: string[]
}
export const periodoInicial = (modo: PeriodoPlanilla['modo'], hoy = hoyLimaIso()): PeriodoPlanilla => ({ modo, desde: hoy, hasta: hoy, dias: [hoy] })

function fechaValida(fecha: string): boolean {
  const valor = new Date(`${fecha}T12:00:00Z`)
  return /^\d{4}-\d{2}-\d{2}$/.test(fecha) && Number.isFinite(valor.getTime()) && valor.toISOString().slice(0, 10) === fecha
}

/** Un año por consulta limita las lecturas; la RPC admite ventanas de 14 días. */
export function fechasPeriodo(periodo: PeriodoPlanilla): string[] | null {
  if (periodo.modo === 'todas') return null
  if (periodo.modo === 'dias') {
    const dias = [...new Set(periodo.dias)].sort()
    if (!dias.length || dias.length > 366 || dias.some((dia) => !fechaValida(dia))) throw new Error('Selecciona entre 1 y 366 días válidos.')
    return dias
  }
  if (!fechaValida(periodo.desde)) throw new Error('Completa una fecha válida.')
  let desde = periodo.desde
  let hasta = periodo.modo === 'rango' ? periodo.hasta : desde
  if (periodo.modo === 'semana') {
    const dia = new Date(`${desde}T12:00:00Z`).getUTCDay()
    desde = sumarDiasIso(desde, -(dia === 0 ? 6 : dia - 1))
    hasta = sumarDiasIso(desde, 6)
  }
  if (!fechaValida(hasta) || hasta < desde) throw new Error('El final debe ser igual o posterior al inicio.')
  const cantidad = Math.round((Date.parse(hasta) - Date.parse(desde)) / 86_400_000) + 1
  if (cantidad > 366) throw new Error('Consulta como máximo 366 días a la vez.')
  return Array.from({ length: cantidad }, (_, i) => sumarDiasIso(desde, i))
}

export function ventanasFechas(fechas: string[]): string[][] {
  const ventanas: string[][] = []
  for (const fecha of [...new Set(fechas)].sort()) {
    const ultima = ventanas.at(-1)
    if (ultima && ultima.length < 14 && sumarDiasIso(ultima.at(-1)!, 1) === fecha) ultima.push(fecha)
    else ventanas.push([fecha])
  }
  return ventanas
}

export function filtrarColaPlanilla(cola: ColaLead[], fechas: string[] | null, origenes: OrigenLectura[]): ColaLead[] {
  const seleccion = fechas === null ? null : new Set(fechas)
  return cola.filter((lead) => origenes.includes(lead.origen) && (!seleccion || seleccion.has(hoyLimaIso(new Date(lead.creado_en)))))
}

export interface FilaPlanilla { id: string; nombre: string; activo: boolean; recibidos: number; porOrigen: Partial<Record<OrigenLectura, number>> }
export function filasPlanilla(supervisores: SupervisorReparto[], dias: DiaAgendaReparto[], origenes: OrigenLectura[], seleccion: string[]): FilaPlanilla[] {
  const filas = new Map<string, FilaPlanilla>(supervisores.map((s) => [s.perfil_id, { id: s.perfil_id, nombre: s.nombre, activo: s.activo, recibidos: 0, porOrigen: {} }]))
  for (const dia of dias) {
    if (!dia.origenes) throw new Error('Falta el desglose de entregas por origen.')
    for (const grupo of dia.origenes.filter((g) => origenes.includes(g.origen))) {
      for (const entrega of grupo.entregas) {
        const id = entrega.supervisor_id ?? 'sin-destino'
        const fila = filas.get(id) ?? { id, nombre: entrega.supervisor_nombre || 'Destino no disponible', activo: false, recibidos: 0, porOrigen: {} }
        fila.recibidos += entrega.derivados
        fila.porOrigen[grupo.origen] = (fila.porOrigen[grupo.origen] ?? 0) + entrega.derivados
        filas.set(id, fila)
      }
    }
  }
  return [...filas.values()].filter((fila) => !seleccion.length || seleccion.includes(fila.id)).sort((a, b) => a.nombre.localeCompare(b.nombre, 'es'))
}

export type BorradorReparto = Record<string, Partial<Record<OrigenLectura, string>>>
export interface EntregaPreparada { lead: ColaLead; supervisorId: string; supervisorNombre: string }

/** Fija IDs una sola vez para revisión: FIFO por ingreso al CRM, sin sustituciones durante el envío. */
export function prepararReparto(borrador: BorradorReparto, cola: ColaLead[], destinos: FilaPlanilla[], origenes: OrigenLectura[]): EntregaPreparada[] {
  const filas = new Map(destinos.map((fila) => [fila.id, fila]))
  const pendientes = new Map<OrigenLectura, ColaLead[]>(ORIGENES_LECTURA.map(({ k }) => [k, cola.filter((lead) => lead.origen === k).sort((a, b) => a.creado_en.localeCompare(b.creado_en) || a.id.localeCompare(b.id))]))
  if (new Set(cola.map((lead) => lead.id)).size !== cola.length) throw new Error('La cola contiene identificadores repetidos. Actualiza antes de repartir.')
  const plan: EntregaPreparada[] = []
  for (const [id, cantidades] of Object.entries(borrador).sort(([a], [b]) => (filas.get(a)?.nombre ?? a).localeCompare(filas.get(b)?.nombre ?? b, 'es') || a.localeCompare(b))) {
    for (const [origenCrudo, texto] of Object.entries(cantidades)) {
      if (!texto || texto === '0') continue
      const origen = origenCrudo as OrigenLectura
      const destino = filas.get(id)
      if (!destino?.activo || !origenes.includes(origen)) throw new Error('Hay cantidades fuera de los filtros o un destino dejó de estar disponible. Revisa la planilla.')
      if (!/^\d+$/.test(texto) || !Number.isSafeInteger(Number(texto))) throw new Error('Escribe cantidades enteras mayores o iguales a cero.')
      const cantidad = Number(texto)
      const disponibles = pendientes.get(origen) ?? []
      if (cantidad > disponibles.length) throw new Error('Las cantidades superan los pendientes disponibles de un origen. Ajusta la planilla.')
      for (const lead of disponibles.splice(0, cantidad)) plan.push({ lead, supervisorId: id, supervisorNombre: destino.nombre })
    }
  }
  return plan
}

export interface ResultadoReparto { confirmadas: EntregaPreparada[]; interrumpida: EntregaPreparada | null; pendientes: number; error: string | null; rechazada?: boolean }
/** Cada RPC es atómica; el conjunto no. Ante respuesta incierta se detiene, nunca se reintenta a ciegas. */
export async function ejecutarReparto(plan: EntregaPreparada[], enviar: (leadId: string, supervisorId: string) => Promise<void>, continuar: () => boolean | string, progreso: (cantidad: number) => void): Promise<ResultadoReparto> {
  const confirmadas: EntregaPreparada[] = []
  for (const entrega of plan) {
    const continuidad = continuar()
    if (continuidad !== true) return { confirmadas, interrumpida: null, pendientes: plan.length - confirmadas.length, error: typeof continuidad === 'string' ? continuidad : 'Envío detenido. Las entregas confirmadas se conservan.' }
    try {
      await enviar(entrega.lead.id, entrega.supervisorId)
      confirmadas.push(entrega)
      progreso(confirmadas.length)
    } catch (fallo) {
      const rechazada = fallo instanceof Error && 'code' in fallo && ['FUERA_DE_COLA', 'NO_INSISTA', 'SIN_PERMISO', 'REGLA_SERVIDOR', 'REINTENTAR', 'CONFLICTO'].includes(String(fallo.code))
      if (rechazada) return { confirmadas, interrumpida: entrega, pendientes: plan.length - confirmadas.length - 1, rechazada: true, error: `Entrega rechazada: ${fallo.message}. Se detuvo el lote; las confirmadas se conservan.` }
      return { confirmadas, interrumpida: entrega, pendientes: plan.length - confirmadas.length - 1, error: 'No se confirmó esta entrega. Puede haberse registrado; consulta el historial antes de volver a prepararla.' }
    }
  }
  return { confirmadas, interrumpida: null, pendientes: 0, error: null }
}
