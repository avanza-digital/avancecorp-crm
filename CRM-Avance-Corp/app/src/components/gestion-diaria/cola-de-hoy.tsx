// La cola del día: cuatro grupos en PESTAÑAS, una sola lista a la vista.
//
// Antes se pintaban los cuatro bloques uno debajo de otro y había que
// desplazarse para ver la mitad. Ahora el conteo de cada pestaña deja ver el
// volumen sin ocupar la pantalla, y solo se lee lo que toca. Cada fila tiene
// DOS líneas —nombre y tiempo— porque el contexto largo se mudó a «Ahora»:
// elegir una fila la lleva allí.
//
// La fila es un `<button>` real con `aria-current`, no un `div` con onClick ni
// un `aria-pressed`: esto es una selección única dentro de una lista, y así el
// tabulador y el lector de pantalla la entienden sin inventar teclado propio.
import type { JSX } from 'react'
import { PhoneCall } from 'lucide-react'
import { ChipTiempo } from '@/components/gestion-diaria/chip-tiempo'
import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
import { Button } from '@/components/ui/button'
import { Tabs } from '@/components/ui/tabs'
import { cn } from '@/lib/utils'
import { paginaDeFilas, type FilaDiaria, type GrupoDia } from '@/lib/gestion-diaria-analista'

export const FILAS_POR_PAGINA = 5

export interface PestanaCola {
  clave: GrupoDia
  etiqueta: string
  ayuda: string
  total: number
  filas: FilaDiaria[]
}

export function ColaDeHoy({
  idBase, pestanas, activa, onPestana, pagina, onPagina, elegido, onElegir, ahora, cargando, hayMas,
}: {
  /** Base de `useId()` de la pantalla: dos instancias no pueden compartir id. */
  idBase: string
  pestanas: readonly PestanaCola[]
  activa: GrupoDia
  onPestana: (grupo: GrupoDia) => void
  pagina: number
  onPagina: (pagina: number) => void
  elegido: string | null
  onElegir: (fila: FilaDiaria) => void
  ahora: number
  cargando: boolean
  /** El servidor dice que hay más de lo que cabe en esta lectura. */
  hayMas: boolean
}): JSX.Element {
  const grupo = pestanas.find((p) => p.clave === activa) ?? pestanas[0]
  const vista = paginaDeFilas(grupo?.filas ?? [], pagina, FILAS_POR_PAGINA)
  const sinAnterior = vista.pagina === 0
  const sinSiguiente = vista.pagina >= vista.paginas - 1
  const vacioTodo = pestanas.every((p) => p.total === 0)

  return (
    <section aria-labelledby={`${idBase}-cola`} className="flex min-w-0 flex-1 flex-col gap-4 rounded-2xl border border-border bg-card p-6">
      <h3 id={`${idBase}-cola`} className="text-xl font-semibold text-primary">Cola de hoy</h3>

      {cargando ? (
        <PanelCargando filas={FILAS_POR_PAGINA} />
      ) : vacioTodo ? (
        <PanelVacio
          icono={PhoneCall}
          titulo="No tienes nada pendiente ahora"
          detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana."
          tamano="grande"
        />
      ) : (
        <Tabs
          etiqueta="Grupos de la cola"
          tamano="grande"
          valor={activa}
          onCambio={onPestana}
          pestanas={pestanas.map((p) => ({
            valor: p.clave,
            etiqueta: p.etiqueta,
            // Con `hayMas` el servidor tiene filas que esta lectura no trajo:
            // el conteo es un MÍNIMO y se dice con el «+», no se promete total.
            extra: hayMas ? `${p.total}+` : String(p.total),
          }))}
          className="flex min-h-0 flex-1 flex-col [&>[role=tabpanel]]:flex [&>[role=tabpanel]]:min-h-0 [&>[role=tabpanel]]:flex-1 [&>[role=tabpanel]]:flex-col [&>[role=tabpanel]]:gap-4"
        >
          <p className="text-base text-[var(--muted-foreground-strong)]">{grupo?.ayuda}</p>

          {vista.total === 0 ? (
            <p role="status" className="text-base text-[var(--muted-foreground-strong)]">
              Nada en este grupo. Mira las otras pestañas: su número está al lado del nombre.
            </p>
          ) : (
            <>
              {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
              <ol role="list" aria-label={`${grupo?.etiqueta} (${vista.rango})`} className="flex min-h-0 flex-1 flex-col gap-2">
                {vista.filas.map((fila) => {
                  const seleccionada = fila.lead_id === elegido
                  return (
                    <li key={fila.lead_id} className="flex flex-1">
                      <button
                        type="button"
                        {...(seleccionada ? { 'aria-current': true as const } : {})}
                        onClick={() => onElegir(fila)}
                        className={cn(
                          'flex w-full min-h-[5.5rem] cursor-pointer items-center justify-between gap-4 rounded-xl px-5 py-4 text-left transition-colors',
                          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-card',
                          seleccionada
                            ? 'border-2 border-primary bg-card'
                            : 'border border-border-strong bg-card hover:bg-muted',
                        )}
                      >
                        <span className="flex min-w-0 flex-col gap-1">
                          <span className="truncate text-lg font-medium leading-7 text-foreground">{fila.nombre_completo}</span>
                          <ChipTiempo fila={fila} ahora={ahora} className="self-start" />
                        </span>
                        {seleccionada && (
                          <span className="shrink-0 text-base font-medium text-primary">Elegido</span>
                        )}
                      </button>
                    </li>
                  )
                })}
              </ol>

              <div className="flex flex-wrap items-center justify-between gap-4">
                {/* Se ANUNCIA: al pasar de página cambian las cinco filas y sin
                    esto el lector de pantalla no diría nada (WCAG 4.1.3). */}
                <p role="status" aria-live="polite" className="text-base text-[var(--muted-foreground-strong)]">
                  {vista.rango}{hayMas && ' de los cargados · hay más en Seguimiento comercial'}
                </p>
                <div className="flex gap-3">
                  {/* `aria-disabled` y no `disabled`, con la guarda en el handler:
                      el botón se deshabilita a sí mismo al pulsarse (última página)
                      y un `disabled` sobre el elemento enfocado manda el foco al
                      body — la misma regla de la casa que «Deshacer». */}
                  <Button variant="outline" className="h-12 text-base font-normal aria-disabled:opacity-50 aria-disabled:cursor-default"
                    aria-disabled={sinAnterior} onClick={() => { if (!sinAnterior) onPagina(vista.pagina - 1) }}>Anterior</Button>
                  <Button variant="outline" className="h-12 text-base font-normal aria-disabled:opacity-50 aria-disabled:cursor-default"
                    aria-disabled={sinSiguiente} onClick={() => { if (!sinSiguiente) onPagina(vista.pagina + 1) }}>Siguiente</Button>
                </div>
              </div>
            </>
          )}
        </Tabs>
      )}
    </section>
  )
}
