// Panel por analista de la vista del supervisor (F4): una hoja compacta con las cuatro cifras de cada analista activo
// del ámbito (`crm.base_gestion_resumen`). Todo número se abre (Miguel): «En base» y «Para llamar hoy» filtran la hoja
// de abajo por ese analista; «Intentos de hoy» y «Reactivaciones del mes» abren su detalle en una hoja lateral. Una
// cifra en 0 no es botón (no hay nada detrás). Sin la B6b en el servidor, el detalle no existe: esas dos cifras se
// leen pero no se abren. En el celular, una tarjeta por analista.
import type { JSX, ReactNode, Ref } from 'react'
import { Users } from 'lucide-react'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { cn } from '@/lib/utils'
import type { CifraDetalle, FilaResumenBase } from '@/lib/base-gestion'

/** Las cuatro cifras, en el orden de la hoja. `filtra` = la cifra filtra la hoja; si no, abre su detalle. */
const CIFRAS = [
  { clave: 'en_base', rotulo: 'En base', pista: 'ver sus leads en la hoja' },
  { clave: 'rellamadas_hoy', rotulo: 'Para llamar hoy', pista: 'ver sus rellamadas de hoy en la hoja' },
  { clave: 'intentos_hoy', rotulo: 'Intentos de hoy', pista: 'ver el detalle' },
  { clave: 'reactivaciones_mes', rotulo: 'Reactivaciones del mes', pista: 'ver el detalle' },
] as const

type ClaveCifra = (typeof CIFRAS)[number]['clave']

const CELDA = 'whitespace-nowrap border-b border-border px-3 py-1.5 text-sm'
const ENCABEZADO = 'sticky top-0 z-10 whitespace-nowrap border-b border-[var(--border-strong)] bg-muted px-3 py-2 text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]'

