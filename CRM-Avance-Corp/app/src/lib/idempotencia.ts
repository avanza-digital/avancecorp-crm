/**
 * Clave de idempotencia de una escritura: un uuid v4 canónico por INTENTO.
 *
 * Quien la usa la genera una vez por intento de formulario y manda la MISMA en
 * cada reintento; el servidor, si ya registró esa escritura para ese actor,
 * devuelve el resultado anterior en vez de repetirla. Así un «error» que en
 * realidad fue un éxito mal leído (red, timeout, o el front rechazando una
 * respuesta válida, como el 05/09/2026 con los contratos) no crea un duplicado.
 *
 * `crypto.randomUUID` existe en todo navegador con https y en Node ≥ 19; el
 * respaldo con `getRandomValues` cubre arneses sin él. El servidor la castea a
 * `uuid`, así que el formato tiene que ser canónico (8-4-4-4-12, minúsculas).
 */
export function nuevaClaveIdempotencia(): string {
  const cripto = globalThis.crypto
  if (typeof cripto?.randomUUID === 'function') return cripto.randomUUID()
  if (typeof cripto?.getRandomValues !== 'function') {
    throw new Error('Este navegador no puede generar una clave de idempotencia segura')
  }
  const bytes = new Uint8Array(16)
  cripto.getRandomValues(bytes)
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x40 // versión 4
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80 // variante RFC 4122
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

/** Mismo criterio que el `::uuid` del servidor: canónico, en minúsculas. */
export const RE_CLAVE_IDEMPOTENCIA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
