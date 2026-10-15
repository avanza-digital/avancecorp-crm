import { act, renderHook } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { useFiltroCampania } from './use-filtro-campania'

beforeEach(() => { sessionStorage.clear(); vi.restoreAllMocks() })

it('conserva la campaña al recargar y separa las selecciones por cuenta y demo', () => {
  const { result, rerender, unmount } = renderHook(({ actor }) => useFiltroCampania(actor), { initialProps: { actor: 'real:uno' } })
  act(() => { result.current[1]('Formulario 3') })
  rerender({ actor: 'real:dos' })
  expect(result.current[0]).toBe('todas')
  rerender({ actor: 'demo:uno' })
  expect(result.current[0]).toBe('todas')
  rerender({ actor: 'real:uno' })
  expect(result.current[0]).toBe('Formulario 3')
  unmount()
  const recarga = renderHook(() => useFiltroCampania('real:uno'))
  expect(recarga.result.current[0]).toBe('Formulario 3')
  act(() => { recarga.result.current[1]('todas') })
  expect(sessionStorage.getItem('crm:cartera:campania:real:uno')).toBe('todas')
})

it('tolera selecciones antiguas y almacenamiento bloqueado', () => {
  sessionStorage.setItem('crm:cartera:campania:real:uno', 'Campaña retirada')
  const { result } = renderHook(() => useFiltroCampania('real:uno'))
  expect(result.current[0]).toBe('todas')
  vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('bloqueado') })
  act(() => { result.current[1]('Formulario 3') })
  expect(result.current[0]).toBe('Formulario 3')
  vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('bloqueado') })
  expect(renderHook(() => useFiltroCampania('real:dos')).result.current[0]).toBe('todas')
})
