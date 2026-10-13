// F4-e: la consulta de «la operación de hoy» del celular para la gerencia (tercera pestaña de «Toda la operación hoy»)
// y el supervisor (bloque «Su celular» de «Mi equipo hoy»). Mismo molde que el pulso de gerencia: refresco cada minuto
// y, en demo, el espejo calculado con el organigrama del store pasando por el MISMO esquema que la respuesta real.
import { useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { llamadasCelularHabilitadas } from '@/lib/config'
import { OperacionCelularHoySchema, type OperacionCelularHoy } from '@/lib/llamadas-celular-operacion'
import { operacionCelularDesdeDemo } from '@/lib/llamadas-celular-operacion-demo'
import { INTERVALO_REGISTRO_MS } from './gestion-diaria-queries'
import { estadoConsulta, estadoDemo } from './gestion-diaria-pulso-queries'
import { llamadasCelularKeys, obtenerOperacionCelularHoy } from './llamadas-celular-api'

export interface OperacionCelularHook {
  datos: OperacionCelularHoy | null
  cargando: boolean
  enVuelo: boolean
  error: unknown
  recargar: () => Promise<void>
}

/**
 * Solo supervisor y gerencia, con las llamadas del celular habilitadas, y solo mientras `habilitado` (la pestaña
 * abierta, el día de hoy): la puerta es solo de hoy (F6 traerá el histórico). El ámbito lo resuelve el servidor.
 */
export function useOperacionCelularHoy(habilitado: boolean): OperacionCelularHook {
  const { yo } = useAuth()
  const { equipo } = useCRMData()
  const ahora = useAhora()
  const rol = yo?.rol ?? null
  const autorizado = Boolean(yo) && (rol === 'gerencia' || rol === 'supervisor') && llamadasCelularHabilitadas(yo?.demo === true) && habilitado
  const real = autorizado && !yo?.demo
  const consulta = useQuery({
    queryKey: [...llamadasCelularKeys.raiz, yo?.id ?? null, rol, 'operacion-hoy'] as const,
    queryFn: ({ signal }) => obtenerOperacionCelularHoy(signal),
    enabled: real, refetchInterval: INTERVALO_REGISTRO_MS, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always',
  })
  const demo = useMemo(() => {
    if (!autorizado || !yo?.demo) return null
    return estadoDemo(OperacionCelularHoySchema, () => operacionCelularDesdeDemo(equipo, ahora, yo.id, yo.rol))
  }, [autorizado, yo, equipo, ahora])
  return demo ?? estadoConsulta(consulta, real)
}
