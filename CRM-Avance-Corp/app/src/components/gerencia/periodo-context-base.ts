import { createContext, type Dispatch, type SetStateAction } from 'react'
import type { PeriodoGerencia } from './periodo'

export interface PeriodoGerenciaContextValue {
  periodo: PeriodoGerencia
  setPeriodo: Dispatch<SetStateAction<PeriodoGerencia>>
  diaLima: string
  /**
   * Filtro de ORIGEN del lead (Miguel, 27/08): recorta el LOTE del rango en
   * Resumen y Conversiones. `null` = todos. Vive junto al período porque las
   * dos pantallas lo comparten igual que comparten las fechas.
   */
  origenFiltrado: string | null
  setOrigenFiltrado: Dispatch<SetStateAction<string | null>>
}

export const PeriodoGerenciaContext = createContext<PeriodoGerenciaContextValue | null>(null)
