import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { CrmApiError } from './crm-api'
import { crmQueryKeys } from './crm-queries'
import { respuestaInversionistas } from './inversionistas-api'
import { EstadoMetricasMultiempresaSchema, MetricasMultiempresaSchema, informeMultiempresaCompleto } from '@/lib/metricas-multiempresa'

export async function obtenerEstadoMetricasMultiempresa(signal: AbortSignal) {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const r = await sb.schema('crm').rpc('metricas_multiempresa_estado_fn').abortSignal(signal)
  if (r.error?.code === 'PGRST202') return { version: 1 as const, habilitada: false }
  return respuestaInversionistas(EstadoMetricasMultiempresaSchema, r)
}
export async function obtenerMetricasMultiempresa(mes: string, signal: AbortSignal) {
  if (!sb) throw new CrmApiError('La conexión no está disponible.', 'SUPABASE_NOT_CONFIGURED')
  const r = await sb.schema('crm').rpc('metricas_multiempresa_fn', { p_mes: mes }).abortSignal(signal)
  const informe = respuestaInversionistas(MetricasMultiempresaSchema, r)
  if (informe.mes !== mes || !informeMultiempresaCompleto(informe)) {
    throw new CrmApiError('El informe llegó incompleto. Vuelve a consultar.', 'RESPUESTA_INCOMPLETA')
  }
  return informe
}
export function useMetricasMultiempresa(actor: string, habilitada: boolean, mes: string) {
  const raiz = [...crmQueryKeys.metricas(), 'multiempresa', actor]
  const estado = useQuery({ queryKey: [...raiz, 'estado'],
    queryFn: ({ signal }) => obtenerEstadoMetricasMultiempresa(signal),
    enabled: habilitada, staleTime: 0, gcTime: 0, retry: false,
    refetchInterval: q => q.state.data?.habilitada ? 15_000 : 300_000,
  })
  const informe = useQuery({ queryKey: [...raiz, mes],
    queryFn: ({ signal }) => obtenerMetricasMultiempresa(mes, signal),
    enabled: habilitada && estado.isSuccess && estado.data.habilitada,
    staleTime: Infinity, gcTime: 0, retry: false, refetchOnWindowFocus: false,
  })
  // El consumidor oculta datos al perder la capacidad o al fallar la lectura;
  // TanStack conserva datos en errores de refresco, no implican permiso vigente.
  return { estado, informe }
}
