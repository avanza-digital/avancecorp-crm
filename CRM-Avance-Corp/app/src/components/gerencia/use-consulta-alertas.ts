import { useState, type SetStateAction } from 'react'
import type { AlertaCRM, TipoAlerta } from '@/lib/alertas'
import { useConsultaGerencia } from './use-consulta-gerencia'

export interface ConsultaAlertas {
  prioridad: 'todas' | AlertaCRM['severidad']
  tipo: 'todos' | TipoAlerta
  busqueda: string
  filtrosAbiertos: boolean
}

const INICIAL: ConsultaAlertas = { prioridad: 'todas', tipo: 'todos', busqueda: '', filtrosAbiertos: false }

/** Vive en el proveedor de la sesión (key usuario/rol); sin almacenamiento de datos. */
export function useConsultaAlertas(gerencia: boolean) {
  const contexto = useConsultaGerencia()
  const [local, setLocal] = useState(INICIAL)
  const consulta = gerencia && contexto ? (contexto.consulta.alertas ?? INICIAL) : local
  function cambiar<K extends keyof ConsultaAlertas>(campo: K, valor: SetStateAction<ConsultaAlertas[K]>) {
    const actualizar = (anterior: ConsultaAlertas): ConsultaAlertas => ({
      ...anterior,
      [campo]: typeof valor === 'function' ? valor(anterior[campo]) : valor,
    })
    if (gerencia && contexto) contexto.setConsulta(anterior => ({ ...anterior, alertas: actualizar(anterior.alertas ?? INICIAL) }))
    else setLocal(actualizar)
  }
  return { ...consulta, cambiar }
}
