import * as v from 'valibot'
import { CorteSchema } from './gestion-diaria-cortes'
import { fechaLima } from './agenda-derivada'
import { camposLlamadasF5, FechaF5, InstanteF5, llamadasCoherentes, NaturalF5, NumeroF5, tasaCoherente, TasaF5, desplazarDia } from './gestion-diaria-pulso'

const ContactoSchema = v.pipe(v.object({ ...camposLlamadasF5, tasa_contacto: TasaF5 }), v.check((d) => llamadasCoherentes(d) && tasaCoherente(d)))
const EstadoCortes = v.picklist(['activo', 'desactivados', 'no_laborable'])
const JornadaSchema = v.object({
  estado: v.picklist(['no_laborable', 'no_iniciada', 'en_curso', 'finalizada']),
  inicio: v.nullable(InstanteF5), cierre: v.nullable(InstanteF5), observado_hasta: v.nullable(InstanteF5),
  primera_en_jornada: v.nullable(InstanteF5), ultima_en_jornada: v.nullable(InstanteF5),
  silencio_inicio_minutos: v.nullable(NumeroF5), silencio_final_minutos: v.nullable(NumeroF5),
  hueco: v.nullable(v.pipe(v.object({ desde: InstanteF5, hasta: InstanteF5, minutos: NumeroF5 }),
    v.check((h) => Math.abs((Date.parse(h.hasta) - Date.parse(h.desde)) / 60_000 - h.minutos) < 0.051))),
})
const DiaHabitosSchema = v.pipe(v.object({
  dia: FechaF5, ...camposLlamadasF5, tasa_contacto: TasaF5,
  primera_llamada_en: v.nullable(InstanteF5), ultima_llamada_en: v.nullable(InstanteF5),
  minimo_llamadas_utiles: v.pipe(NaturalF5, v.minValue(1)), jornada: JornadaSchema,
  cortes: v.object({ estado: EstadoCortes, politica_version: NaturalF5, cartera_referencia: v.literal('consulta_actual'),
    primer_corte: v.nullable(CorteSchema), segundo_corte: v.nullable(CorteSchema) }),
}), v.check((d) => llamadasCoherentes(d) && tasaCoherente(d)
  && (d.jornada.hueco === null || (d.jornada.inicio !== null && d.jornada.observado_hasta !== null
    && Date.parse(d.jornada.hueco.desde) >= Date.parse(d.jornada.inicio)
    && Date.parse(d.jornada.hueco.hasta) <= Date.parse(d.jornada.observado_hasta)))
  && (d.cortes.estado === 'activo' || (d.cortes.primer_corte === null && d.cortes.segundo_corte === null))))
const PersonaHabitosSchema = v.pipe(v.object({
  analista_id: v.string(), nombre_completo: v.string(), supervisor_id: v.nullable(v.string()),
  dias: v.array(DiaHabitosSchema), resumen: ContactoSchema,
  equipo: v.object({ utiles: v.nullable(NaturalF5), contestadas: v.nullable(NaturalF5), tasa_contacto: TasaF5 }),
  distribucion_contacto: v.object({ dias_validos: NaturalF5, minimo: TasaF5, p25: TasaF5, mediana: TasaF5, p75: TasaF5, maximo: TasaF5 }),
  cumplimiento: v.object({ evaluables: NaturalF5, cumplidos_a_tiempo: NaturalF5, recuperados: NaturalF5,
    incumplidos: NaturalF5, pendientes: NaturalF5, sin_cartera: NaturalF5 }),
}), v.check((p) => (['llamadas', 'utiles', 'contestadas'] as const).every((k) => p.resumen[k] === p.dias.reduce((n, d) => n + d[k], 0))
  && p.cumplimiento.evaluables === p.cumplimiento.cumplidos_a_tiempo + p.cumplimiento.recuperados + p.cumplimiento.incumplidos
  && p.distribucion_contacto.dias_validos === p.dias.filter((d) => d.utiles >= d.minimo_llamadas_utiles).length))
export const HabitosGerenciaSchema = v.pipe(v.object({
  version: v.literal(1), generado_en: InstanteF5, desde: FechaF5, hasta: FechaF5,
  dias_solicitados: v.picklist([7, 14, 30]), dias_incluidos: v.pipe(NaturalF5, v.minValue(1)),
  organigrama_referencia: v.literal('consulta_actual'), cartera_referencia: v.literal('consulta_actual'),
  umbral_tasa_baja: v.null(), operacion: ContactoSchema,
  jornadas: v.array(v.object({ dia: FechaF5, minimo_llamadas_utiles: NaturalF5, estado_cortes: EstadoCortes, politica_version: NaturalF5 })),
  personas: v.array(PersonaHabitosSchema),
}), v.check((h) => h.dias_incluidos <= h.dias_solicitados && h.hasta === desplazarDia(h.desde, h.dias_incluidos - 1)
  && h.desde === [desplazarDia(h.hasta, 1 - h.dias_solicitados), desplazarDia(fechaLima(Date.parse(h.generado_en)), -365)].sort().at(-1)
  && h.jornadas.length === h.dias_incluidos && h.jornadas.every((j, i) => j.dia === desplazarDia(h.desde, i))
  && new Set(h.personas.map((p) => p.analista_id)).size === h.personas.length
  && h.personas.every((p) => p.dias.length === h.dias_incluidos && p.dias.every((d, i) => d.dia === h.jornadas[i]!.dia)),
'El período de hábitos no corresponde a sus jornadas'))
export type HabitosGerencia = v.InferOutput<typeof HabitosGerenciaSchema>
export type PersonaHabitos = HabitosGerencia['personas'][number]
