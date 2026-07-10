import { createContext, useContext } from 'react'
import type {
  PanelesActions,
  PanelesState,
  StoreDataApi,
} from './store'

export const StoreDataContext = createContext<StoreDataApi | null>(null)
export const PanelStateContext = createContext<PanelesState | null>(null)
export const PanelActionsContext = createContext<PanelesActions | null>(null)

export function useCRMData(): StoreDataApi {
  const contexto = useContext(StoreDataContext)
  if (!contexto) throw new Error('useCRMData fuera de StoreProvider')
  return contexto
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
