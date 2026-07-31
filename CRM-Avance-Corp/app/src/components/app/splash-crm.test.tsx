import { afterEach, describe, expect, it, vi } from 'vitest'
import { act, render, screen, waitFor } from '@testing-library/react'
import gsap from 'gsap'
import { StrictMode } from 'react'
import { calcularViajeSplash } from './splash-crm-motion'
import { SplashCrm } from './splash-crm'

function simularPreferenciaMovimiento(reducidoInicial: boolean) {
  let reducido = reducidoInicial
  const oyentes = new Set<(evento: MediaQueryListEvent) => void>()
  const consulta = {
    get matches() {
      return reducido
    },
    media: '(prefers-reduced-motion: reduce)',
    onchange: null,
    addEventListener: vi.fn(
      (_tipo: string, oyente: (evento: MediaQueryListEvent) => void) => {
        oyentes.add(oyente)
      },
    ),
    removeEventListener: vi.fn(
      (_tipo: string, oyente: (evento: MediaQueryListEvent) => void) => {
        oyentes.delete(oyente)
      },
    ),
    addListener: vi.fn((oyente: (evento: MediaQueryListEvent) => void) => {
      oyentes.add(oyente)
    }),
    removeListener: vi.fn((oyente: (evento: MediaQueryListEvent) => void) => {
      oyentes.delete(oyente)
    }),
    dispatchEvent: vi.fn(),
  } as unknown as MediaQueryList

  vi.stubGlobal('matchMedia', vi.fn(() => consulta))

  return {
    cambiar(siguiente: boolean) {
      reducido = siguiente
      const evento = { matches: reducido, media: consulta.media } as MediaQueryListEvent
      for (const oyente of [...oyentes]) oyente(evento)
    },
    cantidadOyentes() {
      return oyentes.size
    },
  }
}

