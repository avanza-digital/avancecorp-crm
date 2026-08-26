import type { JSX } from 'react'
import { ArrowRight, Settings2 } from 'lucide-react'
import { money } from '@/lib/format'
import { capitalObjetivo, type ObjetivosPorRol } from '@/lib/objetivos'

/**
 * Resumen de solo lectura. La única vía de edición vive en Configuración →
 * Metas, donde se publica una revisión completa con control de concurrencia.
 */
export function MetasEditor({ objetivos, demo }: { objetivos: ObjetivosPorRol; demo: boolean }): JSX.Element {
  const meta = objetivos.gerencia
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold text-primary">Metas publicadas · solo lectura</p>
          <p className="mt-1 text-xs text-muted-foreground">
            Revisión {objetivos.revision}
            {demo ? ' · datos de ejemplo' : ''}. La edición está centralizada para evitar dos versiones del mismo mes.
          </p>
        </div>
        <a
          href="#/config-metas"
          className="inline-flex h-8 items-center justify-center gap-2 rounded-md bg-primary px-3 text-xs font-semibold text-primary-foreground transition-colors hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
        >
          <Settings2 className="size-4" aria-hidden /> Administrar metas <ArrowRight className="size-4" aria-hidden />
        </a>
      </div>

      <div className="rounded-xl border border-accent/25 bg-accent/[0.06] px-5 py-4">
        <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
          Meta mensual total del equipo
        </p>
        <p className="mt-1 text-2xl font-extrabold tabular-nums text-primary">
          {money(capitalObjetivo(meta, 'PEN'), 'PEN')}
        </p>
        <p className="mt-2 text-xs text-muted-foreground">
          Una sola meta en soles. No se divide por nueva inversión, renovación, aumento de inversión, cantidad de
          contratos ni conversión.
        </p>
      </div>
    </div>
  )
}
