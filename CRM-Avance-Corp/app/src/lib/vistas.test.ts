// Guard de vistas por capacidad (espejo del nav y de la RLS). Se prueba puro:
// vistaBase decide dónde ATERRIZA cada rol y sanearVista qué pasa cuando una
// vista se alcanza por URL sin permiso — la doble defensa del patrón VITANOVA
// (el nav oculta, el guard expulsa, el servidor niega).
import { describe, expect, it } from 'vitest'
import { ROLES, type Rol } from './roles'
import { VISTAS, type Vista } from './router'
import { sanearVista, vistaBase, vistaPermitida } from './vistas'

const VISTAS_POR_GATE = {
  abierto: {
    vendedor: ['hoy', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'config'],
    supervisor: ['hoy', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'equipo'],
    gerencia: ['hoy', 'alertas', 'conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento'],
    directorio: ['hoy', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'equipo', 'config'],
    coordinador: ['hoy', 'repartir'],
  },
  cerrado: {
    vendedor: ['mi-cartera', 'config'],
    supervisor: ['mi-cartera', 'equipo'],
    gerencia: ['hoy', 'alertas', 'conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento'],
    directorio: ['mi-cartera', 'equipo', 'config'],
    coordinador: ['repartir'],
  },
} as const satisfies Record<'abierto' | 'cerrado', Record<Rol, readonly Vista[]>>

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
    // Gerencia aterriza siempre en inteligencia, aunque no haya funciones de leads.
    expect(vistaBase('gerencia', false)).toBe('hoy')
    expect(vistaBase(null, false)).toBe('mi-cartera')
  })
})

describe('vistaPermitida — fuente única de acceso', () => {
  it('mantiene exhaustiva la matriz actual de todos los roles y vistas', () => {
    for (const [leadsVisibles, esperadasPorRol] of [
      [true, VISTAS_POR_GATE.abierto],
      [false, VISTAS_POR_GATE.cerrado],
    ] as const) {
      for (const rol of ROLES) {
        expect(VISTAS.filter((vista) => vistaPermitida(vista, rol, leadsVisibles))).toEqual(
          esperadasPorRol[rol],
        )
      }
    }
  })

  it('niega todas las vistas cuando falta una identidad válida', () => {
    for (const vista of VISTAS) {
      expect(vistaPermitida(vista, null, true)).toBe(false)
      expect(vistaPermitida(vista, undefined, false)).toBe(false)
      expect(vistaPermitida(vista, 'rol-inexistente' as Rol, true)).toBe(false)
    }
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
    expect(sanearVista('repartir', 'gerencia', true)).toBe('hoy')
  })

  it('no altera el comportamiento previo de los roles operativos', () => {
    expect(sanearVista('mi-cartera', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('hoy', 'gerencia', true)).toBe('hoy')
    // #/config SÍ es del vendedor desde que su calendario ICS ("Mi calendario de
    // Google") vive ahí: can('vendedor','verConfiguracion') pasó a true y el
    // guard ya no lo expulsa. Ver ≠ editar: editarConfiguracion sigue en false.
    expect(sanearVista('config', 'vendedor', false)).toBe('config')
    expect(sanearVista('equipo', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('equipo', 'supervisor', false)).toBe('equipo')
    // Gate de leads cerrado: las vistas de leads caen a la base del rol.
    expect(sanearVista('pipeline', 'vendedor', false)).toBe('mi-cartera')
  })

  it('expulsa a Gerencia de las rutas operativas', () => {
    for (const vista of ['pipeline', 'cartera', 'agenda', 'equipo', 'repartir', 'mi-cartera', 'config'] as const) {
      expect(sanearVista(vista, 'gerencia', true)).toBe('hoy')
      expect(sanearVista(vista, 'gerencia', false)).toBe('hoy')
    }
    expect(sanearVista('hoy', 'gerencia', true)).toBe('hoy')
    expect(sanearVista('hoy', 'gerencia', false)).toBe('hoy')
  })

  it('reserva #/alertas para Gerencia con ambos estados del gate', () => {
    expect(sanearVista('alertas', 'gerencia', true)).toBe('alertas')
    expect(sanearVista('alertas', 'gerencia', false)).toBe('alertas')
    expect(sanearVista('alertas', 'supervisor', true)).toBe('hoy')
    expect(sanearVista('alertas', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('alertas', 'directorio', true)).toBe('hoy')
    expect(sanearVista('alertas', 'coordinador', false)).toBe('repartir')
  })
})
