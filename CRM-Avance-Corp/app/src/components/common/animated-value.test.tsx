import { act, cleanup, render } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// La suite general reduce movimiento. Aquí se prueba expresamente la ruta
// animada, incluida la marca temporal anterior al inicio que produce el RAF.
vi.hoisted(() => {
  vi.stubGlobal('matchMedia', vi.fn(() => ({ matches: false })))
})

import { AnimatedValue } from './animated-value'

let fotogramas: Map<number, FrameRequestCallback>
let siguienteId: number

beforeEach(() => {
  fotogramas = new Map()
  siguienteId = 0 // cero es un identificador de RAF válido, también se cancela
  vi.stubGlobal('requestAnimationFrame', vi.fn((callback: FrameRequestCallback) => {
    const id = siguienteId++
    fotogramas.set(id, callback)
    return id
  }))
  vi.stubGlobal('cancelAnimationFrame', vi.fn((id: number) => { fotogramas.delete(id) }))
  vi.spyOn(performance, 'now').mockReturnValue(100)
  vi.spyOn(window, 'matchMedia').mockReturnValue({ matches: false } as MediaQueryList)
})

afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

function avanzarFotograma(now: number) {
  const pendientes = [...fotogramas.values()]
  fotogramas.clear()
  act(() => { pendientes.forEach(callback => callback(now)) })
}

describe('AnimatedValue — el adorno no cambia el signo ni conserva otro indicador', () => {
  it('un RAF anterior a performance.now no convierte capital positivo en negativo', () => {
    const { container } = render(<AnimatedValue value="S/ 19,485.4k" />)
    expect(fotogramas.size).toBe(1)
    avanzarFotograma(95)
    expect(container.textContent).not.toMatch(/-/)
    for (const instante of [100, 250, 500, 800]) {
      avanzarFotograma(instante)
      const mostrado = Number(container.textContent?.replace(/[^\d.-]/g, ''))
      expect(mostrado).toBeGreaterThanOrEqual(0)
      expect(mostrado).toBeLessThanOrEqual(19485.4)
    }
    expect(container.textContent).toBe('S/ 19,485.4k')
    expect(fotogramas.size).toBe(0)
  })

  it('conserva un negativo real, sin convertirlo en positivo durante la transición', () => {
    const { container } = render(<AnimatedValue value="-150.00%" />)
    avanzarFotograma(95)
    expect(Number(container.textContent?.replace('%', ''))).toBeLessThanOrEqual(0)
    avanzarFotograma(800)
    expect(container.textContent).toBe('-150.00%')
  })

  it('entrega al final el texto original, sin reformatear el contrato recibido', () => {
    const { container } = render(<AnimatedValue value="S/ 001.00" />)
    avanzarFotograma(100)
    avanzarFotograma(900)
    expect(container.textContent).toBe('S/ 001.00')
  })

  it('cancela también el RAF con id cero al cambiar de indicador o desmontar', () => {
    const { rerender, unmount } = render(<AnimatedValue value="S/ 471.1k" />)
    expect(fotogramas.has(0)).toBe(true)
    rerender(<AnimatedValue value="US$ 14k" />)
    expect(cancelAnimationFrame).toHaveBeenCalledWith(0)
    expect(fotogramas.has(0)).toBe(false)
    expect(fotogramas.size).toBe(1)
    unmount()
    expect(fotogramas.size).toBe(0)
  })

  it('no muestra el importe del filtro anterior mientras espera el primer RAF nuevo', () => {
    const { container, rerender } = render(<AnimatedValue value="S/ 471.1k" />)
    avanzarFotograma(100)
    avanzarFotograma(900)
    rerender(<AnimatedValue value="US$ 14k" />)
    expect(container.textContent).toBe('US$ 14k')
    avanzarFotograma(1000)
    rerender(<AnimatedValue value="—" />)
    expect(container.textContent).toBe('—')
    expect(fotogramas.size).toBe(0)
  })

  it.each([0, -1, NaN, Infinity])('duración %s: muestra el dato sin iniciar un bucle inválido', duration => {
    const { container } = render(<AnimatedValue value="S/ 777k" duration={duration} />)
    expect(container.textContent).toBe('S/ 777k')
    expect(fotogramas.size).toBe(0)
  })

  it('respeta reducir movimiento al montar y no inventa una transición', () => {
    vi.spyOn(window, 'matchMedia').mockReturnValue({ matches: true } as MediaQueryList)
    const { container } = render(<AnimatedValue value="150%" />)
    expect(container.textContent).toBe('150%')
    expect(fotogramas.size).toBe(0)
  })

  it('un valor no numérico se conserva íntegro', () => {
    const { container } = render(<AnimatedValue value="Sin verificar" />)
    expect(container.textContent).toBe('Sin verificar')
    expect(fotogramas.size).toBe(0)
  })
})
