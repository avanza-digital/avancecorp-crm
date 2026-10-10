import { describe, expect, it } from 'vitest'
import { listaCuadraConNumero, mismosTotales, parametrosDeCifra, type CifraFacturacion } from './parametros-de-cifra'

const base: CifraFacturacion = { dias: ['2026-10-01', '2026-10-02', '2026-10-03'], vista: 'TOTAL' }
const rango = { p_desde: '2026-10-01', p_hasta: '2026-10-03', p_pagina: 1, p_tamano: 25 }
describe('parametrosDeCifra: cada número conserva su ámbito', () => {
  it.each([
    ['pastilla total del tramo', {}, rango],
    ['pastilla por moneda', { vista: 'USD' }, { ...rango, p_moneda: 'USD' }],
    ['pastilla por tipo', { tipo: 'cooperativa' }, { ...rango, p_tipos: ['cooperativa'] }],
    ['celda analista × día', { analistaId: 'ana', equipoId: 'antes', dias: ['2026-10-02'] }, { ...rango, p_desde: '2026-10-02', p_hasta: '2026-10-02', p_analistas: ['ana'], p_equipo: 'antes' }],
    ['total de fila', { analistaId: 'ana', equipoId: 'antes' }, { ...rango, p_analistas: ['ana'], p_equipo: 'antes' }],
    ['total de día', { dias: ['2026-10-02'] }, { ...rango, p_desde: '2026-10-02', p_hasta: '2026-10-02' }],
    ['total de equipo', { equipoId: 'historico' }, { ...rango, p_equipo: 'historico' }],
    ['Sin supervisor', { equipoId: 'sin-supervisor' }, { ...rango, p_sin_equipo: true }],
    ['Sin analista', { analistaId: 'sin-analista' }, { ...rango, p_sin_analista: true }],
    ['Día por tipo', { dias: ['2026-10-02'], tipo: 'contrato_upgrade', vista: 'PEN' }, { ...rango, p_desde: '2026-10-02', p_hasta: '2026-10-02', p_tipos: ['contrato_upgrade'], p_moneda: 'PEN' }],
    ['días sueltos del total de fila', { analistaId: 'ana', diasMarcados: ['2026-10-03', '2026-10-01'] }, { ...rango, p_analistas: ['ana'], p_dias: ['2026-10-01', '2026-10-03'] }],
    ['analistas comparados', { analistas: ['ana', 'beto'], tipo: 'todo' }, { ...rango, p_analistas: ['ana', 'beto'] }],
    ['semana que cruza meses', { dias: ['2026-09-30', '2026-10-01'] }, { ...rango, p_desde: '2026-09-30', p_hasta: '2026-10-01' }],
  ] as const)('%s', (_nombre, extra, esperado) => {
    expect(parametrosDeCifra({ ...base, ...extra })).toEqual(esperado)
  })
  it('no muta los días, y manda incluso días marcados consecutivos', () => {
    const diasMarcados = Object.freeze(['2026-10-02', '2026-10-01'])
    expect(parametrosDeCifra({ ...base, diasMarcados }, 2, 50)).toEqual({ ...rango, p_hasta: '2026-10-02', p_dias: ['2026-10-01', '2026-10-02'], p_pagina: 2, p_tamano: 50 })
    expect(diasMarcados[0]).toBe('2026-10-02')
  })
  it('rechaza un rango vacío, excesivo o una selección incompatible', () => {
    for (const dias of [[], ['2026-10-01', '2026-11-01'], ['ayer']]) expect(() => parametrosDeCifra({ ...base, dias })).toThrow(/tramo/)
    expect(() => parametrosDeCifra({ ...base, analistas: ['ana', 'sin-analista'] })).toThrow(/por separado/)
  })
  it('detecta diferencias aunque se compensen al convertir las monedas', () => {
    expect(mismosTotales([{ moneda: 'PEN', operaciones: 1, monto: 300 }], [{ moneda: 'USD', operaciones: 1, monto: 100 }])).toBe(false)
    expect(mismosTotales([], [])).toBe(true)
  })
})

it('Cuadra comprueba la cifra pulsada además de su composición', () => {
  const totales = [{ moneda: 'PEN' as const, monto: 20, operaciones: 1 }]
  const lista = { version: 1 as const, pagina: 1, tamano: 25 as const, total: 1, totales, filas: [] }
  const abierto = { titulo: 'Total', cifra: base, totales, valor: 20, metrica: 'capital' as const }
  expect(listaCuadraConNumero(abierto, lista)).toBe(true)
  expect(listaCuadraConNumero({ ...abierto, valor: 21 }, lista)).toBe(false)
  expect(listaCuadraConNumero({ ...abierto, valor: 7, cuenta: { modo: 'promedio', divisor: 3 } }, lista)).toBe(true)
})

it.each([
  ['fracciones', Array.from({ length: 300 }, (_, i) => i % 2 === 0 ? 0.1 : 0.2)],
  ['decenas de millones', [90_000_000, ...Array.from({ length: 299 }, () => 0.1)]],
] as const)('Cuadra al céntimo tras muchas sumas: %s', (_caso, sumandos) => {
  const navegador = sumandos.reduce((a, b) => a + b, 0)
  if (_caso === 'decenas de millones') expect(Math.abs(navegador - 90_000_029.9)).toBeGreaterThan(0.000001)
  const centimos = sumandos.reduce((a, b) => a + Math.round(b * 100), 0) / 100
  const totales = [{ moneda: 'PEN' as const, operaciones: 300, monto: navegador }]
  const lista = { version: 1 as const, pagina: 1, tamano: 25 as const, total: 300, filas: [], totales: [{ ...totales[0]!, monto: centimos }] }
  const abierto = { titulo: 'Total', cifra: base, totales, valor: navegador, metrica: 'capital' as const }
  expect(mismosTotales(totales, lista.totales)).toBe(true)
  expect(listaCuadraConNumero(abierto, lista)).toBe(true)
  expect(listaCuadraConNumero({ ...abierto, valor: centimos + 0.006 }, lista)).toBe(false)
  expect(mismosTotales(totales, [{ ...totales[0]!, monto: centimos + 0.01 }])).toBe(false)
})

it('el capital admite menos de medio céntimo; los contratos son exactos', () => {
  const totales = [{ moneda: 'PEN' as const, operaciones: 3, monto: 100 }]
  const lista = { version: 1 as const, pagina: 1, tamano: 25 as const, total: 3, filas: [], totales }
  const abierto = { titulo: 'Total', cifra: base, totales, valor: 100.004, metrica: 'capital' as const }
  expect(listaCuadraConNumero(abierto, lista)).toBe(true)
  expect(listaCuadraConNumero({ ...abierto, valor: 100.006 }, lista)).toBe(false)
  expect(listaCuadraConNumero({ ...abierto, metrica: 'contratos', valor: 3 }, lista)).toBe(true)
  expect(listaCuadraConNumero({ ...abierto, metrica: 'contratos', valor: 3.0000001 }, lista)).toBe(false)
})
