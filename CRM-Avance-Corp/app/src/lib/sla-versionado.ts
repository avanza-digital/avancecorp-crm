import * as v from 'valibot'
import {
  EnteroNoNegativoRpcSchema,
  FechaHoraSchema,
  UuidSchema,
} from './esquemas-rpc'

export const ETAPAS_SLA = [
  'nuevo',
  'contactado',
  'reunion_agendada',
  'propuesta_enviada',
] as const

const MinutosSchema = v.pipe(
  EnteroNoNegativoRpcSchema,
  v.minValue(1),
  v.maxValue(43_200),
)

export const ReglaEtapaSlaSchema = v.strictObject({
  etapa: v.picklist(ETAPAS_SLA),
  maximo_minutos: MinutosSchema,
})

export const ReglasEtapaSlaSchema = v.pipe(
  v.array(ReglaEtapaSlaSchema),
  v.length(4),
  v.check(
    (reglas) => {
      const etapas = new Set(reglas.map((regla) => regla.etapa))
      return etapas.size === ETAPAS_SLA.length
        && ETAPAS_SLA.every((etapa) => etapas.has(etapa))
    },
    'La política SLA debe definir las cuatro etapas',
  ),
)

export const PoliticaSlaSchema = v.pipe(
  v.strictObject({
    id: UuidSchema,
    version: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
    version_anterior_id: v.nullable(UuidSchema),
    vigente_desde: v.string(),
    zona_horaria: v.literal('America/Lima'),
    tipo_reloj: v.literal('corrido'),
    primera_gestion_minutos: MinutosSchema,
    primer_contacto_minutos: MinutosSchema,
    publicada_por: v.nullable(UuidSchema),
    publicada_por_nombre: v.nullable(v.string()),
    publicada_en: FechaHoraSchema,
    etapas: ReglasEtapaSlaSchema,
  }),
  v.check(
    (politica) => politica.primer_contacto_minutos >= politica.primera_gestion_minutos,
    'El primer contacto no puede vencer antes que la primera gestión',
  ),
)

export const ConfiguracionSlaSchema = v.strictObject({
  version: v.literal(1),
  expected_version: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
  puede_editar: v.boolean(),
  politica: PoliticaSlaSchema,
})

export const ResultadoPublicacionSlaSchema = v.pipe(
  v.strictObject({
    id: UuidSchema,
    version: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(2)),
    version_anterior_id: UuidSchema,
    vigente_desde: FechaHoraSchema,
    zona_horaria: v.literal('America/Lima'),
    tipo_reloj: v.literal('corrido'),
    primera_gestion_minutos: MinutosSchema,
    primer_contacto_minutos: MinutosSchema,
    publicada_por: UuidSchema,
    publicada_en: FechaHoraSchema,
  }),
  v.check(
    (politica) => politica.primer_contacto_minutos >= politica.primera_gestion_minutos,
    'El primer contacto no puede vencer antes que la primera gestión',
  ),
)

export const RespuestaPublicacionSlaSchema = v.pipe(
  v.array(ResultadoPublicacionSlaSchema),
  v.length(1),
)

const CamposGrupoSla = {
  politica_id: UuidSchema,
  politica_version: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
  objetivo_minutos: MinutosSchema,
  total: EnteroNoNegativoRpcSchema,
  evaluables: EnteroNoNegativoRpcSchema,
  cumplidos: EnteroNoNegativoRpcSchema,
  fuera_objetivo: EnteroNoNegativoRpcSchema,
  pendientes: EnteroNoNegativoRpcSchema,
} as const

const GrupoSlaSchema = v.pipe(
  v.strictObject(CamposGrupoSla),
  v.check(
    (grupo) => grupo.cumplidos + grupo.fuera_objetivo === grupo.evaluables
      && grupo.evaluables + grupo.pendientes === grupo.total,
    'Totales SLA incoherentes',
  ),
)

const GrupoEtapaSlaSchema = v.pipe(
  v.strictObject({ ...CamposGrupoSla, etapa: v.picklist(ETAPAS_SLA) }),
  v.check(
    (grupo) => grupo.cumplidos + grupo.fuera_objetivo === grupo.evaluables
      && grupo.evaluables + grupo.pendientes === grupo.total,
    'Totales SLA de etapa incoherentes',
  ),
)

export const MetricasSlaSchema = v.strictObject({
  version: v.literal(1),
  generado_en: FechaHoraSchema,
  periodo: v.strictObject({
    desde: v.string(),
    hasta: v.string(),
    zona: v.literal('America/Lima'),
  }),
  ciclos: v.strictObject({
    primera_gestion: v.array(GrupoSlaSchema),
    primer_contacto: v.array(GrupoSlaSchema),
  }),
  asignaciones: v.strictObject({
    primera_gestion: v.array(GrupoSlaSchema),
    primer_contacto: v.array(GrupoSlaSchema),
  }),
  etapas: v.array(GrupoEtapaSlaSchema),
})

