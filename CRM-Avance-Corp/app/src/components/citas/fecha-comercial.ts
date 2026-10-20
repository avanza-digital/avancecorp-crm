// Un solo formateador: crearlo en cada llamada costaba más que el resto del cálculo de Resultados y la Proyección.
const DIA_DE_LIMA = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Lima', year: 'numeric', month: '2-digit', day: '2-digit' })
/** Fechas comerciales sin hora: comparar por día de Lima, nunca por UTC. */
export const fechaLocalCitas = (fecha: string) => DIA_DE_LIMA.format(new Date(fecha))

/** Una fecha comercial no acredita el orden intradía. Sí excluye días posteriores. */
export function entrevistaCompatibleConVenta(asistencia: string | undefined, fechaComercial: string | null): boolean {
  return Boolean(fechaComercial && asistencia && Number.isFinite(Date.parse(asistencia))
    && fechaLocalCitas(asistencia) <= fechaComercial)
}

/** Días de Lima de un periodo (ambos incluidos) e instante de la consulta. */
export interface PeriodoComercial { desde: string; hasta: string; corte: string }

/** Venta del periodo: su fecha comercial cae en él, no después del día del corte, y ya estaba registrada al corte. */
export function ventaComercialDelPeriodo(
  venta: { fecha_comercial?: string | null | undefined; convertido_en: string }, { desde, hasta, corte }: PeriodoComercial,
): boolean {
  const dia = venta.fecha_comercial
  return dia != null && dia >= desde && dia <= hasta
    && dia <= fechaLocalCitas(corte)
    && Date.parse(venta.convertido_en) <= Date.parse(corte)
}

/** El mes como periodo: una fecha comercial válida del mes está entre su día 01 y el 31. */
export function ventaComercialDelMes(
  venta: { fecha_comercial: string | null; convertido_en: string }, mes: string, corte: string,
): boolean {
  return ventaComercialDelPeriodo(venta, { desde: `${mes}-01`, hasta: `${mes}-31`, corte })
}
