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
