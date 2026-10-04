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

import type { ColaLead, OrigenLectura } from '@/lib/tipos'

export type OrdenCola = 'recientes' | 'antiguos'

export interface FiltrosCola {
  /** Texto libre: matchea nombre, distrito o comentario (sin tildes-sensibilidad). */
  busqueda: string
  /** Solo los que el clasificador marcó posible_credito. */
  soloMarcados: boolean
  /** '' = todos los orígenes. Filtro LOCAL (no viaja): acepta cualquier origen que traiga la cola. */
  origen: OrigenLectura | ''
  orden: OrdenCola
}

export const FILTROS_INICIALES: FiltrosCola = {
  busqueda: '',
  soloMarcados: false,
  origen: '',
  orden: 'recientes',
}

/** Normaliza para buscar: minúsculas y sin tildes ("Huamán" ⊇ "huaman"). */
function plano(s: string): string {
  return s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
}

export function filtrarYOrdenarCola(cola: ColaLead[], f: FiltrosCola): ColaLead[] {
  const q = plano(f.busqueda.trim())
  let filas = cola
  if (f.soloMarcados) {
    filas = filas.filter((l) => l.clasificacion_auto === 'posible_credito')
  }
  if (f.origen) {
    filas = filas.filter((l) => l.origen === f.origen)
  }
  if (q) {
    filas = filas.filter((l) =>
      plano(l.nombre_completo).includes(q)
      || plano(l.distrito ?? '').includes(q)
      || plano(l.comentario ?? '').includes(q))
  }
  // creado_en es ISO-8601 UTC: el orden lexicográfico ES el cronológico.
  const asc = f.orden === 'antiguos'
  return [...filas].sort((a, b) =>
    asc ? a.creado_en.localeCompare(b.creado_en) : b.creado_en.localeCompare(a.creado_en))
}

/** Orígenes presentes en la cola, para poblar el filtro sin opciones muertas. */
export function origenesDeCola(cola: ColaLead[]): OrigenLectura[] {
  return [...new Set(cola.map((l) => l.origen))]
}

/** Cuántos leads de la cola vienen marcados por el clasificador. */
export function contarMarcados(cola: ColaLead[]): number {
  return cola.reduce((n, l) => n + (l.clasificacion_auto === 'posible_credito' ? 1 : 0), 0)
}
