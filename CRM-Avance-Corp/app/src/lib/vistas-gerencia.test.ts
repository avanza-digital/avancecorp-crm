import { describe, expect, it } from 'vitest'
import { VISTAS_GERENCIA } from './router'
import { vistaPermitida } from './vistas'

describe('navegación de Gerencia', () => {
  it('expone Resumen y seis páginas ejecutivas exclusivas; Alertas es transversal', () => {
    expect(VISTAS_GERENCIA).toEqual(['conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento', 'informes-empresas'])
    expect(vistaPermitida('alertas', 'gerencia', false)).toBe(true)
  })

  // Miguel, 16/09/2026: «que el módulo de facturación lo tengan los supervisores,
  // para ver el avance de sus equipos». Deja de ser exclusiva; el servidor
  // (crm.facturacion_diaria_fn) recorta al supervisor a su equipo.
  // Directorio la ve desde el 08/10/2026 (Miguel: «sí, que la vea»), en lectura.
  it('Facturación la comparten Gerencia, Supervisión y Directorio, con la llave abierta o cerrada', () => {
    for (const llave of [true, false]) {
      expect(vistaPermitida('facturacion', 'gerencia', llave)).toBe(true)
      expect(vistaPermitida('facturacion', 'supervisor', llave)).toBe(true)
      expect(vistaPermitida('facturacion', 'vendedor', llave)).toBe(false)
      expect(vistaPermitida('facturacion', 'directorio', llave)).toBe(true)
      expect(vistaPermitida('facturacion', 'coordinador', llave)).toBe(false)
    }
  })

  it('habilita las páginas de inteligencia solo para Gerencia, salvo Citas para su equipo', () => {
    for (const vista of VISTAS_GERENCIA) {
      expect(vistaPermitida(vista, 'gerencia', true)).toBe(true)
      expect(vistaPermitida(vista, 'supervisor', true)).toBe(vista === 'reuniones')
      expect(vistaPermitida(vista, 'vendedor', true)).toBe(false)
    }
  })

  it('combina inteligencia con todas las herramientas operativas', () => {
    expect(vistaPermitida('pipeline', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('cartera', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('agenda', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('mi-cartera', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('repartir', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('equipo', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('config', 'gerencia', true)).toBe(true)
    expect(vistaPermitida('hoy', 'gerencia', true)).toBe(true)
  })
})
