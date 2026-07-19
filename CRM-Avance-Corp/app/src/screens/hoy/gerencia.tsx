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
import { metricasDistribucionDemo } from '@/lib/demo-metricas-distribucion'
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
  const [monedaMontos, setMonedaMontos] = useState<'PEN' | 'USD'>('PEN')
  const [mostrarEjemploDistribucion, setMostrarEjemploDistribucion] = useState(false)
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
  const cargandoDistribucion =
    sesionReal && (consultaDistribucion.isPending || consultaDistribucion.isFetching)
  const distribucionRealVacia =
    consultaDistribucion.data == null || consultaDistribucion.data.analistas.length === 0
  const puedeMostrarEjemplo =
    sesionReal && !cargandoDistribucion && distribucionRealVacia
  const mostrandoEjemplo =
    modoDemo || (puedeMostrarEjemplo && mostrarEjemploDistribucion)
  const datosDistribucion = mostrandoEjemplo
    ? metricasDistribucionDemo(periodo.desde, periodo.hasta)
    : consultaDistribucion.data

  const guardarCapacidad = async (analistaId: string, capacidad: number | null) => {
    await actualizarCapacidad.mutateAsync({ analistaId, capacidad })
  }

  return (
    <div className="gerencia-legible mx-auto max-w-[1600px] space-y-7 ac-rise">
      <section className="overflow-hidden rounded-3xl border border-border/80 bg-gradient-to-br from-card via-card to-accent/[0.06] p-4 shadow-[0_18px_45px_-34px_rgba(15,31,61,0.7)] sm:p-5">
        <div className="mb-4 flex flex-wrap items-end justify-between gap-4">
          <div className="max-w-xl">
            <p className="text-[11px] font-extrabold uppercase tracking-[0.18em] text-accent">
              Resumen general
            </p>
            <h2 className="mt-1 text-xl font-extrabold tracking-tight text-primary sm:text-2xl">
              Así está la operación hoy
            </h2>
            <p className="mt-1 text-sm leading-relaxed text-muted-foreground">
              Revisa los montos, los leads activos y lo que todavía falta asignar.
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2 rounded-full border border-border bg-background/85 p-1 shadow-sm">
            <span className="pl-2 text-xs font-semibold text-muted-foreground">Ver montos en</span>
            <div role="group" aria-label="Moneda de los montos" className="flex gap-1">
          {(['PEN', 'USD'] as const).map((moneda) => {
            const seleccionada = monedaMontos === moneda
            return (
              <button
                key={moneda}
                type="button"
                onClick={() => setMonedaMontos(moneda)}
                aria-pressed={seleccionada}
                className={`rounded-full border px-3 py-1.5 text-[11px] font-bold transition-colors ${
                  seleccionada
                    ? 'border-transparent bg-primary text-primary-foreground'
                    : 'border-border text-muted-foreground hover:bg-muted/60'
                }`}
              >
                {moneda === 'PEN' ? 'Soles' : 'Dólares'}
              </button>
            )
          })}
            </div>
          </div>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Monto de leads activos"
          value={money(
            monedaMontos === 'PEN' ? datosLocales.capitalPen : datosLocales.capitalUsd,
            monedaMontos,
          )}
          icon={TrendingUp}
          color="var(--accent)"
          sub={`Leads activos en ${monedaMontos === 'PEN' ? 'soles' : 'dólares'}`}
          delay={0}
        />
        <KpiCard
          label="Leads activos"
          value={String(datosLocales.activos)}
          icon={Users}
          color="var(--chart-2)"
          sub="Leads abiertos con analista"
          delay={60}
        />
        <KpiCard
          label="Por repartir"
          value={String(porRepartir)}
          icon={Inbox}
          color={porRepartir > 0 ? SEMAFORO.atencion : SEMAFORO.ok}
          sub={porRepartir > 0 ? 'Gerencia y supervisores' : 'Todo asignado'}
          delay={120}
        />
        <KpiCard
          label="Monto de ventas cerradas"
          value={money(
            monedaMontos === 'PEN' ? datosLocales.ganadoPen : datosLocales.ganadoUsd,
            monedaMontos,
          )}
          icon={Trophy}
          color={SEMAFORO.navy}
          sub={`Capital de ventas cerradas en ${monedaMontos === 'PEN' ? 'soles' : 'dólares'}`}
          delay={180}
        />
        </div>
      </section>

      {puedeMostrarEjemplo && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-2xl border border-accent/35 bg-accent/[0.07] px-4 py-3 shadow-sm">
          <div>
            <p className="text-sm font-extrabold text-primary">
              {mostrarEjemploDistribucion
                ? 'Estás viendo un ejemplo con datos ficticios'
                : 'La distribución todavía no tiene información para mostrar'}
            </p>
            <p className="mt-0.5 text-xs leading-relaxed text-muted-foreground">
              {mostrarEjemploDistribucion
                ? 'Sirve únicamente para conocer la interfaz. No reemplaza ni modifica datos reales.'
                : 'Puedes abrir un ejemplo completo para conocer cómo se verá cuando existan asignaciones.'}
            </p>
          </div>
          <button
            type="button"
            onClick={() => setMostrarEjemploDistribucion((actual) => !actual)}
            className="rounded-xl bg-primary px-4 py-2 text-xs font-bold text-primary-foreground shadow-sm transition-colors hover:bg-primary-press focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
          >
            {mostrarEjemploDistribucion ? 'Volver a datos reales' : 'Ver ejemplo con datos'}
          </button>
        </div>
      )}

      <DistribucionLeadsGerencia
        datos={datosDistribucion}
        cargando={mostrandoEjemplo ? false : cargandoDistribucion}
        error={mostrandoEjemplo ? null : errorDistribucion}
        modoDemo={mostrandoEjemplo}
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
            label="Monto de leads activos"
            actual={money(datosLocales.capitalPen)}
            objetivo={
              meta.capitalObjetivo > 0
                ? `de ${moneyK(meta.capitalObjetivo)} en soles`
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
              ? `de ${meta.ventasObjetivo} cierres`
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
          title="Estado de los leads"
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
            Distribución de {datosLocales.abiertos} leads abiertos. Los cierres se muestran por separado.
          </p>
        </CardContent>
      </Card>

      <p className="text-[11px] text-muted-foreground">
        {modoDemo
          ? 'Demostración: los datos de esta sección son ficticios.'
          : 'Los números abarcan toda la operación comercial de la empresa.'}
      </p>
    </div>
  )
}
