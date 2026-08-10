// El gate de entorno de la telemetría, bajo prueba.
//
// Por qué existe este archivo: el 2026-08-09 el DSN vivía en `app/.env`, que Vite
// carga en TODOS los modos, y `instalarSentry` solo comprobaba que el DSN existiera.
// Resultado: cada `npm run dev` y cada corrida de Playwright reportaban al proyecto
// de PRODUCCIÓN — 742 eventos de laboratorio (mocks de E2E, fetches cancelados) que
// enterraron la señal real. Miguel decidió SILENCIO TOTAL fuera de producción.
//
// Sin este test, borrar la línea del gate deja verde todo lo demás.
import { afterEach, describe, expect, it, vi } from 'vitest'

const init = vi.fn()
vi.mock('@sentry/react', () => ({ init, captureMessage: vi.fn() }))

const conectarSumidero = vi.fn()
vi.mock('./observabilidad', () => ({
  conectarSumidero,
  idCorrelacion: () => 'correlacion-de-prueba',
  limpiarDato: (d: unknown) => d,
  limpiarTexto: (t: string) => t,
  registrarAviso: vi.fn(),
}))

const { instalarSentry } = await import('./sentry')

/**
 * El import de `@sentry/react` es DINÁMICO: si el gate no cortara, la instalación
 * ocurriría en un microtask posterior. Aseverar justo después de la llamada daría
 * verde aunque el gate no existiera — el mismo error que ya nos costó un rescate de
 * foco muerto. Por eso se cede el turno al event loop de verdad antes de mirar.
 */
async function dejarCorrerLaCargaAsincrona() {
  await new Promise((listo) => setTimeout(listo, 0))
  await new Promise((listo) => setTimeout(listo, 0))
}

afterEach(() => {
  vi.unstubAllEnvs()
  init.mockClear()
  conectarSumidero.mockClear()
})

describe('instalarSentry — silencio total fuera de producción', () => {
  it('NO instala el SDK aunque el DSN esté configurado (modo test/desarrollo)', async () => {
    vi.stubEnv('VITE_SENTRY_DSN', 'https://clave@o4511877814026240.ingest.us.sentry.io/999')

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(init).not.toHaveBeenCalled()
  })

  it('NO engancha el sumidero de observabilidad: los registrarError se quedan en casa', async () => {
    vi.stubEnv('VITE_SENTRY_DSN', 'https://clave@o4511877814026240.ingest.us.sentry.io/999')

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(conectarSumidero).not.toHaveBeenCalled()
  })

  it('sin DSN tampoco hace nada (el guard original sigue vivo)', async () => {
    vi.stubEnv('VITE_SENTRY_DSN', '')

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(init).not.toHaveBeenCalled()
    expect(conectarSumidero).not.toHaveBeenCalled()
  })
})
