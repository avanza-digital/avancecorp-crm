/** Reconsulta en la frontera que informa el servidor. No clasifica pendientes.
 * Usa duración del servidor + tiempo desde recepción: tolera relojes del cliente desfasados.
 * Respaldo de un minuto; TanStack pausa en segundo plano/sin red y revalida al volver.
 */
export function intervaloReconsultaSla(
  datos: { calculado_en: string; proximo_cambio_en?: string | null | undefined } | undefined,
  recibidoEn: number,
  ahora = Date.now(),
): number {
  if (!datos?.proximo_cambio_en) return 60_000
  const demora = Date.parse(datos.proximo_cambio_en) - Date.parse(datos.calculado_en)
  if (!Number.isFinite(demora) || demora <= 0) return 60_000
  return Math.max(1_000, Math.min(60_000, demora - Math.max(0, ahora - recibidoEn)))
}

/** Cuánto dura fresca una foto SLA desde que llegó: hasta su próxima frontera, con tope de 30 s.
 * Duración con los sellos del servidor; TanStack la compara con `dataUpdatedAt` y ya descuenta lo
 * transcurrido (restarlo aquí lo contaría dos veces). Volver a la pestaña solo reconsulta una foto vencida.
 * Sin frontera válida, 30 s; si la frontera no es posterior al cálculo, vencida (0).
 */
export function frescuraSla(
  datos: { calculado_en: string; proximo_cambio_en?: string | null | undefined } | undefined,
): number {
  if (!datos?.proximo_cambio_en) return 30_000
  const demora = Date.parse(datos.proximo_cambio_en) - Date.parse(datos.calculado_en)
  if (!Number.isFinite(demora)) return 30_000
  return Math.max(0, Math.min(30_000, demora))
}
