// Guard de vistas por capacidad (espejo del nav y de la RLS). Se prueba puro:
// vistaBase decide dónde ATERRIZA cada rol y sanearVista qué pasa cuando una
// vista se alcanza por URL sin permiso — la doble defensa del patrón VITANOVA
// (el nav oculta, el guard expulsa, el servidor niega).
import { describe, expect, it } from 'vitest'
import { sanearVista, vistaBase } from './vistas'

describe('vistaBase — dónde aterriza cada rol', () => {
  it('aterriza al coordinador en Repartir (no tiene cartera ni leads)', () => {
    expect(vistaBase('coordinador', false)).toBe('repartir')
    // Aunque el gate de leads se abriera algún día, su landing no cambia.
    expect(vistaBase('coordinador', true)).toBe('repartir')
  })

  it('conserva la landing de los demás roles', () => {
    expect(vistaBase('vendedor', false)).toBe('mi-cartera')
    expect(vistaBase('vendedor', true)).toBe('hoy')
    expect(vistaBase('supervisor', false)).toBe('mi-cartera')
    expect(vistaBase('gerencia', true)).toBe('hoy')
    // Gerencia SÍ puede repartir la cola, pero su landing sigue siendo la suya.
    expect(vistaBase('gerencia', false)).toBe('mi-cartera')
    expect(vistaBase(null, false)).toBe('mi-cartera')
  })
})

describe('sanearVista — expulsión por URL', () => {
  it('deja al coordinador en repartir y lo expulsa de todo lo demás', () => {
    expect(sanearVista('repartir', 'coordinador', false)).toBe('repartir')
    // Bookmarks o URLs a mano: ninguna vista ajena es alcanzable.
    expect(sanearVista('mi-cartera', 'coordinador', false)).toBe('repartir')
    expect(sanearVista('equipo', 'coordinador', false)).toBe('repartir')
    expect(sanearVista('config', 'coordinador', false)).toBe('repartir')
    expect(sanearVista('hoy', 'coordinador', false)).toBe('repartir')
    expect(sanearVista('cartera', 'coordinador', false)).toBe('repartir')
  })

  it('expulsa de #/repartir a quien no reparte la cola', () => {
    expect(sanearVista('repartir', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('repartir', 'supervisor', false)).toBe('mi-cartera')
    expect(sanearVista('repartir', 'directorio', true)).toBe('hoy')
    expect(sanearVista('repartir', null, false)).toBe('mi-cartera')
    // Gerencia sí puede: la pantalla queda accesible.
    expect(sanearVista('repartir', 'gerencia', true)).toBe('repartir')
  })

  it('no altera el comportamiento previo de los roles operativos', () => {
    expect(sanearVista('mi-cartera', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('hoy', 'gerencia', true)).toBe('hoy')
    expect(sanearVista('config', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('equipo', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('equipo', 'supervisor', false)).toBe('equipo')
    // Gate de leads cerrado: las vistas de leads caen a la base del rol.
    expect(sanearVista('pipeline', 'vendedor', false)).toBe('mi-cartera')
  })
})
