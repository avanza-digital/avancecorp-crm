// Hoy · GERENCIA — tablero ejecutivo de TODA la empresa (F1c).
// Fuentes: useCRMData().ambito (esGlobal) + lib/inteligencia (comparativaEquipos,
// embudo, conversionPorOrigen, estancados, metricasPorVendedor) + objetivos.
// Semáforos SIN verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626
// crítico · convertido/ganado = navy #111e3d. PEN y USD JAMÁS se suman.
import { useMemo, type CSSProperties, type JSX } from 'react'
import {
  AlertTriangle,
  ChevronRight,
  Filter,
  Medal,
  Megaphone,
  Percent,
  ShieldCheck,
  Target,
  TrendingUp,
  Trophy,
  Users,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { Progress } from '@/components/ui/progress'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { SegmentBar, type Segment } from '@/components/common/stat-strip'
import { useCRMData, usePanelesActions } from '@/lib/store-context'
import { money, moneyK } from '@/lib/format'
import { ETAPA_INFO, type Lead } from '@/lib/tipos'
import {
  colorMeta,
  comparativaEquipos,
  conversionPorOrigen,
  embudo,
  estancados,
  metricasPorVendedor,
} from '@/lib/inteligencia'

// Semáforos (sin verde) + navy de ganado.
const OK = '#2563eb'
const ATENCION = '#d97706'
const CRITICO = '#dc2626'
const NAVY = '#111e3d'
// Paleta por posición para distinguir equipos en la barra proporcional.
const COLOR_EQUIPO = ['#2563eb', '#7c3aed', '#0891b2', '#d97706']
// Podio del top de vendedores (1º navy · 2º violeta · 3º azul).
const PODIO = [NAVY, '#7c3aed', '#2563eb']

const esAbierto = (l: Lead) => l.activo && l.etapa !== 'convertido' && l.etapa !== 'descartado'

/** Chip de tendencia a partir de la serie demo (último vs anterior). */
function tendenciaDe(serie: number[]): string | undefined {
  if (serie.length < 2) return undefined
  const [prev, ult] = serie.slice(-2)
  if (prev == null || ult == null || prev === 0) return undefined
  const pct = Math.round(((ult - prev) / prev) * 100)
  if (pct === 0) return '— 0%'
  return pct > 0 ? `▲ +${pct}%` : `▼ −${Math.abs(pct)}%`
}

/** Semáforo de un valor contra su objetivo: llega azul · a medias ámbar · lejos rojo. */
function colorVsObjetivo(valor: number, objetivo: number): string {
  if (objetivo <= 0 || valor >= objetivo) return OK
  if (valor >= objetivo / 2) return ATENCION
  return CRITICO
}

/** Ítem de la meta del mes: valor actual grande + objetivo + barra semaforizada. */
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
  const p = Math.max(0, Math.min(100, Math.round(pct)))
  return (
    <div>
      <p className="text-[11px] font-bold uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-1 flex items-baseline gap-2">
        <span className="text-xl font-extrabold tracking-tight tabular-nums text-primary">{actual}</span>
        <span className="text-xs text-muted-foreground">{objetivo}</span>
      </div>
      <div className="mt-2 flex items-center gap-2">
        <Progress value={p} color={colorMeta(p)} className="flex-1" />
        <span className="w-9 text-right text-[11px] font-bold tabular-nums" style={{ color: colorMeta(p) }}>
          {p}%
        </span>
      </div>
    </div>
  )
}

