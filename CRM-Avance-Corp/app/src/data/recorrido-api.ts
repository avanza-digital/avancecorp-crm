import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { registrarError } from '@/lib/observabilidad'
import { normalizarLeadIds } from '@/lib/cierre-estado'
import { RecorridosSchema, type Recorridos } from '@/lib/recorrido-lead'
import { CrmApiError } from './crm-api'

function cancelar(signal?: AbortSignal): void {
  if (signal?.aborted) throw signal.reason instanceof Error
    ? signal.reason : new DOMException('Consulta cancelada', 'AbortError')
}

function contrato(): CrmApiError {
  const error = new CrmApiError('No se pudo comprobar el recorrido del lead.', 'RECORRIDO_CONTRACT')
  registrarError('crm.recorrido.contrato', error)
  return error
}

/** Una lectura por página, en lotes de 100 y sin concurrencia ilimitada. */
export async function obtenerRecorridos(leadIds: readonly string[], signal?: AbortSignal): Promise<Recorridos | null> {
  const ids = normalizarLeadIds(leadIds)
  if (!ids.length) return null
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const respuestas: Recorridos[] = []
  for (let i = 0; i < ids.length; i += 100) {
    cancelar(signal)
    const lote = ids.slice(i, i + 100)
    let consulta = sb.schema('crm').rpc('recorrido_leads_fn', { p_lead_ids: lote })
    if (signal) consulta = consulta.abortSignal(signal)
    const { data, error } = await consulta
    cancelar(signal)
    // Instalación gradual: un backend anterior no interrumpe el CRM existente.
    if (error?.code === 'PGRST202') return null
    if (error) {
      const fallo = new CrmApiError('No se pudo comprobar el recorrido del lead.', error.code || 'POSTGREST_ERROR')
      registrarError('crm.recorrido.lectura', fallo)
      throw fallo
    }
    const parsed = v.safeParse(RecorridosSchema, data)
    if (!parsed.success) throw contrato()
    const respuesta = parsed.output
    const vistos = new Set<string>()
    for (const fila of respuesta.filas) {
      if (!lote.includes(fila.lead_id) || vistos.has(fila.lead_id)) throw contrato()
      vistos.add(fila.lead_id)
    }
    const acumulado = respuestas[0]
    if (acumulado && (acumulado.revision !== respuesta.revision || acumulado.modo !== respuesta.modo
      || acumulado.cohorte_desde !== respuesta.cohorte_desde)) throw contrato()
    respuestas.push(respuesta)
  }
  const primera = respuestas[0]
  return primera ? { ...primera, filas: respuestas.flatMap((r) => r.filas) } : null
}
