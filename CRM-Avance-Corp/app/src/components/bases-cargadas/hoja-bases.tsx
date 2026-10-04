// La HOJA de bases (F5, `crm.seguimiento_bases`): una fila por base con su avance. Forma de la casa (Miguel): hoja de
// cálculo con # de fila, encabezado y primeras columnas fijos, un dato por celda; en el celular, tarjetas. Todo número
// se abre (el detalle de esa cifra en una hoja lateral); el nombre abre la base (reparto y seguimiento).
import type { Ref } from 'react'
import { FOCO } from '@/components/gestion-diaria/estilos-gestion'
import { CELDA, ENCABEZADO } from '@/components/base-gestion/hoja-base'
import { cn } from '@/lib/utils'
import { fmtFecha } from '@/lib/format'
import { etiquetaAvance, etiquetaOrigenBase, ROTULO_CIFRA, type CifraBase, type FilaSeguimientoBases } from '@/lib/bases-cargadas'
import { NumeroAbrible } from './piezas-bases'

/** Las cifras de la hoja, en su orden (las que se abren). */
const CIFRAS_HOJA: readonly CifraBase[] = ['total', 'sin_repartir', 'repartidos', 'sin_tocar', 'trabajados', 'citas']

/** La barra del avance: el número dice el porcentaje; la barra solo lo acompaña (no se lee dos veces). */
export function Avance({ avance }: { avance: number | null }) {
  const pct = avance === null ? 0 : Math.round(Math.min(1, Math.max(0, avance)) * 100)
  return (
    <span className="inline-flex items-center gap-2">
      <span aria-hidden className="h-1.5 w-10 overflow-hidden rounded-full bg-muted">
        <span className="block h-full rounded-full bg-accent" style={{ width: `${pct}%` }} />
      </span>
      <span className="tabular-nums">{etiquetaAvance(avance)}</span>
    </span>
  )
}

export function HojaBases({ filas, esMovil, onAbrirBase, onAbrirCifra, regionRef }: {
  filas: readonly FilaSeguimientoBases[]
  esMovil: boolean
  onAbrirBase: (baseId: string) => void
  onAbrirCifra: (fila: FilaSeguimientoBases, cifra: CifraBase) => void
  regionRef?: Ref<HTMLDivElement> | undefined
}) {
  const cifra = (f: FilaSeguimientoBases, c: CifraBase) => (
    <NumeroAbrible valor={f[c]} contexto={`${f.nombre}, ${ROTULO_CIFRA[c].toLowerCase()}`} onAbrir={() => onAbrirCifra(f, c)} />
  )
  const nombre = (f: FilaSeguimientoBases, clase?: string) => (
    <button
      type="button"
      onClick={() => onAbrirBase(f.base_id)}
      data-foco-clave={`base-carga-${f.base_id}`}
      className={cn('max-w-full cursor-pointer truncate rounded text-left font-semibold underline decoration-[var(--border-strong)] decoration-dotted underline-offset-4 hover:decoration-solid', FOCO, clase)}
    >
      {f.nombre}
    </button>
  )

  if (esMovil) {
    return (
      <div ref={regionRef} tabIndex={-1} role="list" aria-label="Bases cargadas" className={cn('space-y-3 rounded-lg', FOCO)}>
        {filas.map((f) => (
          <div role="listitem" key={f.base_id} className="rounded-xl border border-border bg-card p-4">
            <p className="text-base">{nombre(f, 'pointer-coarse:inline-flex pointer-coarse:min-h-11 pointer-coarse:items-center')}</p>
            <p className="text-sm text-[var(--muted-foreground-strong)]">
              {etiquetaOrigenBase(f.origen)} · {f.supervisor_nombre ?? 'Sin supervisor'} · {fmtFecha(f.creado_en)}
            </p>
            <dl className="mt-3 grid grid-cols-3 gap-x-3 gap-y-2">
              {CIFRAS_HOJA.map((c) => (
                <div key={c}>
                  <dt className="text-[11px] font-bold uppercase tracking-wide text-[var(--muted-foreground-strong)]">{ROTULO_CIFRA[c]}</dt>
                  <dd className="text-base">{cifra(f, c)}</dd>
                </div>
              ))}
            </dl>
            <p className="mt-3 text-sm"><span className="mr-2 text-[13px] font-semibold text-[var(--muted-foreground-strong)]">Avance</span><Avance avance={f.avance} /></p>
          </div>
        ))}
      </div>
    )
  }

  return (
    // oxlint-disable-next-line jsx-a11y/no-noninteractive-tabindex -- La hoja se desplaza con el teclado en los dos ejes.
    <div ref={regionRef} tabIndex={0} role="region" aria-label="Bases cargadas" className={cn('ac-scroll max-h-[calc(100dvh-16rem)] scroll-pl-[15rem] scroll-pt-14 overflow-auto rounded-lg border border-[var(--border-strong)] bg-card', FOCO)}>
      <table className="min-w-full border-separate border-spacing-0">
        <caption className="sr-only">Bases cargadas con su avance: cada número abre su lista y el nombre abre la base para repartirla y seguirla.</caption>
        <thead>
          <tr>
            <th scope="col" className={cn(ENCABEZADO, 'sticky left-0 z-20 w-12 min-w-12 text-center')}>#</th>
            <th scope="col" className={cn(ENCABEZADO, 'sticky left-12 z-20 w-48 min-w-48')}>Base</th>
            <th scope="col" className={ENCABEZADO}>Origen</th>
            <th scope="col" className={ENCABEZADO}>Supervisor</th>
            <th scope="col" className={ENCABEZADO}>Creada</th>
            {/* Rótulos de las cifras en dos líneas si hace falta: la hoja entera cabe a 1440 px sin desplazar. */}
            {CIFRAS_HOJA.map((c) => <th key={c} scope="col" className={cn(ENCABEZADO, 'min-w-14 whitespace-normal px-2 text-right leading-tight')}>{ROTULO_CIFRA[c]}</th>)}
            <th scope="col" className={cn(ENCABEZADO, 'border-r-0')}>Avance</th>
          </tr>
        </thead>
        <tbody>
          {filas.map((f, i) => (
            <tr key={f.base_id} className="group hover:bg-accent/5">
              <td className={cn(CELDA, 'sticky left-0 z-[1] w-12 min-w-12 bg-muted text-center text-[13px] tabular-nums text-[var(--muted-foreground-strong)]')}>{i + 1}</td>
              <th scope="row" className={cn(CELDA, 'sticky left-12 z-[1] w-48 min-w-48 max-w-48 bg-card text-[15px] group-hover:bg-[color-mix(in_srgb,var(--accent)_5%,var(--card))]')} title={f.nombre}>
                {nombre(f)}
              </th>
              <td className={CELDA}>{etiquetaOrigenBase(f.origen)}</td>
              <td className={cn(CELDA, 'max-w-40 truncate')} title={f.supervisor_nombre ?? undefined}>{f.supervisor_nombre ?? '—'}</td>
              <td className={cn(CELDA, 'tabular-nums')}>{fmtFecha(f.creado_en)}</td>
              {CIFRAS_HOJA.map((c) => <td key={c} className={cn(CELDA, 'px-1 text-right')}>{cifra(f, c)}</td>)}
              <td className={cn(CELDA, 'border-r-0')}><Avance avance={f.avance} /></td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