export function HoyGerencia(): JSX.Element {
  const { ambito, equipo, actividades, objetivos, series } = useCRMData()
  const { abrirLead } = usePanelesActions()
  const leads = ambito.leads
  const meta = objetivos.gerencia

  // ── Números de empresa (PEN y USD SIEMPRE por separado) ──
  const d = useMemo(() => {
    const vivos = leads.filter((l) => l.activo)
    const abiertos = vivos.filter(esAbierto)
    // Convención de capital/activos (misma que hoy-supervisor y
    // comparativaEquipos): los parkeados NO suman capital ni cuentan como
    // activos hasta tener vendedor — se reportan aparte como "por repartir".
    const asignados = abiertos.filter((l) => l.vendedor_id != null)
    const vivosAsignados = vivos.filter((l) => l.vendedor_id != null)
    const convertidos = vivos.filter((l) => l.etapa === 'convertido')
    const suma = (ls: Lead[], mon: 'PEN' | 'USD') =>
      ls.filter((l) => l.moneda === mon).reduce((a, l) => a + (l.monto_estimado ?? 0), 0)
    return {
      totalVivos: vivos.length,
      abiertos: abiertos.length, // TODOS los abiertos (base del embudo)
      activos: asignados.length, // abiertos CON vendedor (KPI)
      vivosAsignados: vivosAsignados.length,
      porRepartir: abiertos.filter((l) => l.vendedor_id == null).length,
      capPEN: suma(asignados, 'PEN'),
      capUSD: suma(asignados, 'USD'),
      nConvertidos: convertidos.length,
      ganPEN: suma(convertidos, 'PEN'),
      ganUSD: suma(convertidos, 'USD'),
      // Conversión global con la MISMA base que comparativaEquipos:
      // convertidos / leads CON vendedor (los parkeados no cuentan).
      conversion:
        vivosAsignados.length > 0
          ? Math.round((convertidos.length / vivosAsignados.length) * 100)
          : 0,
    }
  }, [leads])

  const equipos = useMemo(() => comparativaEquipos(equipo, leads, actividades), [equipo, leads, actividades])
  const etapas = useMemo(() => embudo(leads), [leads])
  const origenes = useMemo(() => conversionPorOrigen(leads), [leads])
  const enRiesgo = useMemo(() => estancados(leads, actividades, 7), [leads, actividades])
  const top = useMemo(
    () => metricasPorVendedor(ambito.vendedores, leads, actividades).slice(0, 3),
    [ambito.vendedores, leads, actividades],
  )

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* ── KPIs de empresa ── */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={money(d.capPEN)}
          icon={TrendingUp}
          color="var(--accent)"
          sub={d.capUSD > 0 ? `Pipeline activo (PEN) · +${moneyK(d.capUSD, 'USD')}` : 'Pipeline activo (PEN)'}
          spark={series.capital}
          tendencia={tendenciaDe(series.capital)}
          delay={0}
        />
        <KpiCard
          label="Leads activos"
          value={String(d.activos)}
          icon={Users}
          color="var(--chart-2)"
          sub={d.porRepartir > 0 ? `Con vendedor · +${d.porRepartir} por repartir en bandejas` : 'Todos con vendedor asignado'}
          spark={series.leads}
          tendencia={tendenciaDe(series.leads)}
          delay={60}
        />
        <KpiCard
          label="Conversión global"
          value={`${d.conversion}%`}
          icon={Percent}
          color={colorVsObjetivo(d.conversion, meta.conversionObjetivo)}
          sub={`${d.nConvertidos} de ${d.vivosAsignados} leads con vendedor · objetivo ${meta.conversionObjetivo}%`}
          spark={series.conversion}
          delay={120}
        />
        <KpiCard
          label="Capital ganado"
          value={money(d.ganPEN)}
          icon={Trophy}
          color={NAVY}
          sub={d.ganUSD > 0 ? `Histórico convertidos (PEN) · +${moneyK(d.ganUSD, 'USD')}` : 'Histórico convertidos (PEN)'}
          delay={180}
        />
      </div>

      {/* ── Meta del mes — empresa ── */}
      <Card>
        <SectionHead
          icon={Target}
          title="Meta del mes — Empresa"
          right={<span className="text-xs text-muted-foreground">Objetivos de gerencia</span>}
        />
        <CardContent className="grid gap-5 pt-1 sm:grid-cols-3">
          <MetaItem
            label="Capital en proceso"
            actual={money(d.capPEN)}
            objetivo={`de ${moneyK(meta.capitalObjetivo)} (PEN)`}
            pct={meta.capitalObjetivo > 0 ? (d.capPEN / meta.capitalObjetivo) * 100 : 0}
          />
          <MetaItem
            label="Ventas cerradas"
            actual={String(d.nConvertidos)}
            objetivo={`de ${meta.ventasObjetivo} conversiones`}
            pct={meta.ventasObjetivo > 0 ? (d.nConvertidos / meta.ventasObjetivo) * 100 : 0}
          />
          <MetaItem
            label="Conversión"
            actual={`${d.conversion}%`}
            objetivo={`objetivo ${meta.conversionObjetivo}%`}
            pct={meta.conversionObjetivo > 0 ? (d.conversion / meta.conversionObjetivo) * 100 : 0}
          />
        </CardContent>
      </Card>

      {/* ── Comparativa de equipos ── */}
      <Card>
        <SectionHead
          icon={ShieldCheck}
          title="Comparativa de equipos"
          right={
            <span className="text-xs text-muted-foreground">
              {equipos.length} {equipos.length === 1 ? 'supervisor' : 'supervisores'}
            </span>
          }
        />
        <CardContent className="space-y-4 pt-1">
          {/* Reparto del capital activo (solo PEN — el USD va aparte por fila) */}
          <SegmentBar
            segments={equipos.map<Segment>((e, i) => ({
              label: e.supervisor.nombre_completo,
              value: e.capitalPEN,
              color: COLOR_EQUIPO[i % COLOR_EQUIPO.length] ?? NAVY,
              valTxt: moneyK(e.capitalPEN),
            }))}
          />
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  <th className="py-2 pr-4">Equipo</th>
                  <th className="px-4 py-2 text-right">Vendedores</th>
                  <th className="px-4 py-2 text-right">Activos</th>
                  <th className="px-4 py-2 text-right">Capital en proceso</th>
                  <th className="px-4 py-2 text-right">Conversión</th>
                  <th className="py-2 pl-4 text-right">Por repartir</th>
                </tr>
              </thead>
              <tbody>
                {equipos.map((e, i) => {
                  const c = COLOR_EQUIPO[i % COLOR_EQUIPO.length] ?? NAVY
                  return (
                    <tr key={e.supervisor.perfil_id} className="border-b border-border/60 last:border-0">
                      <td className="py-2.5 pr-4">
                        <div className="flex items-center gap-2.5">
                          <Avatar nombre={e.supervisor.nombre_completo} color={c} className="size-7 text-[10px]" />
                          <span className="truncate font-semibold">{e.supervisor.nombre_completo}</span>
                        </div>
                      </td>
                      <td className="px-4 py-2.5 text-right tabular-nums text-muted-foreground">{e.vendedores}</td>
                      <td className="px-4 py-2.5 text-right font-semibold tabular-nums">{e.activos}</td>
                      <td className="px-4 py-2.5 text-right">
                        <p className="font-extrabold tabular-nums text-primary">{money(e.capitalPEN)}</p>
                        {e.capitalUSD > 0 && (
                          <p className="text-[11px] tabular-nums text-muted-foreground">
                            +{moneyK(e.capitalUSD, 'USD')}
                          </p>
                        )}
                      </td>
                      <td className="px-4 py-2.5 text-right">
                        <Badge color={colorVsObjetivo(e.conversion, meta.conversionObjetivo)} variant="outline">
                          {e.conversion}%
                        </Badge>
                      </td>
                      <td className="py-2.5 pl-4 text-right">
                        {e.parkeados > 0 ? (
                          <Badge color="var(--warning)" dot>
                            {e.parkeados} {e.parkeados === 1 ? 'lead' : 'leads'}
                          </Badge>
                        ) : (
                          <span className="text-xs text-muted-foreground">0</span>
                        )}
                      </td>
                    </tr>
                  )
                })}
                {/* Vacío DENTRO del tbody (colSpan) — la cabecera no queda huérfana */}
                {equipos.length === 0 && (
                  <tr>
                    <td colSpan={6} className="py-4 text-center text-xs text-muted-foreground">
                      Aún no hay supervisores activos con equipo a cargo.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </CardContent>
      </Card>

      {/* ── Embudo + conversión por origen ── */}
      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <SectionHead
            icon={Filter}
            title="Embudo del pipeline"
            right={
              <span className="text-xs tabular-nums text-muted-foreground">{d.abiertos} abiertos</span>
            }
          />
          <CardContent className="space-y-3.5 pt-1">
            {(() => {
              const maxN = Math.max(...etapas.map((e) => e.n), 1)
              return etapas.map((e, i) => {
                const info = ETAPA_INFO[e.etapa]
                const prev = i > 0 ? etapas[i - 1] : undefined
                // Drop-off contra la etapa anterior (solo si de verdad cae).
                const caida = prev && prev.n > 0 && e.n < prev.n ? Math.round(((prev.n - e.n) / prev.n) * 100) : 0
                return (
                  <div key={e.etapa}>
                    <div className="mb-1 flex items-baseline justify-between gap-2 text-xs">
                      <span className="flex items-center gap-2 font-semibold">
                        <span className="size-2 shrink-0 rounded-full" style={{ background: info.color }} />
                        {info.label}
                        {caida > 0 && (
                          <span
                            className="font-bold tabular-nums"
                            style={{ color: caida >= 50 ? CRITICO : ATENCION }}
                            title={`Caída del ${caida}% frente a ${prev ? ETAPA_INFO[prev.etapa].label : ''}`}
                          >
                            ▼ −{caida}%
                          </span>
                        )}
                      </span>
                      <span className="tabular-nums text-muted-foreground">
                        <span className="font-extrabold text-foreground">{e.n}</span>{' '}
                        {e.n === 1 ? 'lead' : 'leads'} · {e.pctDelTotal}%
                      </span>
                    </div>
                    <div className="h-3 overflow-hidden rounded-full bg-muted">
                      <div
                        className="h-full rounded-full transition-[width] duration-700 ease-out"
                        style={{
                          width: `${e.n > 0 ? Math.max((e.n / maxN) * 100, 6) : 0}%`,
                          background: info.color,
                        }}
                      />
                    </div>
                  </div>
                )
              })
            })()}
            <p className="text-[11px] text-muted-foreground">
              % sobre los {d.abiertos} leads abiertos · ▼ marca el drop-off frente a la etapa anterior.
            </p>
          </CardContent>
        </Card>

        <Card>
          <SectionHead
            icon={Megaphone}
            title="Conversión por origen"
            right={<span className="text-xs text-muted-foreground">Histórico de la empresa</span>}
          />
          <CardContent className="pt-1">
            {origenes.length === 0 ? (
              <p className="py-6 text-center text-xs text-muted-foreground">Aún no hay leads registrados.</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border text-left text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                    <th className="py-2 pr-3">Origen</th>
                    <th className="px-3 py-2 text-right">Leads</th>
                    <th className="px-3 py-2 text-right">Conv.</th>
                    <th className="py-2 pl-3">% conversión</th>
                  </tr>
                </thead>
                <tbody>
                  {origenes.map((o, i) => {
                    const mejor = i === 0 && o.convertidos > 0
                    return (
                      <tr key={o.origen} className="border-b border-border/60 last:border-0">
                        <td className="py-2.5 pr-3">
                          <span className="flex items-center gap-2 font-semibold">
                            {o.label}
                            {mejor && (
                              <Badge color={NAVY} variant="solid">
                                Mejor canal
                              </Badge>
                            )}
                          </span>
                        </td>
                        <td className="px-3 py-2.5 text-right tabular-nums text-muted-foreground">{o.total}</td>
                        <td className="px-3 py-2.5 text-right font-semibold tabular-nums">{o.convertidos}</td>
                        <td className="py-2.5 pl-3">
                          <div className="flex items-center gap-2">
                            <Progress
                              value={o.pct}
                              color={mejor ? NAVY : 'var(--accent)'}
                              className="h-1.5 w-full max-w-24 flex-1"
                            />
                            <span className="w-9 shrink-0 text-right text-xs font-bold tabular-nums">{o.pct}%</span>
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      </div>

      {/* ── Capital en riesgo + top vendedores ── */}
      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <SectionHead
            icon={AlertTriangle}
            title="Capital en riesgo"
            right={
              <Badge color={CRITICO} variant="outline">
                ≥ 7 días sin actividad
              </Badge>
            }
          />
          <CardContent className="pt-1">
            {enRiesgo.length === 0 ? (
              <p className="py-6 text-center text-xs text-muted-foreground">
                Sin capital en riesgo — ningún lead abierto lleva 7 días o más sin actividad.
              </p>
            ) : (
              <>
                {(() => {
                  const riesgoPEN = enRiesgo
                    .filter((x) => x.lead.moneda === 'PEN')
                    .reduce((a, x) => a + (x.lead.monto_estimado ?? 0), 0)
                  const riesgoUSD = enRiesgo
                    .filter((x) => x.lead.moneda === 'USD')
                    .reduce((a, x) => a + (x.lead.monto_estimado ?? 0), 0)
                  return (
                    <div className="mb-3 flex items-baseline gap-2">
                      <span className="text-2xl font-extrabold tracking-tight tabular-nums" style={{ color: CRITICO }}>
                        {money(riesgoPEN)}
                      </span>
                      <span className="text-xs text-muted-foreground">
                        estancado (PEN){riesgoUSD > 0 ? ` · +${moneyK(riesgoUSD, 'USD')}` : ''} ·{' '}
                        {enRiesgo.length} {enRiesgo.length === 1 ? 'lead' : 'leads'}
                      </span>
                    </div>
                  )
                })()}
                <div className="space-y-1.5">
                  {enRiesgo.slice(0, 5).map(({ lead, dias }) => {
                    const diasTxt = Math.floor(dias)
                    return (
                      <button
                        key={lead.id}
                        type="button"
                        onClick={() => abrirLead(lead.id)}
                        aria-label={`Abrir ficha de ${lead.nombre_completo}`}
                        className="group flex w-full items-center gap-2.5 rounded-xl border border-border/60 px-3 py-2 text-left transition-colors hover:bg-muted/40 focus-visible:bg-muted/40 focus-visible:outline-none"
                      >
                        <Avatar nombre={lead.nombre_completo} color={diasTxt >= 10 ? CRITICO : ATENCION} className="size-8" />
                        <span className="min-w-0 flex-1 leading-tight">
                          <span className="block truncate text-sm font-semibold">{lead.nombre_completo}</span>
                          <span className="block truncate text-[11px] text-muted-foreground">
                            {lead.vendedor_nombre ?? 'Sin vendedor asignado'} · {ETAPA_INFO[lead.etapa].label}
                          </span>
                        </span>
                        {lead.monto_estimado != null && (
                          <span className="shrink-0 text-sm font-extrabold tabular-nums text-primary">
                            {moneyK(lead.monto_estimado, lead.moneda)}
                          </span>
                        )}
                        <Badge color={diasTxt >= 10 ? CRITICO : ATENCION} dot>
                          {diasTxt} d
                        </Badge>
                        <ChevronRight className="size-4 shrink-0 text-muted-foreground opacity-0 transition-opacity group-hover:opacity-100 group-focus-visible:opacity-100" />
                      </button>
                    )
                  })}
                </div>
                {enRiesgo.length > 5 && (
                  <p className="mt-2 text-[11px] text-muted-foreground">
                    Y {enRiesgo.length - 5} más — revísalos desde la cartera.
                  </p>
                )}
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <SectionHead
            icon={Medal}
            title="Top vendedores"
            right={<span className="text-xs text-muted-foreground">Por capital en proceso (PEN)</span>}
          />
          <CardContent className="space-y-2.5 pt-1">
            {top.length === 0 ? (
              <p className="py-6 text-center text-xs text-muted-foreground">Aún no hay vendedores con cartera.</p>
            ) : (
              top.map((r, i) => {
                const c = PODIO[i] ?? PODIO[PODIO.length - 1] ?? NAVY
                return (
                  <div
                    key={r.m.perfil_id}
                    className="flex items-center gap-3 rounded-xl border border-border/60 px-3 py-2.5"
                    style={i === 0 ? { background: `color-mix(in srgb, ${NAVY} 4%, transparent)` } : undefined}
                  >
                    <span
                      className="ac-chip grid size-8 shrink-0 place-items-center rounded-full text-xs font-extrabold"
                      style={{ '--c': c } as CSSProperties}
                    >
                      {i + 1}º
                    </span>
                    <Avatar nombre={r.m.nombre_completo} color={c} className="size-9" />
                    <div className="min-w-0 flex-1 leading-tight">
                      <p className="truncate text-sm font-semibold">{r.m.nombre_completo}</p>
                      <p className="truncate text-[11px] text-muted-foreground">
                        {r.activos} activos · {r.convertidos} {r.convertidos === 1 ? 'venta' : 'ventas'} ·{' '}
                        {r.conversion}% conv.
                      </p>
                    </div>
                    <div className="shrink-0 text-right">
                      <p className="text-sm font-extrabold tabular-nums text-primary">{money(r.capitalPEN)}</p>
                      {r.capitalUSD > 0 && (
                        <p className="text-[11px] tabular-nums text-muted-foreground">
                          +{moneyK(r.capitalUSD, 'USD')}
                        </p>
                      )}
                    </div>
                  </div>
                )
              })
            )}
          </CardContent>
        </Card>
      </div>

      <p className="text-[11px] text-muted-foreground">
        Tablero de demostración — pronto verás aquí la información real de tu operación.
      </p>
    </div>
  )
}
