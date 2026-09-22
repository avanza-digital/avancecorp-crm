// Contrato de F4. En real, todos los indicadores proceden de una sola foto
// autorizada del servidor. Aquí sólo se valida, busca, ordena y presenta.
import * as v from 'valibot'
import { MarcadorSchema, UmbralesSchema, type Marcador } from './gestion-diaria-analista'
import { CortesJornadaSchema } from './gestion-diaria-cortes'

const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
export const MOTIVOS_EQUIPO = {
  tarea_vencida: 'Tareas vencidas',
  primer_intento_vencido: 'Primer intento fuera de plazo',
  datos_incompletos: 'Datos pendientes de revisar',
  sin_llamar_2h: 'Más de 2 h sin llamar en la jornada',
  corte_manana: 'Primer corte de llamadas pendiente',
  corte_tarde: 'Segundo corte de llamadas pendiente',
} as const
const FilaEquipoSchema = v.object({
  analista_id: v.string(),
  nombre_completo: v.string(),
  gestiones_hoy: Natural,
  ultima_gestion_en: v.nullable(v.string()),
  marcador: MarcadorSchema,
  llamadas_por_lead: v.nullable(v.pipe(v.number(), v.minValue(0))),
  minutos_sin_llamar: v.nullable(Natural),
  tareas_pendientes: Natural,
  tareas_vencidas: Natural,
  citas_hoy: Natural,
  primer_intento_vencido: v.nullable(Natural),
  datos_incompletos: v.nullable(Natural),
  sin_llamar_2h: v.boolean(),
  motivos_atencion: v.array(v.picklist(['tarea_vencida', 'primer_intento_vencido', 'datos_incompletos', 'sin_llamar_2h'])),
  requiere_atencion: v.boolean(),
})
export type FilaEquipoDiario = v.InferOutput<typeof FilaEquipoSchema>

export const DiaEquipoSchema = v.pipe(v.object({
  version: v.literal(1),
  generado_en: v.string(),
  dia: v.string(),
  zona: v.literal('America/Lima'),
  supervisor_id: v.nullable(v.string()),
  umbrales: UmbralesSchema,
  /** Ausente en servidores anteriores: desconocido, no completar con ceros. */
  cortes: v.optional(CortesJornadaSchema),
  pendientes_al: v.string(),
  modo_sla: v.string(),
  equipo: v.array(FilaEquipoSchema),
  resumen: v.object({
    analistas: Natural,
    con_actividad: Natural,
    sin_actividad: Natural,
    con_pendientes: Natural,
    requieren_atencion: Natural,
  }),
}), v.check((d) => {
  const r = resumenEquipo(d.equipo)
  return new Set(d.equipo.map((f) => f.analista_id)).size === d.equipo.length
    && (d.cortes === undefined || (d.cortes.politica_version === d.umbrales.politica_version
      && (d.cortes.estado !== 'activo' || (d.cortes.equipo.length === d.equipo.length
        && d.cortes.equipo.every((f) => d.equipo.some((e) => e.analista_id === f.analista_id))))))
    && Object.keys(r).every((k) => r[k as keyof typeof r] === d.resumen[k as keyof typeof r])
    && d.equipo.every((f) => f.tareas_vencidas <= f.tareas_pendientes
      && f.requiere_atencion === (f.motivos_atencion.length > 0)
      && f.marcador.contestadas <= f.marcador.utiles && f.marcador.utiles <= f.marcador.llamadas
      && (f.marcador.utiles >= d.umbrales.minimo_llamadas_utiles || f.marcador.nivel === null)
      && (d.modo_sla === 'activo' || (f.primer_intento_vencido === null && f.datos_incompletos === null)))
}, 'El resumen del equipo no corresponde a sus filas'))
export type DiaEquipo = v.InferOutput<typeof DiaEquipoSchema>

export type FilaEquipoPresentada = Omit<FilaEquipoDiario, 'motivos_atencion'> & {
  motivos_atencion: (keyof typeof MOTIVOS_EQUIPO)[]
}

/** Une resultados ya confirmados en la misma foto; no calcula cortes ni horarios. */
export function presentarEquipo(dia: DiaEquipo): FilaEquipoPresentada[] {
  const cortes = new Map(dia.cortes?.estado === 'activo'
    ? dia.cortes.equipo.map((f) => [f.analista_id, f]) : [])
  return dia.equipo.map((fila) => {
    const corte = cortes.get(fila.analista_id)
    const motivos: FilaEquipoPresentada['motivos_atencion'] = [...fila.motivos_atencion]
    if (corte?.primer_corte.aviso_pendiente) motivos.push('corte_manana')
    if (corte?.segundo_corte?.aviso_pendiente) motivos.push('corte_tarde')
    const confirmados = corte?.primer_corte.aviso_pendiente || corte?.segundo_corte?.aviso_pendiente
      ? motivos.filter((m) => m !== 'sin_llamar_2h') : motivos
    return { ...fila, motivos_atencion: confirmados, requiere_atencion: confirmados.length > 0 }
  })
}

