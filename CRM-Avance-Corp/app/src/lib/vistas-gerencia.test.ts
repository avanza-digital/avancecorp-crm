import { describe, expect, it } from 'vitest'
import { VISTAS_GERENCIA } from './router'
import { vistaPermitida } from './vistas'

describe('navegación de Gerencia', () => {
  it('expone Resumen y cinco páginas ejecutivas; Alertas es transversal', () => {
    expect(VISTAS_GERENCIA).toEqual(['conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento'])
    expect(vistaPermitida('alertas', 'gerencia', false)).toBe(true)
    expect(vistaPermitida('capital-cierres', 'gerencia', true)).toBe(false)
  })

  it('habilita todas las páginas de inteligencia solo para Gerencia', () => {
    for (const vista of VISTAS_GERENCIA) {
      expect(vistaPermitida(vista, 'gerencia', true)).toBe(true)
      expect(vistaPermitida(vista, 'supervisor', true)).toBe(false)
      expect(vistaPermitida(vista, 'vendedor', true)).toBe(false)
    }
  })

  it('retira Pipeline y las herramientas operativas de Gerencia', () => {
    expect(vistaPermitida('pipeline', 'gerencia', true)).toBe(false)
    expect(vistaPermitida('cartera', 'gerencia', true)).toBe(false)
    expect(vistaPermitida('agenda', 'gerencia', true)).toBe(false)
    expect(vistaPermitida('hoy', 'gerencia', true)).toBe(true)
  })
})
