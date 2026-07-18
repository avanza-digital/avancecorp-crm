import { describe, expect, it } from 'vitest'
import { ORIGENES, ORIGENES_TODOS, origenLabel } from './tipos'

describe('catálogo de orígenes de lead', () => {
  it('expone solo los orígenes seleccionables en altas y ediciones', () => {
    expect(ORIGENES).toEqual([
      { k: 'referido', label: 'Referido' },
      { k: 'landing', label: 'LANDING' },
      { k: 'formulario', label: 'FORMULARIO' },
      { k: 'oficina', label: 'Wallking' },
      { k: 'otro', label: 'Otro' },
    ])
  })

  it('excluye retirados del selector y conserva sus etiquetas históricas', () => {
    const activos = ORIGENES.map((origen) => origen.k)
    const todos = ORIGENES_TODOS.map((origen) => origen.k)

    expect(activos).not.toContain('web')
    expect(activos).not.toContain('campania')
    expect(activos).not.toContain('whatsapp')
    expect(todos).toEqual(expect.arrayContaining(['web', 'campania', 'whatsapp']))
    expect(origenLabel('web')).toBe('Web')
    expect(origenLabel('campania')).toBe('Campaña')
    expect(origenLabel('whatsapp')).toBe('WhatsApp')
  })
})
