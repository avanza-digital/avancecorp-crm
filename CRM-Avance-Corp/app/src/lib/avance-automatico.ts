// lib/avance-automatico.ts — la etapa avanza sola cuando el hecho YA ocurrió.
//
// Pedido de Miguel (2026-07-25): "cuando el analista registre una acción de que
// SÍ contactó a la persona, y el lead está en la primera fase del pipeline, el
// prospecto se mueva solo de etapa" — y de ahí, el principio general: una acción
// debe ayudar a las otras en vez de obligar a repetirlas.
//
// ⚠️ LA FUENTE DE VERDAD ES LA BASE DE DATOS. Estas funciones son el ESPEJO
// OPTIMISTA de dos triggers, y la ÚNICA implementación en modo demo (sin
// Supabase, `persistir()` sale en seco: sin esto el demo pintaría un pipeline
// que no avanza y divergiría del servidor en los e2e).
//   · avancePorContacto  ↔ trg_zz_actividades_avance_etapa    (AFTER INSERT en crm.actividades)
//   · avancePorReunion   ↔ trg_zz_tareas_avance_etapa         (AFTER INSERT en crm.tareas)
//   · retrocesoPorAnularReunion ↔ private.retroceso_por_anular_reunion (INLINE al
//                                  final de crm.cerrar_tarea, no un trigger: así
//                                  ve la reunión que se reagenda en el mismo gesto)
// Si una regla cambia aquí, cambia allá EN LA MISMA ENTREGA, o el optimismo del
// store empieza a mentir hasta el resync.
//
// Regla de los dos AUTOMATISMOS: SOLO SUBEN, JAMÁS BAJAN. Un `cambio_etapa` es un
// hecho registrado con autor, no un estado reversible; una reunión con plantón
// no borra que se agendó.
//
// LA ÚNICA EXCEPCIÓN, y pedida a mano (Miguel, 2026-07-26): «si se anula la reu y
// no se reagenda una en ese mismo momento, debería bajar de etapa». No la
// contradice, la completa — ahí el disparo NO es un automatismo, es una persona
// declarando que esa reunión ya no existe. Sostener `reunion_agendada` sin
// ninguna reunión viva no conserva un hecho: sostiene uno falso, y el más caro,
// porque ese lead deja de aparecer como pendiente de agendar en toda la cola.
// Ver `retrocesoPorAnularReunion` al final del archivo.
import {
  TERMINALES_K,
  TIPOS_CONTACTO_K,
  TIPOS_CONVERSACION_K,
  type Actividad,
  type EtapaActiva,
  type Lead,
  type Tarea,
} from './tipos'

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
 *    comercial. Sin esta guarda, plantar al analista ASCENDERÍA el lead.
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

/**
 * ¿Anular ESTA reunión devuelve el lead a una etapa anterior? (y a cuál)
 *
 * Espejo de `private.retroceso_por_anular_reunion`. La única regla del sistema
 * que BAJA una etapa, y solo porque quien la dispara es una persona anulando:
 * ver la cabecera del archivo para por qué eso no contradice la doctrina.
 *
 * Devuelve `'contactado'`, o `'nuevo'` cuando NUNCA hubo contacto real (un lead
 * subido a mano desde el kanban sin trabajarlo): el retroceso no puede inventar
 * hacia abajo un contacto que no está en el timeline. `null` = no tocar nada.
 *
 * Guardas, todas espejo del trigger y cada una contra una forma de mentir:
 *  · `tipo === 'reunion'` — anular una llamada no mueve ninguna etapa.
 *  · etapa EXACTAMENTE `reunion_agendada` — desde `propuesta_enviada` la etapa
 *    ya no la sostiene la reunión y bajar borraría progreso posterior. Es el
 *    espejo exacto del `etapa in ('nuevo','contactado')` de la subida.
 *  · NINGUNA otra reunión pendiente viva — literalmente el "y no se reagenda una
 *    en ese mismo momento" del pedido.
 *  · NINGUNA `reunion_realizada` en el timeline — si la reunión llegó a ocurrir,
 *    bajar borraría el hito más caro del embudo por limpiar una tarea residual.
 *    Conservador a propósito: ante la duda, no baja.
 *  · CON DUEÑO — misma razón que en la subida: un lead de la cola global no
 *    tiene reunión "con nadie", y en el servidor esa guarda es de seguridad.
 *
 * DIVERGENCIA CONOCIDA con el servidor, y aceptada: el SQL ancla los dos
 * `exists` al inicio del CICLO vigente del lead (`private.inicio_ciclo_lead`)
 * porque un lead reabierto arrastra su historia entera y una reunión realizada
 * hace dos ciclos bloquearía el retroceso para siempre. Aquí no hay de dónde
 * sacar ese instante, así que el espejo mira el timeline completo. El único
 * efecto es un FALSO NEGATIVO en un lead reabierto: la UI no anuncia el
 * retroceso que el servidor sí hace, y la etapa se corrige sola en el resync.
 * Nunca al revés (nunca pinta un retroceso que el servidor no haría), que es el
 * lado en el que un espejo optimista puede permitirse fallar.
 */
export function retrocesoPorAnularReunion(
  lead: Pick<Lead, 'etapa' | 'activo' | 'vendedor_id' | 'asignado_supervisor_id'>,
  tarea: Pick<Tarea, 'id' | 'tipo'>,
  tareasDelLead: readonly Pick<Tarea, 'id' | 'tipo' | 'estado' | 'activo'>[],
  actividadesDelLead: readonly Pick<Actividad, 'tipo'>[],
): Avance {
  if (!lead.activo || TERMINALES_K.has(lead.etapa)) return null
  if (lead.etapa !== 'reunion_agendada') return null
  if ((lead.vendedor_id ?? lead.asignado_supervisor_id ?? null) == null) return null
  if (tarea.tipo !== 'reunion') return null
  const quedaOtraReunion = tareasDelLead.some(
    (t) => t.id !== tarea.id && t.tipo === 'reunion' && t.estado === 'pendiente' && t.activo,
  )
  if (quedaOtraReunion) return null
  if (actividadesDelLead.some((a) => a.tipo === 'reunion_realizada')) return null
  return actividadesDelLead.some((a) => TIPOS_CONTACTO_K.has(a.tipo)) ? 'contactado' : 'nuevo'
}
