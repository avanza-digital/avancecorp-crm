// Series mensuales construidas únicamente con los leads que la RLS ya permitió
// cargar. Un cliente requiere contrato_id: crear un perfil no acredita una
// inversión. Capital solo suma PEN; PEN y USD nunca se mezclan.
import { fechaLima } from './agenda-derivada'
import type { Lead } from './tipos'

export interface SeriesComerciales {
  /** Capital invertido por mes, SOLO PEN (fecha operativa disponible, Lima). */
  capital: number[]
  /** Leads nuevos por mes (creado_en, Lima). */
  leads: number[]
  /** Clientes con inversión formalizada por mes, cualquier moneda. */
  cierres: number[]
  /** % de la cohorte mensual: clientes con contrato / leads recibidos. */
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

/** Etiquetas ascendentes de meses, sin depender de la zona horaria del equipo. */
export function etiquetasMeses(hasta: string, cantidad: number): string[] {
  const partes = hasta.slice(0, 7).split('-').map(Number)
  const anio = partes[0]
  const mes = partes[1]
  if (!anio || !mes || mes < 1 || mes > 12 || cantidad <= 0) return []
  const formato = new Intl.DateTimeFormat('es-PE', { month: 'short', timeZone: 'UTC' })
  return Array.from({ length: cantidad }, (_valor, indice) => {
    const total = anio * 12 + (mes - 1) - (cantidad - 1 - indice)
    const fecha = new Date(Date.UTC(Math.floor(total / 12), total % 12, 1))
    const etiqueta = formato.format(fecha).replace('.', '')
    return etiqueta.charAt(0).toUpperCase() + etiqueta.slice(1)
  })
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
  const clientesCohorte = claves.map(() => 0)

  for (const lead of leads) {
    if (!lead.activo) continue
    const mesAlta = indice.get(mesLima(lead.creado_en))
    if (mesAlta != null) {
      nuevos[mesAlta] = (nuevos[mesAlta] ?? 0) + 1
      if (lead.contrato_id != null) {
        clientesCohorte[mesAlta] = (clientesCohorte[mesAlta] ?? 0) + 1
      }
    }

    if (lead.contrato_id == null) continue
    const mesCierre = indice.get(mesLima(
      lead.actualizado_en ?? lead.convertido_en ?? lead.creado_en,
    ))
    if (mesCierre == null) continue
    cierres[mesCierre] = (cierres[mesCierre] ?? 0) + 1
    if (lead.moneda === 'PEN') {
      capital[mesCierre] = (capital[mesCierre] ?? 0) + lead.monto_estimado
    }
  }

  const conversion = claves.map((_clave, i) => {
    const total = nuevos[i] ?? 0
    return total > 0 ? Math.round(((clientesCohorte[i] ?? 0) / total) * 1000) / 10 : 0
  })

  return { capital, leads: nuevos, cierres, conversion }
}
