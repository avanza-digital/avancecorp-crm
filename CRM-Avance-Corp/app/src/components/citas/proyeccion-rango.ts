// Rango Desde–Hasta de la pestaña Proyección (decisión del dueño, 19/10/2026).
// Fechas «YYYY-MM-DD» de Lima; aritmética de días en UTC para no depender de la
// zona del equipo. Módulo PURO.
import { fechaValida } from './modelo'

export interface RangoProyeccion { desde: string; hasta: string }
/** Tope de meses: cada mes del rango es una consulta al servidor. */
export const MAX_MESES_RANGO = 6
const DIA = 86_400_000
const MESES_CORTOS = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic']
const aDia = (fecha: string) => Date.UTC(Number(fecha.slice(0, 4)), Number(fecha.slice(5, 7)) - 1, Number(fecha.slice(8, 10)))
const dos = (n: number) => String(n).padStart(2, '0')

export const sumarDias = (fecha: string, dias: number) => new Date(aDia(fecha) + dias * DIA).toISOString().slice(0, 10)
export const diasEntre = (desde: string, hasta: string) => Math.round((aDia(hasta) - aDia(desde)) / DIA)
export const finDeMes = (mes: string) => `${mes}-${dos(new Date(Date.UTC(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)), 0)).getUTCDate())}`
function mesSiguiente(mes: string, paso = 1) {
  const d = new Date(Date.UTC(Number(mes.slice(0, 4)), Number(mes.slice(5, 7)) - 1 + paso, 1))
  return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}`
}

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
    ...[1, 2, 3, 4].map(n => ({ id: `s${n}`, etiqueta: `S${n}`,
      rango: { desde: `${mes}-${dos((n - 1) * 7 + 1)}`, hasta: n < 4 ? `${mes}-${dos(n * 7)}` : finDeMes(mes) } })),
  ]
}

/** «1–19 oct 2026» · «28 set – 3 oct 2026» · «28 dic 2025 – 3 ene 2026» · «19 oct 2026». */
export function rotuloRango(rango: RangoProyeccion): string {
  if (!fechaValida(rango.desde) || !fechaValida(rango.hasta)) return 'Periodo no válido'
  const dia = (f: string) => Number(f.slice(8))
  const mes = (f: string) => MESES_CORTOS[Number(f.slice(5, 7)) - 1]!
  const { desde, hasta } = rango
  const anio = hasta.slice(0, 4)
  if (desde === hasta) return `${dia(desde)} ${mes(desde)} ${anio}`
  if (desde.slice(0, 7) === hasta.slice(0, 7)) return `${dia(desde)}–${dia(hasta)} ${mes(hasta)} ${anio}`
  if (desde.slice(0, 4) === anio) return `${dia(desde)} ${mes(desde)} – ${dia(hasta)} ${mes(hasta)} ${anio}`
  return `${dia(desde)} ${mes(desde)} ${desde.slice(0, 4)} – ${dia(hasta)} ${mes(hasta)} ${anio}`
}
