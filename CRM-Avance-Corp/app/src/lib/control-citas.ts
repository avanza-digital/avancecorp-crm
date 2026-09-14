import * as v from 'valibot'
import { METAS_CITAS_INICIALES } from './metas-citas-config'

const DosDecimales = v.check<number>(n => Math.abs(n * 100 - Math.round(n * 100)) < 1e-7)
const Porcentaje = v.pipe(v.number(), v.finite(), v.minValue(1), v.maxValue(100), DosDecimales)
export const MesControlCitasSchema = v.nullable(v.pipe(v.string(), v.regex(/^(20\d{2})-(0[1-9]|1[0-2])$/)))
export const ControlCitasSchema = v.strictObject({
  citas_por_lead: v.pipe(v.number(), v.finite(), v.minValue(0.01), v.maxValue(10), DosDecimales),
  entrevistas_porcentaje: Porcentaje,
  depositos_porcentaje: Porcentaje,
  excluir_manuales_base: v.boolean(),
  actividad_manuales: v.nullable(v.picklist(['excluir', 'incluir'])),
  conteo_entrevistas: v.nullable(v.picklist(['citas_realizadas', 'personas_unicas'])),
  base_avance: v.nullable(v.picklist(['meta_proyectada', 'actividad_real'])),
  mes_resultado: v.nullable(v.picklist(['asignacion', 'evento'])),
  analista_resultado: v.nullable(v.picklist(['asignacion', 'evento'])),
  mes_inicio: MesControlCitasSchema,
  mostrar_meta_citas: v.literal(false),
  base_depositos: v.nullable(v.picklist(['personas_entrevistadas', 'entrevistas'])),
})
export type ControlCitas = v.InferOutput<typeof ControlCitasSchema>
export interface GuardarControlCitasInput {
  versionEsperada: number
  configuracion: ControlCitas
  nota: string
}

/** Acuerdos del usuario. La vigencia se elige al guardar y aplicar la versión. */
export function controlCitasInicial(): ControlCitas {
  return {
    ...METAS_CITAS_INICIALES,
    excluir_manuales_base: false, actividad_manuales: 'incluir', conteo_entrevistas: 'citas_realizadas',
    base_avance: 'actividad_real', mes_resultado: 'evento', analista_resultado: 'evento', mes_inicio: null,
    mostrar_meta_citas: false, base_depositos: 'personas_entrevistadas',
  }
}

export const OPCIONES_CONTROL_CITAS = {
  actividad_manuales: {
    etiqueta: 'Resultados de leads manuales',
    ayuda: 'Define si sus citas, entrevistas y conversiones aportan al cumplimiento.',
    opciones: { excluir: 'Excluir del cumplimiento', incluir: 'Incluir en el cumplimiento' },
  },
  conteo_entrevistas: {
    etiqueta: 'Cómo contar las entrevistas',
    ayuda: 'Una persona puede asistir a más de una cita.',
    opciones: { citas_realizadas: 'Cada cita con asistencia', personas_unicas: 'Cada persona una sola vez' },
  },
  base_avance: {
    etiqueta: 'Cómo medir el avance de entrevistas',
    ayuda: 'La tasa de gestión usa citas con resultado; excluye las futuras y las que todavía no tienen resultado.',
    opciones: { meta_proyectada: 'Entrevistas frente a la meta de citas', actividad_real: 'Entrevistas frente a citas con resultado' },
  },
  base_depositos: {
    etiqueta: 'Base del objetivo de depósitos',
    ayuda: 'Con la base de personas: 7 clientes de 10 personas entrevistadas son 70%, aunque algunas hayan venido varias veces.',
    opciones: { entrevistas: 'Todas las entrevistas realizadas', personas_entrevistadas: 'Personas entrevistadas, una vez por persona' },
  },
  mes_resultado: {
    etiqueta: 'Mes al que corresponde el resultado',
    ayuda: 'Define dónde se cuenta una asistencia o conversión que ocurre en un mes posterior.',
    opciones: { asignacion: 'Mes de asignación del lead', evento: 'Mes en que ocurre cada resultado' },
  },
  analista_resultado: {
    etiqueta: 'Analista al que corresponde el resultado',
    ayuda: 'Define a quién se atribuye cuando el lead cambia de responsable.',
    opciones: { asignacion: 'Analista que recibió el lead', evento: 'Analista responsable de cada evento' },
  },
} as const
export type ReglaControlCitas = keyof typeof OPCIONES_CONTROL_CITAS
export const REGLAS_CONTROL_CITAS = Object.keys(OPCIONES_CONTROL_CITAS) as ReglaControlCitas[]

