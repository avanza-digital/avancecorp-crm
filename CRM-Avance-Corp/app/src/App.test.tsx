// Tests del ARRANQUE (App): las dos pantallas que ve el asesor antes de entrar
// al CRM — el splash con fecha de caducidad y el Login — y las dos regresiones
// que introdujo la pasada de arreglos de sesión del 2026-07-25:
//   1. volver a la pestaña con la app en `error` borraba lo ya tecleado, y
//   2. el reloj del splash no se reiniciaba entre la etapa de ACCESO y la de
//      DATOS, así que una carga lenta pero sana se declaraba atascada.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { StrictMode, useEffect, useState, type ReactNode } from 'react'
import { createActor } from 'xstate'
import App, {
  EntradaCrm,
  LIMITE_SPLASH_MS,
  MINIMO_SPLASH_VISIBLE_MS,
} from './App'
import { AuthContext, type AuthContextValue } from './lib/auth-context'
import { StoreEstadoContext } from './lib/store-context'
import { LIMITE_CARGA_REAL_MS, type StoreEstado } from './lib/store'
import {
  authMaquina,
  faseDe,
  ERROR_SESION,
  LIMITE_VERIFICACION_MS,
  type EstadoAuth,
  type ResultadoVerificacion,
  type Verificar,
} from './lib/auth-maquina'
import type { Yo } from './lib/tipos'

const controlSplash = vi.hoisted(() => ({
  onFinalizar: undefined as (() => void) | undefined,
}))

vi.mock('./components/app/splash-crm', () => ({
  SplashCrm: ({
    fase,
    onFinalizar,
  }: {
    fase: 'acceso' | 'datos' | 'listo'
    onFinalizar?: () => void
  }) => {
    controlSplash.onFinalizar = onFinalizar
    const mensajes = {
      acceso: 'Verificando tu acceso…',
      datos: 'Preparando tu espacio de trabajo…',
      listo: 'Tu espacio está listo',
    }
    return (
      <div className="ac-splash" data-fase={fase}>
        <div role="status">{mensajes[fase]}</div>
        {fase === 'listo' && onFinalizar && (
          <button type="button" onClick={onFinalizar}>
            Finalizar splash
          </button>
        )}
      </div>
    )
  },
}))

const TEXTO_SPLASH_ACCESO = 'Verificando tu acceso…'
const TEXTO_SPLASH_DATOS = 'Preparando tu espacio de trabajo…'
const TEXTO_ATASCADO = 'Esto está tardando demasiado'

const YO: Yo = {
  id: 'u-ana',
  nombre_completo: 'ANA',
  rol: 'vendedor',
  demo: false,
  puede_contratar: true,
}

const AUTH_BASE: AuthContextValue = {
  fase: 'init',
  yo: null,
  error: null,
  entrar: async () => ({ ok: true }),
  entrarDemo: () => {},
  reintentar: () => {},
  salir: async () => {},
}

const DATOS_BASE: StoreEstado = { cargando: false, error: false, reintentar: () => {} }

function pantalla(auth: Partial<AuthContextValue> = {}, datos: Partial<StoreEstado> = {}) {
  return (
    <AuthContext.Provider value={{ ...AUTH_BASE, ...auth }}>
      <StoreEstadoContext.Provider value={{ ...DATOS_BASE, ...datos }}>
        <App />
      </StoreEstadoContext.Provider>
    </AuthContext.Provider>
  )
}

