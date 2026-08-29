// lib/nota-no-show.ts — el plantón deja rastro en el timeline.
//
// EL BUG (2026-07-25): cerrar una reunión con "No asistió" mandaba
// `resultado_tipo: null`, así que `crm.cerrar_tarea` no insertaba NINGUNA
// actividad. La tarea quedaba en estado `no_show` —dato real— pero eso NADIE lo
// lee desde la ficha del lead: lo que se lee ahí es el timeline. Historial mudo
// sobre el plantón: el analista fue, esperó, y a los tres meses no hay rastro.
//
// SE ARREGLA SIN MIGRACIÓN: la RPC ya acepta `p_resultado_tipo = 'nota'` y la
// inserta en la MISMA transacción del cierre, enganchada además a la tarea por
// `resultado_actividad_id`.
//
// POR QUÉ `nota` Y NO OTRO TIPO — son tres caras de la misma decisión, y
// ninguna es opcional:
//  · `nota` está FUERA de TIPOS_CONVERSACION → NO sube la etapa. Plantar al
//    analista jamás puede ascender el embudo.
//  · `nota` está FUERA de TIPOS_CONTACTO → `indexarUltimoContacto` no la ve, así
//    que el lead SIGUE gritando en la cola hasta que alguien lo contacte de
//    verdad. Un plantón no es haber hablado con nadie.
//  · Un tipo nuevo ('reunion_no_asistio') obligaría a tocar el CHECK de
//    `crm.actividades` Y la lista blanca de la RPC → dos migraciones, gen:types
//    y gate RLS. Innecesario: para MEDIR plantones ya está
//    `crm.tareas.estado = 'no_show'`; el timeline solo necesita CONTAR qué pasó.
import { fechaHoraLima } from './agenda-derivada'

/** Cómo empieza SIEMPRE el rastro de un plantón (mismo verbo que el botón). */
export const PREFIJO_NO_SHOW = 'No asistió'

/**
 * El texto que se graba en el timeline al cerrar una reunión en `no_show`.
 *
 * Se dice "reunión" porque `no_show` SOLO se ofrece en tareas de ese tipo; si
 * algún día se ofreciera en otro, hay que revisar esta palabra.
 *
 * INVARIANTE: nunca devuelve cadena vacía ni solo espacios. La RPC guarda
 * `nullif(btrim(coalesce(p_resultado_detalle,'')), '')`: un detalle vacío se
 * volvería NULL y el timeline pintaría "Nota" sin cuerpo — el mismo mudo que
 * esto viene a arreglar. Por eso la FECHA es opcional en el texto (un
 * `vence_en` corrupto degrada en vez de romper) y el prefijo no lo es.
 */
export function notaNoShow(venceEn: string, notaLibre?: string | null): string {
  const ms = Date.parse(venceEn)
  const cuando = Number.isFinite(ms) ? ` a la reunión del ${fechaHoraLima(ms)}` : ' a la reunión'
  const libre = notaLibre?.trim()
  return `${PREFIJO_NO_SHOW}${cuando}${libre ? ` — ${libre}` : ''}`
}
