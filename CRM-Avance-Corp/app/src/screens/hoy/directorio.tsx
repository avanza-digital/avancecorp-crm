// Hoy · DIRECTORIO — auditoría ejecutiva global de SOLO LECTURA (F1c).
// El directorio ve TODA la operación (ambito.esGlobal) pero no ejecuta nada:
// cero botones de acción. Abrir la ficha (modo lectura) sí está permitido,
// igual que los links de contacto tel/wa que viven dentro del drawer.
// Semáforos sin verde: azul #2563eb ok · ámbar #d97706 atención · rojo #dc2626
// crítico · convertido/ganado = navy #111e3d.
import { useMemo, type CSSProperties, type JSX } from 'react'
import {
  ArrowRightLeft,
  BadgeCheck,
  CalendarCheck,
  Coins,
  Eye,
  Filter,
  History,
  MessageCircle,
  MessageSquare,
  PhoneCall,
  PhoneMissed,
  ShieldCheck,
  StickyNote,
  Users,
  UsersRound,
  Wallet,
  XCircle,
  type LucideIcon,
} from 'lucide-react'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Avatar } from '@/components/ui/avatar'
import { KpiCard } from '@/components/common/kpi-card'
import { SectionHead } from '@/components/common/section-head'
import { Donut } from '@/components/common/donut'
import { useStore } from '@/lib/store'
import { comparativaEquipos, embudo } from '@/lib/inteligencia'
import { money, moneyK, fmtFecha } from '@/lib/format'
import {
  ETAPA_INFO,
  MOTIVOS_DESCARTE,
  TIPOS_ACTIVIDAD,
  type Lead,
  type TipoActividad,
} from '@/lib/tipos'

// ── Constantes de la vista ────────────────────────────────────────────────────

const AZUL = '#2563eb' // ok
const AMBAR = '#d97706' // atención
const ROJO = '#dc2626' // crítico
const NAVY = '#111e3d' // ganado/convertido
const VIOLETA = '#7c3aed'

const TERMINALES_K = new Set<string>(['convertido', 'descartado'])
const esAbierto = (l: Lead) => l.activo && !TERMINALES_K.has(l.etapa)

// Mismo mapa de iconos del timeline del drawer (consistencia visual).
const ICONO_ACTIVIDAD: Record<TipoActividad, LucideIcon> = {
  llamada_realizada: PhoneCall,
  llamada_no_contestada: PhoneMissed,
  whatsapp_enviado: MessageCircle,
  whatsapp_recibido: MessageSquare,
  reunion_realizada: CalendarCheck,
  nota: StickyNote,
  cambio_etapa: ArrowRightLeft,
  reasignacion: Users,
  conversion: BadgeCheck,
}

/** "hace Xh / hace Xd" compacto para la bitácora; fechas raras caen a fmtFecha. */
function haceCorto(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime()
  if (!Number.isFinite(ms) || ms < 0) return fmtFecha(iso)
  const h = Math.floor(ms / 3_600_000)
  if (h < 1) return 'hace minutos'
  if (h < 24) return `hace ${h} h`
  const d = Math.floor(h / 24)
  return `hace ${d} d`
}

// ── Pantalla ──────────────────────────────────────────────────────────────────

