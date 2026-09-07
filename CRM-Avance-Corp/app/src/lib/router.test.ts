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
    ['#/seguimiento', 'seguimiento'],
    ['#pipeline', 'pipeline'],
    ['#/agenda/', 'agenda'],
    ['#/equipo///', 'equipo'],
    ['#/config-usuarios', 'config-usuarios'],
    ['#/config-productos', 'config-productos'],
    ['#/config-metas', 'config-metas'],
    ['#/config-sla', 'config-sla'],
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

    // N1 (F3 de «Conversión única»): «Capital» dejó de ser vista — nació
    // muerta por autorización y todo lo suyo vive en el Resumen de Hoy. Su
    // bookmark viejo cae ahí, por URL directa o refresh profundo.
    window.location.hash = '#/capital-cierres'
    expect(leerHash()).toEqual({ vista: 'hoy', leadId: null })

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

  it('registra Derivaciones como módulo independiente y fuera del gate de leads', () => {
    window.location.hash = '#/derivaciones'

    expect(leerHash()).toEqual({ vista: 'derivaciones', leadId: null })
    expect(VISTAS).toContain('derivaciones')
    expect(esVistaLeads('derivaciones')).toBe(false)
    expect(hashDe('derivaciones')).toBe('#/derivaciones')
  })

  it('registra la carpeta de rescate como ruta interna del mundo leads', () => {
    window.location.hash = '#/rescate-carpeta'
    expect(leerHash()).toEqual({ vista: 'rescate-carpeta', leadId: null })
    expect(esVistaInterna('rescate-carpeta')).toBe(true)
    expect(esVistaLeads('rescate-carpeta')).toBe(true)
    expect(hashDe('rescate-carpeta')).toBe('#/rescate-carpeta')
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
    expect(VISTAS.slice(0, 3)).toEqual(['hoy', 'alertas', 'seguimiento'])
    expect(VISTAS_GERENCIA[0]).toBe('conversiones')
    expect(VISTAS_GERENCIA).not.toContain('alertas')
    expect(esVistaGerencia('alertas')).toBe(false)
    expect(esVistaLeads('alertas')).toBe(false)
    expect(hashDe('alertas')).toBe('#/alertas')
  })

  it('separa Seguimiento de los informes de Gerencia y conserva ficha y gate de leads', () => {
    expect(esVistaGerencia('seguimiento')).toBe(false)
    expect(esVistaLeads('seguimiento')).toBe(true)
    expect(esVistaInterna('seguimiento')).toBe(false)
    expect(hashDe('seguimiento', 'l-1')).toBe('#/seguimiento/lead/l-1')
    window.location.hash = '#/seguimiento/lead/l-1'
    expect(leerHash()).toEqual({ vista: 'seguimiento', leadId: 'l-1' })
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
