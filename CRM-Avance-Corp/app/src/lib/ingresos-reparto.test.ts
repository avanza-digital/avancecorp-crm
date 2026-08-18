import { describe, expect, it } from 'vitest'
import {
  etiquetaMesReparto,
  etiquetaSemana,
  inicioDeMes,
  mesActualLima,
} from './ingresos-reparto'

describe('helpers de ingresos de reparto', () => {
  it('calcula el mes con el reloj de Lima, no con el dia UTC', () => {
    expect(mesActualLima(Date.parse('2026-09-01T03:30:00Z'))).toBe('2026-08')
    expect(mesActualLima(Date.parse('2026-09-01T05:30:00Z'))).toBe('2026-09')
  })

  it('solo acepta claves YYYY-MM reales y las convierte al primer dia', () => {
    expect(inicioDeMes('2026-08')).toBe('2026-08-01')
    expect(inicioDeMes('2026-13')).toBeNull()
    expect(inicioDeMes('agosto')).toBeNull()
  })

  it('nombra el mes y los rangos semanales sin depender de la zona del navegador', () => {
    expect(etiquetaMesReparto('2026-08')).toBe('agosto 2026')
    expect(etiquetaSemana('2026-08-01', '2026-08-02')).toBe('1–2 ago')
    expect(etiquetaSemana('2026-08-31', '2026-08-31')).toBe('31 ago')
  })
})
