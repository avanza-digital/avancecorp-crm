import { describe, expect, it } from 'vitest'
import { criterioDesdeTexto, esBusquedaExacta } from './venta-cruzada'

describe('búsqueda exacta en la Cartera', () => {
  it.each(['70000021', '7000 0021', '987 654 321', '+51 987-654-321', '2026-01-000123', 'AB12345'])('«%s» es un dato exacto', (texto) => {
    expect(esBusquedaExacta(texto)).toBe(true)
  })
  it.each(['Ana', 'Ana López', '12345', 'AB-1', '', '   ', 'ana@correo.pe'])('«%s» no lo es', (texto) => {
    expect(esBusquedaExacta(texto)).toBe(false)
  })
})

describe('criterio para buscar en otras carteras', () => {
  it('8 dígitos es un DNI', () => {
    expect(criterioDesdeTexto(' 7000-0021 ')).toEqual({tipo: 'documento', tipoDocumento: 'DNI', numero: '70000021'})
  })
  it('un celular peruano es un teléfono, con o sin 51', () => {
    expect(criterioDesdeTexto('987 654 321')).toEqual({tipo: 'telefono', telefono: '987654321'})
    expect(criterioDesdeTexto('+51 987654321')).toEqual({tipo: 'telefono', telefono: '51987654321'})
  })
  it('otros solo dígitos son un carné de extranjería; con letras, un pasaporte', () => {
    expect(criterioDesdeTexto('001234567')).toEqual({tipo: 'documento', tipoDocumento: 'CE', numero: '001234567'})
    expect(criterioDesdeTexto('ab123456')).toEqual({tipo: 'documento', tipoDocumento: 'PASAPORTE', numero: 'AB123456'})
  })
  it('un número de contrato o un nombre no se ofrecen', () => {
    expect(criterioDesdeTexto('2026-01-000123')).toBeUndefined()
    expect(criterioDesdeTexto('Ana López')).toBeUndefined()
  })
})
