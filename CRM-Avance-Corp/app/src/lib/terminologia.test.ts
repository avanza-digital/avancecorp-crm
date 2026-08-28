import { describe, expect, it } from 'vitest'
import { normalizarCitasInternas, presentarCitas } from './terminologia'

describe('presentarCitas', () => {
  it('cambia singular y plural conservando mayúsculas', () => {
    expect(presentarCitas('Reunión, reunión; Reuniones, reuniones; REUNIÓN y REUNIONES')).toBe(
      'Cita, cita; Citas, citas; CITA y CITAS',
    )
  })

  it('cubre títulos históricos sin tilde', () => {
    expect(presentarCitas('Reunion, reunion y REUNION')).toBe('Cita, cita y CITA')
  })

  it('no modifica contratos internos ni palabras más largas', () => {
    expect(presentarCitas('reunion_agendada · reuniones_realizadas · MetricasReuniones')).toBe(
      'reunion_agendada · reuniones_realizadas · MetricasReuniones',
    )
  })

  it('restaura el vocabulario histórico antes de persistir o consultar', () => {
    expect(normalizarCitasInternas('Cita, cita; Citas, citas; CITA y CITAS')).toBe(
      'Reunión, reunión; Reuniones, reuniones; REUNIÓN y REUNIONES',
    )
  })
})
