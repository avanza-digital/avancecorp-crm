import { useContext } from 'react'
import { PeriodoGerenciaContext, type PeriodoGerenciaContextValue } from './periodo-context-base'

export function usePeriodoGerencia(): PeriodoGerenciaContextValue {
  const contexto = useContext(PeriodoGerenciaContext)
  if (!contexto) throw new Error('usePeriodoGerencia requiere PeriodoGerenciaProvider')
  return contexto
}
