import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { ArrowRight, History, Search } from 'lucide-react'
import { historialDerivaciones } from '@/data/crm-api'
import { ETAPA_INFO, origenLabel, type HistorialDerivacion } from '@/lib/tipos'
import { fechaHora, moneyK } from '@/lib/format'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { SectionHead } from '@/components/common/section-head'
import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'

const TAMANO_PAGINA = 100

interface EstadoHistorial {
  filas: HistorialDerivacion[]
  cargando: boolean
  cargandoMas: boolean
  error: string | null
  hayMas: boolean
}

/** El servidor conserva el acceso a leads cerrado y pagina por fecha+UUID. */
export function HistorialDerivaciones() {
  const [estado, setEstado] = useState<EstadoHistorial>({
    filas: [], cargando: true, cargandoMas: false, error: null, hayMas: false,
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
        filas,
        cargando: false,
        cargandoMas: false,
        error: null,
        hayMas: filas.length === TAMANO_PAGINA,
      })
    } catch (error) {
      if (ctrl.signal.aborted) return
      setEstado((prev) => ({
        ...prev,
        cargando: false,
        cargandoMas: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar el historial.',
      }))
    }
  }, [])

  useEffect(() => {
    void recargar()
    return () => abortRef.current?.abort()
  }, [recargar])

  const cargarMas = async () => {
    const ultima = estado.filas.at(-1)
    if (!ultima || estado.cargandoMas) return
    setEstado((prev) => ({ ...prev, cargandoMas: true, error: null }))
    try {
      const filas = await historialDerivaciones(ultima)
      setEstado((prev) => ({
        ...prev,
        filas: [...prev.filas, ...filas],
        cargandoMas: false,
        hayMas: filas.length === TAMANO_PAGINA,
      }))
    } catch (error) {
      setEstado((prev) => ({
        ...prev,
        cargandoMas: false,
        error: error instanceof Error ? error.message : 'No se pudo cargar más historial.',
      }))
    }
  }

  const filasVisibles = useMemo(() => {
    const consulta = busqueda.trim().toLocaleLowerCase('es-PE')
    if (!consulta) return estado.filas
    return estado.filas.filter((fila) => [
      fila.nombre_completo,
      fila.responsable_anterior,
      fila.responsable_nuevo,
      fila.derivado_por_nombre,
      origenLabel(fila.origen),
      fila.movimiento,
    ].some((valor) => valor.toLocaleLowerCase('es-PE').includes(consulta)))
  }, [busqueda, estado.filas])

  return (
    <Card className="overflow-hidden">
      <SectionHead
        icon={History}
        title="Historial de derivaciones"
        right={<span className="text-[11px] font-semibold text-muted-foreground">{estado.filas.length} cargadas</span>}
      />
      <div className="border-b border-border px-5 py-3">
        <div className="relative max-w-sm">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input
            value={busqueda}
            onChange={(event) => setBusqueda(event.target.value)}
            placeholder="Buscar lead o responsable…"
            aria-label="Buscar en el historial de derivaciones"
            className="h-8 pl-8 text-xs"
          />
        </div>
        <p className="mt-2 text-xs text-muted-foreground">
          Registro de distribución y traspasos. No incluye teléfono, correo ni DNI.
        </p>
      </div>

      {estado.cargando ? (
        <PanelCargando filas={5} />
      ) : estado.error && estado.filas.length === 0 ? (
        <PanelError mensaje={estado.error} onReintentar={() => void recargar()} reintentando={estado.cargando} />
      ) : estado.filas.length === 0 ? (
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
              titulo="No hay movimientos que coincidan"
              detalle="Prueba con el nombre del lead o de una persona responsable."
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

      {estado.error && estado.filas.length > 0 ? (
        <div className="border-t border-border px-5 py-3 text-sm text-destructive" role="status">
          {estado.error}
        </div>
      ) : null}

      {estado.hayMas ? (
        <div className="border-t border-border p-3 text-center">
          <Button size="sm" variant="outline" disabled={estado.cargandoMas} onClick={() => void cargarMas()}>
            {estado.cargandoMas ? 'Cargando…' : 'Mostrar 100 más'}
          </Button>
        </div>
      ) : null}
    </Card>
  )
}
