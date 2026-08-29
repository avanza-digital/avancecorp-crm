import { renderHook } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { ACTIVIDADES_DEMO, EQUIPO_DEMO, LEADS_DEMO } from '@/lib/demo'
import { conversionMensualDemo } from '@/lib/demo-conversion-mensual'

const AHORA = Date.parse('2026-08-27T12:00:00-05:00')

vi.mock('@/lib/ahora', () => ({ useAhora: () => AHORA }))
vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({
    yo: {
      id: 'd-sup1',
      nombre_completo: 'SUPERVISOR UNO',
      rol: 'supervisor',
      demo: true,
      puede_contratar: false,
    },
  }),
}))
vi.mock('./crm-queries', () => ({
  useMetricasVendedores: () => ({
    data: undefined,
    dataUpdatedAt: 0,
    error: null,
    isPending: false,
    refetch: vi.fn(),
  }),
}))

const { useMetricasVendedoresOperativas } = await import('./use-metricas-vendedores-operativas')

describe('useMetricasVendedoresOperativas — demo mensual canónica', () => {
  it('cablea conversionMensualDemo del equipo y no revive la tasa local de 45 días', () => {
    const roster = EQUIPO_DEMO.filter((miembro) => miembro.supervisor_id === 'd-sup1')
    const { result } = renderHook(() => useMetricasVendedoresOperativas(
      roster,
      EQUIPO_DEMO,
      LEADS_DEMO,
      ACTIVIDADES_DEMO,
    ))
    const canonica = conversionMensualDemo(
      AHORA,
      { alcance: 'equipo', actorId: 'd-sup1' },
    )
    const filaCanonica = canonica.responsables.find((fila) => fila.vendedor_id === 'd-v1')
    const filaGestion = result.current.metricas?.filas.find((fila) => fila.m.perfil_id === 'd-v1')

    expect(filaCanonica).toBeDefined()
    expect(filaGestion).toMatchObject({
      conversionDisponible: true,
      conversion: filaCanonica?.conversion_pct,
      divisorConversion: filaCanonica?.divisor,
      numeradorConversion: filaCanonica?.numerador,
      operacionesCartera: filaCanonica?.cartera.conversiones_clientes,
    })
    expect(result.current.metricas?.mesMetrica).toBe('2026-08-01')
  })
})