// ACCESO y DATOS comparten deliberadamente el mismo nodo para que el logo no se
// reinicie. La caducidad se asocia a `fase`, así que la continuidad visual no
// mezcla sus dos presupuestos de carga.
describe('App — el reloj del splash es POR ETAPA, no del arranque entero', () => {
  beforeEach(() => {
    vi.useFakeTimers()
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('una carga lenta pero SANA (acceso + datos encadenados) nunca se declara atascada', () => {
    // El escenario solo tiene sentido si los dos presupuestos juntos se pasan
    // del tope del splash — que es justo el caso real (12 s + 20 s > 25 s).
    expect(LIMITE_VERIFICACION_MS + LIMITE_CARGA_REAL_MS).toBeGreaterThan(LIMITE_SPLASH_MS)

    const { container, rerender } = render(pantalla({ fase: 'init' }))
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_ACCESO)
    const splashInicial = container.querySelector('.ac-splash')

    // Etapa 1: la verificación de acceso consume casi todo SU presupuesto…
    act(() => vi.advanceTimersByTime(LIMITE_VERIFICACION_MS - 1))
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_ACCESO)

    // …resuelve, y arranca la carga de datos: otra etapa, otro splash.
    rerender(pantalla({ fase: 'listo', yo: YO }, { cargando: true }))
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_DATOS)
    expect(container.querySelector('.ac-splash')).toBe(splashInicial)

    // Etapa 2: casi todo su presupuesto también. Ninguna de las dos agotó el
    // suyo, así que esto es LENTITUD, no un cuelgue: el asesor sigue viendo el
    // splash y nadie aborta un fetch que va camino de responder.
    act(() => vi.advanceTimersByTime(LIMITE_CARGA_REAL_MS - 1))
    expect(screen.queryByText(TEXTO_ATASCADO)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_DATOS)
  })

  it('pero un splash de DATOS genuinamente colgado sí caduca y ofrece salida', () => {
    const reintentar = vi.fn()
    render(pantalla({ fase: 'listo', yo: YO }, { cargando: true, reintentar }))

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()

    // La salida es accionable de verdad: pide los datos otra vez y vuelve al
    // splash (si se cuelga otra vez, el reloj lo detecta de nuevo).
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(reintentar).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_DATOS)

    // Y si el reintento TAMBIÉN se cuelga, el reloj re-armado por el clic lo
    // vuelve a cazar: sin esto, un servidor caído dejaría el splash eterno.
    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()
  })

  it('y un splash de ACCESO colgado también caduca (su salida re-verifica la sesión)', () => {
    const reintentar = vi.fn()
    render(pantalla({ fase: 'init', reintentar }))

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(reintentar).toHaveBeenCalledTimes(1)
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_ACCESO)
  })
})

function entrada(
  faseCarga: 'acceso' | 'datos' | null,
  { estricto = false, reintentar = vi.fn() } = {},
) {
  const contenido = (
    <AuthContext.Provider value={{ ...AUTH_BASE, fase: 'listo', yo: YO }}>
      <EntradaCrm faseCarga={faseCarga} onReintentar={reintentar}>
        <main data-testid="workspace" tabIndex={-1}>CRM listo</main>
      </EntradaCrm>
    </AuthContext.Provider>
  )
  return estricto ? <StrictMode>{contenido}</StrictMode> : contenido
}

