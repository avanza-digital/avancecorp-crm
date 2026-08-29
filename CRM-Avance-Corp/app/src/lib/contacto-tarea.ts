// lib/contacto-tarea.ts — ¿qué tarea de la agenda CIERRA este contacto?
//
// Pedido de Miguel (2026-07-25): "una acción debería ayudar a las otras". Hasta
// hoy el analista que llamaba desde la cola registraba la llamada ahí, y luego
// volvía a responder "¿qué pasó?" al cerrar la misma tarea desde la Agenda. Dos
// veces el mismo trabajo, y la agenda quedaba mintiendo hasta que se acordara.
//
// Vive fuera del componente por dos razones: es lógica pura testeable, y la
// regla `react(only-export-components)` prohíbe exportar no-componentes desde
// un archivo de componentes.
import type { Tarea, TipoTarea } from './tipos'
import { fechaLima } from './agenda-derivada'

/** Canal desde el que se contactó (los dos botones de AccionesContacto). */
export type Canal = 'tel' | 'wa'

/** Canal → tipo de tarea que ese canal puede cerrar. Sin fallback a propósito. */
export const TIPO_TAREA_DE_CANAL: Record<Canal, TipoTarea> = { tel: 'llamada', wa: 'whatsapp' }

/**
 * La tarea pendiente que este contacto cierra, o `null` si no hay ninguna clara
 * (entonces el diálogo se comporta como siempre: registra la actividad y ya).
 *
 * Cerrar una tarea es IRREVERSIBLE — no existe "deshacer" — así que solo se
 * empareja cuando no cabe duda de cuál era. Cuatro guardas, todas necesarias
 * (auditoría 2026-07-25):
 *
 *  · SOLO MI TAREA (`t.vendedor_id === miId`). Un supervisor o gerencia que
 *    contacta desde la cola del equipo sigue solo registrando: cerrar el
 *    compromiso de otro le falsearía su cumplimiento y le tocaría la agenda.
 *  · CANAL EXACTO, sin fallback. Teléfono cierra tareas de llamada y WhatsApp
 *    las de WhatsApp. Las de tipo `reunion` y `tarea` NUNCA se tocan desde
 *    aquí: ahí está la mentira gorda (dar por hecha una reunión que no ocurrió).
 *  · VENCE HOY O ANTES (fin del día Lima). Se diverge a propósito de la versión
 *    más estricta ("solo lo ya vencido"): la agenda del día se trabaja en el
 *    orden que el analista quiera, y exigir que la hora ya hubiera pasado
 *    reintroducía justo el trabajo doble que esto viene a quitar. Lo de mañana
 *    no se toca.
 *  · UNA SOLA CANDIDATA. Con dos tareas del mismo canal para hoy no se adivina:
 *    se registra la actividad y el analista cierra la que toque desde la agenda.
 *
 * `tareas` se espera ya filtrada a PENDIENTES del lead (lo que devuelve
 * `tareasDe` del store).
 */
export function tareaQueCierra(
  tareas: Tarea[],
  canal: Canal,
  miId: string | null | undefined,
  ahora: number,
): Tarea | null {
  if (!miId) return null
  const finDeHoy = Date.parse(`${fechaLima(ahora)}T23:59:59-05:00`)
  const tipo = TIPO_TAREA_DE_CANAL[canal]
  const candidatas = tareas.filter(
    (t) => t.tipo === tipo && t.vendedor_id === miId && Date.parse(t.vence_en) <= finDeHoy,
  )
  return candidatas.length === 1 ? (candidatas[0] ?? null) : null
}