/** Resumen para el espejo demo y validación, nunca para completar una lista parcial. */
export function resumenEquipo(equipo: readonly FilaEquipoDiario[]) {
  return {
    analistas: equipo.length,
    con_actividad: equipo.filter((f) => f.gestiones_hoy > 0).length,
    sin_actividad: equipo.filter((f) => f.gestiones_hoy === 0).length,
    con_pendientes: equipo.filter((f) => f.tareas_pendientes > 0 || (f.primer_intento_vencido ?? 0) > 0).length,
    requieren_atencion: equipo.filter((f) => f.requiere_atencion).length,
  }
}

export type OrdenEquipo = 'nombre' | 'llamadas' | 'contacto' | 'pendientes' | 'atencion'
export interface FiltrosEquipo { busqueda: string; soloProblemas: boolean; orden: OrdenEquipo; ascendente: boolean }
const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es').trim()

export function filtrarOrdenarEquipo<T extends FilaEquipoPresentada>(equipo: readonly T[], filtros: FiltrosEquipo): T[] {
  const q = normalizar(filtros.busqueda)
  return equipo.filter((f) => (!filtros.soloProblemas || f.requiere_atencion) && normalizar(f.nombre_completo).includes(q))
    .sort((a, b) => {
      let diferencia = 0
      switch (filtros.orden) {
        case 'nombre': diferencia = a.nombre_completo.localeCompare(b.nombre_completo, 'es'); break
        case 'llamadas': diferencia = a.marcador.llamadas - b.marcador.llamadas; break
        case 'pendientes': diferencia = a.tareas_pendientes - b.tareas_pendientes; break
        case 'atencion': diferencia = Number(a.requiere_atencion) - Number(b.requiere_atencion)
          || a.tareas_vencidas - b.tareas_vencidas || a.marcador.llamadas - b.marcador.llamadas; break
        case 'contacto': {
          // Muestra insuficiente (no sólo denominador cero) al final en ambos
          // sentidos. El servidor aplica el mínimo vigente al producir nivel.
          const sinMuestraA = a.marcador.nivel === null || a.marcador.tasa_contacto_pct === null
          const sinMuestraB = b.marcador.nivel === null || b.marcador.tasa_contacto_pct === null
          if (sinMuestraA || sinMuestraB) return sinMuestraA === sinMuestraB
            ? a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
            : sinMuestraA ? 1 : -1
          diferencia = a.marcador.tasa_contacto_pct! - b.marcador.tasa_contacto_pct!
        }
      }
      return (filtros.ascendente ? diferencia : -diferencia)
        || a.nombre_completo.localeCompare(b.nombre_completo, 'es') || a.analista_id.localeCompare(b.analista_id)
    })
}

export function tiempoSinLlamar(minutos: number | null): string {
  if (minutos === null) return 'Sin llamadas hoy'
  if (minutos === 0) return 'Menos de 1 min'
  return minutos < 60 ? `${minutos} min` : `${Math.floor(minutos / 60)} h ${minutos % 60} min`
}

/** No pintar barras a cero si llegó un desglose parcial o inconsistente. */
export function horarioConfirmado(marcador: Marcador): boolean {
  const horas = marcador.por_hora
  const contestadasPorHora = horas.reduce((total, h) => total + h.contestadas, 0)
  return new Set(horas.map((h) => h.hora)).size === horas.length
    && horas.every((h) => Number.isInteger(h.hora) && h.hora >= 0 && h.hora <= 23
      && Number.isInteger(h.llamadas) && h.llamadas >= 0
      && Number.isInteger(h.contestadas) && h.contestadas >= 0 && h.contestadas <= h.llamadas)
    && horas.reduce((total, h) => total + h.llamadas, 0) === marcador.llamadas
    // gestion_diaria_llamadas cuenta por hora todas las llamada_realizada;
    // el total para la tasa excluye numero_errado/no_es_la_persona. Admitir
    // esa diferencia histórica sólo dentro del número de llamadas no útiles.
    && contestadasPorHora >= marcador.contestadas
    && contestadasPorHora - marcador.contestadas <= marcador.llamadas - marcador.utiles
}