describe('EntradaCrm — ciclo visual, mínimo e inert', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    controlSplash.onFinalizar = undefined
  })
  afterEach(() => {
    vi.useRealTimers()
  })

  it('respeta el mínimo monotónico y libera inert al terminar la salida', () => {
    const { container, rerender } = render(entrada('datos'))

    act(() => vi.advanceTimersByTime(500))
    rerender(entrada(null))

    const workspace = screen.getByTestId('workspace')
    const envoltura = workspace.parentElement
    expect(envoltura).toHaveAttribute('inert')
    expect(envoltura).toHaveAttribute('aria-hidden', 'true')
    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'datos')

    act(() => vi.advanceTimersByTime(MINIMO_SPLASH_VISIBLE_MS - 501))
    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'datos')

    act(() => vi.advanceTimersByTime(1))
    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'listo')

    fireEvent.click(screen.getByRole('button', { name: 'Finalizar splash' }))
    expect(container.querySelector('.ac-splash')).not.toBeInTheDocument()
    expect(envoltura).not.toHaveAttribute('inert')
    expect(envoltura).not.toHaveAttribute('aria-hidden')
    expect(workspace).toHaveFocus()
  })

  it('no roba el foco si ya existe un destino válido al terminar', () => {
    const { rerender } = render(
      <>
        <button type="button">Acción persistente</button>
        {entrada('datos')}
      </>,
    )
    act(() => vi.advanceTimersByTime(MINIMO_SPLASH_VISIBLE_MS))
    rerender(
      <>
        <button type="button">Acción persistente</button>
        {entrada(null)}
      </>,
    )
    act(() => vi.advanceTimersByTime(0))

    const accionPersistente = screen.getByRole('button', { name: 'Acción persistente' })
    accionPersistente.focus()
    expect(accionPersistente).toHaveFocus()

    act(() => controlSplash.onFinalizar?.())
    expect(accionPersistente).toHaveFocus()
    expect(screen.getByTestId('workspace')).not.toHaveFocus()
  })

  it('no reutiliza un timeout obsoleto al volver de datos → listo → datos', () => {
    const { container, rerender } = render(entrada('datos'))

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()

    rerender(entrada(null))
    act(() => vi.advanceTimersByTime(0))
    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'listo')

    rerender(entrada('datos'))
    expect(screen.queryByText(TEXTO_ATASCADO)).not.toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(TEXTO_SPLASH_DATOS)

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS - 1))
    expect(screen.queryByText(TEXTO_ATASCADO)).not.toBeInTheDocument()
    act(() => vi.advanceTimersByTime(1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()
  })

  it('el salvavidas libera el CRM si la salida nunca notifica su fin', () => {
    const { container, rerender } = render(entrada('datos'))
    act(() => vi.advanceTimersByTime(MINIMO_SPLASH_VISIBLE_MS))
    rerender(entrada(null))
    act(() => vi.advanceTimersByTime(0))
    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'listo')

    // Nadie llama onFinalizar (p. ej. pestaña en segundo plano: el navegador
    // congela el rAF y la timeline no avanza). El workspace no puede quedarse
    // inert para siempre: a los 2 s el salvavidas retira la capa él solo.
    act(() => vi.advanceTimersByTime(1_999))
    expect(container.querySelector('.ac-splash')).toBeInTheDocument()
    expect(screen.getByTestId('workspace').parentElement).toHaveAttribute('inert')

    act(() => vi.advanceTimersByTime(1))
    expect(container.querySelector('.ac-splash')).not.toBeInTheDocument()
    expect(screen.getByTestId('workspace').parentElement).not.toHaveAttribute('inert')
    expect(screen.getByTestId('workspace').parentElement).not.toHaveAttribute('aria-hidden')
  })

  it('ignora el callback de una salida anterior si una carga reentra', () => {
    const { container, rerender } = render(entrada('datos'))
    act(() => vi.advanceTimersByTime(MINIMO_SPLASH_VISIBLE_MS))
    rerender(entrada(null))
    act(() => vi.advanceTimersByTime(0))

    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'listo')
    const finalizarSalidaAnterior = controlSplash.onFinalizar
    expect(finalizarSalidaAnterior).toBeTypeOf('function')

    rerender(entrada('datos'))
    act(() => finalizarSalidaAnterior?.())

    expect(container.querySelector('.ac-splash')).toHaveAttribute('data-fase', 'datos')
    expect(screen.queryByTestId('workspace')).not.toBeInTheDocument()
  })

  it('mantiene un solo splash y timers limpios bajo StrictMode', () => {
    const { container, rerender } = render(entrada('acceso', { estricto: true }))
    const splashInicial = container.querySelector('.ac-splash')

    rerender(entrada('datos', { estricto: true }))
    expect(container.querySelectorAll('.ac-splash')).toHaveLength(1)
    expect(container.querySelector('.ac-splash')).toBe(splashInicial)

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS - 1))
    expect(screen.queryByText(TEXTO_ATASCADO)).not.toBeInTheDocument()
    act(() => vi.advanceTimersByTime(1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()
  })
})

