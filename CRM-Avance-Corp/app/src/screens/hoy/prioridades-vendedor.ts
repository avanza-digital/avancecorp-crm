import type { ItemCola } from '@/lib/inteligencia'
import type { EventoAgenda } from '@/lib/agenda-derivada'

export type PrioridadVendedor =
  | {
      fuente: 'cola'
      id: string
      leadId: string
      score: number
      item: ItemCola
    }
  | {
      fuente: 'agenda'
      id: string
      leadId: string
      score: number
      evento: EventoAgenda
    }

/**
 * Une agenda y cola en una franja de trabajo corta.
 *
 * Reglas perceptuales del contrato del vendedor:
 * - máximo tres decisiones simultáneas (Hick);
 * - una sola señal dominante por lead (Gestalt);
 * - todo speed-to-lead antes que cualquier recordatorio (su reloj no se entierra);
 * - una cita vencida gana a una cita futura y a seguimientos no críticos.
 *
 * La función no muta los arrays recibidos. Las superficies completas conservan
 * el detalle; la pantalla retira de ellas los leads elevados a «Ahora».
 */
export function seleccionarPrioridadesVendedor(
  agenda: readonly EventoAgenda[],
  cola: readonly ItemCola[],
  limite = 3,
): PrioridadVendedor[] {
  if (limite <= 0) return []

  const candidatos: Array<PrioridadVendedor & { orden: number }> = []
  let orden = 0

  for (const item of cola) {
    const speedToLead = item.bucket === 'sin_responder'
    const score = speedToLead
      ? 0
      : item.sev === 'critica'
        ? 1
        : item.sev === 'media'
          ? 4
          : 6
    candidatos.push({
      fuente: 'cola',
      id: `cola:${item.lead.id}`,
      leadId: item.lead.id,
      score,
      item,
      orden: orden++,
    })
  }

  for (const evento of agenda) {
    candidatos.push({
      fuente: 'agenda',
      id: `agenda:${evento.id}`,
      leadId: evento.lead_id,
      score: evento.vencida ? 2 : 3,
      evento,
      orden: orden++,
    })
  }

  candidatos.sort((a, b) => a.score - b.score || a.orden - b.orden)

  const vistos = new Set<string>()
  const resultado: PrioridadVendedor[] = []
  for (const candidato of candidatos) {
    if (vistos.has(candidato.leadId)) continue
    vistos.add(candidato.leadId)
    const { orden: _orden, ...prioridad } = candidato
    resultado.push(prioridad)
    if (resultado.length === limite) break
  }
  return resultado
}
