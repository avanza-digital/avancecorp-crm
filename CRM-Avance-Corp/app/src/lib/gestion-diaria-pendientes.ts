import { identidadClienteValida } from './sujeto-gestion'
import * as v from 'valibot'
import type { Lead, Tarea } from './tipos'

// PostgreSQL conserva microsegundos: Date.parse solo no sirve para comparar
// cursores que difieren dentro del mismo milisegundo.
export function instantePendiente(valor: string): bigint | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$/.exec(valor)
  if (!m) return null
  const [ano, mes, dia, hora, minuto, segundo] = m.slice(1, 7).map(Number)
  const fecha = new Date(Date.UTC(ano!, mes! - 1, dia!))
  if (fecha.getUTCFullYear() !== ano || fecha.getUTCMonth() + 1 !== mes || fecha.getUTCDate() !== dia
    || hora! > 23 || minuto! > 59 || segundo! > 59) return null
  const entero = Date.parse(`${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${m[8]}`)
  return Number.isFinite(entero) ? BigInt(entero) * 1000n + BigInt((m[7] ?? '').padEnd(6, '0')) : null
}

const Uuid = v.pipe(v.string(), v.uuid())
const Fecha = v.pipe(v.string(), v.check(s => instantePendiente(s) !== null))
const Natural = v.pipe(v.number(), v.check(n => Number.isSafeInteger(n) && n >= 0))
export const CursorPendientesSchema = v.strictObject({ despues_de: Fecha, despues_id: Uuid })
export type CursorPendientes = v.InferOutput<typeof CursorPendientesSchema>
export const PendienteSupervisorSchema = v.strictObject({
  id: Uuid, vendedor_id: Uuid, tipo: v.string(), titulo: v.string(), vence_en: Fecha,
  estado: v.literal('pendiente'), referencia_tipo: v.picklist(['lead', 'perfil', 'postventa']),
  lead_id: v.nullable(Uuid), lead_nombre: v.nullable(v.string()),
  sujeto_tipo: v.optional(v.picklist(['perfil', 'inversionista'])),
  sujeto_id: v.optional(v.nullable(Uuid)), sujeto_nombre: v.optional(v.string()),
  inversionista_id: v.optional(v.nullable(Uuid)), perfil_id: v.optional(v.nullable(Uuid)), identidad_visible: v.optional(v.boolean()),
})
export type PendienteSupervisor = v.InferOutput<typeof PendienteSupervisorSchema>
export const PaginaPendientesSchema = v.strictObject({
  version: v.union([v.literal(1), v.literal(2)]), zona: v.literal('America/Lima'), supervisor_id: Uuid, analista_id: Uuid,
  generado_en: Fecha, pendientes_al: Fecha, solo_vencidas: v.boolean(),
  limite: v.pipe(Natural, v.minValue(1), v.maxValue(100)),
  resumen: v.strictObject({ tareas_pendientes: Natural, tareas_vencidas: Natural }),
  items: v.array(PendienteSupervisorSchema), hay_mas: v.boolean(),
  siguiente_cursor: v.nullable(CursorPendientesSchema),
})
export type PaginaPendientes = v.InferOutput<typeof PaginaPendientesSchema>
export interface PedidoPendientes {
  supervisor: string; analista: string; soloVencidas: boolean; limite: number; cursor: CursorPendientes | null
}

export function compararPendientes(a: Pick<PendienteSupervisor, 'vence_en' | 'id'>, b: Pick<PendienteSupervisor, 'vence_en' | 'id'>): number {
  const x = instantePendiente(a.vence_en), y = instantePendiente(b.vence_en)
  if (x === null || y === null) throw new Error('Fecha de tarea inválida')
  const idA = a.id.toLowerCase(), idB = b.id.toLowerCase()
  return x < y ? -1 : x > y ? 1 : idA < idB ? -1 : idA > idB ? 1 : 0
}

