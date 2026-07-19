// Series comerciales mensuales REALES — la reactivación de tendencias.
// Fuente: los leads del ámbito YA cargados (la RLS del servidor recorta; cada
// rol ve su propia tendencia). El mes de CIERRE usa actualizado_en: un lead
// terminal es inmutable para el API (editar un cerrado está bloqueado), así
// que actualizado_en ≡ instante del cierre — el MISMO contrato que usa
// crm.metricas_agenda_fn para contar cierres.
// capital SOLO suma PEN (regla de la casa: PEN y USD jamás se suman).
import { fechaLima } from './agenda-derivada'
import type { Lead } from './tipos'

export interface SeriesComerciales {
  /** Capital de ventas cerradas por mes, SOLO PEN (mes de cierre, Lima). */
  capital: number[]
  /** Leads nuevos por mes (creado_en, Lima). */
  leads: number[]
  /** Ventas cerradas por mes (leads convertidos, cualquier moneda). */
  cierres: number[]
  /** % de conversión del mes: convertidos / (convertidos + descartados). */
  conversion: number[]
}

export const SERIES_VACIAS: SeriesComerciales = {
  capital: [],
  leads: [],
  cierres: [],
  conversion: [],
}

function mesLima(iso: string): string {
  const ms = Date.parse(iso)
  return Number.isFinite(ms) ? fechaLima(ms).slice(0, 7) : ''
}

/**
 * Series de los últimos `meses` meses calendario de Lima (ascendente, el mes
 * vigente al final). Los leads desactivados (borrado suave) no cuentan.
 */
export function seriesComerciales(leads: Lead[], ahoraMs: number, meses = 6): SeriesComerciales {
  const partes = fechaLima(ahoraMs).split('-').map(Number)
  const anioActual = partes[0] ?? 1970
  const mesActual = partes[1] ?? 1
  const claves: string[] = []
  for (let i = meses - 1; i >= 0; i -= 1) {
    const total = anioActual * 12 + (mesActual - 1) - i
    const anio = Math.floor(total / 12)
    const mes = (total % 12) + 1
    claves.push(`${anio}-${String(mes).padStart(2, '0')}`)
  }
  const indice = new Map(claves.map((clave, i) => [clave, i]))

  const capital = claves.map(() => 0)
  const nuevos = claves.map(() => 0)
  const cierres = claves.map(() => 0)
  const convertidos = claves.map(() => 0)
  const resueltos = claves.map(() => 0)

  for (const lead of leads) {
    if (!lead.activo) continue
    const mesAlta = indice.get(mesLima(lead.creado_en))
    if (mesAlta != null) nuevos[mesAlta] = (nuevos[mesAlta] ?? 0) + 1

    if (lead.etapa !== 'convertido' && lead.etapa !== 'descartado') continue
    const mesCierre = indice.get(mesLima(lead.actualizado_en ?? lead.creado_en))
    if (mesCierre == null) continue
    resueltos[mesCierre] = (resueltos[mesCierre] ?? 0) + 1
    if (lead.etapa === 'convertido') {
      convertidos[mesCierre] = (convertidos[mesCierre] ?? 0) + 1
      cierres[mesCierre] = (cierres[mesCierre] ?? 0) + 1
      if (lead.moneda === 'PEN') {
        capital[mesCierre] = (capital[mesCierre] ?? 0) + lead.monto_estimado
      }
    }
  }

  const conversion = claves.map((_clave, i) => {
    const total = resueltos[i] ?? 0
    return total > 0 ? Math.round(((convertidos[i] ?? 0) / total) * 100) : 0
  })

  return { capital, leads: nuevos, cierres, conversion }
}
