// Tests de los helpers puros de la pantalla Clientes: la regla de cartera por
// fila (espejo del servidor), la búsqueda normalizada, el filtro por asesor,
// el recorte de ámbito del demo y la paginación con clamp.
import { describe, expect, it } from 'vitest'
import {
  carteraDelAmbito,
  CLIENTES_POR_PAGINA,
  duenoDeCartera,
  esMiCliente,
  filtrarClientes,
  normalizar,
  paginar,
  type ClienteBuscable,
} from './clientes-vista'

/** Fila mínima buscable — cada test pisa solo lo que le importa. */
function fila(sobre: Partial<ClienteBuscable> = {}): ClienteBuscable {
  return {
    nombre_completo: 'CLIENTE DE PRUEBA',
    dni: null,
    correo: null,
    telefono: null,
    asesor_perfil_id: null,
    creado_por: null,
    ...sobre,
  }
}

describe('normalizar', () => {
  it('baja a minúsculas y quita acentos y eñes (es-PE)', () => {
    expect(normalizar('JOSÉ ÑAÑEZ Güisado')).toBe('jose nanez guisado')
  })

  it('deja intactos dígitos y símbolos (teléfonos y documentos)', () => {
    expect(normalizar('+51 987-120345')).toBe('+51 987-120345')
  })
})

describe('esMiCliente (regla de cartera del servidor, POR FILA)', () => {
  const MI = 'yo-1'

  it('asesor_perfil_id = mi uid → mía', () => {
    expect(esMiCliente(fila({ asesor_perfil_id: MI, creado_por: 'otro' }), MI)).toBe(true)
  })

  it('asesor NULL y creado_por = mi uid → mía (herencia del creador)', () => {
    expect(esMiCliente(fila({ asesor_perfil_id: null, creado_por: MI }), MI)).toBe(true)
  })

  it('asesor de OTRO aunque yo la haya creado → ajena (el asesor manda)', () => {
    expect(esMiCliente(fila({ asesor_perfil_id: 'otro', creado_por: MI }), MI)).toBe(false)
  })

  it('sin asesor ni creador → de nadie', () => {
    expect(esMiCliente(fila(), MI)).toBe(false)
  })

  it('sin identidad (yo null/vacío) degrada a ajena, jamás a mía', () => {
    expect(esMiCliente(fila({ asesor_perfil_id: null, creado_por: null }), null)).toBe(false)
    expect(esMiCliente(fila({ asesor_perfil_id: '' }), '')).toBe(false)
  })
})

describe('duenoDeCartera', () => {
  it('prioriza asesor_perfil_id y cae a creado_por solo con asesor NULL', () => {
    expect(duenoDeCartera(fila({ asesor_perfil_id: 'a', creado_por: 'b' }))).toBe('a')
    expect(duenoDeCartera(fila({ asesor_perfil_id: null, creado_por: 'b' }))).toBe('b')
    expect(duenoDeCartera(fila())).toBeNull()
  })
})

describe('filtrarClientes — búsqueda', () => {
  // La columna Asesor pinta '—' tanto para dueño null como para dueño fuera
  // del roster (alta hecha por un admin del portal, que no es fuerza comercial):
  // el filtro debe tratarlos IGUAL o dos filas idénticas a la vista se
  // comportan distinto (hallazgo de revisión 2026-07-16).
  it("'sin_asesor' atrapa también al dueño que NO está en el roster", () => {
    const roster = new Set(['v-1'])
    const filas = [
      fila({ dni: '00000001', asesor_perfil_id: 'v-1' }),
      fila({ dni: '00000002', asesor_perfil_id: null, creado_por: null }),
      fila({ dni: '00000003', asesor_perfil_id: 'admin-portal' }),
    ]
    expect(filtrarClientes(filas, '', 'sin_asesor', roster).map((f) => f.dni).sort()).toEqual(['00000002', '00000003'])
    expect(filtrarClientes(filas, '', 'v-1', roster).map((f) => f.dni)).toEqual(['00000001'])
    // Sin roster (llamadas viejas): compat — solo el dueño null es 'sin asesor'.
    expect(filtrarClientes(filas, '', 'sin_asesor').map((f) => f.dni)).toEqual(['00000002'])
  })

  const cartera = [
    fila({ nombre_completo: 'ROSA MERCEDES AGUILAR VENTURA', dni: '46801357', correo: 'rosa@correo.pe', telefono: '+51987120345' }),
    fila({ nombre_completo: 'BRUNO ALEXIS FONSECA IPARRAGUIRRE', dni: 'PE1548792', correo: 'bruno@correo.pe', telefono: '+51944870231' }),
    fila({ nombre_completo: 'NADIA SOLEDAD CHOQUE MAMANI', dni: '001987654', correo: null, telefono: null }),
  ]

  it('sin query devuelve todo', () => {
    expect(filtrarClientes(cartera, '', 'todos')).toHaveLength(3)
  })

  it('por nombre, insensible a mayúsculas y acentos ("aguílar" encuentra AGUILAR)', () => {
    expect(filtrarClientes(cartera, 'aguílar', 'todos').map((c) => c.dni)).toEqual(['46801357'])
  })

  it('por documento alfanumérico en minúsculas (pasaporte pe1548)', () => {
    expect(filtrarClientes(cartera, 'pe1548', 'todos').map((c) => c.dni)).toEqual(['PE1548792'])
  })

  it('por correo', () => {
    expect(filtrarClientes(cartera, 'bruno@', 'todos')).toHaveLength(1)
  })

  it('por teléfono con formato distinto: "987 120" encuentra +51987120345', () => {
    expect(filtrarClientes(cartera, '987 120', 'todos').map((c) => c.dni)).toEqual(['46801357'])
  })

  it('campos null no matchean ni revientan', () => {
    expect(filtrarClientes(cartera, 'correo.pe', 'todos')).toHaveLength(2)
  })
})

