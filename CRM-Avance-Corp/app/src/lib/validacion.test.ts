import { describe, expect, it } from 'vitest'
import { normalizarTelefono } from './validacion'

describe('normalizarTelefono', () => {
  it.each([
    ['999 888 777', '+51999888777'],
    ['+51 999-888-777', '+51999888777'],
    ['(999) 888.777', '+51999888777'],
  ])('normaliza %s', (entrada, esperado) => {
    expect(normalizarTelefono(entrada)).toBe(esperado)
  })

  it.each(['', '12345678', '+5199988877', '+52999888777', 'javascript:alert(1)'])(
    'rechaza %s',
    (entrada) => expect(normalizarTelefono(entrada)).toBeNull(),
  )
})