export function HoyDirectorio(): JSX.Element {
  const { ambito, equipo, actividades, abrirLead } = useStore()

  const r = useMemo(() => {
    const vivos = ambito.leads.filter((l) => l.activo)
    const abiertos = vivos.filter(esAbierto)
    // Convención de capital/activos (misma que la comparativa de equipos y la
    // nota al pie): los parkeados NO suman capital ni cuentan como activos
    // hasta tener vendedor asignado.
    const asignados = abiertos.filter((l) => l.vendedor_id != null)
    const porRepartir = abiertos.length - asignados.length
    const convertidos = vivos.filter((l) => l.etapa === 'convertido')
    const descartados = vivos.filter((l) => l.etapa === 'descartado')

    // Capital SIEMPRE separado por moneda — jamás un total mixto.
    const suma = (ls: Lead[], usd: boolean) =>
      ls.reduce((a, l) => a + ((l.moneda === 'USD') === usd ? (l.monto_estimado ?? 0) : 0), 0)
    const procesoPEN = suma(asignados, false)
    const procesoUSD = suma(asignados, true)
    const ganadoPEN = suma(convertidos, false)
    const ganadoUSD = suma(convertidos, true)

    const cerrados = convertidos.length + descartados.length
    const tasaDescarte = cerrados > 0 ? Math.round((descartados.length / cerrados) * 100) : 0

    // Distribución por moneda del capital ACTIVO (con vendedor): el donut
    // reparte por número de leads (los montos PEN/USD no se mezclan).
    const abiertosPEN = asignados.filter((l) => l.moneda !== 'USD').length
    const abiertosUSD = asignados.filter((l) => l.moneda === 'USD').length

    // Integridad de descartes: todo descarte debe llevar motivo del catálogo.
    const porMotivo = MOTIVOS_DESCARTE.map((m) => ({
      ...m,
      n: descartados.filter((l) => l.motivo_descarte === m.k).length,
    })).filter((m) => m.n > 0)
    const sinMotivo = descartados.filter((l) => !l.motivo_descarte).length

    const recientes = [...actividades]
      .sort((a, b) => b.creado_en.localeCompare(a.creado_en))
      .slice(0, 8)

    return {
      vivos, abiertos, asignados, porRepartir, convertidos, descartados,
      procesoPEN, procesoUSD, ganadoPEN, ganadoUSD,
      cerrados, tasaDescarte, abiertosPEN, abiertosUSD,
      porMotivo, sinMotivo, recientes,
      filasEquipos: comparativaEquipos(equipo, ambito.leads, actividades),
      etapas: embudo(ambito.leads),
    }
  }, [ambito.leads, equipo, actividades])

  const leadDe = (id: string) => ambito.leads.find((l) => l.id === id)

  return (
    <div className="mx-auto max-w-[1240px] space-y-5 ac-rise">
      {/* Banner de auditoría — sobrio, sin acciones */}
      <div className="flex items-center gap-3 rounded-xl border border-border bg-primary/[0.04] px-4 py-3">
        <span className="ac-chip grid size-9 shrink-0 place-items-center rounded-lg" style={{ '--c': NAVY } as CSSProperties}>
          <Eye className="size-4" />
        </span>
        <div className="min-w-0">
          <p className="text-sm font-bold tracking-tight text-primary">Modo auditoría</p>
          <p className="text-xs text-muted-foreground">
            Visión integral de la operación comercial, solo lectura
          </p>
        </div>
        <Badge color={NAVY} variant="outline" className="ml-auto hidden sm:inline-flex">
          Directorio
        </Badge>
      </div>

      {/* KPIs ejecutivos */}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <KpiCard
          label="Capital en proceso"
          value={money(r.procesoPEN)}
          icon={Wallet}
          color={AZUL}
          sub={
            r.procesoUSD > 0
              ? `Pipeline activo (PEN) · +${moneyK(r.procesoUSD, 'USD')} en dólares`
              : 'Pipeline activo (PEN)'
          }
          delay={0}
        />
        <KpiCard
          label="Capital ganado"
          value={money(r.ganadoPEN)}
          icon={BadgeCheck}
          color={NAVY}
          sub={
            r.ganadoUSD > 0
              ? `${r.convertidos.length} convertidos (PEN) · +${moneyK(r.ganadoUSD, 'USD')} en dólares`
              : `${r.convertidos.length} convertidos (PEN)`
          }
          delay={60}
        />
        <KpiCard
          label="Leads activos"
          value={String(r.asignados.length)}
          icon={Users}
          color={VIOLETA}
          sub={
            r.porRepartir > 0
              ? `Con vendedor · +${r.porRepartir} por repartir · ${r.vivos.length} históricos`
              : `De ${r.vivos.length} leads en el histórico`
          }
          delay={120}
        />
        {/* Semáforo completo: azul sano <30 · ámbar 30–59 · rojo ≥60 */}
        <KpiCard
          label="Tasa de descarte"
          value={`${r.tasaDescarte}%`}
          icon={XCircle}
          color={r.tasaDescarte >= 60 ? ROJO : r.tasaDescarte >= 30 ? AMBAR : AZUL}
          sub={`${r.descartados.length} descartados de ${r.cerrados} cierres`}
          delay={180}
        />
      </div>

      {/* Embudo + distribución por moneda */}
      <div className="grid gap-5 lg:grid-cols-5">
        <Card className="lg:col-span-3">
          <SectionHead
            icon={Filter}
            title="Embudo del pipeline"
            right={
              <span className="text-xs text-muted-foreground">
                {r.abiertos.length} leads abiertos
              </span>
            }
          />
          <CardContent className="space-y-3.5">
            {(() => {
              const maxN = Math.max(1, ...r.etapas.map((e) => e.n))
              return r.etapas.map((e) => {
                const info = ETAPA_INFO[e.etapa]
                return (
                  <div key={e.etapa}>
                    <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
                      <span className="font-semibold text-foreground/85">{info.label}</span>
                      <span className="tabular-nums text-muted-foreground">
                        <span className="font-bold text-foreground">{e.n}</span> · {e.pctDelTotal}%
                      </span>
                    </div>
                    <div className="h-2.5 overflow-hidden rounded-full bg-muted">
                      <div
                        className="h-full rounded-full transition-[width] duration-500 ease-out"
                        style={{ width: `${(e.n / maxN) * 100}%`, background: info.color }}
                      />
                    </div>
                  </div>
                )
              })
            })()}
            <p className="pt-1 text-[11px] text-muted-foreground">
              Solo etapas de trabajo — convertidos y descartados se auditan aparte.
            </p>
          </CardContent>
        </Card>

        <Card className="lg:col-span-2">
          <SectionHead icon={Coins} title="Distribución por moneda" />
          <CardContent>
            <Donut
              size={170}
              slices={[
                { label: 'Soles (PEN)', value: r.abiertosPEN, color: AZUL },
                { label: 'Dólares (USD)', value: r.abiertosUSD, color: VIOLETA },
              ]}
              centerValue={String(r.asignados.length)}
              centerLabel="leads activos"
            />
            {/* Capitales SIEMPRE por separado — nunca un total PEN+USD */}
            <div className="mt-4 grid grid-cols-2 gap-2 border-t border-border pt-3 text-center">
              <div>
                <p className="text-sm font-extrabold tabular-nums text-primary">{moneyK(r.procesoPEN)}</p>
                <p className="text-[11px] text-muted-foreground">Capital activo en soles</p>
              </div>
              <div>
                <p className="text-sm font-extrabold tabular-nums text-primary">{moneyK(r.procesoUSD, 'USD')}</p>
                <p className="text-[11px] text-muted-foreground">Capital activo en dólares</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Comparativa de equipos — tabla sobria, sin acciones */}
      <Card>
        <SectionHead
          icon={UsersRound}
          title="Comparativa de equipos"
          right={
            <span className="text-xs text-muted-foreground">
              Por supervisor · capital en proceso
            </span>
          }
        />
        <CardContent className="overflow-x-auto">
          <table className="w-full min-w-[680px] text-sm">
            <thead>
              <tr className="border-b border-border text-left text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
                <th className="pb-2 pr-3 font-bold">Equipo</th>
                <th className="pb-2 pr-3 text-right font-bold">Vendedores</th>
                <th className="pb-2 pr-3 text-right font-bold">Activos</th>
                <th className="pb-2 pr-3 text-right font-bold">Capital (PEN)</th>
                <th className="pb-2 pr-3 text-right font-bold">Convertidos</th>
                <th className="pb-2 pr-3 text-right font-bold">Conversión</th>
                <th className="pb-2 text-right font-bold">Por repartir</th>
              </tr>
            </thead>
            <tbody>
              {r.filasEquipos.map((f) => (
                <tr key={f.supervisor.perfil_id} className="border-b border-border/60 last:border-0">
                  <td className="py-2.5 pr-3">
                    <div className="flex items-center gap-2.5">
                      <Avatar nombre={f.supervisor.nombre_completo} color={VIOLETA} className="size-7 text-[10px]" />
                      <span className="truncate font-semibold">{f.supervisor.nombre_completo}</span>
                    </div>
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.vendedores}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.activos}</td>
                  <td className="py-2.5 pr-3 text-right">
                    <span className="font-bold tabular-nums text-primary">{moneyK(f.capitalPEN)}</span>
                    {f.capitalUSD > 0 && (
                      <span className="block text-[11px] tabular-nums text-muted-foreground">
                        +{moneyK(f.capitalUSD, 'USD')}
                      </span>
                    )}
                  </td>
                  <td className="py-2.5 pr-3 text-right">
                    <span className="font-semibold tabular-nums" style={{ color: NAVY }}>{f.convertidos}</span>
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{f.conversion}%</td>
                  <td className="py-2.5 text-right">
                    {f.parkeados > 0 ? (
                      <Badge color={AMBAR}>{f.parkeados}</Badge>
                    ) : (
                      <span className="tabular-nums text-muted-foreground">0</span>
                    )}
                  </td>
                </tr>
              ))}
              {r.filasEquipos.length === 0 && (
                <tr>
                  <td colSpan={7} className="py-4 text-center text-xs text-muted-foreground">
                    Sin supervisores activos en el equipo
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          <p className="pt-3 text-[11px] text-muted-foreground">
            Los leads por repartir (parkeados en bandeja del supervisor) no suman al capital
            hasta tener vendedor asignado.
          </p>
        </CardContent>
      </Card>

      {/* Integridad de descartes + actividad reciente */}
      <div className="grid gap-5 lg:grid-cols-2">
        <Card>
          <SectionHead
            icon={ShieldCheck}
            title="Integridad de descartes"
            right={
              r.sinMotivo > 0 ? (
                <Badge color={ROJO} dot>{r.sinMotivo} sin motivo</Badge>
              ) : (
                <Badge color={AZUL} dot>100% con motivo</Badge>
              )
            }
          />
          <CardContent className="space-y-3">
            {r.descartados.length === 0 ? (
              <p className="py-4 text-center text-xs text-muted-foreground">
                No hay leads descartados en el histórico
              </p>
            ) : (
              <>
                {r.porMotivo.map((m) => {
                  const pct = Math.round((m.n / r.descartados.length) * 100)
                  return (
                    <div key={m.k}>
                      <div className="mb-1 flex items-baseline justify-between gap-2 text-sm">
                        <span className="text-foreground/85">{m.label}</span>
                        <span className="tabular-nums text-muted-foreground">
                          <span className="font-bold text-foreground">{m.n}</span> · {pct}%
                        </span>
                      </div>
                      <div className="h-2 overflow-hidden rounded-full bg-muted">
                        <div
                          className="h-full rounded-full transition-[width] duration-500 ease-out"
                          style={{ width: `${pct}%`, background: AMBAR }}
                        />
                      </div>
                    </div>
                  )
                })}
                {r.sinMotivo > 0 && (
                  <p className="rounded-lg border px-3 py-2 text-xs font-semibold" style={{ borderColor: `color-mix(in srgb, ${ROJO} 40%, transparent)`, color: ROJO }}>
                    {r.sinMotivo} {r.sinMotivo === 1 ? 'descarte' : 'descartes'} sin motivo
                    registrado — hallazgo de auditoría
                  </p>
                )}
                <p className="pt-1 text-[11px] text-muted-foreground">
                  {r.descartados.length} descartes en total — todo descarte debe llevar motivo
                  del catálogo.
                </p>
              </>
            )}
          </CardContent>
        </Card>

        <Card>
          <SectionHead
            icon={History}
            title="Actividad reciente"
            right={<span className="text-xs text-muted-foreground">Últimas 8 · toda la operación</span>}
          />
          <CardContent className="space-y-1">
            {r.recientes.length === 0 && (
              <p className="py-4 text-center text-xs text-muted-foreground">
                Aún no hay actividad registrada
              </p>
            )}
            {r.recientes.map((a) => {
              const Icono = ICONO_ACTIVIDAD[a.tipo]
              const lead = leadDe(a.lead_id)
              return (
                <button
                  key={a.id}
                  type="button"
                  onClick={() => abrirLead(a.lead_id)}
                  title="Abrir ficha (solo lectura)"
                  className="flex w-full cursor-pointer items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors hover:bg-muted"
                >
                  <span className="ac-chip grid size-8 shrink-0 place-items-center rounded-lg" style={{ '--c': a.tipo === 'conversion' ? NAVY : AZUL } as CSSProperties}>
                    <Icono className="size-4" />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-sm font-semibold">
                      {lead?.nombre_completo ?? 'Lead fuera del ámbito'}
                    </span>
                    <span className="block truncate text-[11.5px] text-muted-foreground">
                      {TIPOS_ACTIVIDAD[a.tipo]} · {a.autor_nombre}
                    </span>
                  </span>
                  <span className="shrink-0 text-[11px] tabular-nums text-muted-foreground">
                    {haceCorto(a.creado_en)}
                  </span>
                </button>
              )
            })}
          </CardContent>
        </Card>
      </div>

      <p className="text-[11px] text-muted-foreground">
        Auditoría del directorio — datos del ámbito global en modo solo lectura; toda
        mutación está vetada por rol (UX y RLS).
      </p>
    </div>
  )
}
