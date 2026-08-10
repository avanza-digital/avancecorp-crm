// El gate de entorno y el saneo de migas, bajo prueba.
//
// Por qué existe este archivo: el 2026-08-09 el DSN vivía en `app/.env`, que Vite
// carga en TODOS los modos, y `instalarSentry` solo comprobaba que el DSN existiera.
// Resultado: cada `npm run dev` y cada corrida de Playwright reportaban al proyecto
// de PRODUCCIÓN — 742 eventos de laboratorio que enterraron la señal real. Miguel
// decidió SILENCIO TOTAL fuera de producción.
//
// Y la revisión de Codex encontró la otra mitad: al abrir la CSP se activaba un
// canal de PII. Sentry copia el árbol DOM (con `aria-label`) en sus migas de UI, y
// el CRM pone ahí nombres de clientes. Los tests de abajo aseveran las dos cosas.
//
// `observabilidad` se importa REAL a propósito (solo se espía el sumidero): así el
// scrubber que se ejercita es el de verdad, no una identidad que aprueba cualquier cosa.
import { afterEach, describe, expect, it, vi } from 'vitest'

const init = vi.fn()
vi.mock('@sentry/react', () => ({ init, captureMessage: vi.fn() }))

const conectarSumidero = vi.fn()
vi.mock('./observabilidad', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./observabilidad')>()),
  conectarSumidero,
}))

const { instalarSentry } = await import('./sentry')

const DSN = 'https://clave@o4511877814026240.ingest.us.sentry.io/999'

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

/** Instala en modo producción y devuelve las opciones con las que se llamó a init. */
async function instalarComoProduccion() {
  vi.stubEnv('MODE', 'production')
  vi.stubEnv('VITE_SENTRY_DSN', DSN)
  instalarSentry()
  await dejarCorrerLaCargaAsincrona()
  const opciones = init.mock.calls[0]?.[0]
  if (!opciones) throw new Error('Sentry.init no se llamó en modo producción')
  return opciones
}

afterEach(() => {
  vi.unstubAllEnvs()
  init.mockClear()
  conectarSumidero.mockClear()
})

describe('instalarSentry — silencio total fuera de producción', () => {
  it('NO instala el SDK aunque el DSN esté configurado (modo test/desarrollo)', async () => {
    vi.stubEnv('VITE_SENTRY_DSN', DSN)

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(init).not.toHaveBeenCalled()
  })

  it('NO engancha el sumidero: los registrarError se quedan en casa', async () => {
    vi.stubEnv('VITE_SENTRY_DSN', DSN)

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(conectarSumidero).not.toHaveBeenCalled()
  })

  it('un build de STAGING tampoco reporta (MODE, no PROD: `--mode staging` da PROD=true)', async () => {
    vi.stubEnv('MODE', 'staging')
    vi.stubEnv('VITE_SENTRY_DSN', DSN)

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(init).not.toHaveBeenCalled()
  })

  it('sin DSN tampoco hace nada, ni siquiera en producción (el guard del DSN sigue vivo)', async () => {
    vi.stubEnv('MODE', 'production')
    vi.stubEnv('VITE_SENTRY_DSN', '')

    instalarSentry()
    await dejarCorrerLaCargaAsincrona()

    expect(init).not.toHaveBeenCalled()
    expect(conectarSumidero).not.toHaveBeenCalled()
  })
})

describe('instalarSentry — en producción SÍ hay telemetría', () => {
  // Sin esta rama, un `return` incondicional al principio de instalarSentry dejaría
  // toda la suite en verde y nos quedaríamos otra vez sin telemetría sin enterarnos
  // (hueco señalado por Codex).
  it('instala el SDK y engancha el sumidero de observabilidad', async () => {
    await instalarComoProduccion()

    expect(init).toHaveBeenCalledTimes(1)
    expect(conectarSumidero).toHaveBeenCalledTimes(1)
  })

  it('no activa tracing ni PII por defecto', async () => {
    const opciones = await instalarComoProduccion()

    expect(opciones.tracesSampleRate).toBe(0)
    expect(opciones.sendDefaultPii).toBe(false)
    expect(opciones.environment).toBe('production')
  })
})

describe('beforeBreadcrumb — el canal no lleva PII de clientes', () => {
  it('DESCARTA las migas de UI: el aria-label del CRM lleva nombres de clientes', async () => {
    const { beforeBreadcrumb } = await instalarComoProduccion()

    // Lo que Sentry captura al pulsar el botón de «Llamar a …» (contacto.tsx).
    const miga = beforeBreadcrumb(
      {
        category: 'ui.click',
        message: 'button[aria-label="Llamar a JUAN PEREZ QUISPE"]',
      },
      {},
    )

    expect(miga).toBeNull()
  })

  it('DESCARTA también ui.input (lo que el usuario teclea en el buscador)', async () => {
    const { beforeBreadcrumb } = await instalarComoProduccion()

    expect(beforeBreadcrumb({ category: 'ui.input', message: 'input#q' }, {})).toBeNull()
  })

  it('a una petición le deja la ruta pero le quita la query (ahí viaja la búsqueda)', async () => {
    const { beforeBreadcrumb } = await instalarComoProduccion()

    const miga = beforeBreadcrumb(
      {
        category: 'fetch',
        data: {
          url: 'https://x.supabase.co/rest/v1/leads?nombre_completo=ilike.%25JUAN%25&select=*',
          status_code: 200,
        },
      },
      {},
    )

    expect(miga?.data?.url).toBe('https://x.supabase.co/rest/v1/leads?[QUERY REDACTADA]')
    // La ruta sobrevive: sin ella la miga no diría ni qué se llamó.
    expect(miga?.data?.url).toContain('/rest/v1/leads')
    expect(miga?.data?.status_code).toBe(200)
  })

  it('una URL sin query se conserva tal cual', async () => {
    const { beforeBreadcrumb } = await instalarComoProduccion()

    const miga = beforeBreadcrumb({ category: 'fetch', data: { url: 'https://x.supabase.co/rest/v1/leads' } }, {})

    expect(miga?.data?.url).toBe('https://x.supabase.co/rest/v1/leads')
  })
})

describe('beforeSend — el evento sale sin request ni usuario', () => {
  it('borra `request` y `user` (y por eso «Users Impacted» siempre será 0)', async () => {
    const { beforeSend } = await instalarComoProduccion()

    const evento = beforeSend(
      {
        message: 'algo',
        request: { url: 'https://crm.miavance.com/?dni=45781234' },
        user: { id: 'perfil-1', email: 'vendedor@avancecorp.com' },
      },
      {},
    )

    expect(evento.request).toBeUndefined()
    expect(evento.user).toBeUndefined()
  })

  it('escombra el correo del mensaje con el scrubber REAL', async () => {
    const { beforeSend } = await instalarComoProduccion()

    const evento = beforeSend({ message: 'falló para juan.perez@gmail.com' }, {})

    expect(evento.message).not.toContain('juan.perez@gmail.com')
    expect(evento.message).toContain('[CORREO REDACTADO]')
  })
})
