// La cola del día (rediseño del 27/09/2026, diseño de Gestión Diaria con los
// colores del CRM). Filtros en PASTILLA —«Todo» primero y los cuatro grupos—,
// una sola lista a la vista y filas limpias de borde a borde: iniciales,
// nombre, qué toca y el tiempo en palabras. El contexto largo sigue en
// «Ahora»: elegir una fila la lleva allí. Escala y aire: los del diseño.
//
// «Todo» NO es un grupo (hallazgo de Codex): es la cola entera en el orden del
// día. Las pastillas siguen siendo `tab`/`tabpanel` para el lector de pantalla.
//
// La fila es un `<button>` real con `aria-current`, no un `div` con onClick ni
// un `aria-pressed`: esto es una selección única dentro de una lista, y así el
// tabulador y el lector de pantalla la entienden sin inventar teclado propio.
// La elegida se marca con el avatar RELLENO (cambia la forma, no solo el color),
// el nombre en azul y, para el lector, `aria-current` + «Elegido».
import type { JSX } from 'react'
import { ChevronLeft, ChevronRight, PhoneCall } from 'lucide-react'
import { ChipTiempo } from '@/components/gestion-diaria/chip-tiempo'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { Avatar } from '@/components/ui/avatar'
import { Tabs } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'
import {
  FILTRO_TODO, GRUPOS_DIA, detalleDeFila, filasDelFiltro, paginaDeFilas,
  type FilaDiaria, type FiltroCola, type GrupoDia,
} from '@/lib/gestion-diaria-analista'
import { hashDe } from '@/lib/router'

export const FILAS_POR_PAGINA = 8

export interface PestanaCola {
  clave: GrupoDia
  etiqueta: string
  ayuda: string
  total: number
  filas: FilaDiaria[]
}

const ETIQUETA_GRUPO = Object.fromEntries(GRUPOS_DIA.map((g) => [g.clave, g.etiqueta])) as Record<GrupoDia, string>
const BOTON_PAGINA = 'inline-flex h-8 cursor-pointer items-center gap-1 rounded-lg border border-border bg-card px-2.5 text-[13px] font-semibold text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring aria-disabled:cursor-default aria-disabled:opacity-45 aria-disabled:hover:bg-card'

