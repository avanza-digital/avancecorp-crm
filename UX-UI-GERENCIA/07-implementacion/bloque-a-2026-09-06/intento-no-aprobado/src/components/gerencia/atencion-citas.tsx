import type { MetricasReuniones } from '@/lib/metricas-reuniones'
import { numero } from '@/lib/format'
import { Button } from '@/components/ui/button'
import { CircleAlert } from 'lucide-react'

export function AtencionCitas({ datos, cargando, error, onVerResponsables }: {
  datos: MetricasReuniones | null | undefined
  cargando: boolean
  error: string | null
  onVerResponsables?: (() => void) | undefined
}) {
  const disponible = datos != null && !cargando && !error
  const pendientes = disponible ? datos.resumen.pendientes_cierre : null
  const responsables = disponible ? datos.responsables.filter((fila) => fila.pendientes_cierre > 0) : []
  return (
    <section aria-label="Citas que requieren revisión" className={pendientes != null && pendientes > 0 ? 'gi-attention' : 'space-y-3 rounded-2xl border border-[var(--gi-line)] bg-white p-4'}>
      {pendientes != null && pendientes > 0 && <CircleAlert className="size-7 text-amber-600" aria-hidden />}
      <div><h2 className="text-sm font-semibold leading-5">
        {pendientes == null ? 'Revisión de citas no disponible'
          : pendientes > 0 ? `${numero(pendientes)} citas vencidas sin resultado`
          : 'Sin citas vencidas sin resultado'}
      </h2>
      <p className="text-sm leading-5 text-[var(--muted-foreground-strong)]">
        {pendientes == null ? 'No podemos afirmar que no haya pendientes hasta completar esta consulta.'
          : pendientes === 0 ? 'La señal de citas no muestra pendientes en el período. No evalúa los asuntos de otras áreas.'
          : `${responsables.length > 0 ? responsables.map((fila) => `${fila.nombre}: ${numero(fila.pendientes_cierre)}`).join(' · ') + '. ' : ''}Fecha prevista dentro del rango consultado.`}
      </p></div>
      {pendientes != null && pendientes > 0 && (onVerResponsables
        ? <Button variant="outline" className="h-11 min-w-45 rounded-[var(--gi-radius-8)]" onClick={onVerResponsables}>Ver responsables</Button>
        : <a href="#/reuniones" className="inline-flex min-h-11 min-w-45 items-center justify-center rounded-[var(--gi-radius-8)] border border-[var(--gi-line)] px-3 text-sm font-semibold text-[var(--gi-navy)] hover:bg-[var(--gi-soft)] focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-accent/40">Revisar Citas</a>)}
    </section>
  )
}
