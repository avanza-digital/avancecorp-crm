import { createContext, useContext } from 'react'
import type { AlertaCRM } from './alertas'
import type { Rol } from './roles'

export interface EstadoAlertasCRM {
  alertas: AlertaCRM[]
  rol: Rol | null
  cargando: boolean
  errores: string[]
  generadoEn: string | null
  reintentar: () => void
}

const ESTADO_SIN_PROVEEDOR: EstadoAlertasCRM = {
  alertas: [],
  rol: null,
  cargando: false,
  errores: [],
  generadoEn: null,
  reintentar: () => undefined,
}

export const AlertasCRMContext = createContext<EstadoAlertasCRM>(ESTADO_SIN_PROVEEDOR)

export function useAlertasCRM(): EstadoAlertasCRM {
  return useContext(AlertasCRMContext)
}
