import * as v from 'valibot'
import type { ClienteCrm } from '@/lib/supabase'
import type { Lead } from '@/lib/tipos'
import type { GestionCartera } from '@/lib/cartera-keyset'
import { registrarError } from '@/lib/observabilidad'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const FECHA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.(\d{1,6}))?(?:Z|[+-]\d{2}:\d{2})$/
const LOTE_MAXIMO = 100
const RespuestaSchema = v.object({ version: v.literal(1), items: v.array(v.object({
  lead_id: v.string(), vendedor_id: v.nullable(v.string()), tenencia_desde: v.nullable(v.string()),
  gestion_vigente: v.boolean(),
})) })

/** Compara instantes preservando los microsegundos de Postgres y la zona horaria. */
function sello(fecha: string | null | undefined): bigint | null {
  if (!fecha) return null
  const partes = FECHA.exec(fecha)
  // Date.parse solo recibe milisegundos ISO estándar; el resto se suma abajo.
  const ms = Date.parse(fecha.replace(/\.(\d+)(Z|[+-]\d{2}:\d{2})$/, (_, fraccion: string, zona: string) => `.${fraccion.padEnd(3, '0').slice(0, 3)}${zona}`))
  if (!partes || !Number.isFinite(ms)) return null
  return BigInt(ms) * 1000n + BigInt((partes[1] ?? '').padEnd(6, '0').slice(3))
}

/** Una lectura operativa por página. El servidor aplica RLS y la regla de
 * contacto vigente; no descarga historiales. Ausencias, errores o una tenencia
 * distinta quedan sin verificar, nunca se convierten en «no gestionado».
 */
export async function conGestionVigente(
  cliente: ClienteCrm, leads: Lead[], signal?: AbortSignal, filtro?: GestionCartera | null,
): Promise<Lead[]> {
  signal?.throwIfAborted()
  const estados = new Map<string, boolean | null>()
  const pendientes = new Map<string, Lead>()
  for (const l of leads) {
    if (l.etapa !== 'nuevo' || !l.activo || l.vendedor_id == null || l.tenencia_desde == null) estados.set(l.id, false)
    else if (filtro) estados.set(l.id, filtro === 'con_gestion')
    else {
      estados.set(l.id, null)
      if (UUID.test(l.id) && UUID.test(l.vendedor_id) && sello(l.tenencia_desde) !== null) pendientes.set(l.id, l)
    }
  }
  const ids = [...pendientes.keys()]
  for (let inicio = 0; inicio < ids.length; inicio += LOTE_MAXIMO) {
    signal?.throwIfAborted()
    const lote = ids.slice(inicio, inicio + LOTE_MAXIMO)
    let consulta = cliente.schema('crm').rpc('gestion_vigente_fn', { p_lead_ids: lote })
    if (signal) consulta = consulta.abortSignal(signal)
    const { data, error } = await consulta
    signal?.throwIfAborted()
    const respuesta = v.safeParse(RespuestaSchema, data)
    if (error || !respuesta.success || respuesta.output.items.some((f) => !lote.includes(f.lead_id))
      || new Set(respuesta.output.items.map((f) => f.lead_id)).size !== respuesta.output.items.length) {
      registrarError('crm.leads.gestion_no_verificada', new Error('No se pudo verificar la gestión de la página.'))
      continue
    }
    for (const fila of respuesta.output.items) {
      const previo = pendientes.get(fila.lead_id)!
      if (fila.vendedor_id === previo.vendedor_id && sello(fila.tenencia_desde) === sello(previo.tenencia_desde)) {
        estados.set(fila.lead_id, fila.gestion_vigente)
      }
    }
  }
  return leads.map((l) => ({ ...l, gestion_vigente: estados.get(l.id) ?? null }))
}
