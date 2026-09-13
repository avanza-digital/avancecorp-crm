import { useMemo, useState } from 'react'
import { fechaLima } from './agenda-derivada'
import { DIA_MS } from './inteligencia'

export type ModoPeriodoDerivaciones = 'hoy' | 'ayer' | 'semana' | 'rango'

export interface PeriodoDerivaciones {
  desde: string
  hasta: string
}

/** Desplaza una fecha calendario de Lima sin caer en el parseo UTC de YYYY-MM-DD. */
export function desplazarFechaDerivaciones(fecha: string, dias: number): string {
  return fechaLima(Date.parse(`${fecha}T12:00:00-05:00`) + dias * DIA_MS)
}

/**
 * Estado compartido por los reportes de Supervisión y Coordinación. Ambos deben
 * interpretar «Ayer», «Últimos 7 días» y el rango manual de la misma manera.
 */
export function usePeriodoDerivaciones(
  ahora: number,
  modoInicial: ModoPeriodoDerivaciones = 'ayer',
) {
  const hoy = fechaLima(ahora)
  const ayer = desplazarFechaDerivaciones(hoy, -1)
  const [modo, setModo] = useState<ModoPeriodoDerivaciones>(modoInicial)
  const [desdeRango, setDesdeRango] = useState(() => desplazarFechaDerivaciones(hoy, -7))
  const [hastaRango, setHastaRango] = useState(() => ayer)
  const periodo = useMemo<PeriodoDerivaciones>(() => {
    if (modo === 'hoy') return { desde: hoy, hasta: hoy }
    if (modo === 'ayer') return { desde: ayer, hasta: ayer }
    if (modo === 'semana') {
      return { desde: desplazarFechaDerivaciones(hoy, -7), hasta: ayer }
    }
    return { desde: desdeRango, hasta: hastaRango }
  }, [ayer, desdeRango, hastaRango, hoy, modo])
  const diferenciaDias = periodo.desde && periodo.hasta
    ? Math.round(
        (Date.parse(`${periodo.hasta}T12:00:00-05:00`)
          - Date.parse(`${periodo.desde}T12:00:00-05:00`)) / DIA_MS,
      )
    : Number.POSITIVE_INFINITY
  const rangoValido = Boolean(
    periodo.desde
    && periodo.hasta
    && periodo.desde <= periodo.hasta
    && periodo.hasta <= hoy
    && diferenciaDias <= 365,
  )

  return {
    modo,
    setModo,
    desdeRango,
    setDesdeRango,
    hastaRango,
    setHastaRango,
    periodo,
    rangoValido,
    hoy,
  }
}
