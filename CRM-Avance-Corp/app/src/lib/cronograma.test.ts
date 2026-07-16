import { describe, expect, it } from 'vitest'
import { generarCronograma, vencimientoDesdePlazo } from './cronograma'

// Fidelidad del PORT del generador del portal (public_html/js/admin/contratos.js).
// Si estos números cambian, el CRM dejó de calcular igual que el portal.
describe('cronograma — interés simple', () => {
  it('mensual 1 año: 12 cuotas de interés fijo + retorno del capital a +7d', () => {
    const c = generarCronograma(12000, 18, '2026-01-15', '2027-01-15', 'mensual', 'simple')
    const cuotas = c.filter((x) => x.tipo === 'cuota')
    const retorno = c.filter((x) => x.tipo === 'retorno')
    expect(cuotas).toHaveLength(12)
    expect(cuotas.every((x) => x.monto_programado === 180)).toBe(true) // 12000*0.18/12
    expect(retorno).toHaveLength(1)
    expect(retorno[0]!.monto_programado).toBe(12000)
    expect(retorno[0]!.fecha_programada).toBe('2027-01-22') // vencimiento + 7d
  })

  it('trimestral 1 año: 4 cuotas + retorno', () => {
    const c = generarCronograma(10000, 12, '2026-03-31', '2027-03-31', 'trimestral', 'simple')
    expect(c.filter((x) => x.tipo === 'cuota')).toHaveLength(4)
    expect(c.filter((x) => x.tipo === 'cuota')[0]!.monto_programado).toBe(300) // 10000*0.12/4
  })
})

describe('cronograma — interés compuesto', () => {
  it('2 años: intereses acumulados (devolucion) al vencimiento + capital (retorno) a +7d', () => {
    const c = generarCronograma(10000, 18, '2026-01-15', '2028-01-15', 'anual', 'compuesto')
    expect(c).toHaveLength(2)
    const dev = c.find((x) => x.tipo === 'devolucion')!
    const ret = c.find((x) => x.tipo === 'retorno')!
    // Capitaliza anual: 10000→11800→13924; interés total = 3924.
    expect(dev.monto_programado).toBe(3924)
    expect(dev.fecha_programada).toBe('2028-01-15')
    expect(ret.monto_programado).toBe(10000)
    expect(ret.fecha_programada).toBe('2028-01-22')
  })

  it('sin años exactos → vacío (no genera cronograma inválido)', () => {
    expect(generarCronograma(10000, 18, '2026-01-15', '2026-07-15', 'anual', 'compuesto')).toHaveLength(0)
  })
})

describe('vencimientoDesdePlazo', () => {
  it('recorta el desborde de fin de mes', () => {
    expect(vencimientoDesdePlazo('2026-01-31', 1)).toBe('2026-02-28') // no 3-mar
    expect(vencimientoDesdePlazo('2026-01-15', 12)).toBe('2027-01-15')
  })
})
