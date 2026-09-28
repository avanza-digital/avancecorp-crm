// «Toda la operación» de gerencia con el diseño de Gestión Diaria (27/09/2026).
// Las cifras de cada equipo salen SIEMPRE del pulso (autoritativas: incluyen
// autores inactivos y registros sin autor). El detalle por analista solo aporta
// lo que el pulso no trae —quién necesita atención y las barras por hora— y se
// restringe a las personas ACTIVAS que el pulso confirma en cada equipo
// (revisión Codex del plan, 27/09).
import { cifraPulso, type EquipoPulso, type MetricasPulso, type PulsoGerencia } from './gestion-diaria-pulso'
import { compararGravedad, horarioConfirmado, type FilaEquipoPresentada, type FiltrosEquipo } from './gestion-diaria-equipo'
import type { Marcador } from './gestion-diaria-analista'

export interface FilaEquipoOperacion {
  clave: string
  nombre: string
  /** El grupo de quienes no cuelgan de ningún supervisor: siempre al final. */
  fuera: boolean
  analistas: number
  sinRegistro: number
  llamadas: number
  contestadas: number
  utiles: number
  tasaContacto: number | null
  citas: number
  vencidas: number
  primerIntento: number | null
  dispersion: EquipoPulso['dispersion']
  /** Analistas DISTINTOS que necesitan atención; null mientras no llega el detalle (nunca 0 inventado). */
  atencion: number | null
}

const activosDe = (equipo: EquipoPulso) =>
  new Set(equipo.personas.flatMap((p) => p.activo && p.analista_id !== null ? [p.analista_id] : []))

export function filasOperacion(pulso: PulsoGerencia, detalle: readonly FilaEquipoPresentada[] | null): FilaEquipoOperacion[] {
  return pulso.equipos.map((e) => {
    const activos = activosDe(e)
    return {
      clave: e.clave, nombre: e.nombre, fuera: e.clave === 'fuera',
      analistas: e.metricas.analistas_activos, sinRegistro: e.metricas.sin_actividad,
      llamadas: e.metricas.llamadas, contestadas: e.metricas.contestadas, utiles: e.metricas.utiles,
      tasaContacto: e.metricas.tasa_contacto, citas: e.metricas.citas_agendadas, vencidas: e.tareas_vencidas,
      primerIntento: e.primer_intento_vencido, dispersion: e.dispersion,
      atencion: detalle === null ? null : detalle.filter((f) => activos.has(f.analista_id) && f.requiere_atencion).length,
    }
  })
}

export type OrdenOperacion = 'nombre' | 'llamadas' | 'contacto' | 'citas' | 'vencidas' | 'atencion' | 'primer_intento' | 'dispersion'

export interface FiltrosOperacion { busqueda: string; conAtencion: boolean; orden: OrdenOperacion; ascendente: boolean }

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLocaleLowerCase('es').trim()
const amplitud = (f: FilaEquipoOperacion) => f.dispersion.minimo === null || f.dispersion.maximo === null ? null : f.dispersion.maximo - f.dispersion.minimo

function valorDe(f: FilaEquipoOperacion, orden: Exclude<OrdenOperacion, 'nombre'>): number | null {
  switch (orden) {
    case 'llamadas': return f.llamadas
    case 'contacto': return f.tasaContacto
    case 'citas': return f.citas
    case 'vencidas': return f.vencidas
    case 'atencion': return f.atencion
    case 'primer_intento': return f.primerIntento
    case 'dispersion': return amplitud(f)
  }
}

/** «Con atención»: analistas que la necesitan; sin detalle todavía, las señales del pulso. */
export const equipoConAtencion = (f: FilaEquipoOperacion) =>
  f.atencion !== null ? f.atencion > 0 : f.vencidas > 0 || f.sinRegistro > 0 || (f.primerIntento ?? 0) > 0

export function filtrarOrdenarOperacion(filas: readonly FilaEquipoOperacion[], filtros: FiltrosOperacion): FilaEquipoOperacion[] {
  const q = normalizar(filtros.busqueda)
  return filas.filter((f) => normalizar(f.nombre).includes(q) && (!filtros.conAtencion || equipoConAtencion(f)))
    .toSorted((a, b) => {
      // «Fuera de equipos» no compite con los equipos: siempre al final.
      if (a.fuera !== b.fuera) return a.fuera ? 1 : -1
      const nombre = a.nombre.localeCompare(b.nombre, 'es')
      if (filtros.orden === 'nombre') return filtros.ascendente ? nombre : -nombre
      const va = valorDe(a, filtros.orden), vb = valorDe(b, filtros.orden)
      // Sin dato al final en ambos sentidos.
      if (va === null || vb === null) return va === vb ? nombre : va === null ? 1 : -1
      const diferencia = (va - vb) * (filtros.ascendente ? 1 : -1)
      if (diferencia) return diferencia
      // Empate en atención: primero el que más vencidas arrastra.
      return filtros.orden === 'atencion' ? b.vencidas - a.vencidas || nombre : nombre
    })
}

