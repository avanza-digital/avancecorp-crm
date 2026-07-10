// Hoy · VENDEDOR (F1c) — la pantalla diaria del asesor: SU cartera, SU cola de
// acción y SU meta. ambito.leads YA viene recortado por el store (solo los
// suyos), así que aquí no hay ni ranking ni datos de otros vendedores — ni en
// los totales. Semáforos sin verde: azul ok · ámbar atención · rojo crítico.
import type { JSX } from 'react'
import {
  CalendarDays,
  ChevronRight,
  CircleCheckBig,
  Clock,
  FileText,
  MessageCircle,
  Phone,
  Target,
  Trophy,
  Users,
  Wallet,
  Zap,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import { SectionHead } from '@/components/common/section-head'
import { KpiCard } from '@/components/common/kpi-card'
import { AGENDA_DEMO, METAS_DEMO, SPARKS_DEMO } from '@/lib/demo'
import { colaDe, colorMeta, type ItemCola } from '@/lib/inteligencia'
import { useStore } from '@/lib/store'
import { useAuth } from '@/lib/auth'
import { money, moneyK, primerNombre } from '@/lib/format'

// ── Constantes de presentación ────────────────────────────────────────────────

/** Semáforo de severidad de la cola (SIN verde): rojo crítico · ámbar · azul. */
const SEV_COLOR: Record<ItemCola['sev'], string> = {
  critica: '#dc2626',
  media: '#d97706',
  baja: '#2563eb',
}

/** Labels es-PE de los buckets de la cola (por_repartir no aparece para el
 *  vendedor: su ámbito nunca incluye parkeados — se mapea por exhaustividad). */
const BUCKET_LABEL: Record<ItemCola['bucket'], string> = {
  sin_responder: 'Sin responder',
  propuesta_sin_respuesta: 'Propuesta sin respuesta',
  seguimiento: 'Seguimiento',
  por_repartir: 'Por repartir',
}

/** Labels es-PE de los tipos de evento de agenda (con tilde). */
const TIPO_EVENTO: Record<string, string> = {
  reunion: 'Reunión',
  llamada: 'Llamada',
  vencimiento: 'Vencimiento',
}

/** Link de acción rápida (tel:/wa.me reales — mismo patrón del lead-drawer). */
const CLASE_ACCION =
  'inline-flex h-7 items-center gap-1.5 rounded-lg border border-input bg-card px-2.5 text-[11px] font-semibold text-foreground transition-colors hover:bg-muted hover:border-border-strong [&_svg]:size-3.5'

// ── Helpers puros ─────────────────────────────────────────────────────────────

/** Chip de tendencia "▲ +13%" desde la serie del sparkline (últimos 2 puntos). */
function tendenciaDe(serie: number[]): string | undefined {
  if (serie.length < 2) return undefined
  const prev = serie[serie.length - 2]
  const ult = serie[serie.length - 1]
  if (prev === 0) return undefined
  const pct = Math.round(((ult - prev) / prev) * 100)
  if (pct === 0) return undefined
  return pct > 0 ? `▲ +${pct}%` : `▼ −${Math.abs(pct)}%`
}

/** % de avance hacia el objetivo (Progress ya recorta a 0–100 al pintar). */
const pctMeta = (actual: number, objetivo: number): number =>
  objetivo > 0 ? (actual / objetivo) * 100 : 0

/** "hoy" / "N d" para la columna de días de la cola (dias viene con fracción). */
const diasTxt = (d: number): string => (d < 1 ? 'hoy' : `${Math.floor(d)} d`)

/** Fecha larga es-PE con la primera letra en mayúscula. */
function fechaLarga(): string {
  const s = new Date().toLocaleDateString('es-PE', { weekday: 'long', day: 'numeric', month: 'long' })
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyVendedor(): JSX.Element {
  const { ambito, actividades, abrirLead } = useStore()
  const { yo } = useAuth()

  // Universo del asesor — ambito.leads ya es SOLO su cartera.
  const mios = ambito.leads.filter((l) => l.activo)
  const abiertos = mios.filter((l) => l.etapa !== 'convertido' && l.etapa !== 'descartado')
  const convertidos = mios.filter((l) => l.etapa === 'convertido')
  const propuestas = abiertos.filter((l) => l.etapa === 'propuesta_enviada')

  // Capital en proceso — PEN y USD SIEMPRE por separado (jamás un total mixto).
  let capPEN = 0
  let capUSD = 0
  for (const l of abiertos) {
    if (l.moneda === 'USD') capUSD += l.monto_estimado ?? 0
    else capPEN += l.monto_estimado ?? 0
  }

  // Meta del mes: objetivos demo estáticos vs actuales calculados de SUS leads.
  // Misma semántica que supervisor/gerencia: capital EN PROCESO (PEN) vs objetivo.
  const meta = METAS_DEMO.vendedor
  const conversion = mios.length > 0 ? Math.round((convertidos.length / mios.length) * 100) : 0

  // Cola de acción personal (el ámbito del vendedor no trae parkeados).
  const cola = colaDe(ambito.leads, actividades)

  // Agenda demo recortada a SUS leads.
  const idsMios = new Set(mios.map((l) => l.id))
  const agenda = AGENDA_DEMO.filter((ev) => idsMios.has(ev.lead_id))

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Saludo del día */}
      <div>
        <h2 className="text-lg font-extrabold tracking-tight text-primary">
          Hola, {primerNombre(yo?.nombre_completo) || 'asesor'}
        </h2>
        <p className="text-xs text-muted-foreground">
          {fechaLarga()} · Tu cartera y tus pendientes — solo ves lo tuyo
        </p>
      </div>

      {/* KPIs personales — capital PEN con el USD aparte (nunca sumados) */}
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={money(capPEN)}
          icon={Wallet}
          color="#2563eb"
          sub={capUSD > 0 ? `Pipeline activo (PEN) · +${moneyK(capUSD, 'USD')} aparte` : 'Pipeline activo (PEN)'}
          spark={SPARKS_DEMO.capital}
          tendencia={tendenciaDe(SPARKS_DEMO.capital)}
          delay={0}
        />
        <KpiCard
          label="Leads activos"
          value={String(abiertos.length)}
          icon={Users}
          color="#7c3aed"
          sub="Abiertos en tu cartera"
          spark={SPARKS_DEMO.leads}
          tendencia={tendenciaDe(SPARKS_DEMO.leads)}
          delay={60}
        />
        <KpiCard
          label="Propuestas enviadas"
          value={String(propuestas.length)}
          icon={FileText}
          color="#d97706"
          sub="Esperando respuesta del cliente"
          spark={SPARKS_DEMO.propuestas}
          tendencia={tendenciaDe(SPARKS_DEMO.propuestas)}
          delay={120}
        />
        {/* Sin spark: la serie de % de conversión no representa este CONTEO. */}
        <KpiCard
          label="Convertidos"
          value={String(convertidos.length)}
          icon={Trophy}
          color="#111e3d"
          sub="Histórico · clientes ganados"
          delay={180}
        />
      </div>

      <div className="grid gap-5 lg:grid-cols-3">
        {/* Cola de acción personal */}
        <Card className="lg:col-span-2 self-start">
          <SectionHead
            icon={Zap}
            title="Tu siguiente acción hoy"
            right={
              cola.length > 0 ? (
                <Badge color="var(--accent)">
                  {cola.length} {cola.length === 1 ? 'pendiente' : 'pendientes'}
                </Badge>
              ) : undefined
            }
          />
          <CardContent className="space-y-1.5 pt-0">
            {cola.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-10 text-center">
                <CircleCheckBig className="size-8 text-accent" />
                <p className="text-sm font-bold">Al día ✦ sin pendientes</p>
                <p className="text-xs text-muted-foreground">
                  No tienes leads esperando respuesta ni seguimientos vencidos.
                </p>
              </div>
            ) : (
              cola.map((item) => <FilaCola key={item.lead.id} item={item} abrirLead={abrirLead} />)
            )}
          </CardContent>
        </Card>

        <div className="space-y-5">
          {/* Meta del mes */}
          <Card>
            <SectionHead
              icon={Target}
              title="Tu meta del mes"
              right={<span className="text-[11px] text-muted-foreground">objetivos demo</span>}
            />
            <CardContent className="space-y-4 pt-0">
              {[
                {
                  label: 'Capital en proceso (PEN)',
                  pct: pctMeta(capPEN, meta.capitalObjetivo),
                  txt: `${moneyK(capPEN)} de ${moneyK(meta.capitalObjetivo)}`,
                },
                {
                  label: 'Ventas cerradas',
                  pct: pctMeta(convertidos.length, meta.ventasObjetivo),
                  txt: `${convertidos.length} de ${meta.ventasObjetivo}`,
                },
                {
                  label: 'Conversión',
                  pct: pctMeta(conversion, meta.conversionObjetivo),
                  txt: `${conversion}% de ${meta.conversionObjetivo}%`,
                },
              ].map((m) => (
                <div key={m.label}>
                  <div className="flex items-baseline justify-between gap-2">
                    <p className="text-xs font-semibold text-foreground/80">{m.label}</p>
                    <p className="text-xs font-bold tabular-nums">{m.txt}</p>
                  </div>
                  <Progress value={m.pct} color={colorMeta(m.pct)} className="mt-1.5" />
                  <p className="mt-1 text-[11px] tabular-nums text-muted-foreground">
                    {Math.round(m.pct)}% del objetivo
                  </p>
                </div>
              ))}
              {capUSD > 0 && (
                <p className="text-[11px] text-muted-foreground">
                  Además tienes {moneyK(capUSD, 'USD')} en proceso en dólares — se cuenta
                  aparte, nunca se suma al total en soles.
                </p>
              )}
            </CardContent>
          </Card>

          {/* Agenda de hoy (demo, recortada a SUS leads) */}
          <Card>
            <SectionHead
              icon={CalendarDays}
              title="Tu agenda de hoy"
              right={agenda.length > 0 ? <Badge color="var(--accent)">{agenda.length}</Badge> : undefined}
            />
            <CardContent className="space-y-1 pt-0">
              {agenda.length === 0 ? (
                <p className="py-6 text-center text-xs text-muted-foreground">
                  Sin eventos programados para hoy.
                </p>
              ) : (
                agenda.map((ev) => {
                  const hora = ev.cuando.split(' · ')[1] ?? ev.cuando
                  const abrir = () => abrirLead(ev.lead_id)
                  return (
                    <div
                      key={ev.id}
                      role="button"
                      tabIndex={0}
                      aria-label={`Abrir ficha — ${ev.titulo}`}
                      onClick={abrir}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault()
                          abrir()
                        }
                      }}
                      className="flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
                    >
                      <span className="w-1 self-stretch rounded" style={{ background: ev.color, minHeight: 40 }} />
                      <div className="min-w-0 flex-1 leading-tight">
                        <p className="truncate text-[13px] font-semibold">{ev.titulo}</p>
                        <div className="mt-1">
                          <Badge color={ev.color} className="text-[10px]">
                            {TIPO_EVENTO[ev.tipo] ?? ev.tipo}
                          </Badge>
                        </div>
                      </div>
                      <span className="flex shrink-0 items-center gap-1 text-[11px] font-semibold tabular-nums text-muted-foreground">
                        <Clock className="size-3.5" />
                        {hora}
                      </span>
                    </div>
                  )
                })
              )}
            </CardContent>
          </Card>
        </div>
      </div>

      <p className="text-[11px] text-muted-foreground">
        Demo — solo ves tu propia cartera; la visibilidad real la garantiza la RLS jerárquica de la BD.
      </p>
    </div>
  )
}

