// lib/origen-llamada.ts — el id que el celular pone a cada llamada (F4-b, plan
// «Llamadas desde el celular al CRM», 05/10/2026).
//
// La macro arma el id al colgar: la etiqueta del celular y los segundos de su
// reloj («C1-1790980958»). Viaja en la URL de F1 hasta la encuesta, y con él la
// base une el resultado con su llamada exacta (crm.registrar_llamada_v5, F4-a),
// sin adivinar por la hora. La forma la valida el router (`origenLlamadaValido`,
// sin dependencias); aquí se lee su hora para mostrarla. La ventana (30 días
// atrás, uno adelante) y que el celular sea del analista los decide el servidor.
import { fechaLima, horaLima } from './agenda-derivada'

export { origenLlamadaValido } from './router'

/** El momento de la llamada (ms) según el reloj del celular. */
export function momentoDeOrigenLlamada(origen: string): number {
  return Number(origen.slice(origen.indexOf('-') + 1)) * 1000
}

/** «de las 10:42» si fue hoy en Lima; si no, «del 03/10 a las 10:42». */
export function cuandoFueLaLlamada(origen: string, ahora: number = Date.now()): string {
  const ms = momentoDeOrigenLlamada(origen)
  const dia = fechaLima(ms)
  if (dia === fechaLima(ahora)) return `de las ${horaLima(ms)}`
  return `del ${dia.slice(8, 10)}/${dia.slice(5, 7)} a las ${horaLima(ms)}`
}
