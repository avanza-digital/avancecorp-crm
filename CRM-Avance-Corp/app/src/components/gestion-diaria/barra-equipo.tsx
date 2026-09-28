// Barra de la tabla de analistas (diseño de Gestión Diaria, 27/09/2026): el
// resumen del equipo SON los filtros —cada número abre su lista en la tabla— y
// el buscador. La comparten el supervisor y gerencia dentro de un equipo.
import type { JSX } from 'react'
import { Check, Search } from 'lucide-react'
import { Input } from '@/components/ui/input'
import type { EstadoEquipo, FiltrosEquipo } from '@/lib/gestion-diaria-equipo'
import { cn } from '@/lib/utils'
import { CONTROL, PILDORA, PILDORA_ACTIVA, PILDORA_INACTIVA } from './estilos-gestion'

export type Pildora = EstadoEquipo | 'atencion'
const PILDORAS: readonly { valor: Pildora; etiqueta: string }[] = [
  { valor: 'todos', etiqueta: 'Todos' }, { valor: 'con_registro', etiqueta: 'Con registro' },
  { valor: 'sin_registro', etiqueta: 'Sin registro' }, { valor: 'con_pendientes', etiqueta: 'Con pendientes' },
  { valor: 'atencion', etiqueta: 'Necesitan atención' },
]

export interface ConteosEquipo { analistas: number; con_actividad: number; sin_actividad: number; con_pendientes: number }

/** Las MISMAS reglas que el filtro (`resumenEquipo`): el número es la lista. */
function conteoPildora(p: Pildora, r: ConteosEquipo, atencion: number): number {
  return p === 'todos' ? r.analistas : p === 'con_registro' ? r.con_actividad : p === 'sin_registro' ? r.sin_actividad
    : p === 'con_pendientes' ? r.con_pendientes : atencion
}

const pildoraDe = (f: FiltrosEquipo): Pildora => f.soloProblemas ? 'atencion' : f.estado ?? 'todos'
/** Cada cifra es del equipo entero: abrirla limpia la búsqueda, así la lista ES esa cifra (Codex, 27/09). */
const aplicarPildora = (f: FiltrosEquipo, p: Pildora): FiltrosEquipo =>
  ({ ...f, busqueda: '', estado: p === 'atencion' ? 'todos' : p, soloProblemas: p === 'atencion' })

export function BarraEquipo({ filtros, setFiltros, conteos, atencion }: {
  filtros: FiltrosEquipo
  setFiltros: (cambio: (f: FiltrosEquipo) => FiltrosEquipo) => void
  conteos: ConteosEquipo
  atencion: number
}): JSX.Element {
  const pildora = pildoraDe(filtros)
  return (
    <div className="flex shrink-0 flex-wrap items-center gap-2 border-b border-border px-4 py-3">
      {/* El resumen del equipo SON los filtros: cada número abre su lista en la
          tabla (Miguel, 27/09: la jerarquía es de la tabla y de la ficha). */}
      <div role="group" aria-label="Resumen del equipo" className="flex flex-wrap items-center gap-1.5">
        {PILDORAS.map((p) => {
          const activa = pildora === p.valor
          const n = conteoPildora(p.valor, conteos, atencion)
          return (
            <button key={p.valor} type="button" aria-pressed={activa} onClick={() => setFiltros((f) => aplicarPildora(f, p.valor))}
              className={cn(PILDORA, activa ? PILDORA_ACTIVA : PILDORA_INACTIVA)}>
              {activa && <Check aria-hidden className="size-3.5" />}{p.etiqueta}{' '}
              {p.valor === 'atencion' && n > 0
                // Ámbar y no rojo: mezcla vencidas con cortes y tiempo sin llamar (Codex, 27/09).
                ? <span className="grid min-w-5 place-items-center rounded-full bg-[var(--warning-text)] px-1.5 text-[11px] font-bold tabular-nums text-white">{n}</span>
                : <span className="font-bold tabular-nums">{n}</span>}
            </button>
          )
        })}
      </div>
      <label className="relative ml-auto min-w-40 max-w-[220px] flex-1"><span className="sr-only">Buscar analista</span>
        <Search aria-hidden className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input type="search" value={filtros.busqueda} onChange={(e) => setFiltros((f) => ({ ...f, busqueda: e.target.value }))} placeholder="Buscar analista…"
          className={cn(CONTROL, 'min-h-0 pl-9 placeholder:text-[var(--muted-foreground-strong)]')} />
      </label>
    </div>
  )
}
