// Reglas de la cartera keyset (F2). Lo que se prueba aquí NO es "el filtro
// funciona": es que el espejo demo y el WHERE del servidor digan lo MISMO. Cada
// divergencia entre ambos es una demo que enseña un producto que no existe.
import { describe, expect, it } from 'vitest'
import {
  MIN_DIGITOS_BUSQUEDA,
  MIN_TEXTO_BUSQUEDA,
  coincideTextoCartera,
  concatenarPaginas,
  filtrarCarteraLocal,
  normalizarBusquedaCartera,
  ordenarCarteraLocal,
  textoBuscable,
} from './cartera-keyset'
import type { Lead } from './tipos'

function lead(over: Partial<Lead> = {}): Lead {
  return {
    id: 'lead-1',
    nombre_completo: 'ROSA QUISPE',
    telefono: '987654321',
    etapa: 'nuevo',
    origen: 'landing',
    monto_estimado: 1000,
    moneda: 'PEN',
    vendedor_id: 'v-1',
    creado_en: '2026-08-01T10:00:00.000Z',
    actualizado_en: '2026-08-01T10:00:00.000Z',
    activo: true,
    ...over,
  }
}

function leadSinSello(over: Partial<Lead> = {}): Lead {
  const { actualizado_en: _sello, ...resto } = lead(over)
  return resto
}

describe('normalizarBusquedaCartera', () => {
  it('separa el texto de los dígitos y colapsa el ruido', () => {
    expect(normalizarBusquedaCartera('  José  María!! 987-654-321 ')).toEqual({
      texto: 'José María 987-654-321',
      digitos: '987654321',
    })
  })

  it('acota el texto a 80 caracteres y los dígitos a 15', () => {
    const { texto, digitos } = normalizarBusquedaCartera('a'.repeat(200))
    expect(texto).toHaveLength(80)
    expect(digitos).toBe('')
    expect(normalizarBusquedaCartera('1'.repeat(30)).digitos).toHaveLength(15)
  })
})

describe('textoBuscable', () => {
  it('no aplica filtro por debajo del mínimo (el servidor lo rechazaría con 22023)', () => {
    expect(textoBuscable('')).toBeNull()
    expect(textoBuscable('a')).toBeNull()
    expect(MIN_TEXTO_BUSQUEDA).toBe(2)
  })

  it('devuelve el texto normalizado a partir del mínimo', () => {
    expect(textoBuscable(' ro ')).toBe('ro')
  })
})

describe('coincideTextoCartera', () => {
  const rosa = lead({ nombre_completo: 'ROSA QUISPE', telefono: '987654321', dni: '12345678' })

  it('sin texto buscable deja pasar todo', () => {
    expect(coincideTextoCartera(rosa, 'a')).toBe(true)
  })

  it('encuentra por nombre sin distinguir mayúsculas', () => {
    expect(coincideTextoCartera(rosa, 'rosa')).toBe(true)
    expect(coincideTextoCartera(rosa, 'quispe')).toBe(true)
    expect(coincideTextoCartera(rosa, 'mendoza')).toBe(false)
  })

  it('teléfono y DNI SOLO desde 3 dígitos (divergencia deliberada del filtro viejo)', () => {
    expect(MIN_DIGITOS_BUSQUEDA).toBe(3)
    // '98' son 2 dígitos: no busca por teléfono, y como texto tampoco está en
    // el nombre — con la regla vieja (1 dígito) esto habría dado true.
    expect(coincideTextoCartera(rosa, '98')).toBe(false)
    expect(coincideTextoCartera(rosa, '987')).toBe(true)
    expect(coincideTextoCartera(rosa, '345678')).toBe(true)
  })
})

