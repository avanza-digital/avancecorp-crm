import { describe, it, expect } from 'vitest'
import { entrevistaCompatibleConVenta, ventaComercialDelMes } from './fecha-comercial'

describe('fecha comercial sin hora', () => {
 it('el primer día del mes no retrocede por el desfase UTC de Lima', () => {
  const venta = { fecha_comercial: '2026-10-01', convertido_en: '2026-10-06T15:00:00Z' }
  expect(ventaComercialDelMes(venta, '2026-10', '2026-10-07T00:00:00Z')).toBe(true)
  expect(ventaComercialDelMes(venta, '2026-09', '2026-10-07T00:00:00Z')).toBe(false)
  expect(entrevistaCompatibleConVenta('2026-10-02T04:59:59Z', venta.fecha_comercial)).toBe(true)
  expect(entrevistaCompatibleConVenta('2026-10-02T05:00:00Z', venta.fecha_comercial)).toBe(false)
 })
 it('sin fecha comercial no infiere una venta desde la fecha de registro', () => {
  expect(ventaComercialDelMes({ fecha_comercial: null, convertido_en: '2026-10-01T15:00:00Z' }, '2026-10', '2026-10-17T00:00:00Z')).toBe(false)
  expect(entrevistaCompatibleConVenta('2026-09-01T15:00:00Z', null)).toBe(false)
 })
 it('excluye ventas futuras y registros todavía no conocidos al corte', () => {
  const corte = '2026-10-01T04:59:59Z' // aún septiembre en Lima
  expect(ventaComercialDelMes({ fecha_comercial: '2026-10-01', convertido_en: corte }, '2026-10', corte)).toBe(false)
  expect(ventaComercialDelMes({ fecha_comercial: '2026-09-01', convertido_en: '2026-10-06T15:00:00Z' }, '2026-09', corte)).toBe(false)
 })
})
