// Contrato F4.3. El servidor decide objetivos, recuperación, permisos y reloj.
// No recalcular cortes a partir de la caché de actividades del navegador.
import * as v from 'valibot'

const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
const Positivo = v.pipe(v.number(), v.integer(), v.minValue(1))
const Instante = v.pipe(v.string(), v.check((s) => Number.isFinite(Date.parse(s)), 'Instante inválido'))
export const CorteSchema = v.pipe(v.object({
  estado: v.picklist(['pendiente', 'sin_cartera', 'cumplido', 'recuperado', 'incumplido']),
  llamadas: v.nullable(Natural),
  objetivo: v.nullable(Positivo),
  base: v.nullable(Natural),
  llamadas_recuperacion: v.nullable(Natural),
  aviso_pendiente: v.boolean(),
  puede_avisar: v.boolean(),
}), v.check((c) => c.aviso_pendiente === (c.estado === 'incumplido')
  && (!c.puede_avisar || c.aviso_pendiente)
  && (c.estado !== 'pendiente' || c.llamadas === null)
  && (['pendiente', 'sin_cartera'].includes(c.estado)
    || (c.llamadas !== null && c.objetivo !== null && c.base !== null))
  && (c.estado !== 'recuperado' || c.llamadas_recuperacion !== null), 'Corte incompleto o aviso incoherente'))

export const CortesJornadaSchema = v.pipe(v.object({
  version: v.literal(1),
  politica_version: Positivo,
  estado: v.picklist(['desactivados', 'no_laborable', 'activo']),
  cartera_referencia: v.literal('consulta_actual'),
  inicio_jornada: v.nullable(Instante),
  fin_jornada: v.nullable(Instante),
  primer_corte_en: v.nullable(Instante),
  segundo_corte_en: v.nullable(Instante),
  equipo: v.array(v.object({
    analista_id: v.string(),
    cartera_abierta: v.boolean(),
    primer_corte: CorteSchema,
    segundo_corte: v.nullable(CorteSchema),
  })),
}), v.check((c) => {
  if (c.estado !== 'activo') return c.equipo.length === 0 && c.inicio_jornada === null
    && c.fin_jornada === null && c.primer_corte_en === null && c.segundo_corte_en === null
  if (c.inicio_jornada === null || c.fin_jornada === null || c.primer_corte_en === null) return false
  if (!(Date.parse(c.inicio_jornada) < Date.parse(c.primer_corte_en)
    && Date.parse(c.primer_corte_en) < Date.parse(c.fin_jornada))) return false
  if (c.segundo_corte_en !== null && !(Date.parse(c.primer_corte_en) < Date.parse(c.segundo_corte_en)
    && Date.parse(c.segundo_corte_en) < Date.parse(c.fin_jornada))) return false
  return new Set(c.equipo.map((f) => f.analista_id)).size === c.equipo.length && c.equipo.every((f) => {
    const primero = f.primer_corte, segundo = f.segundo_corte
    return (primero.estado !== 'sin_cartera') === f.cartera_abierta
      && primero.objetivo !== null && primero.base === primero.llamadas
      && (segundo === null) === (c.segundo_corte_en === null)
      && (segundo === null || ((segundo.estado !== 'sin_cartera') === f.cartera_abierta
        && segundo.estado !== 'recuperado' && segundo.llamadas_recuperacion === null
        && segundo.base === primero.base && (segundo.base === null) === (segundo.objetivo === null)))
  })
}, 'Cortes de jornada inconsistentes'))

export type CortesJornada = v.InferOutput<typeof CortesJornadaSchema>
