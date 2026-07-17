// Tests de los helpers puros de la pantalla Contratos: búsqueda normalizada
// (N° de contrato / cliente) y filtro por estado, compuestos en AND — misma
// convención que clientes-vista.test.ts (fábrica de filas + describes es-PE).
import { describe, expect, it } from 'vitest'
import { filtrarContratos, type ContratoBuscable } from './contratos-vista'

/** Fila mínima buscable — cada test pisa solo lo que le importa. */
function fila(sobre: Partial<ContratoBuscable> = {}): ContratoBuscable {
  return {
    numero_contrato: '2026-01-000123',
    cliente_nombre: 'CLIENTE DE PRUEBA',
    estado: 'activo',
    ...sobre,
  }
}

const cartera = [
  fila({ numero_contrato: '2026-01-000111', cliente_nombre: 'ROSA MERCEDES AGUILAR VENTURA' }),
  fila({ numero_contrato: '2026-01-000222', cliente_nombre: 'JOSÉ ÑAÑEZ GÜISADO', estado: 'vencido' }),
  // Numeración VIEJA del portal + embed oculto por la RLS (cliente_nombre null).
  fila({ numero_contrato: 'AC-2026-0042', cliente_nombre: null, estado: 'renovado' }),
]

describe('filtrarContratos — búsqueda', () => {
  it('sin query devuelve todo', () => {
    expect(filtrarContratos(cartera, '', 'todos')).toHaveLength(3)
    expect(filtrarContratos(cartera, '   ', 'todos')).toHaveLength(3)
  })

  it('por N° de contrato parcial (solo los 6 dígitos alcanzan)', () => {
    expect(filtrarContratos(cartera, '000222', 'todos').map((k) => k.numero_contrato)).toEqual([
      '2026-01-000222',
    ])
    expect(filtrarContratos(cartera, '2026-01-000111', 'todos')).toHaveLength(1)
  })

  it('la numeración vieja alfanumérica también matchea, insensible a mayúsculas', () => {
    expect(filtrarContratos(cartera, 'ac-2026', 'todos').map((k) => k.numero_contrato)).toEqual([
      'AC-2026-0042',
    ])
  })

  it('por nombre del cliente, insensible a mayúsculas y acentos ("ñañez" encuentra ÑAÑEZ)', () => {
    expect(filtrarContratos(cartera, 'ñañez', 'todos').map((k) => k.numero_contrato)).toEqual([
      '2026-01-000222',
    ])
    expect(filtrarContratos(cartera, 'aguílar', 'todos')).toHaveLength(1)
  })

  it('cliente_nombre null no matchea ni revienta', () => {
    expect(filtrarContratos(cartera, 'rosa', 'todos').map((k) => k.numero_contrato)).toEqual([
      '2026-01-000111',
    ])
  })

  it('sin coincidencias devuelve vacío (la pantalla pinta "Sin resultados")', () => {
    expect(filtrarContratos(cartera, 'nadie-con-este-numero', 'todos')).toHaveLength(0)
  })
})

describe('filtrarContratos — filtro por estado', () => {
  it("'todos' no recorta; un estado deja solo sus filas", () => {
    expect(filtrarContratos(cartera, '', 'todos')).toHaveLength(3)
    expect(filtrarContratos(cartera, '', 'vencido').map((k) => k.numero_contrato)).toEqual([
      '2026-01-000222',
    ])
    expect(filtrarContratos(cartera, '', 'retirado')).toHaveLength(0)
  })

  it('estado y búsqueda se componen (AND)', () => {
    expect(filtrarContratos(cartera, 'ñañez', 'vencido')).toHaveLength(1)
    expect(filtrarContratos(cartera, 'ñañez', 'activo')).toHaveLength(0)
    expect(filtrarContratos(cartera, 'rosa', 'activo')).toHaveLength(1)
  })
})
