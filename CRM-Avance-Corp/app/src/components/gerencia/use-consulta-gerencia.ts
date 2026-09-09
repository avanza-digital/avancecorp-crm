import { useContext } from 'react'
import { ConsultaGerenciaContext } from './consulta-context'

export function useConsultaGerencia() {
  return useContext(ConsultaGerenciaContext)
}