export interface PersonaSinRegistro { analista_id: string; nombre: string; equipo: string; clave: string }

/** Activos sin ninguna gestión en el día (la misma regla que `sin_actividad` del pulso). */
export function personasSinRegistro(pulso: PulsoGerencia): PersonaSinRegistro[] {
  return pulso.equipos.flatMap((e) => e.personas.flatMap((p) => p.activo && p.gestiones === 0 && p.analista_id !== null
    ? [{ analista_id: p.analista_id, nombre: p.nombre_completo ?? 'Analista', equipo: e.nombre, clave: e.clave }] : []))
    .toSorted((a, b) => a.equipo.localeCompare(b.equipo, 'es') || a.nombre.localeCompare(b.nombre, 'es'))
}

/** Quién necesita atención dentro del equipo, el más grave primero. */
export function atencionEquipo(detalle: readonly FilaEquipoPresentada[], equipo: EquipoPulso): FilaEquipoPresentada[] {
  const activos = activosDe(equipo)
  return detalle.filter((f) => activos.has(f.analista_id) && f.requiere_atencion).toSorted(compararGravedad)
}

export interface BarrasEquipo {
  porHora: Marcador['por_hora']
  /** Analistas activos que forman la gráfica. */
  analistas: number
  /** Llamadas del equipo que NO están en la gráfica (autores inactivos o sin autor). */
  otros: number
}

/**
 * Llamadas por hora de los analistas ACTIVOS del equipo. Si el desglose de
 * alguno no se puede confirmar, no se dibuja (no se pintan ceros como sustituto).
 */
export function barrasEquipo(detalle: readonly FilaEquipoPresentada[], equipo: EquipoPulso): BarrasEquipo | null {
  const activos = activosDe(equipo)
  const filas = detalle.filter((f) => activos.has(f.analista_id))
  if (filas.length === 0 || filas.length !== activos.size || !filas.every((f) => horarioConfirmado(f.marcador))) return null
  const porHora = new Map<number, { hora: number; llamadas: number; contestadas: number }>()
  for (const f of filas) for (const h of f.marcador.por_hora) {
    const actual = porHora.get(h.hora) ?? { hora: h.hora, llamadas: 0, contestadas: 0 }
    porHora.set(h.hora, { hora: h.hora, llamadas: actual.llamadas + h.llamadas, contestadas: actual.contestadas + h.contestadas })
  }
  const enGrafica = filas.reduce((n, f) => n + f.marcador.llamadas, 0)
  return { porHora: [...porHora.values()].toSorted((a, b) => a.hora - b.hora), analistas: filas.length, otros: Math.max(0, equipo.metricas.llamadas - enGrafica) }
}

/**
 * «Ayer 92 · Referencia 88 (7 jornadas)». En un día pasado dice «Día anterior»;
 * la referencia son hasta 7 jornadas CON actividad, no 7 días calendario (Codex).
 */
export function referenciaCifra(pulso: PulsoGerencia, campo: keyof MetricasPulso, esHoy: boolean, porcentaje = false): string {
  // Promedios y tasas a entero, como el diseño («7 días 88»): la cifra exacta vive en «Comparar días».
  const cifra = (n: number | null) => cifraPulso(n === null ? null : Math.round(n), porcentaje)
  const anterior = `${esHoy ? 'Ayer' : 'Día anterior'} ${cifra(pulso.ayer.metricas[campo])}`
  const n = pulso.referencia.cantidad
  return n === 0 ? `${anterior} · Sin referencia`
    : `${anterior} · Referencia ${cifra(pulso.referencia.media[campo])} (${n} ${n === 1 ? 'jornada' : 'jornadas'})`
}

/** «Equipo de SUPERVISOR UNO»; el grupo sin supervisor conserva su nombre. */
export const nombreEquipo = (f: { fuera: boolean; nombre: string }) => f.fuera ? f.nombre : `Equipo de ${f.nombre}`

/** A dónde lleva un número del equipo: sus analistas con ese filtro u orden. */
export type PresetEquipo = 'sin_registro' | 'vencidas' | 'atencion' | 'citas'

const FILTROS_EQUIPO: FiltrosEquipo = { busqueda: '', estado: 'todos', soloProblemas: false, orden: 'atencion', ascendente: false, gravedad: true }

/** El número que se abrió desde la operación llega como filtro u orden: el número es la lista. */
export function filtrosDePreset(preset?: PresetEquipo): FiltrosEquipo {
  switch (preset) {
    case 'atencion': return { ...FILTROS_EQUIPO, soloProblemas: true }
    case 'sin_registro': return { ...FILTROS_EQUIPO, estado: 'sin_registro' }
    case 'vencidas': return { ...FILTROS_EQUIPO, orden: 'vencidas', ascendente: false }
    case 'citas': return { ...FILTROS_EQUIPO, orden: 'citas', ascendente: false }
    default: return FILTROS_EQUIPO
  }
}
