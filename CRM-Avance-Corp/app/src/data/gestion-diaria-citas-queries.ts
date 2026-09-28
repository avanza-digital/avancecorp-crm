import { useEffect, useMemo, useRef } from 'react'
import { useInfiniteQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth-context'
import { useCRMData } from '@/lib/store-context'
import { useAhora } from '@/lib/ahora'
import { analistasDelEquipo } from '@/lib/gestion-diaria'
import { citasDesdeDemo, unirPaginasCitas, type AmbitoCitas, type CursorCitas } from '@/lib/gestion-diaria-citas'
import { CrmApiError } from './crm-api'
import { gestionDiariaKeys } from './gestion-diaria-queries'
import { listarCitasGestion } from './gestion-diaria-citas-api'

export const LIMITE_CITAS = 25
export const claveCitas = (actor: string | null, rol: string | null, demo: boolean | null, dia: string, ambito: AmbitoCitas, id: string | null) =>
  [...gestionDiariaKeys.raiz(), actor, rol, demo, 'citas-agendadas', dia, ambito, id, LIMITE_CITAS] as const

/**
 * G4b: la lista exacta de citas agendadas de un ámbito. Se consulta al abrirla (una foto:
 * sin refresco periódico, como el registro que se abre) y «Actualizar» vuelve a pedirla.
 * Supervisión sólo pide el ámbito «analista»; Gerencia, cualquiera. El servidor decide.
 */
export function useCitasGestion(dia: string, ambito: AmbitoCitas, id: string | null, visible: boolean, actualizacion = 0) {
  const { yo } = useAuth()
  const { tareas, equipo, ambito: alcance } = useCRMData()
  const ahora = useAhora()
  const cliente = useQueryClient()
  const revocada = useRef(false)
  const autorizado = yo?.rol === 'gerencia' || (yo?.rol === 'supervisor' && ambito === 'analista')
  const clave = useMemo(() => [...claveCitas(yo?.id ?? null, yo?.rol ?? null, yo?.demo ?? null, dia, ambito, id), actualizacion],
    [yo?.id, yo?.rol, yo?.demo, dia, ambito, id, actualizacion])
  const ambitoClave = useMemo(() => clave.slice(0, -2), [clave])
  const identidad = JSON.stringify(ambitoClave)
  const ultimaIdentidad = useRef(identidad)
  if (ultimaIdentidad.current !== identidad) {
    ultimaIdentidad.current = identidad
    revocada.current = false
  }
  const consulta = useInfiniteQuery({
    queryKey: clave,
    initialPageParam: null as CursorCitas | null,
    queryFn: ({ pageParam, signal }) => {
      if (!yo || !autorizado) throw new CrmApiError('Consulta no autorizada.', '42501')
      const pedido = { dia, ambito, id, limite: LIMITE_CITAS, cursor: pageParam }
      if (yo.demo) {
        // En demo, el mismo ámbito que el servidor: Supervisión su árbol; Gerencia todo.
        if (yo.rol === 'supervisor' && (id === null || !analistasDelEquipo(equipo, yo.id).includes(id))) throw new CrmApiError('Consulta no autorizada.', '42501')
        return Promise.resolve(citasDesdeDemo(pedido, { miembros: equipo, leads: alcance.leads, tareas, ahora }))
      }
      return listarCitasGestion(pedido, signal)
    },
    getNextPageParam: (ultima) => ultima.siguiente_cursor,
    enabled: autorizado && visible && !revocada.current,
    refetchOnWindowFocus: false, refetchOnReconnect: false,
    staleTime: Infinity, gcTime: 0, retry: false,
  })
  const denegada = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  const sinPermiso = denegada || revocada.current
  useEffect(() => {
    if (!denegada) return
    // Bloquear primero: limpiar la caché no debe provocar otra consulta automática.
    revocada.current = true
    void cliente.cancelQueries({ queryKey: ambitoClave })
    cliente.setQueriesData({ queryKey: ambitoClave }, { pages: [], pageParams: [] })
  }, [denegada, cliente, ambitoClave])
  const paginas = autorizado && !sinPermiso ? consulta.data?.pages ?? [] : []
  return {
    items: unirPaginasCitas(paginas), total: paginas[0]?.resumen.total ?? null,
    consultadoEn: paginas[0]?.generado_en ?? null,
    cargando: autorizado && !sinPermiso && consulta.isPending,
    enVuelo: consulta.isFetching, error: sinPermiso ? new CrmApiError('Ya no tienes acceso a estas citas.', '42501') : consulta.error,
    sinPermiso, hayMas: !sinPermiso && !consulta.error && consulta.hasNextPage,
    cargarMas: async () => { if (autorizado && !sinPermiso && !consulta.isFetching && consulta.hasNextPage) await consulta.fetchNextPage() },
    recargar: async () => {
      if (!autorizado) return
      revocada.current = false
      await cliente.cancelQueries({ queryKey: clave, exact: true })
      await cliente.resetQueries({ queryKey: clave, exact: true })
    },
  }
}
