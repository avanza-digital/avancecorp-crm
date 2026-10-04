// Historial COMPLETO de un lead de la base (F2): el encargo pide leerlo de corrido, sin truncar ni plegar. Se
// recorre el cursor de `crm.actividades_de_lead_fn` hasta el final (página a página, sola) y se filtra en el
// navegador con un buscador sin tildes ni mayúsculas. Del más reciente al más antiguo, con quién y cuándo; las
// reasignaciones, los intentos, las reactivaciones y el «No contactar» se leen como lo que fueron. Estados honestos:
// cargando, error con reintento, vacío y «nada coincide» son distintos.
// Se pinta con la MISMA línea de tiempo que la ficha del lead (Miguel, 03/10): sin buscar, las rachas de cambios
// de etapa se agrupan como allí; buscando, cada coincidencia va suelta (un grupo plegado escondería lo encontrado).
import { useEffect, useId, useMemo, useRef, useState, type JSX, type ReactNode } from 'react'
import { RotateCcw, Search } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { iconoActividad } from '@/components/app/actividad-visual'
import { EsqueletoLinea, LineaDeTiempo, type PresentacionActividad } from '@/components/app/linea-de-tiempo'
import { useActividadesDeLead } from '@/data/use-actividades-de-lead'
import { useAhora } from '@/lib/ahora'
import { etiquetaActividadBase, filtrarHistorial } from '@/lib/base-gestion'
import { agruparTimeline, type ItemTimeline } from '@/lib/timeline-lead'
import type { Actividad } from '@/lib/tipos'
import { cn } from '@/lib/utils'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'

/** Título e icono propios de la base («Intento 2 · No contestó», «Marcado «No contactar»»…); el «cuándo», el de siempre. */
const presentar = (a: Actividad): PresentacionActividad => ({ titulo: etiquetaActividadBase(a), Icono: iconoActividad(a) })

/** Espera antes de anunciar el resultado del buscador: el filtrado se ve al instante, pero el lector de pantalla
 *  no recita una cifra por cada tecla (solo la de cuando se deja de escribir). */
const ESPERA_ANUNCIO_MS = 400

/** Una fila del riel sin hito (estados del historial), alineada con el texto de las actividades. */
function FilaEstado({ children }: { children: ReactNode }) {
  return (
    <li className="flex gap-2.5">
      <span className="w-7 shrink-0" aria-hidden />
      <div className="min-w-0 flex-1 pt-0.5">{children}</div>
    </li>
  )
}

export function HistorialBase({ leadId }: { leadId: string }): JSX.Element {
  const id = useId()
  const ahora = useAhora()
  const historial = useActividadesDeLead(leadId)
  const [buscado, setBuscado] = useState('')
  const region = useRef<HTMLDivElement>(null)
  const { hayMas, cargandoMas, error, cargarMas } = historial

  // Recorre el cursor hasta el final: una página tras otra mientras el servidor diga que hay más.
  useEffect(() => {
    if (hayMas && !cargandoMas && error == null) cargarMas()
  }, [hayMas, cargandoMas, error, cargarMas])

  const buscando = buscado.trim() !== ''
  const visibles = useMemo(() => filtrarHistorial(historial.items, buscado), [historial.items, buscado])
  const items = useMemo<ItemTimeline[]>(
    () => (buscando ? visibles.map((act) => ({ clase: 'act', act })) : agruparTimeline(visibles)),
    [buscando, visibles],
  )
  const completo = !historial.cargando && !hayMas && error == null
  const total = historial.items.length
  const conteo = !completo ? 'cargando…' : buscando ? `${visibles.length} de ${total}` : String(total)
  // Un solo aviso al terminar de cargar (no uno por página), y el resultado del buscador cuando se deja de escribir.
  const estado = !completo ? '' : buscando ? `${visibles.length} de ${total} gestiones coinciden` : `Actividad cargada: ${total} ${total === 1 ? 'gestión' : 'gestiones'}`
  const [anunciado, setAnunciado] = useState(estado)
  useEffect(() => {
    const espera = setTimeout(() => setAnunciado(estado), ESPERA_ANUNCIO_MS)
    return () => clearTimeout(espera)
  }, [estado])

  return (
    // El recorte con scroll propio es SOLO de escritorio (dos columnas): en el celular la ficha entera se desplaza y un
    // `min-h-0` dejaría el historial en 0 px de alto (revisor-a11y, WCAG 1.4.10).
    // Sin nombre accesible a propósito: la región nombrada es UNA, «Gestiones del lead» (dos anidadas se leen doble).
    <section className="flex flex-col lg:min-h-0 lg:border-l lg:border-border lg:pl-5">
      <div className="flex flex-wrap items-center gap-3">
        <h3 className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
          Actividad <span className="tabular-nums">({conteo})</span>
        </h3>
        <div className="relative ml-auto w-full sm:w-64">
          <Search aria-hidden className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <label htmlFor={`${id}-buscar`} className="sr-only">Buscar en la actividad</label>
          <input
            id={`${id}-buscar`}
            type="search"
            value={buscado}
            onChange={(e) => setBuscado(e.target.value)}
            placeholder="Buscar en la actividad"
            autoComplete="off"
            className={cn('h-10 w-full rounded-lg border border-input bg-background pl-8 pr-3 text-sm text-foreground placeholder:text-[var(--muted-foreground-strong)]', FOCO)}
          />
        </div>
      </div>
      <p role="status" className="sr-only">{anunciado}</p>

      {/* oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La actividad se desplaza con el teclado (misma excepción que la hoja). */}
      <div ref={region} tabIndex={0} role="region" aria-label="Gestiones del lead" className={cn('ac-scroll mt-3 overscroll-contain rounded-lg pr-2 lg:min-h-0 lg:flex-1 lg:overflow-y-auto', FOCO)}>
        <LineaDeTiempo
          items={items}
          ahora={ahora}
          presentar={presentar}
          aria-label="De la más reciente a la más antigua"
          ariaBusy={historial.cargando || cargandoMas}
          antes={
            <>
              {historial.cargando && <EsqueletoLinea filas={3} />}
              {error != null && !historial.cargando && (
                <FilaEstado>
                  <p role="alert" className="text-xs text-[var(--destructive-text)]">
                    {total > 0 ? 'No se pudo cargar el resto del historial.' : 'No se pudo cargar el historial.'}
                  </p>
                  {/* Si sale bien, el botón desaparece: el foco se queda en la región, no cae en <body> (WCAG 2.4.3). */}
                  <Button
                    type="button"
                    size="xs"
                    variant="outline"
                    className="mt-1.5"
                    onClick={() => {
                      region.current?.focus({ preventScroll: true })
                      historial.reintentar()
                    }}
                  >
                    <RotateCcw aria-hidden /> Reintentar
                  </Button>
                </FilaEstado>
              )}
              {!historial.cargando && error == null && total === 0 && (
                <FilaEstado><p className="text-xs text-muted-foreground">Este lead no tiene gestiones registradas.</p></FilaEstado>
              )}
              {total > 0 && visibles.length === 0 && (
                <FilaEstado><p className="text-xs text-muted-foreground">Nada de la actividad coincide con «{buscado.trim()}».</p></FilaEstado>
              )}
            </>
          }
        >
          {cargandoMas && <FilaEstado><p className="text-xs text-muted-foreground">Cargando gestiones anteriores…</p></FilaEstado>}
        </LineaDeTiempo>
      </div>
    </section>
  )
}
