import { createContext, type Dispatch, type SetStateAction } from 'react'
import type { PeriodoGerencia } from './periodo'

export interface PeriodoGerenciaContextValue {
  periodo: PeriodoGerencia
  setPeriodo: Dispatch<SetStateAction<PeriodoGerencia>>
  diaLima: string
}

export const PeriodoGerenciaContext = createContext<PeriodoGerenciaContextValue | null>(null)
