import { createElement, type ReactNode } from 'react'
import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  publicarMetas: vi.fn(),
  actualizarJerarquiaUsuario: vi.fn(),
}))

vi.mock('@/lib/auth-context', () => ({
  useAuth: () => ({
    yo: {
      id: 'gerencia-1',
      nombre_completo: 'GERENCIA UNO',
      rol: 'gerencia',
      demo: false,
      puede_contratar: true,
    },
  }),
}))

vi.mock('./crm-config-api', async (importActual) => ({
  ...(await importActual<typeof import('./crm-config-api')>()),
  publicarMetas: mocks.publicarMetas,
  actualizarJerarquiaUsuario: mocks.actualizarJerarquiaUsuario,
}))

import { crmQueryKeys } from './crm-queries'
import { useActualizarJerarquiaUsuario, usePublicarMetas } from './crm-config-queries'

function arnes() {
  const cliente = new QueryClient({ defaultOptions: { mutations: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.publicarMetas.mockResolvedValue({})
  mocks.actualizarJerarquiaUsuario.mockResolvedValue({})
})

describe('invalidaciones de configuración con impacto comercial', () => {
  it('publicar metas refresca configuración y cumplimiento de todos los actores del mes', async () => {
    const { cliente, wrapper } = arnes()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const claveConversion = crmQueryKeys.conversionMensual('2026-08-01', 'global')
    const claveCosecha = crmQueryKeys.metricasConversionesEquipo(
      '2026-08-01',
      '2026-08-31',
      'global',
    )
    cliente.setQueryData(claveConversion, { foto: 'revision-anterior' })
    cliente.setQueryData(claveCosecha, { foto: 'revision-anterior' })
    const { result } = renderHook(() => usePublicarMetas('2026-08-01'), { wrapper })

    await act(async () => {
      await result.current.mutateAsync({} as never)
    })

    expect(invalidar).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.configMetas('2026-08-01'),
    })
    expect(invalidar).toHaveBeenCalledWith({
      queryKey: crmQueryKeys.cumplimientoMetasPeriodo('2026-08-01'),
    })
    expect(cliente.getQueryState(claveConversion)?.isInvalidated).toBe(true)
    expect(cliente.getQueryState(claveCosecha)?.isInvalidated).toBe(true)
  })

  it('cambiar jerarquía refresca roster y todas las lecturas cuyo ámbito depende de él', async () => {
    const { cliente, wrapper } = arnes()
    const invalidar = vi.spyOn(cliente, 'invalidateQueries')
    const { result } = renderHook(() => useActualizarJerarquiaUsuario(), { wrapper })

    await act(async () => {
      await result.current.mutateAsync({} as never)
    })

    const claves = invalidar.mock.calls.map(([filtros]) => filtros?.queryKey)
    expect(claves).toEqual(expect.arrayContaining([
      [...crmQueryKeys.config(), 'usuarios'],
      crmQueryKeys.configUsuariosCatalogo(),
      crmQueryKeys.metricasAmbito(),
      crmQueryKeys.metricasConversionesPrefijo(),
      crmQueryKeys.metricasConversionesEquipoPrefijo(),
      crmQueryKeys.conversionMensualPrefijo(),
      crmQueryKeys.cumplimientoMetasPrefijo(),
      crmQueryKeys.metricasReunionesPrefijo(),
    ]))
  })
})
