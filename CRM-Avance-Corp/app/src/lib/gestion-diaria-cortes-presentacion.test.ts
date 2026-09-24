import { describe, expect, it } from 'vitest'
import { jornadaH4 } from './gestion-diaria-h4.fixture'
import { presentarCortesJornada } from './gestion-diaria-cortes-presentacion'

describe('H4: horario y evaluación confirmada', () => {
  it('un corte futuro nunca se da por cumplido; el mínimo no se recalcula en cliente', () => {
    const { equipo } = jornadaH4()
    equipo.cortes!.equipo[0]!.segundo_corte!.objetivo = 27
    const r = presentarCortesJornada(equipo)
    expect(r[1]?.estado).toBe('Programado'); expect(r[1]?.personas[0]?.objetivo).toBe(27)
    expect(r[1]?.personas[0]?.llamadas).toBeNull()
  })
  it('pasar la hora no sustituye una evaluación faltante por cero incumplimientos', () => {
    const { equipo } = jornadaH4(); equipo.generado_en = '2026-09-24T17:00:00-05:00'
    expect(presentarCortesJornada(equipo)[1]?.estado).toBe('Evaluación pendiente')
  })
  it('conserva un resultado recuperado y pendientes después del cierre', () => {
    const { equipo } = jornadaH4(); equipo.generado_en = '2026-09-24T19:00:00-05:00'
    equipo.cortes!.equipo[0]!.primer_corte.puede_avisar = false
    expect(presentarCortesJornada(equipo)[0]).toMatchObject({ recuperados: 1, bajoMinimo: 1, estado: 'Evaluado' })
  })
  it('ausencia de datos y política OFF no fabrican horarios', () => {
    expect(presentarCortesJornada(null)).toEqual([])
    const { equipo } = jornadaH4(); equipo.cortes!.estado = 'desactivados'
    expect(presentarCortesJornada(equipo)).toEqual([])
  })
})
