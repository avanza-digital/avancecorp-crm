import * as v from 'valibot'
import { sb } from '@/lib/supabase'
import { BandejaSchema, ResueltasHoySchema, type Bandeja, type ResueltasHoy, type MotivoDescarte } from '@/lib/llamadas-celular'
import { CrmApiError } from './crm-api'

export const llamadasCelularKeys = {
  raiz: ['llamadas-celular'] as const,
  pendientes: (actor: string) => ['llamadas-celular', actor, 'pendientes'] as const,
  hoy: (actor: string) => ['llamadas-celular', actor, 'hoy'] as const,
}

export async function listarLlamadasCelular(cursor: Bandeja['siguiente'], signal?: AbortSignal): Promise<Bandeja> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('llamadas_celular_bandeja_fn', {
    p_limite: 50,
    ...(cursor ? { p_antes_id: cursor.evento_id, p_antes_recibido_en: cursor.recibido_en } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(BandejaSchema, data)
  // Sin origen no se puede registrar el resultado exacto: no presentar una integración incompleta como operativa.
  if (!parsed.success || parsed.output.filas.some((f) => !f.evento_origen_id)) {
    throw new CrmApiError('No se pudo confirmar la lista de llamadas. Actualiza e inténtalo de nuevo.', 'LLAMADAS_CONTRACT')
  }
  return parsed.output
}

export async function listarResueltasCelular(cursor: ResueltasHoy['siguiente'], signal?: AbortSignal): Promise<ResueltasHoy> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  let consulta = sb.schema('crm').rpc('llamadas_celular_resueltas_hoy_fn', {
    p_limite: 50,
    ...(cursor ? { p_antes_id: cursor.evento_id, p_antes_resuelto_en: cursor.resuelto_en } : {}),
  })
  if (signal) consulta = consulta.abortSignal(signal)
  const { data, error } = await consulta
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ResueltasHoySchema, data)
  if (!parsed.success) throw new CrmApiError('No se pudo confirmar lo resuelto hoy.', 'LLAMADAS_CONTRACT')
  return parsed.output
}

const ConfirmacionAccionSchema = v.object({ evento_id: v.string(), repetido: v.boolean() })
export async function cambiarLlamadaCelular(evento: string, accion:
  { lead: string } | { motivo: MotivoDescarte; detalle: string | null }): Promise<void> {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const { data, error } = 'lead' in accion
    ? await sb.schema('crm').rpc('asociar_llamada_celular', { p_evento_id: evento, p_lead_id: accion.lead })
    : await sb.schema('crm').rpc('descartar_llamada_celular', {
      p_evento_id: evento, p_motivo: accion.motivo, ...(accion.detalle ? { p_detalle: accion.detalle } : {}),
    })
  if (error) throw new CrmApiError(error.message, error.code)
  const parsed = v.safeParse(ConfirmacionAccionSchema, data)
  if (!parsed.success || parsed.output.evento_id !== evento) {
    throw new CrmApiError('No se pudo confirmar el cambio. Actualiza la lista antes de reintentarlo.', 'LLAMADAS_CONTRACT')
  }
}
