import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  escribirHash,
  esVistaGerencia,
  esVistaConfiguracion,
  esVistaInterna,
  esVistaLeads,
  hashDe,
  leerHash,
  VISTAS,
  VISTAS_GERENCIA,
} from './router'

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
    ['#/alertas', 'alertas'],
    ['#pipeline', 'pipeline'],
    ['#/agenda/', 'agenda'],
    ['#/equipo///', 'equipo'],
    ['#/config-usuarios', 'config-usuarios'],
    ['#/config-productos', 'config-productos'],
    ['#/config-metas', 'config-metas'],
    ['#/config-sla', 'config-sla'],
    ['#/rescate', 'rescate'],
    ['#/rescate-carpeta', 'rescate-carpeta'],
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

  it('resuelve las rutas HEREDADAS (clientes/contratos → mi-cartera) sin reintroducirlas', () => {
    // Bookmarks viejos de las pantallas retiradas en Fase 6 caen en la cartera
    // unificada, no en la vista base 'hoy'.
    window.location.hash = '#/clientes'
    expect(leerHash()).toEqual({ vista: 'mi-cartera', leadId: null })

    window.location.hash = '#/contratos'
    expect(leerHash()).toEqual({ vista: 'mi-cartera', leadId: null })

    // Una ruta realmente desconocida sigue degradando a null (no todo es alias).
    window.location.hash = '#/inexistente'
    expect(leerHash()).toEqual({ vista: null, leadId: null })

    // Claves del prototipo del Record NO deben resolver a un miembro heredado
    // (Object/toString/prototype): degradan a null como cualquier ruta desconocida.
    for (const clave of ['constructor', 'toString', '__proto__', 'hasOwnProperty']) {
      window.location.hash = `#/${clave}`
      expect(leerHash()).toEqual({ vista: null, leadId: null })
    }
  })

  it('reconoce #/repartir y la deja FUERA del mundo leads (C1)', () => {
    // 'repartir' debe ser navegable por URL para el coordinador; si entrara en
    // VISTAS_LEADS, el gate de leads (cerrado para su rol) la ocultaría justo a
    // quien es la única pantalla que puede usar.
    window.location.hash = '#/repartir'
    expect(leerHash()).toEqual({ vista: 'repartir', leadId: null })
    expect(VISTAS).toContain('repartir')
    expect(esVistaLeads('repartir')).toBe(false)
    expect(hashDe('repartir')).toBe('#/repartir')
  })

  it('registra Base para gestión y mantiene su carpeta como ruta interna', () => {
    expect(esVistaLeads('rescate')).toBe(true)
    expect(esVistaLeads('rescate-carpeta')).toBe(true)
    expect(esVistaInterna('rescate')).toBe(false)
    expect(esVistaInterna('rescate-carpeta')).toBe(true)
    expect(hashDe('rescate-carpeta')).toBe('#/rescate-carpeta')
  })

  it('registra Derivaciones como módulo independiente y fuera del gate de leads', () => {
    window.location.hash = '#/derivaciones'

    expect(leerHash()).toEqual({ vista: 'derivaciones', leadId: null })
    expect(VISTAS).toContain('derivaciones')
    expect(esVistaLeads('derivaciones')).toBe(false)
    expect(hashDe('derivaciones')).toBe('#/derivaciones')
  })

  it('registra los cuatro módulos como rutas internas de Configuración', () => {
    for (const vista of [
      'config-usuarios',
      'config-productos',
      'config-metas',
      'config-sla',
    ] as const) {
      expect(VISTAS).toContain(vista)
      expect(esVistaConfiguracion(vista)).toBe(true)
      expect(esVistaLeads(vista)).toBe(false)
      expect(esVistaGerencia(vista)).toBe(false)
      expect(hashDe(vista)).toBe(`#/${vista}`)
    }
    expect(esVistaConfiguracion('config')).toBe(false)
  })

  it('registra Alertas justo después de Hoy como bandeja transversal', () => {
    expect(VISTAS.slice(0, 3)).toEqual(['hoy', 'alertas', 'conversiones'])
    expect(VISTAS_GERENCIA[0]).toBe('conversiones')
    expect(VISTAS_GERENCIA).not.toContain('alertas')
    expect(esVistaGerencia('alertas')).toBe(false)
    expect(esVistaLeads('alertas')).toBe(false)
    expect(hashDe('alertas')).toBe('#/alertas')
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
