// F5: contratos de respuestas completas. El navegador valida y presenta;
// no rellena una respuesta parcial con cifras calculadas desde el store.
import * as v from 'valibot'
import { validarPeriodoGerencia } from '@/components/gerencia/periodo'

export const NumeroF5 = v.pipe(v.number(), v.finite(), v.minValue(0))
export const NaturalF5 = v.pipe(NumeroF5, v.integer())
export const TasaF5 = v.nullable(v.pipe(NumeroF5, v.maxValue(100)))
export const InstanteF5 = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s))))
export const FechaF5 = v.pipe(v.string(), v.check((s) => /^\d{4}-\d{2}-\d{2}$/.test(s)
  && Number.isFinite(Date.parse(`${s}T00:00:00Z`)) && new Date(`${s}T00:00:00Z`).toISOString().slice(0, 10) === s))

export const camposLlamadasF5 = { llamadas: NaturalF5, utiles: NaturalF5, contestadas: NaturalF5 }
export function llamadasCoherentes(d: { llamadas: number; utiles: number; contestadas: number }) {
  return d.contestadas <= d.utiles && d.utiles <= d.llamadas
}
export function tasaCoherente(d: { utiles: number; contestadas: number; tasa_contacto: number | null }) {
  return d.utiles === 0 ? d.tasa_contacto === null : d.tasa_contacto !== null
    && Math.abs(d.tasa_contacto - 100 * d.contestadas / d.utiles) < 0.051
}
const camposMetricas = {
  ...camposLlamadasF5, tasa_contacto: TasaF5, leads_unicos: NaturalF5,
  llamadas_por_lead: v.nullable(NumeroF5), citas_agendadas: NaturalF5,
  analistas_activos: NaturalF5, con_actividad: NaturalF5, sin_actividad: NaturalF5,
}
export const MetricasPulsoSchema = v.pipe(v.object(camposMetricas), v.check((m) => llamadasCoherentes(m)
  && tasaCoherente(m) && m.con_actividad + m.sin_actividad === m.analistas_activos
  && m.leads_unicos <= m.llamadas && (m.leads_unicos === 0 ? m.llamadas_por_lead === null
    : m.llamadas_por_lead !== null && Math.abs(m.llamadas_por_lead - m.llamadas / m.leads_unicos) < 0.0051)))
export type MetricasPulso = v.InferOutput<typeof MetricasPulsoSchema>
const camposMedia = Object.fromEntries(Object.keys(camposMetricas).map((k) => [k, v.nullable(NumeroF5)])) as Record<keyof MetricasPulso, v.NullableSchema<typeof NumeroF5, undefined>>
const PersonaSchema = v.pipe(v.object({
  ...camposLlamadasF5, analista_id: v.nullable(v.string()), nombre_completo: v.nullable(v.string()),
  activo: v.boolean(), supervisor_id: v.nullable(v.string()), clave_equipo: v.string(),
  gestiones: NaturalF5, citas_agendadas: NaturalF5, leads_tocados: NaturalF5,
  primera_llamada_en: v.nullable(InstanteF5), ultima_llamada_en: v.nullable(InstanteF5),
}), v.check((p) => llamadasCoherentes(p) && (!p.activo || (p.analista_id !== null && p.nombre_completo !== null))))
const ADITIVAS = ['llamadas', 'utiles', 'contestadas', 'citas_agendadas', 'analistas_activos', 'con_actividad', 'sin_actividad'] as const
const EquipoPulsoSchema = v.pipe(v.object({
  clave: v.string(), supervisor_id: v.nullable(v.string()), nombre: v.string(),
  personas: v.array(PersonaSchema), metricas: MetricasPulsoSchema, tareas_vencidas: NaturalF5,
  primer_intento_vencido: v.nullable(NaturalF5),
  dispersion: v.object({ personas: NaturalF5, minimo: TasaF5, maximo: TasaF5 }),
}), v.check((e) => e.clave === (e.supervisor_id ?? 'fuera') && e.personas.every((p) => p.clave_equipo === e.clave)
  && e.metricas.analistas_activos === e.personas.filter((p) => p.activo).length
  && e.metricas.con_actividad === e.personas.filter((p) => p.activo && p.gestiones > 0).length
  && (['llamadas', 'utiles', 'contestadas', 'citas_agendadas'] as const).every((k) => e.metricas[k] === e.personas.reduce((n, p) => n + p[k], 0))
  && (e.dispersion.personas === 0 ? e.dispersion.minimo === null && e.dispersion.maximo === null
    : e.dispersion.minimo !== null && e.dispersion.maximo !== null && e.dispersion.minimo <= e.dispersion.maximo)))
export const PulsoGerenciaSchema = v.pipe(v.object({
  version: v.literal(1), dia: FechaF5, generado_en: InstanteF5,
  organigrama_referencia: v.literal('consulta_actual'), minimo_llamadas_utiles: v.pipe(NaturalF5, v.minValue(1)),
  actual: MetricasPulsoSchema, ayer: v.object({ dia: FechaF5, metricas: MetricasPulsoSchema }),
  referencia: v.object({ dias: v.array(FechaF5), busqueda_desde: FechaF5, cantidad: NaturalF5, dias_con_tasa: NaturalF5, media: v.object(camposMedia) }),
  equipos: v.array(EquipoPulsoSchema), pendientes_al: InstanteF5, modo_sla: v.string(), vencidas_global: NaturalF5,
}), v.check((d) => {
  const r = d.referencia, personas = d.equipos.flatMap((e) => e.personas)
  return new Set(d.equipos.map((e) => e.clave)).size === d.equipos.length
    && d.equipos.some((e) => e.clave === 'fuera')
    && new Set(personas.map((p) => p.analista_id)).size === personas.length
    && ADITIVAS.every((k) => d.actual[k] === d.equipos.reduce((n, e) => n + e.metricas[k], 0))
    && d.vencidas_global === d.equipos.reduce((n, e) => n + e.tareas_vencidas, 0)
    && d.ayer.dia === desplazarDia(d.dia, -1) && r.busqueda_desde === desplazarDia(d.dia, -365)
    && r.cantidad === r.dias.length && r.cantidad <= 7 && new Set(r.dias).size === r.cantidad
    && r.dias.every((dia, i) => dia < d.dia && dia >= r.busqueda_desde && (i === 0 || dia < r.dias[i - 1]!))
    && r.dias_con_tasa <= r.cantidad && (r.cantidad !== 0 || Object.values(r.media).every((n) => n === null))
    && (r.dias_con_tasa > 0 || r.media.tasa_contacto === null)
    && (d.modo_sla === 'activo' || d.equipos.every((e) => e.primer_intento_vencido === null))
}, 'No se pudo conciliar la operación con los equipos y sus períodos'))
export type PulsoGerencia = v.InferOutput<typeof PulsoGerenciaSchema>
export type EquipoPulso = PulsoGerencia['equipos'][number]
export type PersonaPulso = EquipoPulso['personas'][number]

export function desplazarDia(dia: string, dias: number): string {
  return new Date(Date.parse(`${dia}T00:00:00Z`) + dias * 86_400_000).toISOString().slice(0, 10)
}
export function diaPulsoValido(dia: string, hoy: string): boolean {
  return validarPeriodoGerencia({ desde: dia, hasta: hoy }, Date.parse(`${hoy}T12:00:00-05:00`)).valido
}
export const cifraPulso = (n: number | null, porcentaje = false): string => n === null ? '—'
  : `${new Intl.NumberFormat('es-PE', { maximumFractionDigits: 2 }).format(n)}${porcentaje ? ' %' : ''}`
