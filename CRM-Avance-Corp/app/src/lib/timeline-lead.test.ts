// Tests de agruparTimeline: colapsar rachas consecutivas de cambio_etapa (≥2)
// en un solo ítem, preservando el orden (más reciente primero). Función pura,
// sin render — el tope "Ver anteriores" es estado local del componente.
import { describe, expect, it } from 'vitest'
import { agruparTimeline } from './timeline-lead'
import type { Actividad, TipoActividad } from './tipos'

let seq = 0
function act(tipo: TipoActividad, detalle: string | null = null): Actividad {
  seq += 1
  return { id: `a${seq}`, lead_id: 'l1', tipo, detalle, autor_nombre: 'VENDEDOR UNO', creado_en: `2026-07-17T10:00:0${seq}Z` }
}

describe('agruparTimeline', () => {
  it('lista vacía → sin ítems', () => {
    expect(agruparTimeline([])).toEqual([])
  })

  it('un solo cambio_etapa NO se agrupa (queda como actividad suelta)', () => {
    const a = act('cambio_etapa', 'Nuevo → Contactado')
    const out = agruparTimeline([a])
    expect(out).toHaveLength(1)
    expect(out[0]).toEqual({ clase: 'act', act: a })
  })

  it('rachas de ≥2 cambios consecutivos se colapsan en un grupo', () => {
    const c1 = act('cambio_etapa', 'Reunión → Propuesta')
    const c2 = act('cambio_etapa', 'Propuesta → Reunión')
    const c3 = act('cambio_etapa', 'Contactado → Reunión')
    const out = agruparTimeline([c1, c2, c3])
    expect(out).toHaveLength(1)
    expect(out[0]).toEqual({ clase: 'grupo_etapa', id: `grp-${c1.id}`, items: [c1, c2, c3] })
  })

  it('actividades reales cortan la racha; el orden se preserva', () => {
    const c1 = act('cambio_etapa', 'A → B')
    const c2 = act('cambio_etapa', 'B → A')
    const llamada = act('llamada_realizada', 'primer contacto')
    const c3 = act('cambio_etapa', 'Nuevo → Contactado')
    const out = agruparTimeline([c1, c2, llamada, c3])
    expect(out).toHaveLength(3)
    expect(out[0]).toEqual({ clase: 'grupo_etapa', id: `grp-${c1.id}`, items: [c1, c2] })
    expect(out[1]).toEqual({ clase: 'act', act: llamada })
    // Un único cambio de etapa aislado NO se agrupa
    expect(out[2]).toEqual({ clase: 'act', act: c3 })
  })

  it('sin cambios de etapa: todo pasa como actividades sueltas', () => {
    const a1 = act('llamada_realizada')
    const a2 = act('nota', 'ojo')
    const out = agruparTimeline([a1, a2])
    expect(out).toEqual([
      { clase: 'act', act: a1 },
      { clase: 'act', act: a2 },
    ])
  })
})
