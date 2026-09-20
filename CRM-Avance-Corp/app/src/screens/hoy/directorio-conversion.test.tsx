import { render, screen } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { Miembro } from '@/lib/tipos'
import type { ResumenCartera } from '@/lib/resumen-cartera'

let CONVERSION: number | null = 137.63
let CONVERSION_DISPONIBLE = true
let CIERRES_TOTAL: number | null = 0
let AVISO_CONVERSION: string | null = null
let RESUMEN: ResumenCartera | null = null

const SUPERVISORA: Miembro = {
  perfil_id: 's-1',
  nombre_completo: 'SUPERVISORA UNO',
  rol_crm: 'supervisor',
  supervisor_id: null,
  activo: true,
}

vi.mock('@/lib/store-context', () => ({
  useCRMData: () => ({ ambito: { leads: [] }, equipo: [SUPERVISORA], actividades: [] }),
  usePanelesActions: () => ({ abrirLead: vi.fn() }),
}))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({ yo: { demo: false, rol: 'directorio' } }),
}))
vi.mock('@/lib/ahora', () => ({ useAhora: () => Date.parse('2026-08-27T12:00:00Z') }))
// Fase 3 «sin topes»: la bitácora la sirve una RPC; aquí no hay QueryClient.
vi.mock('@/data/crm-queries', () => ({
  useActividadesRecientes: () => ({ data: [], isPending: false, error: null, refetch: vi.fn() }),
}))
vi.mock('@/data/use-resumen-cartera-operativo', () => ({
  useResumenCarteraOperativo: () => ({ resumen: RESUMEN, error: null, recargar: vi.fn() }),
}))
vi.mock('@/data/use-metricas-vendedores-operativas', () => ({
  useMetricasVendedoresOperativas: () => ({
    metricas: {
      filas: [],
      equipos: [{
        supervisor: SUPERVISORA,
        vendedores: 1,
        activos: 0,
        capitalPEN: 0,
        capitalUSD: 0,
        convertidos: 0,
        cierresConversion: CONVERSION_DISPONIBLE ? 0 : null,
        conversion: CONVERSION,
        conversionDisponible: CONVERSION_DISPONIBLE,
        operacionesCartera: CONVERSION_DISPONIBLE ? 4 : null,
        divisorConversion: CONVERSION_DISPONIBLE ? CONVERSION == null ? 0 : 8 : null,
        numeradorConversion: CONVERSION_DISPONIBLE ? CONVERSION == null ? 4 : 11.0104 : null,
        parkeados: 0,
      }],
      totalConversion: {
        cierresConversion: CIERRES_TOTAL,
        conversion: CONVERSION,
        conversionDisponible: CONVERSION_DISPONIBLE,
        operacionesCartera: CONVERSION_DISPONIBLE ? 4 : null,
        divisorConversion: CONVERSION_DISPONIBLE ? CONVERSION == null ? 0 : 8 : null,
        numeradorConversion: CONVERSION_DISPONIBLE ? CONVERSION == null ? 4 : 11.0104 : null,
      },
      generadoEn: '2026-08-27T12:00:00Z',
      avisoConversion: AVISO_CONVERSION,
      mesMetrica: '2026-08-01',
    },
    error: null,
    recargar: vi.fn(),
  }),
}))
vi.mock('@/lib/tipo-cambio', async (importOriginal) => ({
  ...await importOriginal<typeof import('@/lib/tipo-cambio')>(),
  useTipoCambio: () => ({ tc: null, recargar: vi.fn() }),
}))

const { HoyDirectorio } = await import('./directorio')

describe('HoyDirectorio — conversión exacta por equipo', () => {
  beforeEach(() => {
    CONVERSION = 137.63
    CONVERSION_DISPONIBLE = true
    CIERRES_TOTAL = 0
    AVISO_CONVERSION = null
    RESUMEN = null
  })

  it('conserva decimales, >100 y operaciones de cartera', () => {
    const { container } = render(<HoyDirectorio />)
    const fila = screen.getByRole('row', { name: /SUPERVISORA UNO/ })

    expect(fila).toHaveTextContent('137.63% · 4 de cartera')
    expect(fila).not.toHaveTextContent('138%')
    expect(container.querySelector('[style*="width: 100%"]')).toBeNull()
  })

  it('conserva NULL; no lo convierte en 0 aunque existan operaciones de cartera', () => {
    CONVERSION = null
    render(<HoyDirectorio />)
    const fila = screen.getByRole('row', { name: /SUPERVISORA UNO/ })

    expect(fila).toHaveTextContent('— · Sin divisor mensual · 4 de cartera')
    expect(fila).not.toHaveTextContent('0%')
  })

  it('una lectura de equipo no disponible no inventa cierres, divisor ni cartera', () => {
    CONVERSION = null
    CONVERSION_DISPONIBLE = false
    render(<HoyDirectorio />)
    const fila = screen.getByRole('row', { name: /SUPERVISORA UNO/ })

    expect(fila).toHaveTextContent('Dato no disponible')
    expect(fila).not.toHaveTextContent('Sin divisor mensual')
    expect(fila).not.toHaveTextContent('de cartera')
  })

  it('usa cierres mensuales canónicos y no mezcla ese contador con el capital de 45 días', () => {
    CIERRES_TOTAL = 7
    RESUMEN = {
      version: 1,
      generado_en: '2026-08-27T12:00:00Z',
      ventana_convertidos_dias: 45,
      ventana_metrica: 'mes_calendario',
      mes_metrica: '2026-08-01',
      totales: {
        vivos: 20,
        abiertos: 10,
        asignados: 8,
        parkeados: 2,
        // Lectura heredada deliberadamente contradictoria: ya no alimenta la
        // tarjeta; el total viene del wrapper mensual vía métricas.
        convertidos: 99,
        descartados: 3,
        asignados_pen: 6,
        asignados_usd: 2,
        operaciones_cartera: 4,
      },
      capital: {
        asignado: { pen: 100_000, usd: 2_000 },
        parkeado: { pen: 20_000, usd: 0 },
        ganado: { pen: 80_000, usd: 1_000 },
      },
      // Lectura heredada deliberadamente contradictoria: no debe filtrarse a
      // la tarjeta mensual ni como valor ni como denominador.
      conversion: { convertidos: 88, base: 321, pct: 27.41 },
      descartes: { total: 3, sin_motivo: 0, por_motivo: [] },
      embudo: [],
      sin_tocar: 0,
    }
    render(<HoyDirectorio />)

    const tarjetaCierres = screen.getByText('Cierres del mes').closest('[data-slot="card"]')
    expect(tarjetaCierres).not.toBeNull()
    expect(tarjetaCierres).toHaveTextContent('7')
    expect(tarjetaCierres).toHaveTextContent('Cierres de leads del mes calendario')
    expect(tarjetaCierres).not.toHaveTextContent('99')
    expect(tarjetaCierres).not.toHaveTextContent('88')
    expect(tarjetaCierres).not.toHaveTextContent('321')

    const tarjetaCapital = screen.getByText('Capital ganado').closest('[data-slot="card"]')
    expect(tarjetaCapital).not.toBeNull()
    expect(tarjetaCapital).toHaveTextContent('Capital de cierres · últimos 45 d')
    expect(tarjetaCapital).not.toHaveTextContent('7 convertidos')
  })

  it('avisa una cobertura provisional o en revisión junto a la auditoría', () => {
    AVISO_CONVERSION = 'Provisional: al mes le faltan días de registro'
    render(<HoyDirectorio />)

    expect(screen.getByText(AVISO_CONVERSION).closest('[role="status"]')).not.toBeNull()
  })
})
