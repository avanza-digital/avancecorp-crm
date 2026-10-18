import { useEffect, useState } from 'react'
import { useFacturacionDiaria } from '@/data/crm-queries'
import { useAuth } from '@/lib/auth-context'
import type { FilaFacturacionDia } from '@/lib/facturacion'
import { resumirResultadosHoy } from './jornada-supervisor'

/** Reutiliza la lectura completa de Facturación. Nunca suma una página de contratos. */
export function useResultadosHoy(hoy: string) {
  const { yo } = useAuth()
  const habilitado = yo?.rol === 'supervisor'
  const esDemo = yo?.demo === true
  const mes = `${hoy.slice(0, 7)}-01`
  const consulta = useFacturacionDiaria(habilitado && !esDemo, mes)
  const [intento, setIntento] = useState(0)
  const clave = `${yo?.id}|${mes}|${intento}`
  const [demo, setDemo] = useState<{ clave: string; filas: FilaFacturacionDia[] | null; error: boolean } | null>(null)
  useEffect(() => {
    if (!habilitado || !esDemo) return
    let vigente = true
    if (import.meta.env.DEV && import.meta.env.VITE_ENABLE_DEMO === 'true') {
      void import('@/lib/demo-metricas').then(m => {
        if (vigente) setDemo({ clave, filas: m.demoFacturacionDiaria(mes), error: false })
      }).catch(() => {
        if (vigente) setDemo({ clave, filas: null, error: true })
      })
    } else setDemo({ clave, filas: null, error: true })
    return () => { vigente = false }
  }, [habilitado, esDemo, clave, mes])
  const demoVigente = demo?.clave === clave ? demo : null
  const error = esDemo ? demoVigente?.error === true : Boolean(consulta.error) || (consulta.data?.descartadas ?? 0) > 0 || consulta.data?.posibleRecorte === true
  const valoracion = !esDemo && !error ? consulta.data?.capitalValoracion : undefined
  const cargando = esDemo ? demoVigente === null : consulta.isPending
  const sinCorte = valoracion != null && (valoracion.corteId === null || valoracion.corte === null)
  const diaSinConfirmar = valoracion != null && (valoracion.corte ?? '') < hoy
  // La demo usa su propio organigrama. En real, el servidor ya entrega TODO el subárbol autorizado.
  const filasDemo = demoVigente?.filas?.filter(f => f.supervisorId === yo?.id || f.analistaId === yo?.id)
  const filas = !habilitado || error || sinCorte || diaSinConfirmar ? null : esDemo ? filasDemo ?? null : consulta.data ?? null
  const aviso = sinCorte ? 'Resultados pendientes de confirmar.'
    : diaSinConfirmar ? 'Los cierres de hoy aún están por confirmar.'
    : valoracion && (valoracion.cobertura.pendientes.cantidad > 0 || valoracion.cobertura.por_incorporar.cantidad > 0)
      ? 'Hay cierres pendientes de incorporar. Se muestra el último corte confirmado.' : null
  return {
    resultados: resumirResultadosHoy(filas, hoy), error, cargando, aviso,
    recargar: async () => {
      if (esDemo) setIntento(n => n + 1)
      else if (habilitado) await consulta.refetch()
    },
  }
}