/** Frontera estricta: jamás descartar una fila para aparentar lista completa. */
export function validarPaginaPendientes(valor: unknown, pedido: PedidoPendientes): PaginaPendientes | null {
  if (pedido.cursor && !v.safeParse(CursorPendientesSchema, pedido.cursor).success) return null
  const parsed = v.safeParse(PaginaPendientesSchema, valor)
  if (!parsed.success) return null
  const p = parsed.output, total = p.solo_vencidas ? p.resumen.tareas_vencidas : p.resumen.tareas_pendientes
  if (p.supervisor_id !== pedido.supervisor || p.analista_id !== pedido.analista
    || p.solo_vencidas !== pedido.soloVencidas || p.limite !== pedido.limite
    || p.resumen.tareas_vencidas > p.resumen.tareas_pendientes || p.items.length > p.limite
    || p.items.length > total || p.hay_mas !== (p.siguiente_cursor !== null)
    || (p.hay_mas && (p.items.length !== p.limite || total <= p.items.length))
    || (!pedido.cursor && !p.hay_mas && p.items.length !== total)
    || instantePendiente(p.generado_en) !== instantePendiente(p.pendientes_al)) return null
  const ids = new Set<string>()
  let anterior = pedido.cursor ? { vence_en: pedido.cursor.despues_de, id: pedido.cursor.despues_id } : null
  for (const item of p.items) {
    if (item.sujeto_tipo !== undefined && !identidadClienteValida(item)) return null
    if (ids.has(item.id.toLowerCase()) || item.vendedor_id !== pedido.analista
      || (anterior && compararPendientes(item, anterior) <= 0)
      || (p.solo_vencidas && instantePendiente(item.vence_en)! >= instantePendiente(p.pendientes_al)!)
      || ((item.lead_id === null) !== (item.lead_nombre === null))
      || (item.lead_nombre !== null && !item.lead_nombre.trim())
      || (item.referencia_tipo !== 'lead' && item.lead_id !== null)) return null
    ids.add(item.id.toLowerCase()); anterior = item
  }
  const ultima = p.items.at(-1)
  if (p.siguiente_cursor && (!ultima || compararPendientes(ultima, {
    vence_en: p.siguiente_cursor.despues_de, id: p.siguiente_cursor.despues_id,
  }) !== 0)) return null
  return p
}

/** Una reprogramación puede repetir un ID en otra página: gana su última foto. */
export function unirPaginasPendientes(paginas: readonly PaginaPendientes[]): PendienteSupervisor[] {
  const porId = new Map<string, PendienteSupervisor>()
  for (const pagina of paginas) for (const item of pagina.items) porId.set(item.id.toLowerCase(), item)
  return [...porId.values()].sort(compararPendientes)
}

/** Sólo demo: el store demo sí es completo y ya está acotado por su ámbito. */
export function pendientesDesdeDemo(pedido: PedidoPendientes, tareas: readonly Tarea[], leads: readonly Lead[], ahora: number): PaginaPendientes {
  const base = tareas.filter(t => t.activo && t.estado === 'pendiente' && t.vendedor_id === pedido.analista)
  const porId = new Map(leads.filter(l => l.activo).map(l => [l.id, l]))
  const items: PendienteSupervisor[] = base.map(t => {
    if ([t.lead_id, t.perfil_id, t.inversionista_id].filter(Boolean).length !== 1 || instantePendiente(t.vence_en) === null) {
      throw new Error('No se pudo confirmar la integridad de las tareas demo')
    }
    const lead = t.lead_id ? porId.get(t.lead_id) : undefined
    return { id: t.id, vendedor_id: pedido.analista, tipo: t.tipo, titulo: t.titulo, vence_en: t.vence_en,
      estado: 'pendiente', referencia_tipo: t.lead_id ? 'lead' : t.perfil_id ? 'perfil' : 'postventa',
      lead_id: lead?.nombre_completo.trim() ? lead.id : null, lead_nombre: lead?.nombre_completo.trim() || null }
  })
  const vencidas = items.filter(t => instantePendiente(t.vence_en)! < BigInt(ahora) * 1000n)
  const seleccion = (pedido.soloVencidas ? vencidas : items).sort(compararPendientes)
    .filter(t => !pedido.cursor || compararPendientes(t, { id: pedido.cursor.despues_id, vence_en: pedido.cursor.despues_de }) > 0)
  const pagina = seleccion.slice(0, pedido.limite), ultima = pagina.at(-1), hayMas = seleccion.length > pedido.limite
  return { version: 1, zona: 'America/Lima', supervisor_id: pedido.supervisor, analista_id: pedido.analista,
    generado_en: new Date(ahora).toISOString(), pendientes_al: new Date(ahora).toISOString(),
    solo_vencidas: pedido.soloVencidas, limite: pedido.limite,
    resumen: { tareas_pendientes: items.length, tareas_vencidas: vencidas.length }, items: pagina,
    hay_mas: hayMas, siguiente_cursor: hayMas && ultima ? { despues_de: ultima.vence_en, despues_id: ultima.id } : null }
}
