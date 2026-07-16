import { keepPreviousData, useQuery } from '@tanstack/react-query'
import {
  listarLeads,
  listarMetricasAltasAnalista,
  listarMetricasCapitalMes,
  listarMetricasPagosMes,
  listarMetricasVencimientos,
  type FiltrosLeads,
} from './crm-api'

export const crmQueryKeys = {
  raiz: ['crm'] as const,
  leads: () => [...crmQueryKeys.raiz, 'leads'] as const,
  paginaLeads: (filtros: FiltrosLeads) => [...crmQueryKeys.leads(), 'pagina', filtros] as const,
  // Cartera del portal (panel del analista): bajo la misma raíz para que el
  // logout (queryClient.clear) y las invalidaciones jerárquicas la cubran.
  clientes: () => [...crmQueryKeys.raiz, 'clientes'] as const,
  contratos: () => [...crmQueryKeys.raiz, 'contratos'] as const,
  // Métricas de gerencia (RPCs crm.metricas_*_fn): misma raíz por lo mismo.
  metricas: () => [...crmQueryKeys.raiz, 'metricas'] as const,
  metricasCapital: (meses: number) => [...crmQueryKeys.metricas(), 'capital', meses] as const,
  metricasPagos: (meses: number) => [...crmQueryKeys.metricas(), 'pagos', meses] as const,
  metricasAltas: (meses: number) => [...crmQueryKeys.metricas(), 'altas', meses] as const,
  metricasVencimientos: (dias: number) => [...crmQueryKeys.metricas(), 'vencimientos', dias] as const,
}

export function usePaginaLeads(filtros: FiltrosLeads, habilitada = true) {
  return useQuery({
    queryKey: crmQueryKeys.paginaLeads(filtros),
    queryFn: ({ signal }) => listarLeads(filtros, signal),
    placeholderData: keepPreviousData,
    enabled: habilitada,
  })
}

// ── Métricas de gerencia — SOLO sesión real (`habilitada`): en demo las
//    gráficas se alimentan de agregados de fixtures y NUNCA se toca la red. ─────

export function useMetricasCapitalMes(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasCapital(meses),
    queryFn: ({ signal }) => listarMetricasCapitalMes(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasPagosMes(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasPagos(meses),
    queryFn: ({ signal }) => listarMetricasPagosMes(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasAltasAnalista(habilitada: boolean, meses = 12) {
  return useQuery({
    queryKey: crmQueryKeys.metricasAltas(meses),
    queryFn: ({ signal }) => listarMetricasAltasAnalista(meses, signal),
    enabled: habilitada,
  })
}

export function useMetricasVencimientos(habilitada: boolean, dias = 90) {
  return useQuery({
    queryKey: crmQueryKeys.metricasVencimientos(dias),
    queryFn: ({ signal }) => listarMetricasVencimientos(dias, signal),
    enabled: habilitada,
  })
}

