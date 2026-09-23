import { describe, expect, it } from 'vitest'
import { soloPresentes } from './argumentos-rpc'

describe('soloPresentes', () => {
  it('omite null y undefined: la clave NO viaja y el servidor usa su DEFAULT NULL', () => {
    expect(soloPresentes({ p_etapa: null, p_dia: undefined, p_analista_id: 'a1' })).toEqual({ p_analista_id: 'a1' })
    expect(Object.keys(soloPresentes({ p_etapa: null }))).toEqual([])
  })

  it('conserva los valores «vacíos» que SÍ significan algo: 0, false, cadena vacía y arreglo vacío', () => {
    expect(soloPresentes({ a: 0, b: false, c: '', d: [] })).toEqual({ a: 0, b: false, c: '', d: [] })
  })
})
