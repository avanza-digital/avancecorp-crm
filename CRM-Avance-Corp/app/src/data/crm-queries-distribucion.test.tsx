import { createElement, type ReactNode } from 'react'
import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  listarDistribucion: vi.fn(),
  actualizarCapacidad: vi.fn(),
}))

vi.mock('./crm-api', () => ({
  actualizarCapacidadLeadsObjetivo: mocks.actualizarCapacidad,
  listarMetricasDistribucionLeads: mocks.listarDistribucion,
  listarClientes: vi.fn(),
  listarMetricasCapitalMes: vi.fn(),
  listarMetricasPagosMes: vi.fn(),
  listarMetricasVencimientos: vi.fn(),
  listarMisContratos: vi.fn(),
  obtenerClienteDetalle: vi.fn(),
  obtenerCronograma: vi.fn(),
  obtenerTitulares: vi.fn(),
}))

import {
  crmQueryKeys,
  useActualizarCapacidadLeadsObjetivo,
} from './crm-queries'

const ANALISTA_ID = '11111111-1111-4111-8111-111111111111'

function arnes() {
  const cliente = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.listarDistribucion.mockResolvedValue({ version: 1 })
  mocks.actualizarCapacidad.mockResolvedValue({ analistaId: ANALISTA_ID, capacidad: 20 })
})

describe('query de distribución por capital', () => {
  it('pinea ambas fechas dentro de la clave bajo el prefijo de métricas', () => {
    expect(
      crmQueryKeys.metricasDistribucionLeads('2026-04-01', '2026-06-30'),
    ).toEqual([
      'crm',
      'metricas',
      'distribucion-leads',
      '2026-04-01',
      '2026-06-30',
    ])
  })

})

describe('mutación de capacidad', () => {
  it('manda variables e invalida el prefijo que cubre todas las distribuciones', async () => {
    const { cliente, wrapper } = arnes()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const { result } = renderHook(() => useActualizarCapacidadLeadsObjetivo(), { wrapper })

    await act(async () => {
      await result.current.mutateAsync({ analistaId: ANALISTA_ID, capacidad: 20 })
    })

    expect(mocks.actualizarCapacidad).toHaveBeenCalledWith(ANALISTA_ID, 20)
    expect(invalidar).toHaveBeenCalledWith({ queryKey: crmQueryKeys.metricas() })
  })
})
