// lib/descarte-evidencia.ts — «No responde» hay que haberlo intentado.
//
// Pedido de Miguel (2026-07-25): hoy el diálogo deja elegir «No responde» sobre
// un lead que NADIE llamó nunca. Ese motivo no es una opinión, es una
// AFIRMACIÓN DE HECHO sobre el cliente: sin intentos registrados es falsa, y
// encima ensucia la métrica con la que se decide de dónde traer leads (un
// origen bueno aparece como "no responde" cuando en realidad nadie lo trabajó).
//
// ⚠️ ALCANCE: SUPERFICIE DEL VENDEDOR (el diálogo de la ficha y el gate del
// store que lo respalda). NO es un invariante del dato y NO debe convertirse en
// CHECK ni trigger de `crm.leads`. Rosa (coordinador) cierra leads de la COLA
// GLOBAL con `crm.descartar_lead` — leads sin dueño y SIN NINGUNA actividad,
// donde «No responde» es legítimo. Una regla dura en BD la dejaría sin poder
// descartar, con un error de Postgres que su pantalla no sabe traducir, y
// rompería además la idempotencia y el deshacer de 24 h de esa RPC. Por aquí no
// pasa nunca: su ámbito de leads es ∅ y su pantalla no monta la ficha.
import {
  TIPOS_CONTACTO_K,
  TIPOS_CONVERSACION_K,
  type Actividad,
  type MotivoDescarte,
} from './tipos'

/** Intentos SIN respuesta que exige «No responde». Único knob: la copy lo
 *  interpola, el número jamás se escribe a mano. */
export const INTENTOS_MIN_NO_RESPONDE = 2

/** Motivos que afirman un HECHO verificable en el timeline. Hoy solo uno. */
export const MOTIVOS_CON_EVIDENCIA: ReadonlySet<MotivoDescarte> =
  new Set<MotivoDescarte>(['no_responde'])

export interface EvidenciaNoResponde {
  /** Contactos del asesor sin respuesta POSTERIORES a la última conversación. */
  intentos: number
  /** ¿El cliente respondió alguna vez? Marca desde dónde se cuenta. */
  huboConversacion: boolean
  /** ISO del intento MÁS VIEJO del tramo, o null si no hay ninguno. Mide cuánto
   *  lleva abierta la racha — cinco taps en una tarde no son una racha. */
  desde: string | null
}

/**
 * Intentos sin respuesta que sostienen (o no) un «No responde».
 *
 * Dos filtros, los dos necesarios:
 *  · TIPOS_CONTACTO menos TIPOS_CONVERSACION. `nota` queda fuera porque ya está
 *    fuera de TIPOS_CONTACTO: escribir "llamé y no contestó" en una nota NO es
 *    haber llamado. `reasignacion` y `cambio_etapa` quedan fuera por lo mismo
 *    que documenta `indexarUltimoContacto`: las emite el SISTEMA, y contarlas
 *    dejaría pasar a TODO lead del circuito Rosa → supervisor → vendedor, que
 *    llega con su `reasignacion` puesta. La guarda quedaría de adorno.
 *  · POSTERIORES a la última conversación. Sin esto se podría descartar por «no
 *    responde» a quien contestó ayer: dos intentos viejos más un
 *    `whatsapp_recibido` de hace una hora pasarían el corte.
 *
 * No depende del ORDEN de entrada (el store antepone las optimistas y
 * `actividadesDe` entrega DESC): ordena por timestamp, no por posición. Una
 * fecha corrupta NO cuenta — fail-closed: esto jamás inventa evidencia.
 */
export function evidenciaNoResponde(acts: readonly Actividad[]): EvidenciaNoResponde {
  let ultimaConversacion = Number.NEGATIVE_INFINITY
  for (const a of acts) {
    if (!TIPOS_CONVERSACION_K.has(a.tipo)) continue
    const t = Date.parse(a.creado_en)
    if (Number.isFinite(t) && t > ultimaConversacion) ultimaConversacion = t
  }
  let intentos = 0
  let desde: string | null = null
  for (const a of acts) {
    if (!TIPOS_CONTACTO_K.has(a.tipo) || TIPOS_CONVERSACION_K.has(a.tipo)) continue
    const t = Date.parse(a.creado_en)
    if (!Number.isFinite(t)) continue
    if (t <= ultimaConversacion) continue
    intentos += 1
    if (desde == null || a.creado_en < desde) desde = a.creado_en
  }
  return { intentos, huboConversacion: Number.isFinite(ultimaConversacion), desde }
}

/**
 * Razón por la que «No responde» NO se puede elegir todavía, o `null` si sí.
 *
 * Devuelve texto listo para pintar: el diálogo lo muestra bajo el select y el
 * store lo reutiliza como mensaje del toast, para que la superficie y su gate
 * digan EXACTAMENTE lo mismo (nada de dos redacciones que se desincronizan).
 */
export function vetoNoResponde(acts: readonly Actividad[]): string | null {
  const { intentos, huboConversacion } = evidenciaNoResponde(acts)
  if (intentos >= INTENTOS_MIN_NO_RESPONDE) return null
  const faltan = INTENTOS_MIN_NO_RESPONDE - intentos
  const cola = `Registra ${faltan} ${faltan === 1 ? 'intento más' : 'intentos'} (llamada o WhatsApp) y vuelve.`
  if (huboConversacion && intentos === 0) {
    return `«No responde» está deshabilitado: el cliente SÍ respondió — la última señal del timeline es suya. Si dejó de contestar, ${cola.toLowerCase()}`
  }
  if (intentos === 0) {
    return `«No responde» está deshabilitado: este lead no tiene ningún intento de contacto registrado. ${cola}`
  }
  return `«No responde» está deshabilitado: llevas ${intentos} de ${INTENTOS_MIN_NO_RESPONDE} intentos registrados. ${cola}`
}

/** Sufijo corto para la `<option>` deshabilitada (tiene que caber en un select). */
export const VETO_CORTO = `requiere ${INTENTOS_MIN_NO_RESPONDE} intentos registrados`
