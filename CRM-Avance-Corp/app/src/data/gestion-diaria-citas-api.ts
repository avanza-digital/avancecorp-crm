import { sb } from '@/lib/supabase'
import { validarPaginaCitas, type PaginaCitas, type PedidoCitas } from '@/lib/gestion-diaria-citas'
import { CrmApiError } from './crm-api'
import { soloPresentes } from './argumentos-rpc'

/** G4b: una página de la lista exacta de citas agendadas; el servidor decide el ámbito. */
export async function listarCitasGestion(pedido: PedidoCitas, signal?: AbortSignal): Promise<PaginaCitas> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('gestion_diaria_citas_fn', {
    p_dia: pedido.dia, p_ambito: pedido.ambito, p_limite: pedido.limite,
    ...soloPresentes({ p_id: pedido.id ?? undefined, p_despues_de: pedido.cursor?.despues_de, p_despues_id: pedido.cursor?.despues_id }),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const pagina = validarPaginaCitas(data, pedido)
  if (!pagina) throw new CrmApiError('No se pudo confirmar la lista completa de citas.', 'GESTION_DIARIA_CITAS_CONTRACT')
  return pagina
}