export const EstadoSlaLeadSchema = v.pipe(
  v.strictObject({
    lead_id: UuidSchema,
    ciclo_politica_id: UuidSchema,
    ciclo_politica_version: v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1)),
    primera_gestion_limite_en: FechaHoraSchema,
    primera_gestion_en: v.nullable(FechaHoraSchema),
    primer_contacto_limite_en: FechaHoraSchema,
    primer_contacto_en: v.nullable(FechaHoraSchema),
    ciclo_aproximado: v.boolean(),
    asignacion_id: v.nullable(UuidSchema),
    asignacion_politica_id: v.nullable(UuidSchema),
    asignacion_politica_version: v.nullable(v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1))),
    asignacion_primera_gestion_limite_en: v.nullable(FechaHoraSchema),
    asignacion_primera_gestion_en: v.nullable(FechaHoraSchema),
    asignacion_primer_contacto_limite_en: v.nullable(FechaHoraSchema),
    asignacion_primer_contacto_en: v.nullable(FechaHoraSchema),
    etapa_politica_id: v.nullable(UuidSchema),
    etapa_politica_version: v.nullable(v.pipe(EnteroNoNegativoRpcSchema, v.minValue(1))),
    etapa: v.nullable(v.picklist(ETAPAS_SLA)),
    etapa_iniciada_en: v.nullable(FechaHoraSchema),
    etapa_limite_en: v.nullable(FechaHoraSchema),
    etapa_objetivo_minutos: v.nullable(MinutosSchema),
    etapa_aproximada: v.nullable(v.boolean()),
  }),
  v.check((estado) => {
    const asignacionCompleta = estado.asignacion_id === null
      ? estado.asignacion_politica_id === null
        && estado.asignacion_politica_version === null
        && estado.asignacion_primera_gestion_limite_en === null
        && estado.asignacion_primera_gestion_en === null
        && estado.asignacion_primer_contacto_limite_en === null
        && estado.asignacion_primer_contacto_en === null
      : estado.asignacion_politica_id !== null
        && estado.asignacion_politica_version !== null
        && estado.asignacion_primera_gestion_limite_en !== null
        && estado.asignacion_primer_contacto_limite_en !== null
    const etapaCompleta = estado.etapa === null
      ? estado.etapa_politica_id === null
        && estado.etapa_politica_version === null
        && estado.etapa_iniciada_en === null
        && estado.etapa_limite_en === null
        && estado.etapa_objetivo_minutos === null
        && estado.etapa_aproximada === null
      : estado.etapa_politica_id !== null
        && estado.etapa_politica_version !== null
        && estado.etapa_iniciada_en !== null
        && estado.etapa_limite_en !== null
        && estado.etapa_objetivo_minutos !== null
        && estado.etapa_aproximada !== null
    return asignacionCompleta && etapaCompleta
  }, 'Fotografía SLA viva incompleta'),
)

export const EstadosSlaLeadsSchema = v.pipe(
  v.array(EstadoSlaLeadSchema),
  v.check(
    (estados) => new Set(estados.map((estado) => estado.lead_id)).size === estados.length,
    'La fotografía SLA contiene más de una fila para un lead',
  ),
)

export type PoliticaSla = v.InferOutput<typeof PoliticaSlaSchema>
export type ConfiguracionSla = v.InferOutput<typeof ConfiguracionSlaSchema>
export type ResultadoPublicacionSla = v.InferOutput<typeof ResultadoPublicacionSlaSchema>
export type MetricasSla = v.InferOutput<typeof MetricasSlaSchema>
export type EstadoSlaLead = v.InferOutput<typeof EstadoSlaLeadSchema>
export type ReglaEtapaSla = v.InferOutput<typeof ReglaEtapaSlaSchema>
export type IndiceEstadoSlaLeads = ReadonlyMap<string, EstadoSlaLead>

export interface PublicacionSla {
  zona_horaria: 'America/Lima'
  tipo_reloj: 'corrido'
  primera_gestion_minutos: number
  primer_contacto_minutos: number
  etapas: ReglaEtapaSla[]
}

export function umbralesEtapaMs(
  politica: Pick<PoliticaSla, 'etapas'> | null | undefined,
): Partial<Record<(typeof ETAPAS_SLA)[number], number>> {
  if (!politica) return {}
  return Object.fromEntries(
    politica.etapas.map((regla) => [regla.etapa, regla.maximo_minutos * 60_000]),
  )
}

export function minutosLegibles(minutos: number): string {
  if (minutos % 1_440 === 0) {
    const dias = minutos / 1_440
    return dias === 1 ? '1 día' : `${dias} días`
  }
  if (minutos % 60 === 0) {
    const horas = minutos / 60
    return horas === 1 ? '1 hora' : `${horas} horas`
  }
  return `${minutos} min`
}

/**
 * Fotografía viva por lead. La base garantiza una fila por ciclo abierto; este
 * índice evita buscar O(leads) en cada card y conserva el contrato explícito de
 * que los plazos vienen sellados por episodio, nunca de la política vigente.
 */
export function indexarEstadoSlaLeads(
  estados: readonly EstadoSlaLead[],
): IndiceEstadoSlaLeads {
  return new Map(estados.map((estado) => [estado.lead_id, estado]))
}
