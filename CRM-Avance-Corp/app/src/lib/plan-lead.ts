// lib/plan-lead.ts — ¿este lead tiene un plan VIVO, o solo un plan muerto?
//
// EL AGUJERO (pedido de Miguel, 2026-07-25). Tres pantallas construían a mano
// el mismo Set —`tareas.filter(t => t.estado === 'pendiente' && t.activo)`— y
// ese Set apagaba los buckets por inactividad de `colaDe` y las alertas de
// `estancados`. Pero JAMÁS miraba `vence_en`: una tarea que venció hace dos
// semanas seguía contando como "tiene plan". El lead se escondía de la cola
// detrás de una promesa que nadie cumplió, y **cuanto más se abandonaba, más
// invisible se volvía** — el escudo se lo daba el propio incumplimiento.
//
// REGLA: el plan muere cuando su DÍA (calendario Lima) ya pasó, no a la hora en
// punto. Mismo criterio que `tareaQueCierra` (lib/contacto-tarea.ts) y por la
// misma razón: la agenda del día se trabaja en el orden que el analista quiera.
// Matarlo a las 10:01 convertiría la cola en un eco minuto a minuto de la
// agenda de al lado — justo el doble aviso que hay que evitar.
//
// ⚠️ ESTE CRITERIO NO COINCIDE CON EL DE LA AGENDA, y es a propósito.
// `tareaAEvento` (lib/agenda-derivada) marca «vencida» por HORA: la llamada de
// las 09:00 ya sale en ámbar a las 09:01, y esconderla hasta mañana sería peor.
// Son dos preguntas distintas — "¿ya pasó la hora?" allá, "¿este lead tiene
// dueño de su siguiente paso?" aquí — y las dos están bien contestadas. Pero
// deja una trampa para las pantallas que enseñan las dos superficies a la vez:
// **durante todo el día de hoy una tarea puede estar VENCIDA en la agenda y
// VIGENTE aquí**, con lo cual `colaDe` salta a su lead y ese lead NO tiene fila
// en la cola. Ninguna pantalla puede afirmar lo contrario sin comprobarlo
// (le pasó al pie "+N más vencidas" de screens/hoy/vendedor.tsx, que lo
// prometía a ciegas — hoy lo cuenta, ver `textoRestoVencidas`).
import { fechaLima } from './agenda-derivada'
import type { Tarea } from './tipos'

export interface PlanPorLead {
  /** Leads con ≥1 tarea pendiente cuyo día NO pasó — plan VIVO. */
  vigente: ReadonlySet<string>
  /**
   * Lead → su tarea vencida MÁS VIEJA (la que más avergüenza). Solo días
   * pasados. Un lead puede estar en `vigente` Y aquí a la vez (una tarea muerta
   * y una cita el viernes): quien decide es el consumidor, y `colaDe` pregunta
   * primero por `vigente`.
   */
  vencido: ReadonlyMap<string, Tarea>
  /**
   * Leads con CUALQUIER pendiente, viva o muerta = "tiene algo escrito".
   *
   * Es el que necesitan `sinProximaAccion` y la higiene del viernes: esa
   * pantalla YA lista todas las vencidas por su cuenta, así que pasarle
   * `vigente` sacaría al mismo lead DOS VECES en la misma tarjeta (una como
   * tarea vencida y otra como "sin próxima acción").
   */
  conTarea: ReadonlySet<string>
}

/**
 * ¿ESTA tarea es un plan vivo? Misma regla que `planPorLead`, expuesta aparte
 * para los consumidores que miran las tareas de UN lead (el diálogo de contacto
 * y el botón Agendar). Antes preguntaban `tareasDe(id).length > 0` —que cuenta
 * también las VENCIDAS— y el resultado era un callejón: la cola destapaba al
 * lead abandonado y acto seguido le escondía el botón de agendar por culpa de
 * la misma tarea muerta que lo había destapado.
 */
export function esPlanVivo(t: Tarea, ahora: number): boolean {
  if (t.estado !== 'pendiente' || !t.activo) return false
  const ms = Date.parse(t.vence_en)
  return !Number.isFinite(ms) || fechaLima(ms) >= fechaLima(ahora)
}

/** Clasifica las tareas pendientes de un ámbito en plan vivo / plan muerto. */
export function planPorLead(tareas: Tarea[], ahora: number): PlanPorLead {
  const hoy = fechaLima(ahora)
  const vigente = new Set<string>()
  const vencido = new Map<string, Tarea>()
  const conTarea = new Set<string>()
  for (const t of tareas) {
    if (t.estado !== 'pendiente' || !t.activo) continue
    const leadId = t.lead_id
    if (!leadId) continue // v1: las tareas de cliente no gobiernan la cola de leads
    conTarea.add(leadId)
    const ms = Date.parse(t.vence_en)
    // Fecha corrupta → se trata como VIVA: fail-safe hacia "no molestar". Que
    // una fila rota inunde la cola de todos sería peor que dejarla pasar.
    if (!Number.isFinite(ms) || fechaLima(ms) >= hoy) {
      vigente.add(leadId)
      continue
    }
    const previa = vencido.get(leadId)
    if (!previa || t.vence_en < previa.vence_en) vencido.set(leadId, t)
  }
  return { vigente, vencido, conTarea }
}
