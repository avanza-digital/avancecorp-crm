import { createElement, type ReactNode } from 'react'
import { act, cleanup, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider, focusManager } from '@tanstack/react-query'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { resumenCarteraDesdeAmbito } from '@/lib/resumen-cartera'
import type { Actividad, Lead } from '@/lib/tipos'
import * as api from './crm-api'
import { crmQueryKeys } from './crm-queries'
import { useResumenCarteraOperativo } from './use-resumen-cartera-operativo'

let actor = { id: 's1', rol: 'supervisor', demo: false }
vi.mock('@/lib/auth-context', () => ({ useAuth: () => ({ yo: actor }) }))
const leads: Lead[] = []
const actividades: Actividad[] = []
const foto = (pendientes: number) => {
  const resumen = resumenCarteraDesdeAmbito(leads, actividades, Date.now())
  resumen.totales.parkeados = pendientes
  return resumen
}
let cliente: QueryClient
const wrapper = ({ children }: { children: ReactNode }) => createElement(QueryClientProvider, { client: cliente }, children)
const pasar = async (ms: number) => { await act(async () => { await vi.advanceTimersByTimeAsync(ms) }) }

beforeEach(() => {
  vi.useFakeTimers()
  actor = { id: 's1', rol: 'supervisor', demo: false }
  cliente = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: Infinity, staleTime: 30_000 } } })
  focusManager.setFocused(true)
})
afterEach(() => { cleanup(); cliente.clear(); focusManager.setFocused(undefined); vi.useRealTimers() })

describe('reparto del supervisor actualizado y autorizado', () => {
  it('recibe nuevas llegadas y refleja reparto parcial y total con Hoy abierto', async () => {
    const consultar = vi.spyOn(api, 'listarResumenCartera').mockResolvedValue(foto(0))
    const { result } = renderHook(() => useResumenCarteraOperativo(leads, actividades, true, true), { wrapper })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(0)
    consultar.mockResolvedValue(foto(4))
    await pasar(60_000)
    expect(result.current.resumen?.totales.parkeados).toBe(4)
    // El reparto ya invalida el prefijo compartido: también alcanza la clave por actor.
    consultar.mockResolvedValue(foto(1))
    await act(async () => { await cliente.invalidateQueries({ queryKey: crmQueryKeys.metricasAmbito() }) })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(1)
    consultar.mockResolvedValue(foto(0))
    await act(async () => { await cliente.invalidateQueries({ queryKey: crmQueryKeys.metricasAmbito() }) })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(0)
  })

  it('retira una cifra en caché al fallar el refresco y permite recuperarla', async () => {
    const consultar = vi.spyOn(api, 'listarResumenCartera').mockResolvedValue(foto(9))
    const { result } = renderHook(() => useResumenCarteraOperativo(leads, actividades, true, true), { wrapper })
    await pasar(1)
    consultar.mockRejectedValue(new Error('No disponible'))
    await pasar(60_000)
    expect(result.current.resumen).toBeNull()
    expect(result.current.error).toBeTruthy()
    consultar.mockResolvedValue(foto(2))
    await act(async () => { await result.current.recargar() })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(2)
    expect(result.current.error).toBeNull()
  })

  it('separa supervisores incluso si la consulta anterior resuelve más tarde', async () => {
    let terminar!: (r: ReturnType<typeof foto>) => void
    const consultar = vi.spyOn(api, 'listarResumenCartera').mockImplementationOnce(() => new Promise(resolve => { terminar = resolve }))
      .mockResolvedValue(foto(3))
    const { result, rerender } = renderHook(() => useResumenCarteraOperativo(leads, actividades, true, true), { wrapper })
    await pasar(1)
    actor = { ...actor, id: 's2' }; rerender()
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(3)
    await act(async () => { terminar(foto(999)) })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(3)
    expect(consultar).toHaveBeenCalledTimes(2)
  })

  it('no sondea en segundo plano y revalida al recuperar el foco', async () => {
    const consultar = vi.spyOn(api, 'listarResumenCartera').mockResolvedValue(foto(0))
    const { result } = renderHook(() => useResumenCarteraOperativo(leads, actividades, true, true), { wrapper })
    await pasar(1)
    focusManager.setFocused(false)
    consultar.mockResolvedValue(foto(5))
    await pasar(120_000)
    expect(consultar).toHaveBeenCalledTimes(1)
    await act(async () => { focusManager.setFocused(true) })
    await pasar(1)
    expect(result.current.resumen?.totales.parkeados).toBe(5)
  })

  it('la demo y el modo deshabilitado nunca consultan ni siquiera al reintentar', async () => {
    const consultar = vi.spyOn(api, 'listarResumenCartera')
    actor = { ...actor, demo: true }
    const { result, rerender } = renderHook(({ habilitado }) => useResumenCarteraOperativo(leads, actividades, habilitado, true), {
      wrapper, initialProps: { habilitado: true },
    })
    await act(async () => { await result.current.recargar() })
    await pasar(120_000)
    expect(result.current.resumen?.totales.parkeados).toBe(0)
    actor = { ...actor, demo: false }; rerender({ habilitado: false })
    await act(async () => { await result.current.recargar() })
    expect(result.current.resumen).toBeNull()
    expect(consultar).not.toHaveBeenCalled()
  })
})
