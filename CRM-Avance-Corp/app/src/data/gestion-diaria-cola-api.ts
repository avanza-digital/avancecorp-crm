import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { ColaTrabajoSchema, colaTrabajoCoherente, type ColaTrabajo, type PedidoColaTrabajo } from '@/lib/gestion-diaria-cola'
import { CrmApiError } from './crm-api'

export async function obtenerColaTrabajo(pedido: PedidoColaTrabajo, actor: string, dia: string, signal?: AbortSignal): Promise<ColaTrabajo> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('gestion_diaria_cola_trabajo_fn', {
    p_filtro: pedido.filtro, p_pagina: pedido.pagina, p_limite: pedido.limite,
    ...(pedido.elegido !== null ? { p_elegido: pedido.elegido } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ColaTrabajoSchema, data)
  if (!parsed.success || !colaTrabajoCoherente(parsed.output, pedido, actor, dia)) {
    throw new CrmApiError('No se pudo confirmar la cola de trabajo.', 'GESTION_COLA_CONTRACT')
  }
  return parsed.output
}
