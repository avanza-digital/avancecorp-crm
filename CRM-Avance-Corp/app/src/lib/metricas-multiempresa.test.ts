import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { metricasMultiempresaDemo } from './demo-metricas-multiempresa'
import { MetricasMultiempresaSchema, estadoConciliacion, informeMultiempresaCompleto } from './metricas-multiempresa'

const ejemplo = () => metricasMultiempresaDemo('2026-09-01', '2026-09-11')
describe('Integridad del informe multiempresa', () => {
  it('valida el ejemplo y mantiene monedas y empresas separadas', () => {
    const r = ejemplo()
    expect(v.safeParse(MetricasMultiempresaSchema, r).success).toBe(true)
    expect(informeMultiempresaCompleto(r)).toBe(true)
    expect(estadoConciliacion(r)).toBe('coincide')
    expect(r.produccion).toHaveLength(4)
  })
  it.each(['produccion', 'atribucion', 'tipos_capital', 'conciliacion'] as const)('rechaza grupos duplicados en %s', campo => {
    const r = ejemplo()
    r[campo].push({ ...r[campo][0] } as never)
    expect(informeMultiempresaCompleto(r)).toBe(false)
  })
  it.each(['atribucion', 'tipos_capital', 'conciliacion'] as const)('detecta un detalle truncado de %s', campo => {
    const r = ejemplo(); r[campo].pop()
    expect(informeMultiempresaCompleto(r)).toBe(false)
  })
  it('distingue una diferencia de negocio de un payload incompleto', () => {
    const r = ejemplo(); r.conciliacion[0]!.capital_nucleo += 100; r.conciliacion[0]!.diferencia_capital = -100
    r.conciliacion[0]!.diferencia_atribucion = -100
    expect(informeMultiempresaCompleto(r)).toBe(true)
    expect(estadoConciliacion(r)).toBe('diferencias')
  })
  it('rechaza una conciliación que declara cero pero contiene importes distintos', () => {
    const r = ejemplo(); r.conciliacion[0]!.capital_nucleo += 0.01
    expect(informeMultiempresaCompleto(r)).toBe(false)
  })
  it('una respuesta vacía nunca equivale a una conciliación aprobada', () => {
    const r = ejemplo(); r.produccion = []; r.atribucion = []; r.tipos_capital = []; r.conciliacion = []
    expect(estadoConciliacion(r)).toBe('sin_movimientos')
  })
  it('conserva un grupo del núcleo ausente del informe como diferencia explícita', () => {
    const r = ejemplo()
    r.conciliacion.push({ empresa: 'prodelco', moneda: 'USD', capital_nucleo: 99.01, capital_informe: 0,
      operaciones_nucleo: 1, operaciones_informe: 0, diferencia_capital: -99.01,
      diferencia_operaciones: -1, diferencia_atribucion: -99.01 })
    expect(informeMultiempresaCompleto(r)).toBe(true)
    expect(estadoConciliacion(r)).toBe('diferencias')
    r.conciliacion.at(-1)!.capital_informe = 10
    expect(informeMultiempresaCompleto(r)).toBe(false)
  })
  it('rechaza cantidades negativas, capital no finito, campos omitidos y versiones ajenas', () => {
    for (const cambio of [{ version: 2 }, { conversion: undefined }, { personas: null }]) {
      expect(v.safeParse(MetricasMultiempresaSchema, { ...ejemplo(), ...cambio }).success).toBe(false)
    }
    for (const capital of [NaN, Infinity, -10]) {
      const r = ejemplo(); r.produccion[0]!.capital = capital
      expect(v.safeParse(MetricasMultiempresaSchema, r).success).toBe(false)
    }
  })
  it('rechaza particiones de identidad y fechas incompatibles', () => {
    const r = ejemplo(); r.personas.total++
    expect(informeMultiempresaCompleto(r)).toBe(false)
    const x = ejemplo(); x.hasta = '2026-10-01'
    expect(informeMultiempresaCompleto(x)).toBe(false)
  })
})
