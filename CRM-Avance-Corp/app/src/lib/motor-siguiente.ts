// lib/motor-siguiente.ts — la regla de oro hecha código: al cerrar una tarea,
// el sistema PROPONE la siguiente con default específico (cuándo + canal + qué).
//
// Evidencia (plan v2, sección "Investigación web"):
//  * Implementation intentions (meta-análisis d=0.65): una tarea con fecha,
//    canal y objeto concretos casi duplica la ejecución vs "hacer seguimiento".
//  * ALTERNANCIA de canal: llamada fallida → el siguiente toque es WhatsApp
//    (mensajes entre llamadas +16% de contacto); WhatsApp sin respuesta → llamada.
//  * Cadencia D1/D3 según el resultado (front-loaded al inicio del ciclo).
//  * Es una SUGERENCIA con "saltar" a un toque — jamás candado (patrón unánime
//    de la industria; el lead saltado cae al bucket amarillo, no al olvido).
//  * `no_contactar` (Ley 29571 / "No Insista") APAGA el motor por completo.
//  * Ventana legal L–S 07:00–20:00: el motor solo propone slots válidos.
import type { TipoActividad, TipoTarea } from './tipos'
import { fechaLima } from './agenda-derivada'
import { primerNombre } from './format'

export interface SugerenciaSiguiente {
  tipo: TipoTarea
  titulo: string
  vence_en: string // ISO, siempre dentro de la ventana legal
}

export interface ContextoCierre {
  /** Tipo de la tarea que se está cerrando. */
  tareaTipo: TipoTarea
  /** Cierre elegido: completada o no_show (cancelar no sugiere nada). */
  estado: 'completada' | 'no_show' | 'cancelada'
  /** Resultado 1-tap registrado al log (null si el tipo no lo exige). */
  resultado: TipoActividad | null
  /** Nombre del lead (para el título) y su flag legal. */
  leadNombre: string
  noContactar?: boolean | null
  ahora: number
}

const LIMA_OFFSET_MS = 5 * 3600 * 1000
const DIA_MS = 86_400_000

/**
 * Normaliza un instante objetivo al SLOT legal más cercano hacia adelante:
 * domingo → lunes; antes de 07:00 → 10:00 del mismo día; 20:00 o después →
 * 10:00 del siguiente día hábil.
 */
export function slotHabil(objetivoMs: number): string {
  let ms = objetivoMs
  for (let i = 0; i < 3; i += 1) {
    const lima = new Date(ms - LIMA_OFFSET_MS)
    const dow = lima.getUTCDay()
    const hora = lima.getUTCHours()
    if (dow === 0) {
      ms = Date.parse(`${fechaLima(ms + DIA_MS)}T10:00:00-05:00`)
      continue
    }
    if (hora < 7) {
      ms = Date.parse(`${fechaLima(ms)}T10:00:00-05:00`)
      continue
    }
    if (hora >= 20) {
      ms = Date.parse(`${fechaLima(ms + DIA_MS)}T10:00:00-05:00`)
      continue
    }
    break
  }
  return new Date(ms).toISOString()
}

/** Día D hacia adelante a las 10:00 Lima, saltando domingo. */
const enDias = (ahora: number, d: number): string =>
  slotHabil(Date.parse(`${fechaLima(ahora + d * DIA_MS)}T10:00:00-05:00`))

/**
 * La sugerencia del motor. `null` = no se sugiere nada (no_contactar, o el
 * cierre no amerita seguimiento). El llamador SIEMPRE deja saltar a un toque.
 */
export function sugerirSiguiente(ctx: ContextoCierre): SugerenciaSiguiente | null {
  if (ctx.noContactar) return null // flag legal duro: el motor se apaga
  if (ctx.estado === 'cancelada') return null

  const nombre = primerNombre(ctx.leadNombre)

  // No-show de una reunión: reagendar ES la siguiente (la RPC la encadena por
  // reagendada_de). Evidencia: contactar al día siguiente duplica la recuperación.
  if (ctx.estado === 'no_show') {
    return { tipo: 'reunion', titulo: `Reagendar con ${nombre}`, vence_en: enDias(ctx.ahora, 1) }
  }

  switch (ctx.resultado) {
    case 'llamada_no_contestada':
      // Alternancia: la llamada fallida se persigue por WhatsApp, no insistiendo.
      return { tipo: 'whatsapp', titulo: `WhatsApp a ${nombre}`, vence_en: enDias(ctx.ahora, 1) }
    case 'llamada_realizada':
      return { tipo: 'llamada', titulo: `Siguiente toque — ${nombre}`, vence_en: enDias(ctx.ahora, 3) }
    case 'whatsapp_enviado':
      // Sin respuesta aún: el siguiente toque cambia de canal.
      return { tipo: 'llamada', titulo: `Llamar a ${nombre}`, vence_en: enDias(ctx.ahora, 1) }
    case 'whatsapp_recibido':
      // Lead caliente: responder pronto (2 h, ajustado a la ventana legal).
      return { tipo: 'llamada', titulo: `Llamar a ${nombre} (respondió)`, vence_en: slotHabil(ctx.ahora + 2 * 3600 * 1000) }
    case 'reunion_realizada':
      // Post-reunión: resumen + siguiente paso en <24 h (cadencia del plan).
      return { tipo: 'tarea', titulo: `Enviar propuesta a ${nombre}`, vence_en: enDias(ctx.ahora, 1) }
    default:
      // Cierre sin resultado logueado (tarea genérica hecha): toque en D3.
      return { tipo: 'llamada', titulo: `Llamar a ${nombre}`, vence_en: enDias(ctx.ahora, 3) }
  }
}