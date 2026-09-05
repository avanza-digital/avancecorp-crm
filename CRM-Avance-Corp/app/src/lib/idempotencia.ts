/**
 * Claves de idempotencia de una escritura: un uuid v4 canónico por INTENTO.
 *
 * Quien la usa la genera una vez por intento y manda la MISMA en cada reintento;
 * el servidor, si ya registró esa escritura para ese actor con los mismos datos,
 * devuelve el resultado anterior en vez de repetirla. Así un «error» que en
 * realidad fue un éxito mal leído (red, timeout, o el front rechazando una
 * respuesta válida, como el 05/09/2026 con los contratos) no crea un duplicado.
 *
 * La clave pendiente se guarda en `localStorage` por ÁMBITO (p. ej. el cliente):
 * sobrevive a que el modal se desmonte con la llamada en vuelo (Esc, clic fuera),
 * a una recarga y a dos pestañas del mismo navegador (Codex, 05/09). Solo se
 * libera cuando el servidor confirmó la escritura o cuando el servidor dijo que
 * ese intento ya no tiene sentido. Sin almacenamiento (privado, bloqueado) cae a
 * una memoria del proceso: protege al menos dentro de la misma pestaña.
 */

const PREFIJO = 'crm.idempotencia.'
const memoria = new Map<string, string>()

/** Mismo criterio que el `::uuid` del servidor: canónico, en minúsculas. */
export const RE_CLAVE_IDEMPOTENCIA = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/

/**
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

function leerGuardada(ambito: string): string | null {
  try {
    const valor = globalThis.localStorage?.getItem(PREFIJO + ambito) ?? null
    if (valor && RE_CLAVE_IDEMPOTENCIA.test(valor)) return valor
  } catch {
    // Sin almacenamiento: se sigue con la memoria del proceso.
  }
  const enMemoria = memoria.get(ambito)
  return enMemoria && RE_CLAVE_IDEMPOTENCIA.test(enMemoria) ? enMemoria : null
}

function guardar(ambito: string, clave: string): void {
  memoria.set(ambito, clave)
  try {
    globalThis.localStorage?.setItem(PREFIJO + ambito, clave)
  } catch {
    // Almacenamiento bloqueado o lleno: la memoria del proceso ya la tiene.
  }
}

/**
 * La clave del intento PENDIENTE de este ámbito: la que quedó guardada si hubo un
 * intento sin confirmar, o una nueva (que queda guardada) si no la hay.
 */
export function claveIdempotenciaPendiente(ambito: string): string {
  const guardada = leerGuardada(ambito)
  if (guardada) return guardada
  const clave = nuevaClaveIdempotencia()
  guardar(ambito, clave)
  return clave
}

/** El servidor confirmó (o descartó) el intento: la siguiente escritura es OTRO intento. */
export function liberarClaveIdempotencia(ambito: string): void {
  memoria.delete(ambito)
  try {
    globalThis.localStorage?.removeItem(PREFIJO + ambito)
  } catch {
    // Nada que liberar en el almacenamiento.
  }
}
