import { sb } from '@/lib/supabase'
import { validarPaginaPendientes, type PedidoPendientes, type PaginaPendientes } from '@/lib/gestion-diaria-pendientes'
import { CrmApiError } from './crm-api'
import { soloPresentes } from './argumentos-rpc'

export async function listarPendientesSupervisor(pedido: PedidoPendientes, signal?: AbortSignal): Promise<PaginaPendientes> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('gestion_diaria_pendientes_fn', {
    p_analista_id: pedido.analista, p_solo_vencidas: pedido.soloVencidas, p_limite: pedido.limite,
    ...soloPresentes({ p_despues_de: pedido.cursor?.despues_de, p_despues_id: pedido.cursor?.despues_id }),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const pagina = validarPaginaPendientes(data, pedido)
  if (!pagina) throw new CrmApiError('No se pudo confirmar la lista completa de tareas de este analista.', 'GESTION_DIARIA_PENDIENTES_CONTRACT')
  return pagina
}
