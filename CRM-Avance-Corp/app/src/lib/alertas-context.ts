import { createContext, useContext } from 'react'
import type { AlertaCRM } from './alertas'
import type { AccionReconocimiento } from './reconocimientos-alertas'
import type { Rol } from './roles'

export interface EstadoAlertasCRM {
  /** Lo que la pantalla PINTA: activas primero y, para el supervisor,
   *  las reconocidas ATENUADAS al final (las pospuestas no están). */
  alertas: AlertaCRM[]
  /** Lo que la campana CUENTA: solo las que piden acción hoy — una alerta
   *  reconocida deja de sumar al badge sin dejar de verse (F4). */
  pendientes: number
  /** Alertas OCULTAS por posposición vigente: la pantalla lo dice en una
   *  línea — un vacío que calla una pospuesta afirmaría algo falso (F4). */
  pospuestas: number
  rol: Rol | null
  cargando: boolean
  errores: string[]
  generadoEn: string | null
  reintentar: () => void
  /** F4: asienta reconocer/posponer en el libro (supervisor; la alerta debe
   *  traer `miembros`). `hasta` ISO solo para posponer (tope 7 días). */
  reconocer: (
    alerta: AlertaCRM,
    accion: AccionReconocimiento,
    hasta: string | null,
  ) => Promise<void>
}

const ESTADO_SIN_PROVEEDOR: EstadoAlertasCRM = {
  alertas: [],
  pendientes: 0,
  pospuestas: 0,
  rol: null,
  cargando: false,
  errores: [],
  generadoEn: null,
  reintentar: () => undefined,
  reconocer: async () => undefined,
}

export const AlertasCRMContext = createContext<EstadoAlertasCRM>(ESTADO_SIN_PROVEEDOR)

export function useAlertasCRM(): EstadoAlertasCRM {
  return useContext(AlertasCRMContext)
}
