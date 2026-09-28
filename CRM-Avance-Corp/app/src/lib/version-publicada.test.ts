import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  consultarVersionPublicada,
  hayVersionNueva,
  limpiarMarcaDeVersion,
  urlParaActualizar,
  urlSinMarcaDeVersion,
} from './version-publicada'

function respuestaJson(valor: unknown, ok = true) {
  return {
    ok,
    json: vi.fn().mockResolvedValue(valor),
  }
}

describe('version publicada', () => {
  it('consulta el marcador sin cache y agrega una llave unica', async () => {
    const fetchVersion = vi.fn().mockResolvedValue(
      respuestaJson({ schema: 1, buildId: 'build-20260820T210000Z' }),
    )

    await expect(consultarVersionPublicada({
      baseUrl: 'https://crm.miavance.com/#/pipeline',
      fetchVersion,
      ahora: 1234,
    })).resolves.toEqual({ schema: 1, buildId: 'build-20260820T210000Z' })

    expect(fetchVersion).toHaveBeenCalledOnce()
    const [url, opciones] = fetchVersion.mock.calls[0] as [URL, RequestInit]
    expect(url.toString()).toBe('https://crm.miavance.com/version.json?_version=1234')
    expect(opciones).toMatchObject({
      cache: 'no-store',
      credentials: 'same-origin',
      headers: { Accept: 'application/json' },
    })
  })

  it('ignora respuestas invalidas o fallos de red sin interrumpir la sesion', async () => {
    const invalida = vi.fn().mockResolvedValue(respuestaJson({ buildId: '<script>' }))
    const errorRed = vi.fn().mockRejectedValue(new Error('sin red'))

    await expect(consultarVersionPublicada({
      baseUrl: 'https://crm.miavance.com/',
      fetchVersion: invalida,
    })).resolves.toBeNull()
    await expect(consultarVersionPublicada({
      baseUrl: 'https://crm.miavance.com/',
      fetchVersion: errorRed,
    })).resolves.toBeNull()
  })

  it('solo marca una identidad de build distinta como nueva', () => {
    expect(hayVersionNueva('build-a', { schema: 1, buildId: 'build-b' })).toBe(true)
    expect(hayVersionNueva('build-a', { schema: 1, buildId: 'build-a' })).toBe(false)
    expect(hayVersionNueva('build-a', null)).toBe(false)
  })

  it('conserva la vista hash al forzar un HTML fresco', () => {
    expect(urlParaActualizar(
      'https://crm.miavance.com/?origen=acceso#/derivaciones',
      'build-nuevo',
    )).toBe('https://crm.miavance.com/?origen=acceso&crm_version=build-nuevo#/derivaciones')
  })
})

describe('marca de version en la URL', () => {
  it('quita solo crm_version y conserva la ruta hash y los demas parametros', () => {
    expect(urlSinMarcaDeVersion('https://crm.miavance.com/?crm_version=build-1&otro=1#/hoy'))
      .toBe('https://crm.miavance.com/?otro=1#/hoy')
  })

  it('no deja un ? suelto cuando era el unico parametro', () => {
    expect(urlSinMarcaDeVersion('https://crm.miavance.com/?crm_version=build-1#/hoy'))
      .toBe('https://crm.miavance.com/#/hoy')
  })

  it('devuelve null si no habia nada que limpiar', () => {
    expect(urlSinMarcaDeVersion('https://crm.miavance.com/?otro=1#/hoy')).toBeNull()
    expect(urlSinMarcaDeVersion('https://crm.miavance.com/#/hoy')).toBeNull()
  })

  it('devuelve null ante una URL invalida, sin lanzar', () => {
    expect(() => urlSinMarcaDeVersion('esto no es una url')).not.toThrow()
    expect(urlSinMarcaDeVersion('esto no es una url')).toBeNull()
    expect(urlSinMarcaDeVersion('')).toBeNull()
  })

  it('es la inversa de urlParaActualizar: ida y vuelta devuelven la URL original', () => {
    for (const original of [
      'https://crm.miavance.com/?origen=acceso#/derivaciones',
      'https://crm.miavance.com/#/hoy',
      'https://crm.miavance.com/',
    ]) {
      expect(urlSinMarcaDeVersion(urlParaActualizar(original, 'build-nuevo'))).toBe(original)
    }
  })
})

describe('limpiarMarcaDeVersion (arranque)', () => {
  const irA = (ruta: string) => window.history.replaceState(null, '', ruta)

  afterEach(() => {
    irA('/')
  })

  it('limpia la barra de direcciones sin perder la ruta hash ni disparar hashchange', async () => {
    irA('/?crm_version=build-20260928T194323329Z&otro=1#/hoy')
    const alCambiarHash = vi.fn()
    window.addEventListener('hashchange', alCambiarHash)

    expect(limpiarMarcaDeVersion()).toBe(true)
    // hashchange se despacha en una tarea aparte: hay que dejarla correr.
    await new Promise((resolver) => setTimeout(resolver, 0))

    expect(window.location.search).toBe('?otro=1')
    expect(window.location.hash).toBe('#/hoy')
    expect(window.location.pathname).toBe('/')
    expect(alCambiarHash).not.toHaveBeenCalled()
    window.removeEventListener('hashchange', alCambiarHash)
  })

  it('no toca la URL cuando ya esta limpia', () => {
    irA('/?otro=1#/pipeline')
    const replaceState = vi.spyOn(window.history, 'replaceState')

    expect(limpiarMarcaDeVersion()).toBe(false)

    expect(replaceState).not.toHaveBeenCalled()
    expect(window.location.search).toBe('?otro=1')
    expect(window.location.hash).toBe('#/pipeline')
  })

  it('no rompe el arranque si history falla', () => {
    irA('/?crm_version=build-1#/hoy')
    const replaceState = vi.spyOn(window.history, 'replaceState').mockImplementation(() => {
      throw new Error('sin history')
    })
    try {
      expect(() => limpiarMarcaDeVersion()).not.toThrow()
      expect(limpiarMarcaDeVersion()).toBe(false)
    } finally {
      replaceState.mockRestore()
    }
  })
})
