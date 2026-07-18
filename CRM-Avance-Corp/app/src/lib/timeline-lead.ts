// lib/timeline-lead.ts — Presentación del timeline de la ficha del lead.
// Función PURA (sin React) que agrupa el historial para que no crezca sin cota.
import type { Actividad } from './tipos'

/** Un ítem del timeline ya listo para pintar: o una actividad suelta, o una
 * RACHA colapsada de cambios de etapa consecutivos (≥2). */
export type ItemTimeline =
  | { clase: 'act'; act: Actividad }
  | { clase: 'grupo_etapa'; id: string; items: Actividad[] }

/**
 * Colapsa rachas CONSECUTIVAS de `cambio_etapa` (≥2) en un solo ítem
 * desplegable, para que el ruido de arrastrar el lead ida y vuelta entre etapas
 * no entierre las llamadas/notas. `acts` viene más reciente primero (orden de
 * actividadesDe) y ese orden se preserva. Un cambio de etapa aislado NO se
 * agrupa.
 */
export function agruparTimeline(acts: Actividad[]): ItemTimeline[] {
  const out: ItemTimeline[] = []
  let racha: Actividad[] = []
  const cerrarRacha = () => {
    const [primera] = racha
    if (!primera) return
    if (racha.length === 1) out.push({ clase: 'act', act: primera })
    else out.push({ clase: 'grupo_etapa', id: `grp-${primera.id}`, items: racha })
    racha = []
  }
  for (const a of acts) {
    if (a.tipo === 'cambio_etapa') {
      racha.push(a)
      continue
    }
    cerrarRacha()
    out.push({ clase: 'act', act: a })
  }
  cerrarRacha()
  return out
}
