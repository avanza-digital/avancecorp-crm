// lib/cadencia.ts — la SALIDA de la cadencia de seguimiento.
//
// El motor (`motor-siguiente.ts`) siempre propone otro toque: llamada fallida →
// WhatsApp mañana, WhatsApp sin respuesta → llamada. Es la regla de oro y
// funciona… hasta que el cliente no responde NUNCA. Ahí la cadencia se vuelve
// un bucle: el lead consume un toque cada dos días para siempre, nadie lo
// cierra, y el embudo se llena de zombis que inflan el capital "en proceso".
//
// Esto detecta el plantón y PROPONE cerrar. Nunca cierra solo: en este CRM nada
// descarta sin que una persona lo confirme, y menos por un contador.
import { diasDesdeReferencia } from './inteligencia'
import { evidenciaNoResponde } from './descarte-evidencia'
import type { Actividad } from './tipos'

/**
 * Intentos sin respuesta a partir de los cuales el motor deja de proponer otro
 * toque. Cinco, porque con la cadencia D1/D3 ya construida el 5º toque cae a
 * ~8-10 días del primero: por debajo de eso la industria sigue contactando.
 */
export const INTENTOS_PARA_PROPONER_CIERRE = 5

/**
 * Días MÍNIMOS que debe llevar abierta la racha. Sin este segundo umbral, cinco
 * taps de "No contestó" en una misma tarde —cada tap desde la cola escribe una
 * actividad— propondrían cerrar un lead asignado esta mañana. Tres días es el
 * mismo plazo que la BD da a `contactado` (72 h en `private.umbral_estancamiento`).
 */
export const DIAS_PARA_PROPONER_CIERRE = 3

export interface Planton {
  /** Intentos sin respuesta del tramo vigente. */
  intentos: number
  /** Días desde el primer intento del tramo. */
  dias: number
}

/**
 * ¿Este lead ya agotó la cadencia? `null` = seguir insistiendo.
 *
 * El tramo se cuenta desde la ÚLTIMA CONVERSACIÓN (ver `evidenciaNoResponde`):
 * si el cliente respondió en algún momento, el contador vuelve a cero. "No
 * responde" describe la racha vigente, no la vida entera del lead.
 */
export function plantonDe(acts: readonly Actividad[], ahora: number): Planton | null {
  const { intentos, desde } = evidenciaNoResponde(acts)
  if (intentos < INTENTOS_PARA_PROPONER_CIERRE || desde == null) return null
  const dias = diasDesdeReferencia(desde, ahora)
  if (dias < DIAS_PARA_PROPONER_CIERRE) return null
  return { intentos, dias }
}
