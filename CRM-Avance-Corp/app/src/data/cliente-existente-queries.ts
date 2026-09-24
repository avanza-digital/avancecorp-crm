import { useQuery } from '@tanstack/react-query'
import {
  contratosUpgradeClienteExistente, cuentasClienteExistente, datosLegalesClienteExistente, type LlaveVentaCruzada,
} from './cliente-existente-api'

// Lecturas del formulario de contrato de una venta cruzada, con la llave (búsqueda o
// solicitud) en vez del perfil del cliente. Mismas reglas de frescura que las de siempre:
// datos sensibles, siempre obsoletos al desmontar.
const llaveClave = (llave: LlaveVentaCruzada) => llave.solicitudId !== undefined ? `s:${llave.solicitudId}` : `b:${llave.busquedaId}`

export const ventaCruzadaKeys = {
  todo: ['venta-cruzada'] as const,
  legales: (llave: LlaveVentaCruzada) => ['venta-cruzada', 'legales', llaveClave(llave)] as const,
  cuentas: (llave: LlaveVentaCruzada, moneda: 'PEN' | 'USD') => ['venta-cruzada', 'cuentas', llaveClave(llave), moneda] as const,
  upgrade: (llave: LlaveVentaCruzada) => ['venta-cruzada', 'upgrade', llaveClave(llave)] as const,
}

export function useDatosLegalesVentaCruzada(llave: LlaveVentaCruzada | undefined) {
  return useQuery({
    queryKey: llave ? ventaCruzadaKeys.legales(llave) : ['venta-cruzada', 'legales', 'sin-llave'],
    queryFn: ({signal}) => datosLegalesClienteExistente(llave!, signal),
    enabled: Boolean(llave), staleTime: 0, retry: false,
  })
}

export function useCuentasVentaCruzada(llave: LlaveVentaCruzada | undefined, moneda: 'PEN' | 'USD') {
  return useQuery({
    queryKey: llave ? ventaCruzadaKeys.cuentas(llave, moneda) : ['venta-cruzada', 'cuentas', 'sin-llave', moneda],
    queryFn: ({signal}) => cuentasClienteExistente(llave!, moneda, signal),
    enabled: Boolean(llave), staleTime: 0, gcTime: 0, retry: false,
  })
}

export function useContratosUpgradeVentaCruzada(llave: LlaveVentaCruzada | undefined, habilitada: boolean) {
  return useQuery({
    queryKey: llave ? ventaCruzadaKeys.upgrade(llave) : ['venta-cruzada', 'upgrade', 'sin-llave'],
    queryFn: ({signal}) => contratosUpgradeClienteExistente(llave!, signal),
    enabled: Boolean(llave) && habilitada, staleTime: 0, gcTime: 0, retry: false,
  })
}
