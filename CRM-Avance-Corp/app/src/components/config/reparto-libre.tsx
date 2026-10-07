import { useCallback, useEffect, useRef, useState } from 'react'
import { Split } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { SectionHead } from '@/components/common/section-head'
import {
  guardarConfiguracionReparto,
  obtenerConfiguracionReparto,
  type ConfiguracionReparto,
} from '@/data/reparto-config-api'

/** Se monta solo para Gerencia real. Las dos RPC exigen también el rol activo. */
export function RepartoLibre() {
  const [config, setConfig] = useState<ConfiguracionReparto | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cargando, setCargando] = useState(true)
  const [guardando, setGuardando] = useState(false)
  const [aviso, setAviso] = useState('')
  const guardandoRef = useRef(false)
  const abortRef = useRef<AbortController | null>(null)

  const cargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setCargando(true)
    try {
      const vigente = await obtenerConfiguracionReparto(ctrl.signal)
      if (!ctrl.signal.aborted) setConfig(vigente)
    } catch (fallo) {
      if (!ctrl.signal.aborted) {
        setConfig(null)
        setError(fallo instanceof Error ? fallo.message : 'No se pudo consultar el reparto libre.')
      }
    } finally {
      if (!ctrl.signal.aborted) setCargando(false)
    }
  }, [])

  useEffect(() => {
    void cargar()
    return () => abortRef.current?.abort()
  }, [cargar])

  const cambiar = async () => {
    if (!config || cargando || guardandoRef.current) return
    guardandoRef.current = true
    setGuardando(true)
    setError(null)
    setAviso('')
    try {
      const vigente = await guardarConfiguracionReparto(!config.coordinacion_libre, config.revision)
      setConfig(vigente)
      setAviso(vigente.coordinacion_libre
        ? 'Reparto libre activado para todo el rol Coordinadora.'
        : 'Reparto libre desactivado. Coordinación vuelve a seguir el turno guardado.')
    } catch (fallo) {
      setError(fallo instanceof Error ? fallo.message : 'No se pudo guardar el cambio.')
      setConfig(null)
      await cargar()
    } finally {
      guardandoRef.current = false
      setGuardando(false)
    }
  }

  return (
    <Card>
      <SectionHead icon={Split} title="Reparto libre de Coordinación" />
      <CardContent className="space-y-3 pt-0">
        <p className="text-xs text-muted-foreground">
          Permite que todas las coordinadoras deriven Landing y Formulario a cualquier supervisor activo,
          incluso sin turno guardado. Al desactivarlo, deben seguir la agenda de reparto.
        </p>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="text-sm font-semibold text-primary" role="status">
            {cargando ? 'Consultando estado…' : config ? (config.coordinacion_libre ? 'Activado' : 'Desactivado') : 'Estado no disponible'}
          </p>
          {config && (
            <Button
              type="button"
              variant={config.coordinacion_libre ? 'outline' : 'default'}
              disabled={cargando || guardando}
              onClick={() => { void cambiar() }}
            >
              {guardando ? 'Guardando…' : config.coordinacion_libre ? 'Desactivar reparto libre' : 'Activar reparto libre'}
            </Button>
          )}
          {!config && !cargando && (
            <Button type="button" variant="outline" onClick={() => { setError(null); void cargar() }}>
              Reintentar estado del reparto
            </Button>
          )}
        </div>
        {error && <p role="alert" className="text-xs text-destructive">{error}</p>}
        <p role="status" className="text-xs text-muted-foreground">{aviso}</p>
      </CardContent>
    </Card>
  )
}
