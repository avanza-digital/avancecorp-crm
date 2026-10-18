import { act, renderHook } from '@testing-library/react'
import { beforeEach, expect, it, vi } from 'vitest'
import { useFiltroOrigen } from './use-filtro-origen'
import { origenDeFila } from './tipos'

beforeEach(() => { sessionStorage.clear(); vi.restoreAllMocks() })

it('migra la preferencia de campaña una vez y conserva cuentas y demos aislados', () => {
  sessionStorage.setItem('crm:cartera:campania:real:uno', 'Formulario 3')
  const { result, rerender, unmount } = renderHook(({ actor }) => useFiltroOrigen(actor), { initialProps: { actor: 'real:uno' } })
  expect(result.current[0]).toBe('formulario_3')
  act(() => result.current[1]('todos'))
  rerender({ actor: 'real:dos' })
  expect(result.current[0]).toBe('todos')
  act(() => result.current[1]('landing'))
  rerender({ actor: 'demo:dos' })
  expect(result.current[0]).toBe('todos')
  unmount()
  expect(renderHook(() => useFiltroOrigen('real:uno')).result.current[0]).toBe('todos')
  expect(renderHook(() => useFiltroOrigen('real:dos')).result.current[0]).toBe('landing')
})

it('admite almacenamiento bloqueado y valores de origen inválidos', () => {
  sessionStorage.setItem('crm:cartera:origen:uno', 'retirado')
  expect(renderHook(() => useFiltroOrigen('uno')).result.current[0]).toBe('todos')
  vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('bloqueado') })
  vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('bloqueado') })
  const { result } = renderHook(() => useFiltroOrigen('dos'))
  act(() => result.current[1]('formulario_3'))
  expect(result.current[0]).toBe('formulario_3')
})

it('reconoce F3 legado y canónico sin inferir otras campañas ni orígenes', () => {
  expect(origenDeFila('formulario', 'Formulario 3')).toBe('formulario_3')
  expect(origenDeFila('formulario_3', null)).toBe('formulario_3')
  expect(origenDeFila('formulario', 'Otra')).toBe('formulario')
  expect(origenDeFila('landing', 'Formulario 3')).toBe('landing')
})
