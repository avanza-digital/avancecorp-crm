import { camposIdentidadCliente, identidadClienteValida } from './sujeto-gestion'
import * as v from 'valibot'
import { ESTADOS_CITA, CursorCitasSchema, compararCitas, type CursorCitas } from './gestion-diaria-citas'
import { instantePendiente } from './gestion-diaria-pendientes'

const Uuid = v.pipe(v.string(), v.uuid())
const Natural = v.pipe(v.number(), v.integer(), v.minValue(0))
const Instante = v.pipe(v.string(), v.check(s => Number.isFinite(Date.parse(s))))
const Dia = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/))
const CifrasSchema = v.pipe(v.object({ gestiones: Natural, llamadas: Natural, contestadas: Natural, entrevistas: Natural, ultima_llamada_en: v.nullable(Instante) }), v.check(c => c.contestadas <= c.llamadas && c.llamadas + c.entrevistas <= c.gestiones && (c.llamadas === 0) === (c.ultima_llamada_en === null)))
const MEDIDAS = ['gestiones', 'llamadas', 'contestadas', 'entrevistas'] as const
const DesgloseSchema = v.pipe(v.object({ leads: CifrasSchema, clientes: CifrasSchema, total: CifrasSchema }),
  v.check(d => MEDIDAS.every(k => d.total[k] === d.leads[k] + d.clientes[k])))
export const ResumenGestionesSchema = v.pipe(v.object({
  version: v.literal(1), desde: Dia, hasta: Dia, zona: v.literal('America/Lima'), generado_en: Instante,
  totales: DesgloseSchema, analistas: v.array(v.object({ id: v.nullable(Uuid), nombre: v.string(), metricas: DesgloseSchema })),
}), v.check(d => new Set(d.analistas.map(a => a.id)).size === d.analistas.length
  && (['leads', 'clientes', 'total'] as const).every(g => MEDIDAS.every(k => d.totales[g][k] === d.analistas.reduce((n, a) => n + a.metricas[g][k], 0)))))
export type ResumenGestiones = v.InferOutput<typeof ResumenGestionesSchema>
export const CitaClienteSchema = v.pipe(v.object({
  ...camposIdentidadCliente, id: Uuid, vence_en: Instante, estado: v.picklist(ESTADOS_CITA),
  confirmada_en: v.nullable(Instante), resultado_reunion: v.nullable(v.string()), vendedor_id: v.nullable(Uuid), vendedor_nombre: v.string(),
}), v.check(i => identidadClienteValida(i)))
export const CitasClientesSchema = v.object({
  version: v.literal(1), desde: Dia, hasta: Dia, generado_en: Instante, limite: Natural,
  resumen: v.object({ total: Natural, pendientes: Natural, entrevistas: Natural, no_asistio: Natural, reprogramadas: Natural, canceladas: Natural }),
  items: v.array(CitaClienteSchema), hay_mas: v.boolean(), siguiente_cursor: v.nullable(CursorCitasSchema),
})
export type CitasClientes = v.InferOutput<typeof CitasClientesSchema>

export function citasClientesCoherentes(p: CitasClientes, desde: string, hasta: string, autores: readonly string[] | null, cursor: CursorCitas | null): boolean {
  const total = p.resumen
  if (p.desde !== desde || p.hasta !== hasta || p.limite !== 25
    || total.total !== total.pendientes + total.entrevistas + total.no_asistio + total.reprogramadas + total.canceladas
    || p.items.length > p.limite || p.items.length > total.total || p.hay_mas !== Boolean(p.siguiente_cursor)
    || (p.hay_mas && (p.items.length !== p.limite || total.total <= p.items.length))
    || (!cursor && !p.hay_mas && p.items.length !== total.total)) return false
  const inicio = instantePendiente(`${desde}T00:00:00-05:00`)
  const fin = instantePendiente(`${hasta}T23:59:59.999999-05:00`)
  if (inicio === null || fin === null) return false
  const ids = new Set<string>()
  let anterior = cursor ? { creado_en: cursor.despues_de, id: cursor.despues_id } : null
  for (const item of p.items) {
    const instante = instantePendiente(item.vence_en)
    const actual = { creado_en: item.vence_en, id: item.id }
    if (instante === null || instante < inicio || instante > fin || ids.has(item.id)
      || (autores && (!item.vendedor_id || !autores.includes(item.vendedor_id))) || (anterior && compararCitas(actual, anterior) <= 0)) return false
    ids.add(item.id); anterior = actual
  }
  return !p.siguiente_cursor || Boolean(anterior && compararCitas(anterior, {
    creado_en: p.siguiente_cursor.despues_de, id: p.siguiente_cursor.despues_id,
  }) === 0)
}
