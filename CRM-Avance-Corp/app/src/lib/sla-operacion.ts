import * as v from 'valibot'

const fecha = v.nullable(v.string())
const indicador = v.nullable(v.boolean())
const numero = v.nullable(v.number())
const tarea = v.nullable(v.object({ id: v.string(), tipo: v.string(), vence_en: v.string(), reprogramaciones: v.number() }))
export const EstadoSlaV2Schema = v.object({
  lead_id: v.string(), evaluacion: v.picklist(['completa', 'parcial', 'no_aplica']), motivos_datos: v.array(v.string()),
  seguimiento: v.object({ referencia_en: fecha, ultima_gestion_en: fecha, limite_en: fecha, vencido: indicador, accion_pendiente: indicador }),
  compromiso: v.object({ tarea, validez: v.string(), hasta_en: fecha, cobertura_activa: indicador }),
  etapa: v.object({ limite_original_en: fecha, limite_prorrogado_en: fecha, limite_operativo_en: fecha, techo_en: fecha,
    prorrogas_usadas: numero, prorrogas_restantes: numero, revision_requerida: indicador, motivos_revision: v.array(v.string()) }),
})
export type EstadoSlaV2 = v.InferOutput<typeof EstadoSlaV2Schema>
export const ModoSlaSchema = v.picklist(['legado', 'observacion', 'activo'])
const sobre = { version: v.literal(2), modo: ModoSlaSchema, control_revision: v.number(), calculado_en: v.string() }
export const EstadosSlaV2Schema = v.object({ ...sobre, filas: v.array(EstadoSlaV2Schema) })
export const SENALES_SLA = [
  ['todas', 'Todas las acciones'], ['primera_atencion', 'Primera atención'], ['tareas_vencidas', 'Tareas vencidas'],
  ['seguimientos_pendientes', 'Seguimiento pendiente'], ['revisiones', 'Revisión comercial'],
  ['datos_incompletos', 'Datos incompletos'], ['por_repartir', 'Por repartir'],
] as const
export type SenalSla = typeof SENALES_SLA[number][0]
export type FiltrosSla = { senal: SenalSla; etapa: string | null; analista_id: string | null }
export type CursorSla = Record<string, unknown>
const senales = v.object({ primera_atencion: v.boolean(), tareas_vencidas: v.boolean(), seguimientos_pendientes: v.boolean(),
  revisiones: v.boolean(), datos_incompletos: v.boolean(), por_repartir: v.boolean() })
const cursor = v.nullable(v.record(v.string(), v.unknown()))
export const ColaSlaPaginaSchema = v.object({ ...sobre,
  filtros: v.object({ senal: v.string(), etapa: v.nullable(v.string()), analista_id: v.nullable(v.string()) }),
  limite: v.number(), total_items: v.number(), hay_mas: v.boolean(), cursor_siguiente: cursor,
  rango: v.object({ desde: v.number(), hasta: v.number() }),
  totales: v.object({ primera_atencion: v.number(), tareas_vencidas: v.number(), seguimientos_pendientes: v.number(), revisiones: v.number(), datos_incompletos: v.number(), por_repartir: v.number() }),
  items: v.array(v.object({ lead_id: v.string(), bucket: v.string(), severidad: v.picklist(['critica', 'media', 'baja']),
    prioridad: v.number(), referencia_en: fecha, tarea_id: v.nullable(v.string()),
    lead: v.object({ id: v.string(), nombre_completo: v.string(), etapa: v.string(), analista_id: v.nullable(v.string()), analista_nombre: v.nullable(v.string()) }),
    senales, estado: EstadoSlaV2Schema,
  })),
})
export type ColaSlaPagina = v.InferOutput<typeof ColaSlaPaginaSchema>
export const ACCIONES_SLA: Record<string, string> = {
  primera_atencion: 'Primera atención', tarea_vencida: 'Tarea vencida', tarea_hoy: 'Tarea de hoy',
  seguimiento: 'Seguimiento pendiente', revision_comercial: 'Revisión comercial', datos_incompletos: 'Revisar datos',
  proxima_tarea: 'Próxima tarea', por_repartir: 'Asignar analista',
}
export const MOTIVOS_REVISION_SLA: Record<string, string> = {
  limite_operativo_agotado: 'Se venció el plazo de esta etapa',
  reprogramaciones_agotadas: 'La actividad se reprogramó tres veces o más',
  reingreso_etapa: 'La oportunidad ingresó a esta etapa tres veces o más en este proceso comercial',
}
export function fechaSla(valor: string | null, formato: 'breve' | 'completa' = 'breve'): string {
  if (!valor || !Number.isFinite(Date.parse(valor))) return 'Sin fecha confirmada'
  return new Intl.DateTimeFormat('es-PE', {
    timeZone: 'America/Lima', day: formato === 'completa' ? 'numeric' : '2-digit',
    month: formato === 'completa' ? 'long' : 'short', ...(formato === 'completa' ? { year: 'numeric' as const } : {}),
    hour: '2-digit', minute: '2-digit',
  }).format(new Date(valor))
}

const reglaOperacion = v.object({ etapa: v.picklist(['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']),
  seguimiento_minutos: v.number(), prorroga_minutos: v.number(), prorroga_max: v.number(),
  tope_extra_minutos: v.number(), pausa_habilitada: v.boolean(), pausa_margen_minutos: v.number() })
const politicaOperacion = v.object({ base: v.object({ version: v.number() }), operacion: v.nullable(v.pipe(v.array(reglaOperacion), v.length(4), v.check((reglas) => new Set(reglas.map((r) => r.etapa)).size === 4))) })
export const ControlSlaSchema = v.object({ modo: ModoSlaSchema, revision: v.number(), primera_activacion_en: fecha, politica_adopcion_id: v.nullable(v.string()) })
export const ConfiguracionSlaV2Schema = v.object({ version: v.literal(2), puede_editar: v.boolean(), expected_version: v.number(),
  vigente: politicaOperacion, ultima_publicada: politicaOperacion, control: ControlSlaSchema,
  inicializacion_aprobada: v.optional(v.object({ disponible: v.boolean(), motivo: v.nullable(v.string()),
    config: v.object({ zona_horaria: v.string(), tipo_reloj: v.string(), primera_gestion_minutos: v.number(), primer_contacto_minutos: v.number(),
      etapas: v.pipe(v.array(v.object({ ...reglaOperacion.entries, maximo_minutos: v.number() })), v.length(4), v.check((reglas) => new Set(reglas.map((r) => r.etapa)).size === 4)),
    }),
  })),
})
export const ResultadoModoSlaSchema = v.object({ version: v.literal(2), ...ControlSlaSchema.entries })
export const ResultadoPublicacionSlaV2Schema = v.object({ version: v.literal(2), politica: politicaOperacion, expected_version: v.number() })
