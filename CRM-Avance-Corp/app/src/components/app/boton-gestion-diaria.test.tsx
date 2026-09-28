// El botón «GESTIÓN DIARIA» de la cabecera de «Hoy» del analista (pieza CRM-02
// del UI Playground): qué clase pinta cada estado, que el detalle viva en el
// aria-label y no en pantalla, que la barra diga «4 de 9», que el clic
// descuelgue el teléfono y navegue a los 420 ms, que ⌘/Ctrl no se secuestren y
// que sin AudioContext (jsdom) el «pop» no reviente nada.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { BotonGestionDiaria, DURACION_DESCOLGAR_MS, type EstadoGestionDiaria } from './boton-gestion-diaria'

const URGENTE: EstadoGestionDiaria = { vencidas: 2, pendientes: 3, hechas: 4, yaVisitoHoy: false }
const ACTIVO: EstadoGestionDiaria = { vencidas: 0, pendientes: 3, hechas: 9, yaVisitoHoy: false }
const AL_DIA: EstadoGestionDiaria = { vencidas: 0, pendientes: 0, hechas: 12, yaVisitoHoy: true }

function enlace(): HTMLAnchorElement {
  const a = screen.getByRole('link', { name: /^Ir a Gestión diaria\./ })
  if (!(a instanceof HTMLAnchorElement)) throw new Error('el botón no es un enlace')
  return a
}

function raiz(): HTMLElement {
  const r = enlace().closest('.bgd')
  if (!(r instanceof HTMLElement)) throw new Error('sin raíz .bgd')
  return r
}

/** jsdom declara prefers-reduced-motion (setup.ts): aquí se apaga para ver descolgar. */
function conMovimiento(): void {
  vi.stubGlobal(
    'matchMedia',
    vi.fn(() => ({ matches: false, media: '', addEventListener() {}, removeEventListener() {} })),
  )
}

/**
 * AudioContext de mentira: cuenta cuántos contextos se construyen y cuántos
 * «pop» arrancan de verdad. Es una clase real (no un `vi.fn`): `new` exige un
 * constructor auténtico.
 */
function audioFalso() {
  const start = vi.fn()
  let construidos = 0
  let cerrados = 0
  class ContextoFalso {
    state = 'suspended'
    currentTime = 0
    destination = {}
    constructor() {
      construidos += 1
    }
    close() {
      cerrados += 1
      return Promise.resolve()
    }
    resume() {
      return Promise.resolve()
    }
    createOscillator() {
      return {
        type: 'sine',
        frequency: { setValueAtTime() {}, exponentialRampToValueAtTime() {} },
        connect: () => ({ connect() {} }),
        start,
        stop() {},
      }
    }
    createGain() {
      return { gain: { setValueAtTime() {}, exponentialRampToValueAtTime() {} } }
    }
  }
  vi.stubGlobal('AudioContext', ContextoFalso)
  return { start, construidos: () => construidos, cerrados: () => cerrados }
}

beforeEach(() => {
  vi.useFakeTimers()
})

afterEach(() => {
  vi.useRealTimers()
  vi.unstubAllGlobals()
  // Un clic sin preventDefault deja que jsdom siga el href: se limpia.
  window.location.hash = ''
})

describe('BotonGestionDiaria — el detalle para el lector de pantalla', () => {
  it('habla en singular y plural, y «Al día» no inventa gestiones', () => {
    const { rerender } = render(
      <BotonGestionDiaria estado={{ vencidas: 1, pendientes: 1, hechas: 0, yaVisitoHoy: false }} />,
    )
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. 1 vencida, 1 pendiente. 0 de 2 gestiones hechas hoy')
    rerender(<BotonGestionDiaria estado={{ vencidas: 0, pendientes: 0, hechas: 0, yaVisitoHoy: false }} />)
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. Al día. Sin gestiones registradas hoy')
    expect(raiz()).toHaveClass('bgd--aldia')
  })
})

