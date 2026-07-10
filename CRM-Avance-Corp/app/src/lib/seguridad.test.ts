import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  AUTH_CLEARED_EVENT,
  esSesionAusente,
  guardarSesionDemo,
  leerSesionDemo,
  limpiarSesionDemo,
  mensajeSeguroDeLogin,
  normalizarCorreo,
  notificarAuthLimpia,
} from './seguridad'

describe('seguridad de autenticación', () => {
  beforeEach(() => window.sessionStorage.clear())

  it('encapsula y limpia la sesión demo en sessionStorage', () => {
    expect(guardarSesionDemo('{"rol":"vendedor"}')).toBe(true)
    expect(leerSesionDemo()).toBe('{"rol":"vendedor"}')
    expect(limpiarSesionDemo()).toBe(true)
    expect(leerSesionDemo()).toBeNull()
    expect(limpiarSesionDemo()).toBe(false)
  })

  it('normaliza el correo y limita su longitud', () => {
    expect(normalizarCorreo('  USUARIO@AVANCECORP.PE  ')).toBe('usuario@avancecorp.pe')
    expect(normalizarCorreo('A'.repeat(300))).toHaveLength(254)
  })

  it('no expone mensajes internos del proveedor al usuario', () => {
    expect(mensajeSeguroDeLogin(new Error('Invalid login credentials')))
      .toBe('Correo o contraseña incorrectos')
    expect(mensajeSeguroDeLogin(new Error('internal SQL detail: secret-value')))
      .toBe('No pudimos iniciar sesión. Inténtalo de nuevo.')
  })

  it('distingue una sesión ausente de otros errores', () => {
    expect(esSesionAusente({ name: 'AuthSessionMissingError' })).toBe(true)
    expect(esSesionAusente({ code: 'session_not_found' })).toBe(true)
    expect(esSesionAusente(new Error('network unavailable'))).toBe(false)
  })

  it('notifica a la capa de datos para borrar su caché', () => {
    const listener = vi.fn()
    window.addEventListener(AUTH_CLEARED_EVENT, listener)
    notificarAuthLimpia()
    window.removeEventListener(AUTH_CLEARED_EVENT, listener)
    expect(listener).toHaveBeenCalledOnce()
  })
})
