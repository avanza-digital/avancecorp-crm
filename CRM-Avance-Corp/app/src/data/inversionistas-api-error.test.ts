import { describe, expect, it } from 'vitest'
import * as v from 'valibot'
import { CrmApiError } from './crm-api'
import { respuestaInversionistas } from './inversionistas-api'

describe('errores mostrables de cartera y postventa', () => {
  it.each(['', undefined])('traduce el fallo de transporte con código %s', (code) => {
    try {
      respuestaInversionistas(v.unknown(), { data: null, error: { ...(code === undefined ? {} : { code }), message: 'TypeError: Failed to fetch' } })
      expect.fail('Debió informar el fallo de transporte')
    } catch (error) {
      expect(error).toBeInstanceOf(CrmApiError)
      expect(error).toMatchObject({ code: 'RESPUESTA_NO_RECIBIDA', message: 'No se pudo recibir la respuesta del servidor. Comprueba tu conexión.' })
    }
  })
  it('conserva el código y detalle de un rechazo explícito del servidor', () => {
    expect(() => respuestaInversionistas(v.unknown(), { data: null, error: { code: 'P0409', message: 'La solicitud cambió. Vuelve a consultarla.' } }))
      .toThrow('La solicitud cambió. Vuelve a consultarla.')
  })
})
