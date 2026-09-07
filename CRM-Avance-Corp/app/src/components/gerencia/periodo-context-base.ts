import { createContext, type Dispatch, type SetStateAction } from 'react'
import type { FiltroFuentesConversion } from '@/lib/conversion-vendedores'
import type { PeriodoGerencia } from './periodo'

export interface PeriodoGerenciaContextValue {
  periodo: PeriodoGerencia
  setPeriodo: Dispatch<SetStateAction<PeriodoGerencia>>
  diaLima: string
  /** Fuente cuyo aporte al índice comercial se muestra. `null` = total. */
  origenFiltrado: FiltroFuentesConversion
  setOrigenFiltrado: Dispatch<SetStateAction<FiltroFuentesConversion>>
}

export const PeriodoGerenciaContext = createContext<PeriodoGerenciaContextValue | null>(null)
