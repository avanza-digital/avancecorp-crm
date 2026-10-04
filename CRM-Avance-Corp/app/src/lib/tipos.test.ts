import { describe, expect, it } from 'vitest'
import {
  MOTIVOS_DESCARTE,
  MOTIVOS_DESCARTE_LECTURA,
  ORIGENES,
  ORIGENES_LECTURA,
  ORIGENES_TODOS,
  esOrigen,
  esOrigenAlta,
  esOrigenLectura,
  etiquetaOrigen,
  motivoDescarteLabel,
  origenLabel,
} from './tipos'

describe('catálogo de orígenes de lead', () => {
  it('expone solo los orígenes seleccionables en altas y ediciones', () => {
    expect(ORIGENES).toEqual([
      { k: 'referido', label: 'Referido' },
      { k: 'landing', label: 'LANDING' },
      { k: 'formulario', label: 'FORMULARIO' },
      { k: 'oficina', label: 'Walking' },
    ])
  })

  it('excluye retirados del selector y conserva sus etiquetas históricas', () => {
    const activos = ORIGENES.map((origen) => origen.k)
    const todos = ORIGENES_TODOS.map((origen) => origen.k)

    expect(activos).not.toContain('web')
    expect(activos).not.toContain('campania')
    expect(activos).not.toContain('whatsapp')
    expect(activos).not.toContain('otro')
    expect(todos).toEqual(expect.arrayContaining(['web', 'campania', 'whatsapp', 'otro']))
    expect(origenLabel('web')).toBe('Web')
    expect(origenLabel('campania')).toBe('Campaña')
    expect(origenLabel('whatsapp')).toBe('WhatsApp')
    expect(origenLabel('otro')).toBe('Otro')
  })
})

// F5a «Bases cargadas» (04/10/2026): `base_cargada` se LEE (origen y motivo) pero nadie lo elige.
describe('F5a · base_cargada es de solo lectura', () => {
  it('el origen se lee y se rotula «Base cargada», sin siglas', () => {
    expect(ORIGENES_LECTURA.map((o) => o.k)).toContain('base_cargada')
    expect(origenLabel('base_cargada')).toBe('Base cargada')
    expect(etiquetaOrigen('base_cargada')).toBe('Base cargada')
    expect(esOrigenLectura('base_cargada')).toBe(true)
  })

  it('el origen NO se elige en el alta ni viaja como filtro (catálogos de escritura intactos)', () => {
    expect(ORIGENES.map((o) => o.k)).not.toContain('base_cargada')
    expect(ORIGENES_TODOS.map((o) => o.k)).not.toContain('base_cargada')
    expect(esOrigenAlta('base_cargada')).toBe(false)
    expect(esOrigen('base_cargada')).toBe(false)
  })

  it('el motivo se lee y se rotula, pero el select de descartar no lo ofrece', () => {
    expect(MOTIVOS_DESCARTE_LECTURA.map((m) => m.k)).toContain('base_cargada')
    expect(motivoDescarteLabel('base_cargada')).toBe('Base cargada')
    expect(MOTIVOS_DESCARTE.map((m) => m.k)).not.toContain('base_cargada')
  })

  it('ESTADO DE PRODUCCIÓN: los catálogos de lectura empiezan por los de siempre, en el mismo orden', () => {
    expect(ORIGENES_LECTURA.slice(0, ORIGENES_TODOS.length)).toEqual([...ORIGENES_TODOS])
    expect(MOTIVOS_DESCARTE_LECTURA.slice(0, MOTIVOS_DESCARTE.length)).toEqual([...MOTIVOS_DESCARTE])
    expect(motivoDescarteLabel('no_responde')).toBe('No responde')
    expect(motivoDescarteLabel('desconocido')).toBe('desconocido')
  })
})
