import { describe, expect, it } from 'vitest'
import { intervaloReconsultaSla } from './sla-operacion-reloj'

describe('reconsulta de fronteras informadas por el núcleo', () => {
  const datos = { calculado_en: '2026-09-07T15:00:00Z', proximo_cambio_en: '2026-09-07T15:00:12Z' }
  it('consulta al llegar la hora aunque el reloj local tenga otro día', () => {
    const recibido = Date.parse('2020-01-01Z')
    expect(intervaloReconsultaSla(datos, recibido, recibido)).toBe(12_000)
    expect(intervaloReconsultaSla(datos, recibido, recibido + 4_000)).toBe(8_000)
  })
  it('revalida pronto al volver de suspensión sin producir un bucle', () => {
    expect(intervaloReconsultaSla(datos, 1_000, 100_000)).toBe(1_000)
  })
  it('tolera servidores anteriores, ausencia de datos y fronteras inválidas', () => {
    for (const proximo_cambio_en of [null, undefined, 'infinity', '2026-09-06Z']) {
      expect(intervaloReconsultaSla({ ...datos, proximo_cambio_en }, 1_000, 1_000)).toBe(60_000)
    }
    expect(intervaloReconsultaSla(undefined, 0)).toBe(60_000)
    expect(intervaloReconsultaSla({ ...datos, proximo_cambio_en: '2026-09-08Z' }, 0, 0)).toBe(60_000)
  })
})
