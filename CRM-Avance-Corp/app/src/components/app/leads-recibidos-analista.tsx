import { useMemo, useState, type JSX } from 'react'
import { CalendarRange } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { SectionHead } from '@/components/common/section-head'
import { ControlesPeriodoDerivaciones } from '@/components/common/controles-periodo-derivaciones'
import { AvisoDegradacion } from '@/components/common/aviso-degradacion'
import { usePeriodoDerivaciones } from '@/lib/use-periodo-derivaciones'
import {
  leadsRecibidosAnalistaDesdeAmbito,
  type LeadsRecibidosAnalista,
} from '@/lib/leads-recibidos-analista'
import type { Lead } from '@/lib/tipos'
import { useLeadsRecibidosAnalista } from '@/data/use-leads-recibidos-analista'

const FORMATO_DIA = new Intl.DateTimeFormat('es-PE', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  timeZone: 'America/Lima',
})

function etiquetaDia(fecha: string): string {
  return FORMATO_DIA.format(new Date(`${fecha}T12:00:00-05:00`))
}

export function LeadsRecibidosAnalistaCard({
  analistaId,
  demo,
  leads,
}: {
  analistaId: string
  demo: boolean
  leads: readonly Lead[]
}): JSX.Element {
  const [ahora] = useState(() => Date.now())
  const {
    modo,
    setModo,
    desdeRango,
    setDesdeRango,
    hastaRango,
    setHastaRango,
    periodo,
    rangoValido,
    hoy,
  } = usePeriodoDerivaciones(ahora, 'hoy')
  const consulta = useLeadsRecibidosAnalista(
    !demo && rangoValido,
    periodo.desde,
    periodo.hasta,
  )
  const espejoDemo = useMemo(
    () => demo && rangoValido
      ? leadsRecibidosAnalistaDesdeAmbito(
          leads,
          analistaId,
          periodo.desde,
          periodo.hasta,
          ahora,
        )
      : null,
    [ahora, analistaId, demo, leads, periodo.desde, periodo.hasta, rangoValido],
  )
  const reporte: LeadsRecibidosAnalista | null = demo
    ? espejoDemo
    : consulta.data ?? null
  const diasDescendentes = useMemo(
    () => reporte ? [...reporte.dias].reverse() : [],
    [reporte],
  )

  return (
    <Card role="region" className="overflow-hidden" aria-label="Leads recibidos por período">
      <SectionHead
        icon={CalendarRange}
        title="Leads recibidos"
        right={reporte ? (
          <span className="text-xs font-semibold tabular-nums text-primary" aria-live="polite">
            {reporte.total} en el período
          </span>
        ) : undefined}
      />
      <ControlesPeriodoDerivaciones
        modo={modo}
        desde={desdeRango}
        hasta={hastaRango}
        hoy={hoy}
        rangoInvalido={!rangoValido}
        titulo="¿Cuántos leads recibiste?"
        descripcion="Elige un día o un rango; el detalle se muestra por fecha de asignación."
        mostrarHoy
        ariaLabel="Período de leads recibidos"
        ariaLabelDesde="Fecha inicial de leads recibidos"
        ariaLabelHasta="Fecha final de leads recibidos"
        onModo={setModo}
        onDesde={setDesdeRango}
        onHasta={setHastaRango}
      />
      <CardContent className="pt-4">
        <AvisoDegradacion
          activo={Boolean(consulta.error) && !demo}
          queReintenta="del conteo de leads recibidos"
          onReintentar={() => { void consulta.refetch() }}
        >
          No se pudo cargar el conteo. Tu cartera actual sigue disponible debajo.
        </AvisoDegradacion>

        {rangoValido && consulta.isPending && !demo && (
          <p role="status" className="py-6 text-center text-sm text-muted-foreground">
            Calculando los leads recibidos…
          </p>
        )}

        {reporte && (
          <div className="grid gap-4 md:grid-cols-[minmax(180px,0.6fr)_minmax(260px,1.4fr)]">
            <div className="rounded-xl border border-primary/15 bg-primary/[0.04] p-4">
              <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                Total del período
              </p>
              <p className="mt-1 text-3xl font-extrabold tabular-nums text-primary">
                {reporte.total}
              </p>
              <p className="mt-1 text-xs text-muted-foreground">
                {reporte.total === 1 ? 'lead asignado a ti' : 'leads asignados a ti'}
              </p>
              <p className="mt-3 text-[11px] leading-relaxed text-muted-foreground">
                Este rango actualiza solo el conteo histórico. El listado inferior conserva tu cartera actual.
              </p>
            </div>

            <div>
              <p className="mb-2 text-xs font-semibold">Detalle por día</p>
              <ul
                aria-label="Cantidad de leads recibidos por día"
                className="max-h-56 space-y-1 overflow-y-auto rounded-xl border border-border p-2"
              >
                {diasDescendentes.map((dia) => (
                  <li
                    key={dia.fecha}
                    className="flex min-h-9 items-center justify-between gap-3 rounded-lg px-3 py-1.5 odd:bg-muted/35"
                  >
                    <time dateTime={dia.fecha} className="text-xs font-medium capitalize text-muted-foreground">
                      {etiquetaDia(dia.fecha)}
                    </time>
                    <span className="text-sm font-extrabold tabular-nums">
                      {dia.total} {dia.total === 1 ? 'lead' : 'leads'}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        )}

        {reporte && reporte.aproximados > 0 && (
          <p className="mt-3 text-[11px] text-muted-foreground">
            {reporte.aproximados} {reporte.aproximados === 1 ? 'registro histórico usa' : 'registros históricos usan'} una fecha reconstruida.
          </p>
        )}

        <p className="mt-3 text-[11px] text-muted-foreground">
          Cuenta cada entrada a tu cartera en la fecha en que fue asignada. Una devolución inmediata a la misma bandeja no suma.
        </p>
      </CardContent>
    </Card>
  )
}
