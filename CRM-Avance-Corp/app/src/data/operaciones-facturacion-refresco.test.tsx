import { act, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider, focusManager } from '@tanstack/react-query'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'
import type { ReactNode } from 'react'
import type { ListaOperacionesFacturacion, ParametrosOperacionesFacturacion } from './crm-api'
const listar = vi.hoisted(() => vi.fn(async (_p: ParametrosOperacionesFacturacion): Promise<ListaOperacionesFacturacion> => ({ version: 1, pagina: 1, tamano: 25, total: 0, totales: [], filas: [] })))
vi.mock('./crm-api', async (original) => ({ ...(await original<typeof import('./crm-api')>()), listarOperacionesFacturacion: listar }))
const { useListaOperacionesFacturacion } = await import('./crm-queries')
let cliente: QueryClient
const actual = { p_desde: '2026-10-01', p_hasta: '2026-10-31' }
const cerrado = { p_desde: '2026-09-01', p_hasta: '2026-09-30' }
beforeEach(() => {
  listar.mockClear()
  vi.useFakeTimers({ toFake: ['Date', 'setInterval', 'clearInterval'] })
  vi.setSystemTime(new Date('2026-10-09T15:00:00Z'))
  focusManager.setFocused(true)
  cliente = new QueryClient({ defaultOptions: { queries: { retry: false } } })
})
afterEach(() => { cliente.clear(); focusManager.setFocused(undefined); vi.useRealTimers() })
function wrapper({ children }: { children: ReactNode }) { return <QueryClientProvider client={cliente}>{children}</QueryClientProvider> }
const pedidos = (p: ParametrosOperacionesFacturacion) => listar.mock.calls.filter(([args]) => args.p_hasta === p.p_hasta).length
it('lista: vigente cada cinco minutos, cerrado cada treinta y al recuperar foco', async () => {
  const { result } = renderHook(() => [useListaOperacionesFacturacion(true, actual), useListaOperacionesFacturacion(true, cerrado)], { wrapper })
  await vi.waitFor(() => expect(result.current.every((r) => r.isSuccess)).toBe(true))
  await act(async () => { vi.advanceTimersByTime(5 * 60_000) })
  await vi.waitFor(() => expect(pedidos(actual)).toBe(2))
  expect(pedidos(cerrado)).toBe(1)
  await act(async () => { vi.advanceTimersByTime(25 * 60_000) })
  await vi.waitFor(() => expect(pedidos(cerrado)).toBe(2))
  await act(async () => { focusManager.setFocused(false); focusManager.setFocused(true) })
  await vi.waitFor(() => expect(pedidos(cerrado)).toBe(3))
})
it('un desfase detiene sondeo y foco; solo el reintento explícito repide', async () => {
  const { result } = renderHook(() => useListaOperacionesFacturacion(true, cerrado, () => true), { wrapper })
  await vi.waitFor(() => expect(result.current.isSuccess).toBe(true))
  await act(async () => { vi.advanceTimersByTime(31 * 60_000); focusManager.setFocused(false); focusManager.setFocused(true) })
  expect(listar).toHaveBeenCalledTimes(1)
  await act(async () => { await result.current.refetch() })
  expect(listar).toHaveBeenCalledTimes(2)
})
it('la clave separa cada parámetro, incluidos los indicadores sin persona/equipo y la página', async () => {
  const variantes: ParametrosOperacionesFacturacion[] = [actual, ...[
    { p_desde: '2026-10-02' }, { p_hasta: '2026-10-30' }, { p_dias: ['2026-10-05'] }, { p_analistas: ['ana'] },
    { p_sin_analista: true }, { p_equipo: 'sup' }, { p_sin_equipo: true }, { p_tipos: ['cooperativa'] },
    { p_moneda: 'USD' }, { p_pagina: 2 }, { p_tamano: 100 },
  ].map((p) => ({ ...actual, ...p }))]
  const { result, rerender } = renderHook(({ p }) => useListaOperacionesFacturacion(true, p), { wrapper, initialProps: { p: variantes[0]! } })
  for (const [i, p] of variantes.entries()) {
    rerender({ p })
    await vi.waitFor(() => expect(listar).toHaveBeenCalledTimes(i + 1))
    await vi.waitFor(() => expect(result.current.isSuccess).toBe(true))
  }
  expect(cliente.getQueryCache().getAll()).toHaveLength(variantes.length)
})

it('mantiene la página anterior mientras llega la siguiente, sin volver a pendiente', async () => {
  const { result, rerender } = renderHook(({ pagina }) => useListaOperacionesFacturacion(true, { ...actual, p_pagina: pagina }),
    { wrapper, initialProps: { pagina: 1 } })
  await vi.waitFor(() => expect(result.current.isSuccess).toBe(true))
  const anterior = result.current.data
  let resolver!: (datos: NonNullable<typeof anterior>) => void
  listar.mockImplementationOnce(() => new Promise((resolve) => { resolver = resolve }))
  rerender({ pagina: 2 })
  expect(result.current.data).toBe(anterior)
  expect(result.current.isPlaceholderData).toBe(true)
  expect(result.current.isPending).toBe(false)
  await act(async () => { resolver({ ...anterior!, pagina: 2 }) })
  await vi.waitFor(() => expect(result.current.data?.pagina).toBe(2))
  expect(result.current.isPlaceholderData).toBe(false)
})
