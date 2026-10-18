// La caché del plazo de carga: qué se re-pregunta solo, y qué caduca al fijar
// el plazo. Una invalidación olvidada no falla ruidoso: deja a Gerencia viendo
// el plazo viejo, o la conversión de antes de la reevaluación, sin aviso.
import { createElement, type ReactNode } from 'react'
import { act, renderHook, waitFor } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { beforeEach, describe, expect, it, vi } from 'vitest'

const mocks = vi.hoisted(() => ({
  obtenerPlazosCargaMes: vi.fn(),
  fijarPlazoCargaMes: vi.fn(),
}))

vi.mock('./crm-api', async (importActual) => ({
  ...(await importActual<typeof import('./crm-api')>()),
  obtenerPlazosCargaMes: mocks.obtenerPlazosCargaMes,
  fijarPlazoCargaMes: mocks.fijarPlazoCargaMes,
}))

import { CrmApiError } from './crm-api'
import {
  INTERVALO_CIERRE_MES_ESTADO_MS,
  crmQueryKeys,
  opcionesPlazosCargaMes,
  useFijarPlazoCargaMes,
  usePlazosCargaMes,
} from './crm-queries'

const DATOS = { mes: '2026-09', ultimoDia: '2026-10-20', motivo: 'Los analistas aún cargan ventas' }

function arnes() {
  const cliente = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
  const wrapper = ({ children }: { children: ReactNode }) =>
    createElement(QueryClientProvider, { client: cliente }, children)
  // Lecturas ya en caché (sin observadores: invalidar las marca, no las vuelve a pedir).
  const claves = {
    plazos: crmQueryKeys.plazosCargaMes(),
    cierre: crmQueryKeys.cierreMesEstado(),
    conversion: crmQueryKeys.conversionMensual('2026-09-01', 'global'),
    cumplimiento: crmQueryKeys.cumplimientoMetas('2026-10-01', 'g-1'),
    cooperativas: crmQueryKeys.cierresExternos('2026-09-01'),
    facturacion: crmQueryKeys.facturacionDiaria('2026-10'),
    leads: crmQueryKeys.carteraPagina('todas', 'todos', ''),
    metas: crmQueryKeys.configMetas('2026-09-01'),
  }
  for (const clave of Object.values(claves)) cliente.setQueryData(clave, { semilla: true })
  const invalidada = (clave: readonly unknown[]) => cliente.getQueryState(clave)?.isInvalidated === true
  return { cliente, wrapper, claves, invalidada }
}

beforeEach(() => {
  vi.clearAllMocks()
  vi.spyOn(console, 'error').mockImplementation(() => {})
  mocks.fijarPlazoCargaMes.mockResolvedValue({ ok: true, mes: '2026-09', reabierto: false })
})

describe('lectura del plazo de carga', () => {
  it('re-pregunta con el mismo sondeo que el aviso del ciclo y la habilitación viaja tal cual', () => {
    expect(opcionesPlazosCargaMes(true).refetchInterval).toBe(INTERVALO_CIERRE_MES_ESTADO_MS)
    expect(opcionesPlazosCargaMes(true).enabled).toBe(true)
    expect(opcionesPlazosCargaMes(false).enabled).toBe(false)
    // Literal a propósito: cambiar la forma de la clave rompe a quien invalida.
    expect(crmQueryKeys.plazosCargaMes()).toEqual(['crm', 'plazos-carga-mes'])
  })

  it('deshabilitada (otro rol o demo) no sale a la red', () => {
    const { wrapper } = arnes()
    renderHook(() => usePlazosCargaMes(false), { wrapper })
    expect(mocks.obtenerPlazosCargaMes).not.toHaveBeenCalled()
  })

  it('habilitada pide la lectura con la señal de cancelación', async () => {
    mocks.obtenerPlazosCargaMes.mockResolvedValue({ version: 1, hoy: '2026-10-14', zona: 'America/Lima', meses: [] })
    const { wrapper } = arnes()
    const { result } = renderHook(() => usePlazosCargaMes(true), { wrapper })
    await waitFor(() => expect(result.current.isSuccess).toBe(true))
    expect(mocks.obtenerPlazosCargaMes).toHaveBeenCalledWith(expect.any(AbortSignal))
  })
})

describe('fijar el plazo de carga', () => {
  it('al guardar caducan el plazo y el aviso del ciclo ANTES de resolver, y las fotos de métricas', async () => {
    const { wrapper, claves, invalidada } = arnes()
    const { result } = renderHook(() => useFijarPlazoCargaMes(), { wrapper })

    await act(async () => { await result.current.mutateAsync(DATOS) })

    expect(mocks.fijarPlazoCargaMes).toHaveBeenCalledWith(DATOS)
    // Esperadas por la mutación: al cerrar el diálogo la tarjeta ya pinta lo nuevo.
    expect(invalidada(claves.plazos)).toBe(true)
    expect(invalidada(claves.cierre)).toBe(true)
    // Conversión, cumplimiento, cooperativas y Facturación cuelgan de metricas().
    await waitFor(() => expect(invalidada(claves.conversion)).toBe(true))
    expect(invalidada(claves.cumplimiento)).toBe(true)
    expect(invalidada(claves.cooperativas)).toBe(true)
    expect(invalidada(claves.facturacion)).toBe(true)
    // Lo que el plazo no mueve, no se toca.
    expect(invalidada(claves.leads)).toBe(false)
    expect(invalidada(claves.metas)).toBe(false)
  })

  it('un rechazo de negocio (nada se guardó) no invalida nada', async () => {
    mocks.fijarPlazoCargaMes.mockRejectedValue(new CrmApiError('La fecha debe ser hoy o una fecha futura', 'REGLA_SERVIDOR'))
    const { wrapper, claves, invalidada } = arnes()
    const { result } = renderHook(() => useFijarPlazoCargaMes(), { wrapper })

    await act(async () => { await expect(result.current.mutateAsync(DATOS)).rejects.toThrow('hoy o una fecha futura') })

    expect(Object.values(claves).some(invalidada)).toBe(false)
  })

  it.each(['RESPUESTA_NO_RECIBIDA', 'PLAZO_CARGA_CONTRACT'])('tras %s (pudo guardarse) se refresca igual que en un éxito', async (codigo) => {
    mocks.fijarPlazoCargaMes.mockRejectedValue(new CrmApiError('pudo guardarse', codigo))
    const { wrapper, claves, invalidada } = arnes()
    const { result } = renderHook(() => useFijarPlazoCargaMes(), { wrapper })

    await act(async () => { await expect(result.current.mutateAsync(DATOS)).rejects.toThrow('pudo guardarse') })

    expect(invalidada(claves.plazos)).toBe(true)
    expect(invalidada(claves.cierre)).toBe(true)
    await waitFor(() => expect(invalidada(claves.conversion)).toBe(true))
  })
})
