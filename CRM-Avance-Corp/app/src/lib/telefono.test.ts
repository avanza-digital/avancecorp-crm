// Contrato de los enlaces de contacto. Lo que se protege aquí es que el CRM
// nunca mande a marcar a otro país: en la base hay números guardados sin
// código de país, y "arreglarlos" poniéndoles un `+` delante los convierte en
// un prefijo internacional que no es Perú.
import { describe, expect, it } from 'vitest'
import { enlaceTel, numeroWhatsapp, soloDigitos } from './telefono'

describe('soloDigitos — una sola forma de limpiar un teléfono', () => {
  it.each([
    ['+51 987 654 321', '51987654321'],
    ['987-654-321', '987654321'],
    ['(01) 555 1234', '015551234'],
    ['+51987654321', '51987654321'],
  ])('%s → %s', (entrada, esperado) => {
    expect(soloDigitos(entrada)).toBe(esperado)
  })

  it.each([null, undefined, ''])('%p no revienta: devuelve cadena vacía', (v) => {
    expect(soloDigitos(v)).toBe('')
  })
})

describe('enlaceTel — el marcador del celular', () => {
  it('conserva el + cuando el dato YA venía en formato internacional', () => {
    expect(enlaceTel('+51987654321')).toBe('tel:+51987654321')
  })

  it('NO inventa el + en un número local — ese es el bug que marcaría a otro país', () => {
    // `tel:+999888777` no es Perú. Sin `+`, la red del celular lo resuelve
    // como local, que es justo lo que se quiere.
    expect(enlaceTel('999888777')).toBe('tel:999888777')
  })

  it('limpia separadores sin perder el prefijo internacional', () => {
    expect(enlaceTel('+51 987-654 321')).toBe('tel:+51987654321')
  })

  it.each([null, undefined, '', '  ', '12345', 'sin-numero'])(
    'un número inutilizable (%p) da null, no un enlace roto',
    (v) => {
      expect(enlaceTel(v)).toBeNull()
    },
  )
})

describe('numeroWhatsapp — wa.me exige dígitos pelados', () => {
  it('quita el + y TAMBIÉN los separadores', () => {
    // El criterio viejo era `replace('+','')`, que dejaba espacios y guiones
    // dentro de la URL de wa.me.
    expect(numeroWhatsapp('+51 987-654 321')).toBe('51987654321')
  })

  it.each([null, undefined, '', '12345'])('un número inutilizable (%p) da null', (v) => {
    expect(numeroWhatsapp(v)).toBeNull()
  })
})
