import { describe, expect, it, vi } from 'vitest'
import { registrarError } from './observabilidad'

describe('observabilidad segura', () => {
  it('retira credenciales y PII antes de escribir un evento', () => {
    const consola = vi.spyOn(console, 'error').mockImplementation(() => undefined)

    registrarError(
      'prueba.segura',
      new Error('falló usuario@avancecorp.pe con +51 999 888 777'),
      {
        email: 'usuario@avancecorp.pe',
        cabecera: 'Bearer abc.def-ghi',
        telefono: '+51999888777',
      },
    )

    const salida = JSON.stringify(consola.mock.calls)
    expect(salida).not.toContain('usuario@avancecorp.pe')
    expect(salida).not.toContain('999888777')
    expect(salida).not.toContain('abc.def-ghi')
    expect(salida).toContain('REDACTADO')
  })
})
