import { agendaRepartoDiaria, leadsPorRepartir, supervisoresParaReparto } from './crm-api'
import { ventanasFechas } from '@/lib/planilla-reparto'
import type { DiaAgendaReparto } from '@/lib/tipos'

export async function cargarPlanilla(fechas: string[], signal: AbortSignal) {
  const controlador = new AbortController()
  const cancelar = () => controlador.abort()
  signal.addEventListener('abort', cancelar, { once: true })
  if (signal.aborted) cancelar()
  try {
    const [cola, supervisores, agendas] = await Promise.all([
      leadsPorRepartir(controlador.signal, true), supervisoresParaReparto(controlador.signal), cargarEntregas(fechas, controlador.signal),
    ])
    if (controlador.signal.aborted) throw new DOMException('Lectura cancelada', 'AbortError')
    return { cola, supervisores, ...agendas }
  } catch (error) {
    cancelar() // Una rama fallida no deja leyendo ventanas o páginas hermanas.
    throw error
  } finally { signal.removeEventListener('abort', cancelar) }
}

async function cargarEntregas(fechas: string[], signal: AbortSignal) {
  const dias: DiaAgendaReparto[] = []
  let repartoLibre = true
  // Ventanas sin solapes, secuenciales para no saturar la API con rangos largos.
  for (const ventana of ventanasFechas(fechas)) {
    const agenda = await agendaRepartoDiaria({ desde: ventana[0]!, dias: ventana.length }, signal)
    if (signal.aborted) throw new DOMException('Lectura cancelada', 'AbortError')
    if (agenda.fecha_desde !== ventana[0] || agenda.dias.length !== ventana.length || new Set(agenda.dias.map((dia) => dia.fecha)).size !== ventana.length || agenda.dias.some((dia) => !ventana.includes(dia.fecha) || !dia.origenes)) {
      throw new Error('La consulta de entregas llegó incompleta. Actualiza; no se muestran ceros en lugar de datos faltantes.')
    }
    repartoLibre = repartoLibre && agenda.reparto_libre === true
    dias.push(...agenda.dias)
  }
  return { dias: dias.sort((a, b) => a.fecha.localeCompare(b.fecha)), repartoLibre }
}

export type DatosPlanilla = Awaited<ReturnType<typeof cargarPlanilla>>
