/** Fechas comerciales sin hora: comparar por día de Lima, nunca por UTC. */
export const fechaLocalCitas = (fecha: string) => new Intl.DateTimeFormat('en-CA', {
  timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date(fecha))

/** Una fecha comercial no acredita el orden intradía. Sí excluye días posteriores. */
export function entrevistaCompatibleConVenta(asistencia: string | undefined, fechaComercial: string | null): boolean {
  return Boolean(fechaComercial && asistencia && Number.isFinite(Date.parse(asistencia))
    && fechaLocalCitas(asistencia) <= fechaComercial)
}

export function ventaComercialDelMes(
  venta: { fecha_comercial: string | null; convertido_en: string }, mes: string, corte: string,
): boolean {
  return venta.fecha_comercial !== null && venta.fecha_comercial.startsWith(`${mes}-`)
    && venta.fecha_comercial <= fechaLocalCitas(corte)
    && Date.parse(venta.convertido_en) <= Date.parse(corte)
}