describe('BotonGestionDiaria — estados', () => {
  it('urgente: ámbar en la raíz, teléfono que suena, barra «4 de 9» al 44 % y el detalle solo para el lector', () => {
    const { container } = render(<BotonGestionDiaria estado={URGENTE} />)
    expect(raiz()).toHaveClass('bgd--urgente')
    expect(raiz()).toHaveClass('bgd--rebota')
    expect(raiz()).not.toHaveClass('bgd--calmo')
    expect(raiz()).not.toHaveClass('bgd--descolgado')
    expect(raiz()).toHaveAttribute('data-nivel', 'urgente')
    expect(enlace()).toHaveAttribute('href', '#/gestion-diaria')
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. 2 vencidas, 3 pendientes. 4 de 9 gestiones hechas hoy')
    expect(screen.getByText('GESTIÓN DIARIA')).toBeInTheDocument()
    expect(screen.getByText('4 de 9')).toBeInTheDocument()
    expect(container.querySelector('.bgd__relleno')).toHaveStyle({ width: '44%' })
    expect(container.querySelector('.lucide-phone')).not.toBeNull()
    expect(container.querySelector('.lucide-check')).toBeNull()
    // El detalle NO se escribe en pantalla: solo el rótulo, la cuenta y el icono.
    expect(screen.queryByText(/vencidas/)).toBeNull()
    // Sin haber entrado hoy, insiste: aura y brillo.
    expect(container.querySelector('.bgd__aura')).not.toBeNull()
    expect(container.querySelector('.bgd__brillo')).not.toBeNull()
  })

  it('activo: azul, suena suave y «9 de 12»', () => {
    render(<BotonGestionDiaria estado={ACTIVO} />)
    expect(raiz()).toHaveClass('bgd--activo')
    expect(raiz()).toHaveAttribute('data-nivel', 'activo')
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. 3 pendientes. 9 de 12 gestiones hechas hoy')
    expect(screen.getByText('9 de 12')).toBeInTheDocument()
  })

  it('al día: navy con check, sin barra, sin rebote ni aura, y calmo', () => {
    const { container } = render(<BotonGestionDiaria estado={AL_DIA} />)
    expect(raiz()).toHaveClass('bgd--aldia')
    expect(raiz()).toHaveClass('bgd--calmo')
    expect(raiz()).not.toHaveClass('bgd--rebota')
    expect(container.querySelector('.lucide-check')).not.toBeNull()
    expect(container.querySelector('.lucide-phone')).toBeNull()
    expect(container.querySelector('.bgd__avance')).toBeNull()
    expect(container.querySelector('.bgd__aura')).toBeNull()
    expect(container.querySelector('.bgd__brillo')).toBeNull()
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. Al día. 12 de 12 gestiones hechas hoy')
    expect(screen.getByText('GESTIÓN DIARIA')).toBeInTheDocument()
  })

  it('si ya entró hoy se calma (sin aura ni brillo) pero conserva el color, la barra y el rebote', () => {
    const { container } = render(<BotonGestionDiaria estado={{ ...URGENTE, yaVisitoHoy: true }} />)
    expect(raiz()).toHaveClass('bgd--urgente')
    expect(raiz()).toHaveClass('bgd--calmo')
    expect(raiz()).toHaveClass('bgd--rebota')
    expect(container.querySelector('.bgd__aura')).toBeNull()
    expect(container.querySelector('.bgd__brillo')).toBeNull()
    expect(screen.getByText('4 de 9')).toBeInTheDocument()
  })

  it('sin cifras (cargando o RPC caído): navy sin check ni barra, teléfono quieto, y lo dice al lector', () => {
    const { container } = render(
      <BotonGestionDiaria estado={{ vencidas: 0, pendientes: 0, hechas: 0, yaVisitoHoy: false }} sinCifras />,
    )
    expect(raiz()).toHaveAttribute('data-nivel', 'sin-cifras')
    expect(raiz()).not.toHaveClass('bgd--aldia')
    expect(raiz()).not.toHaveClass('bgd--rebota')
    expect(raiz()).toHaveClass('bgd--calmo')
    expect(container.querySelector('.lucide-phone')).not.toBeNull()
    expect(container.querySelector('.lucide-check')).toBeNull()
    expect(container.querySelector('.bgd__avance')).toBeNull()
    expect(enlace()).toHaveAccessibleName('Ir a Gestión diaria. Sin cifras del día todavía')
  })

  it('los adornos van ocultos al lector y el rótulo visible cabe en el nombre accesible', () => {
    const { container } = render(<BotonGestionDiaria estado={URGENTE} className="extra" />)
    for (const parte of ['.bgd__telefono', '.bgd__flecha', '.bgd__pista', '.bgd__sombra', '.bgd__aura', '.bgd__brillo']) {
      expect(container.querySelector(parte)).toHaveAttribute('aria-hidden', 'true')
    }
    // WCAG 2.5.3 (Label in Name): lo que se lee en pantalla está en el nombre.
    expect(enlace().getAttribute('aria-label')?.toLowerCase()).toContain('gestión diaria')
    expect(raiz()).toHaveClass('extra')
  })
})

