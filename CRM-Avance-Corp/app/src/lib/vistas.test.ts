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
    vendedor: ['hoy', 'alertas', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'config'],
    supervisor: ['hoy', 'alertas', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'equipo'],
    gerencia: ['hoy', 'alertas', 'conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'repartir', 'equipo', 'config', 'config-usuarios', 'config-productos', 'config-metas', 'config-sla'],
    directorio: ['hoy', 'pipeline', 'cartera', 'agenda', 'mi-cartera', 'equipo', 'config', 'config-usuarios', 'config-productos', 'config-metas', 'config-sla'],
    // El coordinador NO entra al mundo leads ni con la llave abierta (2026-08-18):
    // «hoy» es la única vista de leads sin capacidad exigida y se la habría
    // regalado. Su ámbito de leads es ∅ y su destino único es «Repartir».
    coordinador: ['repartir'],
  },
  cerrado: {
    vendedor: ['mi-cartera', 'config'],
    supervisor: ['mi-cartera', 'equipo'],
    gerencia: ['hoy', 'alertas', 'conversiones', 'ranking-vendedores', 'reuniones', 'metas', 'rendimiento', 'mi-cartera', 'repartir', 'equipo', 'config', 'config-usuarios', 'config-productos', 'config-metas', 'config-sla'],
    directorio: ['mi-cartera', 'equipo', 'config', 'config-usuarios', 'config-productos', 'config-metas', 'config-sla'],
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

  it('aterriza a Superadmin sin Gerencia directamente en Usuarios', () => {
    expect(vistaBase('directorio', true, 'superadmin')).toBe('config-usuarios')
    expect(vistaBase('vendedor', false, 'superadmin')).toBe('config-usuarios')
    expect(vistaBase('gerencia', false, 'superadmin')).toBe('hoy')
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
    expect(sanearVista('repartir', 'gerencia', true)).toBe('repartir')
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

  it('abre a Gerencia todas las rutas operativas y conserva el gate de leads', () => {
    for (const vista of ['pipeline', 'cartera', 'agenda'] as const) {
      expect(sanearVista(vista, 'gerencia', true)).toBe(vista)
      expect(sanearVista(vista, 'gerencia', false)).toBe('hoy')
    }
    for (const vista of ['equipo', 'repartir', 'mi-cartera', 'config'] as const) {
      expect(sanearVista(vista, 'gerencia', true)).toBe(vista)
      expect(sanearVista(vista, 'gerencia', false)).toBe(vista)
    }
  })

  it('abre #/alertas para los roles destinatarios y respeta el gate operativo', () => {
    expect(sanearVista('alertas', 'gerencia', true)).toBe('alertas')
    expect(sanearVista('alertas', 'gerencia', false)).toBe('alertas')
    expect(sanearVista('alertas', 'supervisor', true)).toBe('alertas')
    expect(sanearVista('alertas', 'vendedor', true)).toBe('alertas')
    expect(sanearVista('alertas', 'supervisor', false)).toBe('mi-cartera')
    expect(sanearVista('alertas', 'vendedor', false)).toBe('mi-cartera')
    expect(sanearVista('alertas', 'directorio', true)).toBe('hoy')
    expect(sanearVista('alertas', 'coordinador', false)).toBe('repartir')
  })

  it('limita los módulos de gobierno y abre Usuarios al Superadmin Portal', () => {
    for (const vista of ['config-usuarios', 'config-productos', 'config-metas', 'config-sla'] as const) {
      expect(sanearVista(vista, 'gerencia', false)).toBe(vista)
      expect(sanearVista(vista, 'directorio', false)).toBe(vista)
      expect(sanearVista(vista, 'vendedor', false)).toBe('mi-cartera')
    }

    expect(sanearVista('config-usuarios', 'vendedor', false, 'superadmin')).toBe('config-usuarios')
    expect(sanearVista('config-productos', 'vendedor', false, 'superadmin')).toBe('config-usuarios')

    // Caso real del RPC: Superadmin sin membresía se proyecta a Directorio para
    // mantener el tipo `Yo`, pero su capacidad viva lo reduce a una sola ruta.
    expect(VISTAS.filter((vista) =>
      vistaPermitida(vista, 'directorio', true, 'superadmin'),
    )).toEqual(['config-usuarios'])
    expect(sanearVista('hoy', 'directorio', true, 'superadmin')).toBe('config-usuarios')

    // La combinación explícita sí suma autoridades.
    expect(sanearVista('config-productos', 'gerencia', false, 'superadmin')).toBe('config-productos')
  })
})

describe('dónde puede vivir una función nueva del supervisor (decisión #10)', () => {
  // Esta suite nace de un error real: el ranking del supervisor se montó dentro
  // de «Hoy», y en producción un supervisor NO ve «Hoy» —`FUNCIONES_LEADS_APROBADAS`
  // está en false y esa vista pertenece al mundo de leads—, así que la función
  // quedó invisible para su único destinatario. Los tests de render no lo
  // detectaron porque montan el componente saltándose el router.
  //
  // La regla que dejan escrita: antes de colgar algo de una vista, comprobar que
  // el rol al que va dirigido PUEDE ABRIRLA con el gate de leads CERRADO.
  const LEADS_CERRADOS = false

  it('un supervisor NO puede abrir «hoy» con el gate de leads cerrado', () => {
    expect(vistaPermitida('hoy', 'supervisor', LEADS_CERRADOS)).toBe(false)
  })

  it('un supervisor SÍ puede abrir «equipo»: por eso vive ahí su ranking', () => {
    expect(vistaPermitida('equipo', 'supervisor', LEADS_CERRADOS)).toBe(true)
  })

  it('y «mi-cartera», su otra pantalla viva en producción', () => {
    expect(vistaPermitida('mi-cartera', 'supervisor', LEADS_CERRADOS)).toBe(true)
  })

  it('gerencia sí conserva «hoy» aunque el gate esté cerrado (su ranking sigue ahí)', () => {
    expect(vistaPermitida('hoy', 'gerencia', LEADS_CERRADOS)).toBe(true)
  })
})
