import type { JSX } from 'react'
import { ArrowRight, Settings2 } from 'lucide-react'
import { money, numero } from '@/lib/format'
import {
  capitalObjetivo,
  contratosObjetivo,
  type CategoriaMeta,
  type ObjetivosPorRol,
} from '@/lib/objetivos'

const CATEGORIAS: Array<{ clave: CategoriaMeta; label: string }> = [
  { clave: 'nuevo', label: 'Nuevo' },
  { clave: 'renovacion', label: 'Renovación' },
  { clave: 'upgrade', label: 'Upgrade' },
]

/**
 * Resumen de solo lectura. La única vía de edición vive en Configuración →
 * Metas, donde se publica una revisión completa con control de concurrencia.
 */
export function MetasEditor({
  objetivos,
  demo,
}: {
  objetivos: ObjetivosPorRol
  demo: boolean
}): JSX.Element {
  const meta = objetivos.gerencia
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold text-primary">Metas publicadas · solo lectura</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Revisión {objetivos.revision}{demo ? ' · datos de ejemplo' : ''}. La edición está centralizada para evitar dos versiones del mismo mes.
          </p>
        </div>
        <a
          href="#/config-metas"
          className="inline-flex h-8 items-center justify-center gap-2 rounded-md bg-primary px-3 text-xs font-semibold text-primary-foreground transition-colors hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          <Settings2 className="size-4" aria-hidden /> Administrar metas <ArrowRight className="size-4" aria-hidden />
        </a>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <div className="rounded-xl border bg-background px-4 py-3">
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Capital PEN</p>
          <p className="mt-1 text-lg font-bold tabular-nums">{money(capitalObjetivo(meta, 'PEN'), 'PEN')}</p>
        </div>
        <div className="rounded-xl border bg-background px-4 py-3">
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Capital USD</p>
          <p className="mt-1 text-lg font-bold tabular-nums">{money(capitalObjetivo(meta, 'USD'), 'USD')}</p>
        </div>
        <div className="rounded-xl border bg-background px-4 py-3">
          <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">Conversión</p>
          <p className="mt-1 text-lg font-bold tabular-nums">{meta.conversionObjetivo > 0 ? `${numero(meta.conversionObjetivo, 2)}%` : 'Sin meta'}</p>
        </div>
      </div>

      <div className="overflow-x-auto rounded-xl border bg-background">
        <table className="w-full min-w-[620px] text-left text-xs" aria-label="Metas publicadas por categoría y moneda">
          <thead className="bg-muted/45 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
            <tr>
              <th className="px-4 py-2.5" scope="col">Categoría</th>
              <th className="px-4 py-2.5 text-right" scope="col">Capital PEN</th>
              <th className="px-4 py-2.5 text-right" scope="col">Contratos PEN</th>
              <th className="px-4 py-2.5 text-right" scope="col">Capital USD</th>
              <th className="px-4 py-2.5 text-right" scope="col">Contratos USD</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {CATEGORIAS.map(({ clave, label }) => (
              <tr key={clave}>
                <th className="px-4 py-3 font-semibold" scope="row">{label}</th>
                <td className="px-4 py-3 text-right tabular-nums">{money(capitalObjetivo(meta, 'PEN', clave), 'PEN')}</td>
                <td className="px-4 py-3 text-right tabular-nums">{numero(contratosObjetivo(meta, 'PEN', clave))}</td>
                <td className="px-4 py-3 text-right tabular-nums">{money(capitalObjetivo(meta, 'USD', clave), 'USD')}</td>
                <td className="px-4 py-3 text-right tabular-nums">{numero(contratosObjetivo(meta, 'USD', clave))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
