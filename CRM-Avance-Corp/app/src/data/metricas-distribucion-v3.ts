// Puerta V3 de distribución (F3 de «Conversión única», RPC de F2.3b).
//
// VIVE EN SU PROPIO FICHERO a propósito: `crm-api.ts` y `crm-queries.ts` son
// zona de conflicto de la integración de ramas ([[ramas-paralelas-crm]]) y no
// se tocan hasta integrar. Cuando el árbol esté integrado, este fetcher puede
// mudarse a la capa de datos general (F3, paso «capa de datos») sin cambiar
// su contrato.
import * as v from 'valibot'
import { useQuery } from '@tanstack/react-query'
import { sb } from '@/lib/supabase'
import { registrarError } from '@/lib/observabilidad'
import { CrmApiError } from './crm-api'
import {
  MetricasDistribucionLeadsV3Schema,
  type MetricasDistribucionLeadsV3,
} from '@/lib/metricas-distribucion'

const FechaMetricaSchema = v.pipe(v.string(), v.isoDate())

function periodoValido(desde: string, hasta: string): boolean {
  return (
    v.safeParse(FechaMetricaSchema, desde).success
    && v.safeParse(FechaMetricaSchema, hasta).success
    && desde <= hasta
  )
}

function lanzarAbortSiCorresponde(signal?: AbortSignal): void {
  if (!signal?.aborted) return
  throw signal.reason instanceof Error
    ? signal.reason
    : new DOMException('La solicitud fue cancelada.', 'AbortError')
}

/**
 * `database.types.ts` es zona de conflicto y `gen:types` corre recién tras la
 * integración (F3, paso «capa de datos»), así que el tipado generado todavía
 * no conoce la RPC v3. Esta vista mínima del cliente permite llamarla sin
 * tocar el fichero generado; el contrato REAL lo impone el schema Valibot de
 * cierre hermético sobre la respuesta, no el tipo del cable.
 */
interface RpcCrmSinTipos {
  rpc: (
    fn: string,
    args: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: { code?: string | null } | null }> & {
    abortSignal: (signal: AbortSignal) => PromiseLike<{
      data: unknown
      error: { code?: string | null } | null
    }>
  }
}

/**
 * Fotografía atómica V3: la V2 más la puntería SERVIDA (cerrados÷resueltos por
 * analista, rango y resumen — las divisiones que hasta F3 hacía el navegador),
 * la cifra del NÚCLEO y el bloque `sondas`. Igual que la V2: una sola rama
 * inválida invalida el payload completo (cierre hermético, fail-closed).
 */
export async function listarMetricasDistribucionLeadsV3(
  desde: string,
  hasta: string,
  signal?: AbortSignal,
): Promise<MetricasDistribucionLeadsV3> {
  if (!periodoValido(desde, hasta)) {
    const fallo = new CrmApiError('El período de métricas no es válido.', 'PERIODO_METRICAS_INVALIDO')
    registrarError('crm.metricas.distribucion_v3_periodo_invalido', fallo)
    throw fallo
  }
  if (!sb) {
    const fallo = new CrmApiError('Supabase no está configurado.', 'SUPABASE_NOT_CONFIGURED')
    registrarError('crm.cliente_no_disponible', fallo)
    throw fallo
  }

  lanzarAbortSiCorresponde(signal)
  const crm = sb.schema('crm') as unknown as RpcCrmSinTipos
  let consulta = crm.rpc('metricas_distribucion_leads_v3_fn', {
    p_desde: desde,
    p_hasta: hasta,
  })
  if (signal) consulta = consulta.abortSignal(signal) as typeof consulta
  const { data, error } = await consulta
  lanzarAbortSiCorresponde(signal)
  if (error) {
    const fallo = new CrmApiError('No se pudieron cargar las métricas.', error.code || 'POSTGREST_ERROR')
    registrarError('crm.metricas.distribucion_v3_fallido', fallo)
    throw fallo
  }

  const resultado = v.safeParse(MetricasDistribucionLeadsV3Schema, data)
  if (
    !resultado.success
    || resultado.output.cohorte.desde_inclusivo !== desde
    || resultado.output.cohorte.hasta_inclusivo !== hasta
  ) {
    const fallo = new CrmApiError(
      'Las métricas de distribución no tienen el formato esperado.',
      'METRICAS_DISTRIBUCION_CONTRACT',
    )
    registrarError('crm.metricas.distribucion_v3_fuera_de_contrato', fallo)
    throw fallo
  }
  return resultado.output
}

/**
 * Mismo contrato que las fotografías por período de `crm-queries`: habilitación
 * fail-closed y el período SIEMPRE en la clave — cambiar de período jamás
 * reutiliza en silencio la fotografía anterior.
 */
export function useMetricasDistribucionLeadsV3(habilitada: boolean, desde: string, hasta: string) {
  return useQuery({
    queryKey: ['crm', 'metricas', 'distribucion-leads-v3', desde, hasta] as const,
    queryFn: ({ signal }) => listarMetricasDistribucionLeadsV3(desde, hasta, signal),
    enabled: habilitada && Boolean(desde) && Boolean(hasta),
  })
}
