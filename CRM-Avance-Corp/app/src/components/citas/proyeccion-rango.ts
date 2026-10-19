// Rango Desde–Hasta de la pestaña Proyección (decisión del dueño, 19/10/2026).
// Fechas «YYYY-MM-DD» de Lima; aritmética de días en UTC para no depender de la
// zona del equipo. Módulo PURO.
import { fechaValida } from './modelo'

export interface RangoProyeccion { desde: string; hasta: string }
/** Tope de meses: cada mes del rango es una consulta al servidor. */
export const MAX_MESES_RANGO = 6
/** Tope de columnas de la vista por días; con más, la hoja cae a semanas. */
export const MAX_DIAS_COLUMNAS = 31
const DIA = 86_400_000
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic']
const DIAS_CORTOS = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb']
const aDia = (fecha: string) => Date.UTC(Number(fecha.slice(0, 4)), Number(fecha.slice(5, 7)) - 1, Number(fecha.slice(8, 10)))
const dos = (n: number) => String(n).padStart(2, '0')

export const sumarDias = (fecha: string, dias: number) => new Date(aDia(fecha) + dias * DIA).toISOString().slice(0, 10)
export const diasEntre = (desde: string, hasta: string) => Math.round((aDia(hasta) - aDia(desde)) / DIA)
export const finDeMes = (mes: string) => `${mes}-${dos(new Date(Date.UTC(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)), 0)).getUTCDate())}`
function mesSiguiente(mes: string, paso = 1) {
  const d = new Date(Date.UTC(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)) - 1 + paso, 1))
  return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}`
}
/** Semana comercial n (1–4) del mes: 1–7 · 8–14 · 15–21 · 22–fin. */
const semanaDelMes = (mes: string, n: number): RangoProyeccion =>
  ({ desde: `${mes}-${dos((n - 1) * 7 + 1)}`, hasta: n < 4 ? `${mes}-${dos(n * 7)}` : finDeMes(mes) })
const mesCorto = (fecha: string) => MESES_CORTOS[Number(fecha.slice(5, 7)) - 1]!

/** Día 1 del mes de la consulta hasta hoy; si el mes ya pasó (o aún no empieza), el mes entero. */
export function rangoInicial(mes: string, hoy: string): RangoProyeccion {
  const desde = `${mes}-01`
  const fin = finDeMes(mes)
  return { desde, hasta: hoy >= desde && hoy <= fin ? hoy : fin }
}

/** Meses («YYYY-MM») que toca el rango, en orden. */
export function mesesDelRango(rango: RangoProyeccion): string[] {
  const meses: string[] = []
  for (let mes = rango.desde.slice(0, 7); mes <= rango.hasta.slice(0, 7) && meses.length <= MAX_MESES_RANGO; mes = mesSiguiente(mes)) meses.push(mes)
  return meses
}

export function errorRango(rango: RangoProyeccion): string {
  if (!fechaValida(rango.desde) || !fechaValida(rango.hasta)) return 'Introduce fechas válidas.'
  if (rango.desde > rango.hasta) return '«Desde» debe ser anterior o igual a «Hasta».'
  if (mesesDelRango(rango).length > MAX_MESES_RANGO) return `El rango admite hasta ${MAX_MESES_RANGO} meses.`
  return ''
}

export interface AtajoRango { id: string; etiqueta: string; rango: RangoProyeccion }
/** Hoy · Esta semana (lunes a hoy) · Mes (día 1 a hoy) · Mes pasado · S1–S4 del mes de «Hasta». */
export function atajosRango(hoy: string, hasta: string): AtajoRango[] {
  const lunes = sumarDias(hoy, -((new Date(aDia(hoy)).getUTCDay() + 6) % 7))
  const pasado = mesSiguiente(hoy.slice(0, 7), -1)
  const mes = hasta.slice(0, 7)
  return [
    { id: 'hoy', etiqueta: 'Hoy', rango: { desde: hoy, hasta: hoy } },
    { id: 'semana', etiqueta: 'Esta semana', rango: { desde: lunes, hasta: hoy } },
    { id: 'mes', etiqueta: 'Mes', rango: { desde: `${hoy.slice(0, 7)}-01`, hasta: hoy } },
    { id: 'mes-pasado', etiqueta: 'Mes pasado', rango: { desde: `${pasado}-01`, hasta: finDeMes(pasado) } },
    ...[1, 2, 3, 4].map(n => ({ id: `s${n}`, etiqueta: `S${n}`, rango: semanaDelMes(mes, n) })),
  ]
}

/** «1–19 oct 2026» · «28 set – 3 oct 2026» · «28 dic 2025 – 3 ene 2026» · «19 oct 2026». */
export function rotuloRango(rango: RangoProyeccion): string {
  if (!fechaValida(rango.desde) || !fechaValida(rango.hasta)) return 'Periodo no válido'
  const dia = (f: string) => Number(f.slice(8))
  const { desde, hasta } = rango
  const anio = hasta.slice(0, 4)
  if (desde === hasta) return `${dia(desde)} ${mesCorto(desde)} ${anio}`
  if (desde.slice(0, 7) === hasta.slice(0, 7)) return `${dia(desde)}–${dia(hasta)} ${mesCorto(hasta)} ${anio}`
  if (desde.slice(0, 4) === anio) return `${dia(desde)} ${mesCorto(desde)} – ${dia(hasta)} ${mesCorto(hasta)} ${anio}`
  return `${dia(desde)} ${mesCorto(desde)} ${desde.slice(0, 4)} – ${dia(hasta)} ${mesCorto(hasta)} ${anio}`
}

// ───────── Columnas de tiempo (Fase 2) ─────────
/** «mes»: la hoja sin columnas de tiempo; «semanas» y «dias» reparten las citas del rango. */
export type TiempoProyeccion = 'mes' | 'semanas' | 'dias'

export interface TramoProyeccion extends RangoProyeccion {
  id: string
  /** Cabecera: «S2», o el día («19»; «1 nov» el día 1 de un mes y la primera columna). */
  titulo: string
  /** Bajo el título: los días de la semana («8–14»; «22–30 set» si el rango cruza meses) o el día corto («lun»). */
  detalle: string
  /** Título de la lista: «S2 8–14 oct» · «19 oct». */
  rotulo: string
  /** Lector de pantalla y CSV: «S2 8–14 oct» · «lun 19 oct». */
  nombre: string
  domingo: boolean
  hoy: boolean
  futuro: boolean
}

/** La vista por días admite rangos de hasta 31 días. */
export const diasPermitidos = (rango: RangoProyeccion) => !errorRango(rango) && diasEntre(rango.desde, rango.hasta) < MAX_DIAS_COLUMNAS

/** La vista que de verdad se pinta: «Días» con más de 31 días cae a «Semanas». */
export const tiempoEfectivo = (tiempo: TiempoProyeccion, rango: RangoProyeccion): TiempoProyeccion =>
  tiempo === 'dias' && !diasPermitidos(rango) ? 'semanas' : tiempo

const textoDias = (desde: string, hasta: string) => desde === hasta ? `${Number(desde.slice(8))}` : `${Number(desde.slice(8))}–${Number(hasta.slice(8))}`

/** Columnas de tiempo del rango, en orden. Semanas comerciales de cada mes recortadas al rango; días, uno por columna. */
export function tramosDelRango(rango: RangoProyeccion, tiempo: TiempoProyeccion, hoy: string): TramoProyeccion[] {
  const vista = tiempoEfectivo(tiempo, rango)
  if (vista === 'mes' || errorRango(rango)) return []
  if (vista === 'dias') {
    return Array.from({ length: diasEntre(rango.desde, rango.hasta) + 1 }, (_, i) => {
      const fecha = sumarDias(rango.desde, i)
      const dia = Number(fecha.slice(8))
      const semana = DIAS_CORTOS[new Date(aDia(fecha)).getUTCDay()]!
      const rotulo = `${dia} ${mesCorto(fecha)}`
      return { id: fecha, desde: fecha, hasta: fecha, titulo: i === 0 || dia === 1 ? rotulo : String(dia), detalle: semana,
        rotulo, nombre: `${semana} ${rotulo}`, domingo: semana === 'dom', hoy: fecha === hoy, futuro: fecha > hoy }
    })
  }
  const cruza = rango.desde.slice(0, 7) !== rango.hasta.slice(0, 7)
  return mesesDelRango(rango).flatMap(mes => [1, 2, 3, 4].map(n => {
    const semana = semanaDelMes(mes, n)
    const desde = semana.desde < rango.desde ? rango.desde : semana.desde
    const hasta = semana.hasta > rango.hasta ? rango.hasta : semana.hasta
    const dias = textoDias(desde, hasta)
    const rotulo = `S${n} ${dias} ${mesCorto(desde)}`
    return { id: `${mes}-s${n}`, desde, hasta, titulo: `S${n}`, detalle: cruza ? `${dias} ${mesCorto(desde)}` : dias,
      rotulo, nombre: rotulo, domingo: false, hoy: false, futuro: desde > hoy }
  })).filter(tramo => tramo.desde <= tramo.hasta)
}