describe('filtrarClientes — filtro por asesor (compara contra el DUEÑO de cartera)', () => {
  const cartera = [
    fila({ nombre_completo: 'CON ASESOR', asesor_perfil_id: 'v-1', creado_por: 'otro' }),
    fila({ nombre_completo: 'HUERFANA DEL CREADOR', asesor_perfil_id: null, creado_por: 'v-1' }),
    fila({ nombre_completo: 'DE OTRO', asesor_perfil_id: 'v-2', creado_por: 'v-1' }),
    fila({ nombre_completo: 'SIN NADIE', asesor_perfil_id: null, creado_por: null }),
  ]

  it('por perfil_id incluye las filas heredadas por creado_por (misma regla que la columna)', () => {
    expect(filtrarClientes(cartera, '', 'v-1').map((c) => c.nombre_completo)).toEqual([
      'CON ASESOR',
      'HUERFANA DEL CREADOR',
    ])
  })

  it("'sin_asesor' = sin asesor NI creador", () => {
    expect(filtrarClientes(cartera, '', 'sin_asesor').map((c) => c.nombre_completo)).toEqual(['SIN NADIE'])
  })

  it('asesor y búsqueda se componen (AND)', () => {
    expect(filtrarClientes(cartera, 'huerfana', 'v-1')).toHaveLength(1)
    expect(filtrarClientes(cartera, 'de otro', 'v-1')).toHaveLength(0)
  })
})

describe('carteraDelAmbito (recorte DEMO — en real lo hace el servidor)', () => {
  const cartera = [
    fila({ nombre_completo: 'MIA', asesor_perfil_id: 'yo' }),
    fila({ nombre_completo: 'DE MI VENDEDOR', asesor_perfil_id: 'v-1' }),
    fila({ nombre_completo: 'HUERFANA DE MI VENDEDOR', asesor_perfil_id: null, creado_por: 'v-1' }),
    fila({ nombre_completo: 'DEL OTRO EQUIPO', asesor_perfil_id: 'v-9' }),
    fila({ nombre_completo: 'SIN NADIE' }),
  ]

  it('esGlobal (gerencia/directorio) devuelve todo tal cual', () => {
    expect(carteraDelAmbito(cartera, new Set(), true)).toHaveLength(5)
  })

  it('recorta por dueño de cartera dentro del equipo visible', () => {
    const visibles = carteraDelAmbito(cartera, new Set(['yo', 'v-1']), false)
    expect(visibles.map((c) => c.nombre_completo)).toEqual([
      'MIA',
      'DE MI VENDEDOR',
      'HUERFANA DE MI VENDEDOR',
    ])
  })
})

describe('paginar', () => {
  const items = Array.from({ length: 120 }, (_, i) => i + 1)

  it('sin items: 1 página vacía (la pantalla pinta su estado vacío, no NaN)', () => {
    expect(paginar([], 0)).toEqual({ visibles: [], paginas: 1, paginaActual: 0 })
  })

  it('recorta la página pedida (50 por defecto) y calcula el total de páginas', () => {
    const p0 = paginar(items, 0)
    expect(p0.paginas).toBe(3)
    expect(p0.visibles).toHaveLength(CLIENTES_POR_PAGINA)
    expect(p0.visibles[0]).toBe(1)
    const p2 = paginar(items, 2)
    expect(p2.visibles).toHaveLength(20)
    expect(p2.visibles[0]).toBe(101)
  })

  it('página fuera de rango se clampea (tras filtrar, la página 5 puede ya no existir)', () => {
    expect(paginar(items, 99).paginaActual).toBe(2)
    expect(paginar(items, -3).paginaActual).toBe(0)
  })

  it('múltiplo exacto no inventa una página de más', () => {
    expect(paginar(Array.from({ length: 100 }, (_, i) => i), 0).paginas).toBe(2)
  })
})
