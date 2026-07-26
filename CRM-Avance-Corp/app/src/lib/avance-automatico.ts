// lib/avance-automatico.ts — la etapa avanza sola cuando el hecho YA ocurrió.
//
// Pedido de Miguel (2026-07-25): "cuando el vendedor registre una acción de que
// SÍ contactó a la persona, y el lead está en la primera fase del pipeline, el
// prospecto se mueva solo de etapa" — y de ahí, el principio general: una acción
// debe ayudar a las otras en vez de obligar a repetirlas.
//
// ⚠️ LA FUENTE DE VERDAD ES LA BASE DE DATOS. Estas funciones son el ESPEJO
// OPTIMISTA de dos triggers, y la ÚNICA implementación en modo demo (sin
// Supabase, `persistir()` sale en seco: sin esto el demo pintaría un pipeline
// que no avanza y divergiría del servidor en los e2e).
//   · avancePorContacto  ↔ trg_zz_actividades_avance_etapa (AFTER INSERT en crm.actividades)
//   · avancePorReunion   ↔ trg_zz_tareas_avance_etapa      (AFTER INSERT en crm.tareas)
// Si una regla cambia aquí, cambia allá EN LA MISMA ENTREGA, o el optimismo del
// store empieza a mentir hasta el resync.
//
// Regla transversal de las dos: SOLO SUBEN, JAMÁS BAJAN. Un `cambio_etapa` es un
// hecho registrado con autor, no un estado reversible; una reunión con plantón
// no borra que se agendó. Retroceder es siempre decisión explícita de una
// persona (el kanban y la ficha siguen permitiéndolo a mano).
import { TERMINALES_K, TIPOS_CONVERSACION_K, type EtapaActiva, type Lead, type Tarea } from './tipos'

/** Etapa a la que se sube, o null si no hay que tocar nada. */
export type Avance = EtapaActiva | null

/**
 * ¿Este contacto sube el lead de `nuevo` a `contactado`?
 *
 * Solo los tipos de CONVERSACIÓN (el cliente respondió): ver el comentario de
 * TIPOS_CONVERSACION en tipos.ts para por qué "no contestó" y "mensaje enviado"
 * quedan fuera. Solo desde `nuevo`: esta función no adivina etapas más
 * adelante del embudo — que alguien conteste el teléfono no significa que se
 * haya enviado una propuesta.
 */
export function avancePorContacto(lead: Pick<Lead, 'etapa' | 'activo'>, tipo: string): Avance {
  if (!lead.activo || TERMINALES_K.has(lead.etapa)) return null
  if (lead.etapa !== 'nuevo') return null
  return TIPOS_CONVERSACION_K.has(tipo) ? 'contactado' : null
}

/**
 * ¿Agendar esta tarea sube el lead a `reunion_agendada`?
 *
 * Guardas, todas necesarias y todas espejo del trigger:
 *  · `tipo === 'reunion'` — una llamada o un recordatorio no son una reunión.
 *  · `reagendada_de == null` — mata la mentira principal: el motor reagenda
 *    solo tras un no-show (motor-siguiente.ts), y ese rebote NO es progreso
 *    comercial. Sin esta guarda, plantar al asesor ASCENDERÍA el lead.
 *  · `estado === 'pendiente'` y `vence_en` futuro — seeds, backfills e imports
 *    de tareas ya cerradas no mueven embudos.
 *  · `tieneContactoReal` — nunca se afirma "reunión agendada" sobre un lead que
 *    NADIE ha tocado nunca (incluye el caso del supervisor que agenda sobre un
 *    lead parkeado). El llamador lo calcula con TIPOS_CONTACTO (los 5, no los 3
 *    de conversación): para agendar basta con haberlo trabajado.
 *  · etapa en `nuevo`/`contactado` — desde `propuesta_enviada` sería un
 *    RETROCESO que además reinicia el umbral de SLA de 120 h a 72 h.
 *  · CON DUEÑO (analista o bandeja). Un lead de la cola global no tiene
 *    "reunión agendada" con nadie: nadie lo trabaja todavía. En el servidor
 *    esta guarda es además de SEGURIDAD (hallazgo C1 de la auditoría): la
 *    policy `tareas_insert` no consulta `crm.leads`, así que sin ella un
 *    supervisor —o gerencia— podía ascender leads de esa cola. Aquí se replica
 *    porque si no, la UI pintaría un avance optimista que el servidor no hace.
 */
export function avancePorReunion(
  lead: Pick<Lead, 'etapa' | 'activo' | 'vendedor_id' | 'asignado_supervisor_id'>,
  tarea: Pick<Tarea, 'tipo' | 'estado' | 'activo' | 'vence_en'> & { reagendada_de?: string | null },
  tieneContactoReal: boolean,
  ahora: number,
): Avance {
  if (!lead.activo || TERMINALES_K.has(lead.etapa)) return null
  if (lead.etapa !== 'nuevo' && lead.etapa !== 'contactado') return null
  if ((lead.vendedor_id ?? lead.asignado_supervisor_id ?? null) == null) return null
  if (tarea.tipo !== 'reunion' || tarea.estado !== 'pendiente' || !tarea.activo) return null
  if (tarea.reagendada_de != null) return null
  if (!tieneContactoReal) return null
  const vence = Date.parse(tarea.vence_en)
  if (!Number.isFinite(vence) || vence <= ahora) return null
  return 'reunion_agendada'
}
