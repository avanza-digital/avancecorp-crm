// Hoy · GERENCIA — tablero ejecutivo de toda la operación comercial.
// PEN y USD jamás se suman. La conversión de leads se muestra únicamente
// sobre cierres resueltos de la cohorte: convertidos / (convertidos + descartados).
import { lazy, Suspense, useMemo, useState, type JSX } from 'react'
import { Filter, Inbox, Target, TrendingUp, Trophy, Users } from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { Skeleton } from '@/components/ui/skeleton'
import { useCRMData } from '@/lib/store-context'
import { useAuth } from '@/lib/auth-context'
import { money, moneyK } from '@/lib/format'
import { ETAPA_INFO } from '@/lib/tipos'
import { SEMAFORO } from '@/lib/semaforo'
import { capitalPorMoneda, colorMeta, embudo, esAbierto } from '@/lib/inteligencia'
import {
  useActualizarCapacidadLeadsObjetivo,
  useMetricasDistribucionLeads,
} from '@/data/crm-queries'
import { mensajeDeError } from '@/data/crm-api'
import { DistribucionLeadsGerencia } from './distribucion-leads-gerencia'

// Recharts baja solo al entrar en Gerencia; el gate de rol vive en hoy.tsx.
const GraficasGerencia = lazy(() =>
  import('./graficas-gerencia').then((modulo) => ({ default: modulo.GraficasGerencia })),
)

interface PeriodoDistribucion {
  desde: string
  hasta: string
}

function fechaIso(fecha: Date): string {
  return `${fecha.getUTCFullYear()}-${String(fecha.getUTCMonth() + 1).padStart(2, '0')}-${String(fecha.getUTCDate()).padStart(2, '0')}`
}

/** Últimos 90 días calendario inclusivos según America/Lima. */
function periodoInicialDistribucion(): PeriodoDistribucion {
  const hoyLima = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Lima',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  const [anio, mes, dia] = hoyLima.split('-').map(Number)
  const hasta = new Date(Date.UTC(anio ?? 1970, (mes ?? 1) - 1, dia ?? 1))
  const desde = new Date(hasta)
  desde.setUTCDate(desde.getUTCDate() - 89)
  return { desde: fechaIso(desde), hasta: fechaIso(hasta) }
}

/** Ítem de meta: valor actual, objetivo explícito y barra semaforizada. */
function MetaItem({
  label,
  actual,
  objetivo,
  pct,
}: {
  label: string
  actual: string
  objetivo: string
  pct: number
}): JSX.Element {
  const progreso = Math.max(0, Math.min(100, Math.round(pct)))
  return (
    <div>
      <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-1 flex items-baseline gap-2">
        <span className="text-xl font-extrabold tracking-tight tabular-nums text-primary">{actual}</span>
        <span className="text-xs text-muted-foreground">{objetivo}</span>
      </div>
      <div className="mt-2 flex items-center gap-2">
        <Progress value={progreso} color={colorMeta(progreso)} className="flex-1" />
        <span
          className="w-9 text-right text-[11px] font-bold tabular-nums"
          style={{ color: colorMeta(progreso) }}
        >
          {progreso}%
        </span>
      </div>
    </div>
  )
}

