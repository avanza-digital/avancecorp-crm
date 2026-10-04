// Historial COMPLETO de un lead de la base (F2): el encargo pide leerlo de corrido, sin truncar ni plegar. Se
// recorre el cursor de `crm.actividades_de_lead_fn` hasta el final (página a página, sola) y se filtra en el
// navegador con un buscador sin tildes ni mayúsculas. Del más reciente al más antiguo, con fecha, quién y qué pasó;
// las reasignaciones y los intentos de la base se leen como lo que fueron. Estados honestos: cargando, error con
// reintento, vacío y «nada coincide» son distintos.
import { useEffect, useId, useMemo, useState, type JSX } from 'react'
import { RotateCcw, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { etiquetaActividadBase, etiquetaFechaHistorial, filtrarHistorial } from '@/lib/base-gestion'
import { cn } from '@/lib/utils'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'

export function HistorialBase({ leadId }: { leadId: string }): JSX.Element {
  const id = useId()
  const historial = useActividadesDeLead(leadId)
  const [buscado, setBuscado] = useState('')
  const { hayMas, cargandoMas, error, cargarMas } = historial

  // Recorre el cursor hasta el final: una página tras otra mientras el servidor diga que hay más.
  useEffect(() => {
    if (hayMas && !cargandoMas && error == null) cargarMas()
  }, [hayMas, cargandoMas, error, cargarMas])

  const ahora = Date.now()
  const visibles = useMemo(() => filtrarHistorial(historial.items, buscado), [historial.items, buscado])
  const completo = !historial.cargando && !hayMas && error == null
  const total = historial.items.length

  return (
    // El recorte con scroll propio es SOLO de escritorio (dos columnas): en el celular la ficha entera se desplaza y un
    // `min-h-0` dejaría el historial en 0 px de alto (revisor-a11y, WCAG 1.4.10).
    <section aria-labelledby={`${id}-titulo`} className="flex flex-col rounded-xl border border-border bg-card lg:min-h-0">
      <div className="flex flex-wrap items-center gap-3 border-b border-border px-4 py-3">
        <h3 id={`${id}-titulo`} className="text-base font-bold text-foreground">
          Historial <span className="text-sm font-normal text-[var(--muted-foreground-strong)]">({completo ? `${total} ${total === 1 ? 'gestión' : 'gestiones'}` : 'cargando…'})</span>
        </h3>
        <div className="relative ml-auto w-full sm:w-64">
          <Search aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <label htmlFor={`${id}-buscar`} className="sr-only">Buscar en el historial</label>
          <input
            id={`${id}-buscar`}
            type="search"
            value={buscado}
            onChange={(e) => setBuscado(e.target.value)}
            placeholder="Buscar en el historial"
            className={cn('h-10 w-full rounded-lg border border-input bg-background pl-8 pr-3 text-sm text-foreground placeholder:text-[var(--muted-foreground-strong)]', FOCO)}
          />
        </div>
      </div>
      {/* Un solo aviso al terminar de cargar (no uno por página), y el resultado del buscador. */}
      <p role="status" className="sr-only">
        {!completo ? '' : buscado ? `${visibles.length} de ${total} gestiones coinciden` : `Historial cargado: ${total} ${total === 1 ? 'gestión' : 'gestiones'}`}
      </p>

      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- El historial se desplaza con el teclado (misma excepción que la hoja). */}
      <div tabIndex={0} role="region" aria-label="Gestiones del lead" className={cn('ac-scroll px-4 py-3 lg:min-h-0 lg:flex-1 lg:overflow-y-auto', FOCO)}>
        {historial.cargando && (
          <ul aria-hidden className="space-y-3">
            {[0, 1, 2].map((n) => <li key={n} className="h-12 animate-pulse rounded-lg bg-muted motion-reduce:animate-none" />)}
          </ul>
        )}
        {error != null && !historial.cargando && (
          <div className="flex flex-wrap items-center gap-3 rounded-lg border border-border bg-muted/40 px-3 py-2.5">
            <p role="alert" className="text-sm text-foreground">
              {total > 0 ? 'No se pudo cargar el resto del historial.' : 'No se pudo cargar el historial.'}
            </p>
            <Button type="button" size="sm" variant="outline" onClick={historial.reintentar}><RotateCcw aria-hidden /> Reintentar</Button>
          </div>
        )}
        {!historial.cargando && error == null && total === 0 && (
          <p className="text-sm text-[var(--muted-foreground-strong)]">Este lead no tiene gestiones registradas.</p>
        )}
        {total > 0 && visibles.length === 0 && (
          <p className="text-sm text-[var(--muted-foreground-strong)]">Nada del historial coincide con «{buscado.trim()}».</p>
        )}
        {visibles.length > 0 && (
          <ol aria-label="De la más reciente a la más antigua" className="divide-y divide-border">
            {visibles.map((a) => (
              <li key={a.id} className="grid gap-x-4 gap-y-0.5 py-2.5 sm:grid-cols-[9.5rem_minmax(0,1fr)]">
                <span className="text-sm tabular-nums text-[var(--muted-foreground-strong)]">{etiquetaFechaHistorial(a.creado_en, ahora)}</span>
                <div className="min-w-0">
                  <p className="text-[15px] font-semibold text-foreground">{etiquetaActividadBase(a)}</p>
                  {a.detalle && <p className="whitespace-pre-line break-words text-sm text-foreground">{a.detalle}</p>}
                  <p className="text-[13px] text-[var(--muted-foreground-strong)]">{a.autor_nombre}</p>
                </div>
              </li>
            ))}
          </ol>
        )}
        {cargandoMas && <p className="py-2 text-sm text-[var(--muted-foreground-strong)]">Cargando gestiones anteriores…</p>}
      </div>
    </section>
  )
}
