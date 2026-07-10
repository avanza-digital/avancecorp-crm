export const DEMO_SESSION_KEY = 'ac-crm-demo'
export const AUTH_CLEARED_EVENT = 'ac:auth-cleared'

export function leerSesionDemo(): string | null {
  try {
    return window.sessionStorage.getItem(DEMO_SESSION_KEY)
  } catch {
    return null
  }
}

export function guardarSesionDemo(valor: string): boolean {
  try {
    window.sessionStorage.setItem(DEMO_SESSION_KEY, valor)
    return true
  } catch {
    return false
  }
}

export function limpiarSesionDemo(): boolean {
  try {
    const existia = window.sessionStorage.getItem(DEMO_SESSION_KEY) !== null
    window.sessionStorage.removeItem(DEMO_SESSION_KEY)
    return existia
  } catch {
    return false
  }
}

/**
 * Contrato desacoplado con la capa de datos: el QueryClient escucha este evento
 * y elimina inmediatamente cualquier respuesta perteneciente al acceso anterior.
 */
export function notificarAuthLimpia(): void {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(AUTH_CLEARED_EVENT))
}

export function normalizarCorreo(correo: string): string {
  return correo.trim().toLocaleLowerCase('es-PE').slice(0, 254)
}

export function esSesionAusente(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false
  const dato = error as { name?: unknown; code?: unknown; message?: unknown }
  const nombre = typeof dato.name === 'string' ? dato.name : ''
  const codigo = typeof dato.code === 'string' ? dato.code : ''
  const mensaje = typeof dato.message === 'string' ? dato.message : ''
  return nombre === 'AuthSessionMissingError'
    || codigo === 'session_not_found'
    || /auth session missing/i.test(mensaje)
}

export function mensajeSeguroDeLogin(error: unknown): string {
  const mensaje = error && typeof error === 'object' && 'message' in error
    ? String((error as { message?: unknown }).message ?? '')
    : ''

  if (/invalid login|invalid credentials/i.test(mensaje)) return 'Correo o contraseña incorrectos'
  if (/email not confirmed/i.test(mensaje)) return 'Tu correo todavía no está confirmado'
  if (/rate limit|too many requests|over_email_send_rate_limit/i.test(mensaje)) {
    return 'Demasiados intentos. Espera unos minutos y vuelve a intentar.'
  }
  if (/failed to fetch|network|timeout|timed out/i.test(mensaje)) {
    return 'No pudimos conectar con el servicio. Revisa tu conexión e inténtalo de nuevo.'
  }
  return 'No pudimos iniciar sesión. Inténtalo de nuevo.'
}
