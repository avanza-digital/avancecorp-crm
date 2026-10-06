import { useEffect, useEffectEvent, useLayoutEffect, useMemo, useRef } from 'react'
import { useRegistroActividadOperativo } from '@/data/gestion-diaria-queries'
import { CrmApiError } from '@/data/crm-api'
import { EnlaceSujetoGestion } from './enlace-sujeto'
import { etiquetaGestion, horaDeItem, type FiltrosRegistro } from '@/lib/gestion-diaria'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'

const HORA = new Intl.DateTimeFormat('es-PE', { timeZone: 'America/Lima', hour: '2-digit', minute: '2-digit', hour12: false })

/** Las 3 últimas gestiones del analista con el diseño de Gestión Diaria (27/09):
 * hora, etiqueta del resultado y el lead (abre su ficha). Misma consulta y clave
 * que «Registro → Todo», así que no pide nada de más. */
export function UltimasGestionesSupervisor({ analista, dia, visible, actualizacion, revalidar, silencioso = false }: {
  analista: string; dia: string; visible: boolean; actualizacion: number; revalidar: () => void
  /** Panel abierto solo (selección automática): sin anunciar cargas ni errores. */
  silencioso?: boolean
}) {
  const filtros = useMemo<FiltrosRegistro>(() => ({ dia, analistaIds: [analista], pestana: 'todo', etapa: null }), [dia, analista])
  // Misma clave y tamaño que Registro → Todo, primera página sin filtro.
  const consulta = useRegistroActividadOperativo(filtros, null, 25, visible, true)
  const revision = useRef(actualizacion)
  const refrescar = useEffectEvent(() => { void consulta.recargar() })
  const revocar = useEffectEvent(revalidar)
  const sinPermiso = consulta.error instanceof CrmApiError && consulta.error.code === '42501'
  useEffect(() => {
    if (revision.current === actualizacion) return
    revision.current = actualizacion; refrescar()
  }, [actualizacion])
  useEffect(() => { if (sinPermiso) revocar() }, [sinPermiso])
  // Si «Reintentar» se desmonta con el foco dentro (salió bien), el foco pasa al título.
  const titulo = useRef<HTMLHeadingElement>(null)
  const focoEnReintento = useRef(false)
  useLayoutEffect(() => {
    if (consulta.error) return
    if (focoEnReintento.current) { focoEnReintento.current = false; titulo.current?.focus({ preventScroll: true }) }
  }, [consulta.error])
  return <section className="space-y-2" aria-label="Últimas gestiones del analista">
    <div className="flex items-baseline justify-between gap-3">
      <h4 ref={titulo} tabIndex={-1} className="rounded-md text-[15px] font-extrabold text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring">Últimas gestiones</h4>
      {consulta.pagina && <p className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">Consulta {HORA.format(new Date(consulta.pagina.generado_en))}</p>}
    </div>
    {consulta.cargando && <p role={silencioso ? undefined : 'status'} className="text-[13px] text-[var(--muted-foreground-strong)]">Consultando las últimas gestiones…</p>}
    {consulta.error ? <div role={silencioso ? undefined : 'alert'} className="space-y-2 text-[13px]"><p>No se pudieron confirmar las últimas gestiones.</p>
      {!sinPermiso && <Button className="h-9 text-[13px] pointer-coarse:h-11 aria-disabled:cursor-default aria-disabled:opacity-60" variant="outline" aria-disabled={consulta.enVuelo}
        onFocus={() => { focoEnReintento.current = true }} onBlur={() => { focoEnReintento.current = false }}
        onClick={() => { if (!consulta.enVuelo) void consulta.recargar() }}>Reintentar últimas gestiones</Button>}</div>
      : consulta.pagina && consulta.pagina.items.length === 0 ? <p className="text-[13px] text-[var(--muted-foreground-strong)]">No hay gestiones visibles de este analista en el día.</p>
        // oxlint-disable-next-line jsx-a11y/no-redundant-roles
        : <ol role="list" className="divide-y divide-border">{consulta.pagina?.items.slice(0, 3).map(item => <li key={`${item.origen ?? 'lead'}:${item.id}`} className="flex min-w-0 items-center gap-3 py-2">
          <time dateTime={new Date(item.creado_en).toISOString()} className="w-11 shrink-0 text-[13px] tabular-nums text-[var(--muted-foreground-strong)]">{horaDeItem(item)}</time>
          <Badge className="min-h-[22px] shrink-0 py-0 text-[11.5px]" color="var(--primary)" variant="outline">{etiquetaGestion(item)}</Badge>
          <EnlaceSujetoGestion sujeto={item} />
        </li>)}</ol>}
  </section>
}