export function pendientesControlCitas(config: ControlCitas): string[] {
  return [
    ...REGLAS_CONTROL_CITAS.filter(clave => config[clave] === null).map(clave => OPCIONES_CONTROL_CITAS[clave].etiqueta),
    ...(config.mes_inicio === null ? ['Mes de inicio'] : []),
  ]
}

/** Acepta coma o punto decimal sin convertir vacíos en cero ni truncar texto. */
export function numeroControlCitas(texto: string): number | null {
  if (!/^\d+(?:[.,]\d{1,2})?$/.test(texto.trim())) return null
  const numero = Number(texto.trim().replace(',', '.'))
  return Number.isFinite(numero) ? numero : null
}

export const textoNumeroControlCitas = (valor: number) => String(valor).replace('.', ',')

export function ejemploControlCitas(config: ControlCitas) {
  // Simulación explícita, sin datos reales: 100 asignados, 20 de registro propio.
  const leadsBase = config.excluir_manuales_base ? 80 : 100
  const citas = Math.ceil(leadsBase * Math.round(config.citas_por_lead * 100) / 100)
  return { leadsBase, citas }
}

const VersionControlCitasSchema = v.object({
  version: v.pipe(v.number(), v.integer(), v.minValue(1)),
  configuracion: ControlCitasSchema,
  guardado_en: v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s)))),
  guardado_por: v.pipe(v.string(), v.uuid()),
  nota: v.nullable(v.pipe(v.string(), v.maxLength(500))),
  estado: v.literal('borrador'),
})
export type VersionControlCitas = v.InferOutput<typeof VersionControlCitasSchema>
export const AplicacionControlCitasSchema = v.object({
  version: v.pipe(v.number(), v.integer(), v.minValue(1)),
  mes_inicio: v.pipe(v.string(), v.regex(/^(20\d{2})-(0[1-9]|1[0-2])$/)),
  aplicado_en: v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s)))),
  aplicado_por: v.pipe(v.string(), v.uuid()),
})
export const ConsultaControlCitasSchema = v.object({
  version_actual: v.pipe(v.number(), v.integer(), v.minValue(0)),
  ultimo: v.nullable(VersionControlCitasSchema),
  historial: v.pipe(v.array(VersionControlCitasSchema), v.maxLength(20)),
  aplicaciones: v.optional(v.array(AplicacionControlCitasSchema)),
})
export type ConsultaControlCitas = v.InferOutput<typeof ConsultaControlCitasSchema>

export function validarConsultaControlCitas(data: unknown): ConsultaControlCitas | null {
  const resultado = v.safeParse(ConsultaControlCitasSchema, data)
  if (!resultado.success) return null
  const consulta = resultado.output
  if (consulta.version_actual !== (consulta.ultimo?.version ?? 0)) return null
  if (consulta.historial.some((fila, i) => fila.version > consulta.version_actual
    || (i > 0 && fila.version >= consulta.historial[i - 1]!.version))) return null
  if (consulta.version_actual === 0 && consulta.historial.length > 0) return null
  if (consulta.version_actual > 0 && (consulta.historial[0]?.version !== consulta.version_actual
    || JSON.stringify(consulta.historial[0]) !== JSON.stringify(consulta.ultimo))) return null
  if (consulta.aplicaciones && (new Set(consulta.aplicaciones.map(a => a.version)).size !== consulta.aplicaciones.length
    || consulta.aplicaciones.some(a => a.version > consulta.version_actual))) return null
  return consulta
}
