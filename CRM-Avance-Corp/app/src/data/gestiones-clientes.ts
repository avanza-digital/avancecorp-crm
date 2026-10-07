import * as v from 'valibot'
import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { useAuth } from '@/lib/auth-context'
import { CrmApiError } from './crm-api'
import { ResumenGestionesSchema, CitasClientesSchema, citasClientesCoherentes } from '@/lib/gestiones-clientes'
import type { CursorCitas } from '@/lib/gestion-diaria-citas'

export const gestionesClientesKeys = { raiz: ['crm', 'gestion-diaria', 'clientes'] as const }
const refresco = { staleTime: 0, gcTime: 0, retry: false, refetchInterval: 60_000, refetchOnWindowFocus: 'always' as const, refetchOnReconnect: 'always' as const }
export async function resumenGestiones(desde: string, hasta: string, autores: readonly string[] | null, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const q = sb.schema('crm').rpc('gestiones_resumen_fn', { p_desde: desde, p_hasta: hasta, ...(autores ? { p_analista_ids: [...autores] } : {}) })
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error) throw new CrmApiError(r.error.message, r.error.code)
  const parsed = v.safeParse(ResumenGestionesSchema, r.data)
  if (!parsed.success || parsed.output.desde !== desde || parsed.output.hasta !== hasta
    || (autores && parsed.output.analistas.some(a => !a.id || !autores.includes(a.id)))) throw new CrmApiError('No se pudo verificar el resumen de gestiones.', 'GESTIONES_CONTRACT')
  return parsed.output
}
export function useResumenGestiones(desde: string, hasta: string, autores: readonly string[] | null = null) {
  const { yo } = useAuth()
  return useQuery({ ...refresco, queryKey: [...gestionesClientesKeys.raiz, yo?.id, yo?.rol, 'resumen', desde, hasta, autores],
    enabled: Boolean(yo && !yo.demo && autores?.length !== 0), queryFn: ({ signal }) => resumenGestiones(desde, hasta, autores, signal) })
}
export async function citasClientes(desde: string, hasta: string, autores: readonly string[] | null, cursor: CursorCitas | null, signal?: AbortSignal) {
  if (!sb) throw new CrmApiError('No hay conexión con el CRM.', 'SIN_CLIENTE')
  const q = sb.schema('crm').rpc('citas_clientes_fn', { p_desde: desde, p_hasta: hasta, p_limite: 25,
    ...(autores ? { p_analista_ids: [...autores] } : {}), ...(cursor ? { p_despues_de: cursor.despues_de, p_despues_id: cursor.despues_id } : {}) })
  const r = await (signal ? q.abortSignal(signal) : q)
  if (r.error) throw new CrmApiError(r.error.message, r.error.code)
  const parsed = v.safeParse(CitasClientesSchema, r.data)
  if (!parsed.success || !citasClientesCoherentes(parsed.output, desde, hasta, autores, cursor)) {
    throw new CrmApiError('No se pudo verificar la lista de citas de clientes.', 'GESTIONES_CONTRACT')
  }
  return parsed.output
}
export function useCitasClientes(desde: string, hasta: string, autores: readonly string[] | null, cursor: CursorCitas | null) {
  const { yo } = useAuth()
  return useQuery({ ...refresco, refetchInterval: cursor ? false : 60_000,
    queryKey: [...gestionesClientesKeys.raiz, yo?.id, yo?.rol, 'citas', desde, hasta, autores, cursor],
    enabled: Boolean(yo && !yo.demo && autores?.length !== 0), queryFn: ({ signal }) => citasClientes(desde, hasta, autores, cursor, signal) })
}
