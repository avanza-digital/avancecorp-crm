import { describe, expect, it } from 'vitest'
import { VISTAS_GERENCIA } from './router'
import { vistaPermitida } from './vistas'

describe('navegación de Gerencia', () => {
  it('expone Resumen y siete páginas ejecutivas; Alertas es transversal', () => {
    expect(VISTAS_GERENCIA).toEqual(['conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento', 'facturacion', 'informes-empresas'])
    expect(vistaPermitida('alertas', 'gerencia', false)).toBe(true)
  })

  it('habilita todas las páginas de inteligencia solo para Gerencia', () => {
    for (const vista of VISTAS_GERENCIA) {
      expect(vistaPermitida(vista, 'gerencia', true)).toBe(true)
      expect(vistaPermitida(vista, 'supervisor', true)).toBe(false)
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
