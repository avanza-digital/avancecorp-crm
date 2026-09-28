// G4b (27/09/2026): la lista EXACTA de «Citas agendadas» de Gestión Diaria —tareas
// `reunion` CREADAS en el día Lima—, la misma definición que la cifra. La frontera es
// estricta: forma cerrada y coherencia de cada página (día, ámbito, orden, cursor,
// total). Nunca se descarta una fila para aparentar una lista completa.
import * as v from 'valibot'
import { instantePendiente } from './gestion-diaria-pendientes'
import { citasDelDiaDemo, type MundoDemo } from './gestion-diaria-pulso-demo'

export type AmbitoCitas = 'analista' | 'equipo' | 'fuera' | 'operacion'
export const ESTADOS_CITA = ['pendiente', 'completada', 'cancelada', 'no_show'] as const
export type EstadoCita = (typeof ESTADOS_CITA)[number]

const Uuid = v.pipe(v.string(), v.uuid())
const Instante = v.pipe(v.string(), v.check((s) => instantePendiente(s) !== null))
const Dia = v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/))
const Natural = v.pipe(v.number(), v.check((n) => Number.isSafeInteger(n) && n >= 0))
const Nombre = v.nullable(v.pipe(v.string(), v.check((s) => s.trim().length > 0)))

export const CursorCitasSchema = v.strictObject({ despues_de: Instante, despues_id: Uuid })
export type CursorCitas = v.InferOutput<typeof CursorCitasSchema>
export const CitaAgendadaSchema = v.strictObject({
  id: Uuid, vendedor_id: v.nullable(Uuid), vendedor_nombre: Nombre,
  lead_id: v.nullable(Uuid), lead_nombre: Nombre,
  vence_en: Instante, estado: v.picklist(ESTADOS_CITA), creado_en: Instante,
})
export type CitaAgendada = v.InferOutput<typeof CitaAgendadaSchema>
export const PaginaCitasSchema = v.strictObject({
  version: v.literal(1), zona: v.literal('America/Lima'), dia: Dia,
  ambito: v.picklist(['analista', 'equipo', 'fuera', 'operacion']), id: v.nullable(Uuid),
  generado_en: Instante, limite: v.pipe(Natural, v.minValue(1), v.maxValue(100)),
  resumen: v.strictObject({ total: Natural }),
  items: v.array(CitaAgendadaSchema), hay_mas: v.boolean(), siguiente_cursor: v.nullable(CursorCitasSchema),
})
export type PaginaCitas = v.InferOutput<typeof PaginaCitasSchema>
export interface PedidoCitas { dia: string; ambito: AmbitoCitas; id: string | null; limite: number; cursor: CursorCitas | null }

/** Orden del servidor: (creado_en, id), con microsegundos. */
export function compararCitas(a: Pick<CitaAgendada, 'creado_en' | 'id'>, b: Pick<CitaAgendada, 'creado_en' | 'id'>): number {
  const x = instantePendiente(a.creado_en), y = instantePendiente(b.creado_en)
  if (x === null || y === null) throw new Error('Fecha de cita inválida')
  const idA = a.id.toLowerCase(), idB = b.id.toLowerCase()
  return x < y ? -1 : x > y ? 1 : idA < idB ? -1 : idA > idB ? 1 : 0
}

/** [inicio, fin) del día Lima en microsegundos (Lima no cambia de hora: UTC−5). */
function ventanaDia(dia: string): [bigint, bigint] | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dia)
  if (!m) return null
  const inicio = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), 5)
  const fecha = new Date(inicio)
  if (fecha.getUTCFullYear() !== Number(m[1]) || fecha.getUTCMonth() + 1 !== Number(m[2]) || fecha.getUTCDate() !== Number(m[3])) return null
  return [BigInt(inicio) * 1000n, BigInt(inicio + 86_400_000) * 1000n]
}

const mismoId = (a: string | null, b: string | null) => (a === null || b === null) ? a === b : a.toLowerCase() === b.toLowerCase()

