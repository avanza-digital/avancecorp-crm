// lib/recordatorio.ts — anti no-show v1 (Fase E del plan v2), sin push ni API.
//
// El recordatorio viaja por wa.me PRELLENADO y lo dispara el analista a un
// toque. La evidencia manda tres cosas (sección "Investigación web" del plan):
//  * PEDIR RESPUESTA ("¿Confirmamos…?") — el silencio es el clasificador: la
//    cita sin confirmar es la que está en riesgo y amerita llamada.
//  * Mencionar el CAPITAL EN JUEGO del propio trámite (RCT: −32% de
//    inasistencia vs recordatorio genérico).
//  * Tono "utility" (dato del trámite + pregunta contestable en una línea):
//    listo para aprobarse como plantilla utility si algún día migran a la API.
import type { LeadDeAgenda, Tarea } from './tipos'
import { tareaAEvento } from './agenda-derivada'
import { money, primerNombre } from './format'
import { soloDigitos } from './telefono'

// El criterio de teléfono vive en lib/telefono.ts desde 2026-07-25. Antes este
// archivo tenía su propia copia con un comentario que decía ser "el mismo
// criterio que AccionesContacto" — y no lo era: allá se hacía `replace('+','')`,
// que deja espacios y guiones dentro de la URL de wa.me. Una sola fuente.

/**
 * Mensaje de recordatorio de una cita: pide confirmación explícita y ancla el
 * valor a SU inversión. `null` si el lead no tiene teléfono utilizable.
 */
export function mensajeRecordatorio(t: Tarea, lead: LeadDeAgenda, ahora: number): string {
  const ev = tareaAEvento(t, ahora)
  const [dia, hora] = ev.cuando.split(' · ')
  const cuando = dia === 'Hoy' || dia === 'Mañana'
    ? `${(dia ?? '').toLowerCase()} a las ${hora}`
    : `el ${dia} a las ${hora}`
  const capital = money(lead.monto_estimado, lead.moneda)
  return (
    `Hola ${primerNombre(lead.nombre_completo)}, te saluda tu analista de Avance Corp. ` +
    `¿Confirmamos nuestra cita de ${cuando}? ` +
    `Te muestro los números de tu inversión de ${capital}. ` +
    `Si te queda mejor otro horario, dime y lo movemos.`
  )
}

/** Enlace wa.me con el recordatorio prellenado (null sin teléfono). */
export function enlaceRecordatorio(t: Tarea, lead: LeadDeAgenda, ahora: number): string | null {
  const tel = soloDigitos(lead.telefono ?? '')
  if (tel.length < 9) return null
  return `https://wa.me/${tel}?text=${encodeURIComponent(mensajeRecordatorio(t, lead, ahora))}`
}

/**
 * ¿La cita amerita el botón de recordatorio? Reuniones PENDIENTES que caen hoy
 * o mañana (la ventana donde confirmar todavía salva el slot) y aún sin
 * confirmar. Las vencidas ya no se recuerdan: se reagendan.
 */
export function ameritaRecordatorio(t: Tarea, ahora: number): boolean {
  if (t.tipo !== 'reunion' || t.estado !== 'pendiente' || !t.activo) return false
  if (t.confirmada_en) return false
  const ev = tareaAEvento(t, ahora)
  return !ev.vencida && (ev.cuando.startsWith('Hoy') || ev.cuando.startsWith('Mañana'))
}
