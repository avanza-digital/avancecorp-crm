import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowRight, History, Search } from 'lucide-react'
import { historialDerivaciones, TAMANO_PAGINA_HISTORIAL_REPARTO } from '@/data/crm-api'
import { ETAPA_INFO, origenLabel, type HistorialDerivacion } from '@/lib/tipos'
import { fechaHora, moneyK } from '@/lib/format'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
import { AgendaRepartoDiaria } from '@/components/app/agenda-reparto-diaria'

interface EstadoHistorial {
  paginas: HistorialDerivacion[][]
  paginaActual: number
  cargando: boolean
  cargandoSiguiente: boolean
  error: string | null
  hayMas: boolean
}

/**
 * El servidor conserva el acceso a leads cerrado y pagina por fecha+UUID.
 * Se mantiene UNA página en pantalla: navegar no agrega 25/50/100 tarjetas al
 * DOM ni al alto de la vista, aunque el historial tenga años de movimientos.
 */
export function HistorialDerivaciones() {
  const [estado, setEstado] = useState<EstadoHistorial>({
    paginas: [], paginaActual: 0, cargando: true, cargandoSiguiente: false, error: null, hayMas: false,
  })
  const [busqueda, setBusqueda] = useState('')
  const abortRef = useRef<AbortController | null>(null)

  const recargar = useCallback(async () => {
    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((prev) => ({ ...prev, cargando: true, error: null }))
    try {
      const filas = await historialDerivaciones(undefined, ctrl.signal)
      if (ctrl.signal.aborted) return
      setEstado({
        paginas: [filas],
        paginaActual: 0,
        cargando: false,
        cargandoSiguiente: false,
        error: null,
        hayMas: filas.length === TAMANO_PAGINA_HISTORIAL_REPARTO,
      })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((prev) => ({
        ...prev,
        cargando: false,
        cargandoSiguiente: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar el historial.',
      }))
    }
  }, [])

  useEffect(() => {
    void recargar()
    return () => abortRef.current?.abort()
  }, [recargar])

  const irSiguiente = useCallback(async () => {
    if (estado.cargandoSiguiente) return
    if (estado.paginaActual < estado.paginas.length - 1) {
      setEstado((prev) => ({ ...prev, paginaActual: prev.paginaActual + 1, error: null }))
      return
    }
    const actual = estado.paginas[estado.paginaActual]
    const ultima = actual?.at(-1)
    if (!ultima || !estado.hayMas) return

    abortRef.current?.abort()
    const ctrl = new AbortController()
    abortRef.current = ctrl
    setEstado((prev) => ({ ...prev, cargandoSiguiente: true, error: null }))
    try {
      const filas = await historialDerivaciones(ultima, ctrl.signal)
      if (ctrl.signal.aborted) return
      setEstado((prev) => ({
        ...prev,
        paginas: [...prev.paginas, filas],
        paginaActual: prev.paginas.length,
        cargandoSiguiente: false,
        hayMas: filas.length === TAMANO_PAGINA_HISTORIAL_REPARTO,
      }))
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((prev) => ({
        ...prev,
        cargandoSiguiente: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar la página siguiente.',
      }))
    }
  }, [estado])

  const filasPagina = useMemo(
    () => estado.paginas[estado.paginaActual] ?? [],
    [estado.paginaActual, estado.paginas],
  )
  const filasVisibles = useMemo(() => {
    const consulta = busqueda.trim().toLocaleLowerCase('es-PE')
    if (!consulta) return filasPagina
    return filasPagina.filter((fila) => [
      fila.nombre_completo,
      fila.responsable_anterior,
      fila.responsable_nuevo,
      fila.derivado_por_nombre,
      origenLabel(fila.origen),
      fila.movimiento,
    ].some((valor) => valor.toLocaleLowerCase('es-PE').includes(consulta)))
  }, [busqueda, filasPagina])
  const puedeAnterior = estado.paginaActual > 0
  const puedeSiguiente = estado.paginaActual < estado.paginas.length - 1 || estado.hayMas

  return (
    <div className="space-y-4">
      <AgendaRepartoDiaria />
      <Card className="overflow-hidden">
        <SectionHead
          icon={History}
          title="Historial de derivaciones"
          right={(
            <span className="text-[11px] font-semibold text-muted-foreground">
              Página {estado.paginaActual + 1} · hasta {TAMANO_PAGINA_HISTORIAL_REPARTO} movimientos
            </span>
          )}
        />
        <div className="border-b border-border px-5 py-3">
          <div className="relative max-w-sm">
            <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden />
            <Input
              value={busqueda}
              onChange={(event) => setBusqueda(event.target.value)}
              placeholder="Buscar en esta página…"
              aria-label="Buscar en la página actual del historial de derivaciones"
              className="h-8 pl-8 text-xs"
            />
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            Registro de distribución y traspasos. No incluye teléfono, correo ni DNI. La búsqueda se aplica a la página visible.
          </p>
        </div>

        {estado.cargando && estado.paginas.length === 0 ? (
          <PanelCargando filas={5} />
        ) : estado.error && estado.paginas.length === 0 ? (
          <PanelError mensaje={estado.error} onReintentar={() => void recargar()} reintentando={estado.cargando} />
        ) : filasPagina.length === 0 ? (
          <PanelVacio
            icono={History}
            titulo="Aún no hay derivaciones registradas"
            detalle="Cuando un lead pase por una bandeja o se asigne a un analista, su movimiento aparecerá aquí."
          />
        ) : (
          <div className="divide-y divide-border">
            {filasVisibles.length === 0 ? (
              <PanelVacio
                icono={Search}
                titulo="No hay movimientos que coincidan en esta página"
                detalle="Prueba con otro nombre o navega a la página siguiente del historial."
              />
            ) : filasVisibles.map((fila) => {
              const etapa = ETAPA_INFO[fila.etapa_actual]
              return (
                <article key={fila.actividad_id} className="space-y-1.5 px-5 py-3.5">
                  <div className="flex flex-wrap items-center gap-2">
                    <h3 className="font-semibold text-foreground">{fila.nombre_completo}</h3>
                    <span
                      className="rounded-full px-1.5 py-px text-[10px] font-bold uppercase tracking-wide"
                      style={{ color: etapa.color, backgroundColor: `${etapa.color}18` }}
                    >
                      {etapa.label}
                    </span>
                  </div>
                  <div className="flex flex-wrap items-center gap-1.5 text-sm text-muted-foreground">
                    <span className="font-medium text-foreground">{fila.responsable_anterior}</span>
                    <ArrowRight className="size-3.5" aria-label="pasa a" />
                    <span className="font-medium text-foreground">{fila.responsable_nuevo}</span>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {origenLabel(fila.origen)} · <span className="font-semibold text-foreground">{moneyK(fila.monto_estimado, fila.moneda)}</span>
                    {fila.distrito ? ` · ${fila.distrito}` : ''}
                    {' · '}{fechaHora(fila.derivado_en)} por {fila.derivado_por_nombre}
                  </p>
                </article>
              )
            })}
          </div>
        )}

        {estado.error && estado.paginas.length > 0 ? (
          <div className="border-t border-border px-5 py-3 text-sm text-destructive" role="status">
            {estado.error}
          </div>
        ) : null}

        {filasPagina.length > 0 && (puedeAnterior || puedeSiguiente) ? (
          <nav className="flex items-center justify-between gap-3 border-t border-border px-5 py-3" aria-label="Paginación del historial de derivaciones">
            <span className="text-xs tabular-nums text-muted-foreground">
              Mostrando {filasPagina.length} movimientos
            </span>
            <div className="flex gap-2">
              <Button
                size="sm"
                variant="outline"
                disabled={!puedeAnterior || estado.cargandoSiguiente}
                onClick={() => setEstado((prev) => ({ ...prev, paginaActual: Math.max(0, prev.paginaActual - 1), error: null }))}
              >
                Anterior
              </Button>
              <Button size="sm" variant="outline" disabled={!puedeSiguiente || estado.cargandoSiguiente} onClick={() => void irSiguiente()}>
                {estado.cargandoSiguiente ? 'Cargando…' : 'Siguiente'}
              </Button>
            </div>
          </nav>
        ) : null}
      </Card>
    </div>
  )
}
