import { createElement, type ReactNode } from 'react'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  obtenerConversionMensual: vi.fn(),
  listarMetricasConversionesEquipo: vi.fn(),
  derivarLeadsEquipo: vi.fn(),
  revertirDerivacionEquipo: vi.fn(),
  convertirLeadExterno: vi.fn(),
  anularCierreExterno: vi.fn(),
  anularCierreAvance: vi.fn(),
}))

vi.mock('./crm-api', async (importActual) => ({
  ...(await importActual<typeof import('./crm-api')>()),
  obtenerConversionMensual: mocks.obtenerConversionMensual,
  listarMetricasConversionesEquipo: mocks.listarMetricasConversionesEquipo,
  derivarLeadsEquipo: mocks.derivarLeadsEquipo,
  revertirDerivacionEquipo: mocks.revertirDerivacionEquipo,
  convertirLeadExterno: mocks.convertirLeadExterno,
  anularCierreExterno: mocks.anularCierreExterno,
  anularCierreAvance: mocks.anularCierreAvance,
}))

import {
  crmQueryKeys,
  useAnularCierreAvance,
  useAnularCierreExterno,
  useConversionMensual,
  useConvertirLeadExterno,
  useDerivarLeadsEquipo,
  useMetricasConversionesEquipo,
  useRevertirDerivacionEquipo,
} from './crm-queries'

function arnes() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.obtenerConversionMensual.mockResolvedValue({ alcance: 'equipo' })
  mocks.listarMetricasConversionesEquipo.mockResolvedValue({ alcance: 'equipo' })
  mocks.derivarLeadsEquipo.mockResolvedValue({})
  mocks.revertirDerivacionEquipo.mockResolvedValue({})
  mocks.convertirLeadExterno.mockResolvedValue({})
  mocks.anularCierreExterno.mockResolvedValue({})
  mocks.anularCierreAvance.mockResolvedValue({})
})

describe('consultas de conversión con alcance explícito', () => {
  it('envía el alcance esperado a la RPC mensual', async () => {
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useConversionMensual(true, '2026-08-01', 'equipo', 's-1'),
      { wrapper },
    )

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(mocks.obtenerConversionMensual).toHaveBeenCalledWith(
      '2026-08-01',
      'equipo',
      expect.any(AbortSignal),
    )
  })

  it('envía el alcance esperado a la radiografía por vendedor', async () => {
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useMetricasConversionesEquipo(
        true,
        '2026-08-01',
        '2026-08-31',
        'global',
      ),
      { wrapper },
    )

    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(mocks.listarMetricasConversionesEquipo).toHaveBeenCalledWith(
      '2026-08-01',
      '2026-08-31',
      'global',
      expect.any(AbortSignal),
    )
  })

  it('no consulta un alcance propio o de equipo sin actor de caché', () => {
    const { wrapper } = arnes()
    renderHook(() => useConversionMensual(true, '2026-08-01', 'propio'), { wrapper })
    renderHook(() => useMetricasConversionesEquipo(
      true,
      '2026-08-01',
      '2026-08-31',
      'equipo',
    ), { wrapper })

    expect(mocks.obtenerConversionMensual).not.toHaveBeenCalled()
    expect(mocks.listarMetricasConversionesEquipo).not.toHaveBeenCalled()
  })
})

describe('invalidaciones que mueven la conversión', () => {
  it.each([
    ['derivar', useDerivarLeadsEquipo, []],
    ['revertir derivación', useRevertirDerivacionEquipo, 'lead-1'],
    ['convertir externamente', useConvertirLeadExterno, {}],
    ['anular cierre externo', useAnularCierreExterno, {}],
    ['anular cierre Avance', useAnularCierreAvance, {}],
  ] as const)('%s invalida todas las lecturas derivadas', async (_caso, usarMutacion, variables) => {
    const { cliente, wrapper } = arnes()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const { result } = renderHook(() => usarMutacion(), { wrapper })

    await act(async () => {
      await result.current.mutateAsync(variables as never)
    })

    const claves = invalidar.mock.calls.map(([filtros]) => filtros?.queryKey)
    expect(claves).toEqual(expect.arrayContaining([
      crmQueryKeys.metricasAmbito(),
      crmQueryKeys.metricasConversionesPrefijo(),
      crmQueryKeys.metricasConversionesEquipoPrefijo(),
      crmQueryKeys.metricasReunionesPrefijo(),
      crmQueryKeys.conversionMensualPrefijo(),
      crmQueryKeys.cumplimientoMetasPrefijo(),
    ]))
  })
})