// ── Fila de la cola de acción ─────────────────────────────────────────────────
// Dot de severidad + badge del bucket + motivo (con días) + acciones reales
// (tel:/wa.me) + abrir ficha. Los links cortan la propagación para no abrir
// la ficha al llamar/escribir.

function FilaCola({
  item,
  abrirLead,
}: {
  item: ItemCola
  abrirLead: (id: string) => void
}): JSX.Element {
  const c = SEV_COLOR[item.sev]
  const wa = item.lead.telefono.replace('+', '')
  const abrir = () => abrirLead(item.lead.id)
  return (
    <div
      role="button"
      tabIndex={0}
      aria-label={`Abrir ficha — ${item.lead.nombre_completo}`}
      onClick={abrir}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          abrir()
        }
      }}
      className="group flex cursor-pointer items-center gap-3 rounded-lg p-2 transition-colors hover:bg-muted/60 focus-visible:outline-none focus-visible:ring-[3px] focus-visible:ring-ring/40"
    >
      <span className="size-2.5 shrink-0 rounded-full" style={{ background: c }} aria-hidden />
      <div className="min-w-0 flex-1 leading-tight">
        <div className="flex flex-wrap items-center gap-1.5">
          <p className="truncate text-sm font-semibold">{item.lead.nombre_completo}</p>
          <Badge color={c} className="text-[10px]">
            {BUCKET_LABEL[item.bucket]}
          </Badge>
        </div>
        <p className="mt-0.5 truncate text-xs text-muted-foreground">{item.motivo}</p>
      </div>
      <span className="hidden shrink-0 text-[11px] font-semibold tabular-nums text-muted-foreground sm:block">
        {diasTxt(item.dias)}
      </span>
      <div
        className="flex shrink-0 items-center gap-1.5"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={(e) => e.stopPropagation()}
      >
        <a
          href={`tel:${item.lead.telefono}`}
          className={CLASE_ACCION}
          aria-label={`Llamar a ${item.lead.nombre_completo}`}
        >
          <Phone /> <span className="hidden md:inline">Llamar</span>
        </a>
        <a
          href={`https://wa.me/${wa}`}
          target="_blank"
          rel="noreferrer"
          className={CLASE_ACCION}
          aria-label={`WhatsApp a ${item.lead.nombre_completo}`}
        >
          <MessageCircle /> <span className="hidden md:inline">WhatsApp</span>
        </a>
      </div>
      <ChevronRight className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </div>
  )
}
