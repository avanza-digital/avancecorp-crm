import { useEffect, useId, useRef, type JSX } from 'react'
import { ChevronRight, RefreshCw, UserPlus } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { numero } from '@/lib/format'
import { usePanelesActions } from '@/lib/store-context'
import { cn } from '@/lib/utils'
import { useLeadsRecibidosHoy, type DatosLeadsRecibidosHoy } from './use-leads-recibidos-hoy'

/** Recepción, no creación ni etapa: incluye los recibidos hoy aunque ya se
 * hayan gestionado. En real el ledger del servidor filtra ANTES de paginar. */
export function LeadsRecibidosHoy({ ahora, className, integrado = false }: { ahora: number; className?: string; integrado?: boolean }): JSX.Element {
  const datos = useLeadsRecibidosHoy(ahora)
  return <ListaLeadsRecibidosHoy datos={datos} className={className} integrado={integrado} />
}

/** El panel y su pestaña consumen la misma foto, sin consultas ni sondeos dobles. */
export function ListaLeadsRecibidosHoy({ datos, className, integrado = false }: {
  datos: DatosLeadsRecibidosHoy; className?: string | undefined; integrado?: boolean
}): JSX.Element {
  const tituloId = useId()
  const { cartera, total, demo } = datos
  const { abrirLead } = usePanelesActions()
  const listaRef = useRef<HTMLUListElement>(null)
  const reintentarRef = useRef<HTMLButtonElement>(null)
  const enfocarDesde = useRef<number | null>(null)
  useEffect(() => {
    if (enfocarDesde.current == null || cartera.cargandoMas) return
    if (cartera.leads.length > enfocarDesde.current) {
      listaRef.current?.querySelectorAll<HTMLButtonElement>('li button')[enfocarDesde.current]?.focus()
    } else if (cartera.error) {
      reintentarRef.current?.focus()
    }
    enfocarDesde.current = null
  }, [cartera.leads.length, cartera.cargandoMas, cartera.error])

  return (
    <Card role="region" aria-labelledby={tituloId} className={cn('flex min-h-0 min-w-0 flex-col', integrado && 'flex-1 rounded-none border-0 bg-transparent shadow-none', className)}>
      <div className={cn('flex shrink-0 items-center gap-2 px-5 pb-1', integrado ? 'pt-0' : 'pt-3')}>
        {!integrado && <UserPlus className="size-4 shrink-0 text-accent" aria-hidden />}
        <h3 id={tituloId} className={integrado ? 'sr-only' : 'text-[15px] font-bold tracking-tight'}>Leads recibidos hoy</h3>
        {integrado && <span className="text-xs text-muted-foreground">Recibidos hoy</span>}
        {total != null && <>
          <Badge aria-hidden>{numero(total)}</Badge>
          <span className="sr-only">{numero(total)} {total === 1 ? 'lead recibido hoy' : 'leads recibidos hoy'}</span>
        </>}
        {!demo && <Button className="ml-auto shrink-0" variant="ghost" size="icon"
          aria-label="Actualizar leads recibidos hoy" disabled={cartera.cargando || cartera.cargandoMas}
          onClick={() => void cartera.recargar()}>
          <RefreshCw className="size-3.5" aria-hidden />
        </Button>}
      </div>
      <p className="shrink-0 px-5 pb-2 text-xs text-muted-foreground">Asignados a ti · hora de Lima</p>
      <CardContent className={cn('ac-scroll min-h-0 overflow-y-auto pt-0', integrado ? 'max-h-80 lg:max-h-none lg:flex-1' : 'max-h-48')} aria-busy={cartera.cargando || cartera.cargandoMas}>
        {Boolean(cartera.error) && (
          <div role="alert" className="flex flex-wrap items-center gap-2 py-2">
            <p className="text-sm">No se pudieron cargar los leads recibidos hoy.{cartera.leads.length > 0 ? ' Se conserva la última lista cargada.' : ''}</p>
            <Button ref={reintentarRef} variant="outline" size="sm" onClick={() => void cartera.recargar()}>Reintentar</Button>
          </div>
        )}
        {cartera.cargando ? (
          <p role="status" className="py-2 text-sm text-muted-foreground">Cargando leads recibidos hoy…</p>
        ) : cartera.leads.length === 0 ? (
          !cartera.error && <p className="py-2 text-sm text-muted-foreground">Todavía no has recibido leads hoy.</p>
        ) : (
          <>
            <ul ref={listaRef} aria-label="Leads recibidos hoy" className="divide-y divide-border">
              {cartera.leads.map((lead) => {
                // La demo no tiene ledger; usa el mismo sello de su filtro.
                const recibido = demo ? (lead.tenencia_desde ?? lead.creado_en) : lead.recibido_en
                const instante = recibido ? Date.parse(recibido) : Number.NaN
                const hora = Number.isFinite(instante)
                  ? new Date(instante).toLocaleTimeString('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
                  : null
                const detalleId = `${tituloId}-${lead.id}`
                return (
                  <li key={lead.id}>
                    <button type="button" aria-label={`Abrir lead ${lead.nombre_completo}`}
                      aria-describedby={`${detalleId}-telefono${hora ? ` ${detalleId}-hora` : ''}`}
                      onClick={() => abrirLead(lead.id)}
                      className="flex min-h-12 w-full cursor-pointer items-center gap-2 rounded-lg px-2 py-2 text-left hover:bg-muted/60 focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-ring">
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-sm font-semibold">{lead.nombre_completo}</span>
                        <span id={`${detalleId}-telefono`} className="block text-xs text-muted-foreground">{lead.telefono}</span>
                      </span>
                      {hora && <>
                        <span id={`${detalleId}-hora`} className="sr-only">{`Recibido a las ${hora}${lead.recepcion_aproximada ? ' aprox.' : ''}`}</span>
                        <span aria-hidden className="shrink-0 text-xs tabular-nums text-muted-foreground">{hora}{lead.recepcion_aproximada ? ' aprox.' : ''}</span>
                      </>}
                      <ChevronRight className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                    </button>
                  </li>
                )
              })}
            </ul>
            {cartera.hayMas && (
              <Button variant="outline" size="sm" className="mt-2 w-full" aria-disabled={cartera.cargandoMas} onClick={(evento) => {
                if (cartera.cargandoMas) return
                if (document.activeElement === evento.currentTarget) enfocarDesde.current = cartera.leads.length
                cartera.cargarMas()
              }}>
                {cartera.cargandoMas ? 'Cargando…' : 'Cargar más leads de hoy'}
              </Button>
            )}
          </>
        )}
      </CardContent>
    </Card>
  )
}
