import { act, renderHook } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { useViewportMovil } from './use-viewport-movil'

afterEach(() => vi.unstubAllGlobals())
it('libera espacio al teclado, no confunde zoom con teclado y limpia los listeners y altura al salir', () => {
  const viewport = Object.assign(new EventTarget(), { height: 500, scale: 1 })
  vi.stubGlobal('visualViewport', viewport)
  vi.stubGlobal('innerHeight', 844)
  const campo = document.createElement('input'); document.body.append(campo); campo.focus()
  const { result, unmount } = renderHook(() => useViewportMovil(true))
  expect(result.current).toBe(true)
  expect(document.documentElement.style.getPropertyValue('--crm-viewport-alto')).toBe('500px')
  act(() => { viewport.scale = 2; viewport.dispatchEvent(new Event('resize')) })
  expect(result.current).toBe(false)
  expect(document.documentElement.style.getPropertyValue('--crm-viewport-alto')).toBe('')
  act(() => { viewport.scale = 1; viewport.height = 844; viewport.dispatchEvent(new Event('resize')) })
  expect(result.current).toBe(false)
  unmount(); campo.remove()
  expect(document.documentElement.style.getPropertyValue('--crm-viewport-alto')).toBe('')
})
