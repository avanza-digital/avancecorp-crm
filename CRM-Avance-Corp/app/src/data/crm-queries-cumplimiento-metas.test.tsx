import { createElement, type ReactNode } from 'react'
import { renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { CumplimientoMetasRpc } from '@/lib/objetivos'

const mocks = vi.hoisted(() => ({
  obtenerCumplimiento: vi.fn(),
}))

vi.mock('./crm-api', async (importActual) => ({
  ...(await importActual<typeof import('./crm-api')>()),
  obtenerCumplimientoMetas: mocks.obtenerCumplimiento,
}))

import { crmQueryKeys, useCumplimientoMetas } from './crm-queries'

const VENDEDOR_ID = '11111111-1111-4111-8111-111111111111'
const SUPERVISOR_ID = '22222222-2222-4222-8222-222222222222'

const RESPUESTA: CumplimientoMetasRpc = {
  version: 1,
  periodo: '2026-08-01',
  revision: 4,
  publicada_en: '2026-08-01T13:00:00Z',
  fuentes_reales: {
    capital_y_contratos: 'contratos_confirmados',
    conversion: 'leads_recibidos_ponderado',
  },
  vendedores: [{
    vendedor_id: VENDEDOR_ID,
    nombre: 'ANA TORRES',
    supervisor_id: SUPERVISOR_ID,
    supervisor_nombre: 'SUPERVISORA UNO',
    conversion_objetivo: 15,
    conversion_real: 20,
    convertidos: 2,
    resueltos: 10,
    numerador: 2,
    cierres_no_referidos: 2,
    cierres_referidos: 0,
    detalles: [{
      categoria: 'nuevo',
      moneda: 'PEN',
      capital_objetivo: 100_000,
      capital_real: 40_000,
      capital_cumplimiento_pct: 40,
      contratos_objetivo: 0,
      contratos_real: 1,
      contratos_cumplimiento_pct: null,
    }],
  }],
}

function arnes() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  return { cliente, wrapper }
}

beforeEach(() => {
  vi.clearAllMocks()
  mocks.obtenerCumplimiento.mockResolvedValue(RESPUESTA)
})

describe('cumplimiento mensual del ranking', () => {
  it('pinea el mes en la clave y adapta la foto autoritativa para el actor', async () => {
    const { cliente, wrapper } = arnes()
    const { result } = renderHook(
      () => useCumplimientoMetas(true, '2026-08-01', SUPERVISOR_ID),
      { wrapper },
    )

    await waitFor(() => expect(result.current.isSuccess).toBe(true))

    expect(mocks.obtenerCumplimiento).toHaveBeenCalledWith('2026-08-01', expect.any(AbortSignal))
    expect(cliente.getQueryCache().find({
      queryKey: crmQueryKeys.cumplimientoMetas('2026-08-01'),
      exact: true,
    })).toBeDefined()
    expect(result.current.data).toMatchObject({
      periodo: '2026-08-01',
      revision: 4,
      supervisor: { conversionObjetivo: 15 },
      porVendedor: {
        [VENDEDOR_ID]: {
          nombre: 'ANA TORRES',
          supervisorNombre: 'SUPERVISORA UNO',
          conversionObjetivo: 15,
        },
      },
    })
  })

  it('deshabilitada registra la clave pero no toca el servidor', () => {
    const { cliente, wrapper } = arnes()
    renderHook(() => useCumplimientoMetas(false, '2026-08-01', SUPERVISOR_ID), { wrapper })

    expect(mocks.obtenerCumplimiento).not.toHaveBeenCalled()
    expect(cliente.getQueryCache().getAll().map((query) => query.queryKey)).toEqual([
      ['crm', 'metricas', 'cumplimiento-metas', '2026-08-01'],
    ])
  })

  it('propaga el fallo sin fabricar una foto vacía', async () => {
    mocks.obtenerCumplimiento.mockRejectedValue(new Error('500 simulado'))
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useCumplimientoMetas(true, '2026-08-01', SUPERVISOR_ID),
      { wrapper },
    )

    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
  })

  it('rechaza una respuesta válida de otro mes para no cruzar fotos en caché', async () => {
    mocks.obtenerCumplimiento.mockResolvedValue({
      ...RESPUESTA,
      periodo: '2026-07-01',
    })
    const { wrapper } = arnes()
    const { result } = renderHook(
      () => useCumplimientoMetas(true, '2026-08-01', SUPERVISOR_ID),
      { wrapper },
    )

    await waitFor(() => expect(result.current.isError).toBe(true))
    expect(result.current.data).toBeUndefined()
    expect(result.current.error).toEqual(
      new Error('La foto mensual recibida no corresponde al periodo solicitado'),
    )
  })
})