export function ColaDeHoy({
  idBase, pestanas, filtro, onFiltro, pagina, onPagina, elegido, onElegir, ahora, cargando, hayMas, colaCaida, sinConversacionDias,
}: {
  /** Base de `useId()` de la pantalla: dos instancias no pueden compartir id. */
  idBase: string
  pestanas: readonly PestanaCola[]
  filtro: FiltroCola
  onFiltro: (filtro: FiltroCola) => void
  pagina: number
  onPagina: (pagina: number) => void
  elegido: string | null
  onElegir: (fila: FilaDiaria) => void
  ahora: number
  cargando: boolean
  /** El servidor dice que hay más de lo que cabe en esta lectura. */
  hayMas: boolean
  /**
   * La cola del servidor no llegó. Los tres primeros grupos SALEN de ella, así
   * que sus conteos no son ceros: son desconocidos. Decir «Vencidas (0)» haría
   * que el analista se fuera a casa creyendo que no debía nada (Codex, 20/09).
   */
  colaCaida: boolean
  sinConversacionDias: number
}): JSX.Element {
  const lista = filasDelFiltro(pestanas, filtro)
  const vista = paginaDeFilas(lista, pagina, FILAS_POR_PAGINA)
  const sinAnterior = vista.pagina === 0
  const sinSiguiente = vista.pagina >= vista.paginas - 1
  const vacioTodo = pestanas.every((p) => p.total === 0)
  const total = pestanas.reduce((n, p) => n + p.total, 0)
  // Con la cola caída, lo que sale de ella no tiene conteo conocido: «?» y no
  // «0». Con `hayMas` el conteo es un MÍNIMO.
  const conteo = (clave: FiltroCola, n: number) => colaCaida && clave !== 'sin_conversacion' ? '?' : hayMas ? `${n}+` : String(n)
  const etiquetaFiltro = filtro === 'todo' ? FILTRO_TODO.etiqueta : ETIQUETA_GRUPO[filtro]
  const ayuda = filtro === 'todo' ? 'El orden lo pone el servidor, como en tu Hoy.' : pestanas.find((p) => p.clave === filtro)?.ayuda

  return (
    <section aria-labelledby={`${idBase}-cola`} className="relative flex min-h-0 flex-1 flex-col">
      <h3 id={`${idBase}-cola`} className="sr-only">Cola de hoy</h3>
      {cargando ? (
        <div className="p-[18px]"><PanelCargando filas={FILAS_POR_PAGINA} /></div>
      ) : vacioTodo && !colaCaida ? (
        <PanelVacio
          icono={PhoneCall}
          titulo="No tienes nada pendiente ahora"
          detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana."
        />
      ) : (
        <>
          <p className="pointer-events-none absolute right-[18px] top-3 hidden h-9 items-center text-xs text-[var(--muted-foreground-strong)] 2xl:flex">{ayuda}</p>
          <Tabs
            etiqueta="Grupos de la cola"
            variante="pastilla"
            valor={filtro}
            onCambio={onFiltro}
            pestanas={[
              { valor: 'todo' as FiltroCola, etiqueta: FILTRO_TODO.etiqueta, extra: conteo('todo', total) },
              ...pestanas.map((p) => ({ valor: p.clave as FiltroCola, etiqueta: p.etiqueta, extra: conteo(p.clave, p.total) })),
            ]}
            className="flex min-h-0 flex-1 flex-col space-y-0 [&>[role=tablist]]:gap-1.5 [&>[role=tablist]]:border-b [&>[role=tablist]]:border-muted [&>[role=tablist]]:px-[18px] [&>[role=tablist]]:py-3 [&>[role=tablist]>[role=tab]]:min-h-9 [&>[role=tablist]>[role=tab]]:px-3 [&>[role=tablist]>[role=tab]]:py-0 [&>[role=tablist]>[role=tab]]:text-[12.5px] [&>[role=tablist]>[role=tab]]:font-bold [&>[role=tablist]>[role=tab]>span]:text-[12.5px]"
            clasePanel="flex min-h-0 flex-1 flex-col"
          >
            {vista.total === 0 ? (
              <p role="status" className="px-[18px] py-7 text-center text-[13px] text-[var(--muted-foreground-strong)]">
                {colaCaida && filtro !== 'sin_conversacion'
                  ? 'No se pudo leer esta parte de la cola del servidor. No está vacía: no se sabe. Actualiza para verla.'
                  : 'Nada en este grupo. Mira los otros: su número está al lado del nombre.'}
              </p>
            ) : (
              <>
                {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
                <ol role="list" aria-label={`${etiquetaFiltro} (${vista.rango})`} className="ac-scroll min-h-0 flex-1 overflow-y-auto">
                  {vista.filas.map((fila) => {
                    const seleccionada = fila.lead_id === elegido
                    const apoyo = filtro === 'todo'
                      ? `${ETIQUETA_GRUPO[fila.grupo]} · ${detalleDeFila(fila, sinConversacionDias)}`
                      : detalleDeFila(fila, sinConversacionDias)
                    return (
                      <li key={fila.lead_id} className="border-b border-muted">
                        <button
                          type="button"
                          {...(seleccionada ? { 'aria-current': true as const } : {})}
                          onClick={() => onElegir(fila)}
                          className={cn(
                            'flex w-full min-h-[62px] cursor-pointer items-center gap-3 px-[18px] text-left transition-colors',
                            'focus-visible:-outline-offset-2 focus-visible:outline-2 focus-visible:outline-ring',
                            seleccionada ? 'bg-accent/[0.06]' : 'hover:bg-muted/50',
                          )}
                        >
                          <Avatar nombre={fila.nombre_completo} color="var(--accent-press)" relleno={seleccionada} />
                          <span className="flex min-w-0 flex-1 flex-col gap-px">
                            <span className={cn('truncate text-sm font-bold', seleccionada ? 'text-[var(--accent-press)]' : 'text-primary')}>{fila.nombre_completo}</span>
                            <span className="truncate text-xs font-medium text-[var(--muted-foreground-strong)]">{apoyo}</span>
                          </span>
                          {seleccionada && <span className="sr-only">Elegido</span>}
                          <ChipTiempo fila={fila} ahora={ahora} className="shrink-0" />
                        </button>
                      </li>
                    )
                  })}
                </ol>

                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border px-[18px] py-2.5">
                  {/* Se ANUNCIA: al pasar de página cambian las filas y sin esto el
                      lector de pantalla no diría nada (WCAG 4.1.3). */}
                  <p role="status" aria-live="polite" className="text-xs tabular-nums text-[var(--muted-foreground-strong)]">
                    {vista.rango}{hayMas && <> de los cargados · <a className="font-semibold text-primary underline underline-offset-4" href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })}>Ver todas las oportunidades</a></>}
                  </p>
                  <div className="flex items-center gap-1.5">
                    {/* `aria-disabled` y no `disabled`, con la guarda en el handler:
                        el botón se deshabilita a sí mismo al pulsarse (última página)
                        y un `disabled` sobre el elemento enfocado manda el foco al
                        body — la misma regla de la casa que «Deshacer». */}
                    <button type="button" className={BOTON_PAGINA} aria-disabled={sinAnterior}
                      onClick={() => { if (!sinAnterior) onPagina(vista.pagina - 1) }}><ChevronLeft aria-hidden className="size-4" />Anterior</button>
                    <button type="button" className={BOTON_PAGINA} aria-disabled={sinSiguiente}
                      onClick={() => { if (!sinSiguiente) onPagina(vista.pagina + 1) }}>Siguiente<ChevronRight aria-hidden className="size-4" /></button>
                  </div>
                </div>
              </>
            )}
          </Tabs>
        </>
      )}
    </section>
  )
}
