import { describe, expect, it } from 'vitest'
import { etiquetasMeses, seriesComerciales, SERIES_VACIAS } from './series-comerciales'
import type { Lead } from './tipos'

// Reloj inyectado: 15 de julio 2026 al mediodía Lima → ventana feb..jul (6 meses).
const AHORA = Date.UTC(2026, 6, 15, 17, 0) // 12:00 en Lima (UTC-5)

function lead(parche: Partial<Lead>): Lead {
  return {
    id: `l-${Math.abs(JSON.stringify(parche).length)}-${parche.creado_en ?? ''}-${parche.etapa ?? ''}`,
    nombre_completo: 'LEAD SERIE',
    telefono: '+51999000111',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 10_000,
    moneda: 'PEN',
    creado_en: '2026-07-10T15:00:00Z',
    activo: true,
    ...parche,
  }
}

describe('seriesComerciales', () => {
  it('cuenta leads nuevos por mes calendario de Lima (frontera UTC incluida)', () => {
    const series = seriesComerciales([
      lead({ creado_en: '2026-07-10T15:00:00Z' }),
      // 01 jul 03:00Z = 30 jun 22:00 Lima → cuenta en JUNIO, no julio.
      lead({ creado_en: '2026-07-01T03:00:00Z' }),
      // Enero queda fuera de la ventana de 6 meses (feb..jul).
      lead({ creado_en: '2026-01-20T12:00:00Z' }),
    ], AHORA)
    expect(series.leads).toEqual([0, 0, 0, 0, 1, 1])
  })

  it('capital y cierres van al MES DE CIERRE (actualizado_en) y el capital solo suma PEN', () => {
    const series = seriesComerciales([
      lead({
        etapa: 'convertido', contrato_id: 'c-pen', monto_estimado: 100_000, moneda: 'PEN',
        creado_en: '2026-04-10T15:00:00Z', actualizado_en: '2026-06-20T15:00:00Z',
      }),
      lead({
        etapa: 'convertido', contrato_id: 'c-usd', monto_estimado: 50_000, moneda: 'USD',
        creado_en: '2026-05-05T15:00:00Z', actualizado_en: '2026-06-25T15:00:00Z',
      }),
      lead({
        etapa: 'convertido', monto_estimado: 300_000, moneda: 'PEN',
        creado_en: '2026-05-10T15:00:00Z', actualizado_en: '2026-06-26T15:00:00Z',
      }),
    ], AHORA)
    // feb mar abr may jun jul
    expect(series.cierres).toEqual([0, 0, 0, 0, 2, 0])
    expect(series.capital).toEqual([0, 0, 0, 0, 100_000, 0]) // el USD no se mezcla
    expect(series.conversion).toEqual([0, 0, 100, 50, 0, 0])
  })

  it('la conversión del mes es clientes con contrato sobre leads recibidos', () => {
    const series = seriesComerciales([
      lead({ etapa: 'convertido', contrato_id: 'c-jul', creado_en: '2026-07-01T15:00:00Z', actualizado_en: '2026-07-10T15:00:00Z' }),
      lead({ etapa: 'descartado', creado_en: '2026-07-02T15:00:00Z', actualizado_en: '2026-07-11T15:00:00Z' }),
      lead({ etapa: 'descartado', creado_en: '2026-06-02T15:00:00Z', actualizado_en: '2026-06-11T15:00:00Z' }),
    ], AHORA)
    expect(series.conversion).toEqual([0, 0, 0, 0, 0, 50])
  })

  it('ignora leads desactivados (borrado suave) y tolera fechas rotas', () => {
    const series = seriesComerciales([
      lead({ activo: false, etapa: 'convertido', contrato_id: 'c-inactivo', actualizado_en: '2026-07-01T15:00:00Z' }),
      lead({ creado_en: 'no-es-fecha' }),
    ], AHORA)
    expect(series.leads).toEqual([0, 0, 0, 0, 0, 0])
    expect(series.cierres).toEqual([0, 0, 0, 0, 0, 0])
  })

  it('sin actualizado_en (optimista local) el cierre cae al mes de creación', () => {
    const series = seriesComerciales([
      lead({ etapa: 'convertido', contrato_id: 'c-local', creado_en: '2026-07-03T15:00:00Z' }),
    ], AHORA)
    expect(series.cierres).toEqual([0, 0, 0, 0, 0, 1])
  })

  it('SERIES_VACIAS no tiene puntos (los chips no se dibujan)', () => {
    expect(SERIES_VACIAS.capital).toHaveLength(0)
  })

  it('genera etiquetas mensuales ascendentes para las gráficas', () => {
    expect(etiquetasMeses('2026-08-05', 3)).toEqual(['Jun', 'Jul', 'Ago'])
  })
})

// F5a «Bases cargadas»: un cierre sin capital (null) cuenta como cierre pero no suma capital (ni NaN).
describe('F5a · capital vacío en las series', () => {
  it('cuenta el cierre y deja el capital del mes en número', () => {
    const series = seriesComerciales([
      lead({ etapa: 'convertido', contrato_id: 'c-1', monto_estimado: 20_000, actualizado_en: '2026-07-12T15:00:00Z' }),
      lead({ id: 'sin', etapa: 'convertido', contrato_id: 'c-2', monto_estimado: null, actualizado_en: '2026-07-12T15:00:00Z' }),
    ], AHORA)
    expect(series.cierres.at(-1)).toBe(2)
    expect(series.capital.at(-1)).toBe(20_000)
    expect(series.capital.every((c) => Number.isFinite(c))).toBe(true)
  })
})
