import { describe, expect, it, vi } from 'vitest'
import {
  consultarVersionPublicada,
  hayVersionNueva,
  urlParaActualizar,
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
