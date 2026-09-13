import { fechaLima } from './agenda-derivada'
import { desplazarFechaDerivaciones } from './use-periodo-derivaciones'
import type { Lead } from './tipos'

export type ModoFechaCartera = 'todas' | 'hoy' | 'ayer' | 'semana' | 'rango'
export interface RangoFechaCartera { desde: string; hasta: string }

export function periodoFechaCartera(
  modo: ModoFechaCartera,
  rango: RangoFechaCartera,
  hoy: string,
): RangoFechaCartera | null {
  if (modo === 'todas') return null
  if (modo === 'hoy') return { desde: hoy, hasta: hoy }
  if (modo === 'ayer') {
    const ayer = desplazarFechaDerivaciones(hoy, -1)
    return { desde: ayer, hasta: ayer }
  }
  if (modo === 'semana') return { desde: desplazarFechaDerivaciones(hoy, -6), hasta: hoy }
  return rango
}

export function rangoFechaCarteraValido(rango: RangoFechaCartera | null, hoy: string): boolean {
  if (!rango) return true
  const fechaValida = (fecha: string) => /^\d{4}-\d{2}-\d{2}$/.test(fecha)
    && Number.isFinite(Date.parse(`${fecha}T12:00:00-05:00`))
    && fechaLima(Date.parse(`${fecha}T12:00:00-05:00`)) === fecha
  return fechaValida(rango.desde) && fechaValida(rango.hasta)
    && rango.desde <= rango.hasta && rango.hasta <= hoy
}

/** Solo DEMO: no sustituye al ledger de recepción de las cuentas reales. */
export function fechaRecepcionDemo(lead: Lead): string {
  const instante = Date.parse(lead.tenencia_desde ?? lead.creado_en)
  return Number.isFinite(instante) ? fechaLima(instante) : ''
}

export function coincideFechaRecepcionDemo(lead: Lead, rango?: RangoFechaCartera | null): boolean {
  if (!rango) return true
  const fecha = fechaRecepcionDemo(lead)
  return fecha >= rango.desde && fecha <= rango.hasta
}