describe('SplashCrm', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('refleja las fases reales y termina sin movimiento cuando el usuario lo prefiere', () => {
    simularPreferenciaMovimiento(true)
    const finalizar = vi.fn()
    const { container, rerender } = render(
      <SplashCrm fase="acceso" onFinalizar={finalizar} />,
    )

    expect(screen.getByRole('status')).toHaveTextContent('Verificando tu acceso…')
    // Un ancestro aria-busy permitiría a los AT retener los anuncios de la
    // live region: el contenedor no debe declararlo nunca.
    expect(container.querySelector('.ac-splash')).not.toHaveAttribute('aria-busy')
    expect(container.querySelector('img')).toHaveAttribute('alt', '')

    rerender(<SplashCrm fase="datos" onFinalizar={finalizar} />)
    expect(screen.getByRole('status')).toHaveTextContent(
      'Preparando tu espacio de trabajo…',
    )
    expect(finalizar).not.toHaveBeenCalled()

    rerender(<SplashCrm fase="listo" onFinalizar={finalizar} />)
    expect(container.querySelector('[role="status"]')).toHaveTextContent(
      'Tu espacio está listo',
    )
    expect(finalizar).toHaveBeenCalledTimes(1)
  })

  it('finaliza exactamente una vez al montar listo con movimiento reducido bajo StrictMode', () => {
    const media = simularPreferenciaMovimiento(true)
    const finalizar = vi.fn()
    const { unmount } = render(
      <StrictMode>
        <SplashCrm fase="listo" onFinalizar={finalizar} />
      </StrictMode>,
    )

    expect(finalizar).toHaveBeenCalledTimes(1)

    unmount()
    expect(media.cantidadOyentes()).toBe(0)
  })

  it('pausa el ambiente, respeta cambios dinámicos de movimiento y limpia sus tweens', async () => {
    const media = simularPreferenciaMovimiento(false)
    const finalizar = vi.fn()
    const vista = (fase: 'datos' | 'listo') => (
      <StrictMode>
        <SplashCrm fase={fase} onFinalizar={finalizar} />
      </StrictMode>
    )
    const { container, rerender, unmount } = render(vista('datos'))
    const aurora = container.querySelector('.ac-splash__aurora--uno')
    const raiz = container.querySelector('.ac-splash')
    expect(aurora).not.toBeNull()
    expect(raiz).not.toBeNull()
    expect(gsap.getTweensOf(aurora).length).toBeGreaterThan(0)

    rerender(vista('listo'))
    const tweensPausados = gsap
      .getTweensOf(aurora)
      .some((tween) => tween.parent?.paused())
    expect(tweensPausados).toBe(true)
    expect(finalizar).not.toHaveBeenCalled()

    act(() => media.cambiar(true))
    expect(finalizar).toHaveBeenCalledTimes(1)

    act(() => media.cambiar(false))
    expect(raiz).not.toHaveStyle({ visibility: 'hidden' })
    await waitFor(
      () => expect(raiz).toHaveStyle({ visibility: 'hidden' }),
      { timeout: 2_000 },
    )
    expect(finalizar).toHaveBeenCalledTimes(1)

    unmount()
    expect(gsap.getTweensOf(aurora)).toHaveLength(0)
    expect(media.cantidadOyentes()).toBe(0)
  })

  it('la salida real (sin movimiento reducido) notifica onFinalizar exactamente una vez', async () => {
    simularPreferenciaMovimiento(false)
    const finalizar = vi.fn()
    const vista = (fase: 'datos' | 'listo') => (
      <StrictMode>
        <SplashCrm fase={fase} onFinalizar={finalizar} />
      </StrictMode>
    )
    const { rerender } = render(vista('datos'))

    rerender(vista('listo'))
    expect(finalizar).not.toHaveBeenCalled()

    // Para el usuario SIN movimiento reducido (la mayoría) el único aviso de
    // que la salida terminó es el onComplete de la timeline: si ese cableado
    // se rompe, este waitFor caduca y el test cae. La aserción del test del
    // ambiente no lo cubre — allí la llamada contada sale de la rama reducida.
    await waitFor(() => expect(finalizar).toHaveBeenCalledTimes(1), { timeout: 3_000 })
    await new Promise((resolve) => setTimeout(resolve, 60))
    expect(finalizar).toHaveBeenCalledTimes(1)
  })

  it('reintentar durante la salida restaura la splash y permite finalizar de nuevo', () => {
    simularPreferenciaMovimiento(true)
    const finalizar = vi.fn()
    const { container, rerender } = render(
      <SplashCrm fase="datos" onFinalizar={finalizar} />,
    )

    rerender(<SplashCrm fase="listo" onFinalizar={finalizar} />)
    expect(finalizar).toHaveBeenCalledTimes(1)

    // Reintento mientras la salida estaba activa: la splash debe volver entera
    // (ni invisible ni a medio desvanecer) y el cierre debe poder repetirse.
    rerender(<SplashCrm fase="datos" onFinalizar={finalizar} />)
    const raiz = container.querySelector('.ac-splash')
    expect(screen.getByRole('status')).toHaveTextContent(
      'Preparando tu espacio de trabajo…',
    )
    expect(raiz).not.toHaveStyle({ visibility: 'hidden' })
    expect(raiz).not.toHaveStyle({ opacity: '0' })

    rerender(<SplashCrm fase="listo" onFinalizar={finalizar} />)
    expect(finalizar).toHaveBeenCalledTimes(2)
  })

  it('no inventa un viaje cuando el logo lateral está oculto', () => {
    const origen = { left: 450, top: 360, width: 100, height: 100 }
    const marcadorOculto = { left: 13, top: 13, width: 38, height: 38 }

    expect(calcularViajeSplash(origen, marcadorOculto, false)).toBeNull()
    expect(calcularViajeSplash(origen, undefined, true)).toBeNull()
  })

  it('calcula el encaje exacto cuando el logo lateral sí está visible', () => {
    expect(
      calcularViajeSplash(
        { left: 450, top: 360, width: 100, height: 100 },
        { left: 16, top: 13, width: 38, height: 38 },
        true,
      ),
    ).toEqual({ x: -465, y: -378, scale: 0.38 })
  })
})
