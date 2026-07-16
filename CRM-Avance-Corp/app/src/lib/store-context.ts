import { createContext, useContext } from 'react'
import type {
  PanelesActions,
  PanelesState,
  StoreDataApi,
  StoreEstado,
} from './store'

export const StoreDataContext = createContext<StoreDataApi | null>(null)
export const PanelStateContext = createContext<PanelesState | null>(null)
export const PanelActionsContext = createContext<PanelesActions | null>(null)
// Estado de la CARGA remota (sesión real): la app decide entre splash, pantalla
// de error con reintento o el workspace. Nunca es null: default inerte para que
// una sesión demo (que no lo consume de verdad) no reviente si lo lee.
export const StoreEstadoContext = createContext<StoreEstado>({
  cargando: false,
  error: false,
  reintentar: () => {},
})

export function useCRMData(): StoreDataApi {
  const contexto = useContext(StoreDataContext)
  if (!contexto) throw new Error('useCRMData fuera de StoreProvider')
  return contexto
}

export function useStoreEstado(): StoreEstado {
  return useContext(StoreEstadoContext)
}

export function usePanelesState(): PanelesState {
  const contexto = useContext(PanelStateContext)
  if (!contexto) throw new Error('usePanelesState fuera de StoreProvider')
  return contexto
}

export function usePanelesActions(): PanelesActions {
  const contexto = useContext(PanelActionsContext)
  if (!contexto) throw new Error('usePanelesActions fuera de StoreProvider')
  return contexto
}
