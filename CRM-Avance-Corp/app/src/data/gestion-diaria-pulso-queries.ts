import { useMemo } from 'react'
import { useQuery, type UseQueryResult } from '@tanstack/react-query'
import * as v from 'valibot'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { PulsoGerenciaSchema } from '@/lib/gestion-diaria-pulso'
import { HabitosGerenciaSchema } from '@/lib/gestion-diaria-habitos'
import { DiaEquipoSchema } from '@/lib/gestion-diaria-equipo'
import { detalleOperacionDesdeDemo, habitosGerenciaDesdeDemo, pulsoGerenciaDesdeDemo, type MundoDemo } from '@/lib/gestion-diaria-pulso-demo'
import { gestionDiariaKeys, INTERVALO_REGISTRO_MS } from './gestion-diaria-queries'
import { obtenerPulsoGerencia, obtenerHabitosGerencia } from './gestion-diaria-pulso-api'
import { obtenerDiaEquipo } from './gestion-diaria-api'
import { CrmApiError } from './crm-api'

export const clavePulso = (actor: string | null, rol: string | null, tipo: string, dia: string, alcance: number | string | null = null) =>
  [...gestionDiariaKeys.raiz(), actor, rol, 'gerencia', tipo, dia, alcance] as const
function estadoConsulta<T>(consulta: UseQueryResult<T>, habilitada: boolean) {
  return { datos: habilitada && !consulta.error ? consulta.data ?? null : null,
    cargando: habilitada && consulta.isPending, enVuelo: habilitada && consulta.isFetching,
    error: habilitada ? consulta.error : null,
    recargar: async () => { if (habilitada) await consulta.refetch() } }
}
const refresco = { refetchInterval: INTERVALO_REGISTRO_MS, refetchOnWindowFocus: 'always', refetchOnReconnect: 'always' } as const

// Demo (G0): la gerencia demo ve la operación de ejemplo del store, sin red y
// con la MISMA forma de retorno. Lo calculado pasa por el mismo contrato que la
// respuesta real: si el espejo no cuadra, se oculta como un fallo, no se pinta.
const sinRed = async () => {}
function useMundoDemo(activo: boolean): MundoDemo | null {
  const { equipo, ambito, actividadesDelAmbito, tareas } = useCRMData()
  const ahora = useAhora()
  return useMemo(() => activo ? { miembros: equipo, leads: ambito.leads, actividades: actividadesDelAmbito, tareas, ahora } : null,
    [activo, equipo, ambito.leads, actividadesDelAmbito, tareas, ahora])
}
function estadoDemo<S extends v.GenericSchema>(esquema: S, calcular: () => unknown) {
  let datos: v.InferOutput<S> | null = null
  let error: Error | null = null
  try {
    const resultado = v.safeParse(esquema, calcular())
    if (resultado.success) datos = resultado.output
    else error = new CrmApiError('No se pudo conciliar la operación de ejemplo.', 'GESTION_DIARIA_CONTRACT')
  } catch (fallo) {
    error = fallo instanceof Error ? fallo : new Error(String(fallo))
  }
  return { datos, cargando: false, enVuelo: false, error, recargar: sinRed }
}

export function usePulsoGerencia(dia: string) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo
  const mundo = useMundoDemo(yo?.rol === 'gerencia' && yo.demo)
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'pulso', dia),
    queryFn: ({ signal }) => obtenerPulsoGerencia(dia, signal), enabled: real, ...refresco })
  const demo = useMemo(() => mundo && estadoDemo(PulsoGerenciaSchema, () => pulsoGerenciaDesdeDemo(mundo, dia)), [mundo, dia])
  return demo ?? estadoConsulta(consulta, real)
}
export function useHabitosGerencia(hasta: string, dias: 7 | 14 | 30, abierta: boolean) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo && abierta
  const mundo = useMundoDemo(yo?.rol === 'gerencia' && yo.demo && abierta)
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'habitos', hasta, dias),
    queryFn: ({ signal }) => obtenerHabitosGerencia(hasta, dias, signal), enabled: real,
    refetchInterval: false, refetchOnWindowFocus: false, refetchOnReconnect: 'always' })
  const demo = useMemo(() => mundo && estadoDemo(HabitosGerenciaSchema, () => habitosGerenciaDesdeDemo(mundo, hasta, dias)), [mundo, hasta, dias])
  return demo ?? estadoConsulta(consulta, real)
}
export function useDetallePulso(dia: string, abierto: boolean) {
  const { yo } = useAuth()
  const real = yo?.rol === 'gerencia' && !yo.demo && abierto
  const mundo = useMundoDemo(yo?.rol === 'gerencia' && yo.demo && abierto)
  // NULL = operación completa autorizada para gerencia. El pulso particiona
  // al supervisor más cercano; la tabla se restringe con esos IDs confirmados.
  const consulta = useQuery({ queryKey: clavePulso(yo?.id ?? null, yo?.rol ?? null, 'detalle', dia),
    queryFn: ({ signal }) => obtenerDiaEquipo(dia, null, signal), enabled: real, ...refresco })
  const demo = useMemo(() => mundo && estadoDemo(DiaEquipoSchema, () => detalleOperacionDesdeDemo(mundo, dia)), [mundo, dia])
  return demo ?? estadoConsulta(consulta, real)
}