export function validarPaginaCitas(valor: unknown, pedido: PedidoCitas): PaginaCitas | null {
  if (pedido.cursor && !v.safeParse(CursorCitasSchema, pedido.cursor).success) return null
  const parsed = v.safeParse(PaginaCitasSchema, valor)
  const ventana = ventanaDia(pedido.dia)
  if (!parsed.success || !ventana) return null
  const p = parsed.output
  if (p.dia !== pedido.dia || p.ambito !== pedido.ambito || !mismoId(p.id, pedido.id) || p.limite !== pedido.limite
    || p.items.length > p.limite || p.items.length > p.resumen.total
    || p.hay_mas !== (p.siguiente_cursor !== null)
    || (p.hay_mas && (p.items.length !== p.limite || p.resumen.total <= p.items.length))
    || (!pedido.cursor && !p.hay_mas && p.items.length !== p.resumen.total)) return null
  const ids = new Set<string>()
  let anterior = pedido.cursor ? { creado_en: pedido.cursor.despues_de, id: pedido.cursor.despues_id } : null
  for (const item of p.items) {
    const creada = instantePendiente(item.creado_en)!
    if (ids.has(item.id.toLowerCase()) || creada < ventana[0] || creada >= ventana[1]
      || (anterior && compararCitas(item, anterior) <= 0)
      || (p.ambito === 'analista' && !mismoId(item.vendedor_id, pedido.id))
      || ((item.lead_id === null) !== (item.lead_nombre === null))) return null
    ids.add(item.id.toLowerCase()); anterior = item
  }
  const ultima = p.items.at(-1)
  if (p.siguiente_cursor && (!ultima || compararCitas(ultima, { creado_en: p.siguiente_cursor.despues_de, id: p.siguiente_cursor.despues_id }) !== 0)) return null
  return p
}

/** Las páginas se suman en orden; un id repetido conserva su última foto. */
export function unirPaginasCitas(paginas: readonly PaginaCitas[]): CitaAgendada[] {
  const porId = new Map<string, CitaAgendada>()
  for (const pagina of paginas) for (const item of pagina.items) porId.set(item.id.toLowerCase(), item)
  return [...porId.values()].sort(compararCitas)
}

/** Sólo demo: la misma forma que el servidor, con la atribución del pulso demo. */
export function citasDesdeDemo(pedido: PedidoCitas, mundo: Pick<MundoDemo, 'miembros' | 'leads' | 'tareas' | 'ahora'>): PaginaCitas {
  const leads = new Map(mundo.leads.map((l) => [l.id, l]))
  const nombres = new Map(mundo.miembros.map((m) => [m.perfil_id, m.nombre_completo]))
  const todas: CitaAgendada[] = citasDelDiaDemo(mundo, pedido.dia, pedido.ambito, pedido.id).map((t) => {
    const lead = t.lead_id ? leads.get(t.lead_id) : undefined
    const nombre = lead?.nombre_completo.trim() || null
    const dueno = (lead ? lead.vendedor_id : t.vendedor_id) ?? null
    return { id: t.id, vendedor_id: dueno, vendedor_nombre: dueno ? nombres.get(dueno)?.trim() || null : null,
      lead_id: nombre ? lead!.id : null, lead_nombre: nombre, vence_en: t.vence_en,
      estado: (ESTADOS_CITA as readonly string[]).includes(t.estado) ? t.estado as EstadoCita : 'pendiente', creado_en: t.creado_en }
  }).sort(compararCitas)
  const seleccion = todas.filter((c) => !pedido.cursor || compararCitas(c, { creado_en: pedido.cursor.despues_de, id: pedido.cursor.despues_id }) > 0)
  const pagina = seleccion.slice(0, pedido.limite), ultima = pagina.at(-1), hayMas = seleccion.length > pedido.limite
  return { version: 1, zona: 'America/Lima', dia: pedido.dia, ambito: pedido.ambito, id: pedido.id,
    generado_en: new Date(mundo.ahora).toISOString(), limite: pedido.limite, resumen: { total: todas.length }, items: pagina,
    hay_mas: hayMas, siguiente_cursor: hayMas && ultima ? { despues_de: ultima.creado_en, despues_id: ultima.id } : null }
}