export function PanelAnalistas({ idTitulo, filas, esMovil, conDetalle, analistaActivo, onVerEnBase, onVerHoy, onDetalle, regionRef }: {
  /** El h2 visible que nombra la hoja (una sola región, nombrada por su título: no se anuncia dos veces). */
  idTitulo: string
  filas: readonly FilaResumenBase[]
  esMovil: boolean
  /** El servidor tiene la lectura del detalle (B6b): «Intentos de hoy» y «Reactivaciones del mes» se abren. */
  conDetalle: boolean
  /** El analista por el que se está filtrando la hoja (se resalta su renglón). */
  analistaActivo: string | null
  onVerEnBase: (vendedorId: string) => void
  onVerHoy: (vendedorId: string) => void
  onDetalle: (fila: FilaResumenBase, cifra: CifraDetalle) => void
  regionRef?: Ref<HTMLDivElement> | undefined
}): JSX.Element {
  if (filas.length === 0) {
    return (
      <div className="flex items-center gap-3 rounded-lg border border-border bg-card px-4 py-3">
        <Users className="size-4 shrink-0 text-[var(--muted-foreground-strong)]" aria-hidden />
        <p className="text-sm text-[var(--muted-foreground-strong)]">
          No hay analistas activos en tu ámbito. Cuando se sumen al equipo, aquí verás cómo trabajan su base.
        </p>
      </div>
    )
  }

  const accion = (fila: FilaResumenBase, clave: ClaveCifra): (() => void) | undefined => {
    if (fila[clave] === 0) return undefined
    if (clave === 'en_base') return () => onVerEnBase(fila.vendedor_id)
    if (clave === 'rellamadas_hoy') return () => onVerHoy(fila.vendedor_id)
    return conDetalle ? () => onDetalle(fila, clave) : undefined
  }
  const cifra = (fila: FilaResumenBase, c: (typeof CIFRAS)[number]) => (
    <Cifra
      valor={fila[c.clave]}
      contexto={`${fila.nombre}, ${c.rotulo.toLowerCase()}`}
      pista={c.pista}
      urgente={c.clave === 'rellamadas_hoy' && fila.rellamadas_hoy > 0}
      onAbrir={accion(fila, c.clave)}
    />
  )

  if (esMovil) {
    return (
      <div ref={regionRef} tabIndex={-1} role="list" aria-labelledby={idTitulo} className={cn('space-y-2 rounded-lg', FOCO)}>
        {filas.map((fila) => (
          <div role="listitem" key={fila.vendedor_id} className={cn('rounded-xl border bg-card p-3', fila.vendedor_id === analistaActivo ? 'border-accent shadow-[inset_4px_0_0_var(--accent)]' : 'border-border')}>
            <p className="flex flex-wrap items-center gap-2 text-[15px] font-bold text-primary">
              {fila.nombre}
              {fila.vendedor_id === analistaActivo && <EnLaHoja />}
            </p>
            {/* Dos por fila: el número delante de su rótulo (el lector oye rótulo y número, en ese orden). */}
            <dl className="mt-2 grid grid-cols-2 gap-x-2 gap-y-1">
              {CIFRAS.map((c) => (
                <div key={c.clave} className="flex min-w-0 flex-row-reverse items-center justify-end gap-1">
                  <dt className="min-w-0 text-[13px] leading-tight text-[var(--muted-foreground-strong)] [overflow-wrap:anywhere]">{c.rotulo}</dt>
                  <dd className="min-w-10 shrink-0 text-center text-base">{cifra(fila, c)}</dd>
                </div>
              ))}
            </dl>
          </div>
        ))}
      </div>
    )
  }

  return (
    // `scroll-pt-10`: lo que recibe el foco no queda tapado por la cabecera fija (WCAG 2.4.11), como en la hoja.
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- Con muchos analistas la hoja se desplaza con el teclado.
    <div ref={regionRef} className={cn('ac-scroll max-h-[min(40vh,20rem)] scroll-pt-10 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)} tabIndex={0} role="region" aria-labelledby={idTitulo}>
      <table className="min-w-full border-separate border-spacing-0">
        <caption className="sr-only">
          Base para gestión por analista: en base y para llamar hoy filtran la hoja de abajo; intentos de hoy y reactivaciones del mes abren su detalle.
        </caption>
        <thead>
          <tr>
            <th scope="col" className={cn(ENCABEZADO, 'text-left')}>Analista</th>
            {CIFRAS.map((c) => <th key={c.clave} scope="col" className={cn(ENCABEZADO, 'text-right')}>{c.rotulo}</th>)}
          </tr>
        </thead>
        <tbody>
          {filas.map((fila) => {
            const activo = fila.vendedor_id === analistaActivo
            return (
              <tr key={fila.vendedor_id} className={cn(activo ? 'bg-accent/[0.07]' : 'hover:bg-accent/5')}>
                <th scope="row" className={cn(CELDA, 'text-left font-semibold text-primary', activo && 'shadow-[inset_3px_0_0_var(--accent)]')}>
                  {fila.nombre}
                  {activo && <span className="ml-2"><EnLaHoja /></span>}
                </th>
                {CIFRAS.map((c) => <td key={c.clave} className={cn(CELDA, 'text-right')}>{cifra(fila, c)}</td>)}
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

/** Una cifra del panel: botón si hay algo detrás (azul de acción; rojo si es de hoy); si no, un número quieto. */
function Cifra({ valor, contexto, pista, urgente, onAbrir }: { valor: number; contexto: string; pista: string; urgente: boolean; onAbrir: (() => void) | undefined }): ReactNode {
  if (!onAbrir) return <span className="tabular-nums text-[var(--muted-foreground-strong)]">{valor}</span>
  return (
    <button
      type="button"
      onClick={onAbrir}
      className={cn(
        'inline-flex min-h-8 min-w-10 cursor-pointer items-center justify-center rounded-md px-2 font-bold tabular-nums underline decoration-dotted underline-offset-4 transition-colors hover:decoration-solid pointer-coarse:min-h-11 pointer-coarse:min-w-11',
        urgente ? 'text-[var(--destructive-text)] hover:bg-destructive/10' : 'text-[var(--accent-press)] hover:bg-accent/10',
        FOCO,
      )}
    >
      <span className="sr-only">{contexto}: </span>
      {valor}
      <span className="sr-only">, {pista}</span>
    </button>
  )
}

/** El analista por el que se está filtrando la hoja: dicho con texto, no solo con color. */
function EnLaHoja() {
  return <span className="rounded-full bg-accent/10 px-2 py-0.5 text-[11px] font-bold text-[var(--accent-press)]">En la hoja</span>
}
