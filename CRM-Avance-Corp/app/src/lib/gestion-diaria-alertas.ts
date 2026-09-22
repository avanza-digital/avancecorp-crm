import * as v from 'valibot'
import type { AlertaCRM } from './alertas'
import { ModoSlaSchema } from './sla-operacion'

const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
const Id = v.pipe(v.string(), v.uuid())
const Instante = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s))))
export const TipoDiaria = v.picklist(['primera_atencion', 'tarea_vencida', 'seguimiento',
  'revision_comercial', 'datos_incompletos', 'por_repartir', 'parado_2h'])
export const GrupoDiarioSchema = v.pipe(v.strictObject({
  id: v.string(), tipo: TipoDiaria, severidad: v.picklist(['critica', 'atencion']),
  miembros: v.pipe(v.array(Id), v.minLength(1)), total: Natural,
}), v.check((g) => g.miembros.length === g.total && new Set(g.miembros).size === g.total))
export const AlertasDiariasSchema = v.pipe(v.strictObject({
  modo_sla: ModoSlaSchema, alertas: v.array(GrupoDiarioSchema),
}), v.check((r) => new Set(r.alertas.map((a) => a.tipo)).size === r.alertas.length
  && r.alertas.every((a) => r.modo_sla === 'activo' || a.tipo === 'parado_2h')))
export const ContextoDiarioSchema = v.pipe(v.strictObject({
  en_jornada: v.boolean(), analistas: Natural, con_llamadas: Natural,
  equipo: v.array(v.strictObject({ analista_id: Id, nombre: v.string(),
    primera_llamada_en: v.nullable(Instante), llamadas: Natural, sin_llamar_2h: v.boolean() })),
}), v.check((r) => r.analistas === r.equipo.length
  && new Set(r.equipo.map((e) => e.analista_id)).size === r.analistas
  && r.con_llamadas === r.equipo.filter((e) => e.llamadas > 0).length
  && r.equipo.every((e) => (e.llamadas > 0) === (e.primera_llamada_en !== null)
    && (r.en_jornada || !e.sin_llamar_2h))))
export type GrupoDiario = v.InferOutput<typeof GrupoDiarioSchema>
export type ContextoDiario = v.InferOutput<typeof ContextoDiarioSchema>

const titulos: Record<GrupoDiario['tipo'], string> = {
  primera_atencion: 'Gestión inicial pendiente', tarea_vencida: 'Tareas vencidas',
  seguimiento: 'Seguimientos por retomar', revision_comercial: 'Casos por decidir',
  datos_incompletos: 'Fichas por revisar', por_repartir: 'Leads por repartir',
  parado_2h: 'Más de dos horas sin llamadas',
}

/** Consume grupos del servidor. Solo tareas/reparto conservan el libro previo. */
export function alertaDiariaAAlertaCRM(grupo: GrupoDiario, supervisor: string, contexto?: ContextoDiario): AlertaCRM {
  const esInactividad = grupo.tipo === 'parado_2h'
  return {
    id: grupo.id,
    tipo: esInactividad ? 'parado_2h' : grupo.tipo === 'tarea_vencida' || grupo.tipo === 'por_repartir'
      ? grupo.tipo : 'seguimiento_comercial',
    diaria: true, severidad: grupo.severidad, alcance: 'equipo', titulo: titulos[grupo.tipo],
    detalle: esInactividad
      ? (contexto?.equipo.filter((e) => grupo.miembros.includes(e.analista_id)).map((e) => e.nombre).join(', ') ?? '')
      : `${grupo.total} ${grupo.total === 1 ? 'oportunidad por revisar' : 'oportunidades por revisar'}. Un caso puede tener problemas distintos.`,
    responsableId: supervisor, responsable: 'Mi equipo', valor: grupo.total,
    destino: { vista: esInactividad ? 'gestion-diaria' : 'seguimiento', etiqueta: esInactividad ? 'Revisar equipo' : 'Ver pendientes' },
    ...(grupo.tipo === 'tarea_vencida' || grupo.tipo === 'por_repartir' ? { miembros: grupo.miembros } : {}),
  }
}