describe('BotonGestionDiaria — clic, teclado y sonido', () => {
  it('el clic descuelga el teléfono, no navega por su cuenta y llama a onIr a los 420 ms', () => {
    conMovimiento()
    const onIr = vi.fn()
    render(<BotonGestionDiaria estado={URGENTE} onIr={onIr} />)
    const sigueElNavegador = fireEvent.click(enlace())
    expect(sigueElNavegador).toBe(false) // preventDefault: el hash lo escribe onIr
    expect(raiz()).toHaveClass('bgd--descolgado')
    expect(raiz()).not.toHaveClass('bgd--rebota') // en la mano no rebota
    expect(onIr).not.toHaveBeenCalled()
    // Un segundo clic mientras descuelga no dispara dos viajes.
    fireEvent.click(enlace())
    act(() => {
      vi.advanceTimersByTime(DURACION_DESCOLGAR_MS - 1)
    })
    expect(onIr).not.toHaveBeenCalled()
    act(() => {
      vi.advanceTimersByTime(1)
    })
    expect(onIr).toHaveBeenCalledTimes(1)
    expect(raiz()).not.toHaveClass('bgd--descolgado')
  })

  it('con prefers-reduced-motion no hay nada que esperar: navega al instante', () => {
    const onIr = vi.fn()
    render(<BotonGestionDiaria estado={URGENTE} onIr={onIr} />)
    expect(fireEvent.click(enlace())).toBe(false)
    expect(onIr).toHaveBeenCalledTimes(1)
    expect(raiz()).not.toHaveClass('bgd--descolgado')
  })

  it('con ⌘/Ctrl deja que el navegador abra el enlace (pestaña nueva) y no viaja por su cuenta', () => {
    conMovimiento()
    const onIr = vi.fn()
    render(<BotonGestionDiaria estado={URGENTE} onIr={onIr} />)
    expect(fireEvent.click(enlace(), { metaKey: true })).toBe(true)
    expect(fireEvent.click(enlace(), { ctrlKey: true })).toBe(true)
    act(() => {
      vi.advanceTimersByTime(DURACION_DESCOLGAR_MS)
    })
    expect(onIr).not.toHaveBeenCalled()
    expect(raiz()).not.toHaveClass('bgd--descolgado')
  })

  it('sin onIr es un enlace normal: el navegador sigue el href', () => {
    render(<BotonGestionDiaria estado={URGENTE} />)
    expect(fireEvent.click(enlace())).toBe(true)
  })

  it('si la pantalla cambia antes de los 420 ms, el aviso muere con el botón', () => {
    conMovimiento()
    const onIr = vi.fn()
    const { unmount } = render(<BotonGestionDiaria estado={URGENTE} onIr={onIr} />)
    fireEvent.click(enlace())
    unmount()
    act(() => {
      vi.advanceTimersByTime(DURACION_DESCOLGAR_MS)
    })
    expect(onIr).not.toHaveBeenCalled()
  })

  it('sin AudioContext (jsdom) pasar el cursor o enfocar no lanza', () => {
    expect(typeof AudioContext).toBe('undefined')
    render(<BotonGestionDiaria estado={URGENTE} />)
    expect(() => {
      fireEvent.mouseEnter(enlace())
      fireEvent.focus(enlace())
      fireEvent.mouseEnter(enlace())
    }).not.toThrow()
  })

  it('con AudioContext suena un «pop» al pasar el cursor o enfocar, y no más de uno cada 350 ms', () => {
    const { start, construidos } = audioFalso()
    vi.spyOn(performance, 'now').mockReturnValueOnce(1000).mockReturnValueOnce(1100).mockReturnValueOnce(1400)
    render(<BotonGestionDiaria estado={URGENTE} />)
    fireEvent.mouseEnter(enlace()) // 1000 → suena
    fireEvent.focus(enlace()) // 1100 → dentro de la pausa
    fireEvent.mouseEnter(enlace()) // 1400 → suena
    expect(construidos()).toBe(1) // un solo contexto, reutilizado
    expect(start).toHaveBeenCalledTimes(2)
  })

  it('con el sonido apagado ni siquiera crea el AudioContext', () => {
    const { construidos } = audioFalso()
    render(<BotonGestionDiaria estado={URGENTE} sonido={false} />)
    fireEvent.mouseEnter(enlace())
    expect(construidos()).toBe(0)
  })

  it('un AudioContext que revienta no rompe el botón', () => {
    class Revienta {
      constructor() {
        throw new Error('sin audio')
      }
    }
    vi.stubGlobal('AudioContext', Revienta)
    render(<BotonGestionDiaria estado={URGENTE} />)
    expect(() => fireEvent.mouseEnter(enlace())).not.toThrow()
  })

  it('al desmontar libera el AudioContext (el navegador limita cuántos puede haber vivos)', () => {
    const { construidos, cerrados } = audioFalso()
    const { unmount } = render(<BotonGestionDiaria estado={URGENTE} />)
    fireEvent.mouseEnter(enlace())
    expect(construidos()).toBe(1)
    unmount()
    expect(cerrados()).toBe(1)
  })
})
