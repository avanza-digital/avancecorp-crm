// Vista de la cola de reparto (C1-bis): filtro + orden de PRESENTACIÓN.
//
// La RPC entrega la cola en FIFO (más antiguos primero) y ese contrato NO se
// toca: aquí solo se decide cómo la VE el coordinador. Miguel pidió (2026-07-24)
// que el default sea "más recientes primero" — el lead que acaba de entrar se ve
// arriba — con el orden inverso a un clic para repartir lo que más ha esperado.
//
// NO hay orden "por capital" a propósito: la cola mezcla PEN y USD y ordenarlos
// por el número crudo compararía monedas distintas (la regla de la casa es que
// PEN/USD jamás se suman ni se comparan sin conversión).

import { CAT_LABEL, origenLabel, type CategoriaInteres, type ColaLead, type Origen } from '@/lib/tipos'
import type { Moneda } from '@/lib/format'

export type OrdenCola = 'recientes' | 'antiguos'
export type AntiguedadCola = '' | 'hoy' | 'uno_dos' | 'tres_mas'
export type ComentarioCola = '' | 'con' | 'sin'

export interface FiltrosCola {
  /** Texto libre: matchea nombre, distrito o comentario (sin tildes-sensibilidad). */
  busqueda: string
  /** Solo los que el clasificador marcó posible_credito. */
  soloMarcados: boolean
  /** '' = todos los orígenes. */
  origen: Origen | ''
  categoria: CategoriaInteres | ''
  moneda: Moneda | ''
  distrito: string
  antiguedad: AntiguedadCola
  comentario: ComentarioCola
  /** Texto del input: vacío no filtra; se interpreta en la moneda elegida. */
  montoMin: string
  montoMax: string
  orden: OrdenCola
}

export const FILTROS_INICIALES: FiltrosCola = {
  busqueda: '',
  soloMarcados: false,
  origen: '',
  categoria: '',
  moneda: '',
  distrito: '',
  antiguedad: '',
  comentario: '',
  montoMin: '',
  montoMax: '',
  orden: 'recientes',
}

/** Normaliza para buscar: minúsculas y sin tildes ("Huamán" ⊇ "huaman"). */
function plano(s: string): string {
  return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
}

function montoFiltro(valor: string): number | null {
  if (valor.trim() === '') return null
  const numero = Number(valor)
  return Number.isFinite(numero) && numero >= 0 ? numero : null
}

function cumpleAntiguedad(lead: ColaLead, filtro: AntiguedadCola, ahoraMs: number): boolean {
  if (filtro === '') return true
  const desde = Date.parse(lead.creado_en)
  if (!Number.isFinite(desde)) return false
  const dias = Math.max(0, Math.floor((ahoraMs - desde) / 86_400_000))
  if (filtro === 'hoy') return dias === 0
  if (filtro === 'uno_dos') return dias >= 1 && dias <= 2
  return dias >= 3
}

export function filtrarYOrdenarCola(
  cola: ColaLead[],
  f: FiltrosCola,
  ahoraMs = Date.now(),
): ColaLead[] {
  const q = plano(f.busqueda.trim())
  // El capital solo filtra con moneda elegida: comparar 50 000 PEN con
  // 50 000 USD como si fueran la misma magnitud rompería la regla multimoneda.
  const min = f.moneda ? montoFiltro(f.montoMin) : null
  const max = f.moneda ? montoFiltro(f.montoMax) : null
  let filas = cola
  if (f.soloMarcados) {
    filas = filas.filter((l) => l.clasificacion_auto === 'posible_credito')
  }
  if (f.origen) {
    filas = filas.filter((l) => l.origen === f.origen)
  }
  if (f.categoria) {
    filas = filas.filter((l) => l.categoria_interes === f.categoria)
  }
  if (f.moneda) {
    filas = filas.filter((l) => l.moneda === f.moneda)
  }
  if (f.distrito) {
    filas = filas.filter((l) => l.distrito === f.distrito)
  }
  if (f.comentario === 'con') {
    filas = filas.filter((l) => (l.comentario ?? '').trim() !== '')
  } else if (f.comentario === 'sin') {
    filas = filas.filter((l) => (l.comentario ?? '').trim() === '')
  }
  if (f.antiguedad) {
    filas = filas.filter((l) => cumpleAntiguedad(l, f.antiguedad, ahoraMs))
  }
  if (min != null) filas = filas.filter((l) => l.monto_estimado >= min)
  if (max != null) filas = filas.filter((l) => l.monto_estimado <= max)
  if (q) {
    filas = filas.filter((l) =>
      plano(l.nombre_completo).includes(q)
      || plano(l.distrito ?? '').includes(q)
      || plano(l.comentario ?? '').includes(q)
      || plano(origenLabel(l.origen)).includes(q)
      || plano(l.categoria_interes ? CAT_LABEL[l.categoria_interes] : '').includes(q))
  }
  // creado_en es ISO-8601 UTC: el orden lexicográfico ES el cronológico.
  const asc = f.orden === 'antiguos'
  return [...filas].sort((a, b) =>
    asc ? a.creado_en.localeCompare(b.creado_en) : b.creado_en.localeCompare(a.creado_en))
}

/** Orígenes presentes en la cola, para poblar el filtro sin opciones muertas. */
export function origenesDeCola(cola: ColaLead[]): Origen[] {
  return [...new Set(cola.map((l) => l.origen))]
}

/** Distritos reales de la cola: sin opciones muertas ni un rótulo vacío. */
export function distritosDeCola(cola: ColaLead[]): string[] {
  return [...new Set(cola.map((l) => l.distrito?.trim()).filter((d): d is string => Boolean(d)))]
    .sort((a, b) => a.localeCompare(b, 'es'))
}

/** Número que se pinta en el botón "Más filtros" (solo los del panel avanzado). */
export function contarFiltrosAvanzados(f: FiltrosCola): number {
  return [
    f.categoria,
    f.moneda,
    f.distrito,
    f.antiguedad,
    f.comentario,
    f.montoMin.trim(),
    f.montoMax.trim(),
  ].filter(Boolean).length
}

/** Cuántos leads de la cola vienen marcados por el clasificador. */
export function contarMarcados(cola: ColaLead[]): number {
  return cola.reduce((n, l) => n + (l.clasificacion_auto === 'posible_credito' ? 1 : 0), 0)
}
