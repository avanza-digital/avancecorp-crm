// Contrato del resumen mensual exclusivo de la mesa de Rosa. A diferencia del
// resumen de la COLA, este cuenta ALTAS por creado_en: repartir o descartar un
// lead no puede borrar que ingreso al CRM durante ese mes.
import * as v from 'valibot'
import { fechaLima } from './agenda-derivada'

const FechaIsoSchema = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/))

export const IngresosRepartoMesSchema = v.object({
  version: v.literal(1),
  generado_en: v.string(),
  mes: FechaIsoSchema,
  total: v.number(),
  semanas: v.array(v.object({
    numero: v.number(),
    desde: FechaIsoSchema,
    hasta: FechaIsoSchema,
    total: v.number(),
  })),
})

export type IngresosRepartoMes = v.InferOutput<typeof IngresosRepartoMesSchema>

/** Clave YYYY-MM del mes que contiene el instante, siempre en Lima. */
export function mesActualLima(ahoraMs: number): string {
  return fechaLima(ahoraMs).slice(0, 7)
}

/** Convierte la clave del input month al primer dia que exige la RPC. */
export function inicioDeMes(clave: string): string | null {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(clave)) return null
  return `${clave}-01`
}

const MESES_LARGOS = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
]

export function etiquetaMesReparto(clave: string): string {
  const inicio = inicioDeMes(clave)
  if (inicio == null) return clave
  const mes = Number(clave.slice(5, 7))
  return `${MESES_LARGOS[mes - 1] ?? clave} ${clave.slice(0, 4)}`
}

/** "1–6 ago" o "28 jul–3 ago"; las semanas vienen ya recortadas al mes. */
export function etiquetaSemana(desde: string, hasta: string): string {
  const diaDesde = Number(desde.slice(8, 10))
  const diaHasta = Number(hasta.slice(8, 10))
  const mesDesde = Number(desde.slice(5, 7))
  const mesHasta = Number(hasta.slice(5, 7))
  const corto = (mes: number) => (MESES_LARGOS[mes - 1] ?? '').slice(0, 3)
  if (desde === hasta) return `${diaHasta} ${corto(mesHasta)}`
  if (mesDesde === mesHasta) return `${diaDesde}–${diaHasta} ${corto(mesHasta)}`
  return `${diaDesde} ${corto(mesDesde)}–${diaHasta} ${corto(mesHasta)}`
}
