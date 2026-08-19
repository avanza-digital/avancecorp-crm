import { useCallback, useEffect, useRef, useState } from 'react'
import { listarIngresosRepartoMes } from './crm-api'
import type { IngresosRepartoMes } from '@/lib/ingresos-reparto'

interface EstadoIngresosRepartoMes {
  datos: IngresosRepartoMes | null
  cargando: boolean
  error: string | null
}

/**
 * Lectura aislada del resumen mensual de Rosa. No usa el store ni altera las
 * consultas de Gerencia: cambiar el mes solo vuelve a pedir esta fotografia.
 */
export function useIngresosRepartoMes(mes: string) {
  const [estado, setEstado] = useState<EstadoIngresosRepartoMes>({
    datos: null,
    cargando: true,
    error: null,
  })
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado({ datos: null, cargando: true, error: null })
    try {
      const datos = await listarIngresosRepartoMes(mes, ctrl.signal)
      if (!ctrl.signal.aborted) setEstado({ datos, cargando: false, error: null })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado({
        datos: null,
        cargando: false,
        error: error instanceof Error ? error.message : 'No se pudieron cargar los ingresos del mes.',
      })
    }
  }, [mes])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  return { ...estado, recargar: cargar }
}
