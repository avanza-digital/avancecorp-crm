import type { JSX } from 'react'
import type { ModoPeriodoDerivaciones } from '@/lib/use-periodo-derivaciones'
import { Button } from '@/components/ui/button'

export function ControlesPeriodoDerivaciones({
  modo,
  desde,
  hasta,
  hoy,
  rangoInvalido,
  titulo = 'Período para comparar la carga',
  descripcion = 'Todas las tarjetas responden al mismo filtro.',
  onModo,
  onDesde,
  onHasta,
}: {
  modo: ModoPeriodoDerivaciones
  desde: string
  hasta: string
  hoy: string
  rangoInvalido: boolean
  titulo?: string
  descripcion?: string
  onModo: (modo: ModoPeriodoDerivaciones) => void
  onDesde: (fecha: string) => void
  onHasta: (fecha: string) => void
}): JSX.Element {
  return (
    <div className="border-y border-border/70 bg-muted/20 px-5 py-3">
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2.5">
        <div className="mr-auto min-w-[190px]">
          <p className="text-xs font-semibold">{titulo}</p>
          <p className="text-[11px] text-muted-foreground">{descripcion}</p>
        </div>
        <div
          className="flex items-center gap-1"
          role="group"
          aria-label="Período del reporte de derivaciones"
        >
          <Button
            type="button"
            size="xs"
            variant={modo === 'ayer' ? 'accent' : 'outline'}
            onClick={() => onModo('ayer')}
          >
            Ayer
          </Button>
          <Button
            type="button"
            size="xs"
            variant={modo === 'semana' ? 'accent' : 'outline'}
            onClick={() => onModo('semana')}
          >
            Últimos 7 días
          </Button>
          <Button
            type="button"
            size="xs"
            variant={modo === 'rango' ? 'accent' : 'outline'}
            onClick={() => onModo('rango')}
          >
            Rango
          </Button>
        </div>
        {modo === 'rango' && (
          <div className="flex flex-wrap items-end gap-2">
            <label className="grid gap-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
              Desde
              <input
                type="date"
                value={desde}
                max={hoy}
                aria-label="Fecha inicial del reporte de derivaciones"
                onChange={(event) => onDesde(event.target.value)}
                className="h-8 rounded-lg border border-input bg-background px-2 text-xs font-medium text-foreground shadow-sm outline-none transition focus-visible:ring-[3px] focus-visible:ring-ring/30"
              />
            </label>
            <label className="grid gap-1 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
              Hasta
              <input
                type="date"
                value={hasta}
                max={hoy}
                aria-label="Fecha final del reporte de derivaciones"
                onChange={(event) => onHasta(event.target.value)}
                className="h-8 rounded-lg border border-input bg-background px-2 text-xs font-medium text-foreground shadow-sm outline-none transition focus-visible:ring-[3px] focus-visible:ring-ring/30"
              />
            </label>
          </div>
        )}
      </div>
      {rangoInvalido && (
        <p role="status" className="mt-2 text-xs font-medium text-destructive">
          Elige un rango válido, de hasta 366 días, que termine hoy o antes.
        </p>
      )}
    </div>
  )
}
