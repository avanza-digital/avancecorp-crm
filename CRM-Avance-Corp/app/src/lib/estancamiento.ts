// lib/estancamiento.ts — el semáforo por ETAPA de la tarjeta del kanban.
//
// Hoy la card pinta los días desde `creado_en` en gris, siempre igual: un lead
// que lleva 6 días en "Propuesta enviada" (dentro de su plazo) se ve idéntico a
// uno que lleva 6 días en "Nuevo" (seis veces por encima del suyo). El asesor
// tiene que saberse los umbrales de memoria para leer su propio tablero.
//
// DOS DECISIONES DE FONDO, las dos obligatorias:
//
// 1. UN SOLO RELOJ. La referencia sale de `referenciaEspera` (lib/inteligencia),
//    la MISMA que usa la cola de acción — no una copia. Dos fórmulas gemelas
//    divergen, y entonces Hoy y Pipeline dan días distintos sobre el mismo lead.
//
// 2. EL NÚMERO CAMBIA CON EL COLOR. La card mostraba días desde `creado_en`,
//    que es el reloj del CLIENTE; el umbral es del ASESOR. Dejar el número viejo
//    al lado de un punto rojo calculado con otro reloj hace que la card mienta
//    por adyacencia (el ojo lee "rojo por ESE número"). Con el circuito vivo
//    —origen → hoja → cola de Rosa → bandeja → vendedor— un lead pasa días
//    antes de llegar a un asesor: ese es justo el bug que ya se corrigió en la
//    cola el 2026-07-24.
import { SEMAFORO } from './semaforo'
import { referenciaEspera, diasDesdeReferencia, type IndiceUltimaActividad } from './inteligencia'
import type { Etapa, Lead } from './tipos'

const HORA_MS = 3_600_000

/**
 * ESPEJO EXACTO de `private.umbral_estancamiento(text)`.
 *
 * Si allá cambia, cambia aquí (y al revés): son la misma regla, y de ella viven
 * a la vez el color de esta card y las métricas de distribución del servidor.
 * Las etapas terminales no tienen umbral: un lead cerrado no se estanca.
 */
export const UMBRAL_ETAPA_MS: Partial<Record<Etapa, number>> = {
  nuevo: 24 * HORA_MS,
  contactado: 72 * HORA_MS,
  reunion_agendada: 72 * HORA_MS,
  propuesta_enviada: 120 * HORA_MS,
}

/** Plazo de cada etapa en texto, DERIVADO del umbral — nunca escrito a mano. */
export const UMBRAL_DIAS_TXT: Partial<Record<Etapa, string>> = Object.fromEntries(
  Object.entries(UMBRAL_ETAPA_MS).map(([k, ms]) => {
    const horas = (ms ?? 0) / HORA_MS
    return [k, horas < 48 ? `${horas} h` : `${horas / 24} d`]
  }),
)

export interface SemaforoEtapa {
  /** Días (con fracción) desde la referencia del ASESOR. */
  dias: number
  /** Color del punto, o `null` si esa etapa no tiene umbral (terminales). */
  color: string | null
  /** ¿Cruzó el umbral de SU etapa? */
  estancado: boolean
}

/**
 * Semáforo de una card: azul dentro de plazo · ámbar pasado el umbral · rojo al
 * doble. El escalón del doble existe para que un lead a 5 días en `nuevo`
 * (5× su umbral) no se vea igual que uno a 25 h.
 */
export function semaforoEstancamiento(
  lead: Lead,
  indice: IndiceUltimaActividad,
  ahora: number,
): SemaforoEtapa {
  const dias = diasDesdeReferencia(referenciaEspera(lead, indice), ahora)
  const umbral = UMBRAL_ETAPA_MS[lead.etapa]
  if (umbral == null) return { dias, color: null, estancado: false }
  const transcurrido = dias * 86_400_000
  if (transcurrido >= umbral * 2) return { dias, color: SEMAFORO.critico, estancado: true }
  if (transcurrido >= umbral) return { dias, color: SEMAFORO.atencion, estancado: true }
  return { dias, color: SEMAFORO.ok, estancado: false }
}
