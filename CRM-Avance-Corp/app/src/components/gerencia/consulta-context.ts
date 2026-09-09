import { createContext, type Dispatch, type RefObject, type SetStateAction } from 'react'

export type TipoRankingGerencia = 'conversion' | 'capital-total' | 'cosecha'

export interface ConsultaGerencia {
  gestionAnalista: { id: string; nombre: string } | null
  administrarMetasPeriodo: string | null
  rendimientoEquipo: string | null
  rendimientoOrden: 'cupos' | 'carga' | 'cierres' | 'sin_atender' | 'nombre'
  comparacionAbierta: boolean
  comparacionIds: [string, string]
  ranking: TipoRankingGerencia
  horizonteAltas: 3 | 6 | 12
  analistaId: string | null
  volverARanking: boolean
  abrirDetalle: boolean
}

export interface PosicionConsulta {
  scrollTop: number
  focoId: string | null
}

export interface ConsultaGerenciaContextValue {
  consulta: ConsultaGerencia
  setConsulta: Dispatch<SetStateAction<ConsultaGerencia>>
  posiciones: RefObject<Map<string, PosicionConsulta>>
}

// Sólo memoria de la interfaz durante la sesión. No almacena resultados ni
// modifica el período, la población o las fórmulas de los reportes.
export const ConsultaGerenciaContext = createContext<ConsultaGerenciaContextValue | null>(null)