/** Promesa controlable desde el test (una verificación que no responde). */
function diferida<T>() {
  let resolver!: (v: T) => void
  const promesa = new Promise<T>((res) => {
    resolver = res
  })
  return { promesa, resolver }
}

/** Mini-AuthProvider: cablea la MÁQUINA real al contexto, como hace auth.tsx. */
function AuthDeMaquina({
  actor,
  children,
}: {
  actor: ReturnType<typeof createActor<typeof authMaquina>>
  children: ReactNode
}) {
  const [snapshot, setSnapshot] = useState(() => actor.getSnapshot())
  useEffect(() => {
    const suscripcion = actor.subscribe(setSnapshot)
    return () => suscripcion.unsubscribe()
  }, [actor])
  const valor: AuthContextValue = {
    ...AUTH_BASE,
    fase: faseDe(snapshot.value as EstadoAuth, snapshot.context),
    yo: snapshot.context.yo,
    error: snapshot.context.error,
    reintentar: () => actor.send({ type: 'REINTENTAR' }),
  }
  return <AuthContext.Provider value={valor}>{children}</AuthContext.Provider>
}

// Con la app en `error` la pantalla montada es el LOGIN. El REVALIDAR del
// focus/visibilitychange llega SOLO (nadie lo pidió), así que no puede tirar el
// formulario que el asesor está llenando.
describe('App — volver a la pestaña con la app en error no borra lo tecleado', () => {
  it('el correo y la clave sobreviven a la re-verificación silenciosa', async () => {
    const colgada = diferida<ResultadoVerificacion>()
    const verificar = vi
      .fn<Verificar>()
      .mockRejectedValueOnce(new Error(ERROR_SESION)) // arranque: no se pudo verificar
      .mockImplementationOnce(() => colgada.promesa) // la re-verificación tarda
    const actor = createActor(authMaquina, { input: { verificar, alLimpiar: vi.fn() } })
    actor.start()
    await new Promise((res) => setTimeout(res, 0))
    expect(actor.getSnapshot().value).toBe('error')

    render(
      <AuthDeMaquina actor={actor}>
        {/* Datos "cargando" para que el final feliz pare en el splash y no
            exija el StoreProvider entero: aquí se mide el Login, no el CRM. */}
        <StoreEstadoContext.Provider value={{ ...DATOS_BASE, cargando: true }}>
          <App />
        </StoreEstadoContext.Provider>
      </AuthDeMaquina>,
    )

    const correo = screen.getByLabelText('Correo')
    const clave = screen.getByLabelText('Contraseña')
    fireEvent.change(correo, { target: { value: 'ana@avancecorp.pe' } })
    fireEvent.change(clave, { target: { value: 'clave-a-medio-teclear' } })

    // El asesor vuelve a la pestaña → el wrapper manda REVALIDAR.
    act(() => {
      actor.send({ type: 'REVALIDAR' })
    })

    // Se está re-preguntando… en silencio: el formulario NI SE ENTERA.
    expect(actor.getSnapshot().value).toBe('revalidando_error')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Correo')).toHaveValue('ana@avancecorp.pe')
    expect(screen.getByLabelText('Contraseña')).toHaveValue('clave-a-medio-teclear')

    // Y sigue habiendo salida del error: si el servidor ya volvió, entra solo.
    await act(async () => {
      colgada.resolver({ tipo: 'acceso', userId: 'u-ana', rol: 'vendedor', nombre: 'ANA', puedeContratar: true })
      await Promise.resolve()
    })
    expect(actor.getSnapshot().value).toBe('listo')
    expect(screen.queryByLabelText('Correo')).not.toBeInTheDocument()
    actor.stop()
  })
})
