import { beforeEach, describe, expect, it, vi } from 'vitest'
import { escribirHash, hashDe, leerHash } from './router'

describe('router por hash', () => {
  beforeEach(() => {
    window.history.replaceState(null, '', '/')
  })

  it('construye rutas canónicas y codifica el identificador del lead', () => {
    expect(hashDe('hoy')).toBe('#/hoy')
    expect(hashDe('pipeline', null)).toBe('#/pipeline')
    expect(hashDe('cartera', 'lead/á 1')).toBe('#/cartera/lead/lead%2F%C3%A1%201')
  })

  it.each([
    ['#/hoy', 'hoy'],
    ['#pipeline', 'pipeline'],
    ['#/agenda/', 'agenda'],
    ['#/equipo///', 'equipo'],
  ] as const)('acepta variantes compatibles de %s', (hash, vista) => {
    window.location.hash = hash
    expect(leerHash()).toEqual({ vista, leadId: null })
  })

  it('decodifica un lead y descarta rutas o escapes desconocidos', () => {
    window.location.hash = '#/cartera/lead/lead%2F%C3%A1%201'
    expect(leerHash()).toEqual({ vista: 'cartera', leadId: 'lead/á 1' })

    window.location.hash = '#/desconocida/lead/l1'
    expect(leerHash()).toEqual({ vista: null, leadId: null })

    window.location.hash = '#/hoy/lead/%E0%A4%A'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null })
  })

  it('navega con historial normal y evita escrituras redundantes', () => {
    escribirHash('pipeline', 'l1')
    expect(window.location.hash).toBe('#/pipeline/lead/l1')

    const replaceState = vi.spyOn(window.history, 'replaceState')
    escribirHash('pipeline', 'l1')
    expect(replaceState).not.toHaveBeenCalled()
  })

  it('reemplaza rutas de corrección sin agregar navegación', () => {
    const replaceState = vi.spyOn(window.history, 'replaceState')

    escribirHash('hoy', null, true)

    expect(replaceState).toHaveBeenCalledOnce()
    expect(replaceState).toHaveBeenCalledWith(null, '', '#/hoy')
  })
})
