// Tests del ARRANQUE (App): las dos pantallas que ve el asesor antes de entrar
// al CRM — el splash con fecha de caducidad y el Login — y las dos regresiones
// que introdujo la pasada de arreglos de sesión del 2026-07-25:
//   1. volver a la pestaña con la app en `error` borraba lo ya tecleado, y
//   2. el reloj del splash no se reiniciaba entre la etapa de ACCESO y la de
//      DATOS, así que una carga lenta pero sana se declaraba atascada.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { act, fireEvent, render, screen } from '@testing-library/react'
import { useEffect, useState, type ReactNode } from 'react'
import { createActor } from 'xstate'
import App, { LIMITE_SPLASH_MS } from './App'
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

const TEXTO_SPINNER = 'Preparando tu información…'
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

// El splash del ACCESO y el de DATOS ocupan el MISMO hueco del árbol y son el
// mismo componente: sin una `key` distinta React no remonta, el estado interno
// (`atascado`) y su temporizador sobreviven al cambio de etapa, y un solo reloj
// de 25 s acaba cubriendo los dos presupuestos seguidos.
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

    const { rerender } = render(pantalla({ fase: 'init' }))
    expect(screen.getByText(TEXTO_SPINNER)).toBeInTheDocument()

    // Etapa 1: la verificación de acceso consume casi todo SU presupuesto…
    act(() => vi.advanceTimersByTime(LIMITE_VERIFICACION_MS - 1))
    expect(screen.getByText(TEXTO_SPINNER)).toBeInTheDocument()

    // …resuelve, y arranca la carga de datos: otra etapa, otro splash.
    rerender(pantalla({ fase: 'listo', yo: YO }, { cargando: true }))

    // Etapa 2: casi todo su presupuesto también. Ninguna de las dos agotó el
    // suyo, así que esto es LENTITUD, no un cuelgue: el asesor sigue viendo el
    // spinner y nadie aborta un fetch que va camino de responder.
    act(() => vi.advanceTimersByTime(LIMITE_CARGA_REAL_MS - 1))
    expect(screen.queryByText(TEXTO_ATASCADO)).not.toBeInTheDocument()
    expect(screen.getByText(TEXTO_SPINNER)).toBeInTheDocument()
  })

  it('pero un splash de DATOS genuinamente colgado sí caduca y ofrece salida', () => {
    const reintentar = vi.fn()
    render(pantalla({ fase: 'listo', yo: YO }, { cargando: true, reintentar }))

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()

    // La salida es accionable de verdad: pide los datos otra vez y vuelve al
    // spinner (si se cuelga otra vez, el reloj lo detecta de nuevo).
    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(reintentar).toHaveBeenCalledTimes(1)
    expect(screen.getByText(TEXTO_SPINNER)).toBeInTheDocument()
  })

  it('y un splash de ACCESO colgado también caduca (su salida re-verifica la sesión)', () => {
    const reintentar = vi.fn()
    render(pantalla({ fase: 'init', reintentar }))

    act(() => vi.advanceTimersByTime(LIMITE_SPLASH_MS + 1))
    expect(screen.getByText(TEXTO_ATASCADO)).toBeInTheDocument()

    fireEvent.click(screen.getByRole('button', { name: /Reintentar/ }))
    expect(reintentar).toHaveBeenCalledTimes(1)
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
    expect(screen.queryByText(TEXTO_SPINNER)).not.toBeInTheDocument()
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