describe('filtrarCarteraLocal', () => {
  const leads = [
    lead({ id: 'a', etapa: 'nuevo', vendedor_id: 'v-1' }),
    lead({ id: 'b', etapa: 'convertido', vendedor_id: 'v-2', nombre_completo: 'LUIS PEÑA' }),
    lead({ id: 'c', etapa: 'nuevo', vendedor_id: null, nombre_completo: 'ANA TORRES' }),
  ]

  it('«todas»/«todos» no recortan nada', () => {
    expect(filtrarCarteraLocal(leads, { etapa: 'todas', vendedorId: 'todos' })).toHaveLength(3)
  })

  it('filtra por etapa', () => {
    expect(filtrarCarteraLocal(leads, { etapa: 'convertido' }).map((l) => l.id)).toEqual(['b'])
  })

  it('«sin_asignar» son los parkeados, no los de un analista cualquiera', () => {
    expect(filtrarCarteraLocal(leads, { vendedorId: 'sin_asignar' }).map((l) => l.id)).toEqual(['c'])
  })

  it('filtra por analista concreto', () => {
    expect(filtrarCarteraLocal(leads, { vendedorId: 'v-2' }).map((l) => l.id)).toEqual(['b'])
  })

  it('combina filtros con la búsqueda', () => {
    expect(filtrarCarteraLocal(leads, { etapa: 'nuevo', texto: 'ana' }).map((l) => l.id))
      .toEqual(['c'])
  })

  it('un lead soft-borrado (activo=false) queda fuera de la cartera operativa', () => {
    const conBorrado = [...leads, lead({ id: 'z', activo: false, nombre_completo: 'BORRADO' })]
    expect(filtrarCarteraLocal(conBorrado, {}).map((l) => l.id)).not.toContain('z')
    // Ni siquiera buscándolo por su nombre: el filtro es del ámbito, no del texto.
    expect(filtrarCarteraLocal(conBorrado, { texto: 'BORRADO' })).toEqual([])
  })

  it('un lead DESCARTADO sí sigue en la cartera (etapa ≠ soft-delete)', () => {
    const descartado = lead({ id: 'd', etapa: 'descartado', motivo_descarte: 'sin_interes' })
    expect(filtrarCarteraLocal([descartado], {}).map((l) => l.id)).toEqual(['d'])
  })
})

describe('ordenarCarteraLocal', () => {
  it('ordena por actualizado_en desc y desempata por id asc (el orden del keyset)', () => {
    const mismos = [
      lead({ id: 'z', actualizado_en: '2026-08-01T10:00:00.000Z' }),
      lead({ id: 'a', actualizado_en: '2026-08-01T10:00:00.000Z' }),
      lead({ id: 'm', actualizado_en: '2026-08-02T10:00:00.000Z' }),
    ]
    expect(ordenarCarteraLocal(mismos).map((l) => l.id)).toEqual(['m', 'a', 'z'])
  })

  it('degrada a creado_en cuando el lead demo no trae actualizado_en', () => {
    // Sin la clave, no con la clave a `undefined`: es como llega un lead demo.
    const sinSello = [
      leadSinSello({ id: 'viejo', creado_en: '2026-01-01T00:00:00.000Z' }),
      leadSinSello({ id: 'nuevo', creado_en: '2026-07-01T00:00:00.000Z' }),
    ]
    expect(ordenarCarteraLocal(sinSello).map((l) => l.id)).toEqual(['nuevo', 'viejo'])
  })

  it('no muta el array recibido', () => {
    const original = [lead({ id: 'b' }), lead({ id: 'a' })]
    ordenarCarteraLocal(original)
    expect(original.map((l) => l.id)).toEqual(['b', 'a'])
  })
})

describe('concatenarPaginas', () => {
  it('un lead que migró de página aparece UNA sola vez', () => {
    const p1 = [lead({ id: 'a' }), lead({ id: 'b' })]
    const p2 = [lead({ id: 'b' }), lead({ id: 'c' })]
    expect(concatenarPaginas([p1, p2]).map((l) => l.id)).toEqual(['a', 'b', 'c'])
  })

  it('conserva el orden de llegada de las páginas', () => {
    expect(concatenarPaginas([[lead({ id: 'x' })], [lead({ id: 'y' })]]).map((l) => l.id))
      .toEqual(['x', 'y'])
  })

  it('sin páginas devuelve lista vacía', () => {
    expect(concatenarPaginas([])).toEqual([])
  })
})
