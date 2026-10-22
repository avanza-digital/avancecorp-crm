// lib/no-asistio-espera.ts — «No asistió» espera a la hora de la cita.
//
// Regla de Miguel (2026-10-05): una reunión realizada ANTES de la hora pactada
// se marca realizada en el acto; solo «No asistió» espera a que la hora haya
// pasado. Una inasistencia registrada a las diez para una cita de las cinco no
// pudo ocurrir todavía, y Gerencia la veía como plantón.
//
// LA REGLA QUE CUENTA ES LA DEL SERVIDOR: el candado de `crm.tareas`
// (`private.trg_tareas_before_update`) rechaza con 22023 un `no_show` sobre una
// reunión cuya `vence_en` es posterior al reloj, entre por la puerta que entre.
// Esto es solo su espejo para la pantalla: no ofrecer lo que va a rebotar.
import type { Tarea } from './tipos'

/**
 * ¿Hay que esperar todavía para marcar «No asistió» en esta tarea?
 *
 * MISMO BORDE que el servidor: se espera mientras la hora pactada sea
 * POSTERIOR al reloj; desde el instante de la hora (`vence_en <= ahora`) ya no.
 * Dos criterios distintos en el borde harían que la pantalla ofreciera lo que
 * el servidor rechaza, o al revés.
 *
 * Solo aplica a reuniones: es el único tipo que ofrece «No asistió». Y una
 * hora ilegible NO bloquea: la pantalla no inventa candados que el servidor no
 * tiene — si el dato está corrupto, decide él.
 */
export function noAsistioEsperaHora(tarea: Pick<Tarea, 'tipo' | 'vence_en'>, ahora: number): boolean {
  if (tarea.tipo !== 'reunion') return false
  const hora = Date.parse(tarea.vence_en)
  return Number.isFinite(hora) && hora > ahora
}