export function HoyGerencia(): JSX.Element {
  const { ambito, objetivos } = useCRMData()
  const { yo } = useAuth()
  const [periodo, setPeriodo] = useState<PeriodoDistribucion>(periodoInicialDistribucion)
  const sesionReal = Boolean(yo && !yo.demo)
  const modoDemo = yo?.demo === true
  const consultaDistribucion = useMetricasDistribucionLeads(
    sesionReal,
    periodo.desde,
    periodo.hasta,
  )
  const actualizarCapacidad = useActualizarCapacidadLeadsObjetivo()
  const leads = ambito.leads
  const meta = objetivos.gerencia

  const datosLocales = useMemo(() => {
    const vivos = leads.filter((lead) => lead.activo)
    const abiertos = vivos.filter(esAbierto)
    const asignados = abiertos.filter((lead) => lead.vendedor_id != null)
    const convertidos = vivos.filter((lead) => lead.etapa === 'convertido')
    const capital = capitalPorMoneda(asignados)
    const ganado = capitalPorMoneda(convertidos)
    return {
      abiertos: abiertos.length,
      activos: asignados.length,
      porRepartir: abiertos.filter((lead) => lead.vendedor_id == null).length,
      capitalPen: capital.pen,
      capitalUsd: capital.usd,
      convertidos: convertidos.length,
      ganadoPen: ganado.pen,
      ganadoUsd: ganado.usd,
    }
  }, [leads])

  const etapas = useMemo(() => embudo(leads), [leads])
  const porRepartir =
    consultaDistribucion.data?.resumen.por_repartir_actuales ?? datosLocales.porRepartir
  const errorDistribucion =
    sesionReal && consultaDistribucion.error
      ? mensajeDeError(
          consultaDistribucion.error,
          'No pudimos consultar la distribución. Revisa tu conexión e inténtalo otra vez.',
        )
      : null

  const guardarCapacidad = async (analistaId: string, capacidad: number | null) => {
    await actualizarCapacidad.mutateAsync({ analistaId, capacidad })
  }

  return (
    <div className="mx-auto max-w-[1600px] space-y-5 ac-rise">
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={money(datosLocales.capitalPen)}
          icon={TrendingUp}
          color="var(--accent)"
          sub={
            datosLocales.capitalUsd > 0
              ? `Pipeline activo (PEN) · +${moneyK(datosLocales.capitalUsd, 'USD')}`
              : 'Pipeline activo (PEN)'
          }
          delay={0}
        />
        <KpiCard
          label="Leads activos"
          value={String(datosLocales.activos)}
          icon={Users}
          color="var(--chart-2)"
          sub="Cartera abierta con analista asignado"
          delay={60}
        />
        <KpiCard
          label="Por repartir"
          value={String(porRepartir)}
          icon={Inbox}
          color={porRepartir > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={porRepartir > 0 ? 'Cola global + bandejas de supervisión' : 'Las colas están al día'}
          delay={120}
        />
        <KpiCard
          label="Capital ganado"
          value={money(datosLocales.ganadoPen)}
          icon={Trophy}
          color={SEMAFORO.navy}
          sub={
            datosLocales.ganadoUsd > 0
              ? `Histórico convertido (PEN) · +${moneyK(datosLocales.ganadoUsd, 'USD')}`
              : 'Histórico convertido (PEN)'
          }
          delay={180}
        />
      </div>

      <DistribucionLeadsGerencia
        datos={sesionReal ? consultaDistribucion.data : null}
        cargando={sesionReal && (consultaDistribucion.isPending || consultaDistribucion.isFetching)}
        error={errorDistribucion}
        modoDemo={modoDemo}
        desde={periodo.desde}
        hasta={periodo.hasta}
        onCambiarPeriodo={(desde, hasta) => setPeriodo({ desde, hasta })}
        onReintentar={() => {
          if (sesionReal) void consultaDistribucion.refetch()
        }}
        onEditarCapacidad={guardarCapacidad}
      />

      <Card>
        <SectionHead
          icon={Target}
          title="Meta del mes — Empresa"
          right={<span className="text-xs text-muted-foreground">Objetivos de gerencia</span>}
        />
        <CardContent className="grid gap-5 pt-1 sm:grid-cols-2">
          <MetaItem
            label="Capital en proceso"
            actual={money(datosLocales.capitalPen)}
            objetivo={
              meta.capitalObjetivo > 0
                ? `de ${moneyK(meta.capitalObjetivo)} (PEN)`
                : 'meta por definir'
            }
            pct={
              meta.capitalObjetivo > 0
                ? (datosLocales.capitalPen / meta.capitalObjetivo) * 100
                : 0
            }
          />
          <MetaItem
            label="Ventas cerradas"
            actual={String(datosLocales.convertidos)}
            objetivo={
              meta.ventasObjetivo > 0
                ? `de ${meta.ventasObjetivo} conversiones`
                : 'meta por definir'
            }
            pct={
              meta.ventasObjetivo > 0
                ? (datosLocales.convertidos / meta.ventasObjetivo) * 100
                : 0
            }
          />
        </CardContent>
      </Card>

      {/* Gráficas del negocio de contratos. No mezclan PEN y USD. */}
      <Suspense fallback={<Skeleton className="h-[240px] w-full" aria-busy />}>
        <GraficasGerencia />
      </Suspense>

      <Card>
        <SectionHead
          icon={Filter}
          title="Composición del pipeline"
          right={
            <span className="text-xs tabular-nums text-muted-foreground">
              {datosLocales.abiertos} abiertos
            </span>
          }
        />
        <CardContent className="space-y-3.5 pt-1">
          {(() => {
            const maximo = Math.max(...etapas.map((etapa) => etapa.n), 1)
            return etapas.map((etapa) => {
              const info = ETAPA_INFO[etapa.etapa]
              return (
                <div key={etapa.etapa}>
                  <div className="mb-1 flex items-baseline justify-between gap-2 text-xs">
                    <span className="flex items-center gap-2 font-semibold">
                      <span
                        className="size-2 shrink-0 rounded-full"
                        style={{ background: info.color }}
                      />
                      {info.label}
                    </span>
                    <span className="tabular-nums text-muted-foreground">
                      <span className="font-extrabold text-foreground">{etapa.n}</span>{' '}
                      {etapa.n === 1 ? 'lead' : 'leads'} · {etapa.pctDelTotal}%
                    </span>
                  </div>
                  <div className="h-3 overflow-hidden rounded-full bg-muted">
                    <div
                      className="h-full rounded-full transition-[width] duration-700 ease-out"
                      style={{
                        width: `${etapa.n > 0 ? Math.max((etapa.n / maximo) * 100, 6) : 0}%`,
                        background: info.color,
                      }}
                    />
                  </div>
                </div>
              )
            })
          })()}
          <p className="text-[11px] text-muted-foreground">
            Distribución actual sobre {datosLocales.abiertos} leads abiertos; no representa una tasa de
            conversión entre etapas.
          </p>
        </CardContent>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        {modoDemo
          ? 'Tablero de demostración: el historial de asignaciones, conversión y SLA no se simula.'
          : 'Los números abarcan toda la operación comercial de la empresa.'}
      </p>
    </div>
  )
}
