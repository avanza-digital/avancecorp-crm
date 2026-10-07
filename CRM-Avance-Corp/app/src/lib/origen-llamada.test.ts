import { describe, expect, it } from 'vitest'
import { cuandoFueLaLlamada, momentoDeOrigenLlamada, origenLlamadaValido } from './origen-llamada'

describe('id de la llamada del celular', () => {
  it('acepta la forma que exige la base: etiqueta C1–C999 y diez dígitos', () => {
    for (const id of ['C1-1790980958', 'C12-1790980958', 'C999-1790980958']) expect(origenLlamadaValido(id)).toBe(true)
  })

  it('rechaza lo demás (la URL no puede colar otra cosa hasta la encuesta)', () => {
    for (const id of ['', 'C0-1790980958', 'C1000-1790980958', 'c1-1790980958', 'C1-179098095', 'C1-17909809581',
      'C1_1790980958', 'X1-1790980958', 'C1-1790980958 ', ' C1-1790980958', 'C1-17909a0958', '../C1-1790980958']) {
      expect(origenLlamadaValido(id), id).toBe(false)
    }
  })

  it('lee su hora en segundos', () => {
    expect(momentoDeOrigenLlamada('C7-1790980958')).toBe(1_790_980_958_000)
  })

  it('dice la hora en Lima; si no fue hoy, también el día', () => {
    // 1790980958 = 2026-10-02T22:42:38Z = 17:42 del 02/10 en Lima (UTC−5).
    const id = 'C1-1790980958'
    expect(cuandoFueLaLlamada(id, Date.parse('2026-10-02T23:00:00Z'))).toBe('de las 17:42')
    expect(cuandoFueLaLlamada(id, Date.parse('2026-10-05T15:00:00Z'))).toBe('del 02/10 a las 17:42')
    // Pasada la medianoche UTC sigue siendo el mismo día en Lima.
    expect(cuandoFueLaLlamada(id, Date.parse('2026-10-03T03:00:00Z'))).toBe('de las 17:42')
  })
})
